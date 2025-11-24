const std = @import("std");
const shared = @import("shared.zig");
const Building = shared.Building;
const BuildingType = shared.BuildingType;

pub const WorldData = struct {
    buildings: []Building,
    width: f32,
    height: f32,
    tiles_x: i32,
    tiles_y: i32,

    pub fn deinit(self: *WorldData, allocator: std.mem.Allocator) void {
        allocator.free(self.buildings);
    }
};

pub fn loadFromFile(allocator: std.mem.Allocator, path: []const u8) !WorldData {
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
            .sprite_width = sprite_width,
            .sprite_height = sprite_height,
        };
    }

    // Arena allocator is destroyed here, freeing buffer and parsed JSON
    return WorldData{
        .buildings = buildings[0..],
        .width = width,
        .height = height,
        .tiles_x = tiles_x,
        .tiles_y = tiles_y,
    };
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
    var world_data = try loadFromFile(allocator, "assets/world.json");
    defer world_data.deinit(allocator);

    try std.testing.expectEqual(@as(f32, 2000), world_data.width);
    try std.testing.expectEqual(@as(f32, 2000), world_data.height);
    try std.testing.expectEqual(@as(i32, 50), world_data.tiles_x);
    try std.testing.expectEqual(@as(i32, 50), world_data.tiles_y);
    try std.testing.expect(world_data.buildings.len > 0);
}
