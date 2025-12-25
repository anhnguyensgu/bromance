const std = @import("std");
const rl = @import("raylib");
const widgets = @import("../ui/widgets.zig");
const HttpClient = @import("../client/http_client.zig").HttpClient;

pub const LoginScreen = struct {
    username_buf: [32]u8 = std.mem.zeroes([32]u8),
    username_len: usize = 0,
    password_buf: [32]u8 = std.mem.zeroes([32]u8),
    password_len: usize = 0,
    focused_field: enum { Username, Password } = .Username,
    width: f32 = 300.0,
    height: f32 = 250.0, // Increased height for password field
    http_client: *HttpClient,

    // Result of the login attempt
    pub const Result = enum {
        None,
        Login,
    };

    pub const SceneAction = union(enum) {
        None,
        SwitchToWorld,
    };

    pub fn update(self: *LoginScreen, _: f32, _: anytype) SceneAction {
        const result = self.handleInput();
        if (result == .Login) {
            self.login();
            // Assuming successful login for now leads to World
            // In real app, we'd wait for login success callback
            return .SwitchToWorld;
        }
        return .None;
    }

    pub fn draw(self: *LoginScreen, ctx: anytype) void {
        const screen_width = ctx.screen_width;
        const screen_height = ctx.screen_height;

        const x = (@as(f32, @floatFromInt(screen_width)) - self.width) / 2.0;
        const y = (@as(f32, @floatFromInt(screen_height)) - self.height) / 2.0;

        // Draw background
        rl.drawRectangleRec(rl.Rectangle{ .x = x, .y = y, .width = self.width, .height = self.height }, .ray_white);
        rl.drawRectangleLinesEx(rl.Rectangle{ .x = x, .y = y, .width = self.width, .height = self.height }, 1, .light_gray);

        const content_x = x + 20;
        var current_y = y + 40;

        rl.drawText("Welcome!", @intFromFloat(content_x), @intFromFloat(current_y - 30), 20, .dark_gray);

        // --- Username ---
        rl.drawText("Username", @intFromFloat(content_x), @intFromFloat(current_y), 10, .gray);
        current_y += 15;

        const username_rect = rl.Rectangle{ .x = content_x, .y = current_y, .width = self.width - 40, .height = 30 };
        const username_input = widgets.Input{
            .rect = username_rect,
            .text = self.username_buf[0..self.username_len :0],
            .is_focused = self.focused_field == .Username,
        };
        username_input.draw();

        current_y += 40;

        // --- Password ---
        rl.drawText("Password", @intFromFloat(content_x), @intFromFloat(current_y), 10, rl.Color.gray);
        current_y += 15;

        const password_rect = rl.Rectangle{ .x = content_x, .y = current_y, .width = self.width - 40, .height = 30 };
        const password_input = widgets.Input{
            .rect = password_rect,
            .text = self.password_buf[0..self.password_len :0],
            .is_focused = self.focused_field == .Password,
            .input_type = .Password,
        };
        password_input.draw();

        current_y += 45;

        // Login Button
        const btn_rect = widgets.Button(*LoginScreen){ .onClick = LoginScreen.login, .onClickContext = self, .rect = rl.Rectangle{ .x = content_x, .y = current_y, .width = self.width - 40, .height = 40 }, .text = "LOGIN" };
        btn_rect.draw();
    }

    fn handleInput(self: *LoginScreen) Result {
        // Tab Navigation
        if (rl.isKeyPressed(.tab)) {
            self.focused_field = if (self.focused_field == .Username) .Password else .Username;
        }

        // Character Input
        while (true) {
            const char = rl.getCharPressed();
            if (char == 0) break;

            if (char >= 32 and char <= 125) {
                switch (self.focused_field) {
                    .Username => {
                        if (self.username_len < 31) {
                            self.username_buf[self.username_len] = @intCast(char);
                            self.username_len += 1;
                            self.username_buf[self.username_len] = 0;
                        }
                    },
                    .Password => {
                        if (self.password_len < 31) {
                            self.password_buf[self.password_len] = @intCast(char);
                            self.password_len += 1;
                            self.password_buf[self.password_len] = 0;
                        }
                    },
                }
            }
        }

        // Backspace
        if (rl.isKeyPressed(.backspace)) {
            switch (self.focused_field) {
                .Username => {
                    if (self.username_len > 0) {
                        self.username_len -= 1;
                        self.username_buf[self.username_len] = 0;
                    }
                },
                .Password => {
                    if (self.password_len > 0) {
                        self.password_len -= 1;
                        self.password_buf[self.password_len] = 0;
                    }
                },
            }
        }

        // Enter to login
        if (rl.isKeyPressed(.enter)) {
            if (self.username_len > 0) { //  and self.password_len > 0
                return .Login;
            }
        }

        return .None;
    }

    pub fn getUsername(self: *const LoginScreen) [:0]const u8 {
        return self.username_buf[0..self.username_len :0];
    }

    pub fn login(self: *LoginScreen) void {
        std.debug.print("login: {s}\n", .{self.getUsername()});
        // We'll ignore the error for now or handle it better later
        _ = self.http_client.login(self.getUsername(), self.password_buf[0..self.password_len]) catch |err| {
            std.debug.print("Login failed: {}\n", .{err});
            return;
        };
    }
};
