const std = @import("std");
const posix = std.posix;

const shared = @import("shared");

const UdpEchoServer = struct {
    sock: posix.socket_t,
    buffer: [1024]u8 = undefined,

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
        const payload = self.buffer[0..received];
        std.debug.print("msg from {any}: {s}\n", .{ addr, payload });

        _ = try posix.sendto(
            self.sock,
            payload,
            0,
            &addr.any,
            addr.getOsSockLen(),
        );
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

test "udp client receives echoed payload from localhost server" {
    // var server = try UdpEchoServer.init(0);
    // defer server.deinit();
    // const port = try server.boundPort();
    //
    // var thread = try std.Thread.spawn(.{}, serverThread, .{&server});
    // defer thread.join();
    //
    const server_addr = try std.net.Address.parseIp4("127.0.0.1", 9999);
    const client_sock = try posix.socket(server_addr.any.family, posix.SOCK.DGRAM, posix.IPPROTO.UDP);
    defer posix.close(client_sock);

    const message = "ping";
    _ = try posix.sendto(
        client_sock,
        message,
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

    try std.testing.expectEqualStrings(message, buffer[0..received]);
}
