const std = @import("std");
const shared = @import("shared");

pub fn main() !void {
    std.debug.print("Server starting with protocol_version {d}...\n", .{shared.protocol_version});
}
