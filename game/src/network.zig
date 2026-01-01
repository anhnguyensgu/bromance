const std = @import("std");
const wire_endian = std.builtin.Endian.big;

pub const MovePayload = @import("movement/command.zig").MovementCommand;
pub const PingPayload = @import("ping/command.zig").PingPayload;

pub const protocol_version: u8 = 1;
pub const packet_magic = [2]u8{ 0xAB, 0xCD };
pub const packet_header_size: usize = 19;
pub const max_payload_size: usize = 2048;

pub const PacketType = enum(u8) {
    ping = 1,
    move = 2,
    state_update = 3,
    all_players_state = 4,
    leave = 5,
    plots_sync = 6,
};

pub const StatePayload = struct {
    x: f32,
    y: f32,
    timestamp_ns: i64,

    pub fn size() usize {
        return 16;
    }

    pub fn encode(self: StatePayload, dest: []u8) ![]u8 {
        if (dest.len < size()) return error.BufferTooSmall;
        const slice = dest[0..size()];
        std.mem.writeInt(u32, slice[0..4], @as(u32, @bitCast(self.x)), wire_endian);
        std.mem.writeInt(u32, slice[4..8], @as(u32, @bitCast(self.y)), wire_endian);
        std.mem.writeInt(i64, slice[8..16], self.timestamp_ns, wire_endian);
        return slice;
    }

    pub fn decode(buf: []const u8) !StatePayload {
        if (buf.len < size()) return error.BufferTooSmall;
        return .{
            .x = @as(f32, @bitCast(std.mem.readInt(u32, buf[0..4], wire_endian))),
            .y = @as(f32, @bitCast(std.mem.readInt(u32, buf[4..8], wire_endian))),
            .timestamp_ns = std.mem.readInt(i64, buf[8..16], wire_endian),
        };
    }
};

pub const PlayerInfo = struct {
    session_id: u32,
    x: f32,
    y: f32,

    pub fn size() usize {
        return 12; // 4 + 4 + 4
    }

    pub fn encode(self: PlayerInfo, dest: []u8) ![]u8 {
        if (dest.len < size()) return error.BufferTooSmall;
        const slice = dest[0..size()];
        std.mem.writeInt(u32, slice[0..4], self.session_id, wire_endian);
        std.mem.writeInt(u32, slice[4..8], @as(u32, @bitCast(self.x)), wire_endian);
        std.mem.writeInt(u32, slice[8..12], @as(u32, @bitCast(self.y)), wire_endian);
        return slice;
    }

    pub fn decode(buf: []const u8) !PlayerInfo {
        if (buf.len < size()) return error.BufferTooSmall;
        return .{
            .session_id = std.mem.readInt(u32, buf[0..4], wire_endian),
            .x = @as(f32, @bitCast(std.mem.readInt(u32, buf[4..8], wire_endian))),
            .y = @as(f32, @bitCast(std.mem.readInt(u32, buf[8..12], wire_endian))),
        };
    }
};

pub const MAX_PLAYERS: usize = 16;

pub const AllPlayersPayload = struct {
    count: u8,
    players: [MAX_PLAYERS]PlayerInfo,

    pub fn size() usize {
        return 1 + (PlayerInfo.size() * MAX_PLAYERS); // count + players array
    }

    pub fn encode(self: AllPlayersPayload, dest: []u8) ![]u8 {
        if (dest.len < size()) return error.BufferTooSmall;
        const slice = dest[0..size()];
        slice[0] = self.count;
        var offset: usize = 1;
        for (self.players[0..self.count]) |player| {
            _ = try player.encode(slice[offset..]);
            offset += PlayerInfo.size();
        }
        return slice;
    }

    pub fn decode(buf: []const u8) !AllPlayersPayload {
        if (buf.len < size()) return error.BufferTooSmall;
        var result: AllPlayersPayload = undefined;
        result.count = buf[0];
        var offset: usize = 1;
        for (0..result.count) |i| {
            result.players[i] = try PlayerInfo.decode(buf[offset..]);
            offset += PlayerInfo.size();
        }
        return result;
    }
};

