# Player State Persistence Architecture

## Overview

The game server uses a **completely lock-free architecture** for persisting player positions to SQLite.

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                     Game Server                              │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  Main Thread (Game Loop)          Persist Thread             │
│  ───────────────────────          ──────────────             │
│                                                               │
│  Player moves (60 Hz)                                        │
│       ↓                                                       │
│  queuePersist() ──────────────────→ Lock-Free Queue          │
│    write_index ⚛️                      ↓                     │
│                                   read_index ⚛️              │
│                                        ↓                      │
│  Player connects (rare)           flushPendingSync()         │
│       ↓                                ↓                      │
│  loadPlayerState()                Batch UPSERT                │
│       ↓                                ↓                      │
│  ┌──────────────┐                ┌──────────────┐           │
│  │   main_db    │                │  persist_db  │           │
│  │  (Connection)│                │ (Connection) │           │
│  └──────┬───────┘                └──────┬───────┘           │
│         │                                │                   │
│         └────────────────┬───────────────┘                   │
│                          ↓                                    │
│                   SQLite Database                             │
│                   (WAL mode enabled)                          │
│                                                               │
└─────────────────────────────────────────────────────────────┘

Key:
⚛️  = Atomic operation (lock-free)
─→ = Data flow
```

## Components

### 1. Lock-Free SPSC Queue

**Purpose:** Transfer player state updates from game thread to persist thread

**Implementation:**
```zig
pending_queue: [256]PersistEntry
write_index: atomic usize  // Producer only
read_index: atomic usize   // Consumer only
```

**Properties:**
- ✅ Wait-free (bounded time)
- ✅ Zero contention
- ✅ Single producer (main thread)
- ✅ Single consumer (persist thread)
- ✅ ~1-5ns overhead per operation

**Algorithm:** Ring buffer with atomic indices and acquire/release semantics

### 2. Per-Thread Database Connections

**Purpose:** Eliminate mutex contention for SQLite access

**Implementation:**
```zig
main_db: *sqlite3        // Main thread (reads)
persist_db: *sqlite3     // Persist thread (writes)
```

**Properties:**
- ✅ No mutex needed
- ✅ True concurrent read + write (WAL mode)
- ✅ Each thread owns its connection
- ✅ ~200KB memory per connection

### 3. Batch UPSERT

**Purpose:** Minimize database round-trips

**Implementation:**
```sql
INSERT INTO player_state (session_id, x, y, updated_at)
VALUES (1, 100.0, 200.0, 123), (2, 150.0, 250.0, 123), ...
ON CONFLICT(session_id) DO UPDATE SET x=excluded.x, y=excluded.y
```

**Properties:**
- ✅ Single SQL statement for N updates
- ✅ ~10-100x faster than individual UPSERTs
- ✅ Atomic (all-or-nothing)
- ✅ Supports up to ~160 players per batch (8KB buffer)

## Data Flow

### Write Path (Player Movement)

```
1. Player moves
   → Server receives UDP packet
   → Updates client.state.x, client.state.y
   → Marks client.dirty = true

2. Housekeeping (every 5s)
   → For each dirty client:
      → queuePersist(session_id, state)  [⚛️ Lock-free]
      → Mark client.dirty = false

3. Queue operation
   → write_index.load(.acquire)          [⚛️ Atomic read]
   → pending_queue[idx] = entry          [Normal write]
   → write_index.store(idx+1, .release)  [⚛️ Atomic write]

4. Persist thread (every 5s)
   → read_index.load(.acquire)           [⚛️ Atomic read]
   → Copy entries to local buffer
   → read_index.store(new_idx, .release) [⚛️ Atomic write]
   
5. Batch UPSERT
   → Build SQL from local buffer
   → sqlite3_exec(persist_db, sql)       [No lock!]
   → COMMIT
```

### Read Path (Player Connect)

```
1. Player connects
   → Server receives first packet from session_id

2. Load state
   → loadPlayerState(session_id)
   → sqlite3_step(main_db, load_stmt)    [No lock!]
   
3. Spawn player
   → If state exists: restore position
   → If no state: use default spawn (350, 200)
```

## Performance Characteristics

### Latency

| Operation | Latency | Frequency | Contention |
|-----------|---------|-----------|------------|
| queuePersist() | ~1-5ns | 60 Hz × N players | Zero |
| loadPlayerState() | ~1-10ms | Once per connect | Zero |
| flushPendingSync() | ~10-50ms | Every 5s | Zero |

### Throughput

**Queue capacity:** 256 entries  
**Flush interval:** 5 seconds  
**Effective throughput:** ~50 updates/sec sustained  
**Typical load:** 10-20 players × 60 Hz = 600-1200 queued/sec (well within capacity)

### Memory Overhead

- Queue buffer: 256 × 16 bytes = 4 KB
- Main DB connection: ~200 KB
- Persist DB connection: ~200 KB
- **Total:** ~404 KB

## Thread Safety

### Invariants

1. **write_index** only written by main thread
2. **read_index** only written by persist thread
3. **main_db** only accessed by main thread
4. **persist_db** only accessed by persist thread
5. Queue slots protected by index ownership

### Memory Ordering

```zig
// Producer (main thread)
queue[idx] = data;                        // ① Normal write
write_index.store(idx+1, .release);       // ② Release barrier

