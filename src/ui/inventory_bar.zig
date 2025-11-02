const Renderer = @import("../renderer.zig").Renderer;
const GameState = @import("../state.zig").GameState;

pub const InventoryBarUI = struct {
    const HotbarSettings = struct {
        slot_size: u32,
        slots_gap: u32,
        container_padding: u32,
    };

    settings: HotbarSettings,

    pub fn init() InventoryBarUI {
        return .{
            .settings = .{
                .slot_size = 96,
                .slots_gap = 8,
                .container_padding = 12,
            },
        };
    }

    pub fn render(
        self: *const InventoryBarUI,
        renderer: *Renderer,
        state: *const GameState,
    ) void {
        _ = self;
        renderer.drawBanner("Inventory Hotbar");
        renderer.drawInventorySummary(state.inventoryCount(), state.inventoryCapacity());

        for (state.inventory(), 0..) |slot, idx| {
            renderer.drawInventorySlot(idx, slot);
        }
    }
};
