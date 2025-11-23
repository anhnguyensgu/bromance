const std = @import("std");
const rl = @import("raylib");
const command = @import("movement/command.zig");
const MovementCommand = command.MovementCommand;
const MoveDirection = command.MoveDirection;
const client = @import("client/udp_client.zig");
const UdpClient = client.UdpClient;
const applyMoveToVector = client.applyMoveToVector;
const shared = @import("shared.zig");

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

    rl.initWindow(screenWidth, screenHeight, "raylib-zig [core] example - basic window");
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

    // Minimap
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

            // Check collision at new position using shared World logic
            const collision = shared.World.checkCollision(new_pos.x, new_pos.y, player.size.x, player.size.y, cmd.direction);

            if (!collision) {
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

        // Update minimap texture
        updateMinimap(minimap, player.pos, WORLD_W, WORLD_H, MINIMAP_SIZE);

        rl.beginDrawing();
        defer rl.endDrawing();

        // World render (camera space) with camera clamped to world bounds,
        // reserving the minimap area (plus a little extra) so the player
        // never goes under it.
        const view_half_w: f32 = (@as(f32, @floatFromInt(screenWidth)) * 0.5) / camera.zoom;
        const view_half_h: f32 = (@as(f32, @floatFromInt(screenHeight)) * 0.5) / camera.zoom;

        var cam_target_x: f32 = player.pos.x + player.size.x * 0.5;
        var cam_target_y: f32 = player.pos.y + player.size.y * 0.5;

        // Convert minimap occupied pixels into world-units margins on the top/left.
        // Reserve: minimap size + UI margin + a small player-safe pad, so the world
        // renders lower/right enough that the player won't slide under the minimap.
        const PLAYER_SAFE_PX: f32 = 8.0; // extra padding to keep player comfortably away
        const reserved_left_px: f32 =
            MINIMAP_POS.x +
            @as(f32, @floatFromInt(MINIMAP_SIZE)) +
            @as(f32, @floatFromInt(UI_MARGIN_PX)) +
            PLAYER_SAFE_PX;
        // Keep extra vertical headroom so the minimap feels clearly above
        // the world boundary: add an extra UI margin to the reserved band.
        const reserved_top_px: f32 =
            MINIMAP_POS.y +
            @as(f32, @floatFromInt(MINIMAP_SIZE)) +
            (@as(f32, @floatFromInt(UI_MARGIN_PX)) * 2) +
            PLAYER_SAFE_PX;
        const min_bound_x: f32 = ((@as(f32, @floatFromInt(screenWidth)) * 0.5) - reserved_left_px) / camera.zoom;
        const min_bound_y: f32 = ((@as(f32, @floatFromInt(screenHeight)) * 0.5) - reserved_top_px) / camera.zoom;
        const min_x = @max(min_bound_x, 0.0);
        const min_y = @max(min_bound_y, 0.0);

        if (WORLD_W > view_half_w * 2) {
            cam_target_x = std.math.clamp(cam_target_x, min_x, WORLD_W - view_half_w);
        } else {
            cam_target_x = WORLD_W * 0.5;
        }
        if (WORLD_H > view_half_h * 2) {
            cam_target_y = std.math.clamp(cam_target_y, min_y, WORLD_H - view_half_h);
        } else {
            cam_target_y = WORLD_H * 0.5;
        }

        // Avoid covering player with a fixed minimap by shifting camera target
        // so the player's projected screen position stays outside the minimap rect
        const UI_SAFE_MARGIN: f32 = 8.0;
        const player_center_x: f32 = player.pos.x + player.size.x * 0.5;
        const player_center_y: f32 = player.pos.y + player.size.y * 0.5;

        // Compute player's screen position for the current (clamped) camera
        var px_screen: f32 = (player_center_x - cam_target_x) * camera.zoom + camera.offset.x;
        var py_screen: f32 = (player_center_y - cam_target_y) * camera.zoom + camera.offset.y;

        const mm_left: f32 = MINIMAP_POS.x;
        const mm_top: f32 = MINIMAP_POS.y;
        const mm_right: f32 = mm_left + @as(f32, @floatFromInt(MINIMAP_SIZE));
        const mm_bottom: f32 = mm_top + @as(f32, @floatFromInt(MINIMAP_SIZE));

        const inside_h = (px_screen >= mm_left - UI_SAFE_MARGIN) and (px_screen <= mm_right + UI_SAFE_MARGIN);
        const inside_v = (py_screen >= mm_top - UI_SAFE_MARGIN) and (py_screen <= mm_bottom + UI_SAFE_MARGIN);

        if (inside_h) {
            const desired_px = mm_right + UI_SAFE_MARGIN;
            cam_target_x = player_center_x - (desired_px - camera.offset.x) / camera.zoom;
            // re-clamp to world bounds
            if (WORLD_W > view_half_w * 2) {
                cam_target_x = std.math.clamp(cam_target_x, view_half_w, WORLD_W - view_half_w);
            } else {
                cam_target_x = WORLD_W * 0.5;
            }
            px_screen = (player_center_x - cam_target_x) * camera.zoom + camera.offset.x;
        }
        if (inside_v) {
            const desired_py = mm_bottom + UI_SAFE_MARGIN;
            cam_target_y = player_center_y - (desired_py - camera.offset.y) / camera.zoom;
            if (WORLD_H > view_half_h * 2) {
                cam_target_y = std.math.clamp(cam_target_y, view_half_h, WORLD_H - view_half_h);
            } else {
                cam_target_y = WORLD_H * 0.5;
            }
            py_screen = (player_center_y - cam_target_y) * camera.zoom + camera.offset.y;
        }

        camera.target = .init(cam_target_x, cam_target_y);
        camera.begin();

        // Camera follows player
        // Calculate target position (centered on player)
        rl.clearBackground(rl.Color.ray_white);

        rl.beginMode2D(camera);

        // Draw World
        drawWorldTiles(terrain_texture, WORLD_W, WORLD_H);
        try player.draw();
        camera.end();

        // UI: draw the minimap (note the source height is flipped for render textures)
        const src = rl.Rectangle{
            .x = 0,
            .y = 0,
            .width = @as(f32, @floatFromInt(minimap.texture.width)),
            .height = -@as(f32, @floatFromInt(minimap.texture.height)),
        };
        const dst = rl.Rectangle{
            .x = MINIMAP_POS.x,
            .y = MINIMAP_POS.y,
            .width = @as(f32, @floatFromInt(MINIMAP_SIZE)),
            .height = @as(f32, @floatFromInt(MINIMAP_SIZE)),
        };
        rl.drawTexturePro(minimap.texture, src, dst, rl.Vector2{ .x = 0, .y = 0 }, 0, .white);
        rl.drawRectangleLines(@intFromFloat(dst.x), @intFromFloat(dst.y), MINIMAP_SIZE, MINIMAP_SIZE, .black);
        var buf: [128]u8 = undefined;
        const pos_text = std.fmt.bufPrintZ(&buf, "Player: ({:.0}, {:.0})", .{ player.pos.x, player.pos.y }) catch "";
        rl.drawText(
            pos_text,
            MINIMAP_SIZE + @as(i32, @intFromFloat(MINIMAP_POS.x)) + 10,
            @as(i32, @intFromFloat(MINIMAP_POS.y)),
            20,
            .dark_gray,
        );

        udp_client.pollState();
        if (udp_client.sampleInterpolated()) |state| {
            player.pos = state;
        }
    }
}

