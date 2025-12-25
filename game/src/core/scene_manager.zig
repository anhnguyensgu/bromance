const std = @import("std");
const context = @import("context.zig");
const LoginScreen = @import("../screens/login.zig").LoginScreen;
const WorldScreen = @import("../screens/world.zig").WorldScreen;
const GameOverScreen = @import("../screens/game_over.zig").GameOverScreen;

pub const SceneAction = union(enum) {
    None,
    SwitchToLogin,
    SwitchToWorld,
    SwitchToGameOver,
    Quit,
};

pub const Scene = union(enum) {
    Login: *LoginScreen,
    World: *WorldScreen,
    GameOver: *GameOverScreen,

    pub fn update(self: Scene, dt: f32, ctx: *context.GameContext) !SceneAction {
        switch (self) {
            .Login => |s| {
                const action = s.update(dt, ctx);
                switch (action) {
                    .None => return .None,
                    .SwitchToWorld => return .SwitchToWorld,
                }
            },
            .World => |s| {
                const action = s.update(dt, ctx);
                switch (action) {
                    .None => return .None,
                    .SwitchToLogin => return .SwitchToLogin,
                    .SwitchToGameOver => return .SwitchToGameOver,
                }
            },
            .GameOver => |s| {
                const action = try s.update(dt, ctx);
                switch (action) {
                    .None => return .None,
                    .SwitchToLogin => return .SwitchToLogin,
                }
            },
        }
    }

    pub fn draw(self: Scene, ctx: *context.GameContext) void {
        switch (self) {
            .Login => |s| s.draw(ctx),
            .World => |s| s.draw(ctx),
            .GameOver => |s| s.draw(ctx),
        }
    }

    pub fn deinit(self: Scene, allocator: std.mem.Allocator) void {
        switch (self) {
            .Login => |s| {
                // LoginScreen doesn't have deinit currently?
                // It has http_client which is owned by context.
                allocator.destroy(s);
            },
            .World => |s| {
                s.deinit();
                allocator.destroy(s);
            },
            .GameOver => |s| {
                s.deinit(allocator);
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
            .SwitchToGameOver => try self.changeScene(.GameOver, ctx),
            .Quit => {
                // Handle quit? Maybe return an error or status
            },
        }
    }

    pub fn draw(self: *SceneManager, ctx: *context.GameContext) void {
        self.current_scene.draw(ctx);
    }

    fn changeScene(self: *SceneManager, to: enum { Login, World, GameOver }, ctx: *context.GameContext) !void {
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
                self.current_scene = .{ .World = s };
            },
            .GameOver => {
                const s = try self.allocator.create(GameOverScreen);
                s.* = GameOverScreen.init(self.allocator);
                self.current_scene = .{ .GameOver = s };
            },
        }
    }
};
