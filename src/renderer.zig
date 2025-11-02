const std = @import("std");
const GameState = @import("state.zig").GameState;
const InventoryItem = @import("state.zig").InventoryItem;

pub const Renderer = struct {
    pub fn init() Renderer {
        return .{};
    }

    pub fn beginFrame(_: *Renderer) void {
        std.debug.print("\n=== Frame Start =================================\n", .{});
    }

    pub fn endFrame(_: *Renderer) void {
        std.debug.print("=== Frame End ===================================\n", .{});
    }

    pub fn drawBanner(_: *Renderer, title: []const u8) void {
        std.debug.print("-- {s} --\n", .{title});
    }

    pub fn drawInventorySummary(_: *Renderer, filled: usize, capacity: usize) void {
        std.debug.print("Slots: {d}/{d}\n", .{ filled, capacity });
    }

    pub fn drawInventorySlot(_: *Renderer, index: usize, slot: ?InventoryItem) void {
        if (slot) |item| {
            std.debug.print("[{d}] {s} x{d}\n", .{ index + 1, item.name, item.quantity });
        } else {
            std.debug.print("[{d}] (empty)\n", .{index + 1});
        }
    }

    pub fn drawHudLine(
        _: *Renderer,
        label: []const u8,
        comptime fmt: []const u8,
        args: anytype,
    ) void {
        std.debug.print("{s}: ", .{label});
        std.debug.print(fmt, args);
        std.debug.print("\n", .{});
    }

    pub fn drawGameStateSummary(_: *Renderer, state: *const GameState) void {
        const stamina_percent =
            @as(u8, @intFromFloat(@round(state.staminaPercent() * 100.0)));

        std.debug.print(
            "Player: hearts {d}/{d}, stamina {d}%, coins {d}\n",
            .{
                state.hearts(),
                state.maxHearts(),
                stamina_percent,
                state.coins(),
            },
        );
    }
};

const sokol = @import("sokol");
const slog = sokol.log;
const sg = sokol.gfx;
const sapp = sokol.app;
const sglue = sokol.glue;
const sdtx = sokol.debugtext;
const sshape = sokol.shape;
const vec3 = @import("math.zig").Vec3;
const mat4 = @import("math.zig").Mat4;
const assert = @import("std").debug.assert;
const shd = @import("shapes.glsl.zig");

const Shape = struct {
    pos: vec3 = vec3.zero(),
    draw: sshape.ElementRange = .{},
};

const NUM_SHAPES = 5;

const renderState = struct {
    var pass_action: sg.PassAction = .{};
    var pip: sg.Pipeline = .{};
    var bind: sg.Bindings = .{};
    var vs_params: shd.VsParams = undefined;
    var shapes: [NUM_SHAPES]Shape = .{
        .{ .pos = .{ .x = -1, .y = 1, .z = 0 } },
        .{ .pos = .{ .x = 1, .y = 1, .z = 0 } },
        .{ .pos = .{ .x = -2, .y = -1, .z = 0 } },
        .{ .pos = .{ .x = 2, .y = -1, .z = 0 } },
        .{ .pos = .{ .x = 0, .y = -1, .z = 0 } },
    };
    var rx: f32 = 0.0;
    var ry: f32 = 0.0;
    const view = mat4.lookat(.{ .x = 0.0, .y = 1.5, .z = 6.0 }, vec3.zero(), vec3.up());
};

