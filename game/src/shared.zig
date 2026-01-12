const std = @import("std");

pub const command = @import("movement/command.zig");
pub const MovementCommand = command.MovementCommand;
pub const MoveDirection = command.MoveDirection;
pub const network = @import("network.zig");
pub const PingPayload = network.PingPayload;
pub const landscape = @import("tiles/landscape.zig");
pub const LandscapeTile = landscape.LandscapeTile;
pub const drawLandscapeTile = landscape.drawLandscapeTile;
pub const tiles = @import("tiles/layer.zig");
pub const sheets = @import("tiles/sheets.zig");
pub const Frames = sheets.SpriteSet;
const t = @import("tiles/terrain.zig");
pub const TerrainType = t.TerrainType;

pub const menu = @import("ui/menu.zig");
pub const editor_map = @import("map/editor_map.zig");
pub const ghost_layer = @import("ui/ghost_layer.zig");
pub const placement = @import("ui/placement.zig");

pub const plot_mod = @import("plot/plot.zig");
pub const Plot = plot_mod.Plot;
pub const OwnerId = plot_mod.OwnerId;
pub const OwnerIdKind = plot_mod.OwnerIdKind;

// ==================================================================================
// MIGRATION: Core game logic has been moved to core/world.zig
// ==================================================================================
// This file now re-exports from core/world.zig for backward compatibility.
// In Phase 6, direct imports will be updated to use core/mod.zig instead.
// ==================================================================================

const core_world = @import("core/world.zig");

// Re-export core types for backward compatibility
pub const PlayerState = core_world.PlayerState;
pub const CommandInput = core_world.CommandInput;
pub const WorldError = core_world.WorldError;
pub const BuildingType = core_world.BuildingType;
pub const Building = core_world.Building;
pub const Room = core_world.Room;

// Re-export World from core (all logic is now in core/world.zig)
pub const World = core_world.World;

// OLD World implementation has been moved to core/world.zig
// (Removed approximately 330 lines of World struct + methods)

// drawGrassBackground() below stays here for now
// (will be moved to client/renderer.zig in Phase 2.2)
pub fn drawGrassBackground(grass: Frames, world: World) void {
    const tile_w: f32 = world.width / @as(f32, @floatFromInt(world.tiles_x));
    const tile_h: f32 = world.height / @as(f32, @floatFromInt(world.tiles_y));

    var ty: i32 = 0;
    while (ty < world.tiles_y) : (ty += 1) {
        var tx: i32 = 0;
        while (tx < world.tiles_x) : (tx += 1) {
            const x = @as(f32, @floatFromInt(tx)) * tile_w;
            const y = @as(f32, @floatFromInt(ty)) * tile_h;

            const dir: LandscapeTile.Dir = blk: {
                const is_left = tx == 0;
                const is_right = tx == world.tiles_x - 1;
                const is_top = ty == 0;
                const is_bottom = ty == world.tiles_y - 1;

                if (is_left and is_top) break :blk .TopLeftCorner;
                if (is_right and is_top) break :blk .TopRightCorner;
                if (is_left and is_bottom) break :blk .BottomLeftCorner;
                if (is_right and is_bottom) break :blk .BottomRightCorner;
                if (is_left) break :blk .Left;
                if (is_right) break :blk .Right;
                if (is_top) break :blk .Top;
                if (is_bottom) break :blk .Bottom;
                break :blk .Center;
            };

            drawLandscapeTile(grass, dir, x, y);
        }
    }
}


pub const LoginScreen = @import("screens/login.zig").LoginScreen;
pub const WorldScreen = @import("screens/world.zig").WorldScreen;
pub const HttpClient = @import("client/http_client.zig").HttpClient;
