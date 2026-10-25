# World geometry and routes — `src/world/`

## `rift_layout.gd` — `RiftLayout` (@tool, static only)

The 5v5 map ("the Rift"): 6400 × 3460 px, five stacked bands, top to bottom:

| Band | Name | Floor y | Season |
|---|---|---|---|
| 0 | Frostveil — upper lane | 620 | Winter (Japanese winter) |
| 1 | Verdant Deep — upper jungle | 1420 | Summer |
| 2 | Bloomway — middle lane (the lane match) | 1980 | Spring |
| 3 | Verdant Deep — lower jungle | 2780 | Summer |
| 4 | Emberfall — lower lane | 3340 | Fall |

Lanes have 520 px of open air, jungles 760 px and are closed by rock outside `JUNGLE_X0..JUNGLE_X1`
(1400..5000). Base columns (`COL_W` 400 px) at both ends have climbable ledges. Lanes connect only by
platforming through a jungle: one-way **bridges** (`BRIDGES`) sit in each floor, with zig-zag climbing ledges
(`stair`) under them.

Key constants: `WORLD_W`, `WORLD_H`, `TOP`, `LANE_AIR`, `JUNGLE_AIR`, `FLOOR_T`, `FLOORS`, `COL_W`,
`JUNGLE_X0/X1`, `BRIDGES`, `MONSTERS` ([band, x, kind] — two Mossback camps per jungle and a boss in the
middle: Titan above, Wyrm below), `BRIDGE_W`, `STAIR_STEP/SHIFT/W`, `LANES` [0, 2, 4], `BAND_SEASON`,
`BAND_TITLE`, `BAND_SUBTITLE`, `PLATEAUS` (per lane, left half: [x0, x1, height, cliff_left, cliff_right]),
`STRUCTURE_FLOOR` (2), `STRUCTURE_X` (outer 2650, inner 1250, gate 560, core 200), `PAD_HALF`/`PAD_RAMP`
(flat pads under structures), `HILL_AMP`, `HILL_FLAT`/`HILL_RAMP` (flat zone around anchors), `CLIFF_W`, `RAMP_W`.

**Terrain is mirrored around x = 3200** (fairness) — every height function uses `min(x, WORLD_W − x)`.

### Functions
- **`band_top(b) -> float`**: top of band b's air space.
- **`band_rect(b) -> Rect2`**: band b's playable air space.
- **`band_of(y) -> int`**: which band a y position is in.
- **`is_jungle(b) -> bool`**: bands 1 and 3.
- **`in_column(x) -> bool`**: inside a base column.
- **`ground_x_range(i) -> Vector2`**: where floor i has terrain (jungle interior, or between the base columns).
- **`ground_y(i, x) -> float`**: **the** surface height of floor i at x. Place anything that stands on the ground here.
- **`ground_offset(i, x) -> float`**: height relative to the flat floor (negative = higher). On the structure
  floor, blends the terrain to a flat pad around each `STRUCTURE_X` (smoothstep over `PAD_RAMP`) so towers,
  gate and core stand level.
- **`_terrain_offset(i, x) -> float`**: raw terrain: three sine octaves of hills + plateaus, multiplied by the anchor envelope.
- **`_plateau(i, d) -> float`**: plateau height at mirrored x `d` (cliff edges 6 px wide, ramps 180 px).
- **`anchors(i) -> Array[float]`**: x positions that must stay flat on floor i (ends, its bridges, the bridges above whose stairs stand on it).
- **`_envelope(i, x) -> float`**: 0 near anchors, 1 away from them (smoothstep).
- **`stair(i, x) -> Array[Rect2]`**: the climbing ledges from floor i+1 up to the bridge at x in floor i; the top ledge is centred under the opening.
- **`build() -> Dictionary`**: all collision geometry and a platform description for the art:
  `{"solids", "one_ways", "pads", "grounds", "platforms": [{"rect", "kind", "band"}]}`. Kinds: `column` (base
  ledges), `bridge`, `outcrop` (climbing ledges inside a lane, under a bridge in the floor above it — floor
  `i` is a jungle's floor) and `stair` (climbing ledges inside a jungle). The art draws each kind differently.
- **`_make_ground(i, x0, x1) -> GroundStrip`**: samples `ground_y` every 8 px into a strip.
- **`_one_way(one_ways, platforms, r, kind)`**: adds a one-way platform and its description.

## `ground_strip.gd` — `GroundStrip` (@tool)

Rolling terrain on one floor segment, sampled every `STEP` (8) px. Hills only rise above `base_y`.
- **`contains(x) -> bool`**: x is inside the strip.
- **`height_at(x) -> float`**: linear interpolation of the samples.

## `solid_block.gd` — `SolidBlock` (@tool Node2D)

A rectangle of level geometry placed in the editor (training room). `size` and `one_way` are exported.
- **`world_rect() -> Rect2`**: its rectangle in world space.
- **`_draw()`**: simple stone (or one-way) drawing so it's visible in the editor.

## `rift_routes.gd` — `RiftRoutes` (static)

Route planning over the Rift's standing surfaces using real jump limits (`MAX_RISE` 150, `MAX_GAP_UP` 110).
Used by tests and `RouteFollower`; bots will use it to travel between lanes and jungles.
- **`surfaces(include_bases := false) -> Array[Rect2]`**: every standing surface (ground segments as 1 px rects, one-ways; base ledges optional).
- **`lane_surface(lane, x) -> Rect2`**: the ground segment of a lane containing x.
- **`plan(start, goal_band, include_bases := false) -> Array[Rect2]`**: breadth-first search to any ground of
  `goal_band`; jumps up must be within limits and not blocked by solids; drops go through one-ways or off edges. `[]` if unreachable.
- **`_columns(a, b, through_a)`**: x positions where you could move between a and b.
- **`_hits_solid(x, y0, y1, solids) -> bool`**: a vertical segment crosses a solid.
- **`_drop_clear(a, b, solids, one_ways) -> bool`**: you can fall from a onto b with nothing in the way (or walk across at the same height).
- **`_jump_clear(a, b, solids) -> bool`**: you can jump from a up to b without hitting a solid.
- **`_gap(a, b) -> float`**: horizontal gap between two surfaces.
