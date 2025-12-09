const std = @import("std");
const rl = @import("raylib");
const placement = @import("placement.zig");
const PlaceableItem = placement.PlaceableItem;

const editor_map = @import("../map/editor_map.zig");
const Map = editor_map.Map;
const TileId = editor_map.TileId;

/// GhostLayer owns the logic for applying a placement result to
/// a list of placed items + backing map (including eraser behaviour).
pub const GhostLayer = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    placed_items: *std.ArrayList(placement.PlacedItem),
    editor_map: *Map,

    /// Apply a placement result for the given active item.
    ///
    /// - If the item is the special "Eraser" tool, remove any
    ///   placed items that collide with the placement rectangle.
    /// - Otherwise, add a new placed item if there isn't already
    ///   one at that rect, and update the editor map's tile grid.
    pub fn applyPlacement(self: *Self, item: *const PlaceableItem, result: placement.PlacementResult) void {
        if (item.item_type == .Eraser) {
            // Eraser Logic: Remove all items colliding with the eraser cursor
            var i: usize = self.placed_items.items.len;
            while (i > 0) {
                i -= 1;
                if (rl.checkCollisionRecs(self.placed_items.items[i].rect, result.rect)) {
                    _ = self.placed_items.orderedRemove(i);
                }
            }
        } else {
            // Normal Placement Logic
            var already_exists = false;
            for (self.placed_items.items) |existing| {
                if (rl.checkCollisionRecs(existing.rect, result.rect)) {
                    already_exists = true;
                    break;
                }
            }

            if (!already_exists) {
                self.placed_items.append(self.allocator, .{ .data = item.*, .rect = result.rect }) catch {};

                // Also update the editor map with the placed tile
                if (result.col >= 0 and result.row >= 0) {
                    const tile_id: TileId = 1; // Default tile ID for placed items
                    self.editor_map.setTile(@intCast(result.col), @intCast(result.row), tile_id);
                }
            }
        }
    }
};
