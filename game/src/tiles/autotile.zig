const std = @import("std");
const rl = @import("raylib");

/// 4-bit bitmask for cardinal neighbors:
/// - Bit 0 (1): North has same terrain
/// - Bit 1 (2): East has same terrain
/// - Bit 2 (4): South has same terrain
/// - Bit 3 (8): West has same terrain
///
/// This gives 16 combinations (0-15), each mapping to a specific sprite variant.
pub const TileMask = u4;

/// Represents a terrain type that can be auto-tiled
pub const TerrainId = u8;

/// Configuration for a single terrain's auto-tile sprites
/// Maps each of the 16 bitmask combinations to a sprite coordinate
pub const AutoTileConfig = struct {
    /// Sprite sheet coordinates for each bitmask (0-15)
    /// Each entry is [col, row] in tile units
    coords: [16][2]i32,

    /// Tile size in pixels (e.g., 16 for 16x16 tiles)
    tile_size: i32 = 16,

    pub fn fromBlock4x4(start_col: i32, start_row: i32) AutoTileConfig {
        // Named positions in 4x4 grid
        const tl = [2]i32{ start_col + 0, start_row + 0 }; // ┌ top-left corner
        const th = [2]i32{ start_col + 2, start_row + 0 }; // ─ top horizontal
        const tr = [2]i32{ start_col + 3, start_row + 0 }; // ┐ top-right corner

        const lv = [2]i32{ start_col + 0, start_row + 1 }; // │ left vertical
        const c1 = [2]i32{ start_col + 1, start_row + 1 }; // + center/cross
        const rv = [2]i32{ start_col + 3, start_row + 2 }; // │ right vertical

        const c3 = [2]i32{ start_col + 1, start_row + 2 }; // + center variant

        const bl = [2]i32{ start_col + 0, start_row + 3 }; // └ bottom-left corner
        const bh = [2]i32{ start_col + 1, start_row + 3 }; // ─ bottom horizontal
        const br = [2]i32{ start_col + 3, start_row + 3 }; // ┘ bottom-right corner

        // Bitmask: N(1) E(2) S(4) W(8)
        return .{
            .coords = .{
                c1, // 0 (0b0000): isolated → center
                bh, // 1 (0b0001): N only → bottom (opens north)
                lv, // 2 (0b0010): E only → left (opens east)
                bl, // 3 (0b0011): N+E → bottom-left corner
                th, // 4 (0b0100): S only → top (opens south)
                lv, // 5 (0b0101): N+S → left (vertical line)
                tl, // 6 (0b0110): E+S → top-left corner
                lv, // 7 (0b0111): N+E+S → left (T-junction)
                rv, // 8 (0b1000): W only → right (opens west)
                br, // 9 (0b1001): N+W → bottom-right corner
                th, // 10 (0b1010): E+W → top (horizontal line)
                bh, // 11 (0b1011): N+E+W → bottom (T-junction)
                tr, // 12 (0b1100): S+W → top-right corner
                rv, // 13 (0b1101): N+S+W → right (T-junction)
                th, // 14 (0b1110): E+S+W → top (T-junction)
                c3, // 15 (0b1111): all → center/cross
            },
        };
    }

    /// Creates config from a 3x3 block (Layout B - RPG Maker style)
    /// Sprite arrangement:
    ///   Row 0: ┌ ─ ┐  (top-left, top-edge, top-right)
    ///   Row 1: │ + │  (left-edge, center/cross, right-edge)
    ///   Row 2: └ ─ ┘  (bottom-left, bottom-edge, bottom-right)
    pub fn fromBlock3x3(start_col: i32, start_row: i32) AutoTileConfig {
        // Named positions in the 3x3 grid
        const tl = [2]i32{ start_col + 0, start_row + 0 }; // ┌ top-left corner
        const t = [2]i32{ start_col + 1, start_row + 0 }; // ─ top edge (horizontal)
        const tr = [2]i32{ start_col + 2, start_row + 0 }; // ┐ top-right corner
        const l = [2]i32{ start_col + 0, start_row + 1 }; // │ left edge (vertical)
        const c = [2]i32{ start_col + 1, start_row + 1 }; // + center/cross
        const r = [2]i32{ start_col + 2, start_row + 1 }; // │ right edge (vertical)
        const bl = [2]i32{ start_col + 0, start_row + 2 }; // └ bottom-left corner
        const b = [2]i32{ start_col + 1, start_row + 2 }; // ─ bottom edge (horizontal)
        const br = [2]i32{ start_col + 2, start_row + 2 }; // ┘ bottom-right corner

        // Bitmask: N(1) E(2) S(4) W(8)
        // Map each mask to the appropriate sprite based on which neighbors exist
        return .{
            .coords = .{
                c, // 0 (0b0000): isolated → center
                b, // 1 (0b0001): N only → bottom edge (opens north)
                l, // 2 (0b0010): E only → left edge (opens east)
                bl, // 3 (0b0011): N+E → bottom-left corner
                t, // 4 (0b0100): S only → top edge (opens south)
                l, // 5 (0b0101): N+S → left edge (vertical line)
                tl, // 6 (0b0110): E+S → top-left corner
                l, // 7 (0b0111): N+E+S → left edge (T-junction)
                r, // 8 (0b1000): W only → right edge (opens west)
                br, // 9 (0b1001): N+W → bottom-right corner
                t, // 10 (0b1010): E+W → top edge (horizontal line)
                b, // 11 (0b1011): N+E+W → bottom edge (T-junction)
                tr, // 12 (0b1100): S+W → top-right corner
                r, // 13 (0b1101): N+S+W → right edge (T-junction)
                t, // 14 (0b1110): E+S+W → top edge (T-junction)
                c, // 15 (0b1111): all → center/cross
            },
        };
    }

    /// Get the source rectangle for a given bitmask
    pub fn getSourceRect(self: AutoTileConfig, mask: TileMask) rl.Rectangle {
        const coords = self.coords[mask];
        return .{
            .x = @floatFromInt(coords[0] * self.tile_size),
            .y = @floatFromInt(coords[1] * self.tile_size),
            .width = @floatFromInt(self.tile_size),
            .height = @floatFromInt(self.tile_size),
        };
    }
};

