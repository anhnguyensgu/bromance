const Renderer = @import("../renderer.zig").Renderer;
const GameState = @import("../state.zig").GameState;

pub const Hud = struct {
    pub fn init() Hud {
        return .{};
    }

    pub fn render(
        self: *const Hud,
        renderer: *Renderer,
        state: *const GameState,
    ) void {
        _ = self;

        renderer.drawBanner("Heads-Up Display");
        renderer.drawHudLine("Day", "{d}", .{state.dayNumber()});
        renderer.drawHudLine("Cycle", "{s}", .{state.cycleLabel()});
        renderer.drawHudLine("Hearts", "{d}/{d}", .{ state.hearts(), state.maxHearts() });
        const stamina_percent =
            @as(u8, @intFromFloat(@round(state.staminaPercent() * 100.0)));

        renderer.drawHudLine(
            "Stamina",
            "{d}%",
            .{ stamina_percent },
        );
        renderer.drawHudLine("Coins", "{d}", .{state.coins()});
    }
};
