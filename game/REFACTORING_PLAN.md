# Game Architecture Refactoring Plan

**Date:** 2026-01-12
**Based on:** `game_architecture_patterns.md` - Game State + Scenes pattern
**Goal:** Restructure codebase to separate core logic from rendering, enable future multiplayer support

---

## Executive Summary

This refactoring reorganizes the codebase to follow the **Layered Game State** architecture pattern:

1. **Separation of Concerns**: Core game logic (physics, collision, rules) separated from rendering and input
2. **Testability**: Core logic can be unit-tested without raylib/graphics dependencies
3. **Multiplayer Ready**: Core logic can run on both client and server
4. **Clear Dependencies**: No circular imports, predictable dependency flow

---

## Current State Analysis

### Current Structure

```
src/
├── main.zig              # Entry point (good)
├── shared.zig            # ⚠️ 570+ lines: World + collision + DRAWING
├── state.zig             # ⚠️ UI-only state (confusing name)
├── network.zig           # Network protocol (fine)
│
├── character/player.zig  # Player entity
├── client/
│   ├── game_state.zig    # Networked client state
│   ├── http_client.zig
│   └── udp_client.zig
├── core/                 # ⚠️ Mixed: assets + scene management
│   ├── assets.zig
│   ├── context.zig
│   ├── scene_action.zig
│   └── scene_manager.zig
├── screens/              # ✅ Good pattern
│   ├── login.zig
│   └── world.zig
├── tiles/                # Tile rendering (should be client/)
├── ui/                   # UI components (should be client/ui/)
├── plot/                 # Plot system (mixes data + rendering)
├── map/                  # Map editing (tooling)
├── movement/             # Movement commands
├── grpc/                 # External dependency
└── db/                   # External dependency
```

### Issues Identified

| # | Issue | Impact | Anti-pattern |
|---|-------|--------|--------------|
| 1 | `shared.zig` mixes World data with `drawGrassBackground()` | Can't unit test core logic | #5: Mixing Core and Rendering |
| 2 | Three different "GameStates" | Confusing, unclear ownership | - |
| 3 | No pure `core/` module for game logic | Can't run headless/server | - |
| 4 | Rendering scattered across `tiles/`, `plot/`, `screens/` | Hard to maintain | - |
| 5 | No `game/` folder for game objects | Game entities mixed with rendering | - |

---

## Target Structure

```
src/
├── main.zig              # Entry point, game loop, App struct
│
├── core/                 # ⭐ Pure game logic (no raylib)
│   ├── mod.zig           # Export: world, physics, rules
│   ├── world.zig         # World state (from shared.zig)
│   ├── entity.zig        # Entity definitions
│   ├── physics.zig       # Collision, movement rules
│   └── rules.zig         # Game rules (damage, interactions)
│
├── client/               # ⭐ Rendering & input (raylib only)
│   ├── mod.zig           # Export: renderer, camera, input, ui
│   ├── renderer.zig      # ⭐ NEW: Extract all drawing
│   ├── camera.zig        # Camera logic
│   ├── input.zig         # Input handling
│   ├── game_state.zig    # Networked state (keep)
│   ├── http_client.zig   # Keep
│   ├── udp_client.zig    # Keep
│   └── ui/               # Move from root ui/
│       ├── hud.zig
│       ├── menu.zig
│       ├── inventory_bar.zig
│       ├── placement.zig
│       ├── layout.zig
│       ├── widgets.zig
│       └── panels/
│
├── assets/               # ⭐ Asset management (from core/assets.zig)
│   ├── mod.zig
│   ├── sprite_sheet.zig  # SpriteSheet struct
│   ├── tiles.zig         # Tile asset IDs
│   ├── characters.zig    # Character asset IDs
│   └── ui.zig            # UI asset IDs
│
├── scenes/               # ⭐ Game scenes (keep mostly as-is)
│   ├── mod.zig           # Export Scene, SceneManager
│   ├── menu.zig          # MenuScene (from login.zig)
│   ├── game.zig          # GameState/WorldScreen
│   └── ui_state.zig      # Move from root state.zig
│
├── game/                 # ⭐ Game objects
│   ├── mod.zig           # Export: player, enemies
│   ├── player.zig        # Move from character/player.zig
│   └── camera.zig        # Game-side camera state
│
├── plot/                 # ⭐ Split: data to core/, rendering to client/
│   ├── plot.zig          # Keep data structure
│   └── (plot_ui.zig → client/ui/plot.zig)
│
├── tiles/                # ⭐ Split: data to core/, rendering to client/
│   ├── (move to assets/ or client/)
│
├── movement/             # Keep or merge into core/physics.zig
│
└── util/                 # ⭐ Shared utilities
    ├── mod.zig
    └── math.zig
```