pub const LeavePayload = struct {
    reason: u8,

    pub fn size() usize {
        return 1;
    }

    pub fn encode(self: LeavePayload, dest: []u8) ![]u8 {
        if (dest.len < size()) return error.BufferTooSmall;
        dest[0] = self.reason;
        return dest[0..size()];
    }

    pub fn decode(buf: []const u8) !LeavePayload {
        if (buf.len < size()) return error.BufferTooSmall;
        return .{ .reason = buf[0] };
    }
};

pub const MAX_PLOTS: usize = 32;

pub const PlotData = struct {
    id: u64,
    tile_x: i32,
    tile_y: i32,
    width_tiles: i32,
    height_tiles: i32,
    owner_kind: u8,
    owner_len: u8,
    owner_value: [64]u8,

    pub fn size() usize {
        return 8 + 4 + 4 + 4 + 4 + 1 + 1 + 64;
    }

    pub fn encode(self: PlotData, dest: []u8) ![]u8 {
        if (dest.len < size()) return error.BufferTooSmall;
        const slice = dest[0..size()];
        std.mem.writeInt(u64, slice[0..8], self.id, wire_endian);
        std.mem.writeInt(i32, slice[8..12], self.tile_x, wire_endian);
        std.mem.writeInt(i32, slice[12..16], self.tile_y, wire_endian);
        std.mem.writeInt(i32, slice[16..20], self.width_tiles, wire_endian);
        std.mem.writeInt(i32, slice[20..24], self.height_tiles, wire_endian);
        slice[24] = self.owner_kind;
        slice[25] = self.owner_len;
        @memcpy(slice[26..90], &self.owner_value);
        return slice;
    }

    pub fn decode(buf: []const u8) !PlotData {
        if (buf.len < size()) return error.BufferTooSmall;
        var owner_value: [64]u8 = undefined;
        @memcpy(&owner_value, buf[26..90]);
        return .{
            .id = std.mem.readInt(u64, buf[0..8], wire_endian),
            .tile_x = std.mem.readInt(i32, buf[8..12], wire_endian),
            .tile_y = std.mem.readInt(i32, buf[12..16], wire_endian),
            .width_tiles = std.mem.readInt(i32, buf[16..20], wire_endian),
            .height_tiles = std.mem.readInt(i32, buf[20..24], wire_endian),
            .owner_kind = buf[24],
            .owner_len = buf[25],
            .owner_value = owner_value,
        };
    }
};

pub const PlotsSyncPayload = struct {
    count: u8,
    plots: [MAX_PLOTS]PlotData,

    pub fn size() usize {
        return 1 + (MAX_PLOTS * PlotData.size());
    }

    pub fn encode(self: PlotsSyncPayload, dest: []u8) ![]u8 {
        const total_size = 1 + (@as(usize, self.count) * PlotData.size());
        if (dest.len < total_size) return error.BufferTooSmall;
        dest[0] = self.count;
        var offset: usize = 1;
        for (0..self.count) |i| {
            _ = try self.plots[i].encode(dest[offset..]);
            offset += PlotData.size();
        }
        return dest[0..total_size];
    }

    pub fn decode(buf: []const u8) !PlotsSyncPayload {
        if (buf.len < 1) return error.BufferTooSmall;
        var result: PlotsSyncPayload = undefined;
        result.count = buf[0];
        var offset: usize = 1;
        for (0..result.count) |i| {
            result.plots[i] = try PlotData.decode(buf[offset..]);
            offset += PlotData.size();
        }
        return result;
    }
};

