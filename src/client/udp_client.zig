const std = @import("std");
const rl = @import("raylib");

const MovementCommand = @import("../movement/command.zig").MovementCommand;
const MoveDirection = @import("../movement/command.zig").MoveDirection;
const PingPayload = @import("../ping/command.zig").PingPayload;
const shared = @import("../shared.zig");
const network = shared.network;
const ClientGameState = @import("game_state.zig").ClientGameState;

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

    state: *ClientGameState,
    running: std.atomic.Value(bool) = std.atomic.Value(bool).init(true),

    // We need session_id back
    session_id: u32 = 0,

    // We need world for reconciliation
    world: shared.World,

    pub fn init(state: *ClientGameState, world: shared.World, config: struct { server_ip: []const u8, server_port: u16 }) !UdpClient {
        const sock = try std.posix.socket(std.posix.AF.INET, std.posix.SOCK.DGRAM | std.posix.SOCK.NONBLOCK, 0);
        errdefer std.posix.close(sock);

        const addr = try std.net.Address.parseIp4(config.server_ip, config.server_port);

        return UdpClient{
            .sock = sock,
            .server_addr = addr,
            .state = state,
            .session_id = state.session_id, // Get session_id from ClientGameState
            .world = world,
        };
    }

    pub fn deinit(self: *UdpClient) void {
        self.running.store(false, .release);
        std.posix.close(self.sock);
    }

    pub fn run(self: *UdpClient) !void {
        var buf: [network.packet_header_size + network.max_payload_size]u8 = undefined;

        // Initial ping
        try self.sendPing();

        while (self.running.load(.acquire)) {
            // 1. Receive Packets
            var addr_storage: std.posix.sockaddr.storage = undefined;
            var addr_len: std.posix.socklen_t = @sizeOf(std.posix.sockaddr.storage);

            const received = std.posix.recvfrom(
                self.sock,
                &self.recv_buf,
                0, // No flags needed if socket is non-blocking
                @ptrCast(&addr_storage),
                &addr_len,
            ) catch |err| blk: {
                if (err == error.WouldBlock) break :blk @as(usize, 0);
                break :blk @as(usize, 0);
            };

            if (received > 0) {
                const packet = network.Packet.decode(self.recv_buf[0..received]) catch {
                    continue;
                };
                try self.handlePacket(packet);
            }

            // 2. Send Pending Moves
            // We need to peek at the latest move to send
            if (self.state.getLatestMove()) |move| {
                // Send move packet
                var packet = network.Packet{
                    .header = .{
                        .msg_type = .move,
                        .flags = .{ .reliable = true },
                        .sequence = move.seq,
                        .session_id = self.session_id,
                        .ack = 0, // Server will fill this
                        .payload_len = @intCast(MovementCommand.size()),
                    },
                    .payload = .{ .move = move.cmd },
                };

                try packet.encode(&buf);
                const len = network.packet_header_size + packet.header.payload_len;
                _ = try std.posix.sendto(self.sock, buf[0..len], 0, &self.server_addr.any, self.server_addr.getOsSockLen());
            }

            // Sleep a bit to avoid burning CPU (1ms)
            // Sleep a bit to avoid burning CPU (1ms)
            std.posix.nanosleep(0, 1_000_000);
        }
    }

    fn handlePacket(self: *UdpClient, packet: network.Packet) !void {
        switch (packet.payload) {
            .state_update => |state| {
                const server_pos = rl.Vector2{ .x = state.x, .y = state.y };
                const corrected = self.state.reconcileState(packet.header.ack, server_pos, self.world);
                self.state.storeSnapshot(corrected);
            },
            .all_players_state => |all_players| {
                const now: i64 = @intCast(std.time.nanoTimestamp());
                var found_self = false;
                var moving_player = std.AutoHashMap(u32, bool).init(self.state.allocator);
                defer moving_player.deinit();

                for (all_players.players[0..all_players.count]) |player_info| {
                    if (player_info.session_id == self.session_id) {
                        // This is our own position from the server - use for reconciliation
                        const server_pos = rl.Vector2{ .x = player_info.x, .y = player_info.y };
                        const corrected = self.state.reconcileState(packet.header.ack, server_pos, self.world);
                        self.state.storeSnapshot(corrected);
                        found_self = true;
                    } else {
                        // Other player
                        // Let's read previous state first
                        var dir: MoveDirection = .Down;
                        var is_moving = false;

                        if (self.state.getOtherPlayer(player_info.session_id)) |prev| {
                            const dx = player_info.x - prev.pos.x;
                            const dy = player_info.y - prev.pos.y;
                            const movement_threshold: f32 = 0.25;
                            const stale_ns: i64 = 250_000_000; // 250ms
                            const fresh_update = (now - prev.last_update_ns) < stale_ns;
                            const moved_enough = (@abs(dx) > movement_threshold) or (@abs(dy) > movement_threshold);

                            is_moving = fresh_update and moved_enough;

                            if (is_moving) {
                                try moving_player.put(player_info.session_id, true);
                                if (@abs(dx) > @abs(dy)) {
                                    dir = if (dx > 0) .Right else .Left;
                                } else {
                                    dir = if (dy > 0) .Down else .Up;
                                }
                            } else {
                                dir = prev.dir;
                            }
                        }

                        try self.state.updateOtherPlayer(player_info.session_id, .{ .x = player_info.x, .y = player_info.y }, dir, is_moving);
                    }
                }

                var it = self.state.other_players.iterator();
                while (it.next()) |entry| {
                    if (moving_player.contains(entry.key_ptr.*)) continue;
                    entry.value_ptr.is_moving = false;
                }

                // If we didn't find ourselves, we might have just connected
                if (!found_self) {
                    std.debug.print("Warning: own session_id {d} not in all_players_state\n", .{self.session_id});
                }
            },
            else => {},
        }
    }

    pub fn sendPing(self: *UdpClient) !void {
        var buf: [128]u8 = undefined;
        var packet = network.Packet{
            .header = .{
                .msg_type = .ping,
                .session_id = self.session_id,
                .payload_len = @intCast(PingPayload.size()),
            },
            .payload = .{ .ping = .{ .timestamp = @intCast(std.time.milliTimestamp()) } },
        };
        try packet.encode(&buf);
        const len = network.packet_header_size + packet.header.payload_len;
        _ = try std.posix.sendto(self.sock, buf[0..len], 0, &self.server_addr.any, self.server_addr.getOsSockLen());
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
