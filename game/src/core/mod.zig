// ==================================================================================
// Core Game Logic Module
// ==================================================================================
// This module exports pure game logic with NO rendering dependencies.
// All code here should be testable without raylib and runnable on server.
//
// Dependency rule: core/ MUST NOT import from client/, screens/, or ui/
// ==================================================================================

// World and game state (will be extracted from shared.zig in Phase 2)
// TODO Phase 2.1: Extract World, Building, BuildingType from shared.zig
// pub const World = @import("world.zig").World;
// pub const Building = @import("world.zig").Building;
// pub const BuildingType = @import("world.zig").BuildingType;

// Physics and collision (will be extracted from shared.zig in Phase 2)
// TODO Phase 2.3: Extract collision logic from shared.zig
// pub const Physics = @import("physics.zig").Physics;

// Game rules (placeholder for Phase 2)
// TODO Phase 2.4: Create rules.zig for game rules
// pub const Rules = @import("rules.zig").Rules;

// Scene management (already exists)
pub const SceneAction = @import("scene_action.zig").SceneAction;
pub const SceneManager = @import("scene_manager.zig").SceneManager;

// Context (already exists)
pub const Context = @import("context.zig").Context;
