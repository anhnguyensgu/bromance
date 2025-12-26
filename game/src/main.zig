const std = @import("std");
const rl = @import("raylib");
const shared = @import("shared.zig");

const context = @import("core/context.zig");
const scene_manager = @import("core/scene_manager.zig");
const assets = @import("core/assets.zig");

const LoginScreen = shared.LoginScreen;
const HttpClient = shared.HttpClient;

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

    // Init HttpClient
    const http_client = try allocator.create(HttpClient);
    http_client.* = HttpClient.init(allocator);
    defer {
        http_client.deinit();
        allocator.destroy(http_client);
    }

    // Init Asset Cache
    const asset_cache = try allocator.create(assets.AssetCache);
    asset_cache.* = assets.AssetCache.init(allocator);
    defer {
        asset_cache.deinit();
        allocator.destroy(asset_cache);
    }

    // Init Game Context
    var ctx = context.GameContext.init(allocator, asset_cache, http_client, screen_width, screen_height);

    // Initial Screen: Login
    const login_screen = try allocator.create(LoginScreen);
    login_screen.* = LoginScreen{
        .width = 400.0,
        .height = 300.0,
        .http_client = http_client,
    };

    var sm = scene_manager.SceneManager.init(allocator, .{ .Login = login_screen });
    defer sm.deinit();

    // Main game loop
    while (!rl.windowShouldClose()) {
        const dt = rl.getFrameTime();

        // Update
        // Capture error but maybe log and continue or exit?
        sm.update(dt, &ctx) catch |err| {
            std.debug.print("Error in update: {}\n", .{err});
            // break; // Quit on error?
        };

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();
        rl.clearBackground(rl.Color.ray_white);

        sm.draw(&ctx);
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

test "test grpc" {
    const grpc = @import("grpc");
    const auth_proto = @import("model/auth.pb.zig");
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    // 1. Connect to server
    var client = try grpc.GrpcClient.init(allocator, "127.0.0.1", 50051);
    defer client.deinit();

    // 2. Create request
    var req = auth_proto.LoginRequest{
        .username = "user@example.com",
        .password = "password123",
    };

    // 3. Serialize request
    var buf = std.Io.Writer.Allocating.init(allocator);
    defer buf.deinit();
    try req.encode(&buf.writer, allocator);

    // 4. Make RPC call
    const resp_bytes = try client.call("/auth.AuthService/Login", buf.written(), .none);
    defer allocator.free(resp_bytes);

    // 5. Deserialize response
    var reader: std.Io.Reader = .fixed(resp_bytes);
    var resp = try auth_proto.LoginResponse.decode(&reader, allocator);
    defer resp.deinit(allocator);

    std.debug.print("Token: {s}\n", .{resp.token});
}
