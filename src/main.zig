const std = @import("std");
const rl = @import("raylib");
const command = @import("movement/command.zig");
const MovementCommand = command.MovementCommand;
const MoveDirection = command.MoveDirection;
const client = @import("client/udp_client.zig");
const UdpClient = client.UdpClient;
const applyMoveToVector = client.applyMoveToVector;
const shared = @import("shared.zig");

// Helper function to convert tile coordinates to world pixel coordinates
fn tileToWorld(tile_coord: i32, world_size: f32, tiles_count: i32) f32 {
    const tile_size = world_size / @as(f32, @floatFromInt(tiles_count));
    return @as(f32, @floatFromInt(tile_coord)) * tile_size;
}

// Check if a position collides with any building on the map
fn checkBuildingCollision(x: f32, y: f32, w: f32, h: f32) bool {
    const player_left = x;
    const player_right = x + w;
    const player_top = y;
    const player_bottom = y + h;

    for (shared.MAP_BUILDINGS) |building| {
        // Skip roads for collision (they are walkable)
        if (building.building_type == .Road) continue;

        const template = shared.getBuildingTemplate(building.building_type);

        // Convert building tile coordinates to world pixels
        const building_x = tileToWorld(building.tile_x, shared.World.WIDTH, shared.World.TILES_X);
        const building_y = tileToWorld(building.tile_y, shared.World.HEIGHT, shared.World.TILES_Y);
        const building_w = tileToWorld(template.width_tiles, shared.World.WIDTH, shared.World.TILES_X);
        const building_h = tileToWorld(template.height_tiles, shared.World.HEIGHT, shared.World.TILES_Y);

        const building_left = building_x;
        const building_right = building_x + building_w;
        const building_top = building_y;
        const building_bottom = building_y + building_h;

        // AABB collision detection
        const overlaps_x = player_right > building_left and player_left < building_right;
        const overlaps_y = player_bottom > building_top and player_top < building_bottom;

        if (overlaps_x and overlaps_y) {
            return true;
        }
    }

    return false;
}

fn updateCameraFocus(camera: *rl.Camera2D, player: Character, screenWidth: i32, screenHeight: i32, world_w: f32, world_h: f32) void {
    const view_half_w: f32 = (@as(f32, @floatFromInt(screenWidth)) * 0.5) / camera.zoom;
    const view_half_h: f32 = (@as(f32, @floatFromInt(screenHeight)) * 0.5) / camera.zoom;

    var cam_target_x: f32 = player.pos.x + player.size.x * 0.5;
    var cam_target_y: f32 = player.pos.y + player.size.y * 0.5;

    // Basic clamping to world bounds
    if (world_w > view_half_w * 2) {
        cam_target_x = std.math.clamp(cam_target_x, view_half_w, world_w - view_half_w);
    } else {
        cam_target_x = world_w * 0.5;
    }
    if (world_h > view_half_h * 2) {
        cam_target_y = std.math.clamp(cam_target_y, view_half_h, world_h - view_half_h);
    } else {
        cam_target_y = world_h * 0.5;
    }

    camera.target = .init(cam_target_x, cam_target_y);
}

