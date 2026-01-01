const std = @import("std");

/// OwnerId represents who owns a plot
/// Chain-agnostic design - can be wallet address, ENS, NFT, or custom ID
pub const OwnerIdKind = enum {
    none,
    wallet,
    ens,
    nft,
    custom,
};

pub const OwnerId = struct {
    kind: OwnerIdKind,
    value: [64]u8 = [_]u8{0} ** 64,
    len: u8 = 0,

    pub fn init(kind: OwnerIdKind, value: []const u8) OwnerId {
        var id = OwnerId{
            .kind = kind,
            .len = @intCast(@min(value.len, 64)),
        };
        @memcpy(id.value[0..id.len], value[0..id.len]);
        return id;
    }

    pub fn none() OwnerId {
        return OwnerId{ .kind = .none };
    }

    pub fn getValue(self: OwnerId) []const u8 {
        return self.value[0..self.len];
    }

    pub fn equals(self: OwnerId, other: OwnerId) bool {
        if (self.kind != other.kind) return false;
        if (self.len != other.len) return false;
        return std.mem.eql(u8, self.getValue(), other.getValue());
    }

    pub fn format(
        self: OwnerId,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        try writer.print("{s}:", .{@tagName(self.kind)});
        if (self.len > 0) {
            const value = self.getValue();
            try writer.print("{s}", .{value});
        } else {
            try writer.writeAll("(empty)");
        }
    }
};

/// Plot represents a tile-aligned rectangle in the world that can be owned
pub const Plot = struct {
    id: u64,
    tile_x: i32,
    tile_y: i32,
    width_tiles: i32,
    height_tiles: i32,
    owner: OwnerId,

    /// Check if a tile position is within this plot's boundaries
    pub fn containsTile(self: Plot, tx: i32, ty: i32) bool {
        return tx >= self.tile_x and
            tx < self.tile_x + self.width_tiles and
            ty >= self.tile_y and
            ty < self.tile_y + self.height_tiles;
    }

    /// Check if this plot overlaps with another plot
    pub fn overlaps(self: Plot, other: Plot) bool {
        const self_right = self.tile_x + self.width_tiles;
        const self_bottom = self.tile_y + self.height_tiles;
        const other_right = other.tile_x + other.width_tiles;
        const other_bottom = other.tile_y + other.height_tiles;

        return !(self_right <= other.tile_x or
            self.tile_x >= other_right or
            self_bottom <= other.tile_y or
            self.tile_y >= other_bottom);
    }
};

/// OwnershipResolver interface - provides abstraction for ownership checks
/// Allows different implementations (offline, server-based, blockchain, etc.)
pub const OwnershipResolver = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        resolve: *const fn (ptr: *anyopaque, plot_id: u64) ?OwnerId,
        canBuild: *const fn (ptr: *anyopaque, plot_id: u64, user_owner_id: OwnerId) bool,
    };

    pub fn resolve(self: OwnershipResolver, plot_id: u64) ?OwnerId {
        return self.vtable.resolve(self.ptr, plot_id);
    }

    pub fn canBuild(self: OwnershipResolver, plot_id: u64, user_owner_id: OwnerId) bool {
        return self.vtable.canBuild(self.ptr, plot_id, user_owner_id);
    }
};

/// NullResolver - development/offline resolver that allows all operations
pub const NullResolver = struct {
    const Self = @This();

    pub fn init() Self {
        return Self{};
    }

    fn resolveImpl(_: *anyopaque, _: u64) ?OwnerId {
        return null;
    }

    fn canBuildImpl(_: *anyopaque, _: u64, _: OwnerId) bool {
        return true; // Allow building anywhere in dev mode
    }

    pub fn resolver(self: *Self) OwnershipResolver {
        return OwnershipResolver{
            .ptr = self,
            .vtable = &.{
                .resolve = resolveImpl,
                .canBuild = canBuildImpl,
            },
        };
    }
};

