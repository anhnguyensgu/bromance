const std = @import("std");

const rl = @import("raylib");

const player_mod = @import("character/player.zig");
const Character = player_mod.Character;
const CharacterAssets = player_mod.CharacterAssets;
const ClientGameState = @import("client/game_state.zig").ClientGameState;
const client = @import("client/udp_client.zig");
const UdpClient = @import("client/udp_client.zig").UdpClient;
const applyMoveToVector = client.applyMoveToVector;
const command = @import("movement/command.zig");
const MovementCommand = @import("movement/command.zig").MovementCommand;
const MoveDirection = command.MoveDirection;
const shared = @import("shared.zig");
const tiles = @import("tiles/layer.zig");
const MultiLayerTileMap = tiles.MultiLayerTileMap;
const ui_menu = @import("ui/menu.zig");
const MenuItem = ui_menu.MenuItem;
const Menu = ui_menu.Menu;

fn updateCameraFocus(camera: *rl.Camera2D, player: Character, screen_width: i32, screen_height: i32, world: shared.World) void {
    const view_half_w: f32 = (@as(f32, @floatFromInt(screen_width)) * 0.5) / camera.zoom;
    const view_half_h: f32 = (@as(f32, @floatFromInt(screen_height)) * 0.5) / camera.zoom;

    var cam_target_x: f32 = player.pos.x + player.size.x * 0.5;
    var cam_target_y: f32 = player.pos.y + player.size.y * 0.5;

    // Basic clamping to world bounds
    if (world.width > view_half_w * 2) {
        cam_target_x = std.math.clamp(cam_target_x, view_half_w, world.width - view_half_w);
    } else {
        cam_target_x = world.width * 0.5;
    }
    if (world.height > view_half_h * 2) {
        cam_target_y = std.math.clamp(cam_target_y, view_half_h, world.height - view_half_h);
    } else {
        cam_target_y = world.height * 0.5;
    }

    // Keep the camera centered on the player; avoid pushing the target upward, which left a blank strip at the top.
    camera.target = .init(cam_target_x, cam_target_y);
}

fn drawConstruction(townhall_texture: rl.Texture2D, lake_texture: rl.Texture2D, terrain_texture: rl.Texture2D, ruins_texture: rl.Texture2D, world: shared.World) void {
    // Draw all buildings from map configuration
    for (world.buildings) |building| {
        // Convert tile coordinates to world pixels
        const building_x = world.tileToWorldX(building.tile_x);
        const building_y = world.tileToWorldY(building.tile_y);

        switch (building.building_type) {
            .Townhall => {
                const building_pos = rl.Vector2{ .x = building_x, .y = building_y };
                const building_source = rl.Rectangle{ .x = 150, .y = 0, .width = @floatFromInt(@divTrunc(townhall_texture.width, 3)), .height = @floatFromInt(townhall_texture.height) };
                const building_dest = rl.Rectangle{ .x = building_pos.x, .y = building_pos.y, .width = building.sprite_width, .height = building.sprite_height };
                rl.drawTexturePro(townhall_texture, building_source, building_dest, rl.Vector2{ .x = 0, .y = 0 }, 0, .white);
            },
            .Lake => {
                const building_pos = rl.Vector2{ .x = building_x, .y = building_y };
                const building_source = rl.Rectangle{ .x = 0, .y = 0, .width = @floatFromInt(lake_texture.width), .height = @floatFromInt(lake_texture.height) };
                const building_dest = rl.Rectangle{ .x = building_pos.x, .y = building_pos.y, .width = building.sprite_width, .height = building.sprite_height };
                rl.drawTexturePro(lake_texture, building_source, building_dest, rl.Vector2{ .x = 0, .y = 0 }, 0, .white);
            },
            .Road => {
                const building_pos = rl.Vector2{ .x = building_x, .y = building_y };
                const TILE_SRC_SIZE: f32 = 50;
                const road_idx: f32 = 3; // Index 3 is Road

                const building_source = rl.Rectangle{ .x = road_idx * TILE_SRC_SIZE, .y = 0, .width = TILE_SRC_SIZE, .height = TILE_SRC_SIZE };
                const building_dest = rl.Rectangle{ .x = building_pos.x, .y = building_pos.y, .width = building.sprite_width, .height = building.sprite_height };
                rl.drawTexturePro(terrain_texture, building_source, building_dest, rl.Vector2{ .x = 0, .y = 0 }, 0, .white);
            },
            .House => {
                // Draw 3x3 block from Ruins texture
                // Source tiles start at col 0, row 2 (based on analysis)
                const TILE_SIZE: f32 = 4;
                const START_COL: f32 = 0;
                const START_ROW: f32 = 0;

                // We need to draw 9 tiles (3x3 grid)
                // But the building object defines the total size.
                // Let's assume the building dimensions (width_tiles, height_tiles) match the 3x3 grid.
                // We can draw the whole 3x3 block as one large rectangle if they are contiguous in the sprite sheet.
                // Analysis showed cols 0,1,2 and rows 2,3,4 have content.
                // So we can draw a 96x96 block from (0, 64).

                const src_x = START_COL * TILE_SIZE;
                const src_y = START_ROW * TILE_SIZE;
                const src_w = TILE_SIZE;
                const src_h = TILE_SIZE;

                const building_pos = rl.Vector2{ .x = building_x, .y = building_y };
                const building_source = rl.Rectangle{ .x = src_x, .y = src_y, .width = src_w, .height = src_h };
                const building_dest = rl.Rectangle{ .x = building_pos.x, .y = building_pos.y, .width = building.sprite_width, .height = building.sprite_height };

                rl.drawTexturePro(ruins_texture, building_source, building_dest, rl.Vector2{ .x = 0, .y = 0 }, 0, .white);
            },
            else => {},
        }
    }
}

