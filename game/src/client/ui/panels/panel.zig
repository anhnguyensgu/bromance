pub const PanelSettings = struct {
    padding: u32 = 8,
    background: []const u8 = "rgba(0, 0, 0, 0.7)",
    border_color: []const u8 = "rgba(255, 255, 255, 0.5)",
    border_width: u32 = 2,
};

pub const Panel = struct {
    title: []const u8,
    settings: PanelSettings,

    pub fn init(title: []const u8, settings: PanelSettings) Panel {
        return .{ .title = title, .settings = settings };
    }
};
