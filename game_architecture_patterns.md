# Game Architecture Patterns

## Overview

Choosing the right architecture depends on game complexity. ECS is often overkill for indie games.

## Pattern Comparison

| Pattern | Complexity | Best For |
|---------|------------|----------|
| Single struct | Low | Jam games, prototypes |
| **Game State + Scenes** | Medium | Most indie games |
| ECS | High | 1000+ entities, reusable components |

---

## Core Principle: Separation of Concerns

```
┌─────────────────────────────────────────────────────┐
│                      Game                           │
├─────────────┬─────────────┬─────────────────────────┤
│   Core      │   Client    │   Server (future)       │
│  (shared)   │  (render)   │   (authority)           │
├─────────────┼─────────────┼─────────────────────────┤
│ - Game logic│ - Rendering │ - Validation            │
│ - Simulation│ - Input     │ - State authority       │
│ - Entities  │ - UI        │ - Persistence           │
│ - Physics   │ - Audio     │ - Matchmaking           │
│ - Rules     │ - Effects   │ - Anti-cheat            │
└─────────────┴─────────────┴─────────────────────────┘
```

---

## Pattern 1: Object-Oriented (Classic)

Each game object is a self-contained struct with its own update/draw.

```zig
const Player = struct {
    pos: Vec2,
    health: i32,
    sprite: SpriteId,

    pub fn update(self: *Player, dt: f32) void { ... }
    pub fn draw(self: Player, assets: *Assets) void { ... }
};

const Enemy = struct {
    pos: Vec2,
    health: i32,
    ai_state: AIState,

    pub fn update(self: *Enemy, dt: f32) void { ... }
    pub fn draw(self: Enemy, assets: *Assets) void { ... }
};
```

**Pros:**
- Simple, intuitive
- Easy to understand
- Good for small games

**Cons:**
- Code duplication between similar objects
- Hard to add cross-cutting features
- Doesn't scale well

---

## Pattern 2: Game State + Scenes (Recommended)

All game data in one struct. Scenes handle different game modes.

### Game State

```zig
const GameState = struct {
    // All game data in one place
    player: Player,
    enemies: std.ArrayList(Enemy),
    tiles: TileMap,
    camera: Camera,

    // Update everything
    pub fn update(self: *GameState, input: Input, dt: f32) void {
        self.player.update(input, dt);
        for (self.enemies.items) |*e| e.update(dt);
        self.handleCollisions();
    }

    // Draw everything
    pub fn draw(self: *GameState, assets: *Assets) void {
        self.tiles.draw(assets);
        for (self.enemies.items) |e| e.draw(assets);
        self.player.draw(assets);
    }
};
```

### Scene State Machine

```zig
const Scene = union(enum) {
    menu: MenuScene,
    playing: GameState,
    paused: PauseScene,
    game_over: GameOverScene,

    pub fn update(self: *Scene, input: Input, dt: f32) ?Scene {
        return switch (self.*) {
            .menu => |*s| s.update(input),
            .playing => |*s| s.update(input, dt),
            .paused => |*s| s.update(input),
            .game_over => |*s| s.update(input),
        };
    }

    pub fn draw(self: Scene, assets: *Assets) void {
        switch (self) {
            .menu => |s| s.draw(assets),
            .playing => |s| s.draw(assets),
            .paused => |s| s.draw(assets),
            .game_over => |s| s.draw(assets),
        }
    }
};
```

**Pros:**
- All state in one place
- Easy to serialize/save
- Scene transitions are explicit
- Scales to full indie games

**Cons:**
- GameState can get large
- Need discipline to keep organized

---

## Pattern 3: ECS (Entity Component System)

Entities are just IDs. Components are data. Systems process components.

```zig
// Components (just data)
const Position = struct { x: f32, y: f32 };
const Velocity = struct { dx: f32, dy: f32 };
const Sprite = struct { id: SpriteId };
const Health = struct { current: i32, max: i32 };

// Entity is just an ID
const Entity = u32;

// World stores components in arrays
const World = struct {
    positions: ComponentArray(Position),
    velocities: ComponentArray(Velocity),
    sprites: ComponentArray(Sprite),
};

// Systems process components
fn movementSystem(world: *World, dt: f32) void {
    for (world.entities()) |entity| {
        if (world.get(entity, Position, Velocity)) |pos, vel| {
            pos.x += vel.dx * dt;
            pos.y += vel.dy * dt;
        }
    }
}
```

