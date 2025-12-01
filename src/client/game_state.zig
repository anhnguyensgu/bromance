const std = @import("std");
const rl = @import("raylib");
const shared = @import("../shared.zig");
const network = shared.network;
const MovementCommand = @import("../movement/command.zig").MovementCommand;
const MoveDirection = @import("../movement/command.zig").MoveDirection;
const UdpClient = @import("udp_client.zig"); // Circular dependency might be an issue, let's avoid if possible

pub const MAX_PENDING_MOVES: usize = 32;
pub const MAX_SNAPSHOTS: usize = 32;

pub const Snapshot = struct {
    timestamp: i64,
    pos: rl.Vector2,
};

pub const PendingMove = struct {
    seq: u32,
    cmd: MovementCommand,
};

pub const OtherPlayerState = struct {
    pos: rl.Vector2,
    last_update_ns: i64,
    dir: MoveDirection = .Down,
    is_moving: bool = false,
};

pub const ClientGameState = struct {
    mutex: std.Thread.Mutex = .{},

    // Local player state
    snapshots: [MAX_SNAPSHOTS]Snapshot = undefined,
    snapshot_count: usize = 0,

    // Other players state
    other_players: std.AutoHashMap(u32, OtherPlayerState),

    // Input state
    pending_moves: [MAX_PENDING_MOVES]PendingMove = undefined,
    pending_count: usize = 0,
    sequence: u32 = 0,
    session_id: u32 = 0,

    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) ClientGameState {
        // Generate random session ID
        var prng = std.Random.DefaultPrng.init(@intCast(std.time.nanoTimestamp()));
        const random_session_id = prng.random().int(u32);

        return .{
            .other_players = std.AutoHashMap(u32, OtherPlayerState).init(allocator),
            .allocator = allocator,
            .session_id = random_session_id,
        };
    }

    pub fn deinit(self: *ClientGameState) void {
        self.other_players.deinit();
    }

    // --- Thread-Safe Methods ---

    pub fn pushInput(self: *ClientGameState, cmd: MovementCommand) u32 {
        self.mutex.lock();
        defer self.mutex.unlock();

        self.sequence += 1;
        const seq = self.sequence;

        if (self.pending_count < MAX_PENDING_MOVES) {
            self.pending_moves[self.pending_count] = .{ .seq = seq, .cmd = cmd };
            self.pending_count += 1;
        }
        return seq;
    }

    pub fn getPendingMoves(self: *ClientGameState, out_moves: []PendingMove) usize {
        self.mutex.lock();
        defer self.mutex.unlock();

        const count = @min(self.pending_count, out_moves.len);
        @memcpy(out_moves[0..count], self.pending_moves[0..count]);

        // Clear pending moves after retrieving (assuming they will be sent)
        // In a real robust system we might wait for ACK, but for now we send and clear or keep until ACK
        // For this architecture, let's keep them until ACK logic clears them,
        // BUT UdpClient needs to read them to send.
        // Actually, UdpClient sends them immediately.
        // Let's just return the count and let UdpClient read them directly while holding lock if needed.
        // Or better: return a copy for sending.
        return count;
    }

    // Helper to access pending moves safely without copying everything if we just want to iterate
    // But for simplicity, let's expose a method to get the latest move to send
    pub fn getLatestMove(self: *ClientGameState) ?PendingMove {
        self.mutex.lock();
        defer self.mutex.unlock();
        if (self.pending_count == 0) return null;
        return self.pending_moves[self.pending_count - 1];
    }

    pub fn storeSnapshot(self: *ClientGameState, pos: rl.Vector2) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const now: i64 = @intCast(std.time.nanoTimestamp());
        if (self.snapshot_count < MAX_SNAPSHOTS) {
            self.snapshots[self.snapshot_count] = .{ .timestamp = now, .pos = pos };
            self.snapshot_count += 1;
        } else {
            // Shift left
            std.mem.copyForwards(Snapshot, self.snapshots[0 .. MAX_SNAPSHOTS - 1], self.snapshots[1..MAX_SNAPSHOTS]);
            self.snapshots[MAX_SNAPSHOTS - 1] = .{ .timestamp = now, .pos = pos };
        }
    }

    pub fn updateOtherPlayer(self: *ClientGameState, session_id: u32, pos: rl.Vector2, dir: MoveDirection, is_moving: bool) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const now: i64 = @intCast(std.time.nanoTimestamp());
        try self.other_players.put(session_id, .{
            .pos = pos,
            .last_update_ns = now,
            .dir = dir,
            .is_moving = is_moving,
        });
    }

    pub fn getOtherPlayer(self: *ClientGameState, session_id: u32) ?OtherPlayerState {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.other_players.get(session_id);
    }

    // Interpolation logic moved here (or at least the data access)
    pub fn sampleInterpolated(self: *ClientGameState) ?rl.Vector2 {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.snapshot_count == 0) return null;

        // If we only have one snapshot, return it
        if (self.snapshot_count == 1) return self.snapshots[0].pos;

        const now: i64 = @intCast(std.time.nanoTimestamp());
        const render_delay_ns = 45 * 1000 * 1000; // 45ms
        const render_time = now - render_delay_ns;

        // Find two snapshots surrounding render_time
        var i: usize = self.snapshot_count - 1;
        while (i > 0) : (i -= 1) {
            const s2 = self.snapshots[i];
            const s1 = self.snapshots[i - 1];

            if (s1.timestamp <= render_time and s2.timestamp >= render_time) {
                const total = s2.timestamp - s1.timestamp;
                if (total <= 0) return s1.pos;

                const elapsed = render_time - s1.timestamp;
                const t = @as(f32, @floatFromInt(elapsed)) / @as(f32, @floatFromInt(total));

                return rl.Vector2{
                    .x = s1.pos.x + (s2.pos.x - s1.pos.x) * t,
                    .y = s1.pos.y + (s2.pos.y - s1.pos.y) * t,
                };
            }
        }

        // If render_time is newer than newest snapshot, extrapolate or clamp
        if (render_time > self.snapshots[self.snapshot_count - 1].timestamp) {
            return self.snapshots[self.snapshot_count - 1].pos;
        }

        // If render_time is older than oldest, return oldest
        return self.snapshots[0].pos;
    }

    // Reconcile logic needs access to pending moves
    pub fn reconcileState(self: *ClientGameState, ack: u32, server_pos: rl.Vector2, world: shared.World) rl.Vector2 {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Remove acknowledged moves
        var active_count: usize = 0;
        for (0..self.pending_count) |i| {
            if (self.pending_moves[i].seq > ack) {
                self.pending_moves[active_count] = self.pending_moves[i];
                active_count += 1;
            }
        }
        self.pending_count = active_count;

        // Re-apply remaining moves
        var pos = server_pos;
        const PLAYER_SIZE: f32 = 32.0;

        for (0..self.pending_count) |i| {
            const cmd = self.pending_moves[i].cmd;
            const move_amount = cmd.speed * cmd.delta;

            var new_pos = pos;
            switch (cmd.direction) {
                .Up => new_pos.y -= move_amount,
                .Down => new_pos.y += move_amount,
                .Left => new_pos.x -= move_amount,
                .Right => new_pos.x += move_amount,
            }

            // Clamp
            new_pos.x = std.math.clamp(new_pos.x, 0, world.width);
            new_pos.y = std.math.clamp(new_pos.y, 0, world.height);

            // Collision
            const collision = world.checkCollision(new_pos.x, new_pos.y, PLAYER_SIZE, PLAYER_SIZE, cmd.direction);
            if (!collision) {
                pos = new_pos;
            }
        }

        return pos;
    }
};
