const std = @import("std");
const rl = @import("raylib");

/// Character animation states (type-safe)
pub const CharacterAnim = enum {
    idle_up,
    idle_down,
    idle_left,
    idle_right,
    walk_up,
    walk_down,
    walk_left,
    walk_right,
    shadow,
};

/// Character assets with type-safe animation access
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

    const Self = @This();

    pub fn init() !Self {
        // Load all character textures
        const idle_up = try rl.loadTexture("assets/maincharacter/maincidleback.png");
        errdefer rl.unloadTexture(idle_up);

        const idle_down = try rl.loadTexture("assets/maincharacter/maincidlefront.png");
        errdefer rl.unloadTexture(idle_down);

        const idle_left = try rl.loadTexture("assets/maincharacter/maincidleleft.png");
        errdefer rl.unloadTexture(idle_left);

        const idle_right = try rl.loadTexture("assets/maincharacter/maincidleright.png");
        errdefer rl.unloadTexture(idle_right);

        const walk_up = try rl.loadTexture("assets/maincharacter/maincwalkback.png");
        errdefer rl.unloadTexture(walk_up);

        const walk_down = try rl.loadTexture("assets/maincharacter/maincwalkfront.png");
        errdefer rl.unloadTexture(walk_down);

        const walk_left = try rl.loadTexture("assets/maincharacter/maincwalkleft.png");
        errdefer rl.unloadTexture(walk_left);

        const walk_right = try rl.loadTexture("assets/maincharacter/maincwalkright.png");
        errdefer rl.unloadTexture(walk_right);

        const shadow = try rl.loadTexture("assets/maincharacter/maincshadow.png");
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

    pub fn deinit(self: *Self) void {
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

    /// Get a texture by animation type (type-safe accessor)
    pub fn get(self: Self, anim: CharacterAnim) rl.Texture2D {
        return switch (anim) {
            .idle_up => self.idle_up,
            .idle_down => self.idle_down,
            .idle_left => self.idle_left,
            .idle_right => self.idle_right,
            .walk_up => self.walk_up,
            .walk_down => self.walk_down,
            .walk_left => self.walk_left,
            .walk_right => self.walk_right,
            .shadow => self.shadow,
        };
    }

    /// Draw a character animation frame
    pub fn draw(self: Self, anim: CharacterAnim, frame_index: usize, x: f32, y: f32, scale: f32) void {
        const texture = self.get(anim);
        const frame_width: f32 = 32.0; // Character frame width
        const frame_height: f32 = 32.0; // Character frame height

        const src = rl.Rectangle{
            .x = @as(f32, @floatFromInt(frame_index)) * frame_width,
            .y = 0,
            .width = frame_width,
            .height = frame_height,
        };

        const dest = rl.Rectangle{
            .x = x,
            .y = y,
            .width = frame_width * scale,
            .height = frame_height * scale,
        };

        rl.drawTexturePro(texture, src, dest, .{ .x = 0, .y = 0 }, 0, .white);
    }
};
