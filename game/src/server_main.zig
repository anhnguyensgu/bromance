const std = @import("std");
const posix = std.posix;

const shared = @import("shared.zig");
const network = shared.network;

fn loadPlots(allocator: std.mem.Allocator, path: []const u8) ![]shared.Plot {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const file_size = try file.getEndPos();
    const buffer = try allocator.alloc(u8, file_size);
    defer allocator.free(buffer);
    _ = try file.readAll(buffer);

    const parsed = try std.json.parseFromSlice(
        std.json.Value,
        allocator,
        buffer,
        .{},
    );
    defer parsed.deinit();

    const root = parsed.value.object;
    const plots_array = root.get("plots").?.array;

    const plots = try allocator.alloc(shared.Plot, plots_array.items.len);

    for (plots_array.items, 0..) |plot_obj, i| {
        const obj = plot_obj.object;
        const id = @as(u64, @intCast(obj.get("id").?.integer));
        const tile_x = @as(i32, @intCast(obj.get("tile_x").?.integer));
        const tile_y = @as(i32, @intCast(obj.get("tile_y").?.integer));
        const width_tiles = @as(i32, @intCast(obj.get("width_tiles").?.integer));
        const height_tiles = @as(i32, @intCast(obj.get("height_tiles").?.integer));

        var owner = shared.OwnerId.none();
        if (obj.get("owner")) |owner_obj| {
            const owner_data = owner_obj.object;
            const kind_str = owner_data.get("kind").?.string;
            const kind = parseOwnerIdKind(kind_str) orelse .none;

            if (owner_data.get("value")) |value_str| {
                owner = shared.OwnerId.init(kind, value_str.string);
            } else {
                owner = shared.OwnerId{ .kind = kind };
            }
        }

        plots[i] = shared.Plot{
            .id = id,
            .tile_x = tile_x,
            .tile_y = tile_y,
            .width_tiles = width_tiles,
            .height_tiles = height_tiles,
            .owner = owner,
        };
    }

    return plots;
}

fn parseOwnerIdKind(kind_str: []const u8) ?shared.OwnerIdKind {
    if (std.mem.eql(u8, kind_str, "none")) return .none;
    if (std.mem.eql(u8, kind_str, "wallet")) return .wallet;
    if (std.mem.eql(u8, kind_str, "ens")) return .ens;
    if (std.mem.eql(u8, kind_str, "nft")) return .nft;
    if (std.mem.eql(u8, kind_str, "custom")) return .custom;
    return null;
}

const Client = struct {
    address: std.net.Address,
    state: shared.PlayerState,
    last_heard_ns: i64,
};

// Housekeeping configuration
const CLIENT_TIMEOUT_NS: i64 = 30 * std.time.ns_per_s; // 30 seconds without activity = disconnected
const HOUSEKEEPING_INTERVAL_NS: i64 = 5 * std.time.ns_per_s; // Check every 5 seconds

