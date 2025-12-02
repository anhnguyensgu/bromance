# Repository Review

Context: zig 0.15.2, raylib via `raylib_zig`.

## Findings
- `src/network.zig`: `encodeGenericPayload` returns a slice to a stack array (`var des: [T.size()]u8 = undefined; return payload.encode(des[0..]);`), so callers use freed memory. Have the caller provide a buffer or return a fixed-size array instead of a slice into stack memory.
- `src/network.zig`: `Packet.decode` trusts `header.payload_len` and slices `buffer[packet_header_size .. packet_header_size + payload_len]` without checking `buffer.len`. Truncated/malicious packets can trap or read past the receive buffer. Add bounds validation before slicing.
- `src/ui/hud.zig`, `src/ui/inventory_bar.zig`, `src/ui/panels/text_panel.zig`: Import `renderer.zig`, which is not present. These modules currently cannot compile; add the renderer module or adjust imports.
- `src/shared.zig`: `Room.init` returns `Self{}` without initializing `players/width/height`, leaving fields undefined and the initializer unusable. Either remove the stub or provide a proper constructor.
- `src/server_main.zig`: Server movement clamps to `0..1000` and ignores the client map/world collision logic (client uses world size 2000 and building collision). Authoritative positions can diverge, causing reconciliation jitter/teleports. Align server bounds and collision with the shared world rules.
