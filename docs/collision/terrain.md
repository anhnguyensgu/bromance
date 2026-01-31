# Terrain Collision System

This document explains how terrain collision detection works in the game.

## Overview

The terrain collision system uses **directional corner-sampling** to detect collisions with non-walkable terrain (Water, Rock). This approach avoids "sticky" collisions when players slide along edges.

**Source**: `game/src/core/world.zig` (lines 275-306)

## Why Directional Sampling?

Traditional collision checks all 4 corners of the player hitbox, but this causes **"sticky" collisions** - when sliding along a wall, the player gets stuck because corners perpendicular to movement keep detecting the obstacle.

```
Traditional (sticky):          Directional (smooth):
┌───────┐                      ┌───────┐
│ X   X │ ← checks ALL         │     X │ ← only checks
│       │    4 corners         │       │   leading edge
│ X   X │                      │     X │   (moving right)
└───────┘                      └───────┘
```

## How It Works

### Core Function: `checkCollision`

```zig
pub fn checkCollision(self: World, x: f32, y: f32, w: f32, h: f32, direction: MoveDirection) bool {
    const left = x;
    const right = x + w;      // x + 32 (player width)
    const top = y;
    const bottom = y + h;     // y + 32 (player height)

    switch (direction) {
        .Up    => // check top-left & top-right corners
        .Down  => // check bottom-left & bottom-right corners
        .Left  => // check top-left & bottom-left corners
        .Right => // check top-right & bottom-right corners
    }
}
```

### Direction-Based Corner Checks

| Direction | Corners Checked | Description |
|-----------|-----------------|-------------|
| Up        | top-left, top-right | Leading edge at top |
| Down      | bottom-left, bottom-right | Leading edge at bottom |
| Left      | top-left, bottom-left | Leading edge on left |
| Right     | top-right, bottom-right | Leading edge on right |

### Visual Example - Moving Right

```
Player moving RIGHT →

    ┌────────────────────┐
    │                  ╔═╗│  ← top-right checked
    │      PLAYER      ║ ││
    │                  ╠═╣│
    │                  ║ ││
    │                  ╚═╝│  ← bottom-right checked
    └────────────────────┘
                        ↑
                   Leading edge
```

## Tile Lookup System

### Function: `getTileAtPosition`

**Source**: `game/src/core/world.zig` (lines 239-265)

When checking a corner position, the system converts world coordinates to tile coordinates:

```zig
// World position → Tile coordinates
const tx = (clamped_x / world_width) * tiles_x;
const ty = (clamped_y / world_height) * tiles_y;
```

### Terrain Determination

The terrain type is determined in this order:

1. **Check for Road buildings** - If a Road building exists at the tile position, return `Road`
2. **Distance-based generation** - Calculate distance from world center:
   - `dist² < 16` → Water (center lake)
   - `dist² < 25` → Rock (ring around lake)
   - Otherwise → Grass

### World Layout

```
        Grass area (walkable)
    ┌─────────────────────────┐
    │                         │
    │    Rock ring (solid)    │
    │   ┌───────────────┐     │
    │   │               │     │
    │   │  Water (solid)│     │
    │   │    center     │     │
    │   │               │     │
    │   └───────────────┘     │
    │                         │
    └─────────────────────────┘
```

## Terrain Types

Defined in `game/src/core/terrain.zig`:

```zig
pub const TerrainType = enum(u8) {
    Grass = 0,    // Walkable
    Rock = 1,     // Solid - not walkable
    Water = 2,    // Solid - not walkable
    Road = 3,     // Walkable
};
```

### Walkability

```zig
pub fn isWalkable(terrain: TerrainType) bool {
    return terrain == .Grass or terrain == .Road;
}
```

| Terrain | Walkable | Description |
|---------|----------|-------------|
| Grass   | Yes      | Default walkable terrain |
| Road    | Yes      | Player-built paths |
| Rock    | No       | Solid barrier around water |
| Water   | No       | Central lake obstacle |

## Player Hitbox

- **Size**: 32x32 pixels (`PLAYER_SIZE = 32.0`)
- **Defined in**:
  - `client/udp_client.zig:173`
  - `client/game_state.zig:314`
  - `server_main.zig:344`

## Key Benefits

The directional sampling approach provides:

1. **Smooth sliding** - Players can slide along walls without getting stuck
2. **Intuitive movement** - Moving up past a rock on your left won't block you
3. **Performance** - Only 2 corner checks per collision test instead of 4
4. **Predictable behavior** - Collision only triggers when moving into an obstacle

## Related Documentation

- [Building Collision](./building.md) - AABB-based collision for structures
- [Movement System](../movement/README.md) - How collision integrates with player movement

## Source Files

| File | Responsibility |
|------|----------------|
| `core/world.zig` | `checkCollision`, `getTileAtPosition`, `isWalkable` |
| `core/terrain.zig` | `TerrainType` enum definition |
| `core/physics.zig` | Re-exports collision functions |
