const rl = @import("raylib");

pub const Slice = struct {
    // head = the rect you use now; rest = remaining space for the next element.
    //
    // Visualization (top slicing):
    // +--------------------+  <- parent rect
    // | head (use now)     |
    // +--------------------+
    // | rest (remaining)   |
    // | ...                |
    // +--------------------+
    //
    // Full comparison:
    // A) Rect slicing (head/rest)
    // panel_rect
    // +------------------------------+
    // | padding                      |
    // |  +------------------------+  |
    // |  | content_rect            |  |
    // |  |                         |  |
    // |  |  takeTop(20) -> head    |  |
    // |  |  +------------------+   |  |
    // |  |  | title (head)     |   |  |
    // |  |  +------------------+   |  |
    // |  |  rest (remaining)       |  |
    // |  |  +------------------+   |  |
    // |  |  | label (head)     |   |  |
    // |  |  +------------------+   |  |
    // |  |  rest ...               |  |
    // |  +------------------------+  |
    // +------------------------------+
    //
    // Each call gives:
    // - head = the rectangle you place an element into.
    // - rest = what's left for the next element.
    //
    // B) x/y cursor
    // x,y (cursor)
    // |
    // v
    // +------------------------------+
    // | content_rect                 |
    // |   [draw title at cursor]     |
    // |   cursor.y += title_h + gap  |
    // |   [draw label at cursor]     |
    // |   cursor.y += label_h + gap  |
    // |   [draw input at cursor]     |
    // +------------------------------+
    //
    // You just move the cursor down after each element.
    head: rl.Rectangle,
    rest: rl.Rectangle,
};

pub fn takeTop(rect: rl.Rectangle, height: f32, gap: f32) Slice {
    const head = rl.Rectangle{
        .x = rect.x,
        .y = rect.y,
        .width = rect.width,
        .height = height,
    };
    const remaining = rect.height - height - gap;
    const rest = rl.Rectangle{
        .x = rect.x,
        .y = rect.y + height + gap,
        .width = rect.width,
        .height = if (remaining > 0) remaining else 0,
    };
    return .{ .head = head, .rest = rest };
}

pub fn takeBottom(rect: rl.Rectangle, height: f32, gap: f32) Slice {
    const head = rl.Rectangle{
        .x = rect.x,
        .y = rect.y + rect.height - height,
        .width = rect.width,
        .height = height,
    };
    const remaining = rect.height - height - gap;
    const rest = rl.Rectangle{
        .x = rect.x,
        .y = rect.y,
        .width = rect.width,
        .height = if (remaining > 0) remaining else 0,
    };
    return .{ .head = head, .rest = rest };
}

pub const SplitH = struct {
    left: rl.Rectangle,
    right: rl.Rectangle,
};

pub fn splitH(rect: rl.Rectangle, left_width: f32, gap: f32) SplitH {
    const right_width = rect.width - left_width - gap;
    return .{
        .left = rl.Rectangle{
            .x = rect.x,
            .y = rect.y,
            .width = left_width,
            .height = rect.height,
        },
        .right = rl.Rectangle{
            .x = rect.x + left_width + gap,
            .y = rect.y,
            .width = if (right_width > 0) right_width else 0,
            .height = rect.height,
        },
    };
}

pub const SplitV = struct {
    top: rl.Rectangle,
    bottom: rl.Rectangle,
};

pub fn splitV(rect: rl.Rectangle, top_height: f32, gap: f32) SplitV {
    const bottom_height = rect.height - top_height - gap;
    return .{
        .top = rl.Rectangle{
            .x = rect.x,
            .y = rect.y,
            .width = rect.width,
            .height = top_height,
        },
        .bottom = rl.Rectangle{
            .x = rect.x,
            .y = rect.y + top_height + gap,
            .width = rect.width,
            .height = if (bottom_height > 0) bottom_height else 0,
        },
    };
}

pub const Column = struct {
    rect: rl.Rectangle,
    cursor_y: f32,
    gap: f32,

    pub fn init(rect: rl.Rectangle, gap: f32) Column {
        return .{
            .rect = rect,
            .cursor_y = rect.y,
            .gap = gap,
        };
    }

    pub fn next(self: *Column, height: f32) rl.Rectangle {
        const rect = rl.Rectangle{
            .x = self.rect.x,
            .y = self.cursor_y,
            .width = self.rect.width,
            .height = height,
        };
        self.cursor_y += height + self.gap;
        return rect;
    }

    pub fn skip(self: *Column, height: f32) void {
        self.cursor_y += height;
    }
};

pub const Row = struct {
    rect: rl.Rectangle,
    cursor_x: f32,
    gap: f32,

    pub fn init(rect: rl.Rectangle, gap: f32) Row {
        return .{
            .rect = rect,
            .cursor_x = rect.x,
            .gap = gap,
        };
    }

    pub fn next(self: *Row, width: f32) rl.Rectangle {
        const rect = rl.Rectangle{
            .x = self.cursor_x,
            .y = self.rect.y,
            .width = width,
            .height = self.rect.height,
        };
        self.cursor_x += width + self.gap;
        return rect;
    }

    pub fn skip(self: *Row, width: f32) void {
        self.cursor_x += width;
    }
};

pub fn pad(rect: rl.Rectangle, padding: f32) rl.Rectangle {
    return rl.Rectangle{
        .x = rect.x + padding,
        .y = rect.y + padding,
        .width = rect.width - (padding * 2.0),
        .height = rect.height - (padding * 2.0),
    };
}

pub fn center(parent: rl.Rectangle, width: f32, height: f32) rl.Rectangle {
    return rl.Rectangle{
        .x = parent.x + (parent.width - width) / 2.0,
        .y = parent.y + (parent.height - height) / 2.0,
        .width = width,
        .height = height,
    };
}
