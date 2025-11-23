const std = @import("std");
const rl = @import("raylib");
const command = @import("movement/command.zig");
const MovementCommand = command.MovementCommand;
const MoveDirection = command.MoveDirection;
const client = @import("client/udp_client.zig");
const UdpClient = client.UdpClient;
const applyMoveToVector = client.applyMoveToVector;

// Tile grid shared by world render and minimap so visuals match
const TILES_X: i32 = 50;
const TILES_Y: i32 = 50;

pub fn main() !void {
    try runRaylib();
}

pub fn runRaylib() anyerror!void {
    const WORLD_W: f32 = 2000;
    const WORLD_H: f32 = 2000;
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
        .size = rl.Vector2{ .x = 50, .y = 50 },
        .is_moving = false,
        .char_texture = char_texture,
        .dir = .Up,
        .frame_index = 0,
        .anim_timer = 0,
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
    var pending_move: ?MovementCommand = null;
    var udp_client = try UdpClient.init(.{ .server_ip = "127.0.0.1", .server_port = 9999 });
    defer udp_client.deinit();
    udp_client.sendPing() catch |err| std.debug.print("failed to send ping: {s}\n", .{@errorName(err)});

    while (!rl.windowShouldClose()) {
        const dt = rl.getFrameTime();

        if (rl.isKeyDown(.down)) {
            const cmd = MovementCommand{ .direction = .Down, .speed = speed, .delta = dt };
            applyMoveToVector(&player.pos, cmd);
            pending_move = cmd;
        } else if (rl.isKeyDown(.up)) {
            const cmd = MovementCommand{ .direction = .Up, .speed = speed, .delta = dt };
            applyMoveToVector(&player.pos, cmd);
            pending_move = cmd;
        } else if (rl.isKeyDown(.right)) {
            const cmd = MovementCommand{ .direction = .Right, .speed = speed, .delta = dt };
            applyMoveToVector(&player.pos, cmd);
            pending_move = cmd;
        } else if (rl.isKeyDown(.left)) {
            const cmd = MovementCommand{ .direction = .Left, .speed = speed, .delta = dt };
            applyMoveToVector(&player.pos, cmd);
            pending_move = cmd;
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
        if (pending_move) |cmd| {
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
        rl.clearBackground(.white);
        // Draw world tiles matching the minimap pattern
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

fn updateMinimap(mm: rl.RenderTexture2D, player: rl.Vector2, world_w: f32, world_h: f32, mm_size: i32) void {
    rl.beginTextureMode(mm);
    defer rl.endTextureMode();

    // Draw tiles matching world grid, using exact integer partitioning
    // This guarantees full coverage of the minimap texture without gaps.
    rl.clearBackground(.light_gray);
    var ty: i32 = 0;
    while (ty < TILES_Y) : (ty += 1) {
        const y0: i32 = @divTrunc(ty * mm_size, TILES_Y);
        const y1: i32 = @divTrunc((ty + 1) * mm_size, TILES_Y);
        const h: i32 = y1 - y0;
        var tx: i32 = 0;
        while (tx < TILES_X) : (tx += 1) {
            const x0: i32 = @divTrunc(tx * mm_size, TILES_X);
            const x1: i32 = @divTrunc((tx + 1) * mm_size, TILES_X);
            const w: i32 = x1 - x0;
            const on = (((tx + ty) & 1) == 0);
            const color = if (on)
                rl.Color{ .r = 200, .g = 240, .b = 200, .a = 255 }
            else
                rl.Color{ .r = 160, .g = 210, .b = 160, .a = 255 };
            rl.drawRectangle(x0, y0, w, h, color);
        }
    }

    // Player dot (map world position to minimap pixels)
    const px = std.math.clamp(player.x / world_w, 0.0, 1.0);
    const py = std.math.clamp(player.y / world_h, 0.0, 1.0);
    const dot = rl.Vector2{
        .x = px * @as(f32, @floatFromInt(mm_size)),
        .y = py * @as(f32, @floatFromInt(mm_size)),
    };
    rl.drawCircleV(dot, 5.0, .yellow);

    // Line from minimap center to player dot (example line drawing)
    const cx: i32 = @divTrunc(mm_size, 2);
    const cy: i32 = @divTrunc(mm_size, 2);
    rl.drawLine(cx, cy, @as(i32, @intFromFloat(dot.x)), @as(i32, @intFromFloat(dot.y)), rl.Color{ .r = 255, .g = 64, .b = 64, .a = 255 });
}

fn drawWorldTiles(texture: rl.Texture2D, world_w: f32, world_h: f32) void {
    const tile_w: f32 = world_w / @as(f32, @floatFromInt(TILES_X));
    const tile_h: f32 = world_h / @as(f32, @floatFromInt(TILES_Y));
    var ty: i32 = 0;
    while (ty < TILES_Y) : (ty += 1) {
        var tx: i32 = 0;
        while (tx < TILES_X) : (tx += 1) {
            // Custom layout: Water center, Rock ring, Grass outer
            const center_x = TILES_X / 2;
            const center_y = TILES_Y / 2;
            const dx = tx - center_x;
            const dy = ty - center_y;
            const dist_sq = dx * dx + dy * dy;

            var terrain_idx: i32 = 0; // Default Grass
            if (dist_sq < 16) {
                terrain_idx = 2; // Water
            } else if (dist_sq < 25) {
                terrain_idx = 1; // Rock
            }

            // The provided image is 200x50 (4 tiles of 50x50).
            const TILE_SRC_W: f32 = 50;
            const TILE_SRC_H: f32 = 50;

            const src = rl.Rectangle{
                .x = @as(f32, @floatFromInt(terrain_idx)) * TILE_SRC_W,
                .y = 0,
                .width = TILE_SRC_W,
                .height = TILE_SRC_H,
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
            .width = 32,
            .height = 32,
        };
        rl.drawTexturePro(self.char_texture, src, dest, rl.Vector2{ .x = 0, .y = 0 }, 0, .white);
    }
};