**Pros:**
- Cache-friendly (data-oriented)
- Easy to add/remove behaviors
- Scales to thousands of entities
- Reusable components

**Cons:**
- Complex to implement
- Overkill for < 100 entities
- Harder to debug
- Learning curve

**When to use ECS:**
- 1000+ similar entities
- Need runtime component composition
- Building a reusable engine

---

## Recommended Architecture: Layered Game State

```
┌─────────────────────────────────────┐
│              App                    │
│  ┌───────────────────────────────┐  │
│  │     Scene (union/enum)        │  │
│  │  ┌─────────────────────────┐  │  │
│  │  │     GameState           │  │  │
│  │  │  - player               │  │  │
│  │  │  - enemies[]            │  │  │
│  │  │  - tiles                │  │  │
│  │  │  - items[]              │  │  │
│  │  └─────────────────────────┘  │  │
│  └───────────────────────────────┘  │
│  - assets (shared across scenes)    │
│  - audio (shared across scenes)     │
└─────────────────────────────────────┘
```

### Implementation

```zig
// main.zig
const App = struct {
    assets: Assets,
    scene: Scene,

    pub fn init() App {
        return .{
            .assets = Assets.init(),
            .scene = .{ .menu = MenuScene.init() },
        };
    }

    pub fn run(self: *App) void {
        while (!rl.windowShouldClose()) {
            const dt = rl.getFrameTime();
            const input = Input.poll();

            // Scene might transition to another scene
            if (self.scene.update(input, dt)) |next| {
                self.scene.deinit();
                self.scene = next;
            }

            rl.beginDrawing();
            self.scene.draw(&self.assets);
            rl.endDrawing();
        }
    }

    pub fn deinit(self: *App) void {
        self.scene.deinit();
        self.assets.deinit();
    }
};

pub fn main() !void {
    rl.initWindow(800, 600, "Game");
    defer rl.closeWindow();

    var app = App.init();
    defer app.deinit();

    app.run();
}
```

### GameState Example

```zig
// scenes/game.zig
const GameState = struct {
    player: Player,
    enemies: std.BoundedArray(Enemy, 100),
    tile_map: TileMap,
    camera: Camera,

    pub fn init() GameState {
        return .{
            .player = Player.init(100, 100),
            .enemies = .{},
            .tile_map = TileMap.init(),
            .camera = Camera.init(),
        };
    }

    pub fn update(self: *GameState, input: Input, dt: f32) ?Scene {
        // Update player with collision
        handleMovement(&self.player, &self.tile_map, input, dt);

        // Update enemies
        for (&self.enemies.slice()) |*enemy| {
            enemy.update(&self.player, dt);
        }

        // Update camera
        self.camera.follow(self.player.pos, dt);

        // Check game over
        if (self.player.health <= 0) {
            return .{ .game_over = GameOverScene.init(self.player.score) };
        }

        // Check pause
        if (input.isPressed(.escape)) {
            return .{ .paused = PauseScene.init(self) };
        }

        return null; // stay in this scene
    }

    pub fn draw(self: *GameState, assets: *Assets) void {
        self.camera.begin();
        defer self.camera.end();

        self.tile_map.draw(assets);

        for (self.enemies.slice()) |enemy| {
            enemy.draw(assets);
        }

        self.player.draw(assets);
    }
};
```

---

## Project Structure

### Recommended Layout

