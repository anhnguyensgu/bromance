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
pub const drawLandscapeTile = shared.drawLandscapeTile;

// Import the placement system
const placement = @import("ui/placement.zig");
const PlacementSystem = placement.PlacementSystem;
const PlaceableItem = placement.PlaceableItem;

// Import the new dynamic Map system
const editor_map = shared.editor_map;
const Map = editor_map.Map;
const TileId = editor_map.TileId;

// Global editor map reference for save callback
var g_editor_map: ?*Map = null;
var g_allocator: ?std.mem.Allocator = null;
var g_placed_items: ?*std.ArrayList(placement.PlacedItem) = null;

fn tileRect(gridX: i32, gridY: i32, tileSize: i32) rl.Rectangle {
    return rl.Rectangle{
        .x = @as(f32, @floatFromInt(gridX * tileSize)),
        .y = @as(f32, @floatFromInt(gridY * tileSize)),
        .width = @as(f32, @floatFromInt(tileSize)),
        .height = @as(f32, @floatFromInt(tileSize)),
    };
}
// --- Explicit Tile Kinds (no bitmask) ---

// Explicit sprite variants for this tiles inspector.
// These are per-cell visual types, not derived from neighbors.
const TileKind = enum(u8) {
    Empty, // nothing drawn
    GrassCenter, // full grass tile

    RoadSingle,
    RoadEndUp,
    RoadEndRight,
    RoadEndDown,
    RoadEndLeft,
    RoadStraightV,
    RoadStraighRightEdge,
    RoadStraightH,
    RoadStraightHBottom,
    RoadCornerUR,
    RoadCornerDR,
    RoadCornerDL,
    RoadCornerUL,
    RoadTJunctionUp,
    RoadTJunctionRight,
    RoadTJunctionDown,
    RoadTJunctionLeft,
    RoadCross,
};

fn tileKindToCoords(kind: TileKind) [2]i32 {
    // NOTE: These coordinates assume the road block starts at (8,0) in Tileset Spring.png.
    // (col, row) are in 16x16 tile units.
    return switch (kind) {
        .Empty => .{ 0, 0 },

        // Grass
        .GrassCenter => .{ 9, 2 }, // you identified (9,2) as full grass

        // Road variants: 3x3 block starting at (8,0)
        //
        // Top row (row = 0): corners and end-up
        // [8,0] [9,0] [10,0]
        .RoadCornerUL => .{ 8, 0 },
        .RoadEndUp => .{ 9, 0 },
        .RoadCornerUR => .{ 11, 0 },

        // Middle row (row = 1): left/right ends and straight vertical
        // [8,1] [9,1] [10,1]
        .RoadEndLeft => .{ 8, 1 },
        .RoadStraightV => .{ 8, 1 },
        .RoadStraighRightEdge => .{ 11, 2 },
        .RoadEndRight => .{ 10, 1 },

        // Bottom row (row = 2): corners and end-down
        // [8,2] [9,2] [10,2]
        .RoadCornerDL => .{ 8, 3 },
        .RoadEndDown => .{ 9, 2 },
        .RoadCornerDR => .{ 11, 3 },

        // For now, reuse tiles from the same 3x3 block for other variants.
        .RoadStraightH => .{ 10, 0 }, // horizontal uses center for now
        .RoadStraightHBottom => .{ 9, 3 }, // horizontal uses center for now
        .RoadTJunctionUp => .{ 9, 0 }, // reuse end-up art
        .RoadTJunctionRight => .{ 10, 0 }, // reuse end-right art
        .RoadTJunctionDown => .{ 9, 2 }, // reuse end-down art
        .RoadTJunctionLeft => .{ 8, 1 }, // reuse end-left art
        .RoadCross => .{ 9, 1 }, // reuse straight-V as placeholder

        // Fallback if used
        .RoadSingle => .{ 9, 1 },
    };
}

