const std = @import("std");
const PlayerStore = @import("player_store.zig").PlayerStore;
const PlayerState = @import("player_store.zig").PlayerState;

test "concurrent read and write operations" {
    // Create test database
    const test_db = "test_concurrent.sqlite";

    // Clean up any existing test db
    std.fs.cwd().deleteFile(test_db) catch {};

    // Initialize schema (simplified migration)
    {
        const c = @cImport({
            @cInclude("sqlite3.h");
        });

        var db_ptr: ?*c.sqlite3 = null;
        try std.testing.expect(c.sqlite3_open(test_db, &db_ptr) == c.SQLITE_OK);
        const db = db_ptr.?;
        defer _ = c.sqlite3_close(db);

        const schema =
            \\CREATE TABLE player_state (
            \\  session_id INTEGER PRIMARY KEY,
            \\  x REAL NOT NULL,
            \\  y REAL NOT NULL,
            \\  updated_at INTEGER NOT NULL
            \\);
        ;
        try std.testing.expect(c.sqlite3_exec(db, schema, null, null, null) == c.SQLITE_OK);
        try std.testing.expect(c.sqlite3_exec(db, "PRAGMA journal_mode=WAL;", null, null, null) == c.SQLITE_OK);
    }

    // Initialize player store
    var store = try PlayerStore.init(test_db);
    defer store.deinit();

    // Start persist thread
    try store.startPersistThread();

    std.debug.print("\n=== Testing Concurrent Operations ===\n", .{});

    // Test 1: Queue some updates (main thread)
    std.debug.print("1. Queueing updates from main thread...\n", .{});
    for (1..11) |i| {
        store.queuePersist(@intCast(i), .{ .x = @floatFromInt(i * 10), .y = @floatFromInt(i * 20) });
    }
    std.debug.print("   ✓ Queued 10 updates\n", .{});

    // Test 2: Wait for persist thread to flush
    std.debug.print("2. Waiting for persist thread to flush...\n", .{});
    std.Thread.sleep(6 * std.time.ns_per_s);
    std.debug.print("   ✓ Flush completed\n", .{});

    // Test 3: Read while persist thread might be active
    std.debug.print("3. Reading player states (concurrent with persist thread)...\n", .{});
    for (1..11) |i| {
        const state = try store.loadPlayerState(@intCast(i));
        try std.testing.expect(state != null);
        try std.testing.expectApproxEqAbs(@as(f32, @floatFromInt(i * 10)), state.?.x, 0.01);
        try std.testing.expectApproxEqAbs(@as(f32, @floatFromInt(i * 20)), state.?.y, 0.01);
    }
    std.debug.print("   ✓ All reads successful and correct\n", .{});

    // Test 4: Concurrent queue + read
    std.debug.print("4. Testing concurrent queue and read...\n", .{});
    store.queuePersist(100, .{ .x = 1000.0, .y = 2000.0 });
    const old_state = try store.loadPlayerState(1);
    try std.testing.expect(old_state != null);
    std.debug.print("   ✓ Can queue and read simultaneously\n", .{});

    // Test 5: Wait for final flush
    std.debug.print("5. Waiting for final flush...\n", .{});
    std.Thread.sleep(6 * std.time.ns_per_s);
    const new_state = try store.loadPlayerState(100);
    try std.testing.expect(new_state != null);
    try std.testing.expectApproxEqAbs(@as(f32, 1000.0), new_state.?.x, 0.01);
    std.debug.print("   ✓ New entry persisted correctly\n", .{});

    std.debug.print("\n=== All Tests Passed ✓ ===\n\n", .{});

    // Cleanup
    std.fs.cwd().deleteFile(test_db) catch {};
    std.fs.cwd().deleteFile(test_db ++ "-wal") catch {};
    std.fs.cwd().deleteFile(test_db ++ "-shm") catch {};
}

test "queue overflow handling" {
    const test_db = "test_overflow.sqlite";
    std.fs.cwd().deleteFile(test_db) catch {};

    // Initialize schema
    {
        const c = @cImport({
            @cInclude("sqlite3.h");
        });

        var db_ptr: ?*c.sqlite3 = null;
        try std.testing.expect(c.sqlite3_open(test_db, &db_ptr) == c.SQLITE_OK);
        const db = db_ptr.?;
        defer _ = c.sqlite3_close(db);

        const schema =
            \\CREATE TABLE player_state (
            \\  session_id INTEGER PRIMARY KEY,
            \\  x REAL NOT NULL,
            \\  y REAL NOT NULL,
            \\  updated_at INTEGER NOT NULL
            \\);
        ;
        try std.testing.expect(c.sqlite3_exec(db, schema, null, null, null) == c.SQLITE_OK);
        try std.testing.expect(c.sqlite3_exec(db, "PRAGMA journal_mode=WAL;", null, null, null) == c.SQLITE_OK);
    }

    var store = try PlayerStore.init(test_db);
    defer store.deinit();

    // Don't start thread for this test (we're just testing queue)

    std.debug.print("\n=== Testing Queue Overflow ===\n", .{});

    // Fill queue beyond capacity (256 slots, we try 300)
    std.debug.print("Attempting to queue 300 entries (capacity: 255)...\n", .{});
    var queued: usize = 0;
    for (0..300) |i| {
        const before = store.write_index.load(.acquire);
        store.queuePersist(@intCast(i), .{ .x = @floatFromInt(i), .y = @floatFromInt(i) });
        const after = store.write_index.load(.acquire);
        if (after != before) {
            queued += 1;
        }
    }

    std.debug.print("Successfully queued: {d} entries\n", .{queued});
    try std.testing.expect(queued <= 255); // Max capacity - 1 (full check)
    std.debug.print("✓ Queue properly rejects overflow\n\n", .{});

    // Cleanup
    std.fs.cwd().deleteFile(test_db) catch {};
    std.fs.cwd().deleteFile(test_db ++ "-wal") catch {};
    std.fs.cwd().deleteFile(test_db ++ "-shm") catch {};
}
