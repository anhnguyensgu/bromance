const std = @import("std");
const rl = @import("raylib");
const shared = @import("../shared.zig");

const player_mod = @import("../character/player.zig");
const Character = player_mod.Character;
const CharacterAssets = player_mod.CharacterAssets;

const ClientGameState = @import("../client/game_state.zig").ClientGameState;
const client = @import("../client/udp_client.zig");
const UdpClient = @import("../client/udp_client.zig").UdpClient;
const applyMoveToVector = client.applyMoveToVector;

const command = @import("../movement/command.zig");
const MovementCommand = @import("../movement/command.zig").MovementCommand;
const MoveDirection = command.MoveDirection;

const ui_menu = @import("../ui/menu.zig");
const MenuItem = ui_menu.MenuItem;
const Menu = ui_menu.Menu;

const plot_ui = @import("../plot/plot_ui.zig");
const PlotRenderStyle = plot_ui.PlotRenderStyle;
const plot_decoration = @import("../plot/plot_decoration.zig");
const Plot = @import("../plot/plot.zig").Plot;

const Frames = shared.Frames;
const LandscapeTile = shared.LandscapeTile;
const SceneAction = @import("../core/scene_action.zig").SceneAction;

pub const WorldScreen = struct {
    allocator: std.mem.Allocator,
    world: shared.World,
    player: Character,
    assets: CharacterAssets,

    game_state: *ClientGameState,
    udp_client: UdpClient,
    net_thread: std.Thread,

    camera: rl.Camera2D,
    minimap: rl.RenderTexture2D,

    // Textures & Sprites
    tileset_texture: rl.Texture2D,
    townhall_texture: rl.Texture2D,
    lake_texture: rl.Texture2D,
    fence_asset: shared.sheets.FenceAsset,
    grass: Frames,

    // UI
    top_menu: Menu,
    menu_texture: rl.Texture2D,
    map_opened: bool = false,
    active_menu_item: ?usize = null,

    // Plot system
    plot_style: PlotRenderStyle,
    show_plots: bool = true,
    show_tile_grid: bool = false,
    show_fences: bool = true,
    show_sprite_debug: bool = false,
    selected_plot_id: ?u64 = null,
    nearby_plot_id: ?u64 = null,

    // Constants
    const MINIMAP_SIZE: i32 = 180;
    const UI_MARGIN_PX: i32 = 32;
    const MENU_HEIGHT: i32 = 48;
    const SPEED: f32 = 200.0;

    pub fn init(ctx: anytype) !WorldScreen {
        const allocator = ctx.allocator;
        const screen_width = ctx.screen_width;
        const screen_height = ctx.screen_height;
        const assets_cache = ctx.assets;

        // Load World
        var world = shared.World.loadFromFile(allocator, "assets/worldoutput.json") catch |err| blk: {
            std.debug.print("Could not load worldoutput.json: {}, falling back to world.json\n", .{err});
            break :blk try shared.World.loadFromFile(allocator, "assets/world.json");
        };
        errdefer world.deinit(allocator);

        // Assets
        // CharacterAssets handles its own loading for now, could be refactored later to use cache
        const char_assets = try CharacterAssets.loadMainCharacter();
        errdefer char_assets.deinit();

        const tileset_texture = try assets_cache.getTexture("assets/farmrpg/tileset/tilesetspring.png");
        const townhall_texture = try assets_cache.getTexture("assets/farmrpg/objects/house.png");

        // Lake texture specific filter
        const lake_texture = try assets_cache.getTexture("assets/lakesmall.png");
        rl.setTextureFilter(lake_texture, .point);

        const fence_texture = try assets_cache.getTexture("assets/farmrpg/objects/fencescopiar.png");
        rl.setTextureFilter(fence_texture, .point);
        const fence_asset = shared.sheets.FenceAsset.init(fence_texture);

        const grass = Frames{
            .SpringTiles = .{
                .Grass = LandscapeTile.init(tileset_texture, 8.0, 0.0),
            },
        };

        const menu_texture = try assets_cache.getTexture("assets/interface/0.png");
        const top_menu = Menu.init(menu_texture, .{});

        // Player & Camera
        const player = Character.init(rl.Vector2{ .x = 350, .y = 200 }, rl.Vector2{ .x = 16, .y = 16 });
        const camera = rl.Camera2D{
            .target = .init(player.pos.x + 20, player.pos.y + 20),
            .offset = .init(@as(f32, @floatFromInt(screen_width)) / 2.0, @as(f32, @floatFromInt(screen_height)) / 2.0),
            .rotation = 0,
            .zoom = 2,
        };

        // Minimap
        const minimap = try rl.loadRenderTexture(MINIMAP_SIZE, MINIMAP_SIZE);
        errdefer rl.unloadRenderTexture(minimap);

        // Network
        const game_state = try allocator.create(ClientGameState);
        game_state.* = try ClientGameState.init(allocator);

        // We pass the heap pointer to UdpClient, so it stays valid
        const udp_client = try UdpClient.init(game_state, world, .{
            .server_ip = "127.0.0.1",
            .server_port = 9999,
        });

        return WorldScreen{
            .allocator = allocator,
            .world = world,
            .player = player,
            .assets = char_assets,
            .game_state = game_state,
            .udp_client = udp_client,
            .net_thread = undefined, // Set in start()
            .camera = camera,
            .minimap = minimap,
            .tileset_texture = tileset_texture,
            .townhall_texture = townhall_texture,
            .lake_texture = lake_texture,
            .fence_asset = fence_asset,
            .grass = grass,
            .top_menu = top_menu,
            .menu_texture = menu_texture,
            .plot_style = PlotRenderStyle{},
        };
    }

    // Must be called after struct is in its final location (e.g. allocated on heap or stable stack var)
    pub fn start(self: *WorldScreen) !void {
        self.net_thread = try std.Thread.spawn(.{}, UdpClient.run, .{&self.udp_client});
    }

    pub fn deinit(self: *WorldScreen) void {
        self.udp_client.running.store(false, .release);
        self.net_thread.join();

        self.udp_client.deinit();
        self.game_state.deinit();
        self.allocator.destroy(self.game_state);

        rl.unloadRenderTexture(self.minimap);

        self.top_menu.deinit();
        // Textures loaded via AssetCache are not owned by us, do NOT unload them here (except maybe minimap)
        // rl.unloadTexture(self.menu_texture);
        // rl.unloadTexture(self.lake_texture);
        // rl.unloadTexture(self.townhall_texture);
        // rl.unloadTexture(self.tileset_texture);

        self.assets.deinit();
        self.world.deinit(self.allocator);
    }

    // Helper to match menu actions
    fn toggle_map(self: *WorldScreen) void {
        self.map_opened = !self.map_opened;
    }
    fn inventoryAction() void {}
    fn buildAction() void {}
    fn settingsAction() void {}
    fn onMapAction(ctx: ?*anyopaque) void {
        const self: *WorldScreen = @ptrCast(@alignCast(ctx orelse return));
        self.toggle_map();
    }
    fn onInventoryAction(ctx: ?*anyopaque) void {
        _ = ctx;
        inventoryAction();
    }
    fn onBuildAction(ctx: ?*anyopaque) void {
        _ = ctx;
        buildAction();
    }
    fn onSettingsAction(ctx: ?*anyopaque) void {
        _ = ctx;
        settingsAction();
    }

    pub fn update(self: *WorldScreen, dt: f32, ctx: anytype) SceneAction {
        _ = ctx; // potentially unused

        var move_cmd: ?MovementCommand = null;

        // Handle keyboard input
        if (rl.isKeyDown(.w) or rl.isKeyDown(.up)) {
            move_cmd = .{ .direction = .Up, .speed = SPEED, .delta = dt };
        } else if (rl.isKeyDown(.s) or rl.isKeyDown(.down)) {
            move_cmd = .{ .direction = .Down, .speed = SPEED, .delta = dt };
        } else if (rl.isKeyDown(.a) or rl.isKeyDown(.left)) {
            move_cmd = .{ .direction = .Left, .speed = SPEED, .delta = dt };
        } else if (rl.isKeyDown(.d) or rl.isKeyDown(.right)) {
            move_cmd = .{ .direction = .Right, .speed = SPEED, .delta = dt };
        } else if (rl.isKeyPressed(.m)) {
            self.toggle_map();
        } else if (rl.isKeyPressed(.p)) {
            // Toggle plot visibility
            self.show_plots = !self.show_plots;
        } else if (rl.isKeyPressed(.g)) {
            self.show_tile_grid = !self.show_tile_grid;
        } else if (rl.isKeyPressed(.f)) {
            self.show_fences = !self.show_fences;
        } else if (rl.isKeyPressed(.n)) {
            self.show_sprite_debug = !self.show_sprite_debug;
        }

        self.nearby_plot_id = findNearbyPlot(self.game_state.getPlots(), self.world, self.player);

        if (rl.isKeyPressed(.e)) {
            if (self.nearby_plot_id) |plot_id| {
                self.selected_plot_id = plot_id;
                if (self.game_state.getPlotById(plot_id)) |plot| {
                    std.debug.print("Selected plot #{} at ({}, {}), size {}x{}\n", .{
                        plot.id,
                        plot.tile_x,
                        plot.tile_y,
                        plot.width_tiles,
                        plot.height_tiles,
                    });
                    if (plot.owner.kind != .none) {
                        std.debug.print("  Owner: {any}\n", .{plot.owner});
                    } else {
                        std.debug.print("  Unclaimed\n", .{});
                    }
                }
            } else {
                self.selected_plot_id = null;
            }
        }

        if (move_cmd) |cmd| {
            applyMoveToVector(&self.player.pos, cmd, self.world);
            _ = self.game_state.pushInput(cmd);
        }

        // Camera Update
        self.camera.target = self.player.pos;
        updateCameraFocus(&self.camera, self.player, @intFromFloat(self.camera.offset.x * 2 / self.camera.zoom), @intFromFloat(self.camera.offset.y * 2 / self.camera.zoom), self.world);

        // Interpolate Local Player
        if (self.game_state.sampleInterpolated()) |pos| {
            self.player.pos = pos;
        }

        if (move_cmd) |cmd| {
            self.player.update(dt, cmd.direction, true);
        } else {
            self.player.update(dt, .Down, false);
        }

        return .None;
    }

    pub fn draw(self: *WorldScreen, ctx: anytype) void {
        const screen_width = ctx.screen_width;
        const screen_height = ctx.screen_height;
        // Rendering
        var render_camera = self.camera;
        render_camera.target.x = @floor(self.camera.target.x * self.camera.zoom) / self.camera.zoom;
        render_camera.target.y = @floor(self.camera.target.y * self.camera.zoom) / self.camera.zoom;
        // ensure offsets are correct based on current screen size (if resized)
        render_camera.offset = .init(@as(f32, @floatFromInt(screen_width)) / 2.0, @as(f32, @floatFromInt(screen_height)) / 2.0);

        rl.beginMode2D(render_camera);

        shared.drawGrassBackground(self.grass, self.world);

        // Draw plots before buildings (so buildings appear on top)
        if (self.show_plots) {
            const fence = if (self.show_fences) self.fence_asset else null;
            const plots = self.game_state.getPlots();
            plot_ui.drawAllPlots(plots, self.world, self.plot_style, self.selected_plot_id, self.nearby_plot_id, fence);
        }

        if (self.show_tile_grid) {
            plot_ui.drawTileGrid(self.world, rl.Color.init(255, 255, 255, 30));
        }

        if (self.show_fences) {
            const plots = self.game_state.getPlots();
            for (plots) |plot| {
                plot_decoration.drawPlotFenceBorder(self.fence_asset, plot, self.world, self.show_sprite_debug);
            }
        }

        drawConstruction(self.townhall_texture, self.lake_texture, self.tileset_texture, self.world);

        // Draw Other Players
        {
            const other_players = self.game_state.getOtherPlayersForRender();
            var it = other_players.iterator();
            while (it.next()) |entry| {
                const other_player = entry.value_ptr.*;
                drawOtherPlayer(other_player, self.assets);
            }
        }

        self.player.draw(self.assets) catch {};

        // Draw plot info for selected plot
        if (self.selected_plot_id) |plot_id| {
            if (self.game_state.getPlotById(plot_id)) |plot| {
                plot_ui.drawPlotInfo(plot.*, self.world, 16);
            }
        }

        rl.endMode2D();

        // Menu
        // We need to construct menu items wrapper to call methods on self
        // This is tricky because Menu expects static functions in main.zig, but here we want instance methods?
        // ui/menu.zig MenuItem action is `*const fn () void`. It does not take context.
        // HACK: For now, map toggle is internal. Inventory etc are placeholders.
        // We can replicate the static functions wrapper or change Menu to support context.
        // Given existing code, let's keep it simple.

        // Just use local wrapper structs for the menu drawing if needed or passing specific actions.
        // The original used `toggle_map` which modified global state.
        // We can't pass `self.toggle_map` to `MenuItem` because it expects a function pointer, not a delegate.
        // WORKAROUND: For this refactor, we can skip the menu functionality or hardcode checks.
        // OR, we can make the menu items do nothing and handle keys directly (like 'M').
        // Let's handle keys directly for now to be safe and avoid static globals.
        // I will stub the menu actions.

        const menu_items = [_]MenuItem{};
        self.top_menu.drawAsSidebar(250, screen_height, menu_items[0..], &self.active_menu_item, "Construction");

        if (self.map_opened) {
            const minimap_pos = rl.Vector2{
                .x = @as(f32, @floatFromInt(UI_MARGIN_PX)),
                .y = @as(f32, @floatFromInt(MENU_HEIGHT + UI_MARGIN_PX)),
            };
            updateMinimap(self.minimap, self.player.pos, self.world, @floatFromInt(MINIMAP_SIZE), minimap_pos);
        }

        var buf: [128]u8 = undefined;
        const pos_text = std.fmt.bufPrintZ(&buf, "Player: ({:.0}, {:.0})", .{ self.player.pos.x, self.player.pos.y }) catch "";
        const pos_x = screen_width - 300;
        const pos_y = 10;
        rl.drawText(pos_text, pos_x, pos_y, 20, .dark_gray);
        rl.drawFPS(pos_x, pos_y + 24);

        // Plot controls help text
        const help_y = screen_height - 80;
        rl.drawText("P: Plots | G: Grid | F: Fences | B: Debug | M: Map", 10, help_y, 16, rl.Color.init(200, 200, 200, 255));

        if (self.nearby_plot_id) |plot_id| {
            var nearby_buf: [64]u8 = undefined;
            const nearby_text = std.fmt.bufPrintZ(&nearby_buf, "Press E to select Plot #{}", .{plot_id}) catch "";
            rl.drawText(nearby_text, 10, help_y + 20, 20, rl.Color.init(255, 255, 0, 255));
        }

        if (self.show_sprite_debug) {
            self.fence_asset.drawDebug();
        }
    }
};