fn updateMinimap(target: rl.RenderTexture2D, player_pos: rl.Vector2, world_w: f32, world_h: f32, size: f32) void {
    rl.beginTextureMode(target);
    defer rl.endTextureMode();

    rl.clearBackground(rl.Color.light_gray);

    // Draw simplified world representation
    // Water center
    const center_x = size / 2;
    const center_y = size / 2;
    rl.drawCircle(@intFromFloat(center_x), @intFromFloat(center_y), size * 0.15, rl.Color.blue); // Water approx

    // Rock ring
    rl.drawRing(rl.Vector2{ .x = center_x, .y = center_y }, size * 0.1, size * 0.15, 0, 360, 0, rl.Color.brown); // Rock approx

    // Grass outer (background is already gray, maybe draw green rect?)
    // Actually we cleared to light gray. Let's draw green rect first?
    // Optimization: Just draw circles.

    // Draw player
    const px = (player_pos.x / world_w) * size;
    const py = (player_pos.y / world_h) * size;
    rl.drawCircle(@intFromFloat(px), @intFromFloat(py), 4, rl.Color.red);
}

fn drawWorldTiles(texture: rl.Texture2D, world_w: f32, world_h: f32) void {
    const tile_w: f32 = world_w / @as(f32, @floatFromInt(shared.World.TILES_X));
    const tile_h: f32 = world_h / @as(f32, @floatFromInt(shared.World.TILES_Y));
    var ty: i32 = 0;
    while (ty < shared.World.TILES_Y) : (ty += 1) {
        var tx: i32 = 0;
        while (tx < shared.World.TILES_X) : (tx += 1) {
            // Apply same distance-based logic as drawWorldTiles
            const center_x = shared.World.TILES_X / 2;
            const center_y = shared.World.TILES_Y / 2;
            const dx = tx - center_x;
            const dy = ty - center_y;
            const dist_sq = dx * dx + dy * dy;

            var terrain_idx: i32 = 0; // Default Grass
            if (dist_sq < 16) {
                terrain_idx = 2; // Water
            } else if (dist_sq < 25) {
                terrain_idx = 1; // Rock
            }

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