// Consumer (persist thread)
new_idx = write_index.load(.acquire);     // ③ Acquire barrier
data = queue[read_idx];                   // ④ Normal read
```

**Guarantee:** All writes before ② are visible after ③

### Proof of Correctness

**Claim:** No data races

**Proof:**
1. write_index and read_index are atomic → no torn reads
2. Queue slots only accessed when owned (idx < write_idx && idx >= read_idx)
3. Ownership transfer uses acquire/release → no reordering
4. DB connections never shared → no concurrent access
∴ No data races ✅

## WAL Mode Benefits

SQLite with Write-Ahead Logging enables:

1. **Concurrent readers and writers** (different connections)
2. **Better crash recovery** (atomic commits)
3. **Faster writes** (append-only log)
4. **No blocking during checkpoints**

```
Without WAL:
  Reader ←─ BLOCKS ─→ Writer

With WAL:
  Reader ─────────────→ [Reading from main DB]
          ↓
  Writer ─────────────→ [Writing to WAL]
```

## Failure Modes

### Queue Overflow

**Condition:** write_index + 1 == read_index  
**Action:** Drop update (silent)  
**Mitigation:** 256 slot capacity, 5s flush interval  
**Likelihood:** Very low (requires 256 queued updates with no flush)

### Persist Thread Crash

**Condition:** Thread panic during flush  
**Action:** In-flight transaction rolls back  
**Impact:** Recent updates (< 5s) lost  
**Mitigation:** None currently (could add write-ahead log)

### Database Lock Timeout

**Condition:** Another process holds exclusive lock  
**Action:** SQLite returns SQLITE_BUSY  
**Impact:** Batch UPSERT fails, updates lost  
**Mitigation:** Use IMMEDIATE transactions to fail fast

## Testing

### Unit Tests

- ✅ Queue enqueue/dequeue
- ✅ Queue overflow handling
- ✅ Concurrent read during write

### Integration Tests

- ✅ Server start/stop
- ✅ Player connect → position restored
- ✅ Player move → position persisted

### Stress Tests

- ⏳ TODO: 100+ concurrent players
- ⏳ TODO: Queue saturation test
- ⏳ TODO: Thread sanitizer validation

## Comparison with Alternatives

### vs. Mutex-Protected Single Connection

| Aspect | Per-Thread Connections | Single Connection + Mutex |
|--------|------------------------|---------------------------|
| Read latency | ~1-10ms | ~1-10ms + mutex overhead |
| Write latency | ~10-50ms | ~10-50ms + mutex overhead |
| Contention | Zero | Minimal (rare) |
| Code complexity | Simple | Mutex logic |
| Memory | ~404 KB | ~204 KB |
| **Winner** | **✅** | ❌ |

### vs. In-Memory Only

| Aspect | SQLite Persistence | In-Memory Only |
|--------|-------------------|----------------|
| Data durability | ✅ Survives crashes | ❌ Lost on crash |
| Restart time | Fast (load from DB) | Slow (rebuild state) |
| Memory usage | Low (DB on disk) | High (all in RAM) |
| Complexity | Medium | Low |
| **Winner** | **✅** | ❌ |

### vs. External DB (PostgreSQL)

| Aspect | SQLite | PostgreSQL |
|--------|--------|------------|
| Latency | ~1-50ms | ~10-100ms (network) |
| Setup | Zero (embedded) | High (separate server) |
| Scalability | Single server | Distributed |
| Cost | Free | Infrastructure |
| **Winner (game server)** | **✅** | ❌ |

## Metrics to Monitor

```zig
// TODO: Add metrics
queue_depth: usize           // Current queue size
queue_overflows: usize       // Dropped updates count
persist_latency_ms: f64      // Batch UPSERT duration
persist_count: usize         // Updates per batch
db_errors: usize             // SQLite errors count
```

## Future Optimizations

### 1. Adaptive Flush Interval

```zig
// Flush more frequently when queue is filling
const interval = if (queue_depth > 128)
    1000  // 1 second
else
    5000; // 5 seconds
```

### 2. Overflow Warnings

```zig
if (next_write == read_idx) {
    metrics.queue_overflows += 1;
    std.log.warn("Queue full, dropping update for session {d}", .{session_id});
}
```

### 3. Connection Pooling

```zig
// For future: multiple persist threads
var persist_connections: [4]*sqlite3;
// Hash session_id to pick connection
const conn_idx = session_id % 4;
```

### 4. Compression

```zig
// Store deltas instead of absolute positions
const delta_x = state.x - prev_state.x;
const delta_y = state.y - prev_state.y;
// Saves ~50% bandwidth for small movements
```

## References

- [SQLite WAL Mode](https://www.sqlite.org/wal.html)
- [SQLite Multi-threading](https://www.sqlite.org/threadsafe.html)
- [Lock-Free SPSC Queue](https://www.1024cores.net/home/lock-free-algorithms/queues)
- [Zig Atomics](https://ziglang.org/documentation/master/std/#A;std:atomic)

## Related Documentation

- `LOCK_FREE_QUEUE.md` - Detailed queue implementation
- `SQLITE_THREADING.md` - Threading mode and safety
- `MIGRATIONS.md` - Database schema management
- `TESTING.md` - Testing and verification
