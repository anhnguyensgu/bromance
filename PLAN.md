# Standardize Game to 16x16 Pixel Base Unit

## Overview
Standardize all game measurements to use 16x16 as the base pixel unit, with a centralized constants file using comptime-derived values.

## Design Decisions
- Characters: 16x16 (single tile)
- UI: Align to 16px multiples
- Constants: Comptime-derived from `TILE_SIZE`
- Assets: Use placeholders (skip sprite resizing)

---

## Step 1: Create Central Constants File

**Create:** `game/src/core/constants.zig`

```zig
//! Central game constants for 16x16 pixel grid system.
//! All measurements are derived from TILE_SIZE to ensure consistency.

/// Base tile size in pixels - the fundamental unit
pub const TILE_SIZE: f32 = 16.0;
pub const TILE_SIZE_INT: i32 = 16;

// === Tile Multiples (comptime-derived) ===
pub fn tiles(n: comptime_float) f32 {
    return TILE_SIZE * n;
}

pub fn tilesInt(n: comptime_int) i32 {
    return TILE_SIZE_INT * n;
}

// Common multiples
pub const TILE_HALF: f32 = TILE_SIZE * 0.5;   // 8
pub const TILE_2X: f32 = TILE_SIZE * 2.0;     // 32
pub const TILE_3X: f32 = TILE_SIZE * 3.0;     // 48
pub const TILE_4X: f32 = TILE_SIZE * 4.0;     // 64
pub const TILE_5X: f32 = TILE_SIZE * 5.0;     // 80
pub const TILE_6X: f32 = TILE_SIZE * 6.0;     // 96

// === Character ===
pub const CHARACTER_SIZE: f32 = TILE_SIZE;           // 16
pub const CHARACTER_FRAME_SIZE: f32 = TILE_SIZE;     // 16

// === UI ===
pub const UI_MARGIN: f32 = TILE_2X;                  // 32
pub const MENU_TILE_SIZE: f32 = TILE_3X;             // 48
pub const MENU_ITEM_HEIGHT: f32 = TILE_2X;           // 32
pub const MENU_SPACING: f32 = TILE_SIZE;             // 16
pub const MENU_HEIGHT: f32 = TILE_3X;                // 48

// Modal
pub const MODAL_WIDTH: f32 = TILE_SIZE * 32.0;       // 512
pub const MODAL_HEIGHT: f32 = TILE_SIZE * 20.0;      // 320
pub const MODAL_PADDING: f32 = TILE_SIZE;            // 16
pub const MODAL_HEADER_HEIGHT: f32 = TILE_4X;        // 64

// Sidebar
pub const SIDEBAR_TILE_SIZE: f32 = TILE_3X;          // 48
pub const SIDEBAR_SPACING: f32 = TILE_HALF;          // 8
pub const SIDEBAR_PADDING: f32 = TILE_SIZE;          // 16
pub const SIDEBAR_TOP_PADDING: f32 = TILE_5X;        // 80

// Inventory
pub const INVENTORY_SLOT_SIZE: i32 = TILE_SIZE_INT * 6;  // 96
pub const INVENTORY_SLOT_GAP: i32 = TILE_SIZE_INT / 2;   // 8
pub const INVENTORY_PADDING: i32 = TILE_SIZE_INT;        // 16

// Minimap
pub const MINIMAP_SIZE: i32 = TILE_SIZE_INT * 11;    // 176

// === Helper Functions ===
pub fn alignToGrid(value: f32) f32 {
    return @floor(value / TILE_SIZE) * TILE_SIZE;
}

pub fn pixelsToTiles(pixels: f32) i32 {
    return @intFromFloat(pixels / TILE_SIZE);
}

pub fn tilesToPixels(t: i32) f32 {
    return @as(f32, @floatFromInt(t)) * TILE_SIZE;
}
```

---

## Step 2: Update Character System

**File:** `game/src/character/player.zig`
- Line 79-80: `FRAME_WIDTH/HEIGHT` 32 -> `constants.CHARACTER_FRAME_SIZE`
- Shadow rendering: 32x32 -> constants

---

## Step 3: Update Network Player Size

**Files** (change `PLAYER_SIZE: f32 = 32.0`):
- `game/src/client/udp_client.zig`
- `game/src/client/game_state.zig`
- `game/src/server_main.zig`

---

## Step 4: Update World Screen

**File:** `game/src/screens/world.zig`
- `MINIMAP_SIZE`, `UI_MARGIN_PX`, `MENU_HEIGHT` -> use constants
- `drawOtherPlayer`: Replace hardcoded 32 values

---

## Step 5: Update UI Menu System

**File:** `game/src/ui/menu.zig`

| Field | Before | After (derived) |
|-------|--------|-----------------|
| spacing | 12.0 | TILE_SIZE (16) |
| tile_size | 40.0 | TILE_3X (48) |
| side_padding | 25.0 | TILE_2X (32) |
| top_padding | 30.0 | TILE_2X (32) |
| modal width | 520.0 | TILE_SIZE*32 (512) |
| item_height | 36.0 | TILE_2X (32) |

---

## Step 6: Update Tile System References

**Files** (replace magic `16` with `constants.TILE_SIZE`):
- `game/src/tiles/landscape.zig:38`
- `game/src/tiles/autotile.zig:24`
- `game/src/ui/placement.zig:34`

---

## Files Summary

| File | Action |
|------|--------|
| `game/src/core/constants.zig` | CREATE |
| `game/src/character/player.zig` | MODIFY |
| `game/src/client/udp_client.zig` | MODIFY |
| `game/src/client/game_state.zig` | MODIFY |
| `game/src/server_main.zig` | MODIFY |
| `game/src/screens/world.zig` | MODIFY |
| `game/src/ui/menu.zig` | MODIFY |
| `game/src/tiles/landscape.zig` | MODIFY |
| `game/src/tiles/autotile.zig` | MODIFY |
| `game/src/ui/placement.zig` | MODIFY |
