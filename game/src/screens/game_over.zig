const std = @import("std");
const rl = @import("raylib");
const context = @import("../core/context.zig");

pub const GameOverScreen = struct {
    pub fn init(_: std.mem.Allocator) GameOverScreen {
        return GameOverScreen{};
    }

    pub fn update(self: *GameOverScreen, dt: f32, ctx: *context.GameContext) !enum { None, SwitchToLogin } {
        _ = self;
        _ = dt;
        _ = ctx;
        if (rl.isKeyPressed(.enter)) {
            return .SwitchToLogin;
        }
        return .None;
    }

    pub fn draw(self: *GameOverScreen, ctx: *context.GameContext) void {
        _ = self;
        const text = "GAME OVER";
        const font_size = 40;
        const width = rl.measureText(text, font_size);
        const x = @divTrunc(ctx.screen_width - width, 2);
        const y = @divTrunc(ctx.screen_height - font_size, 2);

        rl.drawText(text, x, y, font_size, rl.Color.red);
        rl.drawText("Press ENTER to return to menu", x - 50, y + 60, 20, rl.Color.dark_gray);
    }

    pub fn deinit(self: *GameOverScreen, allocator: std.mem.Allocator) void {
        _ = self;
        _ = allocator;
    }
};
