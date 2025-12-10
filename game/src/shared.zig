const std = @import("std");

pub const command = @import("movement/command.zig");
pub const MovementCommand = command.MovementCommand;
pub const MoveDirection = command.MoveDirection;
pub const network = @import("network.zig");
pub const PingPayload = network.PingPayload;
pub const landscape = @import("tiles/landscape.zig");
pub const LandscapeTile = landscape.LandscapeTile;
pub const drawLandscapeTile = landscape.drawLandscapeTile;
pub const tiles = @import("tiles/layer.zig");
pub const sheets = @import("tiles/sheets.zig");
pub const Frames = sheets.SpriteSet;
const t = @import("tiles/terrain.zig");
pub const TerrainType = t.TerrainType;

pub const menu = @import("ui/menu.zig");
pub const editor_map = @import("map/editor_map.zig");
pub const ghost_layer = @import("ui/ghost_layer.zig");
pub const placement = @import("ui/placement.zig");

pub const PlayerState = struct {
    x: f32,
    y: f32,
};

pub const CommandInput = union(enum) {
    movement: MovementCommand,
};

const WorldError = error{
    IndexOutOfBounds,
    MaxPlayersReached,
};

const Map = struct {
    const Self = @This();

    width: f32,
    height: f32,
};

// Building system
pub const BuildingType = enum {
    Townhall,
    House,
    Shop,
    Farm,
    Lake,
    Road,
};

// Building instance on the map - self-contained with all properties
pub const Building = struct {
    building_type: BuildingType,
    tile_x: i32,
    tile_y: i32,
    width_tiles: i32,
    height_tiles: i32,
    sprite_x: f32 = 0,
    sprite_y: f32 = 0,
    sprite_width: f32,
    sprite_height: f32,
};

// Map configuration - now with complete building data
// Removed MAP_BUILDINGS as it is now part of the World struct instance

