// ==================================================================================
// Core Physics - Collision Detection
// ==================================================================================
// NOTE: Collision logic is currently in World methods (world.zig):
// - World.checkCollision() - Terrain collision with directional sampling
// - World.checkBuildingCollision() - AABB collision with buildings
// - World.checkCollisionAll() - Combined collision check
// - World.isWalkable() - Terrain walkability check
//
// Future: If physics grows complex, extract to dedicated Physics struct here.
// ==================================================================================

const core_world = @import("world.zig");

// Re-export collision-related functions for convenience
pub const World = core_world.World;
pub const isWalkable = core_world.World.isWalkable;
