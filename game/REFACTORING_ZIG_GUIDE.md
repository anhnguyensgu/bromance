# Zig Implementation Guide for Game Architecture Refactoring

**Date:** 2026-01-12
**Zig Version:** 0.15.1
**Purpose:** Zig-specific considerations for the game architecture refactoring

---

## Quick Start

```bash
# Pre-flight checks
zig version          # Should be 0.15.1
zig build            # Ensure clean build
zig build test       # Ensure tests pass

# Create checkpoint
git add -A && git commit -m "Before refactoring: working state"
```

---

## Module Strategy for New Structure

### Current build.zig Modules

```zig
// Current modules in build.zig
- shared (src/shared.zig)         // ⚠️ Needs splitting
- grpc (src/grpc/client.zig)
- zig_client_root (src/main.zig)
- zig_server_root (src/server_main.zig)
- db/migrations (src/db/migrations.zig)
```

### Two Approaches

**Option A: Keep using build.zig modules** (recommended for later)
- Add new modules as you create `core/`, `client/`, `assets/`
- More explicit, better for complex dependencies

**Option B: Use file-based imports only** (recommended for now)
- Simpler, but loses build.zig's dependency tracking
- Better for smaller projects

**Recommendation:** Start with **Option B** (file-based) during refactoring. Add build.zig modules later once structure is stable.

---

## Why `mod.zig` in Zig?

### The Problem

Zig doesn't have Java-style `package` directories. You must import specific files:

```zig
// ❌ This doesn't work
const stuff = @import("my_folder");  // Error: not a file

// ✅ Must import a specific file
const stuff = @import("my_folder/mod.zig");  // Works!
```

### The `mod.zig` Pattern

`mod.zig` acts as a **public API entry point** for a directory:

```
core/
├── mod.zig          ← Public exports (what other files see)
├── world.zig        ← Internal implementation
├── physics.zig      ← Internal implementation
└── rules.zig        ← Internal implementation
```

**Example:**

```zig
// core/mod.zig - The public face of core/
pub const World = @import("world.zig").World;
pub const Building = @import("world.zig").Building;
pub const Physics = @import("physics.zig").Physics;
pub const Rules = @import("rules.zig").Rules;

// Usage elsewhere:
const core = @import("core/mod.zig");
const world = core.World;  // Clean access
```

### Benefits

| Benefit | Description |
|---------|-------------|
| One import | `const core = @import("core/mod.zig")` |
| Clean API | Hide internal details from consumers |
| Easy refactoring | Move internals around, external imports stay same |
| Build.zig mapping | Maps cleanly to Zig's module system |

---

## Module Dependency Graph (Target)

```
core (no external deps)
  ↑
  ├─→ game
  │     ↑
  │     └─→ scenes ─→ client ─→ raylib
  │                      ↑
  └──────────────────────┴─→ assets
```

---

## Handling the `shared` Module

### Current Issue

```zig
// build.zig line 63-68
const shared_mod = b.addModule("shared", .{
    .root_source_file = b.path("src/shared.zig"),
    .target = target,
    .optimize = optimize,
});
shared_mod.addImport("raylib", raylib);  // ⚠️ Core logic shouldn't import raylib!
```

`shared` module mixes core logic with raylib rendering.

### Solution: Split `shared` into separate modules

```zig
// In build.zig (after refactoring)
const core_mod = b.addModule("core", .{
    .root_source_file = b.path("src/core/mod.zig"),
    .target = target,
    .optimize = optimize,
    // NO raylib import!
});

const client_mod = b.addModule("client", .{
    .root_source_file = b.path("src/client/mod.zig"),
    .target = target,
    .optimize = optimize,
});
client_mod.addImport("raylib", raylib);  // Only client imports raylib
client_mod.addImport("core", core_mod);  // Client depends on core
```

---

## Refactoring Phases (Zig-Specific)

### Phase 0: Pre-Flight Checks

```bash
# 1. Ensure everything compiles
zig build

# 2. Ensure tests pass
zig build test

# 3. Create checkpoint
git add -A && git commit -m "Before refactoring: working state"
```

### Phase 1: Create New Module Roots (File-Based)

**Don't modify build.zig yet.** Create `mod.zig` files:

```zig
// src/core/mod.zig
pub const World = @import("world.zig").World;
pub const Building = @import("world.zig").Building;
pub const BuildingType = @import("world.zig").BuildingType;

// src/client/mod.zig
pub const Renderer = @import("renderer.zig").Renderer;
pub const Camera = @import("camera.zig").Camera;
```

### Phase 2: Extract `core/world.zig` from `shared.zig`

**Key principle:** `core/world.zig` must compile without raylib:

```zig
// ❌ BAD - imports raylib
const rl = @import("raylib");

// ✅ GOOD - pure Zig
const std = @import("std");
const MovementCommand = @import("../movement/command.zig").MovementCommand;
```

**Verification step:**
```bash
# This should work (no raylib dependency)
zig test src/core/world.zig
```

### Phase 3: Create `client/renderer.zig`

Extract rendering from `shared.zig`, `tiles/`, `plot/`:

