# World Tiles & Autotiling Design

This document explains how the world grid, buildings, and autotiling should work together in this project.

The main ideas:

- The **terrain grid** (one `TerrainType` per tile) is the ground truth for what each tile *is*.
- **Buildings** are a separate layer drawn on top of terrain and used for collision.
- **Autotiling** (roads, etc.) looks *only* at the terrain grid, not at buildings.

---

## 1. Current Situation

### 1.1 `zig-client/assets/worldedit.json`

`zig-client/assets/worldedit.json` currently looks like:

- A `world` object with:
  - `width`, `height` in pixels
  - `tiles_x`, `tiles_y` as the grid size
- A `buildings` array, with items such as `Townhall`, `Lake`, `House`, and many `Road` entries.

Example (simplified):

```/dev/null/worldedit_example.json#L1-32
{
  "world": {
    "width": 192,
    "height": 320,
    "tiles_x": 12,
    "tiles_y": 20
  },
  "buildings": [
    {
      "type": "Townhall",
      "tile_x": 2,
      "tile_y": 2,
      "width_tiles": 5,
      "height_tiles": 4
    },
    {
      "type": "Road",
      "tile_x": 7,
      "tile_y": 3,
      "width_tiles": 1,
      "height_tiles": 1
    }
  ]
}
```

There is **no explicit terrain grid** in this JSON. Terrain is implicitly deduced at runtime.

### 1.2 `World.getTileAtPosition`

`shared.World` currently derives terrain like this (conceptually):

```/dev/null/shared_world_current.zig#L1-40
pub fn getTileAtPosition(self: World, x: f32, y: f32) TerrainType {
    // 1. Convert world position to tile coords (tx, ty).

    // 2. If any building of type .Road is at (tx, ty), return .Road.
    for (self.buildings) |building| {
        if (building.building_type == .Road and
            building.tile_x == tx and building.tile_y == ty)
        {
            return .Road;
        }
    }

    // 3. Otherwise, use a radial-distance fallback
    //    to choose Water/Rock/Grass based on distance
    //    from the center of the map.
    const center_x = @divTrunc(self.tiles_x, 2);
    const center_y = @divTrunc(self.tiles_y, 2);
    const dx = tx - center_x;
    const dy = ty - center_y;
    const dist_sq = dx * dx + dy * dy;

    if (dist_sq < 16) return .Water;
    if (dist_sq < 25) return .Rock;
    return .Grass;
}
```

So currently:

- Terrain is partially data-driven (roads from `buildings`).
- And partially **procedural fallback** (a radial “island” of water/rock/grass).

There is no single explicit “terrain grid” you can inspect or edit in the JSON.

---

## 2. Problem: Buildings vs Terrain for Autotiling

Autotiling for roads uses a bitmask approach:

```zig-client/src/tiles_test.zig#L35-42
fn computeBitmask(world: shared.World, tx: i32, ty: i32, terrain: shared.TerrainType) u8 {
    var mask: u8 = 0;
    if (world.getTileAtGrid(tx, ty - 1) == terrain) mask |= 1; // Up
    if (world.getTileAtGrid(tx + 1, ty) == terrain) mask |= 2; // Right
    if (world.getTileAtGrid(tx, ty + 1) == terrain) mask |= 4; // Down
    if (world.getTileAtGrid(tx - 1, ty) == terrain) mask |= 8; // Left
    return mask;
}
```

This function assumes:

- `world.getTileAtGrid(tx, ty)` returns the **logical terrain type** of the tile at `(tx, ty)`.
- It can then check neighbors and build a 4-bit mask describing which neighbors share the same terrain (`.Road` in this case).

However, with the current model:

- A **Townhall** occupies several tiles visually (e.g. `width_tiles: 5, height_tiles: 4`).
- But `getTileAtGrid` / `getTileAtPosition` doesn’t know about “Townhall terrain” — it only knows about `Road` buildings and the radial fallback.
- Roads are represented as 1×1 `Road` buildings at specific `(tile_x, tile_y)`.
- All other tiles fall back to Water/Rock/Grass based on distance from the center.

