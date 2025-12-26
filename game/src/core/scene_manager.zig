const std = @import("std");
const context = @import("context.zig");
const scene_action = @import("scene_action.zig");
const LoginScreen = @import("../screens/login.zig").LoginScreen;
const WorldScreen = @import("../screens/world.zig").WorldScreen;

pub const SceneAction = scene_action.SceneAction;

pub const Scene = union(enum) {
    Login: *LoginScreen,
    Gameplay: *WorldScreen,

    pub fn update(self: Scene, dt: f32, ctx: *context.GameContext) !SceneAction {
        return switch (self) {
            .Login => |s| s.update(dt, ctx),
            .Gameplay => |s| s.update(dt, ctx),
        };
    }

    pub fn draw(self: Scene, ctx: *context.GameContext) void {
        switch (self) {
            .Login => |s| s.draw(ctx),
            .Gameplay => |s| s.draw(ctx),
        }
    }

    pub fn deinit(self: Scene, allocator: std.mem.Allocator) void {
        switch (self) {
            .Login => |s| {
                // LoginScreen doesn't have deinit currently?
                // It has http_client which is owned by context.
                allocator.destroy(s);
            },
            .Gameplay => |s| {
                s.deinit();
                allocator.destroy(s);
            },
        }
    }
};

pub const SceneManager = struct {
    current_scene: Scene,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, start_scene: Scene) SceneManager {
        return SceneManager{
            .current_scene = start_scene,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *SceneManager) void {
        self.current_scene.deinit(self.allocator);
    }

    pub fn update(self: *SceneManager, dt: f32, ctx: *context.GameContext) !void {
        const action = try self.current_scene.update(dt, ctx);

        switch (action) {
            .None => {},
            .SwitchToLogin => try self.changeScene(.Login, ctx),
            .SwitchToWorld => try self.changeScene(.World, ctx),
            .Quit => {
                // Handle quit? Maybe return an error or status
            },
        }
    }

    pub fn draw(self: *SceneManager, ctx: *context.GameContext) void {
        self.current_scene.draw(ctx);
    }

    fn changeScene(self: *SceneManager, to: enum { Login, World }, ctx: *context.GameContext) !void {
        // Deinit current
        self.current_scene.deinit(self.allocator);

        // Init new
        switch (to) {
            .Login => {
                const s = try self.allocator.create(LoginScreen);
                s.* = LoginScreen{ .http_client = ctx.http_client }; // Re-init login screen
                self.current_scene = .{ .Login = s };
            },
            .World => {
                const s = try self.allocator.create(WorldScreen);
                s.* = try WorldScreen.init(ctx);
                try s.start();
                self.current_scene = .{ .Gameplay = s };
            },
        }
    }
};
