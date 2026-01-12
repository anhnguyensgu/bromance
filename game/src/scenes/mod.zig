// ==================================================================================
// Scenes Module
// ==================================================================================
// This module exports all scene-related types and utilities.
// RESPONSIBILITIES:
// - Scene definitions (menu, game, etc.)
// - Scene management and transitions
// - UI state for heads-up display
//
// Dependencies:
// - core: World and physics
// - client: Rendering and input
// - game: Game objects (player, camera)
// ==================================================================================

pub const UIState = @import("ui_state.zig").UIState;
pub const InventoryItem = @import("ui_state.zig").InventoryItem;
pub const MAX_INVENTORY_SLOTS = @import("ui_state.zig").MAX_INVENTORY_SLOTS;
