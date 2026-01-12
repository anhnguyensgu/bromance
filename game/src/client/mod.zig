// ==================================================================================
// Client Module - Rendering & Input
// ==================================================================================
// This module contains client-side code: rendering, input handling, and UI.
// All code here can use raylib and graphics dependencies.
//
// Dependency rule: client/ CAN import core/, but core/ MUST NOT import client/
// ==================================================================================

// TODO Phase 2.2: Create renderer.zig and export rendering functions
// pub const renderer = @import("renderer.zig");

// Existing client modules
pub const GameState = @import("game_state.zig").ClientGameState;
pub const HttpClient = @import("http_client.zig").HttpClient;
pub const UdpClient = @import("udp_client.zig").UdpClient;
