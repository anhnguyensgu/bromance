//! Dynamic Map module for the tile map editor
//! Supports variable-sized maps with JSON serialization/deserialization

const std = @import("std");
const rl = @import("raylib");

/// Tile ID type - u16 allows for up to 65535 different tile types
pub const TileId = u16;

/// Empty tile constant
pub const EMPTY_TILE: TileId = 0;

/// Layer types for multi-layer support
pub const LayerType = enum {
    Ground,
    Terrain,
    Objects,
    Collision,
};

/// A single layer of tiles
pub const TileLayer = struct {
    const Self = @This();

    name: []const u8,
    layer_type: LayerType,
    tiles: []TileId,
    visible: bool = true,

    allocator: std.mem.Allocator,

    /// Initialize a new tile layer with the given dimensions
    pub fn init(allocator: std.mem.Allocator, name: []const u8, layer_type: LayerType, width: u32, height: u32) !Self {
        const size = @as(usize, width) * @as(usize, height);
        const tiles = try allocator.alloc(TileId, size);
        @memset(tiles, EMPTY_TILE);

        // Duplicate the name so we own it
        const owned_name = try allocator.dupe(u8, name);

        return Self{
            .name = owned_name,
            .layer_type = layer_type,
            .tiles = tiles,
            .visible = true,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.tiles);
        self.allocator.free(self.name);
    }

    /// Get tile at (x, y) given map width
    pub fn getTile(self: *const Self, x: u32, y: u32, map_width: u32) ?TileId {
        const index = @as(usize, y) * @as(usize, map_width) + @as(usize, x);
        if (index >= self.tiles.len) return null;
        return self.tiles[index];
    }

    /// Set tile at (x, y) given map width
    pub fn setTile(self: *Self, x: u32, y: u32, map_width: u32, tile_id: TileId) void {
        const index = @as(usize, y) * @as(usize, map_width) + @as(usize, x);
        if (index < self.tiles.len) {
            self.tiles[index] = tile_id;
        }
    }

    /// Resize the layer (data will be cleared)
    pub fn resize(self: *Self, new_width: u32, new_height: u32) !void {
        const new_size = @as(usize, new_width) * @as(usize, new_height);
        self.allocator.free(self.tiles);
        self.tiles = try self.allocator.alloc(TileId, new_size);
        @memset(self.tiles, EMPTY_TILE);
    }
};

