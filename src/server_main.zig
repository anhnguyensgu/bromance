const std = @import("std");
const posix = std.posix;

const shared = @import("shared.zig");
const network = shared.network;

const Client = struct {
    address: std.net.Address,
    state: shared.PlayerState,
};

const UdpEchoServer = struct {
    sock: posix.socket_t,
    buffer: [1024]u8 = undefined,
    clients: std.AutoHashMap(u32, Client),
    allocator: std.mem.Allocator,
    world: shared.World,

    pub fn init(allocator: std.mem.Allocator, bind_port: u16) !UdpEchoServer {
        const listen_address = try std.net.Address.parseIp4("0.0.0.0", bind_port);
        const sock = try posix.socket(listen_address.any.family, posix.SOCK.DGRAM, posix.IPPROTO.UDP);

        var enable: c_int = 1;
        try posix.setsockopt(sock, posix.SOL.SOCKET, posix.SO.REUSEADDR, std.mem.asBytes(&enable));
        try posix.setsockopt(sock, posix.SOL.SOCKET, posix.SO.REUSEPORT, std.mem.asBytes(&enable));
        try posix.bind(sock, &listen_address.any, listen_address.getOsSockLen());

        // Load world data for collision detection
        const world = try shared.World.loadFromFile(allocator, "assets/world.json");

        return .{
            .sock = sock,
            .clients = std.AutoHashMap(u32, Client).init(allocator),
            .allocator = allocator,
            .world = world,
        };
    }

    pub fn deinit(self: *UdpEchoServer) void {
        self.world.deinit(self.allocator);
        self.clients.deinit();
        posix.close(self.sock);
    }

    pub fn boundPort(self: *const UdpEchoServer) !u16 {
        var addr_storage: posix.sockaddr.storage = undefined;
        var addr_len: posix.socklen_t = @sizeOf(posix.sockaddr.storage);
        try posix.getsockname(self.sock, @ptrCast(&addr_storage), &addr_len);
        const addr = std.net.Address.initPosix(@ptrCast(@alignCast(&addr_storage)));
        return addr.getPort();
    }

    pub fn run(self: *UdpEchoServer) !void {
        while (true) {
            try self.handleOnce();
        }
    }

    pub fn handleOnce(self: *UdpEchoServer) !void {
        try self.handleOnceInternal(0);
    }

    fn handleOnceNonBlocking(self: *UdpEchoServer) !void {
        try self.handleOnceInternal(posix.MSG.DONTWAIT);
    }

    fn handleOnceInternal(self: *UdpEchoServer, recv_flags: i32) !void {
        var client_addr_storage: posix.sockaddr.storage = undefined;
        var client_addr_len: posix.socklen_t = @sizeOf(posix.sockaddr.storage);
        const received = posix.recvfrom(
            self.sock,
            &self.buffer,
            @intCast(recv_flags),
            @ptrCast(&client_addr_storage),
            &client_addr_len,
        ) catch |err| {
            if (err == error.WouldBlock) return err;
            return err;
        };

        const addr = std.net.Address.initPosix(
            @ptrCast(@alignCast(&client_addr_storage)),
        );

        const payload = self.buffer[0..received];
        const packet = try network.Packet.decode(payload);
        const ack_seq = packet.header.sequence;
        const session_id = packet.header.session_id;

        // Get or create client
        const res = try self.clients.getOrPut(session_id);
        if (!res.found_existing) {
            res.value_ptr.* = .{
                .address = addr,
                .state = .{ .x = 0, .y = 0 },
            };
            std.debug.print("New player connected: session_id={d}\n", .{session_id});
        }
        // Update address in case it changed (e.g. NAT)
        res.value_ptr.address = addr;
        const client = res.value_ptr;

        switch (packet.payload) {
            .ping => |p| {
                std.debug.print("ping payload timestamp: {d}\n", .{p.timestamp});
                try self.broadcastAllPlayers(ack_seq);
            },
            .move => |m| {
                // std.debug.print("move payload direction: {any}\n", .{m.direction});
                self.integrateMove(m, &client.state);
                // Broadcast all players to all clients (includes reconciliation data)
                try self.broadcastAllPlayers(ack_seq);
            },
            .state_update, .all_players_state => {},
        }
    }

    fn broadcastAllPlayers(self: *UdpEchoServer, ack_seq: u32) !void {
        // Build all players payload once
        var all_players: network.AllPlayersPayload = undefined;
        all_players.count = 0;

        var it = self.clients.iterator();
        while (it.next()) |entry| {
            if (all_players.count >= network.MAX_PLAYERS) break;
            const session_id = entry.key_ptr.*;
            const client = entry.value_ptr.*;
            all_players.players[all_players.count] = .{
                .session_id = session_id,
                .x = client.state.x,
                .y = client.state.y,
            };
            all_players.count += 1;
        }

        // Send to all clients (each client will extract their own position for reconciliation)
        var dest_it = self.clients.iterator();
        while (dest_it.next()) |dest_entry| {
            const dest_client = dest_entry.value_ptr;
            try self.sendAllPlayers(&dest_client.address, ack_seq, all_players);
        }
    }

    fn integrateMove(self: *UdpEchoServer, move: network.MovePayload, pos: *shared.PlayerState) void {
        const PLAYER_SIZE: f32 = 32.0; // Must match client
        const move_amount = move.speed * move.delta;

        // Calculate new position
        var new_pos = pos.*;
        switch (move.direction) {
            .Up => new_pos.y -= move_amount,
            .Down => new_pos.y += move_amount,
            .Left => new_pos.x -= move_amount,
            .Right => new_pos.x += move_amount,
        }

        // Clamp to world bounds
        new_pos.x = std.math.clamp(new_pos.x, 0.0, self.world.width);
        new_pos.y = std.math.clamp(new_pos.y, 0.0, self.world.height);

        // Check collision
        const collision = self.world.checkBuildingCollision(new_pos.x, new_pos.y, PLAYER_SIZE, PLAYER_SIZE);

        // Only apply movement if no collision
        if (!collision) {
            pos.* = new_pos;
        }
    }

    fn sendState(self: *UdpEchoServer, addr: *const std.net.Address, ack_seq: u32, state: shared.PlayerState) !void {
        const payload = network.PacketPayload{ .state_update = network.StatePayload{
            .x = state.x,
            .y = state.y,
            .timestamp_ns = @intCast(std.time.nanoTimestamp()),
        } };
        const header = network.PacketHeader{
            .msg_type = .state_update,
            .flags = .{ .reliable = true },
            .session_id = 0,
            .sequence = 0,
            .ack = ack_seq,
            .payload_len = @intCast(network.StatePayload.size()),
        };
        var buffer: [network.packet_header_size + network.StatePayload.size()]u8 = undefined;
        const packet = network.Packet{ .header = header, .payload = payload };
        try packet.encode(buffer[0..]);
        const len = network.packet_header_size + network.StatePayload.size();
        _ = try posix.sendto(self.sock, buffer[0..len], 0, &addr.any, addr.getOsSockLen());
    }

    fn sendAllPlayers(self: *UdpEchoServer, addr: *const std.net.Address, ack_seq: u32, all_players: network.AllPlayersPayload) !void {
        const payload = network.PacketPayload{ .all_players_state = all_players };
        const header = network.PacketHeader{
            .msg_type = .all_players_state,
            .flags = .{ .reliable = true },
            .session_id = 0,
            .sequence = 0,
            .ack = ack_seq,
            .payload_len = @intCast(network.AllPlayersPayload.size()),
        };
        var buffer: [network.packet_header_size + network.AllPlayersPayload.size()]u8 = undefined;
        const packet = network.Packet{ .header = header, .payload = payload };
        try packet.encode(buffer[0..]);
        const len = network.packet_header_size + network.AllPlayersPayload.size();
        _ = try posix.sendto(self.sock, buffer[0..len], 0, &addr.any, addr.getOsSockLen());
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var server = try UdpEchoServer.init(allocator, 9999);
    defer server.deinit();
    try server.run();
}

fn serverThread(server: *UdpEchoServer) void {
    server.handleOnce() catch |err| std.debug.panic("server thread error: {s}", .{@errorName(err)});
}

test "udp client receives echoed ping payload from localhost server" {
    var server = try UdpEchoServer.init(std.testing.allocator, 0);
    defer server.deinit();
    const port = try server.boundPort();

    var thread = try std.Thread.spawn(.{}, serverThread, .{&server});
    defer thread.join();

    const server_addr = try std.net.Address.parseIp4("127.0.0.1", port);
    const client_sock = try posix.socket(server_addr.any.family, posix.SOCK.DGRAM, posix.IPPROTO.UDP);
    defer posix.close(client_sock);

    const PingPayload = @import("ping/command.zig").PingPayload;
    const packet_header_size = network.packet_header_size;
    var packet: [packet_header_size + PingPayload.size()]u8 = undefined;
    const payload = network.PacketPayload{ .ping = PingPayload{ .timestamp = @as(u64, @intCast(std.time.timestamp())) } };
    const header = network.PacketHeader{
        .msg_type = .ping,
        .flags = .{ .reliable = true, .requires_ack = true },
        .session_id = 0x01020304,
        .sequence = 0x0A0B0C0D,
        .ack = 0x0E0F1011,
        .payload_len = @intCast(PingPayload.size()),
    };
    const packet_struct = network.Packet{ .header = header, .payload = payload };
    try packet_struct.encode(packet[0..]);

    _ = try posix.sendto(
        client_sock,
        packet[0..],
        0,
        &server_addr.any,
        server_addr.getOsSockLen(),
    );

    var response_addr_storage: posix.sockaddr.storage = undefined;
    var response_addr_len: posix.socklen_t = @sizeOf(posix.sockaddr.storage);
    var buffer: [128]u8 = undefined;
    const received = try posix.recvfrom(
        client_sock,
        &buffer,
        0,
        @ptrCast(&response_addr_storage),
        &response_addr_len,
    );

    const response = try network.Packet.decode(buffer[0..received]);
    try std.testing.expectEqual(network.PacketType.state_update, response.header.msg_type);
    try std.testing.expectEqual(@as(u32, 0x0A0B0C0D), response.header.ack);
    try std.testing.expectApproxEqAbs(@as(f32, 0), response.payload.state_update.x, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 0), response.payload.state_update.y, 0.0001);
    try std.testing.expect(response.payload.state_update.timestamp_ns != 0);
}

