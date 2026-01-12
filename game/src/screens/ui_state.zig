// ==================================================================================
// UI State - Presentation Layer Only
// ==================================================================================
// This module contains UI display state for the game's heads-up display.
// RESPONSIBILITIES: Tracks visual state like stamina, hearts, coins, inventory
// DO NOT USE FOR: Game logic, player position, network state, world data
//
// Separation from other states:
// - UIState (this file): HUD display values only
// - ClientGameState (client/game_state.zig): Network synchronization, snapshots
// - Character (game/player.zig): Entity position and animation state
// - World (core/world.zig): World data and collision
// ==================================================================================

const std = @import("std");

pub const MAX_INVENTORY_SLOTS: usize = 6;

pub const InventoryItem = struct {
    name: []const u8,
    quantity: u8,
};

pub const UIState = struct {
    // UI display state - not game logic
    day_number: u32,
    is_day: bool,
    stamina: f32,
    hearts_current: u8,
    hearts_max: u8,
    coins_value: u32,
    inventory_slots: [MAX_INVENTORY_SLOTS]?InventoryItem,

    pub fn sample() UIState {
        return .{
            .day_number = 3,
            .is_day = true,
            .stamina = 0.68,
            .hearts_current = 5,
            .hearts_max = 6,
            .coins_value = 47,
            .inventory_slots = .{
                InventoryItem{ .name = "Wood Plank", .quantity = 12 },
                InventoryItem{ .name = "Stone", .quantity = 6 },
                InventoryItem{ .name = "Torch", .quantity = 2 },
                InventoryItem{ .name = "Berry", .quantity = 5 },
                null,
                null,
            },
        };
    }

    pub fn inventory(self: *const UIState) []const ?InventoryItem {
        return self.inventory_slots[0..];
    }

    pub fn inventoryCount(self: *const UIState) usize {
        var count: usize = 0;
        for (self.inventory_slots) |slot| {
            if (slot != null) {
                count += 1;
            }
        }
        return count;
    }

    pub fn inventoryCapacity(self: *const UIState) usize {
        return self.inventory_slots.len;
    }

    pub fn dayNumber(self: *const UIState) u32 {
        return self.day_number;
    }

    pub fn cycleLabel(self: *const UIState) []const u8 {
        return if (self.is_day) "Day" else "Night";
    }

    pub fn staminaPercent(self: *const UIState) f32 {
        return std.math.clamp(self.stamina, 0.0, 1.0);
    }

    pub fn hearts(self: *const UIState) u8 {
        return self.hearts_current;
    }

    pub fn maxHearts(self: *const UIState) u8 {
        return self.hearts_max;
    }

    pub fn coins(self: *const UIState) u32 {
        return self.coins_value;
    }
};
