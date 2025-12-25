const rl = @import("raylib");
const MoveDirection = @import("../movement/command.zig").MoveDirection;

pub const CharacterAssets = struct {
    idle_up: rl.Texture2D,
    idle_down: rl.Texture2D,
    idle_left: rl.Texture2D,
    idle_right: rl.Texture2D,
    walk_up: rl.Texture2D,
    walk_down: rl.Texture2D,
    walk_left: rl.Texture2D,
    walk_right: rl.Texture2D,
    shadow: rl.Texture2D,

    pub fn loadMainCharacter() !CharacterAssets {
        const idle_up = try rl.loadTexture("assets/MainCharacter/MainC_Idle_Back.PNG");
        errdefer rl.unloadTexture(idle_up);

        const idle_down = try rl.loadTexture("assets/MainCharacter/MainC_Idle_Front.PNG");
        errdefer rl.unloadTexture(idle_down);

        const idle_left = try rl.loadTexture("assets/MainCharacter/MainC_Idle_Left.PNG");
        errdefer rl.unloadTexture(idle_left);

        const idle_right = try rl.loadTexture("assets/MainCharacter/MainC_Idle_Right.PNG");
        errdefer rl.unloadTexture(idle_right);

        const walk_up = try rl.loadTexture("assets/MainCharacter/MainC_Walk_Back.PNG");
        errdefer rl.unloadTexture(walk_up);

        const walk_down = try rl.loadTexture("assets/MainCharacter/MainC_Walk_Front.PNG");
        errdefer rl.unloadTexture(walk_down);

        const walk_left = try rl.loadTexture("assets/MainCharacter/MainC_Walk_Left.PNG");
        errdefer rl.unloadTexture(walk_left);

        const walk_right = try rl.loadTexture("assets/MainCharacter/MainC_Walk_Right.PNG");
        errdefer rl.unloadTexture(walk_right);

        const shadow = try rl.loadTexture("assets/MainCharacter/MainC_Shadow.png");
        errdefer rl.unloadTexture(shadow);

        return .{
            .idle_up = idle_up,
            .idle_down = idle_down,
            .idle_left = idle_left,
            .idle_right = idle_right,
            .walk_up = walk_up,
            .walk_down = walk_down,
            .walk_left = walk_left,
            .walk_right = walk_right,
            .shadow = shadow,
        };
    }

    pub fn deinit(self: CharacterAssets) void {
        rl.unloadTexture(self.idle_up);
        rl.unloadTexture(self.idle_down);
        rl.unloadTexture(self.idle_left);
        rl.unloadTexture(self.idle_right);
        rl.unloadTexture(self.walk_up);
        rl.unloadTexture(self.walk_down);
        rl.unloadTexture(self.walk_left);
        rl.unloadTexture(self.walk_right);
        rl.unloadTexture(self.shadow);
    }
};

pub const Character = struct {
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
