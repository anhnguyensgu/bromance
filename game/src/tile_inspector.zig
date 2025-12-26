const std = @import("std");
const rl = @import("raylib");
const shared = @import("shared");
const Menu = shared.menu.Menu;
const MenuItem = shared.menu.MenuItem;

// Import the new auto-tile system
const tiles = shared.tiles;
const TileLayer = tiles.TileLayer;
const AutoTileConfig = tiles.AutoTileConfig;
const AutoTileRenderer = tiles.AutoTileRenderer;
const Terrain = tiles.Terrain;
const MultiLayerTileMap = tiles.MultiLayerTileMap;

// Shared landscape/frames types
const sheets = shared.sheets;
pub const LandscapeTile = shared.LandscapeTile;
pub const Frames = shared.Frames;
const drawGrassBackground = shared.drawGrassBackground;

// Import the placement system
const placement = shared.placement;
const PlacementSystem = placement.PlacementSystem;
const PlaceableItem = placement.PlaceableItem;

// Import the new dynamic Map system
const editor_map = shared.editor_map;
const Map = editor_map.Map;
const TileId = editor_map.TileId;

// Shared GhostLayer for applying placement results
const GhostLayer = shared.ghost_layer.GhostLayer;

// Global editor map reference for save callback
var g_editor_map: ?*Map = null;
var g_allocator: ?std.mem.Allocator = null;
var g_placed_items: ?*std.ArrayList(placement.PlacedItem) = null;

// Sidebar layout constants
const SIDEBAR_WIDTH: f32 = 250.0;

