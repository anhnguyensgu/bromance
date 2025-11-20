const std = @import("std");
const wire_endian = std.builtin.Endian.big;

pub const PingPayload = struct {
    timestamp: u64,
    const Self = @This();

    pub fn size() usize {
        return 8;
    }

    pub fn decode(buf: []const u8) !Self {
        if (buf.len < Self.size()) {
            return error.BufferTooSmall;
        }

        return Self{
            .timestamp = std.mem.readInt(u64, buf[0..8], wire_endian),
        };
    }

    pub fn encode(self: Self, dest: []u8) ![]u8 {
        if (dest.len < Self.size()) {
            return error.BufferTooSmall;
        }
        const slice = dest[0..Self.size()];
        std.mem.writeInt(u64, slice[0..8], self.timestamp, wire_endian);
        return slice;
    }
};
