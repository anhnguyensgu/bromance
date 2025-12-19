const rl = @import("raylib");
const Player = @import("../../game/entities/player.zig").Player;

pub const PlayerAssets = struct {
    idle_up: rl.Texture2D,
    idle_down: rl.Texture2D,
    idle_left: rl.Texture2D,
    idle_right: rl.Texture2D,
    walk_up: rl.Texture2D,
    walk_down: rl.Texture2D,
    walk_left: rl.Texture2D,
    walk_right: rl.Texture2D,
    shadow: rl.Texture2D,
};

pub const PlayerRenderer = struct {
    frame_index: usize = 0,
    anim_timer: f32 = 0,
    last_moving: bool = false,
    debug: bool = true,

    const WALK_SPEED: f32 = 0.1;
    const FRAME_WIDTH: f32 = 32;
    const FRAME_HEIGHT: f32 = 32;

    pub fn update(self: *PlayerRenderer, dt: f32, player: *const Player) void {
        if (player.is_moving) {
            self.anim_timer += dt;
            if (self.anim_timer >= WALK_SPEED) {
                self.anim_timer = 0;
                self.frame_index = (self.frame_index + 1) % 4; // Walk has 4 frames
            }
        } else {
            if (self.last_moving) {
                self.frame_index = 0;
                self.anim_timer = 0;
            }
            self.anim_timer += dt;
            if (self.anim_timer >= WALK_SPEED) {
                self.anim_timer = 0;
                self.frame_index = (self.frame_index + 1) % 9; // Idle has 9 frames
            }
        }

        self.last_moving = player.is_moving;
    }

    pub fn draw(self: *PlayerRenderer, player: *const Player, assets: PlayerAssets) void {
        // Draw shadow
        const shadow_dest = rl.Rectangle{
            .x = player.pos.x,
            .y = player.pos.y + 2, // Slight offset
            .width = 32,
            .height = 32,
        };
        rl.drawTexturePro(assets.shadow, rl.Rectangle{ .x = 0, .y = 0, .width = 32, .height = 32 }, shadow_dest, rl.Vector2{ .x = 0, .y = 0 }, 0, .white);

        // Select texture
        const texture = if (player.is_moving) switch (player.dir) {
            .Up => assets.walk_up,
            .Down => assets.walk_down,
            .Left => assets.walk_left,
            .Right => assets.walk_right,
        } else switch (player.dir) {
            .Up => assets.idle_up,
            .Down => assets.idle_down,
            .Left => assets.idle_left,
            .Right => assets.idle_right,
        };

        const src = rl.Rectangle{
            .x = FRAME_WIDTH * @as(f32, @floatFromInt(self.frame_index)),
            .y = 0,
            .width = FRAME_WIDTH,
            .height = FRAME_HEIGHT,
        };
        const dest = rl.Rectangle{
            .x = player.pos.x,
            .y = player.pos.y,
            .width = player.size.x,
            .height = player.size.y,
        };
        rl.drawTexturePro(texture, src, dest, rl.Vector2{ .x = 0, .y = 0 }, 0, .white);
        if (self.debug) {
            rl.drawRectangleLines(@intFromFloat(player.pos.x), @intFromFloat(player.pos.y), @intFromFloat(player.size.x), @intFromFloat(player.size.y), .red);
        }
    }
};
