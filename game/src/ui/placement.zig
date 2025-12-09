const std = @import("std");
const rl = @import("raylib");
const sheets = @import("../tiles/sheets.zig");

/// Data representing a placeable item (sprite + texture + type)
pub const PlaceableItem = struct {
    sprite: sheets.SpriteRect,
    texture: rl.Texture2D,
    item_type: []const u8 = "Tile",
};

/// A placed item in the world
pub const PlacedItem = struct {
    data: PlaceableItem,
    rect: rl.Rectangle,
};

/// Configuration for the placement system
pub const PlacementConfig = struct {
    grid_size: i32 = 16,
    ghost_alpha: u8 = 150,
    valid_color: rl.Color = rl.Color{ .r = 0, .g = 255, .b = 0, .a = 100 },
    invalid_color: rl.Color = rl.Color{ .r = 255, .g = 0, .b = 0, .a = 100 },
};

/// Result of an update tick
pub const PlacementResult = struct {
    placed: bool = false,
    rect: rl.Rectangle = .{ .x = 0, .y = 0, .width = 0, .height = 0 },
    col: i32 = 0,
    row: i32 = 0,
};

/// Manages placement state and ghost rendering
pub const PlacementSystem = struct {
    const Self = @This();

    active_item: ?*const PlaceableItem = null,
    is_placing: bool = false,
    last_placed_col: ?i32 = null,
    last_placed_row: ?i32 = null,
    config: PlacementConfig,

    // Bounds for validity checking
    bounds_tiles_x: i32 = 0,
    bounds_tiles_y: i32 = 0,

    pub fn init(config: PlacementConfig) Self {
        return .{
            .config = config,
        };
    }

    /// Set the world bounds for validity checking
    pub fn setBounds(self: *Self, tiles_x: i32, tiles_y: i32) void {
        self.bounds_tiles_x = tiles_x;
        self.bounds_tiles_y = tiles_y;
    }

    /// Start placing an item
    pub fn startPlacing(self: *Self, item: *const PlaceableItem) void {
        self.active_item = item;
        self.is_placing = true;
        self.last_placed_col = null;
        self.last_placed_row = null;
    }

    /// Cancel placement mode
    pub fn cancel(self: *Self) void {
        self.is_placing = false;
        self.active_item = null;
        self.last_placed_col = null;
        self.last_placed_row = null;
    }

    /// Check if currently in placement mode
    pub fn isActive(self: *const Self) bool {
        return self.is_placing and self.active_item != null;
    }

    /// Handle mouse button release to reset continuous placement tracking
    pub fn handleMouseRelease(self: *Self) void {
        if (rl.isMouseButtonReleased(.left)) {
            self.last_placed_col = null;
            self.last_placed_row = null;
        }
    }

    /// Calculate grid position from world position
    pub fn worldToGrid(self: *const Self, world_pos: rl.Vector2) struct { col: i32, row: i32 } {
        const col = @divFloor(@as(i32, @intFromFloat(world_pos.x)), self.config.grid_size);
        const row = @divFloor(@as(i32, @intFromFloat(world_pos.y)), self.config.grid_size);
        return .{ .col = col, .row = row };
    }

    /// Calculate snapped world position from grid position
    pub fn gridToWorld(self: *const Self, col: i32, row: i32) rl.Vector2 {
        return .{
            .x = @as(f32, @floatFromInt(col)) * @as(f32, @floatFromInt(self.config.grid_size)),
            .y = @as(f32, @floatFromInt(row)) * @as(f32, @floatFromInt(self.config.grid_size)),
        };
    }

    /// Check if a placement at the given grid position would be valid
    pub fn isValidPlacement(self: *const Self, col: i32, row: i32, tile_w: i32, tile_h: i32) bool {
        return (col >= 0 and row >= 0 and
            col + tile_w <= self.bounds_tiles_x and
            row + tile_h <= self.bounds_tiles_y);
    }

    /// Update and render the ghost preview. Returns placement result if item was placed.
    /// Should be called within beginMode2D/endMode2D block.
    pub fn updateAndRender(self: *Self, camera: rl.Camera2D) PlacementResult {
        var result = PlacementResult{};

        if (!self.isActive()) return result;

        const data = self.active_item.?;
        const grid_size = self.config.grid_size;

        // Get mouse position in world coordinates
        const mouse = rl.getMousePosition();
        const world_mouse = rl.getScreenToWorld2D(mouse, camera);

        // Snap to grid
        const grid_pos = self.worldToGrid(world_mouse);
        const col = grid_pos.col;
        const row = grid_pos.row;
        const snap_pos = self.gridToWorld(col, row);

        // Calculate tile dimensions (rounded up to grid)
        const tile_w = @divTrunc(@as(i32, @intFromFloat(data.sprite.width)) + grid_size - 1, grid_size);
        const tile_h = @divTrunc(@as(i32, @intFromFloat(data.sprite.height)) + grid_size - 1, grid_size);

        const rect = rl.Rectangle{
            .x = snap_pos.x,
            .y = snap_pos.y,
            .width = @floatFromInt(tile_w * grid_size),
            .height = @floatFromInt(tile_h * grid_size),
        };

        // Validity check
        const valid = self.isValidPlacement(col, row, tile_w, tile_h);

        // Draw colored shadow/highlight
        const shadow_color = if (valid) self.config.valid_color else self.config.invalid_color;
        rl.drawRectangleRec(rect, shadow_color);

        // Draw ghost sprite (semi-transparent)
        const src = rl.Rectangle{
            .x = data.sprite.x,
            .y = data.sprite.y,
            .width = data.sprite.width,
            .height = data.sprite.height,
        };
        rl.drawTexturePro(
            data.texture,
            src,
            rect,
            .{ .x = 0, .y = 0 },
            0,
            rl.Color{ .r = 255, .g = 255, .b = 255, .a = self.config.ghost_alpha },
        );

        // Handle placement (continuous while holding left mouse button)
        const is_new_cell = (self.last_placed_col != col or self.last_placed_row != row);
        if (rl.isMouseButtonDown(.left) and valid and is_new_cell) {
            self.last_placed_col = col;
            self.last_placed_row = row;
            result.placed = true;
            result.rect = rect;
            result.col = col;
            result.row = row;
        }

        return result;
    }

    /// Render a list of placed items
    pub fn renderPlacedItems(items: []const PlacedItem) void {
        for (items) |item| {
            sheets.drawSpriteTo(item.data.texture, item.data.sprite, item.rect);
        }
    }
};

/// Manages a list of placed items with memory allocation
pub fn PlacedItemList(comptime capacity: usize) type {
    return struct {
        const Self = @This();

        items: std.ArrayList(PlacedItem),

        pub fn init(allocator: std.mem.Allocator) !Self {
            return .{
                .items = try std.ArrayList(PlacedItem).initCapacity(allocator, capacity),
            };
        }

        pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            self.items.deinit(allocator);
        }

        pub fn add(self: *Self, allocator: std.mem.Allocator, data: PlaceableItem, rect: rl.Rectangle) !void {
            try self.items.append(allocator, .{ .data = data, .rect = rect });
        }

        pub fn clear(self: *Self) void {
            self.items.clearRetainingCapacity();
        }

        pub fn render(self: *const Self) void {
            PlacementSystem.renderPlacedItems(self.items.items);
        }
    };
}
