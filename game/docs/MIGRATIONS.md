# Database Migrations Guide

## Overview

The game uses a custom migration system built in Zig to manage SQLite schema changes. Migrations are defined in code (`src/db/migrations.zig`) and applied via a CLI tool (`zig-migrate`).

## Philosophy

- **Schema and data are separate concerns** from application logic
- Migrations run **before** the application starts, not during `init()`
- Each migration is versioned and tracked in the database
- Migrations are **idempotent** - safe to run multiple times

## Quick Start

```bash
# Build everything (including migration tool)
zig build

# Check current schema version
./zig-out/bin/zig-migrate status

# Apply all pending migrations
./zig-out/bin/zig-migrate up
```

## Migration File Structure

**Location:** `src/db/migrations.zig`

```zig
pub const Migration = struct {
    version: u32,
    name: [:0]const u8,
    up_sql: [:0]const u8,
};

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
    // Add new migrations here...
};
```

## Adding a New Migration

1. **Edit** `src/db/migrations.zig`
2. **Add** a new migration to the `migrations` array:
   ```zig
   .{
       .version = 2,  // Increment from last version
       .name = "add_inventory_table",
       .up_sql =
       \\CREATE TABLE inventory (
       \\  id INTEGER PRIMARY KEY AUTOINCREMENT,
       \\  session_id INTEGER NOT NULL,
       \\  item_id INTEGER NOT NULL,
       \\  quantity INTEGER NOT NULL,
       \\  FOREIGN KEY(session_id) REFERENCES player_state(session_id)
       \\);
       ,
   },
   ```
3. **Rebuild** the migration tool:
   ```bash
   zig build
   ```
4. **Apply** the migration:
   ```bash
   ./zig-out/bin/zig-migrate up
   ```

## Commands

### Status
Check which migrations have been applied:
```bash
./zig-out/bin/zig-migrate status
```

Example output:
```
Current schema version: 1

Migration status:
  [✓] 1: create_player_state_table
  [ ] 2: add_inventory_table
```

### Up (Apply)
Run all pending migrations:
```bash
./zig-out/bin/zig-migrate up
```

Example output:
```
Running migrations...
Current schema version: 1
Applying migration 2: add_inventory_table
✓ Migration 2 applied successfully
Applied 1 migration(s)
```

### Build.zig Shortcuts
You can also use `zig build` to run migrations:
```bash
zig build migrate -- status
zig build migrate -- up
```

## How It Works

### Migration Tracking

Migrations are tracked in the `schema_migrations` table:

```sql
CREATE TABLE schema_migrations (
  version INTEGER PRIMARY KEY,
  name TEXT NOT NULL,
  applied_at INTEGER NOT NULL
);
```

When you run `zig-migrate up`:
1. Opens database connection
2. Creates `schema_migrations` table if it doesn't exist
3. Queries current version: `SELECT MAX(version) FROM schema_migrations`
4. For each migration with `version > current_version`:
   - Begins transaction
   - Executes migration SQL
   - Inserts row into `schema_migrations`
   - Commits transaction

### Safety Features

- **Transactions**: Each migration runs in its own transaction (rollback on error)
- **Version tracking**: Prevents applying the same migration twice
- **Sequential order**: Migrations apply in version order
- **Error handling**: If a migration fails, the database rolls back and reports the error

## Best Practices

### DO:
- ✅ Always increment version numbers sequentially
- ✅ Use descriptive migration names (snake_case)
- ✅ Make migrations idempotent when possible (`CREATE TABLE IF NOT EXISTS`)
- ✅ Run migrations before starting the server
- ✅ Test migrations on a copy of production data before deploying
- ✅ Keep migrations small and focused on a single change

### DON'T:
- ❌ Don't modify existing migrations after they've been applied in production
- ❌ Don't skip version numbers
- ❌ Don't put multiple unrelated changes in one migration
- ❌ Don't assume data exists - check before updating
- ❌ Don't run migrations from multiple processes simultaneously

## Example Workflow

### Development
```bash
# First time setup
zig build
./zig-out/bin/zig-migrate up

# Start developing
./zig-out/bin/zig-server

# Add new feature requiring schema change
# 1. Edit src/db/migrations.zig
# 2. Add migration
# 3. Rebuild and apply
zig build
./zig-out/bin/zig-migrate up

# Continue development
./zig-out/bin/zig-server
```

### Production Deployment
```bash
# On production server
git pull origin main
zig build

# Check what will change
./zig-out/bin/zig-migrate status

# Apply migrations
./zig-out/bin/zig-migrate up

# Restart server
./zig-out/bin/zig-server
```

## Troubleshooting

### "Database not initialized"
Run migrations first:
```bash
./zig-out/bin/zig-migrate up
```

### "SqliteOpenFailed"
Check that:
- `data/` directory exists (it should, `.gitkeep` is tracked)
- You have write permissions
- SQLite3 is installed

### Migration Failed
- Check the error message for SQL syntax issues
- Test your SQL manually: `sqlite3 data/player_state.sqlite`
- The database will be rolled back automatically
- Fix the migration and rebuild

### "Table already exists" (not using IF NOT EXISTS)
If a migration partially applied:
```bash
# Option 1: Fix the SQL manually
sqlite3 data/player_state.sqlite
# Then manually insert into schema_migrations

# Option 2: Delete database and start fresh (dev only!)
rm data/player_state.sqlite*
./zig-out/bin/zig-migrate up
```

## Architecture Notes

**Why separate from PlayerStore.init()?**

- **Single Responsibility**: `PlayerStore` connects to the database; migrations manage schema
- **Explicit control**: Developers must consciously run migrations
- **Testability**: Can test against different schema versions
- **Production safety**: Schema changes are deliberate, not accidental
- **Version tracking**: Clear audit trail of schema evolution

**Why not use an ORM?**

- Zig philosophy: explicit over implicit
- Full control over SQL and performance
- No runtime overhead
- Easy to understand and debug
- Works well with SQLite's simplicity

## Future Enhancements

Possible improvements to the migration system:

- [ ] Rollback support (down migrations)
- [ ] Migration dry-run mode
- [ ] Backup before migration
- [ ] Migration dependencies/prerequisites
- [ ] SQL file imports instead of inline strings
- [ ] Checksum validation of applied migrations