pub const PacketPayload = union(PacketType) {
    ping: PingPayload,
    move: MovePayload,
    state_update: StatePayload,
    all_players_state: AllPlayersPayload,
    leave: LeavePayload,
    plots_sync: PlotsSyncPayload,
    const Self = @This();

    pub fn decodePayload(header: *const PacketHeader, payload: []const u8) !Self {
        switch (header.msg_type) {
            .ping => return .{ .ping = try decodeGenericPayload(PingPayload, payload) },
            .move => return .{ .move = try decodeGenericPayload(MovePayload, payload) },
            .state_update => return .{ .state_update = try decodeGenericPayload(StatePayload, payload) },
            .all_players_state => return .{ .all_players_state = try decodeGenericPayload(AllPlayersPayload, payload) },
            .leave => return .{ .leave = try decodeGenericPayload(LeavePayload, payload) },
            .plots_sync => return .{ .plots_sync = try decodeGenericPayload(PlotsSyncPayload, payload) },
        }
    }

    pub fn encodePayload(self: Self) ![]u8 {
        switch (self) {
            .ping => |b| return try encodeGenericPayload(PingPayload, b),
            .move => |b| return try encodeGenericPayload(MovePayload, b),
            .state_update => |b| return try encodeGenericPayload(StatePayload, b),
            .all_players_state => |b| return try encodeGenericPayload(AllPlayersPayload, b),
            .leave => |b| return try encodeGenericPayload(LeavePayload, b),
        }
    }
};

pub fn decodeGenericPayload(comptime T: type, payload: []const u8) !T {
    // 1. COMPTIME CHECK: Ensure the type T has the required static method.
    // This check runs at compile time, so there is no runtime overhead.
    comptime {
        if (!@hasDecl(T, "decode")) {
            // This stops compilation if a type without 'decode' is used.
            @compileError("Type '" ++ @typeName(T) ++ "' does not provide a static 'decode' function for decoding.");
        }
    }

    // 2. RUNTIME CALL: Since the compiler has validated the interface,
    // we can safely call the static 'decode' function on the type T.
    return T.decode(payload);
}

pub fn encodeGenericPayload(comptime T: type, payload: T) ![]u8 {
    comptime {
        if (!@hasDecl(T, "encode")) {
            // This stops compilation if a type without 'decode' is used.
            @compileError("Type '" ++ @typeName(T) ++ "' does not provide a static 'encode' function for encoding.");
        }

        if (!@hasDecl(T, "size")) {
            // This stops compilation if a type without 'decode' is used.
            @compileError("Type '" ++ @typeName(T) ++ "' does not provide a static 'size' function for encoding.");
        }
    }

    // 2. RUNTIME CALL: Since the compiler has validated the interface,
    // we can safely call the static 'decode' function on the type T.
    var des: [T.size()]u8 = undefined;
    return payload.encode(des[0..]);
}

pub const PacketFlags = struct {
    reliable: bool = false,
    requires_ack: bool = false,
    fragmented: bool = false,
    reserved: u5 = 0,

    pub fn toByte(self: PacketFlags) u8 {
        var bits: u8 = 0;
        if (self.reliable) bits |= 0b0000_0001;
        if (self.requires_ack) bits |= 0b0000_0010;
        if (self.fragmented) bits |= 0b0000_0100;
        bits |= @as(u8, self.reserved) << 3;
        return bits;
    }

    pub fn fromByte(byte: u8) PacketFlags {
        return .{
            .reliable = (byte & 0b0000_0001) != 0,
            .requires_ack = (byte & 0b0000_0010) != 0,
            .fragmented = (byte & 0b0000_0100) != 0,
            .reserved = @as(u5, @truncate(byte >> 3)),
        };
    }
};

