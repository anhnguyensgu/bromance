const std = @import("std");
const rl = @import("raylib");
const shared = @import("../shared.zig");
const network = shared.network;
const MovementCommand = @import("../movement/command.zig").MovementCommand;
const MoveDirection = @import("../movement/command.zig").MoveDirection;

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

    // Other players state - double buffered for lock-free reading
    // Network thread writes to back buffer, then swaps
    // Render thread reads from front buffer
    other_players_buffers: [2]std.AutoHashMap(u32, OtherPlayerState),
    active_buffer: std.atomic.Value(u8) = std.atomic.Value(u8).init(0),

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
            .other_players_buffers = .{
                std.AutoHashMap(u32, OtherPlayerState).init(allocator),
                std.AutoHashMap(u32, OtherPlayerState).init(allocator),
            },
            .allocator = allocator,
            .session_id = random_session_id,
        };
    }

    pub fn deinit(self: *ClientGameState) void {
        self.other_players_buffers[0].deinit();
        self.other_players_buffers[1].deinit();
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
        return count;
    }

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

    // --- Double-Buffer Methods for Other Players ---

    /// Called by render thread to get a read-only view of other players.
    /// This is lock-free - reads the currently active (front) buffer.
    pub fn getOtherPlayersForRender(self: *ClientGameState) *const std.AutoHashMap(u32, OtherPlayerState) {
        const idx = self.active_buffer.load(.acquire);
        return &self.other_players_buffers[idx];
    }

    /// Called by network thread to handle all_players_state packet.
    /// Writes to back buffer, then atomically swaps.
    pub fn handleAllPlayersUpdate(
        self: *ClientGameState,
        players: []const network.PlayerInfo,
        own_session_id: u32,
        ack: u32,
        world: shared.World,
    ) !void {
        const now: i64 = @intCast(std.time.nanoTimestamp());

        // Get front (read) and back (write) buffer indices
        const front_idx = self.active_buffer.load(.acquire);
        const back_idx: u8 = 1 - front_idx;

        const front_buffer = &self.other_players_buffers[front_idx];
        const back_buffer = &self.other_players_buffers[back_idx];

        // Clear back buffer and rebuild from scratch
        back_buffer.clearRetainingCapacity();

        for (players) |player_info| {
            if (player_info.session_id == own_session_id) {
                // This is our own position from the server - use for reconciliation
                const server_pos = rl.Vector2{ .x = player_info.x, .y = player_info.y };
                const corrected = self.reconcileState(ack, server_pos, world);
                self.storeSnapshot(corrected);
                continue;
            }

            // Other player - compute direction and movement
            var dir: MoveDirection = .Down;
            var is_moving = false; // Default to not moving for new players

            if (front_buffer.get(player_info.session_id)) |prev| {
                const dx = player_info.x - prev.pos.x;
                const dy = player_info.y - prev.pos.y;
                const movement_threshold: f32 = 0.25;
                const stale_ns: i64 = 250_000_000; // 250ms
                const fresh_update = (now - prev.last_update_ns) < stale_ns;
                const moved_enough = (@abs(dx) > movement_threshold) or (@abs(dy) > movement_threshold);

                is_moving = fresh_update and moved_enough;

                if (is_moving) {
                    if (@abs(dx) > @abs(dy)) {
                        dir = if (dx > 0) .Right else .Left;
                    } else {
                        dir = if (dy > 0) .Down else .Up;
                    }
                } else {
                    dir = prev.dir;
                }
            }

            try back_buffer.put(player_info.session_id, .{
                .pos = .{ .x = player_info.x, .y = player_info.y },
                .last_update_ns = now,
                .dir = dir,
                .is_moving = is_moving,
            });
        }

        // Atomically swap: back buffer becomes front
        self.active_buffer.store(back_idx, .release);
    }

    // Interpolation logic
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
        const max_x = @max(0.0, world.width - PLAYER_SIZE);
        const max_y = @max(0.0, world.height - PLAYER_SIZE);

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

            // Clamp so the whole player stays inside the world
            new_pos.x = std.math.clamp(new_pos.x, 0.0, max_x);
            new_pos.y = std.math.clamp(new_pos.y, 0.0, max_y);

            // Collision
            const collision = world.checkCollisionAll(new_pos.x, new_pos.y, PLAYER_SIZE, PLAYER_SIZE, cmd.direction);
            if (!collision) {
                pos = new_pos;
            }
        }

        return pos;
    }
};
