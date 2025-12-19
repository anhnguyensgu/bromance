const std = @import("std");
const MovementCommand = @import("../movement/command.zig").MovementCommand;
const MoveDirection = @import("../movement/command.zig").MoveDirection;
const PingPayload = @import("../ping/command.zig").PingPayload;
const Vec2 = @import("../game/math/vec2.zig").Vec2;
const shared = @import("../shared.zig");
const network = shared.network;
const ClientGameState = @import("game_state.zig").ClientGameState;

// Heartbeat interval - must be less than server's CLIENT_TIMEOUT (30s)
const HEARTBEAT_INTERVAL_NS: i64 = 10 * std.time.ns_per_s; // 10 seconds

pub const UdpClient = struct {
    sock: std.posix.socket_t,
    server_addr: std.net.Address,
    recv_buf: [2048]u8 = undefined,

    state: *ClientGameState,
    running: std.atomic.Value(bool) = std.atomic.Value(bool).init(true),

    session_id: u32 = 0,
    world: shared.World,
    last_ping_ns: i64 = 0,

    pub fn init(state: *ClientGameState, world: shared.World, config: struct { server_ip: []const u8, server_port: u16 }) !UdpClient {
        const sock = try std.posix.socket(std.posix.AF.INET, std.posix.SOCK.DGRAM | std.posix.SOCK.NONBLOCK, 0);
        errdefer std.posix.close(sock);

        const addr = try std.net.Address.parseIp4(config.server_ip, config.server_port);

        return UdpClient{
            .sock = sock,
            .server_addr = addr,
            .state = state,
            .session_id = state.session_id,
            .world = world,
        };
    }

    pub fn deinit(self: *UdpClient) void {
        self.running.store(false, .release);
        std.posix.close(self.sock);
    }

    pub fn run(self: *UdpClient) !void {
        defer self.sendLeave() catch {};
        var buf: [network.packet_header_size + network.max_payload_size]u8 = undefined;

        // Initial ping
        try self.sendPing();
        self.last_ping_ns = @intCast(std.time.nanoTimestamp());

        while (self.running.load(.acquire)) {
            const now: i64 = @intCast(std.time.nanoTimestamp());

            // 1. Receive Packets
            var addr_storage: std.posix.sockaddr.storage = undefined;
            var addr_len: std.posix.socklen_t = @sizeOf(std.posix.sockaddr.storage);

            const received = std.posix.recvfrom(
                self.sock,
                &self.recv_buf,
                0,
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
            if (self.state.getLatestMove()) |move| {
                var packet = network.Packet{
                    .header = .{
                        .msg_type = .move,
                        .flags = .{ .reliable = true },
                        .sequence = move.seq,
                        .session_id = self.session_id,
                        .ack = 0,
                        .payload_len = @intCast(MovementCommand.size()),
                    },
                    .payload = .{ .move = move.cmd },
                };

                try packet.encode(&buf);
                const len = network.packet_header_size + packet.header.payload_len;
                _ = try std.posix.sendto(self.sock, buf[0..len], 0, &self.server_addr.any, self.server_addr.getOsSockLen());
            }

            // 3. Send heartbeat ping to keep connection alive (even when idle)
            if (now - self.last_ping_ns > HEARTBEAT_INTERVAL_NS) {
                try self.sendPing();
                self.last_ping_ns = now;
            }

            // Sleep a bit to avoid burning CPU (1ms)
            std.posix.nanosleep(0, 1_000_000);
        }
    }

    fn handlePacket(self: *UdpClient, packet: network.Packet) !void {
        switch (packet.payload) {
            .state_update => |state| {
                const server_pos = Vec2{ .x = state.x, .y = state.y };
                const corrected = self.state.reconcileState(packet.header.ack, server_pos, self.world);
                self.state.storeSnapshot(corrected);
            },
            .all_players_state => |all_players| {
                // Delegate all logic to ClientGameState - uses double buffering internally
                try self.state.handleAllPlayersUpdate(
                    all_players.players[0..all_players.count],
                    self.session_id,
                    packet.header.ack,
                    self.world,
                );
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

    pub fn sendLeave(self: *UdpClient) !void {
        var buf: [128]u8 = undefined;
        var packet = network.Packet{
            .header = .{
                .msg_type = .leave,
                .session_id = self.session_id,
                .payload_len = @intCast(network.LeavePayload.size()),
            },
            .payload = .{ .leave = .{ .reason = 0 } },
        };
        try packet.encode(&buf);
        const len = network.packet_header_size + packet.header.payload_len;
        _ = try std.posix.sendto(self.sock, buf[0..len], 0, &self.server_addr.any, self.server_addr.getOsSockLen());
    }
};

pub fn applyMoveToVector(pos: *Vec2, move: MovementCommand, world: shared.World) void {
    const move_amount = move.speed * move.delta;

    var new_pos = pos.*;
    switch (move.direction) {
        .Up => new_pos.y -= move_amount,
        .Down => new_pos.y += move_amount,
        .Left => new_pos.x -= move_amount,
        .Right => new_pos.x += move_amount,
    }

    const PLAYER_SIZE: f32 = 32.0;
    const max_x = @max(0.0, world.width - PLAYER_SIZE);
    const max_y = @max(0.0, world.height - PLAYER_SIZE);

    // Clamp so the whole player stays inside the world
    new_pos.x = std.math.clamp(new_pos.x, 0.0, max_x);
    new_pos.y = std.math.clamp(new_pos.y, 0.0, max_y);

    // Check collision at new position
    const collision = world.checkCollision(new_pos.x, new_pos.y, PLAYER_SIZE, PLAYER_SIZE, move.direction);

    if (!collision) {
        pos.* = new_pos;
    }
}

fn lerp(a: f32, b: f32, t: f32) f32 {
    return a + (b - a) * t;
}
