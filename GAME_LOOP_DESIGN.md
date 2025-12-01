# Game Loop / Networking Separation

Context: Zig 0.15.2 + raylib. Current setup: client polls the UDP socket once per frame; server only sends when it receives a packet. Symptoms: empty polls most frames, ghost-walking when a packet drops, client FPS tied to network cadence.

## Problems
- Event-driven server: no steady tick; no packets when clients are idle.
- Client per-frame poll: only one `recvfrom` per frame, so burst packets can be skipped; render FPS != network cadence.
- UDP loss: a missed `all_players_state` leaves `is_moving` stale until another packet arrives.

## Preferred Design: Decouple Network from Render
1) **Server tick (20–30 Hz)**
   - Run a fixed loop that always broadcasts `all_players_state` (and your own state) every tick, independent of input.
   - Clients receive at a predictable cadence; fewer empty polls; easier interpolation.

2) **Client recv thread**
   - Put a blocking `recvfrom` loop on a background thread.
   - Push decoded updates into a thread-safe queue; render loop pops/interpolates at any FPS.
   - Continue sending input (moves/pings) from the main thread; ensure only one thread uses the socket for recv.

## Suggested Implementation Steps
- Add a server heartbeat tick (e.g. 50 ms): build `all_players_state` each tick and send to all clients.
- On client: create a `SharedQueue` (mutex + fifo) of decoded state updates; spawn `recvThread` that blocks on `recvfrom`, decodes packets, and enqueues updates.
- Render loop: pop latest updates each frame, interpolate/extrapolate, render; no per-frame socket polling.
- Keep a short stale timeout (100–250 ms) to mark remote players idle if updates stop, to mask packet loss/disconnects.

Benefits: smoother remote movement, less ghost-walking, network cadence independent from render FPS, and predictable update rate for interpolation.

## Interest Management (future)
- Partition world space (e.g. grid/quad-tree) and track which cell(s) each player occupies.
- For each tick/broadcast, include only players within a radius/neighboring cells of the recipient.
- Update client to cull/render only entities it knows about; request on-demand loads when entering new cells.
- Keep a minimal global heartbeat (e.g. positions of nearby players + your own) to avoid starving clients when no movement occurs.
- Consider budgeted sends per tick to prevent bursty packets when many players cluster; prioritize closest entities.
