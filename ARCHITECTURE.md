# Architecture Plan

## Dependency Hierarchy

```
Level 1: Foundational Types (no dependencies)
├── util/
├── movement/
├── ping/
└── model/

Level 2: Core Logic (depends on Level 1)
├── core/
├── map/
├── plot/
└── network.zig

Level 3: Data & Assets (depends on Level 1-2)
├── assets/
├── game/
└── db/

Level 4: Presentation (depends on Level 1-3)
├── client/
├── grpc/
└── scenes/

Top Level: Entry Points
├── server_main.zig
├── tile_inspector.zig
├── screens/
└── main.zig
```

## Module Directory Structure

```
game/src/
├── util/                    # Utility functions
│   └── mod.zig
│
├── movement/                # Movement command types
│   └── command.zig          # MoveDirection enum
│
├── ping/                    # Ping command types
│   └── command.zig          # Ping commands
│
├── model/                   # Generated protobuf models
│   └── auth.pb.zig
│
├── core/                    # Pure game logic (headless)
│   ├── mod.zig
│   ├── context.zig          # Game context
│   ├── physics.zig          # Collision detection
│   ├── rules.zig            # Game rules
│   ├── scene_action.zig     # Scene actions
│   ├── scene_manager.zig    # Scene management
│   ├── terrain.zig          # Terrain types
│   └── world.zig            # World logic
│
├── map/                     # Map system
│   ├── model.zig
│   └── editor_map.zig
│
├── plot/                    # Farming mechanics
│   ├── plot.zig
│   └── plot_decoration.zig
│
├── network.zig              # UDP networking
│
├── assets/                  # Asset management (raylib-dependent)
│   ├── mod.zig
│   ├── characters.zig       # Character assets
│   ├── sprite_sheet.zig     # Sprite sheet handling
│   └── tiles.zig            # Tile assets
│
├── game/                    # Game objects (pure data)
│   ├── mod.zig
│   └── player.zig           # Player entity
│
├── db/                      # Database persistence
│   ├── migrations.zig
│   ├── player_store.zig
│   └── player_store_test.zig
│
├── client/                  # Rendering & input (raylib-dependent)
│   ├── mod.zig
│   ├── game_state.zig       # Network sync state
│   ├── udp_client.zig       # UDP client
│   ├── http_client.zig      # HTTP client
│   ├── tiles/
│   │   ├── sheets.zig       # Sprite sheets
│   │   ├── layer.zig
│   │   ├── landscape.zig
│   │   └── autotile.zig
│   └── ui/
│       ├── layout.zig
│       ├── widgets.zig
│       ├── hud.zig
│       ├── inventory_bar.zig
│       ├── panels/
│       ├── ghost_layer.zig
│       └── placement.zig
│
├── grpc/                    # gRPC client/server
│   ├── client.zig
│   └── http2.zig
│
├── scenes/                  # Scene definitions
│   └── mod.zig
│
├── screens/                 # Rendered scenes with UI
│   ├── login.zig
│   ├── world.zig
│   └── ui_state.zig
│
├── server_main.zig          # Server entry point
├── tile_inspector.zig       # Debug tool
└── main.zig                 # Client entry point
```

## Module Purposes

| Module | Purpose | Depends On |
|--------|---------|------------|
| `util/` | Utility functions | none |
| `movement/` | Movement command types | none |
| `ping/` | Ping command types | none |
| `model/` | Protobuf models | none |
| `core/` | Pure game logic (headless) | util, movement, ping |
| `map/` | Map system | core |
| `plot/` | Farming mechanics | core |
| `network.zig` | UDP networking | model, core |
| `assets/` | Asset management (raylib) | util |
| `game/` | Game objects (pure data) | core, movement |
| `db/` | Database persistence | model, core |
| `client/` | Rendering & input (raylib) | core, assets, game |
| `grpc/` | gRPC layer | model, network |
| `scenes/` | Scene definitions | core, game |
| `screens/` | Rendered scenes with UI | client, scenes, game |

## Dependency Rules

1. **Level 1** (util, movement, ping, model) - No dependencies on other game modules
2. **Level 2** (core, map, plot, network) - Only depends on Level 1
3. **Level 3** (assets, game, db) - Depends on Level 1-2
4. **Level 4** (client, grpc, scenes) - Depends on Level 1-3
5. **Top Level** (screens, main, server_main) - Can depend on anything

## Key Separation Concerns

### core/ vs game/
- **core/** - Abstract rules and logic (collision formulas, physics)
- **game/** - Concrete entity structs (Player with position/health)

### game/ vs client/
- **game/** - Pure data and behavior (no rendering)
- **client/** - Rendering, input, UI (raylib-dependent)

### assets/ vs game/
- **assets/** - Resource loading/unloading (textures, sprites)
- **game/** - Game objects that reference assets by ID

### scenes/ vs screens/
- **scenes/** - Scene logic and state management
- **screens/** - Rendered scenes with UI (client-dependent)