/// A logical tile layer that stores terrain IDs and computes auto-tile masks
pub const TileLayer = struct {
    tiles: []TerrainId,
    width: i32,
    height: i32,
    allocator: std.mem.Allocator,

    /// Empty/air terrain ID (default for out-of-bounds)
    pub const EMPTY: TerrainId = 0;

    pub fn init(allocator: std.mem.Allocator, width: i32, height: i32) !TileLayer {
        const size = @as(usize, @intCast(width * height));
        const tiles = try allocator.alloc(TerrainId, size);
        @memset(tiles, EMPTY);

        return .{
            .tiles = tiles,
            .width = width,
            .height = height,
            .allocator = allocator,
        };
    }

    /// Initialize a tile layer from a worldedit.json-style file.
    /// Behavior:
    /// - Defaults every cell to GRASS (1)
    /// - Applies values from "tiles" grid:
    ///   - 3 -> WATER (3)
    ///   - 2 -> ROAD (2)
    ///   - 0/others -> GRASS (1)
    pub fn initFromWorldEditJson(allocator: std.mem.Allocator, file_path: []const u8) !TileLayer {
        // Read JSON file
        const file = try std.fs.cwd().openFile(file_path, .{});
        defer file.close();
        const file_size = try file.getEndPos();
        const buffer = try allocator.alloc(u8, file_size);
        defer allocator.free(buffer);
        _ = try file.readAll(buffer);

        // Parse as generic JSON value tree
        const parsed = try std.json.parseFromSlice(std.json.Value, allocator, buffer, .{});
        defer parsed.deinit();

        const root = parsed.value.object;
        const tiles_val = root.get("tiles") orelse return error.InvalidFormat;
        const tiles_arr = tiles_val.array;
        const height: i32 = @intCast(tiles_arr.items.len);
        if (height == 0) return error.InvalidFormat;
        const width: i32 = blk: {
            const row0 = tiles_arr.items[0].array;
            break :blk @as(i32, @intCast(row0.items.len));
        };

        var layer = try TileLayer.init(allocator, width, height);
        // Default to GRASS (1)
        layer.fillRect(0, 0, width, height, 1);

        var y: i32 = 0;
        while (y < height) : (y += 1) {
            const row = tiles_arr.items[@intCast(y)].array;
            var x: i32 = 0;
            while (x < width) : (x += 1) {
                const cell = row.items[@intCast(x)];
                const v = cell.integer;
                const id: TerrainId = switch (v) {
                    2 => 2, // ROAD
                    3 => 3, // WATER
                    else => 1, // GRASS
                };
                layer.set(x, y, id);
            }
        }

        return layer;
    }

    /// Initialize a tile layer from a loaded World.
    /// Uses the World's optional tiles grid if present; otherwise creates an empty layer.
    /// Mapping: 0/other -> GRASS(1), 2 -> ROAD(2), 3 -> WATER(3)
    pub fn initFromWorld(allocator: std.mem.Allocator, world: anytype) !TileLayer {
        if (world.tiles.len == 0 or world.tile_grid_x == 0 or world.tile_grid_y == 0) {
            return TileLayer.init(allocator, world.tiles_x, world.tiles_y);
        }

        const width: i32 = world.tile_grid_x;
        const height: i32 = world.tile_grid_y;
        var layer = try TileLayer.init(allocator, width, height);
        // Default to GRASS (1)
        layer.fillRect(0, 0, width, height, 1);

        var y: i32 = 0;
        while (y < height) : (y += 1) {
            var x: i32 = 0;
            while (x < width) : (x += 1) {
                const v = world.tiles[@intCast(y * width + x)];
                const id: TerrainId = switch (v) {
                    2 => 2, // ROAD
                    3 => 3, // WATER
                    else => 1, // GRASS
                };
                layer.set(x, y, id);
            }
        }

        return layer;
    }

    pub fn deinit(self: *TileLayer) void {
        self.allocator.free(self.tiles);
    }

    /// Get terrain at (x, y), returns EMPTY for out-of-bounds
    pub fn get(self: TileLayer, x: i32, y: i32) TerrainId {
        if (x < 0 or y < 0 or x >= self.width or y >= self.height) {
            return EMPTY;
        }
        return self.tiles[@intCast(y * self.width + x)];
    }

    /// Set terrain at (x, y)
    pub fn set(self: *TileLayer, x: i32, y: i32, terrain: TerrainId) void {
        if (x < 0 or y < 0 or x >= self.width or y >= self.height) {
            return;
        }
        self.tiles[@intCast(y * self.width + x)] = terrain;
    }

    /// Compute 4-bit bitmask for auto-tiling at (x, y)
    /// Bits: N(1) E(2) S(4) W(8)
    pub fn computeMask(self: TileLayer, x: i32, y: i32) TileMask {
        const terrain = self.get(x, y);
        if (terrain == EMPTY) return 0;

        var mask: TileMask = 0;

        // Check each cardinal direction
        if (self.get(x, y - 1) == terrain) mask |= 0b0001; // North
        if (self.get(x + 1, y) == terrain) mask |= 0b0010; // East
        if (self.get(x, y + 1) == terrain) mask |= 0b0100; // South
        if (self.get(x - 1, y) == terrain) mask |= 0b1000; // West

        return mask;
    }

    /// Fill a rectangular region with a terrain type
    pub fn fillRect(self: *TileLayer, x: i32, y: i32, w: i32, h: i32, terrain: TerrainId) void {
        var ty = y;
        while (ty < y + h) : (ty += 1) {
            var tx = x;
            while (tx < x + w) : (tx += 1) {
                self.set(tx, ty, terrain);
            }
        }
    }

    /// Draw a line of terrain (horizontal or vertical)
    pub fn drawLine(self: *TileLayer, x1: i32, y1: i32, x2: i32, y2: i32, terrain: TerrainId) void {
        const dx: i32 = if (x2 > x1) 1 else if (x2 < x1) -1 else 0;
        const dy: i32 = if (y2 > y1) 1 else if (y2 < y1) -1 else 0;

        var x = x1;
        var y = y1;
        while (true) {
            self.set(x, y, terrain);
            if (x == x2 and y == y2) break;
            x += dx;
            y += dy;
        }
    }
};

