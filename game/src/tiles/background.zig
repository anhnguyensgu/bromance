const std = @import("std");
const rl = @import("raylib");
const inspector = @import("../tile_inspector.zig");

pub fn drawBackground(tileset_texture: rl.Texture2D) void {
    // Example: use Frames and drawLandscapeTile from tile_inspector
    // to draw a single grass tile at the origin. Adjust as needed.
    const grass_frames = inspector.Frames.SpringTileGrass(tileset_texture);
    inspector.drawLandscapeTile(grass_frames, 0, 0);
}
