const std = @import("std");

fn buildProtobuf(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) void {
    // 1. Get the dependency
    const protobuf_dep = b.dependency("protobuf", .{
        .target = target,
        .optimize = optimize,
    });
    // 2. Get the plugin executable (protoc-gen-zig) compiled from the dependency
    // WORKAROUND: The dependency has a bug where it installs the artifact twice, causing "ambiguous artifact" error.
    // We build it manually here from the source.
    const protoc_plugin = b.addExecutable(.{
        .name = "protoc-gen-zig",
        .root_module = b.createModule(.{
            .root_source_file = protobuf_dep.path("bootstrapped-generator/main.zig"),
            .target = b.graph.host, // Plugin runs on host
            .optimize = optimize,
        }),
    });
    // The plugin needs the protobuf module
    protoc_plugin.root_module.addImport("protobuf", protobuf_dep.module("protobuf"));

    // 3. Define a command to run 'protoc'
    // We use 'addSystemCommand' to call the installed protoc binary
    const gen_cmd = b.addSystemCommand(&.{"protoc"});
    // Point protoc to use our plugin
    gen_cmd.addPrefixedFileArg("--plugin=protoc-gen-zig=", protoc_plugin.getEmittedBin());
    // Output directory for generated files
    gen_cmd.addArg("--zig_out=src/model");
    // Include path for imports (if your proto imports others)
    gen_cmd.addArg("-I../proto");
    // The input proto file
    gen_cmd.addArg("../proto/auth.proto");
    // Ensure the plugin is built before running protoc
    gen_cmd.step.dependOn(&protoc_plugin.step);
    // Create a callable step "zig build generate-proto"
    const generate_step = b.step("generate-proto", "Generate Zig code from proto");
    generate_step.dependOn(&gen_cmd.step);
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    buildProtobuf(b, target, optimize);

    const raylib_dep = b.dependency("raylib_zig", .{
        .target = target,
        .optimize = optimize,
    });
    const raylib = raylib_dep.module("raylib"); // main raylib module
    const raygui = raylib_dep.module("raygui"); // raygui module
    const raylib_artifact = raylib_dep.artifact("raylib"); // raylib C library

    // VERY IMPORTANT: Expose the "protobuf" module to your client
    const protobuf_dep = b.dependency("protobuf", .{ .target = target, .optimize = optimize });
    // Local gRPC module
    const grpc_mod = b.addModule("grpc", .{
        .root_source_file = b.path("src/grpc/client.zig"),
        .target = target,
        .optimize = optimize,
    });

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
    exe.root_module.addImport("protobuf", protobuf_dep.module("protobuf"));
    exe.root_module.addImport("grpc", grpc_mod);

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

    const exe_tests = b.addTest(.{
        .root_module = root_module,
    });
    exe_tests.linkLibrary(raylib_artifact);
    const run_exe_tests = b.addRunArtifact(exe_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_tests.step);
}