// Helper Functions (Copied from main.zig)

fn findNearbyPlot(plots: []const Plot, world: shared.World, player: Character) ?u64 {
    const player_rect = rl.Rectangle{
        .x = player.pos.x,
        .y = player.pos.y,
        .width = player.size.x,
        .height = player.size.y,
    };

    const player_center_x = player.pos.x + player.size.x / 2.0;
    const player_center_y = player.pos.y + player.size.y / 2.0;

    var closest_plot_id: ?u64 = null;
    var closest_distance: f32 = std.math.floatMax(f32);

    const tile_w = world.width / @as(f32, @floatFromInt(world.tiles_x));
    const tile_h = world.height / @as(f32, @floatFromInt(world.tiles_y));

    for (plots) |plot| {
        const plot_x = world.tileToWorldX(plot.tile_x);
        const plot_y = world.tileToWorldY(plot.tile_y);
        const plot_w = @as(f32, @floatFromInt(plot.width_tiles)) * tile_w;
        const plot_h = @as(f32, @floatFromInt(plot.height_tiles)) * tile_h;

        const plot_rect = rl.Rectangle{
            .x = plot_x,
            .y = plot_y,
            .width = plot_w,
            .height = plot_h,
        };

        if (rl.checkCollisionRecs(player_rect, plot_rect)) {
            const plot_center_x = plot_x + plot_w / 2.0;
            const plot_center_y = plot_y + plot_h / 2.0;

            const dx = player_center_x - plot_center_x;
            const dy = player_center_y - plot_center_y;
            const distance = @sqrt(dx * dx + dy * dy);

            if (distance < closest_distance) {
                closest_distance = distance;
                closest_plot_id = plot.id;
            }
        }
    }

    return closest_plot_id;
}