fn drawConstruction(townhall_texture: rl.Texture2D, lake_texture: rl.Texture2D, terrain_texture: rl.Texture2D, world_w: f32, world_h: f32) void {
    // Draw all buildings from map configuration
    for (shared.MAP_BUILDINGS) |building| {
        const template = shared.getBuildingTemplate(building.building_type);

        // Convert tile coordinates to world pixels
        const building_x = tileToWorld(building.tile_x, world_w, shared.World.TILES_X);
        const building_y = tileToWorld(building.tile_y, world_h, shared.World.TILES_Y);

        switch (building.building_type) {
            .Townhall => {
                const building_pos = rl.Vector2{ .x = building_x, .y = building_y };
                const building_source = rl.Rectangle{ .x = 0, .y = 0, .width = @floatFromInt(townhall_texture.width), .height = @floatFromInt(townhall_texture.height) };
                const building_dest = rl.Rectangle{ .x = building_pos.x, .y = building_pos.y, .width = template.sprite_width, .height = template.sprite_height };
                rl.drawTexturePro(townhall_texture, building_source, building_dest, rl.Vector2{ .x = 0, .y = 0 }, 0, .white);
            },
            .Lake => {
                const building_pos = rl.Vector2{ .x = building_x, .y = building_y };
                const building_source = rl.Rectangle{ .x = 0, .y = 0, .width = @floatFromInt(lake_texture.width), .height = @floatFromInt(lake_texture.height) };
                const building_dest = rl.Rectangle{ .x = building_pos.x, .y = building_pos.y, .width = template.sprite_width, .height = template.sprite_height };
                rl.drawTexturePro(lake_texture, building_source, building_dest, rl.Vector2{ .x = 0, .y = 0 }, 0, .white);
            },
            .Road => {
                const building_pos = rl.Vector2{ .x = building_x, .y = building_y };
                const TILE_SRC_SIZE: f32 = 50;
                const road_idx: f32 = 3; // Index 3 is Road

                const building_source = rl.Rectangle{ .x = road_idx * TILE_SRC_SIZE, .y = 0, .width = TILE_SRC_SIZE, .height = TILE_SRC_SIZE };
                const building_dest = rl.Rectangle{ .x = building_pos.x, .y = building_pos.y, .width = template.sprite_width, .height = template.sprite_height };
                rl.drawTexturePro(terrain_texture, building_source, building_dest, rl.Vector2{ .x = 0, .y = 0 }, 0, .white);
            },
            else => {},
        }
    }
}

pub fn main() !void {
    try runRaylib();
}

