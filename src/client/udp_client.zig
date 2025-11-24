const std = @import("std");

const rl = @import("raylib");

const MovementCommand = @import("../movement/command.zig").MovementCommand;
const MoveDirection = @import("../movement/command.zig").MoveDirection;
const PingPayload = @import("../ping/command.zig").PingPayload;
const shared = @import("../shared.zig");
const network = shared.network;
const MAX_PENDING_MOVES: usize = 32;
const MAX_SNAPSHOTS: usize = 32;
const INTERPOLATION_DELAY_NS: i64 = 45_000_000;

const PendingMove = struct {
    seq: u32,
    cmd: MovementCommand,
};

const Snapshot = struct {
    time_ns: i64,
    pos: rl.Vector2,
};

pub const OtherPlayerState = struct {
    pos: rl.Vector2,
    last_update_ns: i64,
    dir: MoveDirection = .Down, // Track facing direction for animation
    is_moving: bool = false, // Track if player is currently moving
};

pub const UdpClient = struct {
    sock: std.posix.socket_t,
    server_addr: std.net.Address,
    recv_buf: [2048]u8 = undefined, // Increased for all_players_state packets
    sequence: u32 = 0,
    pending_moves: [MAX_PENDING_MOVES]PendingMove = undefined,
    pending_count: usize = 0,
    snapshots: [MAX_SNAPSHOTS]Snapshot = undefined,
    snapshot_count: usize = 0,
    session_id: u32 = 0,
    other_players: std.AutoHashMap(u32, OtherPlayerState),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, config: struct { server_ip: []const u8, server_port: u16 }) !UdpClient {
        const sock = try std.posix.socket(std.posix.AF.INET, std.posix.SOCK.DGRAM, 0);
        errdefer std.posix.close(sock);

        const addr = try std.net.Address.parseIp4(config.server_ip, config.server_port);

        // Generate random session ID using timestamp and random bits
        var prng = std.Random.DefaultPrng.init(@intCast(std.time.nanoTimestamp()));
        const random_session_id = prng.random().int(u32);

        return UdpClient{
            .sock = sock,
            .server_addr = addr,
            .session_id = random_session_id,
            .other_players = std.AutoHashMap(u32, OtherPlayerState).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *UdpClient) void {
        self.other_players.deinit();
        std.posix.close(self.sock);
    }

    pub fn sendPing(self: *UdpClient) !void {
        const payload = network.PacketPayload{ .ping = PingPayload{ .timestamp = @as(u64, @intCast(std.time.timestamp())) } };
        const header = network.PacketHeader{
            .msg_type = .ping,
            .flags = .{ .reliable = true, .requires_ack = true },
            .session_id = self.session_id,
            .sequence = 0,
            .ack = 0,
            .payload_len = @intCast(PingPayload.size()),
        };
        var buffer: [network.packet_header_size + PingPayload.size()]u8 = undefined;
        const packet = network.Packet{ .header = header, .payload = payload };
        try packet.encode(buffer[0..]);
        const len = network.packet_header_size + PingPayload.size();
        _ = try std.posix.sendto(self.sock, buffer[0..len], 0, &self.server_addr.any, self.server_addr.getOsSockLen());
    }

    pub fn sendMove(self: *UdpClient, move: MovementCommand) !void {
        const payload = network.PacketPayload{ .move = move };
        const header = network.PacketHeader{
            .msg_type = .move,
            .flags = .{ .reliable = true },
            .session_id = self.session_id,
            .sequence = self.sequence + 1,
            .ack = 0,
            .payload_len = @intCast(MovementCommand.size()),
        };
        var buffer: [network.packet_header_size + MovementCommand.size()]u8 = undefined;
        const packet = network.Packet{ .header = header, .payload = payload };
        try packet.encode(buffer[0..]);
        const len = network.packet_header_size + MovementCommand.size();
        _ = try std.posix.sendto(self.sock, buffer[0..len], 0, &self.server_addr.any, self.server_addr.getOsSockLen());
        self.sequence = header.sequence;
        self.recordPending(.{ .seq = header.sequence, .cmd = move });
    }

    pub fn pollState(self: *UdpClient, world: shared.World) !void {
        var addr_storage: std.posix.sockaddr.storage = undefined;
        var addr_len: std.posix.socklen_t = @sizeOf(std.posix.sockaddr.storage);
        const received = std.posix.recvfrom(
            self.sock,
            &self.recv_buf,
            std.posix.MSG.DONTWAIT,
            @ptrCast(&addr_storage),
            &addr_len,
        ) catch |err| {
            if (err == error.WouldBlock) return;
            std.debug.print("recv error: {s}\n", .{@errorName(err)});
            return;
        };

        const packet = network.Packet.decode(self.recv_buf[0..received]) catch |err| {
            std.debug.print("decode error: {s}\n", .{@errorName(err)});
            return;
        };
        switch (packet.payload) {
            .state_update => |state| {
                const corrected = self.reconcileState(packet.header.ack, state, world);
                self.storeSnapshot(corrected);
                return;
            },
            .all_players_state => |all_players| {
                const now: i64 = @intCast(std.time.nanoTimestamp());
                var found_self = false;
                var moving_player = std.AutoHashMap(u32, bool).init(self.allocator);
                defer moving_player.deinit();

                for (all_players.players[0..all_players.count]) |player_info| {
                    if (player_info.session_id == self.session_id) {
                        // This is our own position from the server - use for reconciliation
                        const state = network.StatePayload{
                            .x = player_info.x,
                            .y = player_info.y,
                            .timestamp_ns = now,
                        };
                        const corrected = self.reconcileState(packet.header.ack, state, world);
                        self.storeSnapshot(corrected);
                        found_self = true;
                    } else {
                        // Other player - calculate direction and movement state
                        const new_pos = rl.Vector2{ .x = player_info.x, .y = player_info.y };

                        // Get previous state to calculate direction and movement
                        var dir: MoveDirection = .Down; // Default
                        var is_moving = false;

                        if (self.other_players.get(player_info.session_id)) |prev_state| {
                            const dx = new_pos.x - prev_state.pos.x;
                            const dy = new_pos.y - prev_state.pos.y;
                            const movement_threshold: f32 = 0.25;
                            const stale_ns: i64 = 250_000_000; // 250ms
                            const fresh_update = (now - prev_state.last_update_ns) < stale_ns;
                            const moved_enough = (@abs(dx) > movement_threshold) or (@abs(dy) > movement_threshold);

                            // Treat player as moving only when the last update is recent and distance jumped enough
                            is_moving = fresh_update and moved_enough;
                            if (is_moving) {
                                try moving_player.put(player_info.session_id, true);

                                // Determine direction based on largest movement component
                                if (@abs(dx) > @abs(dy)) {
                                    dir = if (dx > 0) .Right else .Left;
                                } else {
                                    dir = if (dy > 0) .Down else .Up;
                                }
                            } else {
                                dir = prev_state.dir; // Keep previous direction if not moving
                            }
                        }
                        try self.other_players.put(player_info.session_id, .{
                            .pos = new_pos,
                            .last_update_ns = now,
                            .dir = dir,
                            .is_moving = is_moving,
                        });
                    }
                }

                var it = self.other_players.iterator();
                while (it.next()) |entry| {
                    if (moving_player.contains(entry.key_ptr.*)) continue;
                    entry.value_ptr.is_moving = false;
                }
                std.debug.print("moving player {d}\n", .{moving_player.count()});

                // If we didn't find ourselves, we might have just connected
                if (!found_self) {
                    std.debug.print("Warning: own session_id {d} not in all_players_state\n", .{self.session_id});
                }
                return;
            },
            else => return,
        }
    }

    pub fn sampleInterpolated(self: *UdpClient) ?rl.Vector2 {
        if (self.snapshot_count == 0) return null;
        const now: i64 = @intCast(std.time.nanoTimestamp());
        const target = now - INTERPOLATION_DELAY_NS;
        if (self.snapshot_count == 1 or target <= self.snapshots[0].time_ns) {
            return self.snapshots[0].pos;
        }
        var idx: usize = 1;
        while (idx < self.snapshot_count and self.snapshots[idx].time_ns < target) : (idx += 1) {}
        if (idx == self.snapshot_count) {
            return self.snapshots[self.snapshot_count - 1].pos;
        }
        const after = self.snapshots[idx];
        const before = self.snapshots[idx - 1];
        const span = after.time_ns - before.time_ns;
        if (span <= 0) return after.pos;
        const t = @as(f32, @floatFromInt(target - before.time_ns)) / @as(f32, @floatFromInt(span));
        return rl.Vector2{
            .x = lerp(before.pos.x, after.pos.x, std.math.clamp(t, 0.0, 1.0)),
            .y = lerp(before.pos.y, after.pos.y, std.math.clamp(t, 0.0, 1.0)),
        };
    }

    fn reconcileState(self: *UdpClient, ack: u32, state: network.StatePayload, world: shared.World) rl.Vector2 {
        self.dropAcknowledged(ack);
        var corrected = rl.Vector2{ .x = state.x, .y = state.y };
        var idx: usize = 0;
        while (idx < self.pending_count) : (idx += 1) {
            const entry = self.pending_moves[idx];
            applyMoveToVector(&corrected, entry.cmd, world);
        }
        return corrected;
    }

    fn dropAcknowledged(self: *UdpClient, ack: u32) void {
        var idx: usize = 0;
        while (idx < self.pending_count) {
            if (self.pending_moves[idx].seq <= ack) {
                var shift_idx = idx;
                while (shift_idx + 1 < self.pending_count) : (shift_idx += 1) {
                    self.pending_moves[shift_idx] = self.pending_moves[shift_idx + 1];
                }
                self.pending_count -= 1;
            } else {
                idx += 1;
            }
        }
    }

    fn recordPending(self: *UdpClient, entry: PendingMove) void {
        if (self.pending_count == MAX_PENDING_MOVES) {
            var i: usize = 0;
            while (i + 1 < self.pending_count) : (i += 1) {
                self.pending_moves[i] = self.pending_moves[i + 1];
            }
            self.pending_count -= 1;
        }
        self.pending_moves[self.pending_count] = entry;
        self.pending_count += 1;
    }

    fn storeSnapshot(self: *UdpClient, pos: rl.Vector2) void {
        if (self.snapshot_count == MAX_SNAPSHOTS) {
            var i: usize = 0;
            while (i + 1 < self.snapshot_count) : (i += 1) {
                self.snapshots[i] = self.snapshots[i + 1];
            }
            self.snapshot_count -= 1;
        }
        self.snapshots[self.snapshot_count] = .{
            .time_ns = @intCast(std.time.nanoTimestamp()),
            .pos = pos,
        };
        self.snapshot_count += 1;
    }
};

pub fn applyMoveToVector(pos: *rl.Vector2, move: MovementCommand, world: shared.World) void {
    const move_amount = move.speed * move.delta;

    var new_pos = pos.*;
    switch (move.direction) {
        .Up => new_pos.y -= move_amount,
        .Down => new_pos.y += move_amount,
        .Left => new_pos.x -= move_amount,
        .Right => new_pos.x += move_amount,
    }

    // Clamp to world bounds
    new_pos.x = std.math.clamp(new_pos.x, 0.0, world.width);
    new_pos.y = std.math.clamp(new_pos.y, 0.0, world.height);

    // Check collision at new position (check leading corners)
    const PLAYER_SIZE: f32 = 32.0; // Must match main.zig
    const collision = world.checkCollision(new_pos.x, new_pos.y, PLAYER_SIZE, PLAYER_SIZE, move.direction);

    // Only apply movement if no collision
    if (!collision) {
        pos.* = new_pos;
    }
}

fn lerp(a: f32, b: f32, t: f32) f32 {
    return a + (b - a) * t;
}
