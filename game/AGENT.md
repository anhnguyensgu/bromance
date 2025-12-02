# Codex Working Notes

## Environment
- Zig 0.15.2 (`zig env` to confirm). Keep toolchain consistent across machines before editing.
- Project root: current repo (`new-bromance/bromance`). Build script already wires raylib dependency.

## Build Targets
- Client: `zig build` installs and builds `zig-client`; run via `zig build run`.
- Server: `zig build run-server` (or `zig-out/bin/zig-server` after build) starts the UDP echo loop defined in `src/server_main.zig`.

## Tests
- Run everything in a file: `zig test src/server_main.zig`.
- Filter to a single test: `zig test src/server_main.zig --test-filter "udp client receives"`.
- Tests rely on localhost UDP sockets; ensure the port range is open before running.

## Networking Notes
- `src/server_main.zig` provides `UdpEchoServer`; `main` binds port `9999` while tests bind `0` to get an ephemeral port.
- Payloads are raw UTF-8 (e.g. `{"type":"move_request","dir":"up"}`) and can be parsed with `std.json` once needed.

## Workflow Tips
1. Before coding on a new machine, install Zig 0.15.2 and clone this repo.
2. Run `zig build` once to ensure dependencies resolve (raylib, etc.).
3. Keep this file updated with any workflow constraints or commands you want Codex to follow.
4. When opening a new Codex session, mention any active tasks plus remind it to check `AGENT.md` for context.

## Style Reminders
- Prefer `std` facilities (e.g. `posix.*`, `std.json`) over external libs.
- Tests should avoid binding privileged ports; use port `0` in tests and query `boundPort()`.
- Keep networking code non-blocking-friendly even if currently blocking (structure around `handleOnce` for reuse).
