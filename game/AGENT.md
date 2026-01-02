# Codex Working Notes

## Environment
- Zig 0.15.1 (`zig env` to confirm). Keep toolchain consistent across machines before editing.
- Project root: current repo (`game/`). Build script already wires raylib dependency.

## Build Targets
- Client: `zig build` installs and builds `zig-client`; run via `zig build run`.
- Server: `zig build` builds `zig-server`; run via `zig-out/bin/zig-server`.
- Migrations: `zig build` builds `zig-migrate`; run via `zig build migrate -- <command>`.

## Tests
- Run everything in a file: `zig test src/server_main.zig`.
- Filter to a single test: `zig test src/server_main.zig --test-filter "udp client receives"`.
- Tests rely on localhost UDP sockets; ensure the port range is open before running.

## Database Migrations
- Schema managed by `src/db/migrations.zig` migration system
- **IMPORTANT**: Run migrations before first server start
- Commands:
  - `./zig-out/bin/zig-migrate status` - Check migration status
  - `./zig-out/bin/zig-migrate up` - Apply pending migrations
  - `zig build migrate -- status` - Alternative using build.zig
  - `zig build migrate -- up` - Alternative using build.zig
- Adding new migrations:
  1. Add migration to `src/db/migrations.zig` migrations array
  2. Increment version number
  3. Run `zig-migrate up` to apply

## Persistence System
- SQLite database stores player positions: `data/player_state.sqlite`
- `src/db/player_store.zig`: **Completely lock-free** threaded persistence module
  - **Does NOT create schema** - expects migrations to be run first
  - `loadPlayerState(session_id)`: Sync read on connect (uses main_db, **no mutex**)
  - `queuePersist(session_id, state)`: Lock-free async write (SPSC atomic queue)
  - Persist thread flushes every 5 seconds with batch UPSERT (uses persist_db, **no mutex**)
  - **Per-thread database connections** - zero contention
  - **Lock-free ring buffer** - atomic indices with acquire/release semantics
  - **Batch UPSERT** - single SQL statement for N updates
  - See `docs/ARCHITECTURE_SUMMARY.md` for complete design
  - See `docs/LOCK_FREE_QUEUE.md` for queue implementation details
  - See `docs/SQLITE_THREADING.md` for threading mode explanation
- `src/server_main.zig`: Integration
  - Loads state on connect (restores position or uses spawn)
  - Marks client dirty on move
  - Queues dirty clients every 5s housekeeping
  - Queues dirty clients on disconnect
  - DB path: `data/player_state.sqlite`
  - Default spawn: (350, 200)
- See `TESTING.md` for persistence testing instructions

## Networking Notes
- `src/server_main.zig` provides `UdpEchoServer`; `main` binds port `9999` while tests bind `0` to get an ephemeral port.
- Packet protocol defined in `src/shared.zig` with binary encoding.
- Client state persists to SQLite database.

## Workflow Tips
1. Before coding on a new machine, install Zig 0.15.1 and clone this repo.
2. Run `zig build` once to ensure dependencies resolve (raylib, sqlite3, etc.).
3. Keep this file updated with any workflow constraints or commands you want Codex to follow.
4. When opening a new Codex session, mention any active tasks plus remind it to check `AGENT.md` for context.

## Style Reminders
- Prefer `std` facilities (e.g. `posix.*`, `std.json`) over external libs.
- Tests should avoid binding privileged ports; use port `0` in tests and query `boundPort()`.
- Keep networking code non-blocking-friendly even if currently blocking (structure around `handleOnce` for reuse).
- Use `std.Thread.sleep` for sleeping in threads (not `std.time.sleep`).
