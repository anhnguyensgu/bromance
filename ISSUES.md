# Issue Tracker

## Critical Bugs

- [ ] **CRIT-1**: Race condition in double-buffered player updates
  - File: `game/src/client/game_state.zig:159-228`
  - Risk: Crash during render when buffer swaps mid-iteration

- [ ] **CRIT-2**: Unprotected plots ArrayList access
  - File: `game/src/client/game_state.zig:68-106`
  - Risk: Use-after-free if ArrayList reallocates

- [ ] **CRIT-3**: Network buffer overflow - payload_len not validated
  - File: `game/src/network.zig:410-419`
  - Risk: Malicious packet causes out-of-bounds slice

- [ ] **CRIT-4**: Network array bounds not validated
  - Files: `game/src/client/game_state.zig:74-89`, `network.zig:104-107`
  - Risk: Buffer overread from corrupted count fields

## High Severity

- [ ] **HIGH-1**: World dimensions not validated
  - File: `game/src/shared.zig:120-123`
  - Risk: Division by zero

- [ ] **HIGH-2**: WorldScreen god object (658 lines, 37+ fields)
  - File: `game/src/screens/world.zig`
  - Impact: Untestable, unmaintainable

- [ ] **HIGH-3**: shared.zig re-export hub (571 lines)
  - File: `game/src/shared.zig`
  - Impact: Circular dependencies

- [ ] **HIGH-4**: Character assets not using AssetCache
  - File: `game/src/character/player.zig:16-55`
  - Impact: Duplicate texture loading

- [ ] **HIGH-5**: Hardcoded server config
  - File: `game/src/screens/world.zig:138-139`
  - Impact: Can't change server without recompile

## Medium Severity

- [ ] **MED-1**: Constants not applied consistently
  - File: `game/src/character/player.zig:80-81`
  - Note: FRAME_WIDTH/HEIGHT reverted to hardcoded 32

- [ ] **MED-2**: Silent error suppression
  - Files: `world.zig:341`, `ghost_layer.zig:46`
  - Pattern: `catch {}`

- [ ] **MED-3**: Code duplication in collision logic
  - Files: `udp_client.zig`, `game_state.zig`

- [ ] **MED-4**: Dead code - empty action functions
  - File: `world.zig` - inventoryAction, buildAction, settingsAction

- [ ] **MED-5**: Unsafe pointer casts without validation
  - File: `world.zig:198-211`

## Low Severity

- [ ] **LOW-1**: Hardcoded magic numbers (40+ instances)
- [ ] **LOW-2**: Inconsistent naming conventions
- [ ] **LOW-3**: Missing bounds checking in landscape.zig
- [ ] **LOW-4**: state.zig GameState unused

## Architecture Refactoring (Future)

- [ ] **ARCH-1**: Create InputHandler abstraction
- [ ] **ARCH-2**: Create NetworkService interface
- [ ] **ARCH-3**: Unify asset loading through AssetCache
- [ ] **ARCH-4**: Break WorldScreen into subsystems
- [ ] **ARCH-5**: Establish clear UI architecture
