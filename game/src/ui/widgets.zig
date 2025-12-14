const std = @import("std");
const rl = @import("raylib");

pub fn Button(comptime Context: type) type {
    return struct {
        const Self = @This();

        rect: rl.Rectangle,
        text: [:0]const u8,
        onClick: ?*const fn (context: Context) void = null,
        onClickContext: Context,

        pub fn draw(self: Self) void {
            const mouse_pos = rl.getMousePosition();
            const hovered = rl.checkCollisionPointRec(mouse_pos, self.rect);
            const clicked = rl.isMouseButtonReleased(.left);

            if (hovered) {
                rl.drawRectangleRec(self.rect, rl.Color.sky_blue);
                if (clicked) {
                    if (self.onClick) |handler| {
                        handler(self.onClickContext);
                    }
                }
            } else {
                rl.drawRectangleRec(self.rect, rl.Color.dark_blue);
            }

            const text_width = rl.measureText(self.text, 20);
            const text_x = self.rect.x + (self.rect.width - @as(f32, @floatFromInt(text_width))) / 2.0;
            const text_y = self.rect.y + (self.rect.height - 20) / 2.0; // Vertically center 20px text

            rl.drawText(self.text, @intFromFloat(text_x), @intFromFloat(text_y), 20, rl.Color.white);
        }
    };
}

pub const Input = struct {
    pub const Type = enum {
        Text,
        Password,
    };

    rect: rl.Rectangle,
    text: [:0]const u8,
    is_focused: bool = false,
    input_type: Type = .Text,

    pub fn draw(self: Input) void {
        rl.drawRectangleRec(self.rect, rl.Color.light_gray);
        rl.drawRectangleLinesEx(self.rect, 1, if (self.is_focused) rl.Color.sky_blue else rl.Color.dark_gray);

        switch (self.input_type) {
            .Password => {
                var masked_buf: [64]u8 = undefined;
                const len = @min(self.text.len, masked_buf.len - 1);
                @memset(masked_buf[0..len], '*');
                masked_buf[len] = 0;
                const masked_slice = masked_buf[0..len :0];

                rl.drawText(masked_slice, @intFromFloat(self.rect.x + 5), @intFromFloat(self.rect.y + 8), 10, rl.Color.black);

                if (self.is_focused) {
                    if (@mod(@divFloor(rl.getTime() * 1000, 500), 2) == 0) {
                        const text_width = rl.measureText(masked_slice, 10);
                        rl.drawRectangle(@intFromFloat(self.rect.x + 5 + @as(f32, @floatFromInt(text_width))), @intFromFloat(self.rect.y + 5), 2, 20, rl.Color.black);
                    }
                }
            },
            .Text => {
                rl.drawText(self.text, @intFromFloat(self.rect.x + 5), @intFromFloat(self.rect.y + 8), 10, rl.Color.black);

                if (self.is_focused) {
                    if (@mod(@divFloor(rl.getTime() * 1000, 500), 2) == 0) {
                        const text_width = rl.measureText(self.text, 10);
                        rl.drawRectangle(@intFromFloat(self.rect.x + 5 + @as(f32, @floatFromInt(text_width))), @intFromFloat(self.rect.y + 5), 2, 20, rl.Color.black);
                    }
                }
            },
        }
    }
};