pub const PacketHeader = struct {
    magic: [2]u8 = packet_magic,
    version: u8 = protocol_version,
    msg_type: PacketType,
    flags: PacketFlags = .{},
    session_id: u32 = 0,
    sequence: u32 = 0,
    ack: u32 = 0,
    payload_len: u16 = 0,

    pub const Error = error{
        BufferTooSmall,
        InvalidMagic,
        UnsupportedVersion,
        UnknownPacketType,
    };

    pub fn encode(self: PacketHeader, buffer: []u8) !void {
        if (buffer.len < packet_header_size) {
            return error.BufferTooSmall;
        }

        buffer[0] = self.magic[0];
        buffer[1] = self.magic[1];
        buffer[2] = self.version;
        buffer[3] = @intFromEnum(self.msg_type);
        buffer[4] = self.flags.toByte();
        std.mem.writeInt(u32, buffer[5..9], self.session_id, wire_endian);
        std.mem.writeInt(u32, buffer[9..13], self.sequence, wire_endian);
        std.mem.writeInt(u32, buffer[13..17], self.ack, wire_endian);
        std.mem.writeInt(u16, buffer[17..packet_header_size], self.payload_len, wire_endian);
    }

    pub fn decode(buffer: []const u8) Error!PacketHeader {
        if (buffer.len < packet_header_size) {
            return error.BufferTooSmall;
        }
        if (buffer[0] != packet_magic[0] or buffer[1] != packet_magic[1]) {
            return error.InvalidMagic;
        }

        const version = buffer[2];
        if (version != protocol_version) {
            return error.UnsupportedVersion;
        }

        const msg_type = std.meta.intToEnum(PacketType, buffer[3]) catch {
            return error.UnknownPacketType;
        };

        return .{
            .magic = packet_magic,
            .version = version,
            .msg_type = msg_type,
            .flags = PacketFlags.fromByte(buffer[4]),
            .session_id = std.mem.readInt(u32, buffer[5..9], wire_endian),
            .sequence = std.mem.readInt(u32, buffer[9..13], wire_endian),
            .ack = std.mem.readInt(u32, buffer[13..17], wire_endian),
            .payload_len = std.mem.readInt(u16, buffer[17..19], wire_endian),
        };
    }
};

pub const Packet = struct {
    header: PacketHeader,
    payload: PacketPayload,

    pub fn encode(self: Packet, buffer: []u8) !void {
        if (buffer.len < packet_header_size + self.header.payload_len) {
            return error.BufferTooSmall;
        }

        _ = try self.header.encode(buffer[0..packet_header_size]);
        const body_slice = buffer[packet_header_size .. packet_header_size + self.header.payload_len];

        switch (self.payload) {
            .ping => |payload_ping| {
                var tmp: [PingPayload.size()]u8 = undefined;
                const encoded = try payload_ping.encode(&tmp);
                std.mem.copyForwards(u8, body_slice, encoded);
            },
            .move => |payload_move| {
                var tmp: [MovePayload.size()]u8 = undefined;
                const encoded = try payload_move.encode(&tmp);
                std.mem.copyForwards(u8, body_slice, encoded);
            },
            .state_update => |payload_state| {
                var tmp: [StatePayload.size()]u8 = undefined;
                const encoded = try payload_state.encode(&tmp);
                std.mem.copyForwards(u8, body_slice, encoded);
            },
            .all_players_state => |payload_players| {
                var tmp: [AllPlayersPayload.size()]u8 = undefined;
                const encoded = try payload_players.encode(&tmp);
                std.mem.copyForwards(u8, body_slice, encoded);
            },
            .leave => |payload_leave| {
                var tmp: [LeavePayload.size()]u8 = undefined;
                const encoded = try payload_leave.encode(&tmp);
                std.mem.copyForwards(u8, body_slice, encoded);
            },
            .plots_sync => |payload_plots| {
                var tmp: [PlotsSyncPayload.size()]u8 = undefined;
                const encoded = try payload_plots.encode(&tmp);
                std.mem.copyForwards(u8, body_slice, encoded);
            },
        }
    }

    pub fn decode(buffer: []const u8) !Packet {
        const header = try PacketHeader.decode(buffer[0..packet_header_size]);
        const payload_len: usize = header.payload_len;
        const payload_slice = buffer[packet_header_size .. packet_header_size + payload_len];
        const payload = try PacketPayload.decodePayload(&header, payload_slice);
        return .{
            .header = header,
            .payload = payload,
        };
    }
};

test "packet flags convert to/from byte" {
    const flags = PacketFlags{
        .reliable = true,
        .requires_ack = true,
        .fragmented = false,
        .reserved = 0b10101,
    };

    const byte = flags.toByte();
    try std.testing.expectEqual(@as(u8, 0b1010_1011), byte);
    const roundtrip = PacketFlags.fromByte(byte);
    try std.testing.expectEqual(flags.reliable, roundtrip.reliable);
    try std.testing.expectEqual(flags.requires_ack, roundtrip.requires_ack);
    try std.testing.expectEqual(flags.fragmented, roundtrip.fragmented);
    try std.testing.expectEqual(flags.reserved, roundtrip.reserved);
}
test "packet header encodes and decodes the wire layout" {
    try expectHeaderRoundTrip(.{
        .msg_type = .move,
        .flags = .{ .reliable = true, .requires_ack = true },
        .session_id = 0x01020304,
        .sequence = 0x0A0B0C0D,
        .ack = 0x0E0F1011,
        .payload_len = 512,
    });
}

