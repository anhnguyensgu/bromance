const Vec2 = @import("../math/vec2.zig").Vec2;
const MoveDirection = @import("../../movement/command.zig").MoveDirection;

pub const Player = struct {
    pos: Vec2,
    size: Vec2,
    dir: MoveDirection = .Down,
    is_moving: bool = false,

    pub fn init(pos: Vec2, size: Vec2) Player {
        return .{
            .pos = pos,
            .size = size,
        };
    }

    pub fn setMovement(self: *Player, dir: MoveDirection, is_moving: bool) void {
        self.is_moving = is_moving;
        if (is_moving) {
            self.dir = dir;
        }
    }
};