pub fn main() !void {
    try runRaylib();
}

var map_opened: bool = false;
var sidebar_opened: bool = true;

fn toggle_map() void {
    map_opened = !map_opened;
}

fn toggle_sidebar() void {
    sidebar_opened = !sidebar_opened;
}

fn inventoryAction() void {}
fn buildAction() void {}
fn settingsAction() void {}
const main_menu_items = [_]MenuItem{
    .{ .label = "Map", .action = toggle_map },
    .{ .label = "Inventory", .action = inventoryAction },
    .{ .label = "Build", .action = buildAction },
    .{ .label = "Settings", .action = settingsAction },
};

const BubbleItem = struct {
    label: [:0]const u8,
    action: *const fn () void,
};

const bubble_items = [_]BubbleItem{
    .{ .label = "Map", .action = &toggle_map },
    .{ .label = "Inventory", .action = &inventoryAction },
    .{ .label = "Build", .action = &buildAction },
    .{ .label = "Settings", .action = &settingsAction },
};

fn drawBubbleMenu(center: rl.Vector2, items: []const BubbleItem, mouse_pos: rl.Vector2, clicked: bool) bool {
    if (items.len == 0) return false;

    const item_radius: f32 = 36.0;
    const ring_radius: f32 = 110.0;
    const tau: f32 = 2.0 * std.math.pi;

    // Anchor circle at the center (player position on screen)
    rl.drawCircleV(center, 18, rl.Color{ .r = 30, .g = 34, .b = 48, .a = 235 });
    const center_ix: i32 = @intFromFloat(center.x);
    const center_iy: i32 = @intFromFloat(center.y);
    rl.drawCircleLines(center_ix, center_iy, 22, rl.Color{ .r = 64, .g = 72, .b = 102, .a = 255 });

    var close_menu = false;

    var idx: usize = 0;
    while (idx < items.len) : (idx += 1) {
        const item = items[idx];
        const angle = (tau / @as(f32, @floatFromInt(items.len))) * @as(f32, @floatFromInt(idx)) - std.math.pi * 0.5;
        const pos = rl.Vector2{
            .x = center.x + std.math.cos(angle) * ring_radius,
            .y = center.y + std.math.sin(angle) * ring_radius,
        };

        const hovered = rl.checkCollisionPointCircle(mouse_pos, pos, item_radius);
        const fill = if (hovered) rl.Color{ .r = 64, .g = 74, .b = 108, .a = 245 } else rl.Color{ .r = 42, .g = 48, .b = 68, .a = 220 };
        const stroke = rl.Color{ .r = 88, .g = 98, .b = 132, .a = 255 };
        rl.drawCircleV(pos, item_radius, fill);
        const pos_ix: i32 = @intFromFloat(pos.x);
        const pos_iy: i32 = @intFromFloat(pos.y);
        rl.drawCircleLines(pos_ix, pos_iy, item_radius, stroke);

        const text_w = rl.measureText(item.label, 16);
        rl.drawText(item.label, pos_ix - @divTrunc(text_w, 2), pos_iy - 8, 16, .ray_white);

        if (hovered and clicked) {
            item.action();
            close_menu = true;
        }
    }

    // Close the menu if user clicks outside the bubbles.
    if (clicked and !close_menu) {
        const outer_radius = ring_radius + item_radius;
        const dx = mouse_pos.x - center.x;
        const dy = mouse_pos.y - center.y;
        const dist_sq = dx * dx + dy * dy;
        if (dist_sq > outer_radius * outer_radius) {
            return true;
        }
    }

    return close_menu;
}

