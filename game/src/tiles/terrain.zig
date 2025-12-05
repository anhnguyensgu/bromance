const std = @import("std");

pub const TerrainType = enum(u8) {
    Grass = 0,
    Rock = 1,
    Water = 2,
    Road = 3,
};
