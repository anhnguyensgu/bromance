const std = @import("std");
const rl = @import("raylib");
const shared = @import("../shared.zig");
const sheets = @import("../tiles/sheets.zig");
const plot_decoration = @import("plot_decoration.zig");
const Plot = shared.Plot;
const World = shared.World;
const FenceAsset = sheets.FenceAsset;

/// Plot rendering options
pub const PlotRenderStyle = struct {
    border_color: rl.Color = rl.Color.init(100, 200, 100, 255),
    border_thickness: f32 = 2.0,
    fill_color: rl.Color = rl.Color.init(100, 200, 100, 30),
    selected_border_color: rl.Color = rl.Color.init(255, 215, 0, 255),
    selected_fill_color: rl.Color = rl.Color.init(255, 215, 0, 50),
    hover_border_color: rl.Color = rl.Color.init(255, 255, 255, 255),
    hover_fill_color: rl.Color = rl.Color.init(255, 255, 255, 40),
    owned_border_color: rl.Color = rl.Color.init(50, 150, 255, 255),
    owned_fill_color: rl.Color = rl.Color.init(50, 150, 255, 30),
};

pub const PlotState = enum { normal, hover, selected };

pub fn drawPlotBoundary(plot: Plot, world: World, style: PlotRenderStyle, state: PlotState, fence_asset: ?FenceAsset) void {
    const tile_w = world.width / @as(f32, @floatFromInt(world.tiles_x));
    const tile_h = world.height / @as(f32, @floatFromInt(world.tiles_y));

    const x = world.tileToWorldX(plot.tile_x);
    const y = world.tileToWorldY(plot.tile_y);
    const w = @as(f32, @floatFromInt(plot.width_tiles)) * tile_w;
    const h = @as(f32, @floatFromInt(plot.height_tiles)) * tile_h;

    const fill_color = switch (state) {
        .normal => if (plot.owner.kind != .none) style.owned_fill_color else style.fill_color,
        .hover => style.hover_fill_color,
        .selected => style.selected_fill_color,
    };

    rl.drawRectangle(@intFromFloat(x), @intFromFloat(y), @intFromFloat(w), @intFromFloat(h), fill_color);

    if (fence_asset) |fence| {
        plot_decoration.drawPlotFenceBorder(fence, plot, world, false);
    } else {
        const border_color = switch (state) {
            .normal => if (plot.owner.kind != .none) style.owned_border_color else style.border_color,
            .hover => style.hover_border_color,
            .selected => style.selected_border_color,
        };
        rl.drawRectangleLinesEx(
            rl.Rectangle{ .x = x, .y = y, .width = w, .height = h },
            style.border_thickness,
            border_color,
        );
    }
}

pub fn drawAllPlots(plots: []const Plot, world: World, style: PlotRenderStyle, selected_plot_id: ?u64, hovered_plot_id: ?u64, fence_asset: ?FenceAsset) void {
    for (plots) |plot| {
        const state: PlotState = blk: {
            if (selected_plot_id) |id| {
                if (plot.id == id) break :blk .selected;
            }
            if (hovered_plot_id) |id| {
                if (plot.id == id) break :blk .hover;
            }
            break :blk .normal;
        };

        drawPlotBoundary(plot, world, style, state, fence_asset);
    }
}

/// Draw plot info overlay (shows plot ID and owner)
pub fn drawPlotInfo(plot: Plot, world: World, font_size: i32) void {
    const tile_w = world.width / @as(f32, @floatFromInt(world.tiles_x));
    const tile_h = world.height / @as(f32, @floatFromInt(world.tiles_y));

    const x = world.tileToWorldX(plot.tile_x);
    const y = world.tileToWorldY(plot.tile_y);
    const w = @as(f32, @floatFromInt(plot.width_tiles)) * tile_w;
    const h = @as(f32, @floatFromInt(plot.height_tiles)) * tile_h;

    const center_x = x + w / 2.0;
    const center_y = y + h / 2.0;

    // Draw plot ID
    var id_buf: [32]u8 = undefined;
    const id_text = std.fmt.bufPrintZ(&id_buf, "Plot #{}", .{plot.id}) catch "Plot #?";
    const text_width = rl.measureText(id_text, font_size);
    rl.drawText(
        id_text,
        @intFromFloat(center_x - @as(f32, @floatFromInt(text_width)) / 2.0),
        @intFromFloat(center_y - @as(f32, @floatFromInt(font_size)) / 2.0),
        font_size,
        .white,
    );

    // Draw owner info below ID
    if (plot.owner.kind != .none) {
        var owner_buf: [64]u8 = undefined;
        const owner_value = plot.owner.getValue();
        const display_owner = if (owner_value.len > 12)
            std.fmt.bufPrintZ(&owner_buf, "{s}...{s}", .{ owner_value[0..6], owner_value[owner_value.len - 4 ..] }) catch "Owner"
        else
            std.fmt.bufPrintZ(&owner_buf, "{s}", .{owner_value}) catch "Owner";

        const owner_width = rl.measureText(display_owner, font_size - 4);
        rl.drawText(
            display_owner,
            @intFromFloat(center_x - @as(f32, @floatFromInt(owner_width)) / 2.0),
            @intFromFloat(center_y + @as(f32, @floatFromInt(font_size)) / 2.0 + 4),
            font_size - 4,
            rl.Color.init(200, 200, 200, 255),
        );
    } else {
        const unclaimed = "Unclaimed";
        const unclaimed_width = rl.measureText(unclaimed, font_size - 4);
        rl.drawText(
            unclaimed,
            @intFromFloat(center_x - @as(f32, @floatFromInt(unclaimed_width)) / 2.0),
            @intFromFloat(center_y + @as(f32, @floatFromInt(font_size)) / 2.0 + 4),
            font_size - 4,
            rl.Color.init(150, 150, 150, 255),
        );
    }
}

/// Get hovered plot based on world position (useful for mouse interaction)
pub fn getHoveredPlot(world: World, world_pos_x: f32, world_pos_y: f32) ?u64 {
    if (world.getPlotAtPosition(world_pos_x, world_pos_y)) |plot| {
        return plot.id;
    }
    return null;
}

/// Draw a grid overlay showing tile boundaries (helpful for plot creation)
pub fn drawTileGrid(world: World, color: rl.Color) void {
    const tile_w = world.width / @as(f32, @floatFromInt(world.tiles_x));
    const tile_h = world.height / @as(f32, @floatFromInt(world.tiles_y));

    // Vertical lines
    var x: i32 = 0;
    while (x <= world.tiles_x) : (x += 1) {
        const world_x = @as(f32, @floatFromInt(x)) * tile_w;
        rl.drawLine(
            @intFromFloat(world_x),
            0,
            @intFromFloat(world_x),
            @intFromFloat(world.height),
            color,
        );
    }

    // Horizontal lines
    var y: i32 = 0;
    while (y <= world.tiles_y) : (y += 1) {
        const world_y = @as(f32, @floatFromInt(y)) * tile_h;
        rl.drawLine(
            0,
            @intFromFloat(world_y),
            @intFromFloat(world.width),
            @intFromFloat(world_y),
            color,
        );
    }
}
