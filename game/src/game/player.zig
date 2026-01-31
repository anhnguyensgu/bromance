// ==================================================================================
// Player Entity State
// ==================================================================================
// This module defines the player character entity.
// RESPONSIBILITIES:
// - Player position and animation state
// - Visual rendering of the player character
// - Animation frame updates based on movement
//
// Separation from other states:
// - Character (this file): Player entity position and animation
// - ClientGameState (client/game_state.zig): Network sync and interpolation
// - UIState (screens/ui_state.zig): HUD display values (stamina, hearts)
// - World (core/world.zig): World collision and terrain
// ==================================================================================

const rl = @import("raylib");
const MoveDirection = @import("../movement/command.zig").MoveDirection;
const CharacterAssets = @import("../assets/mod.zig").CharacterAssets;

pub const Character = struct {
    // Player entity - position, animation, rendering
    pos: rl.Vector2,
    size: rl.Vector2,
    dir: MoveDirection,
    is_moving: bool,
    frame_index: usize,
    anim_timer: f32,
    debug: bool,

    const WALK_SPEED: f32 = 0.1;
    const FRAME_WIDTH: f32 = 32;
    const FRAME_HEIGHT: f32 = 32;
    const Self = @This();

    pub fn init(pos: rl.Vector2, size: rl.Vector2) Self {
        return .{
            .pos = pos,
            .size = size,
            .is_moving = false,
            .dir = .Down,
            .frame_index = 0,
            .anim_timer = 0,
            .debug = true,
        };
    }

    pub fn update(self: *Self, dt: f32, dir: MoveDirection, is_moving: bool) void {
        const was_moving = self.is_moving;
        self.is_moving = is_moving;

        if (self.is_moving) {
            self.dir = dir;
            self.anim_timer += dt;
            if (self.anim_timer >= WALK_SPEED) {
                self.anim_timer = 0;
                self.frame_index = (self.frame_index + 1) % 4; // Walk has 4 frames
            }
        } else {
            // Idle animation
            if (was_moving) {
                self.frame_index = 0;
                self.anim_timer = 0;
            }
            self.anim_timer += dt;
            if (self.anim_timer >= WALK_SPEED) {
                self.anim_timer = 0;
                self.frame_index = (self.frame_index + 1) % 9; // Idle has 9 frames
            }
        }
    }

    pub fn draw(self: *Self, assets: CharacterAssets) !void {
        // Draw shadow
        const shadow_dest = rl.Rectangle{
            .x = self.pos.x,
            .y = self.pos.y + 2, // Slight offset
            .width = 32,
            .height = 32,
        };
        rl.drawTexturePro(assets.shadow, rl.Rectangle{ .x = 0, .y = 0, .width = 32, .height = 32 }, shadow_dest, rl.Vector2{ .x = 0, .y = 0 }, 0, .white);

        // Select texture
        const texture = if (self.is_moving) switch (self.dir) {
            .Up => assets.walk_up,
            .Down => assets.walk_down,
            .Left => assets.walk_left,
            .Right => assets.walk_right,
        } else switch (self.dir) {
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
            .x = self.pos.x,
            .y = self.pos.y,
            .width = self.size.x,
            .height = self.size.y,
        };
        rl.drawTexturePro(texture, src, dest, rl.Vector2{ .x = 0, .y = 0 }, 0, .white);
        if (self.debug) {
            rl.drawRectangleLines(@intFromFloat(self.pos.x), @intFromFloat(self.pos.y), @intFromFloat(self.size.x), @intFromFloat(self.size.y), .red);
        }
    }
};
