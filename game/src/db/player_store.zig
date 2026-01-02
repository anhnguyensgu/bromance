const std = @import("std");

const c = @cImport({
    @cInclude("sqlite3.h");
});

pub const PlayerState = struct {
    x: f32,
    y: f32,
};

pub const PersistEntry = struct {
    session_id: u32,
    state: PlayerState,
};

const MAX_PENDING: usize = 256;

pub const PlayerStore = struct {
    // Main thread connection (for reads)
    main_db: *c.sqlite3,
    load_stmt: *c.sqlite3_stmt,

    // Persist thread connection (for writes)
    persist_db: *c.sqlite3,

    // Lock-free SPSC (Single Producer Single Consumer) queue
    pending_queue: [MAX_PENDING]PersistEntry = undefined,
    write_index: std.atomic.Value(usize) = std.atomic.Value(usize).init(0),
    read_index: std.atomic.Value(usize) = std.atomic.Value(usize).init(0),

    should_stop: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    persist_thread: ?std.Thread = null,

    const Self = @This();
    const FLUSH_INTERVAL_MS: u64 = 5000;

    /// Initialize PlayerStore with separate connections per thread.
    /// Database must already be migrated via migrations.zig CLI tool.
    pub fn init(db_path: [:0]const u8) !Self {
        // Open main thread connection (for reads)
        var main_db_ptr: ?*c.sqlite3 = null;
        if (c.sqlite3_open(db_path.ptr, &main_db_ptr) != c.SQLITE_OK) {
            return error.SqliteOpenFailed;
        }
        const main_db = main_db_ptr orelse return error.SqliteOpenFailed;

        // Configure main connection
        if (c.sqlite3_exec(main_db, "PRAGMA synchronous=NORMAL;", null, null, null) != c.SQLITE_OK) {
            _ = c.sqlite3_close(main_db);
            return error.SqliteExecFailed;
        }

        // Prepare load statement on main connection
        var load_stmt: ?*c.sqlite3_stmt = null;
        const load_sql = "SELECT x, y FROM player_state WHERE session_id = ?1 LIMIT 1;";
        if (c.sqlite3_prepare_v2(main_db, load_sql, -1, &load_stmt, null) != c.SQLITE_OK) {
            _ = c.sqlite3_close(main_db);
            return error.SqlitePrepareFailed;
        }

        // Open persist thread connection (for writes)
        var persist_db_ptr: ?*c.sqlite3 = null;
        if (c.sqlite3_open(db_path.ptr, &persist_db_ptr) != c.SQLITE_OK) {
            _ = c.sqlite3_finalize(load_stmt);
            _ = c.sqlite3_close(main_db);
            return error.SqliteOpenFailed;
        }
        const persist_db = persist_db_ptr orelse {
            _ = c.sqlite3_finalize(load_stmt);
            _ = c.sqlite3_close(main_db);
            return error.SqliteOpenFailed;
        };

        // Configure persist connection
        if (c.sqlite3_exec(persist_db, "PRAGMA synchronous=NORMAL;", null, null, null) != c.SQLITE_OK) {
            _ = c.sqlite3_close(persist_db);
            _ = c.sqlite3_finalize(load_stmt);
            _ = c.sqlite3_close(main_db);
            return error.SqliteExecFailed;
        }

        return Self{
            .main_db = main_db,
            .load_stmt = load_stmt.?,
            .persist_db = persist_db,
            // Thread will be started by startPersistThread()
        };
    }

    /// Start the background persistence thread.
    /// Must be called after init() and before use.
    pub fn startPersistThread(self: *Self) !void {
        if (self.persist_thread != null) {
            return error.ThreadAlreadyStarted;
        }
        self.persist_thread = try std.Thread.spawn(.{}, persistThreadFn, .{self});
    }

    pub fn deinit(self: *Self) void {
        // Signal thread to stop
        self.should_stop.store(true, .release);

        // Wait for thread to finish
        if (self.persist_thread) |thread| {
            thread.join();
        }

        // Final flush of any remaining data
        self.flushPendingSync();

        // Close both connections
        _ = c.sqlite3_finalize(self.load_stmt);
        _ = c.sqlite3_close(self.main_db);
        _ = c.sqlite3_close(self.persist_db);
    }

    /// Load player state from database (main thread only, uses main_db)
    pub fn loadPlayerState(self: *Self, session_id: u32) !?PlayerState {
        // No mutex needed! main_db is only used by main thread
        _ = c.sqlite3_reset(self.load_stmt);
        _ = c.sqlite3_clear_bindings(self.load_stmt);

        if (c.sqlite3_bind_int64(self.load_stmt, 1, @intCast(session_id)) != c.SQLITE_OK) {
            return error.SqliteBindFailed;
        }

        const rc = c.sqlite3_step(self.load_stmt);
        if (rc == c.SQLITE_ROW) {
            const x = c.sqlite3_column_double(self.load_stmt, 0);
            const y = c.sqlite3_column_double(self.load_stmt, 1);
            return PlayerState{ .x = @floatCast(x), .y = @floatCast(y) };
        }
        if (rc == c.SQLITE_DONE) {
            return null;
        }

        return error.SqliteStepFailed;
    }

    /// Lock-free enqueue (main thread only - Single Producer)
    pub fn queuePersist(self: *Self, session_id: u32, state: PlayerState) void {
        const write_idx = self.write_index.load(.acquire);
        const read_idx = self.read_index.load(.acquire);

        // Check if queue is full
        const next_write = (write_idx + 1) % MAX_PENDING;
        if (next_write == read_idx) {
            // Queue full - could log warning in production
            return;
        }

        // Write entry (no synchronization needed, only we write here)
        self.pending_queue[write_idx] = .{
            .session_id = session_id,
            .state = state,
        };

        // Publish write (release to make write visible to consumer)
        self.write_index.store(next_write, .release);
    }

    fn persistThreadFn(self: *Self) void {
        while (!self.should_stop.load(.acquire)) {
            std.Thread.sleep(FLUSH_INTERVAL_MS * std.time.ns_per_ms);

            if (self.should_stop.load(.acquire)) break;

            self.flushPendingSync();
        }
    }

    /// Lock-free dequeue and persist (persist thread only - Single Consumer, uses persist_db)
    fn flushPendingSync(self: *Self) void {
        // Load indices (acquire to see producer's writes)
        const write_idx = self.write_index.load(.acquire);
        var read_idx = self.read_index.load(.acquire);

        // Check if queue is empty
        if (read_idx == write_idx) {
            return; // Nothing to persist
        }

        // Calculate how many entries to read
        const count = if (write_idx > read_idx)
            write_idx - read_idx
        else
            (MAX_PENDING - read_idx) + write_idx;

        // Copy entries to local buffer (don't hold shared state during DB ops)
        var entries: [MAX_PENDING]PersistEntry = undefined;
        var copied: usize = 0;
        while (copied < count and read_idx != write_idx) {
            entries[copied] = self.pending_queue[read_idx];
            copied += 1;
            read_idx = (read_idx + 1) % MAX_PENDING;
        }

        // Publish read completion (release to make space available)
        self.read_index.store(read_idx, .release);

        if (copied == 0) return;

        // Build batch upsert SQL dynamically
        var sql_buf: [8192]u8 = undefined;
        var fbs = std.io.fixedBufferStream(&sql_buf);
        const writer = fbs.writer();

        const now = std.time.timestamp();

        writer.writeAll(
            \\INSERT INTO player_state (session_id, x, y, updated_at) VALUES 
            \\
        ) catch {
            std.debug.print("Failed to build batch upsert SQL\n", .{});
            return;
        };

        for (0..copied) |i| {
            const entry = entries[i];
            if (i > 0) {
                writer.writeAll(",\n") catch break;
            }
            writer.print("({d}, {d:.6}, {d:.6}, {d})", .{
                entry.session_id,
                entry.state.x,
                entry.state.y,
                now,
            }) catch break;
        }

        writer.writeAll(
            \\ ON CONFLICT(session_id) DO UPDATE SET
            \\  x = excluded.x,
            \\  y = excluded.y,
            \\  updated_at = excluded.updated_at;
        ) catch {
            std.debug.print("Failed to finalize batch upsert SQL\n", .{});
            return;
        };

        const sql = fbs.getWritten();

        // Need null-terminated string for sqlite3_exec
        var sql_z: [8192:0]u8 = undefined;
        @memcpy(sql_z[0..sql.len], sql);
        sql_z[sql.len] = 0;

        // No mutex needed! persist_db is only used by persist thread
        // Execute batch upsert in a transaction
        if (c.sqlite3_exec(self.persist_db, "BEGIN IMMEDIATE;", null, null, null) != c.SQLITE_OK) {
            std.debug.print("Failed to begin transaction for flush\n", .{});
            return;
        }

        if (c.sqlite3_exec(self.persist_db, sql_z[0..sql.len :0].ptr, null, null, null) != c.SQLITE_OK) {
            const err_msg = c.sqlite3_errmsg(self.persist_db);
            std.debug.print("Failed to execute batch upsert: {s}\n", .{err_msg});
            _ = c.sqlite3_exec(self.persist_db, "ROLLBACK;", null, null, null);
            return;
        }

        if (c.sqlite3_exec(self.persist_db, "COMMIT;", null, null, null) != c.SQLITE_OK) {
            std.debug.print("Failed to commit flush transaction\n", .{});
            _ = c.sqlite3_exec(self.persist_db, "ROLLBACK;", null, null, null);
            return;
        }

        std.debug.print("Persisted {d} player state(s) to database (lock-free + per-thread connections)\n", .{copied});
    }
};
