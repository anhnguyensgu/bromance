# Plot Layout Visual Guide

## World Configuration

**World Size:** 1280x1280 pixels  
**Grid Size:** 80x80 tiles  
**Tile Size:** 16x16 pixels

## Plot Map

```
Grid coordinates (tile_x, tile_y)

    0    10   20   30   40   50   60   70   80
    |----|----|----|----|----|----|----|----|
 0  |
    |
 5  |    [Plot #1]     [Plot #2]     [Plot #5]      [Plot #7]
    |    0xALICE       0xBOB123      farmer.eth     player123
    |    (8,5)         (19,5)        (30,5)         (43,5)
    |    10x8          10x8          12x10          10x8
    |    [OWNED]       [OWNED]       [OWNED-ENS]    [OWNED]
10  |
    |
    |
14  |    [Plot #3]     [Plot #4]     [Plot #6]      [Plot #8]
    |    Unclaimed     Unclaimed     Unclaimed      Unclaimed
    |    (8,14)        (19,14)       (30,16)        (43,14)
    |    10x8          10x8          12x10          10x8
    |    [FREE]        [FREE]        [FREE]         [FREE]
20  |
    |
    |
30  |
```

## Plot Details

### Row 1 (Northern plots - mostly owned)

| ID | Position | Size | Owner | Type | Status |
|----|----------|------|-------|------|--------|
| 1  | (8, 5)   | 10x8 | 0xALICE | Wallet | Owned |
| 2  | (19, 5)  | 10x8 | 0xBOB123 | Wallet | Owned |
| 5  | (30, 5)  | 12x10 | farmer.eth | ENS | Owned |
| 7  | (43, 5)  | 10x8 | player123 | Custom | Owned |

### Row 2 (Southern plots - all unclaimed)

| ID | Position | Size | Owner | Type | Status |
|----|----------|------|-------|------|--------|
| 3  | (8, 14)  | 10x8 | - | None | Unclaimed |
| 4  | (19, 14) | 10x8 | - | None | Unclaimed |
| 6  | (30, 16) | 12x10 | - | None | Unclaimed |
| 8  | (43, 14) | 10x8 | - | None | Unclaimed |

## Visual Representation

When you run the game with `P` key pressed (plot visibility on):

- **Blue bordered plots** = Owned by someone
- **Green bordered plots** = Unclaimed (available)
- **Yellow bordered plot** = Currently selected
- **White bordered plot** = Currently hovered by mouse

## Spacing & Layout

```
Plot positions ensure:
- 1 tile gap between house (11,8) and plots
- 1 tile gap between plots horizontally
- 6 tile gap between upper and lower plot rows
- Even distribution across the 80-tile width
```

## Testing Scenarios

### Test Ownership Verification
1. Click on **Plot #1** → Should show "0xALICE" as owner
2. Click on **Plot #5** → Should show "farmer.eth" as ENS owner
3. Click on **Plot #3** → Should show "Unclaimed"

### Test Different Owner Types
- **Wallet:** Plots #1, #2 (format: 0x...)
- **ENS:** Plot #5 (format: name.eth)
- **Custom:** Plot #7 (custom identifier)
- **None:** Plots #3, #4, #6, #8 (unclaimed land)

### Test Plot Selection
1. Press `P` to toggle plot visibility
2. Press `G` to see the tile grid overlay
3. Hover over plots to see highlight
4. Click to select and view plot info overlay

## Coordinates Reference

For adding new plots between existing ones:

```
Free spaces available at:
- (54-63, 5-12)   - East of Plot #7
- (54-63, 14-21)  - East of Plot #8
- (8-52, 23-30)   - South row 3
- (8-52, 32-40)   - South row 4
```

## World Map Context

```
Notable landmarks in worldoutput.json:
- House at (11, 8) - 5x7 tiles
- Road network at (2-6, 8-11) - Connected path tiles
- Plenty of open space for farming and building
```

## Next Steps

Use this layout to plan:
1. **Farm plots** - Place crop tiles within owned plots
2. **Buildings** - Add barns, workshops on owned land
3. **Decorations** - Fences along plot boundaries
4. **Paths** - Connect plots with road tiles

Press `G` in-game to see the exact tile grid and plan your builds!