// Hard-coded logical grid taken from assets/world_edit.json,
// but now storing explicit TileKind instead of just TerrainType.
fn getTileKindAtGrid(world: shared.World, tx: i32, ty: i32) TileKind {
    // NOTE:
    // This helper assumes that:
    //  - world.width  and world.height match the tileset texture size
    //  - tiles are 16x16
    //  - assets/world_edit.json provides a 12x20 tiles grid (tiles_x/tiles_y from JSON)
    //
    // `tiles_test.zig` then stretches that logical 12x20 grid over the entire texture
    // by recomputing world.tiles_x and world.tiles_y from the texture size.
    //
    // To keep the autotiling behavior consistent with the JSON `tiles` grid,
    // we remap (tx, ty) from the current world.tiles_x/world.tiles_y space
    // back into the original JSON grid / logical grid size.
    //
    // This is a TEMPORARY shim so we can experiment with autotiling
    // in this inspector app without having to fully refactor shared.World
    // to own a concrete tiles array.

    // Hard-coded logical grid taken from assets/world_edit.json
    const logical_tiles_x: i32 = 12;
    const logical_tiles_y: i32 = 20;

    if (tx < 0 or ty < 0 or tx >= world.tiles_x or ty >= world.tiles_y) {
        return .Empty;
    }

    // Map current grid coords (0..world.tiles_x) into logical (0..logical_tiles_x)
    const fx = @as(f32, @floatFromInt(tx)) / @as(f32, @floatFromInt(world.tiles_x));
    const fy = @as(f32, @floatFromInt(ty)) / @as(f32, @floatFromInt(world.tiles_y));

    const logical_tx: i32 = @intFromFloat(fx * @as(f32, @floatFromInt(logical_tiles_x)));
    const logical_ty: i32 = @intFromFloat(fy * @as(f32, @floatFromInt(logical_tiles_y)));

    if (logical_tx < 0 or logical_ty < 0 or logical_tx >= logical_tiles_x or logical_ty >= logical_tiles_y) {
        return .Empty;
    }

    // This is the small hand-authored area we encoded for this inspector.
    // Encoding is now TileKind, not just terrain:
    //   G = GrassCenter
    //   H = RoadStraightH
    //   V = RoadStraightV
    //   C = RoadCross
    //   U/R/D/L = RoadEndUp/Right/Down/Left
    //
    // For simplicity, most of the interior is GrassCenter, and we lay
    // a ring of road around the border plus a small cross near the top.
    const kinds = [_][logical_tiles_x]TileKind{
        .{ .RoadCornerUL, .RoadStraightH, .RoadStraightH, .RoadStraightH, .RoadStraightH, .RoadStraightH, .RoadStraightH, .RoadStraightH, .RoadStraightH, .RoadStraightH, .RoadStraightH, .RoadCornerUR },
        .{ .RoadStraightV, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .RoadStraighRightEdge },
        .{ .RoadStraightV, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .RoadStraighRightEdge },
        .{ .RoadStraightV, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .RoadStraighRightEdge },
        .{ .RoadStraightV, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .RoadStraighRightEdge },
        .{ .RoadStraightV, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .RoadStraighRightEdge },
        .{ .RoadStraightV, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .RoadStraighRightEdge },
        .{ .RoadStraightV, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .RoadStraighRightEdge },
        .{ .RoadStraightV, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .RoadStraighRightEdge },
        .{ .RoadStraightV, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .RoadStraighRightEdge },
        .{ .RoadStraightV, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .RoadStraighRightEdge },
        .{ .RoadStraightV, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .RoadStraighRightEdge },
        .{ .RoadStraightV, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .RoadStraighRightEdge },
        .{ .RoadStraightV, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .RoadStraighRightEdge },
        .{ .RoadStraightV, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .RoadStraighRightEdge },
        .{ .RoadStraightV, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .RoadStraighRightEdge },
        .{ .RoadStraightV, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .RoadStraighRightEdge },
        .{ .RoadStraightV, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .RoadStraighRightEdge },
        .{ .RoadStraightV, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .GrassCenter, .RoadStraighRightEdge },
        .{ .RoadCornerDL, .RoadStraightHBottom, .RoadStraightHBottom, .RoadStraightHBottom, .RoadStraightHBottom, .RoadStraightHBottom, .RoadStraightHBottom, .RoadStraightHBottom, .RoadStraightHBottom, .RoadStraightHBottom, .RoadStraightHBottom, .RoadCornerDR },
    };

    return kinds[@intCast(logical_ty)][@intCast(logical_tx)];
}

// No bitmasking in this inspector anymore – everything is explicit.