fn updateCameraFocus(camera: *rl.Camera2D, player: Character, screen_width: i32, screen_height: i32, world: shared.World) void {
    const view_half_w: f32 = (@as(f32, @floatFromInt(screen_width)) * 0.5) / camera.zoom;
    const view_half_h: f32 = (@as(f32, @floatFromInt(screen_height)) * 0.5) / camera.zoom;
    var cam_target_x: f32 = player.pos.x + player.size.x * 0.5;
    var cam_target_y: f32 = player.pos.y + player.size.y * 0.5;

    cam_target_x = std.math.clamp(cam_target_x, view_half_w * 2, world.width - view_half_w * 2);
    cam_target_y = std.math.clamp(cam_target_y, view_half_h * 2, world.height - view_half_h * 2);
    camera.target = .init(cam_target_x, cam_target_y);
}

fn drawConstruction(townhall_texture: rl.Texture2D, lake_texture: rl.Texture2D, tileset_texture: rl.Texture2D, world: shared.World) void {
    const tile_w = world.width / @as(f32, @floatFromInt(world.tiles_x));
    const tile_h = world.height / @as(f32, @floatFromInt(world.tiles_y));

    for (world.buildings) |building| {
        const building_x = world.tileToWorldX(building.tile_x);
        const building_y = world.tileToWorldY(building.tile_y);

        const building_source = rl.Rectangle{
            .x = building.sprite_x,
            .y = building.sprite_y,
            .width = building.sprite_width,
            .height = building.sprite_height,
        };

        const building_dest = rl.Rectangle{
            .x = building_x,
            .y = building_y,
            .width = @as(f32, @floatFromInt(building.width_tiles)) * tile_w,
            .height = @as(f32, @floatFromInt(building.height_tiles)) * tile_h,
        };

        const texture = switch (building.building_type) {
            .Townhall, .House => townhall_texture,
            .Lake => lake_texture,
            .Tile, .Road => tileset_texture,
            else => continue,
        };

        rl.drawTexturePro(texture, building_source, building_dest, rl.Vector2{ .x = 0, .y = 0 }, 0, .white);
    }
}