### Dependency Flow

```
util ← core ← game ← scenes
         ↑              ↑
       assets ←─────── client
                        ↑
                      ui
```

---

## Refactoring Steps

### Phase 0: Refactor Assets to Enum-based Pattern (⭐ DO FIRST)

**Why First:** This is a self-contained change with immediate benefits. It improves asset management and doesn't depend on other phases.

**Goal:** Replace `StringHashMap`-based `AssetCache` with enum-based `Assets` using `std.EnumArray`.

**Pattern Source:** `/Users/anhnguyen/project/zig/zig-learning/raylib-learn/src/assets.zig`

#### Benefits

| Current (AssetCache) | New (Enum-based) |
|---------------------|------------------|
| `StringHashMap` (runtime) | Direct field access (compile-time) |
| String keys (typo-prone) | Enum values (type-safe) |
| Runtime allocations | Stack-allocated |
| `getTexture("path.png")` | `tile_assets.spring_tiles` |
| Magic number indices | Named tile enums: `.grass`, `.water` |
| No sprite metadata | `SpriteSheet` with dimensions |
| `draw(texture, 5, x, y)` | `spring_tiles.draw(.grass, x, y)` |

#### Step 0.1: Create `assets/sprite_sheet.zig`

**New file:** `src/assets/sprite_sheet.zig`

```zig
const std = @import("std");
const rl = @import("raylib");

/// Generic sprite sheet with frame dimensions and helper methods
pub const SpriteSheet = struct {
    texture: rl.Texture2D,
    frame_w: u32,
    frame_h: u32,
    spacing: u32,
    columns: u32,

    const Self = @This();

    pub fn init(path: [:0]const u8, frame_w: u32, frame_h: u32, spacing: u32, columns: u32) !Self {
        return .{
            .texture = try rl.loadTexture(path),
            .frame_w = frame_w,
            .frame_h = frame_h,
            .spacing = spacing,
            .columns = columns,
        };
    }

    pub fn deinit(self: *Self) void {
        rl.unloadTexture(self.texture);
    }

    /// Get source rectangle for a sprite index
    pub fn getSourceRect(self: Self, index: u32) rl.Rectangle {
        const col: i32 = @intCast(index % self.columns);
        const row: i32 = @intCast(index / self.columns);
        const stride_x: i32 = @intCast(self.frame_w + self.spacing);
        const stride_y: i32 = @intCast(self.frame_h + self.spacing);

        return .{
            .x = @floatFromInt(col * stride_x),
            .y = @floatFromInt(row * stride_y),
            .width = @floatFromInt(self.frame_w),
            .height = @floatFromInt(self.frame_h),
        };
    }

    /// Draw sprite at position with original size
    pub fn draw(self: Self, index: u32, x: i32, y: i32) void {
        const src = self.getSourceRect(index);
        const dest = rl.Vector2{ .x = @floatFromInt(x), .y = @floatFromInt(y) };
        rl.drawTextureRec(self.texture, src, dest, .white);
    }

    /// Draw sprite scaled to destination rectangle
    pub fn drawScaled(self: Self, index: u32, dest_rect: rl.Rectangle) void {
        const src = self.getSourceRect(index);
        rl.drawTexturePro(self.texture, src, dest_rect, .{ .x = 0, .y = 0 }, 0, .white);
    }
};
```

#### Step 0.2: Create `assets/tiles.zig`

**New file:** `src/assets/tiles.zig`