pub const World = struct {
    width: f32,
    height: f32,
    tiles_x: i32,
    tiles_y: i32,
    /// Optional logical tiles grid (flattened row-major). Present for world_edit.json.
    tiles: []const u8 = &[_]u8{},
    /// Dimensions of the optional tiles grid above.
    tile_grid_x: i32 = 0,
    tile_grid_y: i32 = 0,
    buildings: []Building,

    pub fn loadFromFile(allocator: std.mem.Allocator, path: []const u8) !World {
        // Read the entire file
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        const file_size = try file.getEndPos();

        // Safety check: world files shouldn't be huge (limit to 10MB)
        const MAX_FILE_SIZE = 10 * 1024 * 1024;
        if (file_size > MAX_FILE_SIZE) {
            std.debug.print("World file too large: {} bytes (max: {} bytes)\n", .{ file_size, MAX_FILE_SIZE });
            return error.FileTooLarge;
        }

        // Allocate buffer with temporary allocator (will be freed when arena is deinit'd)
        const buffer = try allocator.alloc(u8, file_size);
        defer allocator.free(buffer);
        _ = try file.readAll(buffer);

        // Parse JSON with temporary allocator
        const parsed = try std.json.parseFromSlice(
            std.json.Value,
            allocator,
            buffer,
            .{},
        );
        defer parsed.deinit();

        const root = parsed.value.object;

        // Parse world dimensions
        const world_obj = root.get("world").?.object;
        const width = @as(f32, @floatFromInt(world_obj.get("width").?.integer));
        const height = @as(f32, @floatFromInt(world_obj.get("height").?.integer));
        const tiles_x = @as(i32, @intCast(world_obj.get("tiles_x").?.integer));
        const tiles_y = @as(i32, @intCast(world_obj.get("tiles_y").?.integer));

        // Parse buildings array
        const buildings_array = root.get("buildings").?.array;

        // Allocate buildings with the MAIN allocator (this persists after loading)
        const buildings = try allocator.alloc(Building, buildings_array.items.len);
        errdefer allocator.free(buildings);

        for (buildings_array.items, 0..) |building_obj, i| {
            const obj = building_obj.object;
            const type_str = obj.get("type").?.string;
            const tile_x = @as(i32, @intCast(obj.get("tile_x").?.integer));
            const tile_y = @as(i32, @intCast(obj.get("tile_y").?.integer));
            const width_tiles = @as(i32, @intCast(obj.get("width_tiles").?.integer));
            const height_tiles = @as(i32, @intCast(obj.get("height_tiles").?.integer));
            // sprite_x and sprite_y are optional (for backwards compatibility)
            const sprite_x: f32 = if (obj.get("sprite_x")) |v| @as(f32, @floatFromInt(v.integer)) else 0;
            const sprite_y: f32 = if (obj.get("sprite_y")) |v| @as(f32, @floatFromInt(v.integer)) else 0;
            const sprite_width = @as(f32, @floatFromInt(obj.get("sprite_width").?.integer));
            const sprite_height = @as(f32, @floatFromInt(obj.get("sprite_height").?.integer));

            const building_type = parseBuildingType(type_str) orelse {
                std.debug.print("Unknown building type: {s}\n", .{type_str});
                return error.InvalidBuildingType;
            };

            buildings[i] = Building{
                .building_type = building_type,
                .tile_x = tile_x,
                .tile_y = tile_y,
                .width_tiles = width_tiles,
                .height_tiles = height_tiles,
                .sprite_x = sprite_x,
                .sprite_y = sprite_y,
                .sprite_width = sprite_width,
                .sprite_height = sprite_height,
            };
        }

        // Optional: parse "tiles" grid (2D array) if present
        var tiles_slice: []const u8 = &[_]u8{};
        var tile_grid_x: i32 = 0;
        var tile_grid_y: i32 = 0;
        if (root.get("tiles")) |tiles_val| {
            const rows = tiles_val.array;
            tile_grid_y = @as(i32, @intCast(rows.items.len));
            if (tile_grid_y > 0) {
                const row0 = rows.items[0].array;
                tile_grid_x = @as(i32, @intCast(row0.items.len));
                const total = @as(usize, @intCast(tile_grid_x * tile_grid_y));
                var flat = try allocator.alloc(u8, total);
                errdefer allocator.free(flat);
                var iy: i32 = 0;
                while (iy < tile_grid_y) : (iy += 1) {
                    const row_arr = rows.items[@intCast(iy)].array;
                    var ix: i32 = 0;
                    while (ix < tile_grid_x) : (ix += 1) {
                        flat[@intCast(iy * tile_grid_x + ix)] = @as(u8, @intCast(row_arr.items[@intCast(ix)].integer));
                    }
                }
                tiles_slice = flat;
            }
        }

        // Arena allocator is destroyed here, freeing buffer and parsed JSON
        return World{
            .buildings = buildings[0..],
            .width = width,
            .height = height,
            .tiles_x = tiles_x,
            .tiles_y = tiles_y,
            .tile_grid_x = tile_grid_x,
            .tile_grid_y = tile_grid_y,
            .tiles = tiles_slice,
        };
    }

    pub fn deinit(self: *World, allocator: std.mem.Allocator) void {
        allocator.free(self.buildings);
        if (self.tiles.len > 0) allocator.free(self.tiles);
    }

    pub fn getTileAtPosition(self: World, x: f32, y: f32) TerrainType {
        // Clamp position to world bounds
        const clamped_x = std.math.clamp(x, 0, self.width);
        const clamped_y = std.math.clamp(y, 0, self.height);

        // Convert world position to tile coordinates
        const tx: i32 = @intFromFloat((clamped_x / self.width) * @as(f32, @floatFromInt(self.tiles_x)));
        const ty: i32 = @intFromFloat((clamped_y / self.height) * @as(f32, @floatFromInt(self.tiles_y)));

        // Check map configuration for roads
        for (self.buildings) |building| {
            if (building.building_type == .Road and building.tile_x == tx and building.tile_y == ty) {
                return .Road;
            }
        }

        // Apply same distance-based logic as main.zig::drawWorldTiles
        const center_x = @divTrunc(self.tiles_x, 2);
        const center_y = @divTrunc(self.tiles_y, 2);
        const dx = tx - center_x;
        const dy = ty - center_y;
        const dist_sq = dx * dx + dy * dy;

        if (dist_sq < 16) return .Water;
        if (dist_sq < 25) return .Rock;
        return .Grass;
    }

    pub fn isWalkable(terrain: TerrainType) bool {
        // Grass and Road are walkable
        return terrain == .Grass or terrain == .Road;
    }

    pub fn checkCollision(self: World, x: f32, y: f32, w: f32, h: f32, direction: command.MoveDirection) bool {
        // Define hitbox corners
        const left = x;
        const right = x + w;
        const top = y;
        const bottom = y + h;

        // Check points based on direction
        switch (direction) {
            .Up => {
                // Check top-left and top-right
                if (!isWalkable(self.getTileAtPosition(left, top)) or
                    !isWalkable(self.getTileAtPosition(right, top))) return true;
            },
            .Down => {
                // Check bottom-left and bottom-right
                if (!isWalkable(self.getTileAtPosition(left, bottom)) or
                    !isWalkable(self.getTileAtPosition(right, bottom))) return true;
            },
            .Left => {
                // Check top-left and bottom-left
                if (!isWalkable(self.getTileAtPosition(left, top)) or
                    !isWalkable(self.getTileAtPosition(left, bottom))) return true;
            },
            .Right => {
                // Check top-right and bottom-right
                if (!isWalkable(self.getTileAtPosition(right, top)) or
                    !isWalkable(self.getTileAtPosition(right, bottom))) return true;
            },
        }
        return false;
    }

    pub fn checkBuildingCollision(self: World, x: f32, y: f32, w: f32, h: f32) bool {
        const player_left = x;
        const player_right = x + w;
        const player_top = y;
        const player_bottom = y + h;

        const tile_w = self.width / @as(f32, @floatFromInt(self.tiles_x));
        const tile_h = self.height / @as(f32, @floatFromInt(self.tiles_y));

        for (self.buildings) |building| {
            // Skip roads for collision (they are walkable)
            if (building.building_type == .Road) continue;

            // Convert building tile coordinates to world pixels
            const building_x = @as(f32, @floatFromInt(building.tile_x)) * tile_w;
            const building_y = @as(f32, @floatFromInt(building.tile_y)) * tile_h;
            const building_w = @as(f32, @floatFromInt(building.width_tiles)) * tile_w;
            const building_h = @as(f32, @floatFromInt(building.height_tiles)) * tile_h;

            // Clamp building bounds to the world so we don't get
            // spurious collisions when a building sits on the edge.
            const building_left = @max(0.0, building_x);
            const building_top = @max(0.0, building_y);
            const building_right = @min(self.width, building_x + building_w);
            const building_bottom = @min(self.height, building_y + building_h);

            // AABB collision detection
            const overlaps_x = player_right > building_left and player_left < building_right;
            const overlaps_y = player_bottom > building_top and player_top < building_bottom;

            if (overlaps_x and overlaps_y) {
                return true;
            }
        }

        return false;
    }
    pub fn tileToWorldX(self: World, tile_x: i32) f32 {
        const tile_w = self.width / @as(f32, @floatFromInt(self.tiles_x));
        return @as(f32, @floatFromInt(tile_x)) * tile_w;
    }

    pub fn tileToWorldY(self: World, tile_y: i32) f32 {
        const tile_h = self.height / @as(f32, @floatFromInt(self.tiles_y));
        return @as(f32, @floatFromInt(tile_y)) * tile_h;
    }
};

