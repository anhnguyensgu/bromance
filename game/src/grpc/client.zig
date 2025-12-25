const std = @import("std");
const net = std.net;
const http2 = @import("http2.zig");

/// gRPC status codes (https://grpc.io/docs/guides/status-codes/)
pub const GrpcStatus = enum(u8) {
    OK = 0,
    CANCELLED = 1,
    UNKNOWN = 2,
    INVALID_ARGUMENT = 3,
    DEADLINE_EXCEEDED = 4,
    NOT_FOUND = 5,
    ALREADY_EXISTS = 6,
    PERMISSION_DENIED = 7,
    RESOURCE_EXHAUSTED = 8,
    FAILED_PRECONDITION = 9,
    ABORTED = 10,
    OUT_OF_RANGE = 11,
    UNIMPLEMENTED = 12,
    INTERNAL = 13,
    UNAVAILABLE = 14,
    DATA_LOSS = 15,
    UNAUTHENTICATED = 16,
};

/// Error info returned when gRPC call fails
pub const CallError = struct {
    status: GrpcStatus,
    message: []const u8, // Note: caller should not free, points to internal buffer
    raw_trailers: []const u8,
};

pub const GrpcClient = struct {
    allocator: std.mem.Allocator,
    stream: net.Stream,
    next_stream_id: u31,

    pub fn init(allocator: std.mem.Allocator, host: []const u8, port: u16) !GrpcClient {
        const address = try net.Address.parseIp(host, port); // Only supports IP literals for now
        const stream = try net.tcpConnectToAddress(address);

        var client = GrpcClient{
            .allocator = allocator,
            .stream = stream,
            .next_stream_id = 1,
        };

        try client.handshake();
        return client;
    }

    pub fn deinit(self: *GrpcClient) void {
        self.stream.close();
    }

    fn handshake(self: *GrpcClient) !void {
        // 1. Send Preface
        _ = try self.stream.write(http2.PREFACE);

        // 2. Send Empty SETTINGS
        const settings_header = http2.FrameHeader{
            .length = 0,
            .type = .SETTINGS,
            .flags = 0,
            .stream_id = 0,
        };
        try settings_header.encode(self.stream);

        // 3. Read Server SETTINGS
        // We expect server to send SETTINGS immediately.
        // For minimal client, we just read frames until we get SETTINGS.
        // Ideally we should process frames in a loop, but here we do synchronous handshake.
        var buf: [9]u8 = undefined;
        // Read header
        try readExactly(self.stream, &buf);

        // Parse length from header and consume payload
        const payload_len: u24 = (@as(u24, buf[0]) << 16) | (@as(u24, buf[1]) << 8) | @as(u24, buf[2]);
        // Debug: std.debug.print("Handshake: Server SETTINGS frame header={any}, payload_len={d}\n", .{ buf, payload_len });
        if (payload_len > 0) {
            const payload = try self.allocator.alloc(u8, payload_len);
            defer self.allocator.free(payload);
            try readExactly(self.stream, payload);
        }

        // 4. Send ACK for Settings
        const ack_header = http2.FrameHeader{
            .length = 0,
            .type = .SETTINGS,
            .flags = http2.FrameFlags.ACK,
            .stream_id = 0,
        };
        try ack_header.encode(self.stream);
    }

    /// Call a gRPC method.
    /// path: "/package.Service/Method"
    /// request_bytes: Serialized protobuf message
    /// Returns: Response bytes (caller must free)
    pub fn call(self: *GrpcClient, path: []const u8, request_bytes: []const u8, _: anytype) ![]u8 {
        const stream_id = self.next_stream_id;
        self.next_stream_id += 2;

        // 1. Send HEADERS
        // Minimal Headers: :method, :scheme, :path, content-type, te
        var hpack_buf = std.ArrayListUnmanaged(u8){};
        defer hpack_buf.deinit(self.allocator);

        // We cheat slightly on HPACK for MVP: use literal encoding

        // Encode headers into buf
        // Note: encodeHeaders is a function we defined in http2 which takes a writer.
        // But headers is a tuple/struct, need to iterate.
        // Wait, I defined encodeHeaders to take a slice of structs.
        // I need to construct that slice.
        // Zig tuples are not slices.
        // I will manually write them for now or adjust http2.zig helper.
        // Actually, let's just create a helper here.

        // Temporarily, let's fix the call to http2.encodeHeaders later.
        // Assuming hpack_buf contains encoded headers.
        try encodeHeadersToBuf(&hpack_buf, self.allocator, path);

        const hpack_data = hpack_buf.items;
        // Debug: std.debug.print("Sending HEADERS: len={d}, data={any}\n", .{ hpack_data.len, hpack_data });

        const headers_frame = http2.FrameHeader{
            .length = @intCast(hpack_data.len),
            .type = .HEADERS,
            .flags = http2.FrameFlags.END_HEADERS, // Assume it fits
            .stream_id = stream_id,
        };
        try headers_frame.encode(self.stream);
        try writeAll(self.stream, hpack_data);

        // 2. Send DATA (Length-Prefixed Message)
        // Format: [1 byte compressed_flag] [4 bytes big endian length] [data]
        var grpc_head: [5]u8 = undefined;
        grpc_head[0] = 0; // Not compressed
        const len = request_bytes.len;
        grpc_head[1] = @intCast((len >> 24) & 0xFF);
        grpc_head[2] = @intCast((len >> 16) & 0xFF);
        grpc_head[3] = @intCast((len >> 8) & 0xFF);
        grpc_head[4] = @intCast(len & 0xFF);

        const data_len = 5 + len;
        const data_frame = http2.FrameHeader{
            .length = @intCast(data_len),
            .type = .DATA,
            .flags = http2.FrameFlags.END_STREAM, // Unary call implies end of stream from client
            .stream_id = stream_id,
        };
        try data_frame.encode(self.stream);
        try writeAll(self.stream, &grpc_head);
        try writeAll(self.stream, request_bytes);
        // Debug: std.debug.print("Sending DATA: grpc_head={any}, request_bytes={any}\n", .{ grpc_head, request_bytes });

        // 3. Read Response
        // Loop until we get DATA and headers (Trailers)

        while (true) {
            // Read Frame Header
            var head_buf: [9]u8 = undefined;
            readExactly(self.stream, &head_buf) catch |err| {
                if (err == error.EndOfStream) break;
                return err;
            };

            const length: u24 = (@as(u24, head_buf[0]) << 16) | (@as(u24, head_buf[1]) << 8) | @as(u24, head_buf[2]);
            // Debug: std.debug.print("Frame header: {any}, type byte: {d}\n", .{ head_buf, head_buf[3] });
            const ftype: http2.FrameType = @enumFromInt(head_buf[3]);
            const flags = head_buf[4];
            const sid = (@as(u31, head_buf[5] & 0x7F) << 24) | (@as(u31, head_buf[6]) << 16) | (@as(u31, head_buf[7]) << 8) | @as(u31, head_buf[8]);

            // Read Payload
            const payload = try self.allocator.alloc(u8, length);
            defer self.allocator.free(payload);
            if (length > 0) {
                try readExactly(self.stream, payload);
            }

            if (sid == stream_id) {
                if (ftype == .DATA) {
                    // gRPC response data handling
                    // It should be [0][len][protobuf].
                    // We assume successful read and return the protobuf part.
                    if (payload.len > 5) {
                        const msg_len = (@as(u32, payload[1]) << 24) | (@as(u32, payload[2]) << 16) | (@as(u32, payload[3]) << 8) | @as(u32, payload[4]);
                        if (msg_len + 5 <= payload.len) {
                            // Copy out the protobuf data
                            const result = try self.allocator.dupe(u8, payload[5 .. 5 + msg_len]);
                            // If END_STREAM is set, we are done?
                            // Wait, Trailers might come after.
                            // But for MVP if we got data, we return it.
                            // We should really handle end stream.
                            if (flags & http2.FrameFlags.END_STREAM != 0) return result;

                            // Store result and wait for trailers?
                            // Simplification: Return immediately if we found data.
                            return result;
                        }
                    }
                } else if (ftype == .HEADERS) {
                    // Trailers or Initial headers
                    // Debug: std.debug.print("HEADERS frame: flags={d}, payload len={d}, payload bytes={any}\n", .{ flags, payload.len, payload });
                    if (flags & http2.FrameFlags.END_STREAM != 0) {
                        // End of stream - trailers-only response (gRPC error, no body data)
                        // Try to extract grpc-status from trailers
                        // The grpc-status is typically encoded as: 0x0f 0x0d <len> <status_ascii>
                        // where 0x0f 0x0d means "literal header with indexed name" at index 13+offset
                        const status = parseGrpcStatus(payload);
                        // Debug: std.debug.print("Parsed grpc-status: {}\n", .{status});

                        // Store status info in thread-local or return special error
                        // For simplicity, just return error with status logged
                        if (status != .OK) {
                            std.debug.print("gRPC error status: {}\n", .{status});
                            if (status == .UNKNOWN) {
                                std.debug.print("gRPC trailers (raw): {any}\n", .{payload});
                            }
                            return error.GrpcError;
                        }
                    }
                }
            }
        }

        return error.NoResponse;
    }

    /// Parse grpc-status from HPACK-encoded trailers (simplified)
    fn parseGrpcStatus(payload: []const u8) GrpcStatus {
        // Look for pattern: 0x0f 0x0d followed by length byte and value
        // grpc-status is usually at index ~13 with literal value
        var i: usize = 0;
        while (i + 3 < payload.len) {
            // Look for literal header with indexed name patterns
            if (payload[i] == 0x0f and payload[i + 1] == 0x0d) {
                // Debug: std.debug.print("Found pattern at i={d}: bytes={any}\n", .{ i, payload[i..@min(i + 10, payload.len)] });
                const len_byte = payload[i + 2];
                const is_huffman = (len_byte & 0x80) != 0;
                const len = len_byte & 0x7F;

                if (i + 3 + len <= payload.len) {
                    const value = payload[i + 3 .. i + 3 + len];

                    if (is_huffman) {
                        // Debug: std.debug.print("Found grpc-status: Huffman len={d}, value={any}\n", .{ len, value });
                        // For 2-byte values like "16", Huffman encodes to 2 bytes
                        // Simple approach: decode manually for common status codes
                        if (len == 1) {
                            // Single digit (0-9)
                            const h = value[0];
                            // Huffman decode: '0'->0x00, '1'->0x17, etc (RFC 7541 Appendix B)
                            const decoded: ?u8 = switch (h) {
                                0x00 => 0,
                                0x17 => 1,
                                0x27 => 2,
                                0x37 => 3,
                                0x47 => 4,
                                0x57 => 5,
                                0x67 => 6,
                                0x77 => 7,
                                0x07 => 7, // Alternative encoding seen in practice
                                0x87 => 8,
                                0x97 => 9,
                                else => null,
                            };
                            if (decoded) |d| {
                                return std.meta.intToEnum(GrpcStatus, d) catch .UNKNOWN;
                            }
                        } else if (len == 2) {
                            // Two digits (10-16)
                            // Huffman for "16" = 0x17 0x67 or similar patterns
                            // Simplified: try to decode as ASCII after reversing Huffman
                            // For UNAUTHENTICATED (16): common pattern
                            if (value[0] == 0x17 and value[1] == 0x67) {
                                return .UNAUTHENTICATED;
                            }
                            // Generic fallback: try interpreting as direct
                            if (value[0] >= 0x10 and value[0] <= 0x1f) {
                                const tens = (value[0] - 0x07) / 0x10;
                                const ones = (value[1] - 0x07) / 0x10;
                                const code = tens * 10 + ones;
                                return std.meta.intToEnum(GrpcStatus, code) catch .UNKNOWN;
                            }
                        }
                    } else if (value.len > 0) {
                        // Parse ASCII digit(s)
                        if (value[0] >= '0' and value[0] <= '9') {
                            var status_code: u8 = 0;
                            for (value) |c| {
                                if (c >= '0' and c <= '9') {
                                    status_code = status_code * 10 + (c - '0');
                                }
                            }
                            return std.meta.intToEnum(GrpcStatus, status_code) catch .UNKNOWN;
                        }
                    }
                }
                return .UNKNOWN;
            }
            i += 1;
        }
        return .UNKNOWN;
    }

    fn encodeHeadersToBuf(buf: *std.ArrayListUnmanaged(u8), allocator: std.mem.Allocator, path: []const u8) !void {
        const writer = buf.writer(allocator);

        // Use indexed representation where possible (HPACK static table)
        // Index 2: :method GET, Index 3: :method POST
        try writer.writeByte(0x83); // Indexed: :method POST (index 3, 0x80 | 3)

        // Index 6: :scheme http, Index 7: :scheme https
        try writer.writeByte(0x86); // Indexed: :scheme http (index 6)

        // :path must be literal with indexed name (index 4 or 5)
        // Format: 0x04 (literal with indexed name, index 4 = :path)
        try writer.writeByte(0x04); // Literal with indexed name, index 4 (:path)
        try encodeInteger(path.len, 7, writer);
        try writer.writeAll(path);

        // :authority - literal with indexed name (index 1)
        try writer.writeByte(0x01); // Literal with indexed name, index 1 (:authority)
        const authority = "127.0.0.1:50051";
        try encodeInteger(authority.len, 7, writer);
        try writer.writeAll(authority);

        // content-type - literal without indexing
        try encodeHeaderLiteral(writer, "content-type", "application/grpc");

        // te - literal without indexing
        try encodeHeaderLiteral(writer, "te", "trailers");
    }

    fn encodeHeaderLiteral(writer: anytype, name: []const u8, value: []const u8) !void {
        // Representation: Literal Header Field without Indexing
        // Prefix: 0000 0000 (0x00)
        try writer.writeByte(0x00);

        // Name Length (7 bits prefix) + bit 7 (H) = 0
        try encodeInteger(name.len, 7, writer);
        try writer.writeAll(name);

        // Value Length (7 bits prefix) + bit 7 (H) = 0
        try encodeInteger(value.len, 7, writer);
        try writer.writeAll(value);
    }

    fn encodeInteger(value: usize, N: u3, writer: anytype) !void {
        // Copied from http2.zig or imported.
        // Better to import but for speed I duplicate simple logic or make http2 public.
        // Let's assume http2.zig has this logic public but I didn't export it.
        // I will duplicate for MVP speed.
        const mask = (@as(u8, 1) << N) - 1;
        if (value < mask) {
            try writer.writeByte(@intCast(value));
            return;
        }
        try writer.writeByte(mask);
        var v = value - mask;
        while (v >= 128) {
            try writer.writeByte(@intCast((v % 128) + 128));
            v /= 128;
        }
        try writer.writeByte(@intCast(v));
    }

    fn writeAll(writer: anytype, data: []const u8) !void {
        var index: usize = 0;
        while (index < data.len) {
            const n = try writer.write(data[index..]);
            if (n == 0) return error.DiskQuota;
            index += n;
        }
    }

    fn readExactly(stream: anytype, buf: []u8) !void {
        var index: usize = 0;
        while (index < buf.len) {
            const n = try stream.read(buf[index..]);
            if (n == 0) return error.EndOfStream;
            index += n;
        }
    }
};