pub fn runRaylib() anyerror!void {
    const WORLD_W: f32 = shared.World.WIDTH;
    const WORLD_H: f32 = shared.World.HEIGHT;
    // Initialization
    //--------------------------------------------------------------------------------------
    const screenWidth = 800;
    const screenHeight = 450;

    rl.initWindow(screenWidth, screenHeight, "Bromance");
    defer rl.closeWindow(); // Close window and OpenGL context

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second
    //--------------------------------------------------------------------------------------

    // Main game loop
    const img = try rl.loadImage("assets/combined_sprite_sheet_48x48.png");
    defer rl.unloadImage(img);
    const char_texture = try rl.loadTextureFromImage(img);
    defer rl.unloadTexture(char_texture);
    const terrain_img = try rl.loadImage("assets/terrain_sprites.png");
    defer rl.unloadImage(terrain_img);
    const terrain_texture = try rl.loadTextureFromImage(terrain_img);
    defer rl.unloadTexture(terrain_texture);

    const townhall_img = try rl.loadImage("assets/townhall_medium.png");
    defer rl.unloadImage(townhall_img);
    const townhall_texture = try rl.loadTextureFromImage(townhall_img);
    defer rl.unloadTexture(townhall_texture);

    const lake_img = try rl.loadImage("assets/lake_small.png");
    defer rl.unloadImage(lake_img);
    const lake_texture = try rl.loadTextureFromImage(lake_img);
    defer rl.unloadTexture(lake_texture);

    var player = Character{
        .pos = rl.Vector2{ .x = 350, .y = 200 },
        .size = rl.Vector2{ .x = 32, .y = 32 },
        .is_moving = false,
        .char_texture = char_texture,
        .dir = .Up,
        .frame_index = 0,
        .anim_timer = 0,
        .debug = true,
    };
    const speed = 200;
    var camera = rl.Camera2D{
        .target = .init(player.pos.x + 20, player.pos.y + 20),
        .offset = .init(screenWidth / 2, screenHeight / 2),
        .rotation = 0,
        .zoom = 1,
    };

    // // Minimap
    const MINIMAP_SIZE: i32 = 180;
    const UI_MARGIN_PX: i32 = 32; // keep minimap a bit away from edges
    const MINIMAP_POS = rl.Vector2{
        .x = @as(f32, @floatFromInt(UI_MARGIN_PX)),
        .y = @as(f32, @floatFromInt(UI_MARGIN_PX)),
    };
    const minimap = try rl.loadRenderTexture(MINIMAP_SIZE, MINIMAP_SIZE);
    defer rl.unloadRenderTexture(minimap);

    const move_send_interval: f32 = 0.05;
    var move_accum: f32 = 0.0;
    var udp_client = try UdpClient.init(.{ .server_ip = "127.0.0.1", .server_port = 9999 });
    defer udp_client.deinit();
    udp_client.sendPing() catch |err| std.debug.print("failed to send ping: {s}\n", .{@errorName(err)});

    var pending_move: ?MovementCommand = null;
    while (!rl.windowShouldClose()) {
        const dt = rl.getFrameTime();

        // Input handling - just capture the intended move
        if (rl.isKeyDown(.down)) {
            pending_move = MovementCommand{ .direction = .Down, .speed = speed, .delta = dt };
        } else if (rl.isKeyDown(.up)) {
            pending_move = MovementCommand{ .direction = .Up, .speed = speed, .delta = dt };
        } else if (rl.isKeyDown(.right)) {
            pending_move = MovementCommand{ .direction = .Right, .speed = speed, .delta = dt };
        } else if (rl.isKeyDown(.left)) {
            pending_move = MovementCommand{ .direction = .Left, .speed = speed, .delta = dt };
        } else {
            pending_move = null;
        }

        move_accum += dt;
        if (move_accum >= move_send_interval) {
            move_accum = 0;
            if (pending_move) |cmd| {
                udp_client.sendMove(cmd) catch |err| std.debug.print("failed to send move: {s}\n", .{@errorName(err)});
            }
        }

        // Apply movement with collision detection
        if (pending_move) |cmd| {
            const old_pos = player.pos;
            var new_pos = old_pos;
            applyMoveToVector(&new_pos, cmd);

            // Check terrain collision using shared World logic
            const terrain_collision = shared.World.checkCollision(new_pos.x, new_pos.y, player.size.x, player.size.y, cmd.direction);

            // Check building collision
            const building_collision = checkBuildingCollision(new_pos.x, new_pos.y, player.size.x, player.size.y);

            if (!terrain_collision and !building_collision) {
                player.pos = new_pos;
            }
            player.update(dt, cmd.direction, true);
        } else {
            player.update(dt, .Down, false);
        }

        // Clamp to world bounds
        if (player.pos.x < 0) player.pos.x = 0;
        if (player.pos.y < 0) player.pos.y = 0;
        if (player.pos.x > WORLD_W - player.size.x) player.pos.x = WORLD_W - player.size.x;
        if (player.pos.y > WORLD_H - player.size.y) player.pos.y = WORLD_H - player.size.y;

        rl.beginDrawing();
        defer rl.endDrawing();

        // Camera follows player
        updateCameraFocus(&camera, player, screenWidth, screenHeight, WORLD_W, WORLD_H);

        rl.clearBackground(rl.Color.ray_white);
        rl.beginMode2D(camera);

        // Draw World
        drawWorldTiles(terrain_texture, WORLD_W, WORLD_H);

        // Draw all buildings from map configuration
        drawConstruction(townhall_texture, lake_texture, terrain_texture, WORLD_W, WORLD_H);

        try player.draw();
        camera.end();

        // UI: draw the minimap (note the source height is flipped for render textures)
        updateMinimap(minimap, player.pos, WORLD_W, WORLD_H, MINIMAP_SIZE, MINIMAP_POS);

        var buf: [128]u8 = undefined;
        const pos_text = std.fmt.bufPrintZ(&buf, "Player: ({:.0}, {:.0})", .{ player.pos.x, player.pos.y }) catch "";
        rl.drawText(
            pos_text,
            MINIMAP_POS.x + 10,
            10,
            20,
            .dark_gray,
        );

        rl.drawFPS(10, 10);

        //sending to server
        udp_client.pollState();
        if (udp_client.sampleInterpolated()) |state| {
            player.pos = state;
        }
    }
}