/// Draw a grass background with a bordered edge, using the same layout
/// as the tile inspector. This keeps main.zig and tile_inspector.zig
/// using a single shared implementation.
pub fn drawGrassBackground(grass: Frames, world: World) void {
    const tile_w: f32 = world.width / @as(f32, @floatFromInt(world.tiles_x));
    const tile_h: f32 = world.height / @as(f32, @floatFromInt(world.tiles_y));

    var ty: i32 = 0;
    while (ty < world.tiles_y) : (ty += 1) {
        var tx: i32 = 0;
        while (tx < world.tiles_x) : (tx += 1) {
            const x = @as(f32, @floatFromInt(tx)) * tile_w;
            const y = @as(f32, @floatFromInt(ty)) * tile_h;

            const dir: LandscapeTile.Dir = blk: {
                const is_left = tx == 0;
                const is_right = tx == world.tiles_x - 1;
                const is_top = ty == 0;
                const is_bottom = ty == world.tiles_y - 1;

                if (is_left and is_top) break :blk .TopLeftCorner;
                if (is_right and is_top) break :blk .TopRightCorner;
                if (is_left and is_bottom) break :blk .BottomLeftCorner;
                if (is_right and is_bottom) break :blk .BottomRightCorner;
                if (is_left) break :blk .Left;
                if (is_right) break :blk .Right;
                if (is_top) break :blk .Top;
                if (is_bottom) break :blk .Bottom;
                break :blk .Center;
            };

            drawLandscapeTile(grass, dir, x, y);
        }
    }
}

