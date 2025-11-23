const std = @import("std");
const command = @import("movement/command.zig");
const MovementCommand = command.MovementCommand;

pub const network = @import("network.zig");

pub const PlayerState = struct {
    x: f32,
    y: f32,
};

pub const CommandInput = union(enum) {
    movement: MovementCommand,
};

pub const TerrainType = enum(u8) {
    Grass = 0,
    Rock = 1,
    Water = 2,
    Road = 3,
};

const WorldError = error{
    IndexOutOfBounds,
    MaxPlayersReached,
};

const Map = struct {
    const Self = @This();

    width: f32,
    height: f32,
};

pub const World = struct {
    pub const WIDTH: f32 = 2000;
    pub const HEIGHT: f32 = 2000;
    pub const TILES_X: i32 = 50;
    pub const TILES_Y: i32 = 50;

    pub fn getTileAtPosition(x: f32, y: f32) TerrainType {
        // Clamp position to world bounds
        const clamped_x = std.math.clamp(x, 0, WIDTH);
        const clamped_y = std.math.clamp(y, 0, HEIGHT);

        // Convert world position to tile coordinates
        const tx: i32 = @intFromFloat((clamped_x / WIDTH) * @as(f32, @floatFromInt(TILES_X)));
        const ty: i32 = @intFromFloat((clamped_y / HEIGHT) * @as(f32, @floatFromInt(TILES_Y)));

        // Apply same distance-based logic as main.zig::drawWorldTiles
        const center_x = TILES_X / 2;
        const center_y = TILES_Y / 2;
        const dx = tx - center_x;
        const dy = ty - center_y;
        const dist_sq = dx * dx + dy * dy;

        if (dist_sq < 16) return .Water;
        if (dist_sq < 25) return .Rock;
        return .Grass;
    }

    pub fn isWalkable(terrain: TerrainType) bool {
        return terrain == .Grass or terrain == .Road;
    }

    pub fn checkCollision(x: f32, y: f32, w: f32, h: f32, direction: command.MoveDirection) bool {
        // Define hitbox corners
        const left = x;
        const right = x + w;
        const top = y;
        const bottom = y + h;

        // Check points based on direction
        switch (direction) {
            .Up => {
                // Check top-left and top-right
                if (!isWalkable(getTileAtPosition(left, top)) or
                    !isWalkable(getTileAtPosition(right, top))) return true;
            },
            .Down => {
                // Check bottom-left and bottom-right
                if (!isWalkable(getTileAtPosition(left, bottom)) or
                    !isWalkable(getTileAtPosition(right, bottom))) return true;
            },
            .Left => {
                // Check top-left and bottom-left
                if (!isWalkable(getTileAtPosition(left, top)) or
                    !isWalkable(getTileAtPosition(left, bottom))) return true;
            },
            .Right => {
                // Check top-right and bottom-right
                if (!isWalkable(getTileAtPosition(right, top)) or
                    !isWalkable(getTileAtPosition(right, bottom))) return true;
            },
        }
        return false;
    }
};

pub const Room = struct {
    const Self = @This();

    players: []*PlayerState,
    width: f32,
    height: f32,

    // //
    // keys: []u64, // user IDs
    // slots: []u16, // assigned room index
    // states: []u8, // 0=EMPTY, 1=OCCUPIED, 2=TOMBSTONE

    pub fn init(_: usize) Self {
        // var players = [capacity]*PlayerState{};
        return Self{
            // .players = players[0..],
            // .width = 100.0,
            // .height = 100.0,
        };
    }

    pub fn calculatePlayerPosition(self: *Self, move: MovementCommand, idx: usize) WorldError!void {
        if (idx >= self.players.len) {
            return WorldError.IndexOutOfBounds;
        }
        var x = self.players[idx].x;
        var y = self.players[idx].y;
        switch (move.direction) {
            .Up => {
                y -= move.delta * move.speed;
            },
            .Down => {
                y += move.delta * move.speed;
            },
            .Left => {
                x -= move.delta * move.speed;
            },
            .Right => {
                x += move.delta * move.speed;
            },
        }
        if (x < 0.0 or x > self.width or y < 0.0 or y > self.height) {
            return WorldError.IndexOutOfBounds;
        }

        self.players[idx].x = x;
        self.players[idx].y = y;
    }
};

test "player move right" {
    const move = MovementCommand{
        .direction = .Right,
        .speed = 1.0,
        .delta = 0.5,
    };
    var player = PlayerState{
        .x = 0.0,
        .y = 0.0,
    };
    var players = [_]*PlayerState{&player};
    var world = Room{
        .players = players[0..],
        .width = 100.0,
        .height = 100.0,
    };
    const idx: usize = 0;
    try world.calculatePlayerPosition(move, idx);
    std.debug.print("pos {d}-{d}\n", .{ world.players[idx].x, world.players[idx].y });
    try std.testing.expectEqual(0.5, world.players[idx].x);
}

test "player move out of right boundary" {
    const move = MovementCommand{
        .direction = .Right,
        .speed = 1.0,
        .delta = 0.5,
    };
    var player = PlayerState{
        .x = 100.0,
        .y = 0.0,
    };
    var players = [_]*PlayerState{&player};
    var world = Room{
        .players = players[0..],
        .width = 100.0,
        .height = 100.0,
    };
    const idx: usize = 0;
    try std.testing.expectError(WorldError.IndexOutOfBounds, world.calculatePlayerPosition(move, idx));
}
