# Camera, Zoom, and Tile Seams

This document explains why thin white lines can appear between tiles when the camera moves or zooms, and how we fix it in the editor (`tile_inspector.zig`).

---

## 1. Symptom

- In the tile editor, when you **move** or especially when you **zoom** the camera, you sometimes see **1‑pixel white (or background‑colored) lines** between tiles.
- At zoom 1.0 and with the camera not moving, everything usually looks fine.

These lines are *not* gaps in the tile grid; they are rendering artifacts.

---

## 2. Why it Happens

### 2.1 World → Screen Transform

Raylib uses a `Camera2D` to transform from world space to screen space. Conceptually, for one axis:

```text
screen_x = (world_x - camera.target.x) * camera.zoom + camera.offset.x
```

- Tiles live on an integer grid in **world space**: `0, 16, 32, 48, ...`.
- `camera.target` and `camera.zoom` are **floats** and can be fractional when you pan/zoom.

When `(world_x - camera.target.x) * camera.zoom` is **not an integer**, tile edges land on **sub‑pixel positions** (e.g. `127.3px`, `143.7px`). The GPU has to sample between pixels and between texels in the spritesheet.

Because of that, the GPU blends:

- Between the tile and whatever sits next to it in the **texture** (neighbor tile / padding), and
- Between adjacent pixels on the **screen**.

This blending shows up as thin lines between tiles.

### 2.2 Zoom Makes It Worse

Zoom multiplies everything:

```text
screen_x = (world_x - camera.target.x) * zoom + offset
```

Even if `camera.target.x` is an integer, a non‑integer `zoom` will push the tile edges onto fractional pixel coordinates.

So there are two main ways to get seams:

1. `camera.target` is fractional.
2. `zoom` is fractional.

In our editor we want **smooth camera movement and smooth zoom**, so both of those are normally true.

---

## 3. Naïve Fixes (and Why We Avoid Them)

### 3.1 Snap the Camera Itself

We could force:

```zig
camera.target.x = @floor(camera.target.x);
camera.target.y = @floor(camera.target.y);
```

This helps a bit, but:

- It makes the camera move in **discrete pixel steps**, not truly smoothly.
- Any logic that reads `camera.target` (e.g. focusing, UI placement, minimap) now sees a **quantized** value instead of the real smooth one.
- It still doesnt fully fix the problem when `zoom` is not 1.0, because `zoom` itself introduces fractional screen positions.

### 3.2 Force Integer Zoom Only

We could only allow zoom 1x, 2x, 3x, ... and snap `camera.zoom` to integers. That would avoid some artifacts, but:

- Zoom feels **chunky** and not smooth.
- Still doesnt help if the camera target is fractional.

We want **smooth camera** *and* **smooth zoom**, so we need a different approach.

---

## 4. The Actual Fix: Render Camera Snapped in Screen Space

We separate the idea of **logical camera** (used by game logic and input) from **render camera** (used only for drawing):

- `camera`  
  - Holds the true, smooth camera state.  
  - Updated from input (`WASD`, mouse wheel).  
  - May have fractional `target` and `zoom`.

- `render_camera`  
  - A copy of `camera` made each frame.  
  - Used only for `rl.beginMode2D`.  
  - We adjust its `target` so that, after zoom, it lands **exactly on pixel centers**.

### 4.1 Snapping Formula

For one axis:

```text
screen_target_x = camera.target.x * camera.zoom
```

We want `screen_target_x` to be an integer. So we define:

```text
snapped_target_x = floor(camera.target.x * camera.zoom) / camera.zoom
```

This keeps `camera` smooth, but `render_camera` is nudged just enough to keep the grid aligned with the pixel grid.

### 4.2 Code Pattern in `tile_inspector.zig`

Inside the main loop, before drawing:

```zig
rl.beginDrawing();
defer rl.endDrawing();

rl.clearBackground(rl.Color.ray_white);

// Use a render camera snapped to pixel grid (camera itself stays smooth)
var render_camera = camera;
render_camera.target.x = @floor(camera.target.x * camera.zoom) / camera.zoom;
render_camera.target.y = @floor(camera.target.y * camera.zoom) / camera.zoom;

rl.beginMode2D(render_camera);
// draw tiles, world, placement, etc.
PlacementSystem.renderPlacedItems(placed_items.items);
const result = placement_system.updateAndRender(render_camera);
rl.endMode2D();
```

Key points:

- Only `render_camera` is modified; `camera` keeps the original smooth values.
- All world drawing that needs pixel‑perfect tiles uses `render_camera`.

---

## 5. Texture Filtering

We also configure textures for **point filtering**:

```zig
// Use point filtering to prevent pixel bleeding between tiles
rl.setTextureFilter(tileset_texture, .point);
rl.setTextureFilter(house_texture, .point);
rl.setTextureFilter(lake_texture, .point);
```

This disables bilinear filtering so:

- Pixels stay crisp (no blur on zoom).  
- When sampling at exact texel centers, we dont accidentally blend with neighboring tiles inside the spritesheet.

Point filtering alone does *not* fix the seam issue if the camera isnt aligned, but together with the snapped `render_camera` it gives stable, clean tile edges at any zoom.

---

## 6. Zoom Behavior

We keep zoom **smooth** in the editor:

```zig
const wheel = rl.getMouseWheelMove();
if (wheel != 0) {
    const zoom_speed: f32 = 0.1;
    const min_zoom: f32 = 0.5;
    const max_zoom: f32 = 4.0; // optional

    camera.zoom += wheel * zoom_speed;
    camera.zoom = std.math.clamp(camera.zoom, min_zoom, max_zoom);
}
```

Because we snap the render camera in **screen space**, smooth zoom values are fine; we no longer require zoom to be an integer.

---

## 7. Summary

- Tile seams happen when camera and zoom cause tile edges to land on **sub‑pixel positions**, so the GPU blends texels and pixels.
- Snapping the main camera or forcing integer zoom solves it but makes camera/zoom feel bad and can interfere with game logic.
- The robust solution is to:
  - Keep a smooth logical `camera` for input and gameplay.
  - Derive a `render_camera` each frame with target snapped in screen space (`floor(target * zoom) / zoom`).
  - Use point filtering on textures for crisp pixel‑art.

This gives us **smooth camera + smooth zoom** and **no visible seams** between tiles.