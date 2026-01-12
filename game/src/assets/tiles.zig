const std = @import("std");
const rl = @import("raylib");
const SpriteSheet = @import("sprite_sheet.zig").SpriteSheet;

/// Spring tileset terrain types (type-safe)
pub const SpringTerrain = enum {
    grass,
    road,
    rock,
    water,

    /// Get the base tile coordinates (in tile units, not pixels) for this terrain
    pub fn getBaseTileCoords(self: SpringTerrain) struct { x: f32, y: f32 } {
        return switch (self) {
            .grass => .{ .x = 8.0, .y = 0.0 },
            .road => .{ .x = 0.0, .y = 0.0 }, // TODO: Verify these coordinates
            .rock => .{ .x = 0.0, .y = 4.0 }, // TODO: Verify these coordinates
            .water => .{ .x = 0.0, .y = 8.0 }, // TODO: Verify these coordinates
        };
    }
};

/// Direction within a 3x3 landscape tile block (for auto-tiling)
pub const LandscapeTileDir = enum(usize) {
    top_left_corner = 0,
    top = 1,
    top_right_corner = 2,

    left = 3,
    center = 4,
    right = 5,

    bottom_left_corner = 6,
    bottom = 7,
    bottom_right_corner = 8,

    inner_center_1 = 9,
    inner_center_2 = 10,
};

/// A 3x3 block of landscape tiles for auto-tiling
pub const LandscapeTileBlock = struct {
    texture: rl.Texture2D,
    base_x: f32,
    base_y: f32,
    tile_size: f32 = 16.0,

    const Self = @This();

    pub fn init(texture: rl.Texture2D, base_tx: f32, base_ty: f32) Self {
        return .{
            .texture = texture,
            .base_x = base_tx,
            .base_y = base_ty,
        };
    }

    /// Get the source rectangle for a specific tile in the 3x3 block
    pub fn getSourceRect(self: Self, dir: LandscapeTileDir) rl.Rectangle {
        const ts = self.tile_size;
        const base_x = self.base_x;
        const base_y = self.base_y;

        // These match the layout in landscape.zig
        const coords: [11]struct { x: f32, y: f32 } = .{
            // Row 0
            .{ .x = base_x + 0.0, .y = base_y + 0.0 },
            .{ .x = base_x + 2.0, .y = base_y + 0.0 },
            .{ .x = base_x + 3.0, .y = base_y + 0.0 },
            // Row 1
            .{ .x = base_x + 0.0, .y = base_y + 1.0 },
            .{ .x = base_x + 1.0, .y = base_y + 2.0 },
            .{ .x = base_x + 3.0, .y = base_y + 2.0 },
            // Row 2
            .{ .x = base_x + 0.0, .y = base_y + 3.0 },
            .{ .x = base_x + 1.0, .y = base_y + 3.0 },
            .{ .x = base_x + 3.0, .y = base_y + 3.0 },
            // Inner tiles
            .{ .x = base_x + 1.0, .y = base_y + 1.0 },
            .{ .x = base_x + 2.0, .y = base_y + 2.0 },
        };

        const coord = coords[@intFromEnum(dir)];
        return .{
            .x = coord.x * ts,
            .y = coord.y * ts,
            .width = ts,
            .height = ts,
        };
    }

    /// Draw a specific tile from this block
    pub fn draw(self: Self, dir: LandscapeTileDir, x: f32, y: f32) void {
        const src = self.getSourceRect(dir);
        const dest = rl.Vector2{ .x = x, .y = y };
        rl.drawTextureRec(self.texture, src, dest, .white);
    }
};

/// Typed Spring tileset wrapper with terrain support
pub const SpringTileSheet = struct {
    texture: rl.Texture2D,

    const Self = @This();

    /// Get a landscape tile block for a specific terrain type
    pub fn getTerrain(self: Self, terrain: SpringTerrain) LandscapeTileBlock {
        const coords = terrain.getBaseTileCoords();
        return LandscapeTileBlock.init(self.texture, coords.x, coords.y);
    }

    /// Draw a terrain tile at a position
    pub fn drawTerrain(self: Self, terrain: SpringTerrain, dir: LandscapeTileDir, x: f32, y: f32) void {
        const block = self.getTerrain(terrain);
        block.draw(dir, x, y);
    }
};

/// Main Assets struct for tile sheets
pub const TileAssets = struct {
    spring_tiles: SpringTileSheet,

    const Self = @This();

    pub fn init() !Self {
        const texture = try rl.loadTexture("assets/farmrpg/tileset/tilesetspring.png");
        return .{
            .spring_tiles = .{ .texture = texture },
        };
    }

    pub fn deinit(self: *Self) void {
        rl.unloadTexture(self.spring_tiles.texture);
    }
};