/// Renderer for auto-tiled layers
pub const AutoTileRenderer = struct {
    texture: rl.Texture2D,
    configs: std.AutoHashMap(TerrainId, AutoTileConfig),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, texture: rl.Texture2D) AutoTileRenderer {
        return .{
            .texture = texture,
            .configs = std.AutoHashMap(TerrainId, AutoTileConfig).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *AutoTileRenderer) void {
        self.configs.deinit();
    }

    /// Register an auto-tile configuration for a terrain type
    pub fn registerTerrain(self: *AutoTileRenderer, terrain_id: TerrainId, config: AutoTileConfig) !void {
        try self.configs.put(terrain_id, config);
    }

    /// Draw a tile layer with auto-tiling
    pub fn drawLayer(self: AutoTileRenderer, layer: TileLayer, dest_tile_w: f32, dest_tile_h: f32) void {
        self.drawLayerWithOffset(layer, 0, 0, dest_tile_w, dest_tile_h);
    }

    pub fn drawBackground(self: AutoTileRenderer, layer: TileLayer, offset_x: f32, offset_y: f32, dest_tile_w: f32, dest_tile_h: f32) void {
        var ty: i32 = 0;
        while (ty < layer.height) : (ty += 1) {
            var tx: i32 = 0;
            while (tx < layer.width) : (tx += 1) {
                const config = self.configs.get(1) orelse continue;
                var coords: [2]i32 = .{ 8, 0 };
                if (tx == 0) {
                    if (ty == layer.height - 1) {
                        coords[1] += 3;
                    } else if (ty > 0) {
                        coords[1] += 1;
                    }
                } else if (tx == layer.width - 1) {
                    if (ty == layer.height - 1) {
                        coords[0] += 3;
                        coords[1] += 3;
                    } else if (ty == 0) {
                        coords[0] += 3;
                    } else {
                        coords[0] += 3;
                        coords[1] += 2;
                    }
                } else if (ty == 0) {
                    coords[0] += 2;
                } else if (ty == layer.height - 1) {
                    coords[0] += 1;
                    coords[1] += 3;
                } else {
                    coords[0] += 1;
                    coords[1] += 2;
                }
                const src: rl.Rectangle = .{
                    .x = @floatFromInt(coords[0] * config.tile_size),
                    .y = @floatFromInt(coords[1] * config.tile_size),
                    .width = @floatFromInt(config.tile_size),
                    .height = @floatFromInt(config.tile_size),
                };

                const dest = rl.Rectangle{
                    .x = offset_x + @as(f32, @floatFromInt(tx)) * dest_tile_w,
                    .y = offset_y + @as(f32, @floatFromInt(ty)) * dest_tile_h,
                    .width = dest_tile_w,
                    .height = dest_tile_h,
                };

                rl.drawTexturePro(self.texture, src, dest, .{ .x = 0, .y = 0 }, 0, .white);
            }
        }
    }

    /// Draw a tile layer with world offset
    pub fn drawLayerWithOffset(self: AutoTileRenderer, layer: TileLayer, offset_x: f32, offset_y: f32, dest_tile_w: f32, dest_tile_h: f32) void {
        var ty: i32 = 0;
        while (ty < layer.height) : (ty += 1) {
            var tx: i32 = 0;
            while (tx < layer.width) : (tx += 1) {
                const terrain = layer.get(tx, ty);
                if (terrain == TileLayer.EMPTY) continue;

                const config = self.configs.get(terrain) orelse continue;
                const mask = layer.computeMask(tx, ty);
                const src = config.getSourceRect(mask);

                const dest = rl.Rectangle{
                    .x = offset_x + @as(f32, @floatFromInt(tx)) * dest_tile_w,
                    .y = offset_y + @as(f32, @floatFromInt(ty)) * dest_tile_h,
                    .width = dest_tile_w,
                    .height = dest_tile_h,
                };

                rl.drawTexturePro(self.texture, src, dest, .{ .x = 0, .y = 0 }, 0, .white);
            }
        }
    }

    /// Draw a single tile at world position (useful for editor preview)
    pub fn drawTile(self: AutoTileRenderer, terrain: TerrainId, mask: TileMask, dest: rl.Rectangle) void {
        const config = self.configs.get(terrain) orelse return;
        const src = config.getSourceRect(mask);
        rl.drawTexturePro(self.texture, src, dest, .{ .x = 0, .y = 0 }, 0, .white);
    }
};

