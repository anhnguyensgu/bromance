# Standardize Game to 16x16 Pixel Base Unit

## Overview
Standardize all game measurements to use 16x16 as the base pixel unit, with a centralized constants file.

## User Decisions
- Characters: Resize from 32x32 to 16x16 (single tile)
- UI: Align to 16px multiples (16, 32, 48, 64, 80, 96...)
- Constants: Centralize in `core/constants.zig`

---

## Implementation Steps

### Step 1: Create Central Constants File
**Create:** `game/src/core/constants.zig`

```zig
pub const TILE_SIZE: f32 = 16.0;
pub const TILE_SIZE_INT: i32 = 16;

// Derived multiples
pub const TILE_2X: f32 = 32.0;
pub const TILE_3X: f32 = 48.0;
pub const TILE_4X: f32 = 64.0;
pub const TILE_6X: f32 = 96.0;
pub const TILE_20X: f32 = 320.0;

// Character
pub const CHARACTER_SIZE: f32 = 16.0;
pub const CHARACTER_FRAME_SIZE: f32 = 16.0;

// UI
pub const UI_MARGIN: f32 = 32.0;
pub const MENU_TILE_SIZE: f32 = 48.0;
pub const MENU_ITEM_HEIGHT: f32 = 32.0;
pub const MENU_SPACING: f32 = 16.0;
pub const MENU_HEIGHT: f32 = 48.0;

// Modal
pub const MODAL_WIDTH: f32 = 512.0;   // 32*16
pub const MODAL_HEIGHT: f32 = 320.0;  // 20*16
pub const MODAL_PADDING: f32 = 16.0;
pub const MODAL_HEADER_HEIGHT: f32 = 64.0;

// Sidebar
pub const SIDEBAR_TILE_SIZE: f32 = 48.0;
pub const SIDEBAR_SPACING: f32 = 8.0;
pub const SIDEBAR_PADDING: f32 = 16.0;
pub const SIDEBAR_TOP_PADDING: f32 = 80.0;

// Inventory
pub const INVENTORY_SLOT_SIZE: u32 = 96;
pub const INVENTORY_SLOT_GAP: u32 = 8;
pub const INVENTORY_PADDING: u32 = 16;

// Minimap
pub const MINIMAP_SIZE: i32 = 176;  // 11*16
```

---

### Step 2: Update Character System (32 -> 16)

**File:** `game/src/character/player.zig`
- Line 79-80: Change `FRAME_WIDTH/HEIGHT` from 32 to use `constants.CHARACTER_FRAME_SIZE`
- Lines ~125-127: Update shadow rendering from 32x32 to 16x16

---

### Step 3: Update Network Player Size

**Files to update** (change `PLAYER_SIZE: f32 = 32.0` to use constants):
- `game/src/client/udp_client.zig:173`
- `game/src/client/game_state.zig:290`
- `game/src/server_main.zig:343`

---

### Step 4: Update World Screen

**File:** `game/src/screens/world.zig`
- Lines 75-78: Update `MINIMAP_SIZE`, `UI_MARGIN_PX`, `MENU_HEIGHT` to use constants
- `drawOtherPlayer` function: Replace hardcoded 32 values with constants

---

### Step 5: Update UI Menu System

**File:** `game/src/ui/menu.zig`

MenuLayout (lines 8-14):
| Field | Before | After |
|-------|--------|-------|
| spacing | 12.0 | 16.0 |
| tile_size | 40.0 | 48.0 |
| side_padding | 25.0 | 32.0 |
| top_padding | 30.0 | 32.0 |

ModalMenuLayout (lines 41-55):
| Field | Before | After |
|-------|--------|-------|
| width | 520.0 | 512.0 |
| padding | 24.0 | 16.0 |
| header_height | 60.0 | 64.0 |
| item_height | 36.0 | 32.0 |
| menu_width | 180.0 | 176.0 |
| body_offset_x | 220.0 | 224.0 |
| body_offset_y | 90.0 | 96.0 |
| back_width | 100.0 | 96.0 |
| back_height | 36.0 | 32.0 |

Sidebar (lines 380-386): Update to use constants

---

### Step 6: Update Inventory Bar

**File:** `game/src/ui/inventory_bar.zig`
- container_padding: 12 -> 16

---

### Step 7: Update Tile System References

**Files** (replace magic 16 with constants):
- `game/src/tiles/landscape.zig:38` - `const ts: f32 = 16.0`
- `game/src/tiles/autotile.zig:24` - `tile_size: i32 = 16`
- `game/src/ui/placement.zig:34` - `grid_size: i32 = 16`

---

### Step 8: Resize Character Sprites (Asset Work)

Character sprites need resizing from 32x32 to 16x16 frames:
```
assets/maincharacter/maincidleback.png
assets/maincharacter/maincidlefront.png
assets/maincharacter/maincidleleft.png
assets/maincharacter/maincidleright.png
assets/maincharacter/maincwalkback.png
assets/maincharacter/maincwalkfront.png
assets/maincharacter/maincwalkleft.png
assets/maincharacter/maincwalkright.png
assets/maincharacter/maincshadow.png
```

Use nearest-neighbor sampling to preserve pixel art:
```bash
convert input.png -filter point -resize 50% output.png
```

---

## Files Summary

| File | Action |
|------|--------|
| `game/src/core/constants.zig` | CREATE |
| `game/src/character/player.zig` | MODIFY (32->16) |
| `game/src/client/udp_client.zig` | MODIFY |
| `game/src/client/game_state.zig` | MODIFY |
| `game/src/server_main.zig` | MODIFY |
| `game/src/screens/world.zig` | MODIFY |
| `game/src/ui/menu.zig` | MODIFY |
| `game/src/ui/inventory_bar.zig` | MODIFY |
| `game/src/tiles/landscape.zig` | MODIFY |
| `game/src/tiles/autotile.zig` | MODIFY |
| `game/src/ui/placement.zig` | MODIFY |
| `assets/maincharacter/*.png` | RESIZE |

---

## Testing
1. Build: `zig build`
2. Run game and verify:
   - Player renders at 16x16 (half previous size)
   - UI elements align to 16px grid
   - Multiplayer sync works correctly
   - Collision detection still functions