test "packet ping encodes and decodes the wire layout" {
    const now = @as(u64, @intCast(std.time.timestamp()));
    var buffer: [packet_header_size + PingPayload.size()]u8 = undefined;
    const header = PacketHeader{
        .msg_type = .ping,
        .flags = .{ .reliable = true, .requires_ack = true },
        .session_id = 0x01020304,
        .sequence = 0x0A0B0C0D,
        .ack = 0x0E0F1011,
        .payload_len = @intCast(PingPayload.size()),
    };
    const payload = PacketPayload{ .ping = PingPayload{ .timestamp = now } };
    const packet = Packet{ .header = header, .payload = payload };
    try packet.encode(buffer[0..]);

    try expectMagicVersion(buffer[0..packet_header_size]);
    const decoded_payload = try PacketPayload.decodePayload(&header, buffer[packet_header_size .. packet_header_size + header.payload_len]);
    try std.testing.expectEqual(now, decoded_payload.ping.timestamp);
    try expectHeaderRoundTrip(header);
}

test "packet move payload round trips through PacketPayload union" {
    var buffer: [packet_header_size + MovePayload.size()]u8 = undefined;
    const header = PacketHeader{
        .msg_type = .move,
        .flags = .{ .reliable = true },
        .session_id = 0x11121314,
        .sequence = 77,
        .ack = 50,
        .payload_len = @intCast(MovePayload.size()),
    };

    const move = MovePayload{
        .direction = .Right,
        .speed = 4.5,
        .delta = 0.25,
    };

    const payload = PacketPayload{ .move = move };
    const p = Packet{
        .header = header,
        .payload = payload,
    };
    try p.encode(buffer[0..]);

    try expectMagicVersion(buffer[0..packet_header_size]);

    const decoded_payload = try PacketPayload.decodePayload(&header, buffer[packet_header_size .. packet_header_size + header.payload_len]);
    try std.testing.expectEqual(move.direction, decoded_payload.move.direction);
    try std.testing.expectEqual(move.speed, decoded_payload.move.speed);
    try std.testing.expectEqual(move.delta, decoded_payload.move.delta);
    try expectHeaderRoundTrip(header);
}

test "packet state payload encodes and decodes" {
    const payload = StatePayload{ .x = 10.5, .y = -4.25, .timestamp_ns = 123 };
    var buf: [StatePayload.size()]u8 = undefined;
    const encoded = try payload.encode(&buf);
    const decoded = try StatePayload.decode(encoded);
    try std.testing.expectEqual(payload.x, decoded.x);
    try std.testing.expectEqual(payload.y, decoded.y);
    try std.testing.expectEqual(payload.timestamp_ns, decoded.timestamp_ns);
}

fn expectHeaderRoundTrip(header: PacketHeader) !void {
    var buf: [packet_header_size]u8 = undefined;
    try header.encode(buf[0..]);
    try expectMagicVersion(buf[0..]);
    const decoded = try PacketHeader.decode(buf[0..]);
    try std.testing.expectEqual(header.msg_type, decoded.msg_type);
    try std.testing.expectEqual(header.flags.toByte(), decoded.flags.toByte());
    try std.testing.expectEqual(header.session_id, decoded.session_id);
    try std.testing.expectEqual(header.sequence, decoded.sequence);
    try std.testing.expectEqual(header.ack, decoded.ack);
    try std.testing.expectEqual(header.payload_len, decoded.payload_len);
}

fn expectMagicVersion(buf: []const u8) !void {
    try std.testing.expectEqual(packet_magic[0], buf[0]);
    try std.testing.expectEqual(packet_magic[1], buf[1]);
    try std.testing.expectEqual(@as(u8, protocol_version), buf[2]);
}
