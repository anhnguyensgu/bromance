const std = @import("std");

const c = @cImport({
    @cInclude("sqlite3.h");
});

/// Migration definition
pub const Migration = struct {
    version: u32,
    name: [:0]const u8,
    up_sql: [:0]const u8,
};

/// All migrations in order
pub const migrations = [_]Migration{
    .{
        .version = 1,
        .name = "create_player_state_table",
        .up_sql =
        \\CREATE TABLE IF NOT EXISTS player_state (
        \\  session_id INTEGER PRIMARY KEY,
        \\  x REAL NOT NULL,
        \\  y REAL NOT NULL,
        \\  updated_at INTEGER NOT NULL
        \\);
        ,
    },
};

/// Initialize the migrations metadata table
fn initMigrationsTable(db: *c.sqlite3) !void {
    const sql =
        \\CREATE TABLE IF NOT EXISTS schema_migrations (
        \\  version INTEGER PRIMARY KEY,
        \\  name TEXT NOT NULL,
        \\  applied_at INTEGER NOT NULL
        \\);
    ;

    if (c.sqlite3_exec(db, sql, null, null, null) != c.SQLITE_OK) {
        const err_msg = c.sqlite3_errmsg(db);
        std.debug.print("Failed to create migrations table: {s}\n", .{err_msg});
        return error.SqliteExecFailed;
    }
}

/// Get the current schema version
fn getCurrentVersion(db: *c.sqlite3) !u32 {
    const sql = "SELECT MAX(version) FROM schema_migrations;";
    var stmt: ?*c.sqlite3_stmt = null;

    if (c.sqlite3_prepare_v2(db, sql, -1, &stmt, null) != c.SQLITE_OK) {
        return error.SqlitePrepareFailed;
    }
    defer _ = c.sqlite3_finalize(stmt);

    const rc = c.sqlite3_step(stmt);
    if (rc == c.SQLITE_ROW) {
        const version = c.sqlite3_column_int64(stmt, 0);
        if (version > 0) {
            return @intCast(version);
        }
    }

    return 0; // No migrations applied yet
}

/// Record a migration as applied
fn recordMigration(db: *c.sqlite3, migration: Migration) !void {
    const sql = "INSERT INTO schema_migrations (version, name, applied_at) VALUES (?1, ?2, ?3);";
    var stmt: ?*c.sqlite3_stmt = null;

    if (c.sqlite3_prepare_v2(db, sql, -1, &stmt, null) != c.SQLITE_OK) {
        return error.SqlitePrepareFailed;
    }
    defer _ = c.sqlite3_finalize(stmt);

    if (c.sqlite3_bind_int64(stmt, 1, @intCast(migration.version)) != c.SQLITE_OK) {
        return error.SqliteBindFailed;
    }
    // Use null destructor (SQLite copies the string)
    if (c.sqlite3_bind_text(stmt, 2, migration.name.ptr, @intCast(migration.name.len), null) != c.SQLITE_OK) {
        return error.SqliteBindFailed;
    }
    const now: i64 = std.time.timestamp();
    if (c.sqlite3_bind_int64(stmt, 3, now) != c.SQLITE_OK) {
        return error.SqliteBindFailed;
    }

    if (c.sqlite3_step(stmt) != c.SQLITE_DONE) {
        return error.SqliteStepFailed;
    }
}

