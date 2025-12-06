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

const TileData = struct { sprite: sheets.SpriteRect, texture: rl.Texture2D };

const PlacedItem = struct {
    data: TileData,
    rect: rl.Rectangle,
};

pub fn main() !void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "Tiles Test App");
    defer rl.closeWindow();

    rl.setTargetFPS(60);

    // Load Assets
    var tileset_img = try rl.loadImage("assets/Farm RPG FREE 16x16 - Tiny Asset Pack/Tileset/Tileset Spring.png");
    // Apply color keying for transparency (Black -> Transparent)
    rl.imageColorReplace(&tileset_img, rl.Color.black, rl.Color.blank);
    defer rl.unloadImage(tileset_img);

    const tileset_texture = try rl.loadTextureFromImage(tileset_img);
    defer rl.unloadTexture(tileset_texture);
    const grass = Frames{
        .SpringTiles = .{
            .Grass = LandscapeTile.init(tileset_texture),
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

    //UI has spritesheet
    var menu = try Menu.load();
    defer menu.deinit();

    const PlacementState = struct {
        active_item: ?*const TileData = null,
        is_placing: bool = false,
    };
    var placement_state = PlacementState{};
    var active_menu_idx: ?usize = null;

    var placed_items = try std.ArrayList(PlacedItem).initCapacity(allocator, 8);
    defer placed_items.deinit(allocator);

    var menu_items_list = try std.ArrayList(MenuItem).initCapacity(allocator, 12);
    defer menu_items_list.deinit(allocator);

    // Helper to add item
    const addMenuItem = struct {
        fn add(list: *std.ArrayList(MenuItem), alloc: std.mem.Allocator, label: [:0]const u8, sprite: sheets.SpriteRect, tex: rl.Texture2D) !void {
            const data_ptr = try alloc.create(TileData);
            data_ptr.* = .{ .sprite = sprite, .texture = tex };
            try list.append(alloc, .{
                .label = label,
                .action = saveWorld,
                .custom_draw = drawMenuItem,
                .data = data_ptr,
            });
        }
    }.add;

    // Grass variants
    const grass_frames = sheets.SpriteSet.SpringTileGrass(tileset_texture);
    inline for (std.meta.fields(LandscapeTile.Dir)) |field| {
        const dir = @field(LandscapeTile.Dir, field.name);
        // Shorten label for menu width? Or just use "Grass"
        // User said "grass with all diretion", maybe helpful to label them?
        // But drawMenuItem draws label on top if no sprite? No, it draws sprite if data exists.
        // Label is fallback. But let's set label to "Grass".
        try addMenuItem(&menu_items_list, allocator, "Grass", grass_frames.SpringTiles.Grass.get(dir), tileset_texture);
    }

    // Road (Center only for now)
    const road_frames = sheets.SpriteSet.SpringTileRoad(tileset_texture);
    try addMenuItem(&menu_items_list, allocator, "Road", road_frames.SpringTiles.Road.get(.Center), tileset_texture);

    // Clean up created data pointers at end of scope
    defer {
        for (menu_items_list.items) |item| {
            if (item.data) |ptr| {
                const tile_data = @as(*TileData, @ptrCast(@alignCast(@constCast(ptr))));
                allocator.destroy(tile_data);
            }
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

        // Placement Logic Inputs
        if (rl.isKeyPressed(.escape)) {
            placement_state.is_placing = false;
            placement_state.active_item = null;
            active_menu_idx = null;
        }

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

        // Render placed items
        for (placed_items.items) |item| {
            sheets.drawSpriteTo(item.data.texture, item.data.sprite, item.rect);
        }

        // Ghost Rendering & Placement
        if (placement_state.is_placing) {
            if (placement_state.active_item) |data| {
                const mouse = rl.getMousePosition();
                const world_mouse = rl.getScreenToWorld2D(mouse, camera);

                // Snap to grid (16x16)
                const col = @divFloor(@as(i32, @intFromFloat(world_mouse.x)), 16);
                const row = @divFloor(@as(i32, @intFromFloat(world_mouse.y)), 16);
                const snap_x = @as(f32, @floatFromInt(col)) * 16.0;
                const snap_y = @as(f32, @floatFromInt(row)) * 16.0;

                const rect = rl.Rectangle{ .x = snap_x, .y = snap_y, .width = 16, .height = 16 };

                // Validity check (bounds)
                const valid = (snap_x >= 0 and snap_y >= 0 and snap_x < world.width and snap_y < world.height);

                // Colored Shadow
                const shadow_color = if (valid) rl.Color{ .r = 0, .g = 255, .b = 0, .a = 100 } else rl.Color{ .r = 255, .g = 0, .b = 0, .a = 100 };
                rl.drawRectangleRec(rect, shadow_color);

                // Ghost Sprite (semi-transparent)
                // We need a drawSprite variant that takes Color, or modify drawSpriteTo to accept color
                // sheets.drawSpriteTo uses .white hardcoded.
                // Let's manually draw for ghost to apply alpha
                const src = rl.Rectangle{
                    .x = data.sprite.x,
                    .y = data.sprite.y,
                    .width = data.sprite.width,
                    .height = data.sprite.height,
                };
                rl.drawTexturePro(
                    data.texture,
                    src,
                    rect,
                    .{ .x = 0, .y = 0 },
                    0,
                    rl.Color{ .r = 255, .g = 255, .b = 255, .a = 150 }, // Ghost alpha
                );

                // Handle Click to Place
                if (rl.isMouseButtonPressed(.left) and valid) {
                    // Check if spot is free? For now just place on top
                    placed_items.append(allocator, .{ .data = data.*, .rect = rect }) catch {};
                }
            }
        }

        rl.endMode2D();

        rl.drawFPS(screen_width - 80, 10);

        // Show current mode and controls
        const mode_text = if (use_autotile) "Mode: AUTO-TILE (TAB to switch)" else "Mode: EXPLICIT (TAB to switch)";
        rl.drawText(mode_text, 10, 10, 20, rl.Color.dark_blue);
        rl.drawText("Use Arrow Keys to Move Camera, Mouse Wheel to Zoom", 10, screen_height - 30, 20, rl.Color.dark_gray);
        if (placement_state.is_placing) {
            rl.drawText("PLACING MODE: Click to place, ESC to cancel", 10, screen_height - 50, 20, rl.Color.dark_purple);
        }

        // Draw Menu
        menu.draw(world.width, menu_items_list.items, &active_menu_idx);

        // Check if menu selection changed to update placement state
        if (active_menu_idx) |idx| {
            // If we have an active item, enter placement mode for it
            // We assume idx corresponds to inspector_menu_items order
            if (idx < menu_items_list.items.len) {
                if (menu_items_list.items[idx].data) |data_ptr| {
                    const tile_data = @as(*const TileData, @ptrCast(@alignCast(data_ptr)));
                    placement_state.active_item = tile_data;
                    placement_state.is_placing = true;
                    // Optional: Reset active_menu_idx if we want to deselect in UI,
                    // or keep it to show what's selected.
                    // If we keep it, we need to make sure we don't re-trigger logic inadvertently,
                    // but setting active_item repeatedly to same is fine.
                }
            }
        } else {
            // If menu has no selection (e.g. user toggled off?), maybe exit placement?
            // Logic depends on `active_item` behavior in menu.zig.
            // Currently it toggles. If it becomes null, we stop placing.
            if (!placement_state.is_placing) {
                // consistent state
            }
            // If I press ESC, I set is_placing false, should I clear active_menu_idx code-side? done above.
        }
    }
}

fn saveWorld() void {}

fn drawMenuItem(item: *const MenuItem, rect: rl.Rectangle, active: bool, hovered: bool) void {
    if (active or hovered) {
        rl.drawRectangleRec(rect, rl.Color.sky_blue);
    }

    if (item.data) |data| {
        const tile_data = @as(*const TileData, @ptrCast(@alignCast(data)));
        sheets.drawSpriteTo(tile_data.texture, tile_data.sprite, rect);
    } else {
        const text_x = @as(i32, @intFromFloat(rect.x + 10));
        const text_y = @as(i32, @intFromFloat(rect.y + (rect.height - 20) / 2));
        rl.drawText(item.label, text_x, text_y, 20, if (active) rl.Color.white else rl.Color.black);
    }
}
