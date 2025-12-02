const std = @import("std");
const wire_endian = std.builtin.Endian.big;

pub const MovementCommand = struct {
    direction: MoveDirection,
    speed: f32,
    delta: f32,
    const Self = @This();

    pub fn size() usize {
        return 1 + 4 + 4;
    }

    pub fn decode(buf: []const u8) !Self {
        if (buf.len < Self.size()) {
            return error.BufferTooSmall;
        }
        const dir = std.meta.intToEnum(MoveDirection, buf[0]) catch {
            return error.InvalidEnumValue;
        };

        return Self{ .direction = dir, .speed = readFloat(f32, buf[1..5], wire_endian), .delta = readFloat(f32, buf[5..], wire_endian) };
    }

    pub fn encode(self: Self, dest: []u8) ![]u8 {
        if (dest.len < Self.size()) {
            return error.BufferTooSmall;
        }
        const slice = dest[0..Self.size()];
        const dir = @intFromEnum(self.direction);
        dest[0] = dir;
        writeFloat(f32, slice[1..5], self.speed, wire_endian);
        writeFloat(f32, slice[5..], self.delta, wire_endian);
        return slice;
    }
};

fn writeFloat(comptime T: type, buf: []u8, value: T, endian: std.builtin.Endian) void {
    const Int = std.meta.Int(.unsigned, @bitSizeOf(T));
    const bits: Int = @bitCast(value);
    const arr_ptr = buf[0..@sizeOf(Int)];

    std.mem.writeInt(Int, arr_ptr, bits, endian);
}

fn readFloat(comptime T: type, buf: []const u8, endian: std.builtin.Endian) T {
    const Int = std.meta.Int(.unsigned, @bitSizeOf(T));

    // safety check
    std.debug.assert(buf.len >= @sizeOf(Int));

    // make a *[N]u8 for readInt
    const arr_ptr: *const [@sizeOf(Int)]u8 = buf[0..@sizeOf(Int)];

    const bits: Int = std.mem.readInt(Int, arr_ptr, endian);
    return @bitCast(bits);
}

pub const MoveDirection = enum {
    Up,
    Down,
    Left,
    Right,
};

test "encode MoveDirection" {
    const move = MovementCommand{
        .direction = .Left,
        .speed = 2.5,
        .delta = 0.1,
    };
    var payload: [MovementCommand.size()]u8 = undefined;
    const buf = move.encode(payload[0..]) catch |err| std.debug.panic("encode failed: {s}", .{@errorName(err)});
    const decoded = MovementCommand.decode(buf) catch |err| std.debug.panic("decode failed: {s}", .{@errorName(err)});

    try std.testing.expectEqual(move.direction, decoded.direction);
    try std.testing.expectEqual(move.speed, decoded.speed);
    try std.testing.expectEqual(move.delta, decoded.delta);
}
