const std = @import("std");
const rl = @import("raylib");
const terrain = @import("./terrain.zig");
const landscape = @import("./landscape.zig");

const TerrainType = terrain.TerrainType;

/// Simple descriptor for a sub-rectangle in a spritesheet.
pub const SpriteRect = struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,
};

/// Central registry for sprite-sheet groupings.
pub const SpriteSheets = enum {
    SpringTiles,
    Menu,
};

pub const LandscapeTile = landscape.LandscapeTile;

/// Sprite variants for menu UI.
pub const MenuSpriteId = enum(usize) {
    Background,
    Button,
};

const menu_sprite_count = std.enums.values(MenuSpriteId).len;

pub const MenuSprites = struct {
    descriptors: [menu_sprite_count]SpriteRect,
    texture2D: rl.Texture2D,

    const Self = @This();

    pub fn init(text: rl.Texture2D) Self {
        return .{
            .descriptors = .{
                .{ .x = 95, .y = 3, .width = 83, .height = 172 }, // header strip
                .{ .x = 64.0, .y = 0.0, .width = 64.0, .height = 64.0 }, // button tile
            },
            .texture2D = text,
        };
    }

    pub fn deinit(self: Self) void {
        rl.unloadTexture(self.texture2D);
    }

    pub fn get(self: Self, sprite: MenuSpriteId) SpriteRect {
        return self.descriptors[@intFromEnum(sprite)];
    }
};

/// A tagged union of available sprite-sheet groups and terrain types.
///
/// Example:
///   var grass_frames = Frames.SpringTileGrass(tileset_texture);
///   drawLandscapeTile(grass_frames, 0, 0);
pub const SpriteSet = union(SpriteSheets) {
    SpringTiles: union(TerrainType) {
        Grass: LandscapeTile,
        Rock: LandscapeTile,
        Water: LandscapeTile,
        Road: LandscapeTile,
    },
    Menu: MenuSprites,

    /// Convenience constructor for a spring grass 3x3 tile block.
    pub fn SpringTileGrass(tileset_texture: rl.Texture2D, base_tx: f32, base_ty: f32) SpriteSet {
        return .{
            .SpringTiles = .{
                .Grass = LandscapeTile.init(tileset_texture, base_tx, base_ty), // Grass is at 0,0
            },
        };
    }

    /// Convenience constructor for a spring road 3x3 tile block.
    pub fn SpringTileRoad(tileset_texture: rl.Texture2D, base_tx: f32, base_ty: f32) SpriteSet {
        return .{
            .SpringTiles = .{
                .Road = LandscapeTile.init(tileset_texture, base_tx, base_ty), // Road is at 8,0
            },
        };
    }

    /// Convenience constructor for menu sprites.
    pub fn MenuSheet(menu_texture: rl.Texture2D) SpriteSet {
        return .{ .Menu = MenuSprites.init(menu_texture) };
    }
};

/// Draw a sprite from a texture at the given position using its original size.
pub fn drawSprite(texture: rl.Texture2D, sprite: SpriteRect, x: f32, y: f32) void {
    const dest = rl.Rectangle{
        .x = x,
        .y = y,
        .width = sprite.width,
        .height = sprite.height,
    };

    drawSpriteTo(texture, sprite, dest);
}

/// Draw a sprite into an arbitrary destination rectangle (scaling as needed).
pub fn drawSpriteTo(texture: rl.Texture2D, sprite: SpriteRect, dest: rl.Rectangle) void {
    const src = rl.Rectangle{
        .x = sprite.x,
        .y = sprite.y,
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
