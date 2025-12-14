const std = @import("std");
const mem = std.mem;

pub const PREFACE = "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n";

pub const FrameType = enum(u8) {
    DATA = 0x0,
    HEADERS = 0x1,
    PRIORITY = 0x2,
    RST_STREAM = 0x3,
    SETTINGS = 0x4,
    PUSH_PROMISE = 0x5,
    PING = 0x6,
    GOAWAY = 0x7,
    WINDOW_UPDATE = 0x8,
    CONTINUATION = 0x9,
};

pub const FrameFlags = struct {
    pub const END_STREAM: u8 = 0x1;
    pub const END_HEADERS: u8 = 0x4;
    pub const PADDED: u8 = 0x8;
    pub const PRIORITY: u8 = 0x20;
    pub const ACK: u8 = 0x1; // For SETTINGS and PING
};

pub const FrameHeader = struct {
    length: u24,
    type: FrameType,
    flags: u8,
    stream_id: u31,

    pub fn encode(self: FrameHeader, writer: anytype) !void {
        var buf: [9]u8 = undefined;
        // Length (24 bits)
        buf[0] = @intCast((self.length >> 16) & 0xFF);
        buf[1] = @intCast((self.length >> 8) & 0xFF);
        buf[2] = @intCast(self.length & 0xFF);
        // Type (8 bits)
        buf[3] = @intFromEnum(self.type);
        // Flags (8 bits)
        buf[4] = self.flags;
        // Stream ID (31 bits) - Ignore R bit for now
        buf[5] = @intCast((self.stream_id >> 24) & 0x7F); // Mask R bit
        buf[6] = @intCast((self.stream_id >> 16) & 0xFF);
        buf[7] = @intCast((self.stream_id >> 8) & 0xFF);
        buf[8] = @intCast(self.stream_id & 0xFF);

        _ = try writer.write(&buf);
    }
};

/// Minimal HPACK encoder (Literal Header Field never Indexed)
/// Format: 0001xxxx (Index) -> we use Literal Header Field without Indexing (0000xxxx)?
/// Actually, Literal Header Field without Indexing starts with '0000'.
/// 4-bit prefix.
/// If we handle new name, it is '00000000' followed by name string and value string.
pub fn encodeHeaders(headers: []const struct { []const u8, []const u8 }, writer: anytype) !void {
    for (headers) |header| {
        const name = header[0];
        const value = header[1];

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
}

fn encodeInteger(value: usize, N: u3, writer: anytype) !void {
    // Basic integer encoding for HPACK
    // Since N is 7 for strings usually...
    // If value < 2^N - 1, write it
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
