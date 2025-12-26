const std = @import("std");
const rl = @import("raylib");
const layout = @import("../ui/layout.zig");
const widgets = @import("../ui/widgets.zig");
const HttpClient = @import("../client/http_client.zig").HttpClient;
const SceneAction = @import("../core/scene_action.zig").SceneAction;

pub const LoginScreen = struct {
    username_buf: [32:0]u8 = std.mem.zeroes([32:0]u8),
    username_len: usize = 0,
    password_buf: [32:0]u8 = std.mem.zeroes([32:0]u8),
    password_len: usize = 0,
    focused_field: enum { Username, Password } = .Username,
    width: f32 = 300.0,
    height: f32 = 250.0, // Increased height for password field
    http_client: *HttpClient,
    is_dev: bool = true,

    // Result of the login attempt
    pub const Result = enum {
        None,
        Login,
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
        const title = layout.takeTop(self.renderPanel(ctx), 20, 15);
        var cursor = title.rest;

        rl.drawText("Welcome!", @intFromFloat(title.head.x), @intFromFloat(title.head.y), 20, .dark_gray);

        self.drawUsernameInput(&cursor);
        self.drawPasswordInput(&cursor);

        // Login Button
        const spacer = layout.takeTop(cursor, 5, 0);
        cursor = spacer.rest;
        const btn_rect = widgets.Button(*LoginScreen){
            .onClick = LoginScreen.login,
            .onClickContext = self,
            .rect = layout.takeTop(cursor, 40, 0).head,
            .text = "LOGIN",
        };
        btn_rect.draw();
    }

    pub fn renderPanel(self: *LoginScreen, ctx: anytype) rl.Rectangle {
        const screen_width = ctx.screen_width;
        const screen_height = ctx.screen_height;

        const screen_rect = rl.Rectangle{
            .x = 0,
            .y = 0,
            .width = @floatFromInt(screen_width),
            .height = @floatFromInt(screen_height),
        };
        const panel_rect = layout.center(screen_rect, self.width, self.height);
        const panel = widgets.Panel{ .rect = panel_rect };

        panel.draw();
        return panel.contentRect();
    }

    fn drawUsernameInput(self: *LoginScreen, cursor: *rl.Rectangle) void {
        const label_slice = layout.takeTop(cursor.*, 10, 5);
        cursor.* = label_slice.rest;
        rl.drawText("Username", @intFromFloat(label_slice.head.x), @intFromFloat(label_slice.head.y), 10, .gray);

        const input_slice = layout.takeTop(cursor.*, 30, 15);
        cursor.* = input_slice.rest;
        const input_rect = input_slice.head;
        if (rl.isMouseButtonPressed(.left) and rl.checkCollisionPointRec(rl.getMousePosition(), input_rect)) {
            self.focused_field = .Username;
        }

        const username_input = widgets.Input{
            .rect = input_rect,
            .text = self.username_buf[0..self.username_len :0],
            .is_focused = self.focused_field == .Username,
        };
        username_input.draw();
    }

    fn drawPasswordInput(self: *LoginScreen, cursor: *rl.Rectangle) void {
        const label_slice = layout.takeTop(cursor.*, 10, 5);
        cursor.* = label_slice.rest;
        rl.drawText("Password", @intFromFloat(label_slice.head.x), @intFromFloat(label_slice.head.y), 10, rl.Color.gray);

        const input_slice = layout.takeTop(cursor.*, 30, 15);
        cursor.* = input_slice.rest;
        const input_rect = input_slice.head;
        if (rl.isMouseButtonPressed(.left) and rl.checkCollisionPointRec(rl.getMousePosition(), input_rect)) {
            self.focused_field = .Password;
        }

        const password_input = widgets.Input{
            .rect = input_rect,
            .text = self.password_buf[0..self.password_len :0],
            .is_focused = self.focused_field == .Password,
            .input_type = .Password,
        };
        password_input.draw();
    }

    fn handleInput(self: *LoginScreen) Result {
        // Tab Navigation
        if (rl.isKeyPressed(.tab)) {
            self.focused_field = if (self.focused_field == .Username) .Password else .Username;
        }

        switch (self.focused_field) {
            .Username => widgets.handleFieldInput(self.username_buf[0..], &self.username_len),
            .Password => widgets.handleFieldInput(self.password_buf[0..], &self.password_len),
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
        if (self.is_dev) {
            return;
        }
        std.debug.print("login: {s}\n", .{self.getUsername()});
        // We'll ignore the error for now or handle it better later
        _ = self.http_client.login(self.getUsername(), self.password_buf[0..self.password_len]) catch |err| {
            std.debug.print("Login failed: {}\n", .{err});
            return;
        };
    }
};