pub fn main() !void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "Tiles Test App");
    defer rl.closeWindow();

    // Disable escape key from closing the window
    rl.setExitKey(.null);

    rl.setTargetFPS(60);

    // Load Assets
    var tileset_img = try rl.loadImage("assets/farmrpg/tileset/tilesetspring.png");
    // Apply color keying for transparency (Black -> Transparent)
    rl.imageColorReplace(&tileset_img, rl.Color.black, rl.Color.blank);
    defer rl.unloadImage(tileset_img);

    const tileset_texture = try rl.loadTextureFromImage(tileset_img);
    defer rl.unloadTexture(tileset_texture);

    // Use point filtering to prevent pixel bleeding between tiles
    rl.setTextureFilter(tileset_texture, .point);

    const house_img = try rl.loadImage("assets/farmrpg/objects/house.png");
    defer rl.unloadImage(house_img);
    const house_texture = try rl.loadTextureFromImage(house_img);
    defer rl.unloadTexture(house_texture);
    rl.setTextureFilter(house_texture, .point);

    const house_sprites = shared.sheets.SpriteSet.HouseSheet(house_texture);
    defer house_sprites.House.deinit();

    const lake_img = try rl.loadImage("assets/lakesmall.png");
    defer rl.unloadImage(lake_img);
    const lake_texture = try rl.loadTextureFromImage(lake_img);
    rl.setTextureFilter(lake_texture, .point);
    const lake_sprites = shared.sheets.SpriteSet.LakeSheet(lake_texture);
    defer lake_sprites.Lake.deinit();

    const grass = Frames{
        .SpringTiles = .{
            .Grass = LandscapeTile.init(tileset_texture, 8.0, 0.0),
        },
    };

    // Initialize World
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var world = shared.World.loadFromFile(allocator, "assets/worldoutput.json") catch |err| blk: {
        std.debug.print("Could not load worldoutput.json: {}, falling back to worldedit.json\n", .{err});
        break :blk try shared.World.loadFromFile(allocator, "assets/worldedit.json");
    };
    defer world.deinit(allocator);

    // Calculate tile size from world dimensions
    const tile_width: u32 = @intCast(@divFloor(@as(i32, @intFromFloat(world.width)), world.tiles_x));
    const tile_height: u32 = @intCast(@divFloor(@as(i32, @intFromFloat(world.height)), world.tiles_y));

    // Initialize the new dynamic Map for editing
    var editor_map_instance = try Map.initWithTileSize(
        allocator,
        @intCast(world.tiles_x),
        @intCast(world.tiles_y),
        tile_width,
        tile_height,
    );
    defer editor_map_instance.deinit();

    // Set global reference for save callback
    g_editor_map = &editor_map_instance;
    g_allocator = allocator;

    // Camera - offset to start after sidebar so map doesn't go behind it
    var camera = rl.Camera2D{
        .target = .init(0, 0),
        .offset = .init(SIDEBAR_WIDTH, 0), // Map starts after sidebar
        .rotation = 0,
        .zoom = 1.0,
    };

    // Initialize the modular placement system with world's tile size
    var placement_system = PlacementSystem.init(.{ .grid_size = @intCast(tile_width) });
    placement_system.setBounds(world.tiles_x, world.tiles_y);

    var active_menu_idx: ?usize = null;

    var placed_items = try std.ArrayList(placement.PlacedItem).initCapacity(allocator, 8);
    defer placed_items.deinit(allocator);
    g_placed_items = &placed_items;

    var menu_items_list = try std.ArrayList(MenuItem).initCapacity(allocator, 12);
    defer menu_items_list.deinit(allocator);

    // Storage for heap-allocated PlaceableItem pointers (for cleanup)
    var placeable_ptrs = try std.ArrayList(*PlaceableItem).initCapacity(allocator, 12);
    defer {
        for (placeable_ptrs.items) |ptr| {
            allocator.destroy(ptr);
        }
        placeable_ptrs.deinit(allocator);
    }

    // Helper to add item
    const addMenuItem = struct {
        fn add(
            list: *std.ArrayList(MenuItem),
            ptrs: *std.ArrayList(*PlaceableItem),
            alloc: std.mem.Allocator,
            label: [:0]const u8,
            item_type: placement.ItemType,
            sprite: sheets.SpriteRect,
            tex: rl.Texture2D,
        ) !void {
            // Allocate PlaceableItem on the heap so pointer remains stable
            const data_ptr = try alloc.create(PlaceableItem);
            data_ptr.* = .{ .sprite = sprite, .texture = tex, .item_type = item_type };
            try ptrs.append(alloc, data_ptr);

            try list.append(alloc, .{
                .label = label,
                .action = saveWorld,
                .custom_draw = drawMenuItem,
                .data = data_ptr,
            });
        }
    }.add;

    //UI has spritesheet
    const menu_texture = try rl.loadTexture("assets/farmrpg/menu/mainmenu.png");
    defer rl.unloadTexture(menu_texture);
    var menu = Menu.init(menu_texture, .{});
    defer menu.deinit();

    const frames = [_]sheets.SpriteSet{ grass, .{
        .SpringTiles = .{
            .Water = LandscapeTile.init(tileset_texture, 8.0, 8.0),
        },
    }, .{
        .SpringTiles = .{
            .Road = LandscapeTile.init(tileset_texture, 8.0, 12.0),
        },
    }, .{
        .SpringTiles = .{
            .Rock = LandscapeTile.init(tileset_texture, 8.0, 4.0),
        },
    }, house_sprites, lake_sprites, menu.sprite_set };

    for (frames) |g| {
        switch (g) {
            .SpringTiles => |t| switch (t) {
                .Grass => |ts| {
                    for (ts.descriptors) |desc| {
                        try addMenuItem(&menu_items_list, &placeable_ptrs, allocator, "Grass", .Tile, desc, ts.texture2D);
                    }
                },
                .Road => |ts| {
                    for (ts.descriptors) |desc| {
                        try addMenuItem(&menu_items_list, &placeable_ptrs, allocator, "Road", .Tile, desc, ts.texture2D);
                    }
                },
                else => {},
            },
            .House => |t| {
                // House
                try addMenuItem(&menu_items_list, &placeable_ptrs, allocator, "House", .House, t.descriptor, t.texture2D);
            },
            .Lake => |t| {
                try addMenuItem(&menu_items_list, &placeable_ptrs, allocator, "Lake", .Lake, t.descriptor, t.texture2D);
            },
            else => {},
        }
    }

    // Add Eraser Tool
    const eraser_img = rl.genImageColor(16, 16, .gray);
    defer rl.unloadImage(eraser_img);
    const eraser_tex = try rl.loadTextureFromImage(eraser_img);
    defer rl.unloadTexture(eraser_tex);

    try addMenuItem(&menu_items_list, &placeable_ptrs, allocator, "Eraser", .Eraser, .{ .x = 0, .y = 0, .width = 16, .height = 16 }, eraser_tex);

    // Restore placed items from loaded world buildings
    const w_tile_w = world.width / @as(f32, @floatFromInt(world.tiles_x));
    const w_tile_h = world.height / @as(f32, @floatFromInt(world.tiles_y));

    for (world.buildings) |b| {
        const b_type_name = @tagName(b.building_type);
        // Find matching item in menu list to get correct sprite/data
        for (menu_items_list.items) |menu_item| {
            if (menu_item.data) |data_ptr| {
                const placeable = @as(*const PlaceableItem, @ptrCast(@alignCast(data_ptr)));
                if (std.mem.eql(u8, placeable.item_type.toString(), b_type_name)) {
                    // Found match, create placed item
                    const px = @as(f32, @floatFromInt(b.tile_x)) * w_tile_w;
                    const py = @as(f32, @floatFromInt(b.tile_y)) * w_tile_h;
                    const pw = @as(f32, @floatFromInt(b.width_tiles)) * w_tile_w;
                    const ph = @as(f32, @floatFromInt(b.height_tiles)) * w_tile_h;

                    try placed_items.append(allocator, .{ .data = placeable.*, .rect = rl.Rectangle{ .x = px, .y = py, .width = pw, .height = ph } });
                    break;
                }
            }
        }
    }

    var ghost_layer = GhostLayer{
        .allocator = allocator,
        .placed_items = &placed_items,
        .editor_map = &editor_map_instance,
    };

    while (!rl.windowShouldClose()) {
        // Camera Controls
        if (rl.isKeyDown(.right)) camera.target.x += 5;
        if (rl.isKeyDown(.left)) camera.target.x -= 5;
        if (rl.isKeyDown(.down)) camera.target.y += 5;
        if (rl.isKeyDown(.up)) camera.target.y -= 5;

        // Zoom (only when mouse is not over sidebar)
        const mouse_pos = rl.getMousePosition();
        if (mouse_pos.x > SIDEBAR_WIDTH) {
            const wheel = rl.getMouseWheelMove();
            if (wheel != 0) {
                //Todo: using zig math to clamp the zoom
                const zoom_speed: f32 = 0.1;
                const min_zoom: f32 = 0.5;
                const max_zoom: f32 = 4.0;

                camera.zoom += wheel * zoom_speed;
                if (camera.zoom < min_zoom) camera.zoom = min_zoom;
                if (camera.zoom > max_zoom) camera.zoom = max_zoom;
            }
        }

        // Placement Logic Inputs - ESC to deselect/cancel placement
        if (rl.isKeyPressed(.escape)) {
            placement_system.cancel();
            active_menu_idx = null;
        }

        // Save map with Ctrl+S
        if (rl.isKeyDown(.left_control) and rl.isKeyPressed(.s)) {
            saveWorld();
        }

        // Handle mouse release for continuous placement tracking
        placement_system.handleMouseRelease();

        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(rl.Color.ray_white);

        // Use a render camera snapped to pixel grid (camera itself stays smooth)
        var render_camera = camera;
        render_camera.target.x = @floor(camera.target.x * camera.zoom) / camera.zoom;
        render_camera.target.y = @floor(camera.target.y * camera.zoom) / camera.zoom;

        rl.beginMode2D(render_camera);
        // Draw the raw tileset first as a background reference (to the right)
        rl.drawTexture(tileset_texture, 100, 0, .white);

        // Draw grass background first

        // Draw grass background
        drawGrassBackground(grass, world);

        // Render placed items using the placement system
        PlacementSystem.renderPlacedItems(placed_items.items);

        // Ghost Rendering & Placement using the modular system
        const result = placement_system.updateAndRender(render_camera);
        if (result.placed) {
            if (placement_system.active_item) |item| {
                ghost_layer.applyPlacement(item, result);
            }
        }

        rl.endMode2D();

        rl.drawFPS(screen_width - 80, 10);

        if (placement_system.isActive()) {
            rl.drawText("PLACING MODE: Click to place, ESC to cancel", @intFromFloat(SIDEBAR_WIDTH + 10), screen_height - 50, 16, rl.Color.dark_purple);
        }

        // Draw Map Resize UI (positioned to the right of sidebar)
        try drawMapResizeControls(g_allocator.?, g_editor_map.?, &world, SIDEBAR_WIDTH + 10, 10);
        placement_system.setBounds(world.tiles_x, world.tiles_y);

        // Draw Menu in Sidebar (using Menu component)
        menu.drawAsSidebar(SIDEBAR_WIDTH, screen_height, menu_items_list.items, &active_menu_idx);

        // Check if menu selection changed to update placement state
        if (active_menu_idx) |idx| {
            // If we have an active item, enter placement mode for it
            if (idx < menu_items_list.items.len) {
                if (menu_items_list.items[idx].data) |data_ptr| {
                    const placeable_item = @as(*const PlaceableItem, @ptrCast(@alignCast(data_ptr)));
                    placement_system.startPlacing(placeable_item);
                }
            }
        } else {
            // If menu has no selection (e.g. user toggled off), clear placement state
            // Same behavior as pressing ESC
            placement_system.cancel();
        }
    }
}

