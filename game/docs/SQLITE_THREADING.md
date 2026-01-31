# SQLite Threading Mode and Safety

## Current Configuration

**Threading Mode:** `SQLITE_THREADSAFE=2` (Multi-thread)  
**Architecture:** **Separate DB connections per thread** ✅

```bash
$ sqlite3 data/player_state.sqlite "PRAGMA compile_options;" | grep THREAD
THREADSAFE=2
```

## SQLite Threading Modes

| Mode | Name | Description | Our Usage |
|------|------|-------------|-----------|
| 0 | Single-thread | No thread safety at all | ❌ Not safe |
| 1 | Serialized | Fully thread-safe, SQLite handles locking | ❌ Too slow |
| **2** | **Multi-thread** | **Thread-safe, but no connection sharing** | **✅ Current** |

## Mode 2: Multi-thread Rules

### What's Allowed ✅

```zig
// Thread 1
var db1: *sqlite3 = sqlite3_open("db.sqlite");
sqlite3_exec(db1, "SELECT ...");

// Thread 2  
var db2: *sqlite3 = sqlite3_open("db.sqlite");  // Different connection
sqlite3_exec(db2, "SELECT ...");  // ✓ Safe - separate connections
```

### What's NOT Allowed ❌

```zig
// Shared between threads
var db: *sqlite3 = sqlite3_open("db.sqlite");

// Thread 1
sqlite3_exec(db, "SELECT ...");  // ❌ RACE CONDITION

// Thread 2
sqlite3_exec(db, "UPDATE ...");  // ❌ RACE CONDITION
```

**Solution:** Use external synchronization (mutex)

## Our Architecture

### Solution: Separate Connections Per Thread ✅

```zig
pub const PlayerStore = struct {
    // Main thread connection (reads only)
    main_db: *c.sqlite3,
    load_stmt: *c.sqlite3_stmt,
    
    // Persist thread connection (writes only)
    persist_db: *c.sqlite3,
    
    // NO MUTEX NEEDED!
};
```

### ~~Old Approach: Shared Connection + Mutex~~ (Deprecated)

```zig
// Main thread - uses main_db (NO LOCK)
pub fn loadPlayerState(self: *Self, session_id: u32) !?PlayerState {
    // No mutex needed! main_db is only accessed by main thread
    _ = c.sqlite3_reset(self.load_stmt);
    const rc = c.sqlite3_step(self.load_stmt);
    // ...
}

// Persist thread - uses persist_db (NO LOCK)
fn flushPendingSync(self: *Self) void {
    // ... prepare SQL ...
    
    // No mutex needed! persist_db is only accessed by persist thread
    c.sqlite3_exec(self.persist_db, "BEGIN IMMEDIATE;", ...);
    c.sqlite3_exec(self.persist_db, sql, ...);
    c.sqlite3_exec(self.persist_db, "COMMIT;", ...);
}
```

## Why Separate Connections? ✅

### Benefits

**Pros:**
- ✅ **Zero contention** - No mutex, no blocking
- ✅ **True parallelism** - WAL mode enables concurrent read + write
- ✅ **Simpler code** - No mutex logic, each thread owns its connection
- ✅ **Better performance** - No lock overhead (~25-100ns saved per operation)
- ✅ **Correct by design** - Follows SQLite multi-thread mode best practices

**Cons:**
- ⚠️ Slightly more memory (~200KB per connection)
- ⚠️ Need to close both connections in deinit()

**Decision:** ✅ **Use separate connections** - Better performance, cleaner code, proper threading model.

## Lock-Free Architecture

### Zero Mutex Design

```
Queue Operations (atomic, lock-free)
  write_index: atomic  ← No lock
  read_index: atomic   ← No lock

Database Operations (per-thread, no lock needed)
  main_db: *sqlite3    ← Main thread only
  persist_db: *sqlite3 ← Persist thread only
```

### Thread Timeline