export fn init() void {
    sg.setup(.{
        .environment = sglue.environment(),
        .logger = .{ .func = slog.func },
    });

    var sdtx_desc: sdtx.Desc = .{
        .logger = .{ .func = slog.func },
    };
    sdtx_desc.fonts[0] = sdtx.fontOric();
    sdtx.setup(sdtx_desc);

    // pass-action for clearing to black
    renderState.pass_action.colors[0] = .{
        .load_action = .CLEAR,
        .clear_value = .{ .r = 0, .g = 0, .b = 0, .a = 1 },
    };

    // shader- and pipeline-object
    renderState.pip = sg.makePipeline(.{
        .shader = sg.makeShader(shd.shapesShaderDesc(sg.queryBackend())),
        .layout = init: {
            var l = sg.VertexLayoutState{};
            l.buffers[0] = sshape.vertexBufferLayoutState();
            l.attrs[shd.ATTR_shapes_position] = sshape.positionVertexAttrState();
            l.attrs[shd.ATTR_shapes_normal] = sshape.normalVertexAttrState();
            l.attrs[shd.ATTR_shapes_texcoord] = sshape.texcoordVertexAttrState();
            l.attrs[shd.ATTR_shapes_color0] = sshape.colorVertexAttrState();
            break :init l;
        },
        .index_type = .UINT16,
        .cull_mode = .NONE,
        .depth = .{
            .compare = .LESS_EQUAL,
            .write_enabled = true,
        },
    });

    // generate shape geometries
    var vertices: [6 * 1024]sshape.Vertex = undefined;
    var indices: [16 * 1024]u16 = undefined;
    var buf: sshape.Buffer = .{
        .vertices = .{ .buffer = sshape.asRange(&vertices) },
        .indices = .{ .buffer = sshape.asRange(&indices) },
    };
    buf = sshape.buildBox(buf, .{
        .width = 1.0,
        .height = 1.0,
        .depth = 1.0,
        .tiles = 10,
        .random_colors = true,
    });
    renderState.shapes[0].draw = sshape.elementRange(buf);
    buf = sshape.buildPlane(buf, .{
        .width = 1.0,
        .depth = 1.0,
        .tiles = 10,
        .random_colors = true,
    });
    renderState.shapes[1].draw = sshape.elementRange(buf);
    buf = sshape.buildSphere(buf, .{
        .radius = 0.75,
        .slices = 36,
        .stacks = 20,
        .random_colors = true,
    });
    renderState.shapes[2].draw = sshape.elementRange(buf);
    buf = sshape.buildCylinder(buf, .{
        .radius = 0.5,
        .height = 1.5,
        .slices = 36,
        .stacks = 10,
        .random_colors = true,
    });
    renderState.shapes[3].draw = sshape.elementRange(buf);
    buf = sshape.buildTorus(buf, .{
        .radius = 0.5,
        .ring_radius = 0.3,
        .rings = 36,
        .sides = 18,
        .random_colors = true,
    });
    renderState.shapes[4].draw = sshape.elementRange(buf);
    assert(buf.valid);

    // one vertex- and index-buffer for all shapes
    renderState.bind.vertex_buffers[0] = sg.makeBuffer(sshape.vertexBufferDesc(buf));
    renderState.bind.index_buffer = sg.makeBuffer(sshape.indexBufferDesc(buf));
}

export fn frame() void {
    // help text
    sdtx.canvas(sapp.widthf() * 0.5, sapp.heightf() * 0.5);
    sdtx.pos(0.5, 0.5);
    sdtx.puts("press key to switch draw mode:\n\n");
    sdtx.puts("  1: vertex normals\n");
    sdtx.puts("  2: texture coords\n");
    sdtx.puts("  3: vertex colors\n");

    // view-project matrix
    const proj = mat4.persp(60.0, sapp.widthf() / sapp.heightf(), 0.01, 10.0);
    const view_proj = mat4.mul(proj, renderState.view);

    // model-rotation matrix
    const dt: f32 = @floatCast(sapp.frameDuration() * 60);
    renderState.rx += 1.0 * dt;
    renderState.ry += 1.0 * dt;
    const rxm = mat4.rotate(renderState.rx, .{ .x = 1, .y = 0, .z = 0 });
    const rym = mat4.rotate(renderState.ry, .{ .x = 0, .y = 1, .z = 0 });
    const rm = mat4.mul(rxm, rym);

    // render shapes...
    sg.beginPass(.{ .action = renderState.pass_action, .swapchain = sglue.swapchain() });
    sg.applyPipeline(renderState.pip);
    sg.applyBindings(renderState.bind);
    for (renderState.shapes) |shape| {
        // per-shape model-view-projection matrix
        const model = mat4.mul(mat4.translate(shape.pos), rm);
        renderState.vs_params.mvp = mat4.mul(view_proj, model);
        sg.applyUniforms(shd.UB_vs_params, sg.asRange(&renderState.vs_params));
        sg.draw(shape.draw.base_element, shape.draw.num_elements, 1);
    }
    sdtx.draw();
    sg.endPass();
    sg.commit();
}

export fn input(event: ?*const sapp.Event) void {
    const ev = event.?;
    if (ev.type == .KEY_DOWN) {
        renderState.vs_params.draw_mode = switch (ev.key_code) {
            ._1 => 0.0,
            ._2 => 1.0,
            ._3 => 2.0,
            else => renderState.vs_params.draw_mode,
        };
    }
}

export fn cleanup() void {
    sdtx.shutdown();
    sg.shutdown();
}

pub fn run() void {
    sapp.run(.{
        .init_cb = init,
        .frame_cb = frame,
        .event_cb = input,
        .cleanup_cb = cleanup,
        .width = 800,
        .height = 600,
        .sample_count = 4,
        .icon = .{ .sokol_default = true },
        .window_title = "shapes.zig",
        .logger = .{ .func = slog.func },
    });
}