fn saveWorld() void {
    const map = g_editor_map orelse {
        std.debug.print("No map to save\n", .{});
        return;
    };
    const items = g_placed_items orelse {
        std.debug.print("No placed items to save\n", .{});
        return;
    };

    // Create file
    const file = std.fs.cwd().createFile("assets/worldoutput.json", .{}) catch |err| {
        std.debug.print("Failed to create file: {}\n", .{err});
        return;
    };
    defer file.close();

    // Prepare buildings data for serialization
    // We need an intermediate struct that matches the JSON output format
    const JsonBuilding = struct {
        type: []const u8,
        tile_x: i32,
        tile_y: i32,
        width_tiles: i32,
        height_tiles: i32,
        sprite_x: i32,
        sprite_y: i32,
        sprite_width: i32,
        sprite_height: i32,
    };

    var json_buildings = std.ArrayList(JsonBuilding).initCapacity(g_allocator.?, items.items.len) catch |err| {
        std.debug.print("Failed to allocate buildings list: {}\n", .{err});
        return;
    };
    defer json_buildings.deinit(g_allocator.?);

    for (items.items) |item| {
        const tile_x = @divFloor(@as(i32, @intFromFloat(item.rect.x)), @as(i32, @intCast(map.tile_width)));
        const tile_y = @divFloor(@as(i32, @intFromFloat(item.rect.y)), @as(i32, @intCast(map.tile_height)));
        const width_tiles = @divFloor(@as(i32, @intFromFloat(item.rect.width)), @as(i32, @intCast(map.tile_width)));
        const height_tiles = @divFloor(@as(i32, @intFromFloat(item.rect.height)), @as(i32, @intCast(map.tile_height)));

        json_buildings.appendAssumeCapacity(.{
            .type = item.data.item_type.toString(),
            .tile_x = tile_x,
            .tile_y = tile_y,
            .width_tiles = width_tiles,
            .height_tiles = height_tiles,
            .sprite_x = @as(i32, @intFromFloat(item.data.sprite.x)),
            .sprite_y = @as(i32, @intFromFloat(item.data.sprite.y)),
            .sprite_width = @as(i32, @intFromFloat(item.data.sprite.width)),
            .sprite_height = @as(i32, @intFromFloat(item.data.sprite.height)),
        });
    }

    var buffer: [1024 * 1024]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);
    const writer = fbs.writer();

    // Use the shared export function
    map.exportAsGameMap(writer, json_buildings.items) catch |err| {
        std.debug.print("Failed to export map: {}\n", .{err});
        return;
    };

    // Write to file
    _ = file.writeAll(fbs.getWritten()) catch |err| {
        std.debug.print("Failed to write file: {}\n", .{err});
        return;
    };

    std.debug.print("World saved to assets/worldoutput.json ({} items)\n", .{items.items.len});
}

