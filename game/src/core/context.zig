const std = @import("std");
const assets = @import("assets.zig");
const HttpClient = @import("../client/http_client.zig").HttpClient;

pub const GameContext = struct {
    allocator: std.mem.Allocator,
    assets: *assets.AssetCache,
    screen_width: i32,
    screen_height: i32,
    http_client: *HttpClient, // Login needs this

    pub fn init(allocator: std.mem.Allocator, asset_cache: *assets.AssetCache, http_client: *HttpClient, width: i32, height: i32) GameContext {
        return GameContext{
            .allocator = allocator,
            .assets = asset_cache,
            .http_client = http_client,
            .screen_width = width,
            .screen_height = height,
        };
    }
};