```zig
// src/client/renderer.zig
const std = @import("std");
const rl = @import("raylib");
const core = @import("../core/mod.zig");

pub fn drawGrassBackground(grass: anytype, world: *const core.World) void {
    // Rendering logic here
}
```

### Phase 4: Update Imports Incrementally

**Update one file at a time, compile after each:**

```bash
# After updating screens/world.zig
zig build  # Should still compile
```

### Phase 5: Update build.zig (Final Step)

Once structure is stable and all imports work:

```zig
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const raylib_dep = b.dependency("raylib_zig", .{
        .target = target,
        .optimize = optimize,
    });
    const raylib = raylib_dep.module("raylib");
    const raylib_artifact = raylib_dep.artifact("raylib");

    // ⭐ NEW: Core module (no raylib!)
    const core_mod = b.addModule("core", .{
        .root_source_file = b.path("src/core/mod.zig"),
        .target = target,
        .optimize = optimize,
    });

    // ⭐ NEW: Client module (has raylib)
    const client_mod = b.addModule("client", .{
        .root_source_file = b.path("src/client/mod.zig"),
        .target = target,
        .optimize = optimize,
    });
    client_mod.addImport("raylib", raylib);
    client_mod.addImport("core", core_mod);

    // ⭐ NEW: Assets module
    const assets_mod = b.addModule("assets", .{
        .root_source_file = b.path("src/assets/mod.zig"),
        .target = target,
        .optimize = optimize,
    });
    assets_mod.addImport("raylib", raylib);

    // Update existing modules to use new structure
    const root_module = b.addModule("zig_client_root", .{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "core", .module = core_mod },
            .{ .name = "client", .module = client_mod },
            .{ .name = "assets", .module = assets_mod },
        },
    });

    // ... rest of build.zig
}
```

---

## Zig 0.15.x Specific Tips

1. **Module imports are explicit** - Must declare in build.zig or use file-based `@import`
2. **No more `usingnamespace`** - Use explicit exports via `pub const` in `mod.zig`
3. **Anonymous structs** - Use for simple data containers (like `PendingMove`)
4. **Error unions** - Use `!T` and `try` consistently
5. **`zig fmt`** - Format code after changes

---

## Verification Checklist

After each phase:

```bash
# 1. Compile check
zig build

# 2. Test check
zig build test

# 3. Format check
zig fmt src/

# 4. Run game (smoke test)
zig build run
```

---

## Testing During Refactoring

Zig 0.15.x test discovery:

```bash
# Run all tests
zig build test

# Test specific file
zig test src/core/world.zig

# Test with filtering
zig build test --test-filter "collision"
```

**Important:** Keep `shared.zig` working until ALL imports are updated, or everything breaks.

---

## Multiplayer-Aware Structure

Since you have a **networked multiplayer game**, use this modified pattern:

```
┌─────────────────────────────────────────────────────┐
│                   Client App                        │
│  ┌───────────────────────────────────────────────┐  │
│  │     Scene (Login → World)                    │  │
│  │  ┌─────────────────────────────────────────┐  │  │
│  │  │  ClientGameState (networked state)      │  │  │
│  │  │  - snapshots, interpolation              │  │  │
│  │  │  - other_players (double-buffered)       │  │  │
│  │  └─────────────────────────────────────────┘  │  │
│  │  ┌─────────────────────────────────────────┐  │  │
│  │  │  Local Entities                          │  │  │
│  │  │  - player (predicted)                    │  │  │
│  │  │  - plots (server-synced)                 │  │  │
│  │  └─────────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────────┘  │
│  - assets (shared)                                    │
│  - renderer (client-only)                            │
└─────────────────────────────────────────────────────┘
```

### Key Adjustments for Multiplayer

| Folder | Contains | Can run on server? |
|--------|----------|-------------------|
| `core/` | Pure logic (collision, terrain) | ✅ Yes |
| `game/` | Game objects (Player, Plot) | ⚠️ Partially |
| `client/` | Rendering + networking | ❌ No |
| `scenes/` | Scene management | ❌ No |

---

## Common Pitfalls

### 1. Forgetting to export in `mod.zig`

```zig
// core/mod.zig
pub const World = @import("world.zig").World;
// ❌ Forgot to export Building!

// Usage elsewhere
const core = @import("core/mod.zig");
const b = core.Building;  // ❌ Error: no member named 'Building'
```

### 2. Importing raylib in core logic

```zig
// core/world.zig
const rl = @import("raylib");  // ❌ Breaks headless testing!
```

### 3. Circular dependencies

```
core imports client
client imports core
```

Keep dependency flow: `util ← core ← game ← scenes → client`

### 4. Deleting `shared.zig` too early

Keep `shared.zig` until ALL imports are updated and working.

---

## Rollback Strategy

If refactoring breaks something:

```bash
# Revert to last checkpoint
git checkout <commit-hash>

# Or revert specific file
git checkout HEAD~1 -- src/core/world.zig
```

---

## References

- `REFACTORING_PLAN.md` - Main refactoring plan
- `game_architecture_patterns.md` - Architecture patterns
- Zig 0.15.1 documentation: https://ziglang.org/documentation/0.15.1/