/// Main Map struct with dynamic dimensions
pub const Map = struct {
    const Self = @This();

    /// Map dimensions in tiles
    width: u32,
    height: u32,

    /// Tile size in pixels
    tile_width: u32 = 16,
    tile_height: u32 = 16,

    /// Layers (dynamic array using slice)
    layers: []TileLayer,
    layer_count: usize,
    layer_capacity: usize,

    /// Allocator for memory management
    allocator: std.mem.Allocator,

    /// Map metadata
    name: []const u8 = "Untitled",

    /// Initialize a new empty map
    pub fn init(allocator: std.mem.Allocator, width: u32, height: u32) !Self {
        // Start with capacity for 4 layers
        const initial_capacity: usize = 4;
        const layers = try allocator.alloc(TileLayer, initial_capacity);

        var map = Self{
            .width = width,
            .height = height,
            .layers = layers,
            .layer_count = 0,
            .layer_capacity = initial_capacity,
            .allocator = allocator,
        };

        // Create default ground layer
        try map.addLayer("Ground", .Ground);

        return map;
    }

    /// Initialize with custom tile size
    pub fn initWithTileSize(
        allocator: std.mem.Allocator,
        width: u32,
        height: u32,
        tile_width: u32,
        tile_height: u32,
    ) !Self {
        var map = try init(allocator, width, height);
        map.tile_width = tile_width;
        map.tile_height = tile_height;
        return map;
    }

    pub fn deinit(self: *Self) void {
        for (self.layers[0..self.layer_count]) |*layer| {
            layer.deinit();
        }
        self.allocator.free(self.layers);
    }

    /// Add a new layer
    pub fn addLayer(self: *Self, name: []const u8, layer_type: LayerType) !void {
        // Grow capacity if needed
        if (self.layer_count >= self.layer_capacity) {
            const new_capacity = self.layer_capacity * 2;
            const new_layers = try self.allocator.realloc(self.layers, new_capacity);
            self.layers = new_layers;
            self.layer_capacity = new_capacity;
        }

        const layer = try TileLayer.init(self.allocator, name, layer_type, self.width, self.height);
        self.layers[self.layer_count] = layer;
        self.layer_count += 1;
    }

    /// Get layer by index
    pub fn getLayer(self: *Self, index: usize) ?*TileLayer {
        if (index >= self.layer_count) return null;
        return &self.layers[index];
    }

    /// Get layer by name
    pub fn getLayerByName(self: *Self, name: []const u8) ?*TileLayer {
        for (self.layers[0..self.layer_count]) |*layer| {
            if (std.mem.eql(u8, layer.name, name)) {
                return layer;
            }
        }
        return null;
    }

    /// Get tile from the first layer at position
    pub fn getTile(self: *const Self, x: u32, y: u32) ?TileId {
        if (self.layer_count == 0) return null;
        return self.layers[0].getTile(x, y, self.width);
    }

    /// Set tile on the first layer at position
    pub fn setTile(self: *Self, x: u32, y: u32, tile_id: TileId) void {
        if (self.layer_count == 0) return;
        self.layers[0].setTile(x, y, self.width, tile_id);
    }

    /// Get tile from specific layer
    pub fn getTileOnLayer(self: *const Self, layer_index: usize, x: u32, y: u32) ?TileId {
        if (layer_index >= self.layer_count) return null;
        return self.layers[layer_index].getTile(x, y, self.width);
    }

    /// Set tile on specific layer
    pub fn setTileOnLayer(self: *Self, layer_index: usize, x: u32, y: u32, tile_id: TileId) void {
        if (layer_index >= self.layer_count) return;
        self.layers[layer_index].setTile(x, y, self.width, tile_id);
    }

    /// Resize the map (all layers will be cleared)
    pub fn resize(self: *Self, new_width: u32, new_height: u32) !void {
        self.width = new_width;
        self.height = new_height;
        for (self.layers[0..self.layer_count]) |*layer| {
            try layer.resize(new_width, new_height);
        }
    }

    /// Get world width in pixels
    pub fn getWorldWidth(self: *const Self) f32 {
        return @as(f32, @floatFromInt(self.width * self.tile_width));
    }

    /// Get world height in pixels
    pub fn getWorldHeight(self: *const Self) f32 {
        return @as(f32, @floatFromInt(self.height * self.tile_height));
    }

    /// Convert world position to tile coordinates
    pub fn worldToTile(self: *const Self, world_x: f32, world_y: f32) struct { x: i32, y: i32 } {
        const tx = @divFloor(@as(i32, @intFromFloat(world_x)), @as(i32, @intCast(self.tile_width)));
        const ty = @divFloor(@as(i32, @intFromFloat(world_y)), @as(i32, @intCast(self.tile_height)));
        return .{ .x = tx, .y = ty };
    }

    /// Convert tile coordinates to world position (top-left corner)
    pub fn tileToWorld(self: *const Self, tile_x: i32, tile_y: i32) struct { x: f32, y: f32 } {
        const wx = @as(f32, @floatFromInt(tile_x)) * @as(f32, @floatFromInt(self.tile_width));
        const wy = @as(f32, @floatFromInt(tile_y)) * @as(f32, @floatFromInt(self.tile_height));
        return .{ .x = wx, .y = wy };
    }

    /// Check if tile coordinates are within bounds
    pub fn isInBounds(self: *const Self, x: i32, y: i32) bool {
        return x >= 0 and y >= 0 and
            x < @as(i32, @intCast(self.width)) and
            y < @as(i32, @intCast(self.height));
    }

    // ============================================================
    // JSON Serialization
    // ============================================================

    /// JSON structure for serialization
    const JsonMap = struct {
        name: []const u8,
        width: u32,
        height: u32,
        tile_width: u32,
        tile_height: u32,
        layers: []const JsonLayer,
    };

    const JsonLayer = struct {
        name: []const u8,
        layer_type: []const u8,
        visible: bool,
        tiles: []const TileId,
    };

    /// Save map to JSON file
    pub fn saveToFile(self: *const Self, filename: []const u8) !void {
        // Create file
        const file = try std.fs.cwd().createFile(filename, .{});
        defer file.close();

        // Build JSON string manually
        var buffer: [1024 * 1024]u8 = undefined; // 1MB buffer
        var fbs = std.io.fixedBufferStream(&buffer);
        const writer = fbs.writer();

        try self.writeJson(writer);

        // Write to file
        _ = try file.writeAll(fbs.getWritten());
    }

    /// Write map as JSON to any writer
    pub fn writeJson(self: *const Self, writer: anytype) !void {
        // Write JSON manually for compatibility
        try writer.writeAll("{\n");
        try writer.print("  \"name\": \"{s}\",\n", .{self.name});
        try writer.print("  \"width\": {},\n", .{self.width});
        try writer.print("  \"height\": {},\n", .{self.height});
        try writer.print("  \"tile_width\": {},\n", .{self.tile_width});
        try writer.print("  \"tile_height\": {},\n", .{self.tile_height});
        try writer.writeAll("  \"layers\": [\n");

        for (self.layers[0..self.layer_count], 0..) |layer, layer_idx| {
            try writer.writeAll("    {\n");
            try writer.print("      \"name\": \"{s}\",\n", .{layer.name});
            try writer.print("      \"layer_type\": \"{s}\",\n", .{@tagName(layer.layer_type)});
            try writer.print("      \"visible\": {},\n", .{layer.visible});
            try writer.writeAll("      \"tiles\": [");

            for (layer.tiles, 0..) |tile, i| {
                if (i > 0) try writer.writeAll(", ");
                try writer.print("{}", .{tile});
            }

            try writer.writeAll("]\n");
            try writer.writeAll("    }");
            if (layer_idx < self.layer_count - 1) {
                try writer.writeAll(",");
            }
            try writer.writeAll("\n");
        }

        try writer.writeAll("  ]\n");
        try writer.writeAll("}\n");
    }

    /// Load map from JSON file
    pub fn loadFromFile(allocator: std.mem.Allocator, filename: []const u8) !Self {
        const file = try std.fs.cwd().openFile(filename, .{});
        defer file.close();

        const file_size = try file.getEndPos();

        // Safety check
        const MAX_FILE_SIZE = 50 * 1024 * 1024; // 50MB limit
        if (file_size > MAX_FILE_SIZE) {
            return error.FileTooLarge;
        }

        const buffer = try allocator.alloc(u8, file_size);
        defer allocator.free(buffer);
        _ = try file.readAll(buffer);

        return try parseJson(allocator, buffer);
    }

    /// Parse JSON buffer into Map
    pub fn parseJson(allocator: std.mem.Allocator, json_buffer: []const u8) !Self {
        const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_buffer, .{});
        defer parsed.deinit();

        const root = parsed.value.object;

        // Parse basic properties
        const width = @as(u32, @intCast(root.get("width").?.integer));
        const height = @as(u32, @intCast(root.get("height").?.integer));
        const tile_width = if (root.get("tile_width")) |v| @as(u32, @intCast(v.integer)) else 16;
        const tile_height = if (root.get("tile_height")) |v| @as(u32, @intCast(v.integer)) else 16;

        // Count layers
        var layer_count: usize = 0;
        if (root.get("layers")) |layers_val| {
            layer_count = layers_val.array.items.len;
        }
        if (layer_count == 0) layer_count = 1; // At least one default layer

        const initial_capacity = @max(layer_count, 4);
        const layers = try allocator.alloc(TileLayer, initial_capacity);

        var map = Self{
            .width = width,
            .height = height,
            .tile_width = tile_width,
            .tile_height = tile_height,
            .layers = layers,
            .layer_count = 0,
            .layer_capacity = initial_capacity,
            .allocator = allocator,
        };
        errdefer map.deinit();

        // Parse layers
        if (root.get("layers")) |layers_val| {
            const layers_array = layers_val.array;
            for (layers_array.items) |layer_val| {
                const layer_obj = layer_val.object;

                const name = layer_obj.get("name").?.string;
                const layer_type_str = layer_obj.get("layer_type").?.string;
                const visible = if (layer_obj.get("visible")) |v| v.bool else true;

                const layer_type = parseLayerType(layer_type_str);

                var layer = try TileLayer.init(allocator, name, layer_type, width, height);
                layer.visible = visible;

                // Parse tiles
                if (layer_obj.get("tiles")) |tiles_val| {
                    const tiles_array = tiles_val.array;
                    for (tiles_array.items, 0..) |tile_val, i| {
                        if (i < layer.tiles.len) {
                            layer.tiles[i] = @as(TileId, @intCast(tile_val.integer));
                        }
                    }
                }

                map.layers[map.layer_count] = layer;
                map.layer_count += 1;
            }
        }

        // If no layers were loaded, create a default ground layer
        if (map.layer_count == 0) {
            const ground_layer = try TileLayer.init(allocator, "Ground", .Ground, width, height);
            map.layers[0] = ground_layer;
            map.layer_count = 1;
        }

        return map;
    }

    fn parseLayerType(type_str: []const u8) LayerType {
        if (std.mem.eql(u8, type_str, "Ground")) return .Ground;
        if (std.mem.eql(u8, type_str, "Terrain")) return .Terrain;
        if (std.mem.eql(u8, type_str, "Objects")) return .Objects;
        if (std.mem.eql(u8, type_str, "Collision")) return .Collision;
        return .Ground; // default
    }

    // ============================================================
    // Drawing utilities (requires raylib)
    // ============================================================

    /// Draw the map using a tileset texture
    /// tile_source_fn: function that returns source rectangle for a tile ID
    pub fn draw(
        self: *const Self,
        tileset: rl.Texture2D,
        camera: rl.Camera2D,
        tile_source_fn: *const fn (TileId) rl.Rectangle,
    ) void {
        // Calculate visible tile range based on camera
        const screen_width = rl.getScreenWidth();
        const screen_height = rl.getScreenHeight();

        const top_left = rl.getScreenToWorld2D(.{ .x = 0, .y = 0 }, camera);
        const bottom_right = rl.getScreenToWorld2D(
            .{ .x = @floatFromInt(screen_width), .y = @floatFromInt(screen_height) },
            camera,
        );

        const start_tile = self.worldToTile(top_left.x, top_left.y);
        const end_tile = self.worldToTile(bottom_right.x, bottom_right.y);

        // Clamp to map bounds with some padding
        const start_x = @max(0, start_tile.x - 1);
        const start_y = @max(0, start_tile.y - 1);
        const end_x = @min(@as(i32, @intCast(self.width)), end_tile.x + 2);
        const end_y = @min(@as(i32, @intCast(self.height)), end_tile.y + 2);

        // Draw each visible layer
        for (self.layers[0..self.layer_count]) |layer| {
            if (!layer.visible) continue;

            var ty: i32 = start_y;
            while (ty < end_y) : (ty += 1) {
                var tx: i32 = start_x;
                while (tx < end_x) : (tx += 1) {
                    const tile_id = layer.getTile(
                        @intCast(tx),
                        @intCast(ty),
                        self.width,
                    ) orelse continue;

                    if (tile_id == EMPTY_TILE) continue;

                    const world_pos = self.tileToWorld(tx, ty);
                    const src_rect = tile_source_fn(tile_id);
                    const dest_rect = rl.Rectangle{
                        .x = world_pos.x,
                        .y = world_pos.y,
                        .width = @floatFromInt(self.tile_width),
                        .height = @floatFromInt(self.tile_height),
                    };

                    rl.drawTexturePro(
                        tileset,
                        src_rect,
                        dest_rect,
                        .{ .x = 0, .y = 0 },
                        0,
                        rl.Color.white,
                    );
                }
            }
        }
    }

    /// Draw grid overlay
    pub fn drawGrid(self: *const Self, color: rl.Color) void {
        const tw = @as(f32, @floatFromInt(self.tile_width));
        const th = @as(f32, @floatFromInt(self.tile_height));
        const world_w = self.getWorldWidth();
        const world_h = self.getWorldHeight();

        // Vertical lines
        var x: u32 = 0;
        while (x <= self.width) : (x += 1) {
            const px = @as(f32, @floatFromInt(x)) * tw;
            rl.drawLineV(
                .{ .x = px, .y = 0 },
                .{ .x = px, .y = world_h },
                color,
            );
        }

        // Horizontal lines
        var y: u32 = 0;
        while (y <= self.height) : (y += 1) {
            const py = @as(f32, @floatFromInt(y)) * th;
            rl.drawLineV(
                .{ .x = 0, .y = py },
                .{ .x = world_w, .y = py },
                color,
            );
        }
    }
};

