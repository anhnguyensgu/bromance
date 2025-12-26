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

pub const Panel = struct {
    rect: rl.Rectangle,
    padding: f32 = 20.0,
    background: rl.Color = rl.Color.ray_white,
    border: rl.Color = rl.Color.light_gray,
    border_width: f32 = 1.0,

    pub fn draw(self: Panel) void {
        rl.drawRectangleRec(self.rect, self.background);
        rl.drawRectangleLinesEx(self.rect, self.border_width, self.border);
    }

    pub fn contentRect(self: Panel) rl.Rectangle {
        return rl.Rectangle{
            .x = self.rect.x + self.padding,
            .y = self.rect.y + self.padding,
            .width = self.rect.width - (self.padding * 2.0),
            .height = self.rect.height - (self.padding * 2.0),
        };
    }
};

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
        rl.drawRectangleLinesEx(self.rect, 1, if (self.is_focused) .sky_blue else .dark_gray);

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

pub fn handleFieldInput(buf: []u8, len: *usize) void {
    const v_pressed = rl.isKeyPressed(.v);
    const cmd_down = rl.isKeyDown(.left_super) or rl.isKeyDown(.right_super);
    const cmd_paste = v_pressed and cmd_down;

    if (cmd_paste) {
        pasteClipboardText(buf, len);
    }

    if (!cmd_paste) {
        while (true) {
            const char = rl.getCharPressed();
            if (char == 0) break;

            if (char >= 32 and char <= 125) {
                if (len.* < buf.len - 1) {
                    buf[len.*] = @intCast(char);
                    len.* += 1;
                    buf[len.*] = 0;
                }
            }
        }
    }

    if (rl.isKeyPressed(.backspace)) {
        if (len.* > 0) {
            len.* -= 1;
            buf[len.*] = 0;
        }
    }
}

fn pasteClipboardText(buf: []u8, len: *usize) void {
    if (buf.len == 0) return;

    const clip_ptr = rl.cdef.GetClipboardText();
    if (clip_ptr == null) return;

    const clip = std.mem.span(@as([*:0]const u8, @ptrCast(clip_ptr)));
    if (clip.len == 0) return;

    const max_len = buf.len - 1;
    var i: usize = 0;
    while (i < clip.len and len.* < max_len) : (i += 1) {
        const c = clip[i];
        if (c < 32) continue;
        buf[len.*] = c;
        len.* += 1;
    }

    buf[len.*] = 0;
}