/// DefaultResolver - simple resolver that checks plot ownership
pub const DefaultResolver = struct {
    const Self = @This();

    plots: []const Plot,

    pub fn init(plots: []const Plot) Self {
        return Self{ .plots = plots };
    }

    fn resolveImpl(ptr: *anyopaque, plot_id: u64) ?OwnerId {
        const self: *Self = @ptrCast(@alignCast(ptr));
        for (self.plots) |plot| {
            if (plot.id == plot_id) {
                return plot.owner;
            }
        }
        return null;
    }

    fn canBuildImpl(ptr: *anyopaque, plot_id: u64, user_owner_id: OwnerId) bool {
        const self: *Self = @ptrCast(@alignCast(ptr));
        for (self.plots) |plot| {
            if (plot.id == plot_id) {
                // If plot has no owner, allow anyone to build (unowned land)
                if (plot.owner.kind == .none) return true;
                // Otherwise, user must match owner
                return plot.owner.equals(user_owner_id);
            }
        }
        // If plot doesn't exist, disallow building
        return false;
    }

    pub fn resolver(self: *Self) OwnershipResolver {
        return OwnershipResolver{
            .ptr = self,
            .vtable = &.{
                .resolve = resolveImpl,
                .canBuild = canBuildImpl,
            },
        };
    }
};

test "OwnerId creation and comparison" {
    const id1 = OwnerId.init(.wallet, "0x1234567890");
    const id2 = OwnerId.init(.wallet, "0x1234567890");
    const id3 = OwnerId.init(.wallet, "0xABCDEF");

    try std.testing.expect(id1.equals(id2));
    try std.testing.expect(!id1.equals(id3));
}

test "Plot contains tile" {
    const plot = Plot{
        .id = 1,
        .tile_x = 10,
        .tile_y = 10,
        .width_tiles = 5,
        .height_tiles = 5,
        .owner = OwnerId.none(),
    };

    try std.testing.expect(plot.containsTile(10, 10)); // Top-left corner
    try std.testing.expect(plot.containsTile(14, 14)); // Bottom-right corner (inclusive)
    try std.testing.expect(!plot.containsTile(15, 15)); // Outside
    try std.testing.expect(!plot.containsTile(9, 10)); // Left of plot
}

test "Plot overlap detection" {
    const plot1 = Plot{
        .id = 1,
        .tile_x = 0,
        .tile_y = 0,
        .width_tiles = 10,
        .height_tiles = 10,
        .owner = OwnerId.none(),
    };

    const plot2 = Plot{
        .id = 2,
        .tile_x = 5,
        .tile_y = 5,
        .width_tiles = 10,
        .height_tiles = 10,
        .owner = OwnerId.none(),
    };

    const plot3 = Plot{
        .id = 3,
        .tile_x = 20,
        .tile_y = 20,
        .width_tiles = 10,
        .height_tiles = 10,
        .owner = OwnerId.none(),
    };

    try std.testing.expect(plot1.overlaps(plot2));
    try std.testing.expect(!plot1.overlaps(plot3));
}

test "NullResolver allows all builds" {
    var null_resolver = NullResolver.init();
    const resolver = null_resolver.resolver();

    try std.testing.expect(resolver.canBuild(1, OwnerId.none()));
    try std.testing.expect(resolver.canBuild(1, OwnerId.init(.wallet, "0x123")));
}

test "DefaultResolver checks ownership" {
    const plots = [_]Plot{
        .{
            .id = 1,
            .tile_x = 0,
            .tile_y = 0,
            .width_tiles = 10,
            .height_tiles = 10,
            .owner = OwnerId.init(.wallet, "0xALICE"),
        },
        .{
            .id = 2,
            .tile_x = 10,
            .tile_y = 0,
            .width_tiles = 10,
            .height_tiles = 10,
            .owner = OwnerId.none(), // Unowned plot
        },
    };

    var default_resolver = DefaultResolver.init(&plots);
    const resolver = default_resolver.resolver();

    const alice = OwnerId.init(.wallet, "0xALICE");
    const bob = OwnerId.init(.wallet, "0xBOB");

    // Alice can build on her plot
    try std.testing.expect(resolver.canBuild(1, alice));
    // Bob cannot build on Alice's plot
    try std.testing.expect(!resolver.canBuild(1, bob));
    // Anyone can build on unowned plot
    try std.testing.expect(resolver.canBuild(2, alice));
    try std.testing.expect(resolver.canBuild(2, bob));
}
