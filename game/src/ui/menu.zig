const rl = @import("raylib");
const shared = @import("../shared.zig");
const sheets = shared.sheets;
const MenuSprite = sheets.MenuSprites;
const MenuSpriteId = sheets.MenuSpriteId;

pub const MenuLayout = struct {
    spacing: f32 = 12.0,
    tile_size: f32 = 40.0,
    side_padding: f32 = 25.0,
    top_padding: f32 = 30.0,
    max_menu_width: f32 = 400.0,
};

pub const MenuItem = struct {
    label: [:0]const u8,
    action: *const fn () void,
    col_span: usize = 1,
    custom_draw: ?*const fn (item: *const MenuItem, rect: rl.Rectangle, active: bool, hovered: bool) void = null,
    data: ?*const anyopaque = null,

    pub fn draw(self: MenuItem, rect: rl.Rectangle, active: bool, hovered: bool) void {
        //render sprite Springtiles
        if (self.custom_draw) |drawFn| {
            drawFn(&self, rect, active, hovered);
        } else {
            if (active or hovered) {
                const overlay = rl.Color{ .r = 50, .g = 56, .b = 72, .a = 150 };
                rl.drawRectangleRec(rect, overlay);
            }

            const text_y: i32 = @intFromFloat(rect.y + (rect.height - 18) / 2);
            rl.drawText(self.label, @intFromFloat(rect.x + 12), text_y, 18, .ray_white);
        }
    }
};

// Simple menu sprite bundle so loading/unloading stays with the menu module.
pub const Menu = struct {
    const Self = @This();
    sprite_set: shared.sheets.SpriteSet,
    layout: MenuLayout,
    is_open: bool = false,

    pub fn init(texture: rl.Texture2D, layout: MenuLayout) Menu {
        return .{
            .sprite_set = shared.sheets.SpriteSet.MenuSheet(texture),
            .layout = layout,
        };
    }

    pub fn toggle(self: *Self) void {
        self.is_open = !self.is_open;
    }

    pub fn deinit(self: *Menu) void {
        _ = self;
        // Texture is owned by client, nothing to clean up here for now.
    }

    pub fn draw(self: *Self, pos_x: f32, menu_items: []const MenuItem, active_item: ?*?usize) void {
        const spacing = self.layout.spacing;
        const tile_size = self.layout.tile_size;
        const side_padding = self.layout.side_padding;
        const top_padding = self.layout.top_padding;
        const max_menu_width = self.layout.max_menu_width;

        // Calculate columns dynamically based on item count
        const available_max_width = max_menu_width - (2.0 * side_padding);
        const max_cols: usize = @intFromFloat(@divFloor(available_max_width + spacing, tile_size + spacing));

        var cols = menu_items.len;
        if (cols > max_cols) cols = max_cols;
        if (cols < 1) cols = 1;

        const menu_width: f32 = (2.0 * side_padding) + (@as(f32, @floatFromInt(cols)) * (tile_size + spacing)) - spacing;
        const ratio = menu_width / 80.0;

        // First pass: Calculate total height needed
        var current_col: usize = 0;
        var current_row: usize = 0;
        for (menu_items) |item| {
            var span = item.col_span;
            if (span > max_cols) span = max_cols;

            // If item doesn't fit in current row, wrap to next line
            if (current_col + span > max_cols) {
                current_col = 0;
                current_row += 1;
            }

            // Advance cursor
            current_col += span;
            if (current_col >= max_cols) {
                current_col = 0;
                current_row += 1;
            }
        }
        // If we ended exactly at start of new row, rows count is explicitly correct (due to final += 1),
        // but if we ended mid-row, we are still IN that row, so count is row + 1.
        // BUT my logic above increments current_row PREEMPTIVELY if we wrap.
        // Let's refine the loop below to be identical for drawing.

        const total_rows = if (current_col == 0 and current_row > 0) current_row else current_row + 1;
        const total_height = top_padding + (@as(f32, @floatFromInt(total_rows)) * (tile_size + spacing)) + spacing;
        const total_height_f = @max(total_height, 100 * ratio);

        if (rl.isKeyPressed(.b)) {
            self.toggle();
        }
        if (!self.is_open) return;
        switch (self.sprite_set) {
            .Menu => |sheet| {
                const rect = sheet.get(.Background);
                // Adjust background height to fit content
                sheets.drawSpriteTo(sheet.texture2D, rect, .{ .x = pos_x, .y = 0, .width = menu_width, .height = total_height_f });
            },
            else => {},
        }

        const mouse = rl.getMousePosition();
        const clicked = rl.isMouseButtonPressed(rl.MouseButton.left);

        current_col = 0;
        current_row = 0;

        for (menu_items, 0..) |item, idx| {
            var span = item.col_span;
            if (span > max_cols) span = max_cols;

            // Wrap if needed
            if (current_col + span > max_cols) {
                current_col = 0;
                current_row += 1;
            }

            const x = pos_x + side_padding + (@as(f32, @floatFromInt(current_col)) * (tile_size + spacing));
            const y = top_padding + (@as(f32, @floatFromInt(current_row)) * (tile_size + spacing));

            // Calculate width based on span
            // width = (tile_size * span) + (spacing * (span - 1))
            const item_width = (tile_size * @as(f32, @floatFromInt(span))) + (spacing * @as(f32, @floatFromInt(span - 1)));

            const padding = 3;
            const rect = rl.Rectangle{ .x = x - padding, .y = y - padding, .width = item_width + padding * 2, .height = tile_size + padding * 2 };
            rl.drawRectangleLinesEx(rect, 2.0, .white);

            // Advance cursor for next item
            current_col += span;
            if (current_col >= max_cols) {
                current_col = 0;
                current_row += 1;
            }

            // Draw semi-transparent overlay for hover/active states
            const hovered = rl.checkCollisionPointRec(mouse, rect);

            var is_active = false;
            if (active_item) |ptr| {
                if (ptr.*) |current| {
                    is_active = (current == idx);
                }
            }

            item.draw(rect, is_active, hovered);

            if (hovered and clicked) {
                if (active_item) |ptr| {
                    // Toggle behavior: clicking same item deselects it
                    if (ptr.*) |current| {
                        if (current == idx) {
                            ptr.* = null;
                        } else {
                            ptr.* = idx;
                            item.action();
                        }
                    } else {
                        ptr.* = idx;
                        item.action();
                    }
                }
            }
        }

        rl.drawLine(@intFromFloat(pos_x), @intFromFloat(total_height_f), @intFromFloat(pos_x + menu_width), @intFromFloat(total_height_f), .red);
    }
};
