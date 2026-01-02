# Testing Guide

## Running Tests

### Player Store Tests

Test the lock-free persistence system with per-thread database connections.

```bash
# Run all tests
zig test src/db/player_store_test.zig -lc -lsqlite3

# Run specific tests
zig test src/db/player_store_test.zig -lc -lsqlite3 --test-filter "concurrent"
zig test src/db/player_store_test.zig -lc -lsqlite3 --test-filter "overflow"
```

### Test Coverage

**1. Concurrent Read and Write Operations**
- Tests lock-free queue with background persist thread
- Verifies concurrent reads during writes (WAL mode)
- Validates data integrity across thread boundaries
- Confirms acquire/release semantics work correctly

**2. Queue Overflow Handling**
- Tests capacity limits (255 entries)
- Verifies graceful degradation (silently drops)
- Checks atomic index wraparound

### Expected Output

**Concurrent test:**
```
=== Testing Concurrent Operations ===
1. Queueing updates from main thread...
   ✓ Queued 10 updates
2. Waiting for persist thread to flush...
Persisted 10 player state(s) to database (lock-free + per-thread connections)
   ✓ Flush completed
3. Reading player states (concurrent with persist thread)...
   ✓ All reads successful and correct
4. Testing concurrent queue and read...
   ✓ Can queue and read simultaneously
5. Waiting for final flush...
Persisted 1 player state(s) to database (lock-free + per-thread connections)
   ✓ New entry persisted correctly

=== All Tests Passed ✓ ===
```

**Overflow test:**
```
=== Testing Queue Overflow ===
Attempting to queue 300 entries (capacity: 255)...
Successfully queued: 255 entries
✓ Queue properly rejects overflow
```

## Test Architecture

### Thread Model

```
Test Thread                    Persist Thread (spawned)
───────────                    ────────────────────────

1. Init store
2. startPersistThread() ────→  Spawned
3. queuePersist() ──────────→  (queue)
4. Sleep 6s                         ↓
                              flushPendingSync()
                              sqlite3_exec(persist_db)
5. loadPlayerState() ←───────  (concurrent!)
   sqlite3_step(main_db)
```

### Database Setup

Each test creates its own temporary database:
- `test_concurrent.sqlite` (concurrent test)
- `test_overflow.sqlite` (overflow test)

Schema created inline (no migration dependency):
```sql
CREATE TABLE player_state (
  session_id INTEGER PRIMARY KEY,
  x REAL NOT NULL,
  y REAL NOT NULL,
  updated_at INTEGER NOT NULL
);
PRAGMA journal_mode=WAL;
```

### Cleanup

Tests automatically clean up:
```zig
defer {
    std.fs.cwd().deleteFile(test_db) catch {};
    std.fs.cwd().deleteFile(test_db ++ "-wal") catch {};
    std.fs.cwd().deleteFile(test_db ++ "-shm") catch {};
}
```

## Important Changes

### Thread Lifecycle

**Before (buggy):**
```zig
pub fn init(...) !Self {
    var store = Self{ ... };
    store.persist_thread = std.Thread.spawn(..., &store) catch null;
    //                                              ^^^^^^
    // BUG: Pointer to local variable!
    return store; // Move invalidates pointer
}
```

**After (fixed):**
```zig
pub fn init(...) !Self {
    return Self{ ... }; // Return without thread
}

pub fn startPersistThread(self: *Self) !void {
    self.persist_thread = try std.Thread.spawn(..., self);
    //                                              ^^^^
    // CORRECT: Pointer to caller's memory
}
```

**Usage:**
```zig
var store = try PlayerStore.init(db_path);
try store.startPersistThread(); // Start after init returns
defer store.deinit();
```

### Why This Matters

The issue was:
1. `init()` creates local var `store` on stack
2. `spawn()` gets pointer `&store` → points to stack
3. `init()` returns `store` → **moves** struct to caller
4. Thread uses pointer → **dangling pointer!** 💥

