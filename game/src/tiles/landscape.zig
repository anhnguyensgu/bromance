const std = @import("std");
const rl = @import("raylib");
const terrain = @import("./terrain.zig");
const TerrainType = terrain.TerrainType;

/// Simple descriptor for a sub-rectangle in a tileset texture.
pub const TileDescriptor = struct {
    x: f32,
    y: f32,
    tile_w: f32,
    tile_h: f32,
};

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
    descriptors: [9]TileDescriptor,
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
            .descriptors = [_]TileDescriptor{
                // Row 0
                .{ .x = (base_tx + 0.0) * ts, .y = (base_ty + 0.0) * ts, .tile_w = ts, .tile_h = ts },
                .{ .x = (base_tx + 1.0) * ts, .y = (base_ty + 0.0) * ts, .tile_w = ts, .tile_h = ts },
                .{ .x = (base_tx + 2.0) * ts, .y = (base_ty + 0.0) * ts, .tile_w = ts, .tile_h = ts },

                // Row 1
                .{ .x = (base_tx + 0.0) * ts, .y = (base_ty + 1.0) * ts, .tile_w = ts, .tile_h = ts },
                .{ .x = (base_tx + 1.0) * ts, .y = (base_ty + 1.0) * ts, .tile_w = ts, .tile_h = ts },
                .{ .x = (base_tx + 2.0) * ts, .y = (base_ty + 1.0) * ts, .tile_w = ts, .tile_h = ts },

                // Row 2
                .{ .x = (base_tx + 0.0) * ts, .y = (base_ty + 2.0) * ts, .tile_w = ts, .tile_h = ts },
                .{ .x = (base_tx + 1.0) * ts, .y = (base_ty + 2.0) * ts, .tile_w = ts, .tile_h = ts },
                .{ .x = (base_tx + 2.0) * ts, .y = (base_ty + 2.0) * ts, .tile_w = ts, .tile_h = ts },
            },
            .texture2D = text,
        };
    }

    pub fn get(self: Self, d: Dir) TileDescriptor {
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
/// Currently this chooses the top-left descriptor of the selected LandscapeTile.
/// You can extend it to accept a LandscapeTile.Dir parameter if you want to
/// draw specific edges/corners/center.
pub fn drawLandscapeTile(d: Frames, x: f32, y: f32) void {
    const tile_union = switch (d) {
        .SpringTiles => |t| t,
    };

    // For now we always pick Grass if present, otherwise Road/first available.
    // You can change this selection logic depending on how you use Frames.
    const tile: LandscapeTile = blk: {
        if (@hasField(@TypeOf(tile_union), "Grass")) {
            break :blk tile_union.Grass;
        } else if (@hasField(@TypeOf(tile_union), "Road")) {
            break :blk tile_union.Road;
        } else if (@hasField(@TypeOf(tile_union), "Rock")) {
            break :blk tile_union.Rock;
        } else if (@hasField(@TypeOf(tile_union), "Water")) {
            break :blk tile_union.Water;
        } else {
            // Fallback: this should not happen given the current union definition.
            break :blk tile_union.Grass;
        }
    };

    // Use the top-left corner descriptor as the default.
    const desc = tile.get(LandscapeTile.Dir.TopLeftCorner);

    const src = rl.Rectangle{
        .x = desc.x,
        .y = desc.y,
        .width = desc.tile_w,
        .height = desc.tile_h,
    };

    const dest = rl.Rectangle{
        .x = x,
        .y = y,
        .width = desc.tile_w,
        .height = desc.tile_h,
    };

    rl.drawTexturePro(
        tile.texture2D,
        src,
        dest,
        .{ .x = 0, .y = 0 },
        0,
        .white,
    );
}
