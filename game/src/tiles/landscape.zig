const std = @import("std");
const rl = @import("raylib");
const terrain = @import("./terrain.zig");
const TerrainType = terrain.TerrainType;

/// Simple descriptor for a sub-rectangle in a spritesheet.
pub const SpriteRect = struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,
};

/// Draw a sprite from a texture at the given position.
pub fn drawSprite(texture: rl.Texture2D, sprite: SpriteRect, x: f32, y: f32) void {
    const src = rl.Rectangle{
        .x = sprite.x,
        .y = sprite.y,
        .width = sprite.width,
        .height = sprite.height,
    };

    const dest = rl.Rectangle{
        .x = x,
        .y = y,
        .width = sprite.width,
        .height = sprite.height,
    };

    rl.drawTexturePro(
        texture,
        src,
        dest,
        .{ .x = 0, .y = 0 },
        0,
        .white,
    );
}

/// Identify which sprite sheet set a Frames value belongs to.
/// For now we only have SpringTiles, but this can be extended.
pub const SpriteSheets = enum {
    SpringTiles,
};

/// A logical 3x3 block of landscape tiles (e.g. auto-tiling variants).
pub const LandscapeTile = struct {
    pub const Dir = enum(usize) {
        TopLeftCorner = 0,
        Top = 1,
        TopRightCorner = 2,

        Left = 3,
        Center = 4, // Center of the 3x3
        Right = 5,

        BottomLeftCorner = 6,
        Bottom = 7,
        BottomRightCorner = 8,
    };

    /// 9 entries: 3x3 block
    descriptors: [9]SpriteRect,
    texture2D: rl.Texture2D,

    const Self = @This();

    /// Initialize a LandscapeTile for a specific 3x3 region in the tileset.
    ///
    /// This version is specialized to the road block used previously:
    /// it assumes a 3x3 block starting at tile coords (8, 0),
    /// with each tile 16x16 pixels.
    pub fn init(text: rl.Texture2D) Self {
        const ts: f32 = 16.0;
        const base_tx: f32 = 8.0;
        const base_ty: f32 = 0.0;

        return Self{
            .descriptors = [_]SpriteRect{
                // Row 0
                .{ .x = (base_tx + 0.0) * ts, .y = (base_ty + 0.0) * ts, .width = ts, .height = ts },
                .{ .x = (base_tx + 2.0) * ts, .y = (base_ty + 0.0) * ts, .width = ts, .height = ts },
                .{ .x = (base_tx + 3.0) * ts, .y = (base_ty + 0.0) * ts, .width = ts, .height = ts },

                // Row 1
                .{ .x = (base_tx + 0.0) * ts, .y = (base_ty + 1.0) * ts, .width = ts, .height = ts },
                .{ .x = (base_tx + 1.0) * ts, .y = (base_ty + 2.0) * ts, .width = ts, .height = ts },
                .{ .x = (base_tx + 3.0) * ts, .y = (base_ty + 2.0) * ts, .width = ts, .height = ts },

                // Row 2
                .{ .x = (base_tx + 0.0) * ts, .y = (base_ty + 3.0) * ts, .width = ts, .height = ts },
                .{ .x = (base_tx + 1.0) * ts, .y = (base_ty + 3.0) * ts, .width = ts, .height = ts },
                .{ .x = (base_tx + 3.0) * ts, .y = (base_ty + 3.0) * ts, .width = ts, .height = ts },
            },
            .texture2D = text,
        };
    }

    pub fn get(self: Self, d: Dir) SpriteRect {
        return self.descriptors[@intFromEnum(d)];
    }
};

/// A tagged union of available sprite-sheet groups and terrain types.
///
/// Example:
///   var grass_frames = Frames.SpringTileGrass(tileset_texture);
///   drawLandscapeTile(grass_frames, 0, 0);
pub const Frames = union(SpriteSheets) {
    SpringTiles: union(TerrainType) {
        Grass: LandscapeTile,
        Rock: LandscapeTile,
        Water: LandscapeTile,
        Road: LandscapeTile,
    },

    /// Convenience constructor for a spring grass 3x3 tile block.
    pub fn SpringTileGrass(tileset_texture: rl.Texture2D) Frames {
        return .{ .SpringTiles = .{
            .Grass = LandscapeTile.init(tileset_texture),
        } };
    }

    /// Convenience constructor for a spring road 3x3 tile block.
    pub fn SpringTileRoad(tileset_texture: rl.Texture2D) Frames {
        return .{ .SpringTiles = .{
            .Road = LandscapeTile.init(tileset_texture),
        } };
    }
};

/// Draw a landscape tile selected from a Frames value at the given position.
///
/// The `dir` parameter specifies which part of the 3x3 tile block to draw
/// (e.g., Center for full tiles, TopLeftCorner for corners, etc.)
pub fn drawLandscapeTile(d: Frames, dir: LandscapeTile.Dir, x: f32, y: f32) void {
    const tile: LandscapeTile = switch (d) {
        .SpringTiles => |t| switch (t) {
            .Grass => |tile| tile,
            .Road => |tile| tile,
            .Rock => |tile| tile,
            .Water => |tile| tile,
        },
    };

    const sprite = tile.get(dir);
    drawSprite(tile.texture2D, sprite, x, y);
}