```
src/
├── main.zig              # Entry point, App struct, game loop

├── core/                 # Pure game logic (no rendering)
│   ├── mod.zig
│   ├── world.zig         # World state, tile data
│   ├── entity.zig        # Entity definitions
│   ├── physics.zig       # Movement, collision rules
│   └── rules.zig         # Game rules (damage, etc.)

├── client/               # Rendering & input (raylib)
│   ├── mod.zig
│   ├── renderer.zig      # Draw world, entities
│   ├── camera.zig        # Camera logic
│   ├── input.zig         # Input handling
│   ├── ui.zig            # UI rendering
│   └── audio.zig         # Sound (future)

├── assets/               # Asset management
│   ├── mod.zig
│   ├── sprite_sheet.zig  # SpriteSheet struct
│   ├── tiles.zig         # Tile asset IDs
│   ├── characters.zig    # Character asset IDs
│   └── ui.zig            # UI asset IDs

├── scenes/               # Game scenes/states
│   ├── mod.zig           # Scene union
│   ├── menu.zig          # MenuScene
│   ├── game.zig          # GameState (playing)
│   ├── pause.zig         # PauseScene
│   └── game_over.zig     # GameOverScene

├── game/                 # Game objects
│   ├── mod.zig
│   ├── player.zig        # Player struct
│   ├── enemy.zig         # Enemy struct
│   ├── tile_map.zig      # TileMap struct
│   └── camera.zig        # Camera struct

└── util/                 # Shared utilities
    ├── mod.zig
    └── math.zig          # Math helpers
```

### Dependency Flow

```
util ← core ← game ← scenes
         ↑              ↑
       assets ←─────── client
```

| Folder | Purpose | Depends On |
|--------|---------|------------|
| `core/` | Game rules, can run headless | Nothing |
| `client/` | Rendering, input | core, assets |
| `assets/` | Resource management | raylib only |
| `game/` | Game objects | core |
| `scenes/` | Scene management | game, assets |
| `util/` | Helpers | Nothing |

### Benefits

**1. Testable core logic**
```zig
// core/ has no raylib dependency
// Can unit test game rules without graphics
test "collision detection" {
    var world = World.init();
    // test pure logic
}
```

**2. Future multiplayer ready**
```zig
// core/ runs on both client and server
// client/ is client-only
// Add server/ later without rewriting game logic
```

**3. Clear dependencies**
- No circular imports
- Easy to understand what depends on what

---

## Game Loop Structure

```zig
pub fn main() !void {
    // Init
    var assets = Assets.init();
    defer assets.deinit();

    var world = World.init();
    var renderer = Renderer.init(&assets);
    var input = Input.init();

    // Loop
    while (!rl.windowShouldClose()) {
        const dt = rl.getFrameTime();

        // 1. Input (client)
        const commands = input.poll();

        // 2. Update (core + systems)
        world.update(commands, dt);

        // 3. Render (client)
        renderer.draw(&world);
    }
}
```

---

## Decision Guide

| Question | Answer | Pattern |
|----------|--------|---------|
| Prototype / game jam? | Yes | Single struct |
| Indie game < 100 entities? | Yes | **Game State + Scenes** |
| Need runtime entity composition? | Yes | ECS |
| 1000+ similar entities? | Yes | ECS |
| Building reusable engine? | Yes | ECS |

---

## Anti-patterns to Avoid

### 1. God Object
```zig
// Bad - everything in one massive struct
const Game = struct {
    // 50 fields...
    // 100 methods...
};
```

Split into focused structs (Player, TileMap, Camera).

### 2. Premature ECS
```zig
// Bad - ECS for 10 entities
const world = ecs.World.init();
world.spawn(.{ Position{}, Velocity{}, Sprite{} });
```

Just use structs until you have 100+ similar entities.

### 3. Global State
```zig
// Bad
var global_player: Player = undefined;
var global_assets: Assets = undefined;
```

Pass explicitly or use App struct.

### 4. Scene Logic in Main
```zig
// Bad - main.zig handles all scene logic
if (current_scene == .menu) {
    // 100 lines of menu logic
} else if (current_scene == .playing) {
    // 200 lines of game logic
}
```

Each scene should be its own struct with update/draw.

### 5. Mixing Core and Rendering
```zig
// Bad - game logic depends on raylib
const Player = struct {
    pub fn update(self: *Player) void {
        if (rl.isKeyDown(.w)) { // raylib in core logic!
            self.pos.y -= 1;
        }
    }
};
```

Pass input as data, keep core logic pure.