// Left Sidebar Menu Item
const SidebarItem = struct {
    icon: [:0]const u8, // Unicode icon or short text
    label: [:0]const u8,
    action: *const fn () void,
};

const sidebar_items = [_]SidebarItem{
    .{ .icon = "M", .label = "Map", .action = &toggle_map },
    .{ .icon = "I", .label = "Inventory", .action = &inventoryAction },
    .{ .icon = "B", .label = "Build", .action = &buildAction },
    .{ .icon = "S", .label = "Settings", .action = &settingsAction },
};

fn drawSidebar(sidebar_texture: rl.Texture2D, screen_height: i32, menu_height: i32) void {
    _ = menu_height;
    const sidebar_width: f32 = 220.0;
    const screen_height_f = @as(f32, @floatFromInt(screen_height));

    // Calculate source width to maintain aspect ratio
    // dest_ratio = sidebar_width / screen_height
    // src_width = src_height * dest_ratio
    const texture_height = @as(f32, @floatFromInt(sidebar_texture.height));
    const src_width = texture_height * (sidebar_width / screen_height_f);

    const src = rl.Rectangle{
        .x = 0,
        .y = 0,
        .width = src_width,
        .height = texture_height,
    };
    const dest = rl.Rectangle{
        .x = 0,
        .y = 0,
        .width = sidebar_width,
        .height = screen_height_f,
    };
    rl.drawTexturePro(sidebar_texture, src, dest, rl.Vector2{ .x = 0, .y = 0 }, 0, rl.Color.white);
}

