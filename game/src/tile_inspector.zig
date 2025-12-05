const std = @import("std");
const rl = @import("raylib");
const shared = @import("shared");

// Import the new auto-tile system
const tiles = shared.tiles;
const TileLayer = tiles.TileLayer;
const AutoTileConfig = tiles.AutoTileConfig;
const AutoTileRenderer = tiles.AutoTileRenderer;
const Terrain = tiles.Terrain;
const MultiLayerTileMap = tiles.MultiLayerTileMap;

// Shared landscape/frames types
const landscape = shared.landscape;
const TileDescriptor = landscape.TileDescriptor;
const SpriteSheets = landscape.SpriteSheets;
const LandscapeTile = landscape.LandscapeTile;
const Frames = landscape.Frames;
const drawLandscapeTile = landscape.drawLandscapeTile;

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
    const dirt = Frames{
        .SpringTiles = .{
            .Road = LandscapeTile.init(tileset_texture),
        },
    };
    _ = grass;
    _ = dirt;

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

        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(rl.Color.ray_white);

        rl.beginMode2D(camera);
        // Draw the raw tileset first as a background reference (to the right)
        rl.drawTexture(tileset_texture, @as(i32, @intFromFloat(world.width)), 0, .white);

        // Draw the world tiles
        if (use_autotile) {
            // NEW: Auto-tile system - automatically selects correct sprite based on neighbors
            const tile_w: f32 = world.width / @as(f32, @floatFromInt(world.tiles_x));
            const tile_h: f32 = world.height / @as(f32, @floatFromInt(world.tiles_y));
            auto_tile_map.draw(tile_w, tile_h);
        } else {
            // OLD: Explicit TileKind system (manual sprite selection)
            drawWorldTiles(tileset_texture, world);
        }
        rl.endMode2D();

        // Inspector Overlay Logic (Grid & Hover) - Now in World Space (mostly)
        // Actually, since we are using a Camera, we should convert mouse to world space.

        const mouse_screen = rl.getMousePosition();
        const mouse_world = rl.getScreenToWorld2D(mouse_screen, camera);

        // Draw Grid Lines (in World Space via Camera? No, easier to draw in screen space if fixed,
        // but since we have a camera now, let's draw grid in World Space inside Mode2D)

        rl.beginMode2D(camera);
        const cols = world.tiles_x;
        const rows = world.tiles_y;

        var r: i32 = 0;
        while (r <= rows) : (r += 1) {
            const y = @as(f32, @floatFromInt(r * 16));
            rl.drawLineEx(rl.Vector2{ .x = 0, .y = y }, rl.Vector2{ .x = world.width, .y = y }, 1.0 / camera.zoom, // Keep line thin
                rl.Color.red);
        }
        var c: i32 = 0;
        while (c <= cols) : (c += 1) {
            const x = @as(f32, @floatFromInt(c * 16));
            rl.drawLineEx(rl.Vector2{ .x = x, .y = 0 }, rl.Vector2{ .x = x, .y = world.height }, 1.0 / camera.zoom, rl.Color.red);
        }

        // Hover Highlight
        if (mouse_world.x >= 0 and mouse_world.x < world.width and
            mouse_world.y >= 0 and mouse_world.y < world.height)
        {
            const col = @divTrunc(@as(i32, @intFromFloat(mouse_world.x)), 16);
            const row = @divTrunc(@as(i32, @intFromFloat(mouse_world.y)), 16);

            rl.drawRectangleLinesEx(rl.Rectangle{ .x = @as(f32, @floatFromInt(col * 16)), .y = @as(f32, @floatFromInt(row * 16)), .width = 16, .height = 16 }, 2.0 / camera.zoom, rl.Color.yellow);
        }
        rl.endMode2D();

        // Tooltip (Screen Space)
        if (mouse_world.x >= 0 and mouse_world.x < world.width and
            mouse_world.y >= 0 and mouse_world.y < world.height)
        {
            const col = @divTrunc(@as(i32, @intFromFloat(mouse_world.x)), 16);
            const row = @divTrunc(@as(i32, @intFromFloat(mouse_world.y)), 16);
            const text = rl.textFormat("Grid: %d, %d", .{ col, row });
            rl.drawText(text, @as(i32, @intFromFloat(mouse_screen.x)) + 10, @as(i32, @intFromFloat(mouse_screen.y)) - 20, 20, rl.Color.black);
        }

        rl.drawFPS(screen_width - 80, 10);

        // Show current mode and controls
        const mode_text = if (use_autotile) "Mode: AUTO-TILE (TAB to switch)" else "Mode: EXPLICIT (TAB to switch)";
        rl.drawText(mode_text, 10, 10, 20, rl.Color.dark_blue);
        rl.drawText("Use Arrow Keys to Move Camera, Mouse Wheel to Zoom", 10, screen_height - 30, 20, rl.Color.dark_gray);
    }
}
