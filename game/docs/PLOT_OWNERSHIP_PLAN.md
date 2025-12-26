# Plot Ownership Plan (Chain‑Agnostic)

## Goals
- Represent plots as tile‑aligned rectangles in the world.
- Keep ownership checks chain‑agnostic via a small interface.
- Make placement/building logic enforce plot ownership.
- Allow future Web3 implementations without touching gameplay code.

## 1) Data Model
- Add a `Plot` type:
  - `id: u64`
  - `rect: { tile_x, tile_y, width_tiles, height_tiles }`
  - `owner: OwnerId?`
- Add `OwnerId` type (opaque string + kind enum):
  - `kind: enum { none, wallet, ens, nft, custom }`
  - `value: [64]u8`, `len: u8`
- World JSON: add optional `plots` array.

## 2) Ownership Abstraction
- Define a resolver interface:
  - `resolve(plot_id) -> OwnerId?`
  - `canBuild(plot_id, user_owner_id) -> bool`
- Provide `NullResolver` (offline/dev):
  - `resolve` returns null
  - `canBuild` returns true

## 3) Placement Rules
- When placing/building:
  - Find plot by tile position.
  - If no plot: disallow (or allow based on config).
  - If plot exists: `resolver.canBuild(plot_id, user)` must be true.
- Add UI feedback when blocked (e.g., “Not your plot”).

## 4) Persistence
- Load/save plots via world JSON.
- Keep `owner` optional so offline maps work.

## 5) Integration Points
- Placement system (`ui/placement.zig` + editor) uses plot lookup.
- Collision and world checks unaffected unless you want plots to be non‑walkable.
- Server can inject resolver that verifies ownership.

## 6) Future Web3 Binding (Not Now)
- Wallet ownership: `OwnerId{ kind: .wallet, value: "0x..." }`
- NFT ownership: `OwnerId{ kind: .nft, value: "chain:contract:tokenId" }`
- ENS ownership: `OwnerId{ kind: .ens, value: "name.eth" }`

## Open Questions
- Should building be allowed outside plots?
- Are plots fixed size or variable?
- Should plots be editable in the tile inspector?
- Which client user identity format should be used initially?