pub fn runRaylib() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var world = try shared.World.loadFromFile(allocator, "assets/world.json");
    defer world.deinit(allocator);

    // Initialization
    //--------------------------------------------------------------------------------------
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "Bromance");
    defer rl.closeWindow(); // Close window and OpenGL context

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second
    //--------------------------------------------------------------------------------------

    var top_menu = try Menu.load();
    defer top_menu.deinit();
    const menu_height: i32 = top_menu.height;

    // Main game loop
    // Load Character Assets
    const assets = CharacterAssets{
        .idle_up = try rl.loadTexture("assets/MainCharacter/MainC_Idle_Back.PNG"),
        .idle_down = try rl.loadTexture("assets/MainCharacter/MainC_Idle_Front.PNG"),
        .idle_left = try rl.loadTexture("assets/MainCharacter/MainC_Idle_Left.PNG"),
        .idle_right = try rl.loadTexture("assets/MainCharacter/MainC_Idle_Right.PNG"),
        .walk_up = try rl.loadTexture("assets/MainCharacter/MainC_Walk_Back.PNG"),
        .walk_down = try rl.loadTexture("assets/MainCharacter/MainC_Walk_Front.PNG"),
        .walk_left = try rl.loadTexture("assets/MainCharacter/MainC_Walk_Left.PNG"),
        .walk_right = try rl.loadTexture("assets/MainCharacter/MainC_Walk_Right.PNG"),
        .shadow = try rl.loadTexture("assets/MainCharacter/MainC_Shadow.png"),
    };
    defer {
        rl.unloadTexture(assets.idle_up);
        rl.unloadTexture(assets.idle_down);
        rl.unloadTexture(assets.idle_left);
        rl.unloadTexture(assets.idle_right);
        rl.unloadTexture(assets.walk_up);
        rl.unloadTexture(assets.walk_down);
        rl.unloadTexture(assets.walk_left);
        rl.unloadTexture(assets.walk_right);
        rl.unloadTexture(assets.shadow);
    }
    // Load tileset for auto-tile system (like tile_inspector.zig)
    var tileset_img = try rl.loadImage("assets/Farm RPG FREE 16x16 - Tiny Asset Pack/Tileset/Tileset Spring.png");
    // Apply color keying for transparency (Black -> Transparent)
    rl.imageColorReplace(&tileset_img, rl.Color.black, rl.Color.blank);
    defer rl.unloadImage(tileset_img);
    const tileset_texture = try rl.loadTextureFromImage(tileset_img);
    defer rl.unloadTexture(tileset_texture);

    const terrain_img = try rl.loadImage("assets/terrain_sprites.png");
    defer rl.unloadImage(terrain_img);
    const terrain_texture = try rl.loadTextureFromImage(terrain_img);
    defer rl.unloadTexture(terrain_texture);

    const townhall_img = try rl.loadImage("assets/Farm RPG FREE 16x16 - Tiny Asset Pack/Objects/House.png");
    defer rl.unloadImage(townhall_img);
    const townhall_texture = try rl.loadTextureFromImage(townhall_img);
    defer rl.unloadTexture(townhall_texture);

    const lake_img = try rl.loadImage("assets/lake_small.png");
    defer rl.unloadImage(lake_img);
    const lake_texture = try rl.loadTextureFromImage(lake_img);
    defer rl.unloadTexture(lake_texture);

    const ruins_img = try rl.loadImage("assets/Buildings/Topdown RPG 32x32 - Ruins.PNG");
    defer rl.unloadImage(ruins_img);
    const ruins_texture = try rl.loadTextureFromImage(ruins_img);
    defer rl.unloadTexture(ruins_texture);

    var player = Character.init(rl.Vector2{ .x = 350, .y = 200 }, rl.Vector2{ .x = 32, .y = 32 });
    const speed = 200;
    var camera = rl.Camera2D{
        .target = .init(player.pos.x + 20, player.pos.y + 20),
        .offset = .init(screen_width / 2, screen_height / 2),
        .rotation = 0,
        .zoom = 1,
    };

    // Minimap
    const MINIMAP_SIZE: i32 = 180;
    const UI_MARGIN_PX: i32 = 32; // keep minimap a bit away from edges
    const MINIMAP_POS = rl.Vector2{
        .x = @as(f32, @floatFromInt(UI_MARGIN_PX)),
        .y = @as(f32, @floatFromInt(menu_height + UI_MARGIN_PX)),
    };
    const minimap = try rl.loadRenderTexture(MINIMAP_SIZE, MINIMAP_SIZE);
    defer rl.unloadRenderTexture(minimap);

    // Initialize auto-tile map from loaded world (like tile_inspector.zig)
    var auto_tile_map = try MultiLayerTileMap.initFromWorld(allocator, tileset_texture, world);
    defer auto_tile_map.deinit();

    // Initialize Game State
    var game_state = ClientGameState.init(allocator);
    defer game_state.deinit();

    // Initialize UDP Client
    var udp_client = try UdpClient.init(&game_state, world, .{
        .server_ip = "127.0.0.1",
        .server_port = 9999,
    });
    defer udp_client.deinit();

    // Spawn Network Thread
    const net_thread = try std.Thread.spawn(.{}, UdpClient.run, .{&udp_client});
    defer net_thread.join();

    // Main game loop
    var active_menu_item: ?usize = null;
    while (!rl.windowShouldClose()) {
        const delta = rl.getFrameTime();
        var move_cmd: ?MovementCommand = null;

        if (rl.isKeyDown(.w) or rl.isKeyDown(.up)) {
            move_cmd = .{ .direction = .Up, .speed = speed, .delta = delta };
        } else if (rl.isKeyDown(.s) or rl.isKeyDown(.down)) {
            move_cmd = .{ .direction = .Down, .speed = speed, .delta = delta };
        } else if (rl.isKeyDown(.a) or rl.isKeyDown(.left)) {
            move_cmd = .{ .direction = .Left, .speed = speed, .delta = delta };
        } else if (rl.isKeyDown(.d) or rl.isKeyDown(.right)) {
            move_cmd = .{ .direction = .Right, .speed = speed, .delta = delta };
        } else if (rl.isKeyPressed(.m)) {
            toggle_map();
        }

        if (move_cmd) |cmd| {
            // Push input to game state (thread-safe)
            _ = game_state.pushInput(cmd);
            // However, the 'reconcileState' logic is now in the network thread.
            // To get instant feedback, we should probably maintain a 'visual_pos' that we update immediately here.
            // But for simplicity of this refactor, let's stick to the architecture:
            // Input -> Queue -> Network Thread -> Update Snapshot (Reconciled) -> Render Thread reads Snapshot.
            // This adds 1 RTT + Processing delay to visual movement if we only read confirmed snapshots.
            // BUT, our 'reconcileState' logic in UdpClient (now Network Thread) applies pending moves to the latest server state.
            // So as soon as we push input, if we also had a way to apply it to the latest snapshot locally...
            // Actually, the previous code called 'sendMove' which updated 'pending_moves'.
            // Then 'pollState' would reconcile.
            // Here, we push to 'pending_moves'. The network thread reads it and sends it.
            // The network thread ALSO receives packets and reconciles.
            // If we want smooth movement, we need to predict locally.
            // Let's just push input for now and see.

        }

        // ... (Rendering) ...

        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(rl.Color.ray_white);

        // Camera follows player
        camera.target = player.pos;
        updateCameraFocus(&camera, player, screen_width, screen_height, world);

        rl.beginMode2D(camera);

        // Draw World using auto-tile system (like tile_inspector.zig)
        const tile_w: f32 = world.width / @as(f32, @floatFromInt(world.tiles_x));
        const tile_h: f32 = world.height / @as(f32, @floatFromInt(world.tiles_y));
        auto_tile_map.draw(tile_w, tile_h);

        // Draw all buildings from map configuration
        drawConstruction(townhall_texture, lake_texture, terrain_texture, ruins_texture, world);

        // Draw other players with animation
        // Uses double-buffered state - lock-free read from the active buffer
        {
            const other_players = game_state.getOtherPlayersForRender();
            var it = other_players.iterator();
            while (it.next()) |entry| {
                const other_player = entry.value_ptr.*;

                // Calculate sprite row based on direction
                // Calculate sprite row based on direction
                // const row: f32 = 0; // Only one row in new asset

                const now_ns: i64 = @intCast(std.time.nanoTimestamp());
                const stale_timeout_ns: i64 = 500_000_000; // 500ms
                const is_moving = other_player.is_moving and (now_ns - other_player.last_update_ns <= stale_timeout_ns);

                // Draw shadow
                const shadow_dest = rl.Rectangle{
                    .x = other_player.pos.x,
                    .y = other_player.pos.y + 2,
                    .width = 32,
                    .height = 32,
                };
                rl.drawTexturePro(assets.shadow, rl.Rectangle{ .x = 0, .y = 0, .width = 32, .height = 32 }, shadow_dest, rl.Vector2{ .x = 0, .y = 0 }, 0, .white);

                // Select texture and frame count
                const texture = if (is_moving) switch (other_player.dir) {
                    .Up => assets.walk_up,
                    .Down => assets.walk_down,
                    .Left => assets.walk_left,
                    .Right => assets.walk_right,
                } else switch (other_player.dir) {
                    .Up => assets.idle_up,
                    .Down => assets.idle_down,
                    .Left => assets.idle_left,
                    .Right => assets.idle_right,
                };

                const frame_count: f32 = if (is_moving) 4.0 else 9.0;
                const anim_speed: f32 = 8.0;
                const global_time = rl.getTime();
                const frame: i32 = @intFromFloat(@mod(global_time * anim_speed, frame_count));

                const src = rl.Rectangle{
                    .x = @as(f32, @floatFromInt(frame * 32)),
                    .y = 0,
                    .width = 32,
                    .height = 32,
                };
                const dest = rl.Rectangle{
                    .x = other_player.pos.x,
                    .y = other_player.pos.y,
                    .width = 32,
                    .height = 32,
                };
                rl.drawTexturePro(texture, src, dest, rl.Vector2{ .x = 0, .y = 0 }, 0, rl.Color{ .r = 200, .g = 200, .b = 255, .a = 255 });
            }
        }

        // Interpolate and Draw Local Player
        if (game_state.sampleInterpolated()) |pos| {
            player.pos = pos;
        }

        // Update player animation state based on input (visual only)
        if (move_cmd) |cmd| {
            player.update(delta, cmd.direction, true);
        } else {
            player.update(delta, .Down, false);
        }

        try player.draw(assets);
        rl.endMode2D();

        top_menu.draw(200, main_menu_items[0..], &active_menu_item);

        // Draw left sidebar overlay
        // if (sidebar_opened) {
        //     drawSidebar(sidebar_texture, screen_height, menu_height);
        // }

        // UI: draw the minimap (note the source height is flipped for render textures)
        if (map_opened) {
            updateMinimap(minimap, player.pos, world, MINIMAP_SIZE, MINIMAP_POS);
        }

        var buf: [128]u8 = undefined;
        const pos_text = std.fmt.bufPrintZ(&buf, "Player: ({:.0}, {:.0})", .{ player.pos.x, player.pos.y }) catch "";
        const minimap_pos_x: i32 = @intFromFloat(MINIMAP_POS.x);
        rl.drawText(pos_text, minimap_pos_x + 10, menu_height + 10, 20, .dark_gray);

        rl.drawFPS(10, menu_height + 10);
    }

    // Signal network thread to stop
    udp_client.running.store(false, .release);
}

