const std = @import("std");
const rl = @import("raylib");

pub const AssetCache = struct {
    allocator: std.mem.Allocator,
    textures: std.StringHashMap(rl.Texture2D),
    fonts: std.StringHashMap(rl.Font),
    // sounds: std.StringHashMap(rl.Sound),

    pub fn init(allocator: std.mem.Allocator) AssetCache {
        return AssetCache{
            .allocator = allocator,
            .textures = std.StringHashMap(rl.Texture2D).init(allocator),
            .fonts = std.StringHashMap(rl.Font).init(allocator),
            // .sounds = std.StringHashMap(rl.Sound).init(allocator),
        };
    }

    pub fn deinit(self: *AssetCache) void {
        var tex_it = self.textures.iterator();
        while (tex_it.next()) |entry| {
            rl.unloadTexture(entry.value_ptr.*);
        }
        self.textures.deinit();

        var font_it = self.fonts.iterator();
        while (font_it.next()) |entry| {
            rl.unloadFont(entry.value_ptr.*);
        }
        self.fonts.deinit();
    }

    pub fn getTexture(self: *AssetCache, path: [:0]const u8) !rl.Texture2D {
        if (self.textures.get(path)) |tex| {
            return tex;
        }

        const texture = try rl.loadTexture(path);

        try self.textures.put(path, texture);
        return texture;
    }

    pub fn getFont(self: *AssetCache, path: [:0]const u8, font_size: i32) !rl.Font {
        if (self.fonts.get(path)) |font| {
            return font;
        }

        const font = try rl.loadFontEx(path, font_size, null);
        try self.fonts.put(path, font);
        return font;
    }
};