// ============================================================
// Standalone saveWorld function for compatibility
// ============================================================

/// Save a Map to a JSON file (standalone function)
pub fn saveWorld(map: *const Map, filename: []const u8) !void {
    try map.saveToFile(filename);
}

// ============================================================
// Tests
// ============================================================

test "Map: create and basic operations" {
    const allocator = std.testing.allocator;

    var map = try Map.init(allocator, 10, 10);
    defer map.deinit();

    // Test dimensions
    try std.testing.expectEqual(@as(u32, 10), map.width);
    try std.testing.expectEqual(@as(u32, 10), map.height);

    // Test tile operations
    map.setTile(5, 5, 42);
    try std.testing.expectEqual(@as(?TileId, 42), map.getTile(5, 5));

    // Test bounds
    try std.testing.expect(map.isInBounds(0, 0));
    try std.testing.expect(map.isInBounds(9, 9));
    try std.testing.expect(!map.isInBounds(-1, 0));
    try std.testing.expect(!map.isInBounds(10, 0));
}

test "Map: JSON serialization roundtrip" {
    const allocator = std.testing.allocator;

    // Create a map with some data
    var original = try Map.init(allocator, 5, 5);
    defer original.deinit();

    original.setTile(0, 0, 1);
    original.setTile(2, 2, 2);
    original.setTile(4, 4, 3);

    // Serialize to JSON string using fixed buffer
    var buffer: [1024 * 64]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);

    try original.writeJson(fbs.writer());
    const json_output = fbs.getWritten();

    // Parse back
    var loaded = try Map.parseJson(allocator, json_output);
    defer loaded.deinit();

    // Verify
    try std.testing.expectEqual(original.width, loaded.width);
    try std.testing.expectEqual(original.height, loaded.height);
    try std.testing.expectEqual(original.getTile(0, 0), loaded.getTile(0, 0));
    try std.testing.expectEqual(original.getTile(2, 2), loaded.getTile(2, 2));
    try std.testing.expectEqual(original.getTile(4, 4), loaded.getTile(4, 4));
}

