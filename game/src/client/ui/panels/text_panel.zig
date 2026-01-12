const Renderer = @import("../../renderer.zig").Renderer;
const scenes = @import("../../../scenes/mod.zig");
const UIState = scenes.UIState;

pub const ValueFn = fn (*const UIState) []const u8;

pub const TextPanel = struct {
    label: []const u8,
    value: ValueFn,

    pub fn init(label: []const u8, value: ValueFn) TextPanel {
        return .{ .label = label, .value = value };
    }

    pub fn render(
        self: *const TextPanel,
        renderer: *Renderer,
        state: *const UIState,
    ) void {
        renderer.drawHudLine(self.label, "{s}", .{self.value(state)});
    }
};
