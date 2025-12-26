# Voice Chat Design (future)

- Transport: dedicate a channel for audio (UDP with light reliability/FEC or a reliable stream); keep game traffic separate.
- Codec: Opus for low bitrate/latency; frame size 20–40 ms; stereo optional.
- Capture path: background thread captures mic → encodes → enqueues frames at fixed cadence; gate with PTT/VOX to reduce chatter.
- Send path: packetize under MTU; include session id + talk-spurt/frame sequence to drop late/stale audio; rate-limit.
- Receive path: jitter buffer + decode; spatialize (volume/pan) by distance; attenuate or drop outside interest range.
- Controls: per-client mute/block, global mute, volume per speaker.
- Security/abuse: minimal auth tag on audio packets; allow server-side mute/kick; consider profanity/abuse reporting later.