test "udp client receives echoed move payload from localhost server" {
    var server = try UdpEchoServer.init(std.testing.allocator, 0);
    defer server.deinit();
    const port = try server.boundPort();

    var thread = try std.Thread.spawn(.{}, serverThread, .{&server});
    defer thread.join();

    const server_addr = try std.net.Address.parseIp4("127.0.0.1", port);
    const client_sock = try posix.socket(server_addr.any.family, posix.SOCK.DGRAM, posix.IPPROTO.UDP);
    defer posix.close(client_sock);

    const MovePayload = @import("movement/command.zig").MovementCommand;
    const packet_header_size = network.packet_header_size;
    var packet: [packet_header_size + MovePayload.size()]u8 = undefined;
    const payload = network.PacketPayload{ .move = MovePayload{
        .direction = .Right,
        .speed = 3.0,
        .delta = 0.5,
    } };
    const header = network.PacketHeader{
        .msg_type = .move,
        .flags = .{ .reliable = true },
        .session_id = 0x02030405,
        .sequence = 1,
        .ack = 0,
        .payload_len = @intCast(MovePayload.size()),
    };
    const packet_struct = network.Packet{ .header = header, .payload = payload };
    try packet_struct.encode(packet[0..]);

    _ = try posix.sendto(
        client_sock,
        packet[0..],
        0,
        &server_addr.any,
        server_addr.getOsSockLen(),
    );

    var response_addr_storage: posix.sockaddr.storage = undefined;
    var response_addr_len: posix.socklen_t = @sizeOf(posix.sockaddr.storage);
    var buffer: [128]u8 = undefined;
    const received = try posix.recvfrom(
        client_sock,
        &buffer,
        0,
        @ptrCast(&response_addr_storage),
        &response_addr_len,
    );

    const response = try network.Packet.decode(buffer[0..received]);
    try std.testing.expectEqual(network.PacketType.state_update, response.header.msg_type);
    try std.testing.expectEqual(@as(u32, 1), response.header.ack);
    try std.testing.expectApproxEqAbs(@as(f32, 1.5), response.payload.state_update.x, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 0), response.payload.state_update.y, 0.0001);
    try std.testing.expect(response.payload.state_update.timestamp_ns != 0);
}