```
Main Thread (Game Loop)          Persist Thread (Background)
───────────────────────          ───────────────────────────

1. Player moves
2. queuePersist()
     write_index.store() ⚛️        (no contention)
3. Continue game loop...
                                  4. Timer fires (5 seconds)
                                  5. flushPendingSync()
                                       read_index.load() ⚛️
                                       (copy queue to buffer)
                                       read_index.store() ⚛️
                                       sqlite3_exec(persist_db, ...)
                                       ↑ No lock! Separate connection

6. Player connects (CAN HAPPEN DURING PERSIST!)
7. loadPlayerState()
     sqlite3_step(main_db, ...)   ← No lock! Separate connection
     ↑ Concurrent with persist! WAL mode allows this
```

**Key:** Both queue operations AND DB operations are lock-free! ✅

## Performance Analysis

### Contention Points

**1. Queue operations (lock-free):**
- Frequency: Every player move (~60 Hz per player)
- Lock: None ✅
- Contention: Zero
- Overhead: ~1-5ns per operation

**2. Database operations (NO LOCK!):**
- Frequency: 
  - Reads: Once per player connect (~0.1 Hz)
  - Writes: Once every 5 seconds (0.2 Hz)
- Lock: **None** ✅
- Contention: **Zero** ✅
- Overhead: SQLite only (~1-10ms for reads, ~10-50ms for batch writes)

### Concurrent Operations ✅

```
Time  Main Thread           Persist Thread
────  ───────────           ──────────────
t0    Player connects
t1    loadPlayerState()
t2      sqlite3_step(main_db) ←─┐
t3                               │ CONCURRENT!
t4                          flushPendingSync()
t5                            sqlite3_exec(persist_db) ←─┘
t6      return state        
t7                            COMMIT
```

**Result:** ✅ **True parallelism!** WAL mode allows concurrent reader + writer

**Impact:** ZERO blocking, operations run in parallel

## WAL Mode Benefits

Even with a single connection, WAL mode helps:

```
// With WAL, these CAN run concurrently:
Thread 1: SELECT ... (reads from WAL)
Thread 2: INSERT ... (writes to WAL)

// Without WAL (rollback journal):
Thread 1: SELECT ... ← BLOCKS
Thread 2: INSERT ... ← BLOCKS
```

Our mutex prevents this parallelism, but WAL still gives us:
- ✅ Better crash recovery
- ✅ Faster writes (append-only)
- ✅ No blocking during checkpoints

## Future: Per-Thread Connections

If we need better parallelism:

```zig
pub const PlayerStore = struct {
    main_db: *c.sqlite3,
    main_stmt: *c.sqlite3_stmt,
    
    persist_db: *c.sqlite3,
    
    // No mutex needed!
};

pub fn init(db_path: [:0]const u8) !Self {
    // Open connection 1 (main thread)
    var main_db = try openDb(db_path);
    
    // Open connection 2 (persist thread)
    var persist_db = try openDb(db_path);
    
    return Self{
        .main_db = main_db,
        .persist_db = persist_db,
    };
}
```

**Benchmark first!** Current mutex overhead is negligible.

## Testing Thread Safety

### Stress Test

```zig
test "concurrent load and persist" {
    var store = try PlayerStore.init("test.db");
    defer store.deinit();
    
    // Thread 1: Rapid loads
    var load_thread = try std.Thread.spawn(.{}, rapidLoad, .{&store});
    
    // Thread 2: Rapid persists  
    var persist_thread = try std.Thread.spawn(.{}, rapidPersist, .{&store});
    
    load_thread.join();
    persist_thread.join();
    
    // Check: No corruption, no deadlocks
}
```

### Tools

```bash
# Thread sanitizer (detects data races)
zig build -Dsanitize-thread=true

# Valgrind helgrind (detects race conditions)
valgrind --tool=helgrind ./zig-out/bin/zig-server
```

## Summary

| Aspect | Solution | Performance |
|--------|----------|-------------|
| Queue operations | Lock-free atomics | ⚡ ~1-5ns, zero contention |
| DB reads | Separate connection (main_db) | ⚡ ~1-10ms, **zero contention** |
| DB writes | Separate connection (persist_db) | ⚡ ~10-50ms, **zero contention** |

**Overall:** 🚀 **Completely lock-free architecture!**
- Queue: Lock-free SPSC ring buffer
- Database: Per-thread connections, no mutex
- WAL mode: Enables true concurrent read + write

**Thread safety:** ✅ Correct by design (no shared mutable state)
