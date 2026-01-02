const std = @import("std");
const migrations = @import("db/migrations.zig");

const DB_PATH: [:0]const u8 = "data/player_state.sqlite";

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        printUsage();
        return;
    }

    const command = args[1];

    if (std.mem.eql(u8, command, "up")) {
        std.debug.print("Running migrations...\n", .{});
        try migrations.migrate(DB_PATH);
    } else if (std.mem.eql(u8, command, "status")) {
        try migrations.status(DB_PATH);
    } else {
        std.debug.print("Unknown command: {s}\n", .{command});
        printUsage();
        std.process.exit(1);
    }
}

fn printUsage() void {
    std.debug.print(
        \\Usage: zig-migrate <command>
        \\
        \\Commands:
        \\  up      Run all pending migrations
        \\  status  Show current migration status
        \\
        \\Examples:
        \\  zig-migrate up       # Apply all pending migrations
        \\  zig-migrate status   # Check which migrations have been applied
        \\
    , .{});
}
