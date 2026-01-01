const std = @import("std");
const rl = @import("raylib");
const shared = @import("../shared.zig");
const sheets = @import("../tiles/sheets.zig");
const Plot = shared.Plot;
const World = shared.World;
const FenceStyle = sheets.FenceStyle;
const FenceAsset = sheets.FenceAsset;

pub fn drawFence(fence_asset: FenceAsset, world_x: f32, world_y: f32, style: FenceStyle, debug: bool) void {
    const sprite = fence_asset.get(style);
    const source = rl.Rectangle{
        .x = sprite.x,
        .y = sprite.y,
        .width = sprite.width,
        .height = sprite.height,
    };
    const dest = rl.Rectangle{
        .x = world_x,
        .y = world_y,
        .width = 16,
        .height = 16,
    };
    rl.drawTexturePro(fence_asset.texture2D, source, dest, .{ .x = 0, .y = 0 }, 0, .white);

    if (debug) {
        rl.drawRectangleLines(@intFromFloat(dest.x), @intFromFloat(dest.y), @intFromFloat(dest.width), @intFromFloat(dest.height), .red);
    }
}

pub fn drawPlotFenceBorder(fence_asset: FenceAsset, plot: Plot, world: World, debug: bool) void {
    var tx: i32 = 0;
    while (tx < plot.width_tiles) : (tx += 1) {
        var ty: i32 = 0;
        while (ty < plot.height_tiles) : (ty += 1) {
            const world_x = world.tileToWorldX(plot.tile_x + tx);
            const world_y = world.tileToWorldY(plot.tile_y + ty);

            const is_left = tx == 0;
            const is_right = tx == plot.width_tiles - 1;
            const is_top = ty == 0;
            const is_bottom = ty == plot.height_tiles - 1;

            const is_corner = (is_left or is_right) and (is_top or is_bottom);
            const is_edge = is_left or is_right or is_top or is_bottom;

            if (is_corner) {
                const style: FenceStyle = if (is_top and is_left)
                    .top_left_corner
                else if (is_top and is_right)
                    .top_right_corner
                else if (is_bottom and is_left)
                    .bottom_left_corner
                else
                    .bottom_right_corner;

                drawFence(fence_asset, world_x, world_y, style, debug);
            } else if (is_edge) {
                const style: FenceStyle = if (is_top)
                    .t_top
                else if (is_bottom) .t_top else .vertical;

                drawFence(fence_asset, world_x, world_y, style, debug);
            }
        }
    }
}
