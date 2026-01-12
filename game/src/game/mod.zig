// ==================================================================================
// Game Objects Module
// ==================================================================================
// This module contains game entity definitions like players, NPCs, items, etc.
// Game objects can depend on core/ for game logic and client/ for rendering.
// ==================================================================================

// Player entity
pub const Player = @import("player.zig").Character;
pub const CharacterAssets = @import("player.zig").CharacterAssets;

// Note: Camera logic currently lives in screens/world.zig
// If camera logic grows more complex, it can be extracted to game/camera.zig