// --- Tests ---

test "TileLayer basic operations" {
    var layer = try TileLayer.init(std.testing.allocator, 10, 10);
    defer layer.deinit();

    // Default is empty
    try std.testing.expectEqual(TileLayer.EMPTY, layer.get(5, 5));

    // Set and get
    layer.set(5, 5, 1);
    try std.testing.expectEqual(@as(TerrainId, 1), layer.get(5, 5));

    // Out of bounds returns empty
    try std.testing.expectEqual(TileLayer.EMPTY, layer.get(-1, 0));
    try std.testing.expectEqual(TileLayer.EMPTY, layer.get(100, 0));
}

test "TileLayer computeMask" {
    var layer = try TileLayer.init(std.testing.allocator, 5, 5);
    defer layer.deinit();

    // Create a cross pattern
    //   1
    // 1 1 1
    //   1
    layer.set(2, 1, 1); // North
    layer.set(1, 2, 1); // West
    layer.set(2, 2, 1); // Center
    layer.set(3, 2, 1); // East
    layer.set(2, 3, 1); // South

    // Center should have all 4 neighbors
    try std.testing.expectEqual(@as(TileMask, 0b1111), layer.computeMask(2, 2));

    // North tile has only South neighbor
    try std.testing.expectEqual(@as(TileMask, 0b0100), layer.computeMask(2, 1));

    // West tile has only East neighbor
    try std.testing.expectEqual(@as(TileMask, 0b0010), layer.computeMask(1, 2));
}

test "AutoTileConfig fromBlock4x4" {
    const config = AutoTileConfig.fromBlock4x4(0, 0);

    // Isolated tile (mask 0) should be at (0, 0)
    try std.testing.expectEqual(@as(i32, 0), config.coords[0][0]);
    try std.testing.expectEqual(@as(i32, 0), config.coords[0][1]);

    // Cross/center (mask 15) should be at (3, 3)
    try std.testing.expectEqual(@as(i32, 3), config.coords[15][0]);
    try std.testing.expectEqual(@as(i32, 3), config.coords[15][1]);
}