fn updateMinimap(target: rl.RenderTexture2D, player_pos: rl.Vector2, world_w: f32, world_h: f32, size: f32, MINIMAP_POS: rl.Vector2) void {
    // 1. Update the minimap texture content (Inside a block!)
    {
        rl.beginTextureMode(target);
        defer rl.endTextureMode();

        rl.clearBackground(rl.Color.light_gray);

        // Draw buildings on minimap
        for (shared.MAP_BUILDINGS) |building| {
            const template = shared.getBuildingTemplate(building.building_type);

            // Convert building tile coordinates to world pixels
            const building_x = tileToWorld(building.tile_x, world_w, shared.World.TILES_X);
            const building_y = tileToWorld(building.tile_y, world_h, shared.World.TILES_Y);
            const building_w = tileToWorld(template.width_tiles, world_w, shared.World.TILES_X);
            const building_h = tileToWorld(template.height_tiles, world_h, shared.World.TILES_Y);

            // Convert to minimap coordinates
            const minimap_x = (building_x / world_w) * size;
            const minimap_y = (building_y / world_h) * size;
            const minimap_w = (building_w / world_w) * size;
            const minimap_h = (building_h / world_h) * size;

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
        const px = (player_pos.x / world_w) * size;
        const py = (player_pos.y / world_h) * size;
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

fn drawWorldTiles(texture: rl.Texture2D, world_w: f32, world_h: f32) void {
    const tile_w: f32 = world_w / @as(f32, @floatFromInt(shared.World.TILES_X));
    const tile_h: f32 = world_h / @as(f32, @floatFromInt(shared.World.TILES_Y));
    var ty: i32 = 0;
    while (ty < shared.World.TILES_Y) : (ty += 1) {
        var tx: i32 = 0;
        while (tx < shared.World.TILES_X) : (tx += 1) {
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

const Character = struct {
    pos: rl.Vector2,
    size: rl.Vector2,
    dir: MoveDirection,
    is_moving: bool,
    char_texture: rl.Texture2D,
    frame_index: usize,
    anim_timer: f32,
    debug: bool,

    const WALK_SPEED: f32 = 0.1;
    const FRAME_WIDTH: f32 = 16;
    const FRAME_HEIGHT: f32 = 16;
    const Self = @This();

    pub fn init(pos: rl.Vector2, size: rl.Vector2) Self {
        return .{
            .pos = pos,
            .size = size,
            .is_moving = false,
        };
    }

    pub fn update(self: *Self, dt: f32, dir: MoveDirection, is_moving: bool) void {
        self.is_moving = is_moving;
        if (self.is_moving) {
            self.dir = dir;
            self.anim_timer += dt;
            if (self.anim_timer >= WALK_SPEED) {
                self.anim_timer = 0;
                self.frame_index = (self.frame_index + 1) % 3;
            }
        }
    }

    pub fn draw(self: *Self) !void {
        const row: f32 = switch (self.dir) {
            .Up => 0,
            .Down => 1,
            .Right => 2,
            .Left => 2,
        };
        const width: f32 = if (self.dir == .Left) -FRAME_WIDTH else FRAME_WIDTH;
        const src = rl.Rectangle{
            .x = FRAME_WIDTH * @as(f32, @floatFromInt(self.frame_index)),
            .y = row * FRAME_HEIGHT,
            .width = width,
            .height = FRAME_HEIGHT,
        };
        const dest = rl.Rectangle{
            .x = self.pos.x,
            .y = self.pos.y,
            .width = self.size.x,
            .height = self.size.y,
        };
        rl.drawTexturePro(self.char_texture, src, dest, rl.Vector2{ .x = 0, .y = 0 }, 0, .white);
        if (self.debug) {
            rl.drawRectangleLines(@intFromFloat(self.pos.x), @intFromFloat(self.pos.y), @intFromFloat(self.size.x), @intFromFloat(self.size.y), .red);
        }
    }
};
