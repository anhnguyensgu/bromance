const rl = @import("raylib");
const sheets = @import("sheets.zig");
const Frames = sheets.SpriteSet;
const drawSprite = sheets.drawSprite;
const SpriteRect = sheets.SpriteRect;

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

        InnerCenter1 = 9,
        InnerCenter2 = 10,
    };

    /// 9 entries: 3x3 block
    descriptors: [11]SpriteRect,
    texture2D: rl.Texture2D,

    const Self = @This();

    /// Initialize a LandscapeTile for a specific 3x3 region in the tileset.
    ///
    /// This version is specialized to the road block used previously:
    /// it assumes a 3x3 block starting at tile coords (8, 0),
    /// with each tile 16x16 pixels.
    pub fn init(text: rl.Texture2D, base_tx: f32, base_ty: f32) Self {
        const ts: f32 = 16.0;

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

                .{ .x = (base_tx + 1.0) * ts, .y = (base_ty + 1.0) * ts, .width = ts, .height = ts },
                .{ .x = (base_tx + 2.0) * ts, .y = (base_ty + 2.0) * ts, .width = ts, .height = ts },
            },
            .texture2D = text,
        };
    }

    pub fn get(self: Self, d: Dir) SpriteRect {
        return self.descriptors[@intFromEnum(d)];
    }
};

/// Draw a landscape tile selected from a Frames value at the given position.
///
/// The `dir` parameter specifies which part of the 3x3 tile block to draw
/// (e.g., Center for full tiles, TopLeftCorner for corners, etc.)
pub fn drawLandscapeTile(d: Frames, dir: LandscapeTile.Dir, x: f32, y: f32) void {
    switch (d) {
        .SpringTiles => |t| {
            const tile: LandscapeTile = switch (t) {
                .Grass => |lt| lt,
                .Road => |lt| lt,
                .Rock => |lt| lt,
                .Water => |lt| lt,
            };
            const sprite = tile.get(dir);
            drawSprite(tile.texture2D, sprite, x, y);
        },
        // Only tile sprites are valid for landscape drawing.
        else => return,
    }
}
