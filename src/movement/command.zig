pub const MovementCommand = struct {
    direction: MoveDirection,
    speed: f32,
    delta: f32,
};

pub const MoveDirection = enum {
    Up,
    Down,
    Left,
    Right,
};