/// Run all pending migrations
pub fn migrate(db_path: [:0]const u8) !void {
    var db_ptr: ?*c.sqlite3 = null;

    if (c.sqlite3_open(db_path.ptr, &db_ptr) != c.SQLITE_OK) {
        std.debug.print("Failed to open database: {s}\n", .{db_path});
        return error.SqliteOpenFailed;
    }
    defer _ = c.sqlite3_close(db_ptr);

    const db = db_ptr orelse return error.SqliteOpenFailed;

    // Enable WAL mode for better concurrency (persistent, stored in DB file)
    if (c.sqlite3_exec(db, "PRAGMA journal_mode=WAL;", null, null, null) != c.SQLITE_OK) {
        return error.SqliteExecFailed;
    }
    // Set synchronous mode for performance (per-connection, not persistent)
    // Note: Application code must also set this when opening connections
    if (c.sqlite3_exec(db, "PRAGMA synchronous=NORMAL;", null, null, null) != c.SQLITE_OK) {
        return error.SqliteExecFailed;
    }

    // Initialize migrations table
    try initMigrationsTable(db);

    // Get current version
    const current_version = try getCurrentVersion(db);
    std.debug.print("Current schema version: {d}\n", .{current_version});

    // Run pending migrations
    var applied_count: u32 = 0;
    for (migrations) |migration| {
        if (migration.version <= current_version) {
            continue;
        }

        std.debug.print("Applying migration {d}: {s}\n", .{ migration.version, migration.name });

        // Begin transaction
        if (c.sqlite3_exec(db, "BEGIN IMMEDIATE;", null, null, null) != c.SQLITE_OK) {
            std.debug.print("Failed to begin transaction\n", .{});
            return error.SqliteExecFailed;
        }

        // Run migration SQL
        if (c.sqlite3_exec(db, migration.up_sql, null, null, null) != c.SQLITE_OK) {
            const err_msg = c.sqlite3_errmsg(db);
            std.debug.print("Migration failed: {s}\n", .{err_msg});
            _ = c.sqlite3_exec(db, "ROLLBACK;", null, null, null);
            return error.MigrationFailed;
        }

        // Record migration
        recordMigration(db, migration) catch |err| {
            std.debug.print("Failed to record migration: {}\n", .{err});
            _ = c.sqlite3_exec(db, "ROLLBACK;", null, null, null);
            return err;
        };

        // Commit transaction
        if (c.sqlite3_exec(db, "COMMIT;", null, null, null) != c.SQLITE_OK) {
            std.debug.print("Failed to commit migration\n", .{});
            _ = c.sqlite3_exec(db, "ROLLBACK;", null, null, null);
            return error.SqliteExecFailed;
        }

        std.debug.print("✓ Migration {d} applied successfully\n", .{migration.version});
        applied_count += 1;
    }

    if (applied_count == 0) {
        std.debug.print("No pending migrations\n", .{});
    } else {
        std.debug.print("Applied {d} migration(s)\n", .{applied_count});
    }
}

/// Show migration status
pub fn status(db_path: [:0]const u8) !void {
    var db_ptr: ?*c.sqlite3 = null;

    if (c.sqlite3_open(db_path.ptr, &db_ptr) != c.SQLITE_OK) {
        std.debug.print("Failed to open database: {s}\n", .{db_path});
        return error.SqliteOpenFailed;
    }
    defer _ = c.sqlite3_close(db_ptr);

    const db = db_ptr orelse return error.SqliteOpenFailed;

    // Check if migrations table exists
    const check_sql = "SELECT name FROM sqlite_master WHERE type='table' AND name='schema_migrations';";
    var check_stmt: ?*c.sqlite3_stmt = null;
    if (c.sqlite3_prepare_v2(db, check_sql, -1, &check_stmt, null) != c.SQLITE_OK) {
        return error.SqlitePrepareFailed;
    }
    defer _ = c.sqlite3_finalize(check_stmt);

    const has_table = c.sqlite3_step(check_stmt) == c.SQLITE_ROW;

    if (!has_table) {
        std.debug.print("Database not initialized. Run migrations first.\n", .{});
        std.debug.print("\nPending migrations:\n", .{});
        for (migrations) |migration| {
            std.debug.print("  [ ] {d}: {s}\n", .{ migration.version, migration.name });
        }
        return;
    }

    const current_version = try getCurrentVersion(db);
    std.debug.print("Current schema version: {d}\n", .{current_version});
    std.debug.print("\nMigration status:\n", .{});

    for (migrations) |migration| {
        if (migration.version <= current_version) {
            std.debug.print("  [✓] {d}: {s}\n", .{ migration.version, migration.name });
        } else {
            std.debug.print("  [ ] {d}: {s}\n", .{ migration.version, migration.name });
        }
    }
}