This leads to problems:

- Tiles under or adjacent to a Townhall might be visually covered by the Townhall sprite, but terrain logic still thinks they’re Grass/Rock/Water.
- When computing the road bitmask next to the Townhall, neighbor tiles that *look* like part of a continuous road may be misclassified (e.g. fallback says `.Grass` instead of `.Road`), so the autotile mask is wrong and the road sprites don’t connect properly.

In short:

> Buildings and terrain are conflated. Autotiling should care only about the underlying terrain, not about building footprints.

---

## 3. Desired Model

### 3.1 Separation of Concerns

We want a clean separation:

1. **Terrain grid** – “What is this tile?”
   - One `TerrainType` per `(tx, ty)`.
   - Example enum values: `Grass`, `Rock`, `Water`, `Road`.
   - This is the **ground truth** for walkability, autotiling, etc.

2. **Building layer** – “What large sprite sits on top of these tiles?”
   - Rectangles (Townhall, House, Lake, etc.) with positions and sizes in tile units.
   - Used for:
     - Rendering big sprites (Townhall, Lake).
     - Collision (`checkBuildingCollision`).
   - Building presence does **not** automatically change the underlying terrain type.

Autotiling logic (`computeBitmask`) must:

- Use only the terrain grid via `getTileAtGrid`.
- Ignore building geometry entirely.

Collision logic (`checkBuildingCollision`) must:

- Use the building rectangles from `buildings`.
- Optionally also look at `isWalkable(terrain)` if terrain itself is blocking.

### 3.2 Consequences

- `worldedit.json` must describe a **full terrain grid** (every tile).
- We no longer rely on radial fallback rules at runtime.
- Roads become a **terrain concern**: the fact that a tile is `.Road` lives in the terrain grid, not solely in the buildings list.

This also makes the world fully data-driven: what you see in the editor (tiles) is exactly what the game uses for behavior.

---

## 4. Proposed JSON Schema: Add a Tiles Grid

To support a full terrain grid, extend `worldedit.json` with a `tiles` field.

### 4.1 Encoding the terrain grid

We keep the existing structure but add `tiles`:

```/dev/null/worldedit_with_tiles.json#L1-80
{
  "world": {
    "width": 192,
    "height": 320,
    "tiles_x": 12,
    "tiles_y": 20
  },

  // New: terrain grid (20 rows × 12 columns)
  // Encoded as integers that map to TerrainType:
  //   0 = Grass
  //   1 = Rock
  //   2 = Water
  //   3 = Road
  "tiles": [
    [0,0,0,0,0,0,0,0,0,0,0,0],
    [0,0,0,0,0,0,3,3,3,3,3,3],
    [0,0,0,0,0,0,3,0,0,0,0,0]
    // ...
    // (tiles_y rows total; each row has tiles_x entries)
  ],

  "buildings": [
    {
      "type": "Townhall",
      "tile_x": 2,
      "tile_y": 2,
      "width_tiles": 5,
      "height_tiles": 4,
      "sprite_width": 192,
      "sprite_height": 170
    },
    {
      "type": "Lake",
      "tile_x": 2,
      "tile_y": 8,
      "width_tiles": 5,
      "height_tiles": 4,
      "sprite_width": 240,
      "sprite_height": 200
    },
    {
      "type": "House",
      "tile_x": 8,
      "tile_y": 8,
      "width_tiles": 4,
      "height_tiles": 4,
      "sprite_width": 4,
      "sprite_height": 4
    }
  ]
}
```

Notes:

- `tiles` is a 2D array of size `tiles_y × tiles_x`.
- The values are integers that map directly to `shared.TerrainType`’s underlying `u8`:
  - `0` → `TerrainType.Grass`
  - `1` → `TerrainType.Rock`
  - `2` → `TerrainType.Water`
  - `3` → `TerrainType.Road`