fn updateMinimap(target: rl.RenderTexture2D, player_pos: rl.Vector2, world: shared.World, size: f32, MINIMAP_POS: rl.Vector2) void {
    // 1. Update the minimap texture content (Inside a block!)
    {
        rl.beginTextureMode(target);
        defer rl.endTextureMode();

        rl.clearBackground(rl.Color.light_gray);

        // Draw buildings on minimap
        for (world.buildings) |building| {
            // Convert building tile coordinates to world pixels
            const building_x = world.tileToWorldX(building.tile_x);
            const building_y = world.tileToWorldY(building.tile_y);
            const building_w = world.tileToWorldX(building.width_tiles);
            const building_h = world.tileToWorldY(building.height_tiles);

            // Convert to minimap coordinates
            const minimap_x = (building_x / world.width) * size;
            const minimap_y = (building_y / world.height) * size;
            const minimap_w = (building_w / world.width) * size;
            const minimap_h = (building_h / world.height) * size;

            // Choose color based on building type
            const building_color = switch (building.building_type) {
                .Townhall => rl.Color.gold,
                .House => rl.Color.orange,
                .Shop => rl.Color.purple,
                .Farm => rl.Color.green,
                .Lake => rl.Color.blue,
                .Road => rl.Color.brown,
            };

            // Draw building as a small rectangle
            rl.drawRectangle(@intFromFloat(minimap_x), @intFromFloat(minimap_y), @intFromFloat(minimap_w), @intFromFloat(minimap_h), building_color);
        }

        // Draw player
        const px = (player_pos.x / world.width) * size;
        const py = (player_pos.y / world.height) * size;
        rl.drawCircle(@intFromFloat(px), @intFromFloat(py), 4, rl.Color.red);
    } // <--- Texture mode ends here

    // 2. Draw the updated texture to the screen
    const src = rl.Rectangle{
        .x = 0,
        .y = 0,
        .width = @as(f32, @floatFromInt(target.texture.width)),
        .height = -@as(f32, @floatFromInt(target.texture.height)),
    };
    const dst = rl.Rectangle{
        .x = MINIMAP_POS.x,
        .y = MINIMAP_POS.y,
        .width = @as(f32, size),
        .height = @as(f32, size),
    };
    rl.drawTexturePro(target.texture, src, dst, rl.Vector2{ .x = 0, .y = 0 }, 0, .white);
    rl.drawRectangleLines(@intFromFloat(dst.x), @intFromFloat(dst.y), @intFromFloat(size), @intFromFloat(size), .black);
}

