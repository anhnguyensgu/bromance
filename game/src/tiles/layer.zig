const std = @import("std");
const rl = @import("raylib");
const autotile = @import("autotile.zig");

pub const TileLayer = autotile.TileLayer;
pub const AutoTileConfig = autotile.AutoTileConfig;
pub const AutoTileRenderer = autotile.AutoTileRenderer;
pub const TerrainId = autotile.TerrainId;
pub const TileMask = autotile.TileMask;

/// Predefined terrain IDs for the game
pub const Terrain = struct {
    pub const EMPTY: TerrainId = 0;
    pub const GRASS: TerrainId = 1;
    pub const ROAD: TerrainId = 2;
    pub const WATER: TerrainId = 3;
    pub const ROCK: TerrainId = 4;
    pub const DIRT: TerrainId = 5;
};

/// Factory to create auto-tile configs for the "Tileset Spring.png" tileset
/// This tileset uses 16x16 tiles
pub const TilesetSpring = struct {
    /// Road tiles starting at (8, 0) - uses 4x4 Layout B (RPG Maker style)
    /// Layout:
    ///   Row 0: ┌ ─ ─ ┐
    ///   Row 1: │ + + │
    ///   Row 2: │ + + │
    ///   Row 3: └ ─ ─ ┘
    pub fn roadConfig() AutoTileConfig {
        return AutoTileConfig.fromBlock4x4(8, 0);
    }

    /// Grass tiles - single tile at (9, 2), no auto-tiling needed
    /// Returns a config where all masks point to the same tile
    pub fn grassConfig() AutoTileConfig {
        return AutoTileConfig.fromBlock4x4(8, 0);
    }

    /// Water tiles starting at (0, 4) - uses 3x3 block layout
    pub fn waterConfig() AutoTileConfig {
        return AutoTileConfig.fromBlock3x3(0, 4);
    }

    /// Helper to create a config that always uses the same tile
    fn singleTileConfig(col: i32, row: i32) AutoTileConfig {
        var coords: [16][2]i32 = undefined;
        for (&coords) |*c| {
            c.* = .{ col, row };
        }
        return .{ .coords = coords };
    }
};

/// Multi-layer tile system for rendering multiple terrain types
/// Supports background layer (grass), terrain layer (water, rocks), and path layer (roads)
pub const MultiLayerTileMap = struct {
    background: TileLayer,
    terrain: TileLayer,
    paths: TileLayer,
    renderer: AutoTileRenderer,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, width: i32, height: i32, texture: rl.Texture2D) !MultiLayerTileMap {
        var renderer = AutoTileRenderer.init(allocator, texture);

        // Register terrain configs
        try renderer.registerTerrain(Terrain.GRASS, TilesetSpring.grassConfig());
        try renderer.registerTerrain(Terrain.ROAD, TilesetSpring.roadConfig());
        try renderer.registerTerrain(Terrain.WATER, TilesetSpring.waterConfig());

        // Initialize layers
        var background = try TileLayer.init(allocator, width, height);
        const terrain_layer = try TileLayer.init(allocator, width, height);
        const paths_layer = try TileLayer.init(allocator, width, height);

        // Fill background with grass by default
        background.fillRect(0, 0, width, height, Terrain.GRASS);

        return .{
            .background = background,
            .terrain = terrain_layer,
            .paths = paths_layer,
            .renderer = renderer,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *MultiLayerTileMap) void {
        self.background.deinit();
        self.terrain.deinit();
        self.paths.deinit();
        self.renderer.deinit();
    }

    /// Draw all layers in order (background -> terrain -> paths)
    pub fn draw(self: MultiLayerTileMap, tile_w: f32, tile_h: f32) void {
        self.drawWithOffset(0, 0, tile_w, tile_h);
    }

    pub fn drawBackground(self: MultiLayerTileMap, tile_w: f32, tile_h: f32) void {
        self.renderer.drawBackground(self.background, 0, 0, tile_w, tile_h);
    }

    pub fn drawWithOffset(self: MultiLayerTileMap, offset_x: f32, offset_y: f32, tile_w: f32, tile_h: f32) void {
        self.renderer.drawBackground(self.background, offset_x, offset_y, tile_w, tile_h);
        // self.renderer.drawLayerWithOffset(self.terrain, offset_x, offset_y, tile_w, tile_h);
        // self.renderer.drawLayerWithOffset(self.paths, offset_x, offset_y, tile_w, tile_h);
    }

    /// Create a tile map from a world_edit.json file for the background layer.
    /// Background cells default to GRASS (1), with WATER (3) and ROAD (2) applied from the JSON.
    pub fn initFromWorldEditFile(allocator: std.mem.Allocator, texture: rl.Texture2D, path: []const u8) !MultiLayerTileMap {
        var renderer = AutoTileRenderer.init(allocator, texture);

        // Register terrain configs
        try renderer.registerTerrain(Terrain.GRASS, TilesetSpring.grassConfig());
        try renderer.registerTerrain(Terrain.ROAD, TilesetSpring.roadConfig());
        try renderer.registerTerrain(Terrain.WATER, TilesetSpring.waterConfig());

        // Build background from JSON
        const background = try TileLayer.initFromWorldEditJson(allocator, path);
        const terrain_layer = try TileLayer.init(allocator, background.width, background.height);
        const paths_layer = try TileLayer.init(allocator, background.width, background.height);

        return .{
            .background = background,
            .terrain = terrain_layer,
            .paths = paths_layer,
            .renderer = renderer,
            .allocator = allocator,
        };
    }

    /// Create a tile map from a loaded World.
    /// Uses World's optional tiles grid for background; terrain/paths are empty.
    pub fn initFromWorld(allocator: std.mem.Allocator, texture: rl.Texture2D, world: anytype) !MultiLayerTileMap {
        var renderer = AutoTileRenderer.init(allocator, texture);

        // Register terrain configs
        try renderer.registerTerrain(Terrain.GRASS, TilesetSpring.grassConfig());
        try renderer.registerTerrain(Terrain.ROAD, TilesetSpring.roadConfig());
        try renderer.registerTerrain(Terrain.WATER, TilesetSpring.waterConfig());

        // Background from world tiles grid (or empty if none)
        const background = try TileLayer.initFromWorld(allocator, world);
        const terrain_layer = try TileLayer.init(allocator, background.width, background.height);
        const paths_layer = try TileLayer.init(allocator, background.width, background.height);

        return .{
            .background = background,
            .terrain = terrain_layer,
            .paths = paths_layer,
            .renderer = renderer,
            .allocator = allocator,
        };
    }

    /// Place a road at (x, y) on the paths layer
    pub fn setRoad(self: *MultiLayerTileMap, x: i32, y: i32) void {
        self.paths.set(x, y, Terrain.ROAD);
    }

    /// Place water at (x, y) on the terrain layer
    pub fn setWater(self: *MultiLayerTileMap, x: i32, y: i32) void {
        self.terrain.set(x, y, Terrain.WATER);
    }

    /// Draw a road path from (x1, y1) to (x2, y2)
    pub fn drawRoadPath(self: *MultiLayerTileMap, x1: i32, y1: i32, x2: i32, y2: i32) void {
        self.paths.drawLine(x1, y1, x2, y2, Terrain.ROAD);
    }

    /// Fill a rectangular region with water
    pub fn fillWater(self: *MultiLayerTileMap, x: i32, y: i32, w: i32, h: i32) void {
        self.terrain.fillRect(x, y, w, h, Terrain.WATER);
    }
};
