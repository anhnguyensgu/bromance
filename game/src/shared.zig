// ==================================================================================
// DEPRECATED: This file provides backward compatibility for the old asset system
// ==================================================================================
// Phase 7 (Current): Core types migrated to direct imports
//   - Use @import("core/mod.zig") for World, PlayerState, Building, etc.
//   - Use @import("plot/plot.zig") for Plot, OwnerId
//   - Use @import("network.zig") for network types
//   - Use @import("movement/command.zig") for movement types
//
// Remaining exports in this file are for LEGACY/DEPRECATED systems:
//   - Old asset system (sheets, tiles, Frames, LandscapeTile)
//   - Tool utilities (menu, editor_map, ghost_layer, placement)
//   - drawGrassBackground (utility function)
//
// These will be migrated to the new enum-based asset system (assets/mod.zig) in a
// future cleanup phase. For new code, use the assets/mod.zig module instead.
// ==================================================================================

const std = @import("std");

// ==================================================================================
// OLD ASSET SYSTEM (Deprecated - use assets/mod.zig instead)
// ==================================================================================

pub const landscape = @import("client/tiles/landscape.zig");
pub const LandscapeTile = landscape.LandscapeTile;
pub const drawLandscapeTile = landscape.drawLandscapeTile;
pub const tiles = @import("client/tiles/layer.zig");
pub const sheets = @import("client/tiles/sheets.zig");
pub const Frames = sheets.SpriteSet;

const core_world = @import("core/world.zig");
pub const World = core_world.World;

// Legacy utility function for drawing grass backgrounds
// TODO: Migrate to new asset system or move to a renderer module
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

// ==================================================================================
// UTILITY EXPORTS (Tool-specific)
// ==================================================================================

pub const menu = @import("client/ui/menu.zig");
pub const editor_map = @import("map/editor_map.zig");
pub const ghost_layer = @import("client/ui/ghost_layer.zig");
pub const placement = @import("client/ui/placement.zig");
