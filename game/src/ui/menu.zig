const rl = @import("raylib");

pub const MenuItem = struct {
    label: [:0]const u8,
    action: fn () void,
};
pub const SpriteType = enum { Main, Button };

pub const SpriteSelector = struct {
    pub fn getRect(sprite_type: SpriteType) rl.Rectangle {
        return switch (sprite_type) {
            .Main => rl.Rectangle{ .x = 95, .y = 0, .width = 120, .height = 32 },
            .Button => rl.Rectangle{ .x = 64, .y = 0, .width = 64, .height = 64 },
        };
    }
};

// Simple menu sprite bundle so loading/unloading stays with the menu module.
pub const Menu = struct {
    texture: rl.Texture2D,
    height: i32,

    pub fn load() !Menu {
        const tex = try rl.loadTexture("assets/Farm RPG FREE 16x16 - Tiny Asset Pack/Menu/Main_menu.png");
        return .{
            .texture = tex,
            .height = 48,
        };
    }

    pub fn deinit(self: *Menu) void {
        rl.unloadTexture(self.texture);
    }

    pub fn draw(self: *const Menu, screen_width: i32, comptime menu_items: []const MenuItem, active_item: *?usize) void {
        drawMenu(self.*, screen_width, menu_items, active_item);
    }
};

pub fn drawMenu(menu: Menu, screen_width: i32, comptime menu_items: []const MenuItem, active_item: *?usize) void {
    _ = active_item;
    const item_height = menu.height;
    // const item_height_f = @as(f32, @floatFromInt(item_height));
    const menu_width: f32 = 150;

    const total_height = item_height * @as(i32, menu_items.len);
    const total_height_f = @as(f32, @floatFromInt(total_height));

    const size = SpriteSelector.getRect(.Main);

    const src = rl.Rectangle{
        .x = size.x,
        .y = size.y,
        .width = 79,
        .height = size.height,
    };
    const dest = rl.Rectangle{
        .x = 0,
        .y = 0,
        .width = menu_width,
        .height = total_height_f,
    };
    rl.drawTexturePro(menu.texture, src, dest, rl.Vector2{ .x = 0, .y = 0 }, 0, .white);

    // var y: f32 = 0;
    // const padding: f32 = 12;

    // const mouse = rl.getMousePosition();
    // const clicked = rl.isMouseButtonPressed(rl.MouseButton.left);

    // inline for (menu_items, 0..) |item, idx| {
    //     const rect = rl.Rectangle{ .x = 0, .y = y, .width = menu_width, .height = item_height_f };

    //     // Draw semi-transparent overlay for hover/active states
    //     const hovered = rl.checkCollisionPointRec(mouse, rect);
    //     const is_active = if (active_item.*) |current| current == idx else false;
    //     if (hovered or is_active) {
    //         const overlay = rl.Color{ .r = 50, .g = 56, .b = 72, .a = 150 };
    //         rl.drawRectangleRec(rect, overlay);
    //     }

    //     const text_y: i32 = @intFromFloat(y + (item_height_f - 18) / 2);
    //     rl.drawText(item.label, @intFromFloat(padding), text_y, 18, .ray_white);

    //     if (hovered and clicked) {
    //         active_item.* = idx;
    //         item.action();
    //     }

    //     y += item_height_f;
    // }

    rl.drawLine(0, total_height, @intFromFloat(menu_width), total_height, .gray);
    _ = screen_width;
}