fn drawButton(rect: rl.Rectangle, text: [:0]const u8, mouse: rl.Vector2, clicked: bool) bool {
    const hovered = rl.checkCollisionPointRec(mouse, rect);
    const pressed = hovered and clicked;

    rl.drawRectangleRec(rect, if (pressed) rl.Color.gray else if (hovered) rl.Color.light_gray else rl.Color.white);
    rl.drawRectangleLinesEx(rect, 1, rl.Color.dark_gray);

    const text_w = rl.measureText(text, 10);
    const text_x = @as(i32, @intFromFloat(rect.x + (rect.width - @as(f32, @floatFromInt(text_w))) / 2.0));
    const text_y = @as(i32, @intFromFloat(rect.y + (rect.height - 10.0) / 2.0));
    rl.drawText(text, text_x, text_y, 10, rl.Color.black);

    return pressed;
}

fn drawMapResizeControls(allocator: std.mem.Allocator, map: *Map, world: *shared.World, x: f32, y: f32) !void {
    _ = allocator;
    const mouse = rl.getMousePosition();
    const clicked = rl.isMouseButtonPressed(rl.MouseButton.left);

    var buf: [64]u8 = undefined;

    // Background
    rl.drawRectangleRec(.{ .x = x, .y = y, .width = 210, .height = 70 }, rl.Color{ .r = 240, .g = 240, .b = 240, .a = 200 });
    rl.drawRectangleLinesEx(.{ .x = x, .y = y, .width = 210, .height = 70 }, 1, rl.Color.gray);

    const button_size = 20.0;
    const padding = 10.0;

    // Width
    {
        const row_y = y + padding;
        rl.drawText("Width:", @as(i32, @intFromFloat(x + padding)), @as(i32, @intFromFloat(row_y + 2)), 16, rl.Color.dark_gray);

        // [-]
        const minus_rect = rl.Rectangle{ .x = x + 80, .y = row_y, .width = button_size, .height = button_size };
        if (drawButton(minus_rect, "-", mouse, clicked)) {
            if (map.width > 1) {
                try map.resize(map.width - 1, map.height);
                world.tiles_x = @intCast(map.width);
                world.width = @as(f32, @floatFromInt(map.width * map.tile_width));
            }
        }

        // Value
        const val_str = try std.fmt.bufPrintZ(&buf, "{}", .{map.width});
        rl.drawText(val_str, @as(i32, @intFromFloat(x + 110)), @as(i32, @intFromFloat(row_y + 2)), 16, rl.Color.black);

        // [+]
        const plus_rect = rl.Rectangle{ .x = x + 150, .y = row_y, .width = button_size, .height = button_size };
        if (drawButton(plus_rect, "+", mouse, clicked)) {
            try map.resize(map.width + 1, map.height);
            world.tiles_x = @intCast(map.width);
            world.width = @as(f32, @floatFromInt(map.width * map.tile_width));
        }
    }

    // Height
    {
        const row_y = y + 35;
        rl.drawText("Height:", @as(i32, @intFromFloat(x + padding)), @as(i32, @intFromFloat(row_y + 2)), 16, rl.Color.dark_gray);

        // [-]
        const minus_rect = rl.Rectangle{ .x = x + 80, .y = row_y, .width = button_size, .height = button_size };
        if (drawButton(minus_rect, "-", mouse, clicked)) {
            if (map.height > 1) {
                try map.resize(map.width, map.height - 1);
                world.tiles_y = @intCast(map.height);
                world.height = @as(f32, @floatFromInt(map.height * map.tile_height));
            }
        }

        // Value
        const val_str = try std.fmt.bufPrintZ(&buf, "{}", .{map.height});
        rl.drawText(val_str, @as(i32, @intFromFloat(x + 110)), @as(i32, @intFromFloat(row_y + 2)), 16, rl.Color.black);

        // [+]
        const plus_rect = rl.Rectangle{ .x = x + 150, .y = row_y, .width = button_size, .height = button_size };
        if (drawButton(plus_rect, "+", mouse, clicked)) {
            try map.resize(map.width, map.height + 1);
            world.tiles_y = @intCast(map.height);
            world.height = @as(f32, @floatFromInt(map.height * map.tile_height));
        }
    }
}

fn drawMenuItem(item: *const MenuItem, rect: rl.Rectangle, active: bool, hovered: bool) void {
    if (active or hovered) {
        rl.drawRectangleRec(rect, rl.Color.sky_blue);
    }

    if (item.data) |data| {
        const placeable_item = @as(*const PlaceableItem, @ptrCast(@alignCast(data)));
        sheets.drawSpriteTo(placeable_item.texture, placeable_item.sprite, rect);
    } else {
        const text_x = @as(i32, @intFromFloat(rect.x + 10));
        const text_y = @as(i32, @intFromFloat(rect.y + (rect.height - 20) / 2));
        rl.drawText(item.label, text_x, text_y, 20, if (active) rl.Color.white else rl.Color.black);
    }
}