fn drawGrassBackground(grass: Frames, world: shared.World) void {
    const tile_w: f32 = 16.0;
    const tile_h: f32 = 16.0;

    var ty: i32 = 0;
    while (ty < world.tiles_y) : (ty += 1) {
        var tx: i32 = 0;
        while (tx < world.tiles_x) : (tx += 1) {
            const x = @as(f32, @floatFromInt(tx)) * tile_w;
            const y = @as(f32, @floatFromInt(ty)) * tile_h;

            // Determine the correct tile direction based on position
            const dir: LandscapeTile.Dir = blk: {
                const is_left = tx == 0;
                const is_right = tx == world.tiles_x - 1;
                const is_top = ty == 0;
                const is_bottom = ty == world.tiles_y - 1;

                if (is_left and is_top) {
                    break :blk .TopLeftCorner;
                } else if (is_right and is_top) {
                    break :blk .TopRightCorner;
                } else if (is_left and is_bottom) {
                    break :blk .BottomLeftCorner;
                } else if (is_right and is_bottom) {
                    break :blk .BottomRightCorner;
                } else if (is_left) {
                    break :blk .Left;
                } else if (is_right) {
                    break :blk .Right;
                } else if (is_top) {
                    break :blk .Top;
                } else if (is_bottom) {
                    break :blk .Bottom;
                } else {
                    break :blk .Center;
                }
            };

            drawLandscapeTile(grass, dir, x, y);
        }
    }
}