fn drawOtherPlayer(other_player: anytype, assets: CharacterAssets) void {
    const now_ns: i64 = @intCast(std.time.nanoTimestamp());
    const stale_timeout_ns: i64 = 500_000_000;
    const is_moving = other_player.is_moving and (now_ns - other_player.last_update_ns <= stale_timeout_ns);

    const shadow_dest = rl.Rectangle{
        .x = other_player.pos.x,
        .y = other_player.pos.y + 2,
        .width = 32,
        .height = 32,
    };
    rl.drawTexturePro(assets.shadow, .{ .x = 0, .y = 0, .width = 32, .height = 32 }, shadow_dest, .{ .x = 0, .y = 0 }, 0, .white);

    const texture = if (is_moving) switch (other_player.dir) {
        .Up => assets.walk_up,
        .Down => assets.walk_down,
        .Left => assets.walk_left,
        .Right => assets.walk_right,
    } else switch (other_player.dir) {
        .Up => assets.idle_up,
        .Down => assets.idle_down,
        .Left => assets.idle_left,
        .Right => assets.idle_right,
    };

    const frame_count: f32 = if (is_moving) 4.0 else 9.0;
    const anim_speed: f32 = 8.0;
    const global_time = rl.getTime();
    const frame: i32 = @intFromFloat(@mod(global_time * anim_speed, frame_count));

    const src = rl.Rectangle{
        .x = @as(f32, @floatFromInt(frame * 32)),
        .y = 0,
        .width = 32,
        .height = 32,
    };
    const dest = rl.Rectangle{
        .x = other_player.pos.x,
        .y = other_player.pos.y,
        .width = 32,
        .height = 32,
    };
    rl.drawTexturePro(texture, src, dest, rl.Vector2{ .x = 0, .y = 0 }, 0, rl.Color{ .r = 200, .g = 200, .b = 255, .a = 255 });
}

