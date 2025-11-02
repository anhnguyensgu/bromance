const std = @import("std");
const GameState = @import("state.zig").GameState;
const Renderer = @import("renderer.zig").Renderer;
const InventoryBarUI = @import("ui/inventory_bar.zig").InventoryBarUI;
const Hud = @import("ui/hud.zig").Hud;

pub const GameClient = struct {
    allocator: std.mem.Allocator,
    state: GameState,
    renderer: Renderer,
    inventory_bar: InventoryBarUI,
    hud: Hud,

    pub fn init(allocator: std.mem.Allocator) !GameClient {
        return .{
            .allocator = allocator,
            .state = GameState.sample(),
            .renderer = Renderer.init(),
            .inventory_bar = InventoryBarUI.init(),
            .hud = Hud.init(),
        };
    }

    pub fn bootstrap(self: *GameClient) void {
        std.debug.print("Bootstrapping Zig client...\n", .{});
        self.renderer.drawGameStateSummary(&self.state);
    }

    pub fn renderFrame(self: *GameClient) void {
        self.renderer.beginFrame();
        self.inventory_bar.render(&self.renderer, &self.state);
        self.hud.render(&self.renderer, &self.state);
        self.renderer.endFrame();
    }

    pub fn deinit(self: *GameClient) void {
        _ = self;
    }
};
