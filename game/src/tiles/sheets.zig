const std = @import("std");
const rl = @import("raylib");
const terrain = @import("./terrain.zig");
const landscape = @import("./landscape.zig");
const player = @import("../character/player.zig");

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
    House,
    Lake,
    MainCharacter,
    Fence,
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
                .{ .x = 30, .y = 50, .width = 300, .height = 320 }, // header strip
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

pub const House = struct {
    descriptor: SpriteRect,
    texture2D: rl.Texture2D,

    const Self = @This();

    pub fn init(text: rl.Texture2D) Self {
        return .{
            .descriptor = .{
                .x = 150,
                .y = 0,
                .width = @as(f32, @floatFromInt(@divTrunc(text.width, 3))),
                .height = @as(f32, @floatFromInt(text.height)),
            },
            .texture2D = text,
        };
    }

    pub fn deinit(self: Self) void {
        rl.unloadTexture(self.texture2D);
    }
};

pub const Lake = struct {
    descriptor: SpriteRect,
    texture2D: rl.Texture2D,

    const Self = @This();

    pub fn init(text: rl.Texture2D) Self {
        return .{
            .descriptor = .{
                .x = 0,
                .y = 0,
                .width = @floatFromInt(text.width),
                .height = @floatFromInt(text.height),
            },
            .texture2D = text,
        };
    }

    pub fn deinit(self: Self) void {
        rl.unloadTexture(self.texture2D);
    }
};

pub const FenceStyle = enum(usize) {
    horizontal,
    vertical,
    top_left_corner,
    top_right_corner,
    bottom_left_corner,
    bottom_right_corner,
    cross,
    t_top,
    t_bottom,
    t_left,
    t_right,
};

const fence_sprite_count = std.enums.values(FenceStyle).len;

pub const FenceAsset = struct {
    descriptors: [fence_sprite_count]SpriteRect,
    texture2D: rl.Texture2D,
    debug_mode: bool = false,
    const Self = @This();

    pub fn init(text: rl.Texture2D) Self {
        return .{
            .descriptors = .{
                .{ .x = 16, .y = 0, .width = 16, .height = 16 },
                .{ .x = 0, .y = 16, .width = 16, .height = 16 },
                .{ .x = 0, .y = 0, .width = 16, .height = 16 },
                .{ .x = 32, .y = 0, .width = 16, .height = 16 },
                .{ .x = 0, .y = 32, .width = 16, .height = 16 },
                .{ .x = 32, .y = 32, .width = 16, .height = 16 },
                .{ .x = 16, .y = 16, .width = 16, .height = 16 },
                .{ .x = 16, .y = 32, .width = 16, .height = 16 },
                .{ .x = 16, .y = 0, .width = 16, .height = 16 },
                .{ .x = 0, .y = 16, .width = 16, .height = 16 },
                .{ .x = 32, .y = 16, .width = 16, .height = 16 },
            },
            .texture2D = text,
        };
    }

    pub fn deinit(self: Self) void {
        rl.unloadTexture(self.texture2D);
    }

    pub fn get(self: Self, style: FenceStyle) SpriteRect {
        return self.descriptors[@intFromEnum(style)];
    }

    pub fn drawDebug(self: Self) void {
        const texture_width = @as(f32, @floatFromInt(self.texture2D.width));
        const texture_height = @as(f32, @floatFromInt(self.texture2D.height));

        rl.drawTexture(self.texture2D, 10, 10, .white);

        for (self.descriptors, 0..) |sprite, i| {
            const rect = rl.Rectangle{
                .x = 10 + sprite.x,
                .y = 10 + sprite.y,
                .width = sprite.width,
                .height = sprite.height,
            };
            const color = rl.Color.init(255, 0, 0, 100);
            rl.drawRectangleLines(@intFromFloat(rect.x), @intFromFloat(rect.y), @intFromFloat(rect.width), @intFromFloat(rect.height), color);

            var buf: [32]u8 = undefined;
            const label = std.fmt.bufPrintZ(&buf, "{d}", .{i}) catch "";
            rl.drawText(label, @intFromFloat(rect.x + 2), @intFromFloat(rect.y + 2), 8, .red);
        }

        rl.drawRectangleLines(10, 10, @intFromFloat(texture_width), @intFromFloat(texture_height), .yellow);
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
    House: House,
    Lake: Lake,
    MainCharacter: player.CharacterAssets,
    Fence: FenceAsset,

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

    pub fn HouseSheet(texture: rl.Texture2D) SpriteSet {
        return .{ .House = House.init(texture) };
    }

    pub fn LakeSheet(texture: rl.Texture2D) SpriteSet {
        return .{ .Lake = Lake.init(texture) };
    }

    pub fn FenceSheet(texture: rl.Texture2D) SpriteSet {
        return .{ .Fence = FenceAsset.init(texture) };
    }

    pub fn MainCharacterSheet() !SpriteSet {
        return .{ .MainCharacter = try player.CharacterAssets.loadMainCharacter() };
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
