# Tile System Notes (Summary)

## What you asked to capture
- You wanted a clear refresher on the tile map system because the original was AI‑generated and hard to follow.
- You asked if buildings should align to tiles (answer: yes, with current system).
- You asked what `tile_x`, `tile_y`, `width_tiles`, `height_tiles` mean.
- You asked what the `shared.World` fields mean and how they relate.

## Current reality (as‑is)
There are three overlapping systems that are only partially connected:

1) **Logical terrain grid**
- Source: `world_edit.json` contains a `tiles` 2D array.
- Loaded into `shared.World.tiles` (flattened) with `tile_grid_x/y`.
- Intended to be the ground truth for terrain, but runtime code does **not** use it yet.

2) **Auto‑tiling renderer**
- Types: `TileLayer`, `AutoTileConfig`, `AutoTileRenderer`.
- Uses N/E/S/W neighbor bitmask to pick visual variants.
- Exists, but not wired into runtime rendering (terrain/paths are commented out in draw).

3) **Editor map/placement**
- `Map` is a multi‑layer editor grid.
- `PlacementSystem` + `GhostLayer` place sprites on the grid.
- Export writes buildings, not the tiles grid.

## Tile map 101 (refresher)
- **Tile map**: grid of tile IDs (rows × columns).
- **Tile size**: pixel size of each tile.
- **Tile ID**: integer that maps to a sprite in the tileset.
- **Tileset**: image containing many tile sprites.
- **Layers**: multiple tile grids drawn in order (ground, roads, objects).

## Autotiling
- Store a terrain ID (e.g., Road) in the grid.
- At render time, check 4 neighbors to build a bitmask.
- Use that mask to pick the correct tile variant (corner/edge/center).

## Buildings (current project meaning)
- `tile_x`, `tile_y`: top‑left tile coordinate of the building footprint.
- `width_tiles`, `height_tiles`: size in tiles.
- Pixels are derived by multiplying by tile size:
  - `px = tile_x * tile_width`, `py = tile_y * tile_height`.
- Buildings are drawn above terrain; they are not the terrain itself.

## shared.World fields (meaning)
- `width`, `height`: world size in **pixels**.
- `tiles_x`, `tiles_y`: grid size in **tiles**.
- `tiles`: optional terrain grid, flattened row‑major.
- `tile_grid_x`, `tile_grid_y`: dimensions of `tiles`.
- `buildings`: list of building instances (tile‑aligned).

## Consistency expectation
- `tiles_x/tiles_y` and `tile_grid_x/tile_grid_y` should match.
- If `tiles` exists, it should be the source of truth for terrain (rendering + collision + autotiling).
- If `tiles` is missing, fallback procedural terrain can be used.