- We keep `buildings` to define:
  - Where Townhall/Lake/House/HUD-level objects go.
  - What areas are blocked for player movement.

### 4.2 Roads in tiles vs buildings

Long term, it’s cleaner if:

- Roads are defined **only** in the terrain grid (`tiles`).
- `buildings` no longer include `Road` entries (unless you have a specific reason to keep them).

For migration, it’s fine to:

- Keep `Road` entries in `buildings` while we transition,
- Use them only for debugging or visualization, but not for terrain queries.

---

## 5. World Struct & Accessors

### 5.1 World fields

In `zig-client/src/shared.zig`, the `World` struct should evolve to:

```/dev/null/shared_world_tiles.zig#L1-40
pub const World = struct {
    width: f32,
    height: f32,
    tiles_x: i32,
    tiles_y: i32,
    buildings: []Building,

    // New: flattened terrain grid, length = tiles_x * tiles_y
    tiles: []TerrainType,

    // ...
};
```

Indexing convention for the flattened array:

- `index = ty * tiles_x + tx`
- `0 <= tx < tiles_x`
- `0 <= ty < tiles_y`

### 5.2 `getTileAtGrid`

Implement `getTileAtGrid` using only the terrain grid:

```/dev/null/shared_world_tiles.zig#L42-66
pub fn getTileAtGrid(self: World, tx: i32, ty: i32) TerrainType {
    // Option 1: clamp out-of-bounds and return a default.
    if (tx < 0 or ty < 0 or tx >= self.tiles_x or ty >= self.tiles_y) {
        // Safe default; you can also choose Rock or Water.
        return .Grass;
    }

    const idx: usize = @intCast(ty * self.tiles_x + tx);
    return self.tiles[idx];
}
```

This function is now:

- A pure lookup into the terrain grid.
- Ignorant of buildings and any radial fallback.

### 5.3 `getTileAtPosition`

Convert world coordinates to tile coordinates and delegate:

```/dev/null/shared_world_tiles.zig#L68-100
pub fn getTileAtPosition(self: World, x: f32, y: f32) TerrainType {
    // Clamp to world bounds.
    const clamped_x = std.math.clamp(x, 0, self.width);
    const clamped_y = std.math.clamp(y, 0, self.height);

    // Convert to tile coordinates.
    const tx: i32 = @intFromFloat(
        (clamped_x / self.width) * @as(f32, @floatFromInt(self.tiles_x))
    );
    const ty: i32 = @intFromFloat(
        (clamped_y / self.height) * @as(f32, @floatFromInt(self.tiles_y))
    );

    return self.getTileAtGrid(tx, ty);
}
```

Key differences from the current implementation:

- **No radial distance logic**.
- **No terrain derived from buildings**.
- The terrain grid in `World.tiles` is the single source of truth.

---

## 6. Autotiling with a Real Terrain Grid

With `getTileAtGrid` backed by `tiles`, the autotiling bitmask becomes robust and predictable.

### 6.1 Bitmask computation

The function in `tiles_test.zig`:

```zig-client/src/tiles_test.zig#L35-42
fn computeBitmask(world: shared.World, tx: i32, ty: i32, terrain: shared.TerrainType) u8 {
    var mask: u8 = 0;
    if (world.getTileAtGrid(tx, ty - 1) == terrain) mask |= 1; // Up
    if (world.getTileAtGrid(tx + 1, ty) == terrain) mask |= 2; // Right
    if (world.getTileAtGrid(tx, ty + 1) == terrain) mask |= 4; // Down
    if (world.getTileAtGrid(tx - 1, ty) == terrain) mask |= 8; // Left
    return mask;
}
```

Interpreting the bits:

- Bit 0 (`1`): up (`ty - 1`) is the same terrain.
- Bit 1 (`2`): right (`tx + 1`) is the same terrain.
- Bit 2 (`4`): down (`ty + 1`) is the same terrain.
- Bit 3 (`8`): left (`tx - 1`) is the same terrain.