fn drawWorldTiles(tileset: rl.Texture2D, world: shared.World) void {
    const tile_w: f32 = world.width / @as(f32, @floatFromInt(world.tiles_x));
    const tile_h: f32 = world.height / @as(f32, @floatFromInt(world.tiles_y));

    var ty: i32 = 0;
    while (ty < world.tiles_y) : (ty += 1) {
        var tx: i32 = 0;
        while (tx < world.tiles_x) : (tx += 1) {
            const dest = rl.Rectangle{
                .x = @as(f32, @floatFromInt(tx)) * tile_w,
                .y = @as(f32, @floatFromInt(ty)) * tile_h,
                .width = tile_w,
                .height = tile_h,
            };

            // 1. Look up explicit TileKind for this logical cell
            const kind = getTileKindAtGrid(world, tx, ty);

            if (kind != .Empty) {
                const coords = tileKindToCoords(kind);
                const src = tileRect(coords[0], coords[1], 16);
                rl.drawTexturePro(tileset, src, dest, rl.Vector2{ .x = 0, .y = 0 }, 0, .white);
            }
        }
    }
}

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
    var tileset_img = try rl.loadImage("assets/Farm RPG FREE 16x16 - Tiny Asset Pack/Tileset/Tileset Spring.png");
    // Apply color keying for transparency (Black -> Transparent)
    rl.imageColorReplace(&tileset_img, rl.Color.black, rl.Color.blank);
    defer rl.unloadImage(tileset_img);

    const tileset_texture = try rl.loadTextureFromImage(tileset_img);
    defer rl.unloadTexture(tileset_texture);

    const house_img = try rl.loadImage("assets/Farm RPG FREE 16x16 - Tiny Asset Pack/Objects/House.png");
    defer rl.unloadImage(house_img);
    const house_texture = try rl.loadTextureFromImage(house_img);
    defer rl.unloadTexture(house_texture);

    const house_sprites = shared.sheets.SpriteSet.HouseSheet(house_texture);
    defer house_sprites.House.deinit();

    const lake_img = try rl.loadImage("assets/lake_small.png");
    defer rl.unloadImage(lake_img);
    const lake_texture = try rl.loadTextureFromImage(lake_img);
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

    var world = try shared.World.loadFromFile(allocator, "assets/world_edit.json");
    defer world.deinit(allocator);
    world.height = @as(f32, @floatFromInt(tileset_texture.height));
    world.width = @as(f32, @floatFromInt(tileset_texture.width));
    world.tiles_x = @divTrunc(@as(i32, @intFromFloat(world.width)), 16);
    world.tiles_y = @divTrunc(@as(i32, @intFromFloat(world.height)), 16);

    // Initialize the new dynamic Map for editing
    var editor_map_instance = try Map.initWithTileSize(
        allocator,
        @intCast(world.tiles_x),
        @intCast(world.tiles_y),
        16,
        16,
    );
    defer editor_map_instance.deinit();

    // Set global reference for save callback
    g_editor_map = &editor_map_instance;
    g_allocator = allocator;

    // Initialize auto-tile map from loaded world (uses world's tiles grid if present)
    var auto_tile_map = try MultiLayerTileMap.initFromWorld(allocator, tileset_texture, world);
    defer auto_tile_map.deinit();

    // Optionally draw additional paths/terrain using auto_tile_map.* APIs if desired

    var use_autotile = true; // Toggle between old explicit system and new auto-tile

    // Camera - Match Inspector Transform (Pos: 10,10, Scale: 2.0)
    var camera = rl.Camera2D{
        .target = .init(0, 0),
        .offset = .init(10, 10),
        .rotation = 0,
        .zoom = 1.0,
    };

    // Initialize the modular placement system
    var placement_system = PlacementSystem.init(.{});
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
            item_type: []const u8,
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
    const menu_texture = try rl.loadTexture("assets/Farm RPG FREE 16x16 - Tiny Asset Pack/Menu/Main_menu.png");
    defer rl.unloadTexture(menu_texture);
    var menu = Menu.init(menu_texture, .{});
    defer menu.deinit();

    const frames = [_]sheets.SpriteSet{ grass, .{
        .SpringTiles = .{
            .Water = LandscapeTile.init(tileset_texture, 8.0, 8.0),
        },
    }, .{
        .SpringTiles = .{
            .Road = LandscapeTile.init(tileset_texture, 8.0, 4.0),
        },
    }, house_sprites, lake_sprites, menu.sprite_set };

    for (frames) |g| {
        switch (g) {
            .SpringTiles => |t| switch (t) {
                .Grass => |ts| {
                    for (ts.descriptors) |desc| {
                        try addMenuItem(&menu_items_list, &placeable_ptrs, allocator, "Grass", "Tile", desc, ts.texture2D);
                    }
                },
                .Road => |ts| {
                    for (ts.descriptors) |desc| {
                        try addMenuItem(&menu_items_list, &placeable_ptrs, allocator, "Road", "Road", desc, ts.texture2D);
                    }
                },
                else => {},
            },
            .House => |t| {
                // House
                try addMenuItem(&menu_items_list, &placeable_ptrs, allocator, "House", "House", t.descriptor, t.texture2D);
            },
            .Lake => |t| {
                try addMenuItem(&menu_items_list, &placeable_ptrs, allocator, "Lake", "Lake", t.descriptor, t.texture2D);
            },
            else => {},
        }
    }

    while (!rl.windowShouldClose()) {
        // Camera Controls
        if (rl.isKeyDown(.right)) camera.target.x += 5;
        if (rl.isKeyDown(.left)) camera.target.x -= 5;
        if (rl.isKeyDown(.down)) camera.target.y += 5;
        if (rl.isKeyDown(.up)) camera.target.y -= 5;

        // Zoom
        const wheel = rl.getMouseWheelMove();
        if (wheel != 0) {
            camera.zoom += wheel * 0.1;
            if (camera.zoom < 0.1) camera.zoom = 0.1;
        }

        // Toggle auto-tile mode with TAB
        if (rl.isKeyPressed(.tab)) {
            use_autotile = !use_autotile;
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

        rl.beginMode2D(camera);
        // Draw the raw tileset first as a background reference (to the right)
        rl.drawTexture(tileset_texture, 100, 0, .white);

        // Draw grass background first

        // Draw the world tiles on top
        if (use_autotile) {
            // NEW: Auto-tile system - automatically selects correct sprite based on neighbors
            drawGrassBackground(grass, world);
        } else {
            // OLD: Explicit TileKind system (manual sprite selection)
            drawWorldTiles(tileset_texture, world);
        }

        // Render placed items using the placement system
        PlacementSystem.renderPlacedItems(placed_items.items);

        // Ghost Rendering & Placement using the modular system
        const result = placement_system.updateAndRender(camera);
        if (result.placed) {
            if (placement_system.active_item) |item| {
                // Check if an item already exists at this position to prevent duplicates
                var already_exists = false;
                for (placed_items.items) |existing| {
                    if (existing.rect.x == result.rect.x and existing.rect.y == result.rect.y) {
                        already_exists = true;
                        break;
                    }
                }

                if (!already_exists) {
                    placed_items.append(allocator, .{ .data = item.*, .rect = result.rect }) catch {};

                    // Also update the editor map with the placed tile
                    if (result.col >= 0 and result.row >= 0) {
                        const tile_id: TileId = 1; // Default tile ID for placed items
                        editor_map_instance.setTile(@intCast(result.col), @intCast(result.row), tile_id);
                    }
                }
            }
        }

        rl.endMode2D();

        rl.drawFPS(screen_width - 80, 10);

        // Show current mode and controls
        const mode_text = if (use_autotile) "Mode: AUTO-TILE (TAB to switch)" else "Mode: EXPLICIT (TAB to switch)";
        rl.drawText(mode_text, 10, 10, 20, rl.Color.dark_blue);
        rl.drawText("Arrow Keys: Move | Scroll: Zoom | Ctrl+S: Save", 10, screen_height - 30, 20, rl.Color.dark_gray);
        if (placement_system.isActive()) {
            rl.drawText("PLACING MODE: Click to place, ESC to cancel", 10, screen_height - 50, 20, rl.Color.dark_purple);
        }

        // Show map dimensions
        var dim_buf: [64:0]u8 = undefined;
        _ = std.fmt.bufPrint(&dim_buf, "Map: {}x{} tiles", .{ editor_map_instance.width, editor_map_instance.height }) catch {};
        rl.drawText(&dim_buf, screen_width - 150, 10, 16, rl.Color.dark_gray);

        // Draw Menu
        menu.draw(world.width, menu_items_list.items, &active_menu_idx);

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
    const file = std.fs.cwd().createFile("assets/world_output.json", .{}) catch |err| {
        std.debug.print("Failed to create file: {}\n", .{err});
        return;
    };
    defer file.close();

    // Build JSON manually
    var buffer: [1024 * 1024]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);
    const writer = fbs.writer();

    writer.writeAll("{\n") catch return;
    writer.print("  \"world\": {{\n", .{}) catch return;
    writer.print("    \"width\": {},\n", .{map.width * map.tile_width}) catch return;
    writer.print("    \"height\": {},\n", .{map.height * map.tile_height}) catch return;
    writer.print("    \"tiles_x\": {},\n", .{map.width}) catch return;
    writer.print("    \"tiles_y\": {}\n", .{map.height}) catch return;
    writer.writeAll("  },\n") catch return;

    // Write placed items as buildings
    writer.writeAll("  \"buildings\": [\n") catch return;
    for (items.items, 0..) |item, i| {
        const tile_x = @divFloor(@as(i32, @intFromFloat(item.rect.x)), @as(i32, @intCast(map.tile_width)));
        const tile_y = @divFloor(@as(i32, @intFromFloat(item.rect.y)), @as(i32, @intCast(map.tile_height)));
        const width_tiles = @divFloor(@as(i32, @intFromFloat(item.rect.width)), @as(i32, @intCast(map.tile_width)));
        const height_tiles = @divFloor(@as(i32, @intFromFloat(item.rect.height)), @as(i32, @intCast(map.tile_height)));

        writer.writeAll("    {\n") catch return;
        writer.print("      \"type\": \"{s}\",\n", .{item.data.item_type}) catch return;
        writer.print("      \"tile_x\": {},\n", .{tile_x}) catch return;
        writer.print("      \"tile_y\": {},\n", .{tile_y}) catch return;
        writer.print("      \"width_tiles\": {},\n", .{width_tiles}) catch return;
        writer.print("      \"height_tiles\": {},\n", .{height_tiles}) catch return;
        writer.print("      \"sprite_width\": {},\n", .{@as(i32, @intFromFloat(item.data.sprite.width))}) catch return;
        writer.print("      \"sprite_height\": {}\n", .{@as(i32, @intFromFloat(item.data.sprite.height))}) catch return;
        writer.writeAll("    }") catch return;
        if (i < items.items.len - 1) {
            writer.writeAll(",") catch return;
        }
        writer.writeAll("\n") catch return;
    }
    writer.writeAll("  ]\n") catch return;
    writer.writeAll("}\n") catch return;

    // Write to file
    _ = file.writeAll(fbs.getWritten()) catch |err| {
        std.debug.print("Failed to write file: {}\n", .{err});
        return;
    };

    std.debug.print("World saved to assets/world_output.json ({} items)\n", .{items.items.len});
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