fn updateMinimap(target: rl.RenderTexture2D, player_pos: rl.Vector2, world: shared.World, size: f32, MINIMAP_POS: rl.Vector2) void {
    {
        rl.beginTextureMode(target);
        defer rl.endTextureMode();

        rl.clearBackground(rl.Color.light_gray);

        for (world.buildings) |building| {
            const building_x = world.tileToWorldX(building.tile_x);
            const building_y = world.tileToWorldY(building.tile_y);
            const building_w = world.tileToWorldX(building.width_tiles);
            const building_h = world.tileToWorldY(building.height_tiles);

            const minimap_x = (building_x / world.width) * size;
            const minimap_y = (building_y / world.height) * size;
            const minimap_w = (building_w / world.width) * size;
            const minimap_h = (building_h / world.height) * size;

            const building_color = switch (building.building_type) {
                .Townhall => rl.Color.gold,
                .House => rl.Color.orange,
                .Shop => rl.Color.purple,
                .Farm => rl.Color.green,
                .Lake => rl.Color.blue,
                .Road => rl.Color.brown,
                .Tile => rl.Color.gray,
            };

            rl.drawRectangle(@intFromFloat(minimap_x), @intFromFloat(minimap_y), @intFromFloat(minimap_w), @intFromFloat(minimap_h), building_color);
        }

        const px = (player_pos.x / world.width) * size;
        const py = (player_pos.y / world.height) * size;
        rl.drawCircle(@intFromFloat(px), @intFromFloat(py), 4, rl.Color.red);
    }

    const src = rl.Rectangle{
        .x = 0,
        .y = 0,
        .width = @as(f32, @floatFromInt(target.texture.width)),
        .height = -@as(f32, @floatFromInt(target.texture.height)),
    };
    const dst = rl.Rectangle{
        .x = MINIMAP_POS.x,
        .y = MINIMAP_POS.y,
        .width = @as(f32, size),
        .height = @as(f32, size),
    };
    rl.drawTexturePro(target.texture, src, dst, rl.Vector2{ .x = 0, .y = 0 }, 0, .white);
    rl.drawRectangleLines(@intFromFloat(dst.x), @intFromFloat(dst.y), @intFromFloat(size), @intFromFloat(size), .black);
}
