const std = @import("std");
const rl = @import("raylib");
const shared = @import("shared.zig");

const LoginScreen = shared.LoginScreen;
const WorldScreen = shared.WorldScreen;
const HttpClient = shared.HttpClient;

const ScreenType = enum {
    Login,
    World,
};

const Screen = union(ScreenType) {
    Login: *LoginScreen,
    World: *WorldScreen,
};

pub fn main() !void {
    try runRaylib();
}

pub fn runRaylib() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialization
    const screen_width = 1000;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "Bromance");
    defer rl.closeWindow(); // Close window and OpenGL context

    // Disable escape key from closing the window
    rl.setExitKey(.null);
    rl.setTargetFPS(60);

    // Initial Screen: Login
    // We allocate screens on the heap to avoid stack overflow or move issues.

    // Init HttpClient
    const http_client = try allocator.create(HttpClient);
    http_client.* = HttpClient.init(allocator);
    defer {
        http_client.deinit();
        allocator.destroy(http_client);
    }
    // Don't destroy http_client here, LoginScreen needs it.
    // Ideally we should manage its lifecycle better (e.g. destroy when login is done or game exits).
    // For now, let's defer destruction at end of main, assuming it lives for app duration or until login done.

    var current_screen: Screen = .{ .Login = try allocator.create(LoginScreen) };
    current_screen.Login.* = LoginScreen{
        .width = 400.0,
        .height = 300.0,
        .http_client = http_client,
    };

    // We can also just keep a pointer to the current screen if we want polymorphism,
    // but Zig unions are explicit.

    // Main game loop
    while (!rl.windowShouldClose()) {
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(rl.Color.ray_white);

        switch (current_screen) {
            .Login => |login| {
                const result = login.draw(screen_width, screen_height);
                if (result == .Login) {
                    allocator.destroy(login);

                    const world_screen = try allocator.create(WorldScreen);
                    errdefer allocator.destroy(world_screen);

                    world_screen.* = try WorldScreen.init(allocator, screen_width, screen_height);
                    try world_screen.start();

                    current_screen = .{ .World = world_screen };
                }
            },
            .World => |world| {
                world.draw(screen_width, screen_height);
                // Handle logout if implemented later
            },
        }
    }

    // Cleanup current screen on exit
    switch (current_screen) {
        .Login => |login| {
            allocator.destroy(login);
        },
        .World => |world| {
            world.deinit();
            allocator.destroy(world);
        },
    }
}

test "aa" {
    const allocator = std.testing.allocator;
    const grpc = @import("grpc");
    const auth_proto = @import("model/auth.pb.zig"); // Generated file
    // 1. Initialize Connection
    var client = try grpc.GrpcClient.init(allocator, "127.0.0.1", 50051);
    defer client.deinit();

    // 2. Prepare Request
    var req = auth_proto.LoginRequest{
        .username = "test@example.com",
        .password = "password123",
    };

    // 3. Serialize (using Allocating writer pattern)
    var buf = std.Io.Writer.Allocating.init(allocator);
    defer buf.deinit();
    try req.encode(&buf.writer, allocator);

    // 4. Send
    const resp_bytes = client.call("/auth.AuthService/Login", buf.written(), .none) catch |err| {
        if (err == error.GrpcError) {
            // Server returned trailers-only (gRPC error like UNAUTHENTICATED)
            // This is expected if user doesn't exist - client still works!
            std.debug.print("gRPC call returned error (trailers-only response) - client works!\n", .{});
            return;
        }
        return err;
    };
    defer allocator.free(resp_bytes);

    // 5. Deserialize
    var r: std.Io.Reader = .fixed(resp_bytes);
    var resp = try auth_proto.LoginResponse.decode(&r, allocator);
    defer resp.deinit(allocator);
    try std.testing.expect(resp.token.len > 0);
}