```zig
const std = @import("std");
const rl = @import("raylib");
const SpriteSheet = @import("sprite_sheet.zig").SpriteSheet;

/// Spring tileset tile indices (type-safe)
pub const SpringTile = enum(u32) {
    grass = 0,
    grass_flowers = 1,
    dirt = 2,
    stone_path = 3,
    water = 4,
    sand = 5,
    // Add more tiles as they're identified in the sprite sheet
};

/// Dungeon tileset tile indices (type-safe)
pub const DungeonTile = enum(u32) {
    floor = 0,
    wall = 1,
    door = 2,
    // Add more tiles as needed
};

/// Typed Spring tileset wrapper
pub const SpringTileSheet = struct {
    sheet: SpriteSheet,

    pub fn draw(self: SpringTileSheet, tile: SpringTile, x: i32, y: i32) void {
        self.sheet.draw(@intFromEnum(tile), x, y);
    }

    pub fn drawScaled(self: SpringTileSheet, tile: SpringTile, dest_rect: rl.Rectangle) void {
        self.sheet.drawScaled(@intFromEnum(tile), dest_rect);
    }

    pub fn getSourceRect(self: SpringTileSheet, tile: SpringTile) rl.Rectangle {
        return self.sheet.getSourceRect(@intFromEnum(tile));
    }
};

/// Typed Dungeon tileset wrapper
pub const DungeonTileSheet = struct {
    sheet: SpriteSheet,

    pub fn draw(self: DungeonTileSheet, tile: DungeonTile, x: i32, y: i32) void {
        self.sheet.draw(@intFromEnum(tile), x, y);
    }

    pub fn drawScaled(self: DungeonTileSheet, tile: DungeonTile, dest_rect: rl.Rectangle) void {
        self.sheet.drawScaled(@intFromEnum(tile), dest_rect);
    }

    pub fn getSourceRect(self: DungeonTileSheet, tile: DungeonTile) rl.Rectangle {
        return self.sheet.getSourceRect(@intFromEnum(tile));
    }
};

/// Tile sheet asset IDs (compile-time safe)
pub const TileSheetId = enum {
    spring_tiles,
    dungeon,
    forest,
    castle,
};

/// Main Assets struct for tile sheets
pub const TileAssets = struct {
    spring_tiles: SpringTileSheet,
    // dungeon: DungeonTileSheet,
    // Add more typed sheets as needed

    pub fn init() !TileAssets {
        return .{
            .spring_tiles = .{
                .sheet = try SpriteSheet.init("assets/spring.png", 16, 16, 1, 12),
            },
            // .dungeon = .{
            //     .sheet = try SpriteSheet.init("assets/dungeon.png", 16, 16, 1, 12),
            // },
        };
    }

    pub fn deinit(self: *TileAssets) void {
        self.spring_tiles.sheet.deinit();
        // self.dungeon.sheet.deinit();
    }
};
```

#### Step 0.3: Create `assets/characters.zig`

**New file:** `src/assets/characters.zig`

```zig
const std = @import("std");
const rl = @import("raylib");
const SpriteSheet = @import("sprite_sheet.zig").SpriteSheet;

/// Main character animation frames (type-safe)
pub const MainCharacterFrame = enum(u32) {
    idle_down = 0,
    walk_down_1 = 1,
    walk_down_2 = 2,
    idle_up = 3,
    walk_up_1 = 4,
    walk_up_2 = 5,
    idle_left = 6,
    walk_left_1 = 7,
    walk_left_2 = 8,
    idle_right = 9,
    walk_right_1 = 10,
    walk_right_2 = 11,
};

/// Typed Main Character sprite sheet wrapper
pub const MainCharacterSheet = struct {
    sheet: SpriteSheet,

    pub fn draw(self: MainCharacterSheet, frame: MainCharacterFrame, x: i32, y: i32) void {
        self.sheet.draw(@intFromEnum(frame), x, y);
    }

    pub fn drawScaled(self: MainCharacterSheet, frame: MainCharacterFrame, dest_rect: rl.Rectangle) void {
        self.sheet.drawScaled(@intFromEnum(frame), dest_rect);
    }

    pub fn getSourceRect(self: MainCharacterSheet, frame: MainCharacterFrame) rl.Rectangle {
        return self.sheet.getSourceRect(@intFromEnum(frame));
    }
};

pub const CharacterAssets = struct {
    main_character: MainCharacterSheet,

    pub fn init() !CharacterAssets {
        return .{
            .main_character = .{
                .sheet = try SpriteSheet.init("assets/characters/main.png", 32, 32, 0, 4),
            },
        };
    }

    pub fn deinit(self: *CharacterAssets) void {
        self.main_character.sheet.deinit();
    }
};
```

