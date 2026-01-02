# Testing Instructions for Player State Persistence

## Prerequisites
- Zig 0.15.1
- SQLite3 (usually pre-installed on macOS/Linux)

## Setup

### 1. Build the Game
```bash
cd game
zig build
```

### 2. Run Unit Tests

**Player Store Tests (Lock-Free Queue + Per-Thread Connections):**
```bash
# Run all player store tests
zig test src/db/player_store_test.zig -lc -lsqlite3

# Run specific test
zig test src/db/player_store_test.zig -lc -lsqlite3 --test-filter "concurrent"
zig test src/db/player_store_test.zig -lc -lsqlite3 --test-filter "overflow"
```

**Tests included:**
- ✅ Concurrent read and write operations (verifies lock-free safety)
- ✅ Queue overflow handling (255 entry capacity)
- ✅ Lock-free SPSC queue semantics
- ✅ Per-thread database connections (no mutex contention)

### 3. Run Database Migrations
**IMPORTANT:** You must run migrations before starting the server for the first time.

```bash
# Check migration status
./zig-out/bin/zig-migrate status

# Run all pending migrations
./zig-out/bin/zig-migrate up
```

Expected output:
```
Running migrations...
Current schema version: 0
Applying migration 1: create_player_state_table
✓ Migration 1 applied successfully
Applied 1 migration(s)
```

### 4. Run the Server
```bash
./zig-out/bin/zig-server
```

Expected output:
```
Server running on port 9999...
```

## Run the Client
In a new terminal:
```bash
./zig-out/bin/zig-client
```

## Test Persistence Flow

### 1. First Connection (New Player)
1. Start the server
2. Run the client and connect
3. Move your character around the map
4. Wait at least 5 seconds (persistence interval)
5. Check server output for: `Persisted X player state(s) to database`
6. Quit the client

### 2. Verify Database
```bash
sqlite3 game/data/player_state.sqlite "SELECT * FROM player_state;"
```

Expected output: A row with your session_id and last position

### 3. Reconnection (Position Restoration)
1. Restart the client (not the server)
2. Connect with the same session_id (should happen automatically)
3. Check server output for: `Player reconnected: session_id=X, restored pos=(X.X, Y.Y)`
4. Your character should appear at the last saved position

## Expected Server Logs

**New Player:**
```
New player connected: session_id=1234567890, spawn=(350.0, 200.0), total_clients=1
Sent 4 plots to client
Persisted 1 player state(s) to database
```

**Reconnecting Player:**
```
Player reconnected: session_id=1234567890, restored pos=(378.5, 220.3), total_clients=1
Sent 4 plots to client
```

## Database Schema

The schema is managed through migrations in `src/db/migrations.zig`.

**Current tables:**

```sql
-- Player positions
CREATE TABLE player_state (
  session_id INTEGER PRIMARY KEY,
  x REAL NOT NULL,
  y REAL NOT NULL,
  updated_at INTEGER NOT NULL
);

-- Migration tracking (managed automatically)
CREATE TABLE schema_migrations (
  version INTEGER PRIMARY KEY,
  name TEXT NOT NULL,
  applied_at INTEGER NOT NULL
);
```

## Migration Commands

```bash
# Check which migrations have been applied
./zig-out/bin/zig-migrate status

# Apply all pending migrations
./zig-out/bin/zig-migrate up

# Or use the build.zig shortcut
zig build migrate -- status
zig build migrate -- up
```

## Troubleshooting

### Build Errors
If you see linker errors about sqlite3:
```bash
# macOS: install sqlite3 via brew
brew install sqlite3

# Linux: install libsqlite3-dev
sudo apt-get install libsqlite3-dev
```

### Database Not Created
The database is only created when:
1. Server starts successfully
2. At least one player connects

Check server startup logs for SQLite errors.

### Position Not Restored
- Make sure you're using the same session_id (automatic with current client)
- Wait at least 5 seconds after moving before quitting
- Check server logs for "Persisted X player state(s)" message

## Architecture

**Main Thread:**
- Game loop, packet handling
- Sync DB reads: `loadPlayerState()` on connect
- Mark clients dirty on move
- Queue dirty clients every 5s housekeeping

**Persist Thread:**
- Runs every 5 seconds
- Flushes queue to SQLite
- Uses WAL mode for concurrent reads

**Data Flow:**
```
Client moves → mark dirty → housekeeping → queuePersist() → queue
                                          │
                                          ▼
                                    Persist Thread
                                          │
                                          ▼
                                    Flush to SQLite
```