Solution:
1. `init()` returns struct (no thread)
2. Caller calls `startPersistThread()` on **their** copy
3. Thread gets valid pointer ✅

## Stress Testing (TODO)

```zig
test "stress test - 1000 concurrent operations" {
    var store = try PlayerStore.init("stress.sqlite");
    defer store.deinit();
    try store.startPersistThread();
    
    // Hammer queue from main thread
    for (0..1000) |i| {
        store.queuePersist(@intCast(i), .{ .x = @floatFromInt(i), .y = 0 });
        
        // Concurrent reads every 100 writes
        if (i % 100 == 0) {
            _ = try store.loadPlayerState(@intCast(i / 2));
        }
    }
    
    // Wait for all to flush
    std.Thread.sleep(10 * std.time.ns_per_s);
    
    // Verify all persisted
    for (0..1000) |i| {
        const state = try store.loadPlayerState(@intCast(i));
        try std.testing.expect(state != null);
    }
}
```

## Thread Sanitizer

Detect data races at runtime:

```bash
# Build with thread sanitizer
zig test src/db/player_store_test.zig -lc -lsqlite3 -fsanitize-thread

# Or on Linux with Valgrind helgrind
valgrind --tool=helgrind zig test src/db/player_store_test.zig -lc -lsqlite3
```

**Note:** Thread sanitizer may report false positives with SQLite internals.

## Debugging Failed Tests

### Test Hangs

**Symptom:** Test runs forever, never completes

**Cause:** Thread not started or deadlock

**Debug:**
```zig
// Add timeout
const timeout = std.time.ns_per_s * 30; // 30 seconds
std.Thread.sleep(timeout);
std.debug.print("TIMEOUT - thread may be stuck\n", .{});
```

### Data Not Persisting

**Symptom:** `loadPlayerState()` returns `null` after queue

**Causes:**
1. Didn't wait for flush (5s interval)
2. Thread not started (`startPersistThread()` not called)
3. Queue overflowed (check capacity)

**Debug:**
```zig
std.debug.print("Queue state: write={}, read={}\n", .{
    store.write_index.load(.acquire),
    store.read_index.load(.acquire),
});
```

### SQLite Errors

**Symptom:** `Failed to execute batch upsert` in logs

**Causes:**
1. DB file locked by another process
2. Disk full
3. Invalid SQL (buffer overflow?)

**Debug:**
```bash
# Check DB file
sqlite3 test_concurrent.sqlite "SELECT COUNT(*) FROM player_state;"

# Check locks
lsof test_concurrent.sqlite
```

## CI/CD Integration

```yaml
# .github/workflows/test.yml
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: goto-bus-stop/setup-zig@v2
        with:
          version: 0.15.1
      
      - name: Install SQLite
        run: sudo apt-get install -y libsqlite3-dev
      
      - name: Run Tests
        run: |
          cd game
          zig test src/db/player_store_test.zig -lc -lsqlite3
```

## Performance Benchmarks (TODO)

```zig
test "benchmark - queue throughput" {
    var store = try PlayerStore.init("bench.sqlite");
    defer store.deinit();
    
    const start = std.time.nanoTimestamp();
    
    for (0..1_000_000) |i| {
        store.queuePersist(@intCast(i % 1000), .{ .x = 0, .y = 0 });
    }
    
    const end = std.time.nanoTimestamp();
    const duration_ns = end - start;
    const ops_per_sec = 1_000_000 * std.time.ns_per_s / duration_ns;
    
    std.debug.print("Throughput: {} ops/sec\n", .{ops_per_sec});
    // Expected: ~50-100M ops/sec (lock-free atomic overhead)
}
```

## References

- [Zig Test Documentation](https://ziglang.org/documentation/master/#Zig-Test)
- [SQLite Testing](https://www.sqlite.org/testing.html)
- [Lock-Free Correctness Testing](https://www.1024cores.net/home/lock-free-algorithms/testing)