const UdpEchoServer = struct {
    sock: posix.socket_t,
    buffer: [1024]u8 = undefined,
    clients: std.AutoHashMap(u32, Client),
    allocator: std.mem.Allocator,
    world: shared.World,
    plots: []shared.Plot,
    last_housekeeping_ns: i64 = 0,

    pub fn init(allocator: std.mem.Allocator, bind_port: u16) !UdpEchoServer {
        const listen_address = try std.net.Address.parseIp4("0.0.0.0", bind_port);
        const sock = try posix.socket(listen_address.any.family, posix.SOCK.DGRAM, posix.IPPROTO.UDP);

        var enable: c_int = 1;
        try posix.setsockopt(sock, posix.SOL.SOCKET, posix.SO.REUSEADDR, std.mem.asBytes(&enable));
        try posix.setsockopt(sock, posix.SOL.SOCKET, posix.SO.REUSEPORT, std.mem.asBytes(&enable));
        try posix.bind(sock, &listen_address.any, listen_address.getOsSockLen());

        // Set socket to non-blocking for housekeeping checks
        var flags = try posix.fcntl(sock, posix.F.GETFL, 0);
        flags |= @as(u32, @bitCast(posix.O{ .NONBLOCK = true }));
        _ = try posix.fcntl(sock, posix.F.SETFL, flags);

        // Load world data for collision detection
        const world = try shared.World.loadFromFile(allocator, "assets/worldoutput.json");

        const plots = try loadPlots(allocator, "assets/plots.json");

        const now: i64 = @intCast(std.time.nanoTimestamp());

        return .{
            .sock = sock,
            .clients = std.AutoHashMap(u32, Client).init(allocator),
            .allocator = allocator,
            .world = world,
            .plots = plots,
            .last_housekeeping_ns = now,
        };
    }

    pub fn deinit(self: *UdpEchoServer) void {
        self.world.deinit(self.allocator);
        self.allocator.free(self.plots);
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
        std.debug.print("Server running on port 9999...\n", .{});

        while (true) {
            // Try to receive a packet (non-blocking)
            self.handleOnceNonBlocking() catch |err| {
                if (err != error.WouldBlock) {
                    std.debug.print("Error handling packet: {s}\n", .{@errorName(err)});
                }
            };

            // Run housekeeping periodically
            try self.runHousekeeping();

            // Small sleep to avoid burning CPU when no packets
            std.posix.nanosleep(0, 1_000_000); // 1ms
        }
    }

    fn handleOnceNonBlocking(self: *UdpEchoServer) !void {
        var client_addr_storage: posix.sockaddr.storage = undefined;
        var client_addr_len: posix.socklen_t = @sizeOf(posix.sockaddr.storage);
        const received = try posix.recvfrom(
            self.sock,
            &self.buffer,
            0,
            @ptrCast(&client_addr_storage),
            &client_addr_len,
        );

        const addr = std.net.Address.initPosix(
            @ptrCast(@alignCast(&client_addr_storage)),
        );

        const payload = self.buffer[0..received];
        const packet = try network.Packet.decode(payload);
        const ack_seq = packet.header.sequence;
        const session_id = packet.header.session_id;
        const now: i64 = @intCast(std.time.nanoTimestamp());

        // Get or create client
        const res = try self.clients.getOrPut(session_id);
        if (!res.found_existing) {
            res.value_ptr.* = .{
                .address = addr,
                .state = .{ .x = 0, .y = 0 },
                .last_heard_ns = now,
            };
            std.debug.print("New player connected: session_id={d}, total_clients={d}\n", .{ session_id, self.clients.count() });
            try self.sendPlots(&addr, ack_seq);
        }

        // Update last heard time and address
        res.value_ptr.last_heard_ns = now;
        res.value_ptr.address = addr;
        const client = res.value_ptr;

        switch (packet.payload) {
            .ping => |p| {
                std.debug.print("ping from session_id={d}, timestamp={d}\n", .{ session_id, p.timestamp });
                try self.broadcastAllPlayers(ack_seq);
            },
            .move => |m| {
                self.integrateMove(m, &client.state);
                try self.broadcastAllPlayers(ack_seq);
            },
            .leave => |l| {
                std.debug.print("Player leaving: session_id={d}, reason={d}\n", .{ session_id, l.reason });
                _ = self.clients.remove(session_id);
                std.debug.print("Player removed, total_clients={d}\n", .{self.clients.count()});
                try self.broadcastAllPlayers(ack_seq);
            },
            .state_update, .all_players_state, .plots_sync => {},
        }
    }

    fn runHousekeeping(self: *UdpEchoServer) !void {
        const now: i64 = @intCast(std.time.nanoTimestamp());

        // Only run housekeeping at intervals
        if (now - self.last_housekeeping_ns < HOUSEKEEPING_INTERVAL_NS) {
            return;
        }
        self.last_housekeeping_ns = now;

        // Find and remove stale clients
        // Use a fixed-size buffer since we don't expect many stale clients per cycle
        var stale_clients: [network.MAX_PLAYERS]u32 = undefined;
        var stale_count: usize = 0;

        var it = self.clients.iterator();
        while (it.next()) |entry| {
            const session_id = entry.key_ptr.*;
            const client = entry.value_ptr.*;
            const inactive_duration = now - client.last_heard_ns;

            if (inactive_duration > CLIENT_TIMEOUT_NS) {
                if (stale_count < network.MAX_PLAYERS) {
                    stale_clients[stale_count] = session_id;
                    stale_count += 1;
                }
                const inactive_secs = @divFloor(inactive_duration, std.time.ns_per_s);
                std.debug.print("Client timed out: session_id={d}, inactive for {d}s\n", .{ session_id, inactive_secs });
            }
        }

        // Remove stale clients
        if (stale_count > 0) {
            for (stale_clients[0..stale_count]) |session_id| {
                _ = self.clients.remove(session_id);
            }
            std.debug.print("Removed {d} stale client(s), total_clients={d}\n", .{ stale_count, self.clients.count() });

            // Broadcast updated player list to remaining clients
            try self.broadcastAllPlayers(0);
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

        // Send to all clients
        var dest_it = self.clients.iterator();
        while (dest_it.next()) |dest_entry| {
            const dest_client = dest_entry.value_ptr;
            try self.sendAllPlayers(&dest_client.address, ack_seq, all_players);
        }
    }

    fn integrateMove(self: *UdpEchoServer, move: network.MovePayload, pos: *shared.PlayerState) void {
        const PLAYER_SIZE: f32 = 32.0;
        const move_amount = move.speed * move.delta;

        var new_pos = pos.*;
        switch (move.direction) {
            .Up => new_pos.y -= move_amount,
            .Down => new_pos.y += move_amount,
            .Left => new_pos.x -= move_amount,
            .Right => new_pos.x += move_amount,
        }

        const max_x = @max(0.0, self.world.width - PLAYER_SIZE);
        const max_y = @max(0.0, self.world.height - PLAYER_SIZE);
        new_pos.x = std.math.clamp(new_pos.x, 0.0, max_x);
        new_pos.y = std.math.clamp(new_pos.y, 0.0, max_y);

        const collision = self.world.checkCollisionAll(new_pos.x, new_pos.y, PLAYER_SIZE, PLAYER_SIZE, move.direction);

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

    fn sendPlots(self: *UdpEchoServer, addr: *const std.net.Address, ack_seq: u32) !void {
        var plots_payload: network.PlotsSyncPayload = undefined;
        plots_payload.count = @min(@as(u8, @intCast(self.plots.len)), network.MAX_PLOTS);

        for (0..plots_payload.count) |i| {
            const plot = self.plots[i];
            plots_payload.plots[i] = network.PlotData{
                .id = plot.id,
                .tile_x = plot.tile_x,
                .tile_y = plot.tile_y,
                .width_tiles = plot.width_tiles,
                .height_tiles = plot.height_tiles,
                .owner_kind = @intFromEnum(plot.owner.kind),
                .owner_len = plot.owner.len,
                .owner_value = plot.owner.value,
            };
        }

        const payload = network.PacketPayload{ .plots_sync = plots_payload };
        const payload_size = 1 + (@as(usize, plots_payload.count) * network.PlotData.size());
        const header = network.PacketHeader{
            .msg_type = .plots_sync,
            .flags = .{ .reliable = true },
            .session_id = 0,
            .sequence = 0,
            .ack = ack_seq,
            .payload_len = @intCast(payload_size),
        };

        var buffer: [network.packet_header_size + network.PlotsSyncPayload.size()]u8 = undefined;
        const packet = network.Packet{ .header = header, .payload = payload };
        try packet.encode(buffer[0..]);
        const len = network.packet_header_size + payload_size;
        _ = try posix.sendto(self.sock, buffer[0..len], 0, &addr.any, addr.getOsSockLen());

        std.debug.print("Sent {d} plots to client\n", .{plots_payload.count});
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
    server.handleOnceNonBlocking() catch |err| {
        if (err != error.WouldBlock) {
            std.debug.panic("server thread error: {s}", .{@errorName(err)});
        }
    };
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