test "Map: resize" {
    const allocator = std.testing.allocator;

    var map = try Map.init(allocator, 10, 10);
    defer map.deinit();

    map.setTile(5, 5, 42);
    try map.resize(20, 20);

    try std.testing.expectEqual(@as(u32, 20), map.width);
    try std.testing.expectEqual(@as(u32, 20), map.height);
    // Data should be cleared after resize
    try std.testing.expectEqual(@as(?TileId, 0), map.getTile(5, 5));
}

test "Map: multiple layers" {
    const allocator = std.testing.allocator;

    var map = try Map.init(allocator, 10, 10);
    defer map.deinit();

    try map.addLayer("Objects", .Objects);
    try map.addLayer("Collision", .Collision);

    try std.testing.expectEqual(@as(usize, 3), map.layer_count);

    // Set tiles on different layers
    map.setTileOnLayer(0, 5, 5, 1);
    map.setTileOnLayer(1, 5, 5, 2);
    map.setTileOnLayer(2, 5, 5, 3);

    try std.testing.expectEqual(@as(?TileId, 1), map.getTileOnLayer(0, 5, 5));
    try std.testing.expectEqual(@as(?TileId, 2), map.getTileOnLayer(1, 5, 5));
    try std.testing.expectEqual(@as(?TileId, 3), map.getTileOnLayer(2, 5, 5));
}