The result is a value from 0–15 representing which neighbors match. This is then used to index into a `bitmask_map` that chooses which sprite to draw from the tileset (e.g. straight, corner, T-junction, cross, etc.).

Because `getTileAtGrid` now reflects **only** the terrain grid:

- A Townhall can visually occupy multiple tiles, but those tiles still have terrain (e.g. `.Grass`) underneath.
- Roads are explicit `.Road` entries in the terrain grid.
- Roads adjacent to big buildings will generate correct masks, since they’re no longer confused by the building footprint.

### 6.2 Drawing roads

The road drawing code roughly does:

```/dev/null/tiles_test_draw_road.zig#L1-40
if (tile_type == .Road) {
    const mask = computeBitmask(world, tx, ty, .Road);
    const offset = bitmask_map[mask];
    const path_src = tileRect(PATH_START_X + offset[0], PATH_START_Y + offset[1], 16);
    rl.drawTexturePro(tileset, path_src, dest, rl.Vector2{ .x = 0, .y = 0 }, 0, .white);
}
```

The correctness now depends solely on:

1. `world.tiles` being correct (explicit road tiles where needed),
2. `bitmask_map` matching your tileset layout.

The presence of a Townhall, Lake, etc. is irrelevant to the mask; they’re just drawn afterwards on top and used for collision.

---

## 7. Migration Strategy

To avoid breaking the game while refactoring, here is a staged approach.

### 7.1 Phase 1 – Add Tiles, Keep Fallback

- Add the `tiles` field to `World` and `worldedit.json`.
- In `loadFromFile`:
  - If `tiles` exists in JSON:
    - Parse it and fill `World.tiles`.
  - If `tiles` is missing:
    - Allocate `tiles` and fill it using the **current** logic (roads-from-buildings + radial fallback).
- Update `getTileAtGrid` and `getTileAtPosition` to:
  - Prefer `tiles` if present,
  - Or run the old fallback logic if `tiles` is empty.

This keeps existing behavior while allowing new worlds to be fully tile-driven.

### 7.2 Phase 2 – Generate Tiles for Existing Worlds

- For existing `worldedit.json` files that don’t have `tiles`:
  - Temporarily run a tool (or debug code) that:
    - For each `tx, ty`, runs the old `getTileAtGrid` / `getTileAtPosition`.
    - Records the resulting `TerrainType` into a `tiles` array.
  - Save that `tiles` array into the JSON.
- Now all worlds will have an explicit terrain grid that reproduces the old behavior.

### 7.3 Phase 3 – Switch Fully to Tiles

- Once all worlds have explicit `tiles`:
  - Remove or disable the radial fallback logic.
  - Remove terrain-from-buildings logic (especially for roads).
- Ensure:
  - `getTileAtGrid` always reads from `World.tiles`.
  - Autotiling (`computeBitmask`) is purely grid-based.

### 7.4 Phase 4 – Cleanup Roads in Buildings (Optional)

- Decide whether you still need `Road` in `buildings`.
- If not, remove `Road` building entries from JSON and code paths that use them.

---

## 8. Summary

- Autotiling (roads, etc.) requires **knowing the terrain for all tiles** in the map.
- Today, terrain is a mix of:
  - Roads from `buildings`, and
  - A radial fallback for Water/Rock/Grass.
- This breaks down near large buildings like Townhall, where building footprints occupy tiles but do not affect terrain logic consistently.

The proposed direction:

1. **Add a terrain grid** (`tiles`) to `worldedit.json`.
2. Store a `TerrainType` for every tile `(tx, ty)`.
3. Make `World.getTileAtGrid` and `getTileAtPosition` read only from `tiles`.
4. Treat buildings as a separate layer for visuals and collision.
5. Drive `computeBitmask` and road drawing entirely from the terrain grid.

With this design, `worldedit.json` truly “contains all tiles in the map,” and autotiling becomes predictable even when buildings occupy multiple tiles.