fn drawWorldTiles(texture: rl.Texture2D, world: shared.World) void {
    const tile_w: f32 = world.width / @as(f32, @floatFromInt(world.tiles_x));
    const tile_h: f32 = world.height / @as(f32, @floatFromInt(world.tiles_y));
    var ty: i32 = 0;
    while (ty < world.tiles_y) : (ty += 1) {
        var tx: i32 = 0;
        while (tx < world.tiles_x) : (tx += 1) {
            const terrain_idx: i32 = 0; // Default Grass

            // Source rect from sprite sheet (horizontal strip)
            // 0: Grass, 1: Rock, 2: Water
            // The sprite sheet is 200x50, with 4 tiles of 50x50.
            // Indices: 0=Grass, 1=Rock, 2=Water, 3=Road?
            // Let's assume the sprite sheet matches our indices.
            const TILE_SRC_SIZE: f32 = 50;

            const src = rl.Rectangle{
                .x = @as(f32, @floatFromInt(terrain_idx)) * TILE_SRC_SIZE,
                .y = 0,
                .width = TILE_SRC_SIZE,
                .height = TILE_SRC_SIZE,
            };

            const dest = rl.Rectangle{
                .x = @as(f32, @floatFromInt(tx)) * tile_w,
                .y = @as(f32, @floatFromInt(ty)) * tile_h,
                .width = tile_w,
                .height = tile_h,
            };

            rl.drawTexturePro(texture, src, dest, rl.Vector2{ .x = 0, .y = 0 }, 0, .white);
        }
    }
}
