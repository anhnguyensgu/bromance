const std = @import("std");
const rl = @import("raylib");

/// Generic sprite sheet with frame dimensions and helper methods
pub const SpriteSheet = struct {
    texture: rl.Texture2D,
    frame_w: u32,
    frame_h: u32,
    spacing: u32,
    columns: u32,

    const Self = @This();

    pub fn init(path: [:0]const u8, frame_w: u32, frame_h: u32, spacing: u32, columns: u32) !Self {
        return .{
            .texture = try rl.loadTexture(path),
            .frame_w = frame_w,
            .frame_h = frame_h,
            .spacing = spacing,
            .columns = columns,
        };
    }

    pub fn deinit(self: *Self) void {
        rl.unloadTexture(self.texture);
    }

    /// Get source rectangle for a sprite index
    pub fn getSourceRect(self: Self, index: u32) rl.Rectangle {
        const col: i32 = @intCast(index % self.columns);
        const row: i32 = @intCast(index / self.columns);
        const stride_x: i32 = @intCast(self.frame_w + self.spacing);
        const stride_y: i32 = @intCast(self.frame_h + self.spacing);

        return .{
            .x = @floatFromInt(col * stride_x),
            .y = @floatFromInt(row * stride_y),
            .width = @floatFromInt(self.frame_w),
            .height = @floatFromInt(self.frame_h),
        };
    }

    /// Draw sprite at position with original size
    pub fn draw(self: Self, index: u32, x: i32, y: i32) void {
        const src = self.getSourceRect(index);
        const dest = rl.Vector2{ .x = @floatFromInt(x), .y = @floatFromInt(y) };
        rl.drawTextureRec(self.texture, src, dest, .white);
    }

    /// Draw sprite scaled to destination rectangle
    pub fn drawScaled(self: Self, index: u32, dest_rect: rl.Rectangle) void {
        const src = self.getSourceRect(index);
        rl.drawTexturePro(self.texture, src, dest_rect, .{ .x = 0, .y = 0 }, 0, .white);
    }
};