pub const Room = struct {
    const Self = @This();

    players: []*PlayerState,
    width: f32,
    height: f32,

    // //
    // keys: []u64, // user IDs
    // slots: []u16, // assigned room index
    // states: []u8, // 0=EMPTY, 1=OCCUPIED, 2=TOMBSTONE

    pub fn init(_: usize) Self {
        // var players = [capacity]*PlayerState{};
        return Self{
            // .players = players[0..],
            // .width = 100.0,
            // .height = 100.0,
        };
    }

    pub fn calculatePlayerPosition(self: *Self, move: MovementCommand, idx: usize) WorldError!void {
        if (idx >= self.players.len) {
            return WorldError.IndexOutOfBounds;
        }
        var x = self.players[idx].x;
        var y = self.players[idx].y;
        switch (move.direction) {
            .Up => {
                y -= move.delta * move.speed;
            },
            .Down => {
                y += move.delta * move.speed;
            },
            .Left => {
                x -= move.delta * move.speed;
            },
            .Right => {
                x += move.delta * move.speed;
            },
        }
        if (x < 0.0 or x > self.width or y < 0.0 or y > self.height) {
            return WorldError.IndexOutOfBounds;
        }

        self.players[idx].x = x;
        self.players[idx].y = y;
    }
};

test "player move right" {
    const move = MovementCommand{
        .direction = .Right,
        .speed = 1.0,
        .delta = 0.5,
    };
    var player = PlayerState{
        .x = 0.0,
        .y = 0.0,
    };
    var players = [_]*PlayerState{&player};
    var world = Room{
        .players = players[0..],
        .width = 100.0,
        .height = 100.0,
    };
    const idx: usize = 0;
    try world.calculatePlayerPosition(move, idx);
    std.debug.print("pos {d}-{d}\n", .{ world.players[idx].x, world.players[idx].y });
    try std.testing.expectEqual(0.5, world.players[idx].x);
}

test "player move out of right boundary" {
    const move = MovementCommand{
        .direction = .Right,
        .speed = 1.0,
        .delta = 0.5,
    };
    var player = PlayerState{
        .x = 100.0,
        .y = 0.0,
    };
    var players = [_]*PlayerState{&player};
    var world = Room{
        .players = players[0..],
        .width = 100.0,
        .height = 100.0,
    };
    const idx: usize = 0;
    try std.testing.expectError(WorldError.IndexOutOfBounds, world.calculatePlayerPosition(move, idx));
}

fn parseBuildingType(type_str: []const u8) ?BuildingType {
    if (std.mem.eql(u8, type_str, "Townhall")) return .Townhall;
    if (std.mem.eql(u8, type_str, "House")) return .House;
    if (std.mem.eql(u8, type_str, "Shop")) return .Shop;
    if (std.mem.eql(u8, type_str, "Farm")) return .Farm;
    if (std.mem.eql(u8, type_str, "Lake")) return .Lake;
    if (std.mem.eql(u8, type_str, "Road")) return .Road;
    return null;
}

test "loadFromFile" {
    const allocator = std.testing.allocator;
    var world_data = try World.loadFromFile(allocator, "assets/world.json");
    defer world_data.deinit(allocator);

    try std.testing.expectEqual(@as(f32, 2000), world_data.width);
    try std.testing.expectEqual(@as(f32, 2000), world_data.height);
    try std.testing.expectEqual(@as(i32, 50), world_data.tiles_x);
    try std.testing.expectEqual(@as(i32, 50), world_data.tiles_y);
    try std.testing.expect(world_data.buildings.len > 0);
}
