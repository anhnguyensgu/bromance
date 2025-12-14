const std = @import("std");

pub const HttpClient = struct {
    allocator: std.mem.Allocator,
    client: std.http.Client,

    pub fn init(allocator: std.mem.Allocator) HttpClient {
        return .{
            .allocator = allocator,
            .client = std.http.Client{ .allocator = allocator },
        };
    }

    pub fn deinit(self: *HttpClient) void {
        self.client.deinit();
    }

    pub fn login(self: *HttpClient, username: []const u8, password: []const u8) !bool {
        var buf: [1024]u8 = undefined;
        const uri = try std.Uri.parse("http://127.0.0.1:3000/auth/login");

        const payload = try std.fmt.bufPrint(&buf, "{f}", .{
            std.json.fmt(.{ .username = username, .password = password }, .{}),
        });

        var req = try self.client.request(.POST, uri, .{
            .headers = .{ .content_type = .{ .override = "application/json" } },
        });
        defer req.deinit();

        // This sends headers (with Content-Length) and body
        _ = try req.sendBody(payload);

        var redirect_buffer: [1024]u8 = undefined;
        const res = try req.receiveHead(&redirect_buffer);

        if (res.head.status == .ok) {
            // TODO: Parse response for token
            return true;
        }
        return false;
    }
};
