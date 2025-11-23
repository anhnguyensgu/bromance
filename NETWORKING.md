# Networking Refactor Summary

## Protocol Layer
- `StatePayload` now carries `x`, `y`, and `timestamp_ns` (16‑byte payload) so every `state_update` conveys an authoritative position plus the server timestamp.
- `PacketPayload` supports `ping`, `move`, and `state_update`, and `Packet.decode` respects header `payload_len`.
- Added unit tests for `StatePayload` round‑trip and packet encode/decode behavior.

## Server (`src/server_main.zig`)
- Tracks a single `player_pos` and integrates move commands (speed × delta).
- Replies to `ping`/`move` with `state_update` packets whose header `.ack` echoes the input sequence, and whose payload contains `x`, `y`, `timestamp_ns`.
- Tests decode the server’s reply and assert message type, ack, and authoritative position.

## Client (`src/main.zig`)
- Movement inputs are applied locally (prediction) and queued with sequence numbers in a fixed array (Zig 0.15.2 compatible).
- On `state_update` arrival, the client snaps to the authoritative state, drops acknowledged commands, reapplies the remaining inputs, and stores the corrected position in a timestamped snapshot buffer.
- Rendering samples snapshots ~30 ms in the past for smooth motion without rubber‑banding; `move_send_interval` tightened to `1/64` (≈15.6 ms) to emulate a 64‑tick feel.

## Netcode Techniques (code references)
- **Client-side prediction** – the render loop applies every pressed movement immediately before enqueueing it for the network, so controls feel instant (`src/main.zig:90-115`).
- **Authoritative server with reconciliation** – the server integrates `move` payloads and echoes the client sequence via `PacketHeader.ack`, while the client discards acknowledged commands then replays the remaining inputs on top of the authoritative state (`src/server_main.zig:62-105`, `src/main.zig:335-358`).
- **Snapshot interpolation / render delay** – each corrected position is timestamped when stored, and the renderer samples ~30 ms in the past to smooth jitter without rubber-banding (`src/main.zig:373-407`).

## Notes
- All changes stick to Zig 0.15.2 APIs (no `ArrayList.init`, `nanoTimestamp()` cast to `i64`, etc.).
- Run `ZIG_GLOBAL_CACHE_DIR=zig-cache-global ZIG_LOCAL_CACHE_DIR=zig-cache zig test src/network.zig`, `zig test src/server_main.zig`, and `zig build run` locally—this environment can’t fetch `raylib-zig` or write Zig’s cache.