#### Step 0.4: Create `assets/mod.zig`

**New file:** `src/assets/mod.zig`

```zig
// Core types
pub const SpriteSheet = @import("sprite_sheet.zig").SpriteSheet;

// Tile assets
pub const TileAssets = @import("tiles.zig").TileAssets;
pub const SpringTile = @import("tiles.zig").SpringTile;
pub const DungeonTile = @import("tiles.zig").DungeonTile;
pub const SpringTileSheet = @import("tiles.zig").SpringTileSheet;
pub const DungeonTileSheet = @import("tiles.zig").DungeonTileSheet;

// Character assets
pub const CharacterAssets = @import("characters.zig").CharacterAssets;
pub const MainCharacterFrame = @import("characters.zig").MainCharacterFrame;
pub const MainCharacterSheet = @import("characters.zig").MainCharacterSheet;
```

#### Step 0.5: Update `screens/world.zig` (and other consumers)

**Before:**
```zig
const assets = @import("../core/assets.zig");
var asset_cache = assets.AssetCache.init(allocator);
defer asset_cache.deinit();
const grass_tex = try asset_cache.getTexture("assets/grass.png");
```

**After:**
```zig
const assets = @import("../assets/mod.zig");
var tile_assets = try assets.TileAssets.init();
defer tile_assets.deinit();
// Type-safe, self-documenting tile drawing
tile_assets.spring_tiles.draw(.grass, x, y);
tile_assets.spring_tiles.draw(.water, x2, y2);
```

#### Step 0.6: Migrate Existing Tile Calls

**Files to update:**
- `screens/world.zig` - Main game rendering
- `tiles/sheets.zig` - Old pattern (deprecate after migration)
- `ui/` - Any UI tile usage

**Migration pattern:**
```zig
// OLD - String keys, magic numbers, runtime lookups
const grass_frames = shared.Frames.SpringTileGrass(texture, 0, 0);
shared.drawLandscapeTile(grass_frames, x, y);

// NEW - Type-safe enums, compile-time checked
tile_assets.spring_tiles.draw(.grass, x, y);

// Multiple tiles example
tile_assets.spring_tiles.draw(.grass, x, y);
tile_assets.spring_tiles.draw(.water, x + 16, y);
tile_assets.spring_tiles.draw(.dirt, x, y + 16);
```

#### Step 0.7: Deprecate Old Files (After Testing)

**Delete after migration complete:**
- `core/assets.zig` → Replaced by enum-based assets

**Keep for compatibility (optional):**
- `tiles/sheets.zig` → Mark as deprecated, migrate consumers

### Phase 1: Foundation (Low Risk)

#### Step 1.1: Create `core/mod.zig`
**File:** `src/core/mod.zig`
```zig
pub const World = @import("world.zig").World;
pub const Building = @import("world.zig").Building;
pub const BuildingType = @import("world.zig").BuildingType;

pub const Physics = @import("physics.zig").Physics;
pub const Rules = @import("rules.zig").Rules;
```

#### Step 1.2: Create `util/mod.zig`
**File:** `src/util/mod.zig`
```zig
pub const math = @import("math.zig");
```

#### Step 1.3: Create `assets/mod.zig`
**Move:** `src/core/assets.zig` → `src/assets/mod.zig`

---

### Phase 2: Split Core from Rendering (High Impact)

#### Step 2.1: Create `core/world.zig` (Logic Only)
**Source:** Extract from `shared.zig`

**What to include:**
- `World` struct definition
- `Building`, `BuildingType` enums
- `getTileAtPosition()` - pure logic
- `isWalkable()` - pure logic
- `checkCollision()` - pure logic
- `checkBuildingCollision()` - pure logic
- `tileToWorldX/Y()`, `worldToTileX/Y()`
- `getPlotAtTile()`, `getPlotAtPosition()`, `getPlotById()`
- `Room`, `PlayerState` (test structures)

**What to REMOVE:**
- ❌ `drawGrassBackground()` → move to `client/renderer.zig`
- ❌ Any imports of `rl = @import("raylib")`

