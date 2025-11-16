const std = @import("std");
const command = @import("movement/command.zig");
const MovementCommand = command.MovementCommand;

pub const protocol_version: u32 = 1;

pub const PlayerState = struct {
    x: f32,
    y: f32,
};

pub const CommandInput = union(enum) {
    movement: MovementCommand,
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
