const std = @import("std");
const posix = std.posix;

const shared = @import("shared.zig");
const network = shared.network;

const UdpEchoServer = struct {
    sock: posix.socket_t,
    buffer: [1024]u8 = undefined,
    player_pos: shared.PlayerState = .{ .x = 0, .y = 0 },

    pub fn init(bind_port: u16) !UdpEchoServer {
        const listen_address = try std.net.Address.parseIp4("0.0.0.0", bind_port);
        const sock = try posix.socket(listen_address.any.family, posix.SOCK.DGRAM, posix.IPPROTO.UDP);

        var enable: c_int = 1;
        try posix.setsockopt(sock, posix.SOL.SOCKET, posix.SO.REUSEADDR, std.mem.asBytes(&enable));
        try posix.setsockopt(sock, posix.SOL.SOCKET, posix.SO.REUSEPORT, std.mem.asBytes(&enable));
        try posix.bind(sock, &listen_address.any, listen_address.getOsSockLen());

        return .{ .sock = sock };
    }

    pub fn deinit(self: *UdpEchoServer) void {
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

        //parse packet
        const payload = self.buffer[0..received];
        const packet = try network.Packet.decode(payload);
        const ack_seq = packet.header.sequence;
        switch (packet.payload) {
            .ping => |p| {
                std.debug.print("ping payload timestamp: {d}\n", .{p.timestamp});
                try self.sendState(&addr, ack_seq);
            },
            .move => |m| {
                std.debug.print("move payload direction: {any}\n", .{m.direction});
                self.integrateMove(m);
                try self.sendState(&addr, ack_seq);
            },
            .state_update => {},
        }
    }

    fn integrateMove(self: *UdpEchoServer, move: network.MovePayload) void {
        var pos = self.player_pos;
        switch (move.direction) {
            .Up => pos.y -= move.speed * move.delta,
            .Down => pos.y += move.speed * move.delta,
            .Left => pos.x -= move.speed * move.delta,
            .Right => pos.x += move.speed * move.delta,
        }
        pos.x = std.math.clamp(pos.x, 0, 1000);
        pos.y = std.math.clamp(pos.y, 0, 1000);
        self.player_pos = pos;
    }

    fn sendState(self: *UdpEchoServer, addr: *const std.net.Address, ack_seq: u32) !void {
        const payload = network.PacketPayload{ .state_update = network.StatePayload{
            .x = self.player_pos.x,
            .y = self.player_pos.y,
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
};

pub fn main() !void {
    var server = try UdpEchoServer.init(9999);
    defer server.deinit();
    try server.run();
}

fn serverThread(server: *UdpEchoServer) void {
    server.handleOnce() catch |err| std.debug.panic("server thread error: {s}", .{@errorName(err)});
}

test "udp client receives echoed ping payload from localhost server" {
    var server = try UdpEchoServer.init(0);
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
    var server = try UdpEchoServer.init(0);
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
