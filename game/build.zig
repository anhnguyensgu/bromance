const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const raylib_dep = b.dependency("raylib_zig", .{
        .target = target,
        .optimize = optimize,
    });
    const raylib = raylib_dep.module("raylib"); // main raylib module
    const raygui = raylib_dep.module("raygui"); // raygui module
    const raylib_artifact = raylib_dep.artifact("raylib"); // raylib C library

    // Shared module (reused by client & server)
    const shared_mod = b.addModule("shared", .{
        .root_source_file = b.path("src/shared.zig"),
        .target = target,
        .optimize = optimize,
    });
    shared_mod.addImport("raylib", raylib);

    const root_module = b.addModule("zig_client_root", .{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "shared", .module = shared_mod }},
    });

    const exe = b.addExecutable(.{
        .name = "zig-client",
        .root_module = root_module,
    });

    exe.linkLibrary(raylib_artifact);
    exe.root_module.addImport("raylib", raylib);
    exe.root_module.addImport("raygui", raygui);

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the zig-client demo");
    run_step.dependOn(&run_cmd.step);

    // Server executable (pure Zig, imports shared)
    const server_mod = b.addModule("zig_server_root", .{
        .root_source_file = b.path("src/server_main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "shared", .module = shared_mod }},
    });
    const server_exe = b.addExecutable(.{ .name = "zig-server", .root_module = server_mod });
    b.installArtifact(server_exe);
    const run_server = b.addRunArtifact(server_exe);
    run_server.step.dependOn(b.getInstallStep());
    b.step("run-server", "Run the zig server").dependOn(&run_server.step);

    // Tile Inspector executable
    const inspector_mod = b.addModule("zig_inspector_root", .{
        .root_source_file = b.path("src/tile_inspector.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "shared", .module = shared_mod }},
    });
    const inspector_exe = b.addExecutable(.{ .name = "tile-inspector", .root_module = inspector_mod });
    inspector_exe.linkLibrary(raylib_artifact);
    inspector_exe.root_module.addImport("raylib", raylib);
    inspector_exe.root_module.addImport("raygui", raygui);
    b.installArtifact(inspector_exe);
    const run_inspector = b.addRunArtifact(inspector_exe);
    run_inspector.step.dependOn(b.getInstallStep());
    b.step("run-inspector", "Run the tile inspector app").dependOn(&run_inspector.step);
}
