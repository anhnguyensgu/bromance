# Building Collision System

This document explains how building collision detection works in the game.

## Overview

The building collision system uses **AABB (Axis-Aligned Bounding Box)** collision detection to check for overlaps between the player and buildings. Unlike terrain collision, building collision is direction-independent and checks full rectangular overlap.

**Source**: `game/src/core/world.zig` (lines 313-349)

## AABB Collision Explained

AABB collision detects when two axis-aligned rectangles overlap. Two rectangles overlap when they overlap on **both** the X and Y axes simultaneously.

```
    Overlap on X axis:
    ┌─────────┐
    │    A    │
    │    ┌────┼────┐
    └────┼────┘    │
         │    B    │
         └─────────┘

    No overlap:
    ┌─────────┐
    │    A    │     ┌─────────┐
    │         │     │    B    │
    └─────────┘     └─────────┘
```

## How It Works

### Core Function: `checkBuildingCollision`

```zig
pub fn checkBuildingCollision(self: World, x: f32, y: f32, w: f32, h: f32) bool {
    // Player bounds
    const player_left = x;
    const player_right = x + w;
    const player_top = y;
    const player_bottom = y + h;

    // Calculate tile dimensions in pixels
    const tile_w = self.width / tiles_x;
    const tile_h = self.height / tiles_y;

    for (self.buildings) |building| {
        // Skip walkable buildings
        if (building.building_type == .Road) continue;

        // Convert building tile coords to world pixels
        // ... (see below)

        // AABB overlap test
        const overlaps_x = player_right > building_left and player_left < building_right;
        const overlaps_y = player_bottom > building_top and player_top < building_bottom;

        if (overlaps_x and overlaps_y) return true;
    }
    return false;
}
```

### Step-by-Step Process

1. **Calculate player bounds** in world pixels
2. **Iterate through all buildings**
3. **Skip Road buildings** (they are walkable)
4. **Convert building tile coordinates to world pixels**:
   ```zig
   const building_x = building.tile_x * tile_w;
   const building_y = building.tile_y * tile_h;
   const building_w = building.width_tiles * tile_w;
   const building_h = building.height_tiles * tile_h;
   ```
5. **Clamp building bounds** to world boundaries (prevents edge collisions)
6. **Perform AABB overlap test**

### AABB Overlap Formula

```zig
const overlaps_x = player_right > building_left AND player_left < building_right;
const overlaps_y = player_bottom > building_top AND player_top < building_bottom;

collision = overlaps_x AND overlaps_y;
```

### Visual Breakdown

```
       building_left    building_right
              │               │
              ▼               ▼
         ┌────────────────────┐ ← building_top
         │                    │
         │     BUILDING       │
         │                    │
    ┌────┼───┐                │
    │    │   │                │
    │ P ─┼───┼────────────────┤ ← building_bottom
    │    │   │
    └────┼───┘
         │
    player overlaps building on both axes = COLLISION
```

## Building Data Structure

**Source**: `game/src/core/world.zig` (lines 54-64)

```zig
pub const Building = struct {
    building_type: BuildingType,
    tile_x: i32,           // Position in tile coordinates
    tile_y: i32,
    width_tiles: i32,      // Size in tiles
    height_tiles: i32,
    sprite_x: f32 = 0,     // Sprite rendering data
    sprite_y: f32 = 0,
    sprite_width: f32,
    sprite_height: f32,
};
```

## Building Types

**Source**: `game/src/core/world.zig` (lines 43-51)

```zig
pub const BuildingType = enum {
    Townhall,
    House,
    Shop,
    Farm,
    Lake,
    Road,   // Walkable - skipped in collision
    Tile,
};
```

### Collision Behavior by Type

| Building Type | Solid | Description |
|---------------|-------|-------------|
| Townhall      | Yes   | Central town building |
| House         | Yes   | Residential structure |
| Shop          | Yes   | Commerce building |
| Farm          | Yes   | Agricultural structure |
| Lake          | Yes   | Water feature (building form) |
| Road          | No    | Walkable path |
| Tile          | Yes   | Generic tile structure |

## Coordinate Conversion

Buildings are stored in **tile coordinates** but collision checks use **world pixels**.

```zig
// Tile to world conversion
const tile_w = world.width / world.tiles_x;
const tile_h = world.height / world.tiles_y;

const world_x = tile_x * tile_w;
const world_y = tile_y * tile_h;
```

### Example

```
World: 1600x1600 pixels, 50x50 tiles
Tile size: 32x32 pixels

Building at tile (10, 5) with size 2x3 tiles:
- World position: (320, 160) pixels
- World size: (64, 96) pixels
```

## Edge Handling

Building bounds are clamped to world boundaries to prevent spurious collisions:

```zig
const building_left = @max(0.0, building_x);
const building_top = @max(0.0, building_y);
const building_right = @min(self.width, building_x + building_w);
const building_bottom = @min(self.height, building_y + building_h);
```

This handles cases where buildings are placed at or beyond world edges.

## Why No Direction Parameter?

Unlike terrain collision, building collision doesn't use direction because:

1. **Full AABB is needed** - Buildings are larger multi-tile structures
2. **No sliding optimization needed** - Players don't typically slide along buildings
3. **Simpler logic** - Direction-independent checks are easier to reason about

## Combined Collision Check

Both terrain and building collision are combined in `checkCollisionAll`:

```zig
pub fn checkCollisionAll(self: World, x: f32, y: f32, w: f32, h: f32, direction: MoveDirection) bool {
    return self.checkCollision(x, y, w, h, direction) or
           self.checkBuildingCollision(x, y, w, h);
}
```

## Performance Considerations

- **O(n) complexity** - Iterates through all buildings per check
- **Early exit** - Returns immediately on first collision
- **Road skip** - Walkable buildings are quickly skipped

For large numbers of buildings, consider spatial partitioning (quadtree, grid).

## Related Documentation

- [Terrain Collision](./terrain.md) - Directional corner-sampling for terrain
- [Movement System](../movement/README.md) - How collision integrates with player movement

## Source Files

| File | Responsibility |
|------|----------------|
| `core/world.zig` | `checkBuildingCollision`, `Building` struct, `BuildingType` enum |
| `core/physics.zig` | Re-exports collision functions |