#### Step 2.2: Create `client/renderer.zig` (NEW)
**Source:** Extract rendering from `shared.zig`, `tiles/`, `plot/`

**Contents:**
```zig
const core = @import("../core/mod.zig");
const assets = @import("../assets/mod.zig");

pub fn drawGrassBackground(grass: assets.Frames, world: *const core.World) void { ... }
pub fn drawWorld(world: *const core.World, assets: *const Assets) void { ... }
pub fn drawBuilding(building: core.Building, ...) void { ... }
```

#### Step 2.3: Create `core/physics.zig`
**Source:** Extract collision logic from `shared.zig`

**Contents:**
```zig
pub const Physics = struct {
    pub fn checkEntityCollision(...) bool { ... }
    pub fn resolveMovement(...) void { ... }
};
```

#### Step 2.4: Create `core/rules.zig` (Placeholder)
**Future:** Game rules like damage, interactions

```zig
pub const Rules = struct {
    // Placeholder for future game rules
};
```

---

### Phase 3: Reorganize Game Objects

#### Step 3.1: Create `game/mod.zig`
**File:** `src/game/mod.zig`
```zig
pub const Player = @import("player.zig").Character;
pub const Camera = @import("camera.zig").Camera;
```

#### Step 3.2: Move `character/player.zig` → `game/player.zig`
**Action:** Move file, update imports

**Update:** All files that import `character/player.zig` to use `game/player.zig`

#### Step 3.3: Extract camera logic to `game/camera.zig`
**Source:** Extract from `screens/world.zig`

**Contents:**
```zig
pub const Camera = struct {
    // Camera state and update logic
    pub fn followTarget(...) void { ... }
    pub fn clampToWorld(...) void { ... }
};
```

---

### Phase 4: Reorganize Rendering

#### Step 4.1: Move `ui/` → `client/ui/`
**Action:** Move entire directory

**Update imports:**
- `@import("../ui/menu.zig")` → `@import("ui/menu.zig")`
- From `screens/`, `client/`, etc.

#### Step 4.2: Move `tiles/` → `client/tiles/` or `assets/tiles/`
**Decision point:** Are these assets or rendering helpers?

**Recommendation:** Split
- `tiles/sheets.zig` → `assets/sheets.zig` (asset loading)
- `tiles/landscape.zig`, `tiles/layer.zig` → `client/renderer.zig` (drawing)

#### Step 4.3: Split `plot/`
**Move:** `plot/plot_ui.zig` → `client/ui/plot.zig`
**Keep:** `plot/plot.zig` in place (or move to `game/plot.zig`?)

---

### Phase 5: Consolidate State

#### Step 5.1: Rename `state.zig` → `scenes/ui_state.zig`
**Reason:** It's UI state, not game state

**Rename:** `GameState` → `UIState` (to avoid confusion)

#### Step 5.2: Clarify state ownership
- `scenes/ui_state.zig` → UI state (stamina, hearts, inventory display)
- `client/game_state.zig` → Networked client state (snapshots, reconciliation)
- `game/player.zig` → Player entity state
- `core/world.zig` → World state

---

### Phase 6: Update All Imports

#### Step 6.1: Update `main.zig`
```zig
// Old
const shared = @import("shared.zig");
const assets = @import("core/assets.zig");

// New
const core = @import("core/mod.zig");
const assets = @import("assets/mod.zig");
const client = @import("client/mod.zig");
const scenes = @import("scenes/mod.zig");
```

#### Step 6.2: Update `screens/world.zig`
```zig
// Old
const shared = @import("../shared.zig");

// New
const core = @import("../core/mod.zig");
const client = @import("../client/mod.zig");
const assets = @import("../assets/mod.zig");
```

#### Step 6.3: Update `screens/login.zig`
```zig
// Old
const shared = @import("../shared.zig");

// New
const scenes = @import("mod.zig");
```

#### Step 6.4: Update `client/game_state.zig`
```zig
// Old
const shared = @import("../shared.zig");

// New
const core = @import("../core/mod.zig");
```

---

## File Changes Summary

