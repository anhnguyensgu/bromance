// ==================================================================================
// Core Game Logic Module
// ==================================================================================
// This module exports pure game logic with NO rendering dependencies.
// All code here should be testable without raylib and runnable on server.
//
// Dependency rule: core/ MUST NOT import from client/, screens/, or ui/
// ==================================================================================

// World and game state
pub const World = @import("world.zig").World;
pub const Building = @import("world.zig").Building;
pub const BuildingType = @import("world.zig").BuildingType;
pub const PlayerState = @import("world.zig").PlayerState;
pub const Room = @import("world.zig").Room;
pub const WorldError = @import("world.zig").WorldError;
pub const CommandInput = @import("world.zig").CommandInput;
pub const TerrainType = @import("world.zig").TerrainType;
pub const Plot = @import("world.zig").Plot;
pub const OwnerId = @import("world.zig").OwnerId;
pub const OwnerIdKind = @import("world.zig").OwnerIdKind;
pub const MovementCommand = @import("world.zig").MovementCommand;
pub const MoveDirection = @import("world.zig").MoveDirection;

// Physics and collision (currently in world.zig methods)
pub const physics = @import("physics.zig");

// Game rules (placeholder)
pub const Rules = @import("rules.zig").Rules;

// Scene management (already exists)
pub const SceneAction = @import("scene_action.zig").SceneAction;
pub const SceneManager = @import("scene_manager.zig").SceneManager;

// Context (already exists)
pub const Context = @import("context.zig").Context;
