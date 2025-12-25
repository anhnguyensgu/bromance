# Zig gRPC Client

A minimal gRPC client implementation in Zig, built from scratch with HTTP/2 and HPACK support.

## Features

- ✅ HTTP/2 connection and handshake
- ✅ HPACK header encoding (indexed + literal)
- ✅ gRPC length-prefixed message framing
- ✅ Protobuf integration via `zig-protobuf`
- ✅ Unary RPC calls
- ✅ Error handling with gRPC status codes

## Quick Start

```zig
const std = @import("std");
const grpc = @import("grpc");
const auth_proto = @import("model/auth.pb.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    
    // 1. Connect to server
    var client = try grpc.GrpcClient.init(allocator, "127.0.0.1", 50051);
    defer client.deinit();
    
    // 2. Create request
    var req = auth_proto.LoginRequest{
        .username = "user@example.com",
        .password = "password123",
    };
    
    // 3. Serialize request
    var buf = std.Io.Writer.Allocating.init(allocator);
    defer buf.deinit();
    try req.encode(&buf.writer, allocator);
    
    // 4. Make RPC call
    const resp_bytes = try client.call("/auth.AuthService/Login", buf.written(), .none);
    defer allocator.free(resp_bytes);
    
    // 5. Deserialize response
    var reader: std.Io.Reader = .fixed(resp_bytes);
    var resp = try auth_proto.LoginResponse.decode(&reader, allocator);
    defer resp.deinit(allocator);
    
    std.debug.print("Token: {s}\n", .{resp.token});
}
```

## API Reference

### GrpcClient

```zig
pub const GrpcClient = struct {
    /// Initialize a new gRPC client and connect to the server.
    /// Performs HTTP/2 handshake automatically.
    pub fn init(allocator: std.mem.Allocator, host: []const u8, port: u16) !GrpcClient;
    
    /// Close the connection.
    pub fn deinit(self: *GrpcClient) void;
    
    /// Make a unary RPC call.
    /// - path: The gRPC method path, e.g., "/package.Service/Method"
    /// - request_bytes: Serialized protobuf message
    /// - Returns: Serialized response bytes (caller must free)
    pub fn call(self: *GrpcClient, path: []const u8, request_bytes: []const u8, _: anytype) ![]u8;
};
```

### GrpcStatus

gRPC status codes for error handling:

```zig
pub const GrpcStatus = enum(u8) {
    OK = 0,
    CANCELLED = 1,
    UNKNOWN = 2,
    INVALID_ARGUMENT = 3,
    DEADLINE_EXCEEDED = 4,
    NOT_FOUND = 5,
    ALREADY_EXISTS = 6,
    PERMISSION_DENIED = 7,
    RESOURCE_EXHAUSTED = 8,
    FAILED_PRECONDITION = 9,
    ABORTED = 10,
    OUT_OF_RANGE = 11,
    UNIMPLEMENTED = 12,
    INTERNAL = 13,
    UNAVAILABLE = 14,
    DATA_LOSS = 15,
    UNAUTHENTICATED = 16,
};
```

## Error Handling

The client returns `error.GrpcError` when the server responds with a non-OK gRPC status:

```zig
const resp_bytes = client.call("/auth.AuthService/Login", buf.written(), .none) catch |err| {
    switch (err) {
        error.GrpcError => {
            // Server returned an error (e.g., UNAUTHENTICATED, NOT_FOUND)
            std.debug.print("gRPC call failed\n", .{});
            return;
        },
        error.NoResponse => {
            // No response received
            std.debug.print("No response from server\n", .{});
            return;
        },
        else => return err,
    }
};
```

### Common Errors

| Error | Description |
|-------|-------------|
| `error.GrpcError` | Server returned non-OK gRPC status |
| `error.NoResponse` | Connection closed without response |
| `error.EndOfStream` | Unexpected end of stream |
| `error.ConnectionRefused` | Cannot connect to server |

## File Structure

```
src/grpc/
├── README.md       # This file
├── client.zig      # GrpcClient implementation
└── http2.zig       # HTTP/2 frame types and encoding
```

## Limitations

This is a minimal implementation with the following limitations:

1. **Unary calls only** - No streaming support (client/server/bidirectional)
2. **No TLS** - Plaintext connections only (`-plaintext` equivalent)
3. **No compression** - gzip/deflate not supported
4. **Basic HPACK** - Uses simple encoding, no dynamic table
5. **No connection pooling** - Single connection per client
6. **No timeouts** - Calls block indefinitely

## Protocol Details

### HTTP/2 Framing

The client implements these HTTP/2 frame types:
- `SETTINGS` - Connection settings exchange
- `HEADERS` - Request/response headers
- `DATA` - Message payload
- `WINDOW_UPDATE` - Flow control (read only)
- `PING` - Keep-alive (skipped)
- `GOAWAY` - Connection termination (skipped)

### gRPC Message Format

Each gRPC message uses length-prefixed framing:

```
┌─────────────┬──────────────────┬─────────────────┐
│ Compressed  │ Message Length   │ Message Data    │
│ (1 byte)    │ (4 bytes, BE)    │ (N bytes)       │
└─────────────┴──────────────────┴─────────────────┘
```

### HPACK Encoding

Headers are encoded using:
- **Indexed representation** for common headers (`:method`, `:scheme`)
- **Literal without indexing** for dynamic headers (`:path`, `:authority`)

## Dependencies

- `zig-protobuf` - For protobuf serialization/deserialization
- Zig 0.15.x standard library

## Testing

Run the test suite:

```bash
zig build test
```

The test connects to a gRPC server on `127.0.0.1:50051` and performs a login RPC call.

## License

MIT