### Phase 0 New Files (Assets Refactoring)
```
src/assets/sprite_sheet.zig   # SpriteSheet struct with helper methods
src/assets/tiles.zig          # TileSheetId enum, TileAssets struct
src/assets/characters.zig     # CharacterSheetId enum, CharacterAssets struct
src/assets/mod.zig            # Export all asset modules
```

### Phase 1-8 New Files (12)
```
src/core/mod.zig           # Core exports
src/core/world.zig         # Extracted from shared.zig
src/core/physics.zig       # Extracted from shared.zig
src/core/rules.zig         # New placeholder
src/client/mod.zig         # Client exports
src/client/renderer.zig    # New: all rendering
src/game/mod.zig           # Game exports
src/game/camera.zig        # Extracted from screens/world.zig
src/util/mod.zig           # Utilities
src/util/math.zig          # Math helpers
src/scenes/ui_state.zig    # Renamed from state.zig
```

### Phase 0 Deleted Files
```
src/core/assets.zig        # Replaced by enum-based assets
```

### Phase 1-8 Moved Files (8)
```
character/player.zig     → game/player.zig
ui/                      → client/ui/
tiles/sheets.zig         → assets/sheets.zig (or deprecated)
tiles/*.zig (rendering)  → client/renderer.zig
plot/plot_ui.zig         → client/ui/plot.zig
state.zig                → scenes/ui_state.zig
movement/command.zig     → core/physics.zig or keep
```

### Phase 1-8 Deleted Files (1)
```
shared.zig                # After extraction complete
```

### Modified Files (Major Changes)
```
screens/world.zig         # Update imports, migrate to new assets
screens/login.zig         # Update imports
main.zig                  # Update imports
client/game_state.zig     # Update imports
core/scene_manager.zig    # May need minor updates
```

---

## Testing Strategy

### After Each Phase

1. **Compile Check:** `zig build`
2. **Run Tests:** `zig build test`
3. **Manual Test:** Run game, verify rendering works

### Specific Tests

| Test | Verify |
|------|--------|
| `zig build` | No compilation errors |
| `zig build test` | All unit tests pass |
| Run game | World renders correctly |
| Collision | Player collision still works |
| Network | Client can connect to server |

---

## Rollback Plan

If refactoring breaks something critical:

1. **Git checkpoint after each phase**
   ```bash
   git commit -m "Phase N: description"
   ```

2. **Revert to last working phase**
   ```bash
   git revert HEAD
   ```

3. **Keep `shared.zig` until all imports updated**
   - Don't delete until `core/world.zig` is working

---

## Success Criteria

✅ **Core logic has no raylib dependency**
```bash
grep -r "raylib" src/core/
# Should return empty
```

✅ **Can unit test collision without graphics**
```zig
test "collision detection" {
    var world = core.World.init(...);
    try testing.expect(world.checkCollision(...));
}
```

✅ **Clear dependency flow**
```
util ← core ← game ← scenes
  assets ← client
```

✅ **No more "shared.zig" dumping ground**

✅ **All imports use explicit modules**
```zig
const core = @import("core/mod.zig");
const client = @import("client/mod.zig");
```

---

## Implementation Order

1. ✅ Create this plan
2. ⏳ **Phase 0:** **Refactor Assets to Enum-based pattern** (DO FIRST)
3. ⏳ **Phase 1:** Create new directory structure (mod.zig files)
4. ⏳ **Phase 2:** Extract `core/world.zig` from `shared.zig`
5. ⏳ **Phase 3:** Create `client/renderer.zig`
6. ⏳ **Phase 4:** Move game objects to `game/`
7. ⏳ **Phase 5:** Reorganize `ui/` and `tiles/`
8. ⏳ **Phase 6:** Update all imports
9. ⏳ **Phase 7:** Delete `shared.zig`
10. ⏳ **Phase 8:** Final testing and cleanup

---

## Open Questions

1. **`movement/command.zig`**: Keep as-is or merge into `core/physics.zig`?
2. **`plot/plot.zig`**: Is it core data or game object?
3. **`tiles/`**: Split between `assets/` and `client/`?
4. **Camera**: Should it be in `game/` or `client/`?
5. **Minimap**: Client rendering or game logic?

---

## References

- `game_architecture_patterns.md` - Source architecture patterns
- Current codebase in `game/src/`
- Scene system already follows pattern well (`screens/`, `core/scene_manager.zig`)

