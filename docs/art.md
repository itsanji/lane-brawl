# Procedural art — `src/art/`

No image assets: everything is drawn with Godot's `draw_*` calls from seeded RNGs, so the map looks the same
every run. Art never touches the simulation. Direction: Hollow Knight-like (one dominant hue per area, light
foggy backgrounds, darker midground, near-black foreground, sparse glowing accents) — original art only.

## `rift_art.gd` — `RiftArt` (@tool Node2D)

Builds the whole map's visuals from `RiftLayout`. Lanes (seasonal, open sky) and jungles (enclosed,
bioluminescent) have different layer stacks — see the header comment and the `Z_*` constants for the order
(sky −70 … gameplay … front 20/22). Content is split into 800 px `ArtChunk`s inside `ParallaxNode` layers so
off-screen chunks are culled. `TORII_X` = the winter lane's torii gates. Exports: `art_seed`, `rebuild`
(tick it in the editor to regenerate).

Setup and helpers
- **`_ready()`** → **`_build()`**: frees old children, creates shared materials (additive, two sway shader
  strengths, flicker), then builds every lane/jungle band, the base columns, rock and platforms.
- **`_layer(factor, z, name) -> Node2D`**: a layer node (plain if factor 1, else a `ParallaxNode`).
- **`_chunk(parent, paint, mat)`**: adds an `ArtChunk` that calls `paint(ci)` once.
- **`_parallax(factor, z, name, paint, mat)`**: a layer filled with chunks across everything that can scroll into view; calls `paint(ci, x0)` per chunk.
- **`_rng(a, b, c) -> RandomNumberGenerator`**: deterministic RNG seeded from `art_seed` + the given keys.
- **`_chunks(x0, x1) -> Array[float]`**: chunk start positions covering a range.
- **`_gy(b, x)`**: shorthand for `RiftLayout.ground_y`.
- **`_near_anchor(b, x, margin)`**, **`_near_torii(b, x, margin)`**: keep decor clear of bridges/stairs and torii.
- **`_add_atmosphere(b, p, area, season)`**: adds `FogWisps`, `SeasonParticles` and `Critters` (butterflies in spring, fireflies in summer, birds otherwise) for a band.

Lanes
- **`_build_lane(b)`**: sky gradient, glows/moon, ridges (0.12), light shafts, far/mid-far/mid trees, two haze
  layers, near-mid bushes, fog bands, ground decor and lights, foreground (1.2) and near-camera foreground (1.5), atmosphere.
- **`_haze(b, p, top, h, z, alpha)`**: a translucent fog gradient over the band.
- **`_paint_ridges(...)`**: distant hills (winter: Fuji-like peaks and pagodas).
- **`_paint_shafts(...)`**: additive light shafts from the sky.
- **`_paint_trees(..., depth)`**: season trees at depth 0 (far), 1 (mid-far), 2 (mid): pines/matsu, blossom trees, autumn trees.
- **`_paint_nearmid(...)`**: dark bushes and partial trunks just behind the action.
- **`_paint_lane_decor(ci, b, season, p, x0, x1)`**: things standing on the ground (grass, rocks, snow, camellias, tōrō...), skipping anchors and torii.
- **`_paint_shrine(...)`**: the winter lane's torii with chōchin lanterns and bamboo fences.
- **`_lantern_positions(b, x0, x1)`**: where lane lanterns stand (away from anchors/torii).
- **`_paint_lane_lights(...)`**: lanterns and their flickering additive glows.
- **`_paint_front(...)`**, **`_paint_front2(...)`**: near-black foreground silhouettes framing the screen.

Jungles
- **`_build_jungle(b)`**: cave gradient, bioluminescent glows, giant trunks and roots, haze, undergrowth with
  glowing mushrooms, leaves, light beams falling through the bridges above, fog, decor, floor lights, foreground.
- **`_paint_jungle_trunks(..., depth)`**: giant trunks (depth 0) and trunks with root curtains (depth 1).
- **`_mushrooms(b, x0, salt) -> Array[Vector3]`**: deterministic mushroom placements (x, size, colour index) — shared by the undergrowth and its glow layer so they line up.
- **`_paint_jungle_mid(...)`**, **`_paint_jungle_mid_glows(...)`**: ferns, vines and glowing mushrooms, and their glows.
- **`_paint_jungle_nearmid(...)`**: dark big leaves close behind the action.
- **`_paint_jungle_decor(...)`**, **`_floor_shrooms(...)`**, **`_paint_jungle_floor_lights(...)`**: floor plants and mushrooms with glows.
- **`_paint_jungle_front2(...)`**: near-camera dark leaves.

Rock, bases, platforms
- **`_build_rock(solids)`**: chunks every solid rectangle (floors, walls, jungle rock).
- **`_paint_rock(ci, piece, whole)`**: rock body with seasonal top and underside.
- **`_paint_cap(ci, piece, p, season, r, floor_index)`**: the surface along the terrain line (snow, grass, moss, leaves) and the rim light.
- **`_paint_underside(...)`**: dripping/hanging detail under a floor (icicles, roots...).
- **`_build_columns()`** / **`_paint_column(ci, seg, tc, team)`**: base sanctuaries (team-coloured arches, crystals — except the middle lane, where the `Structure` core is drawn instead — and glows).
- **`_build_platforms(platforms)`** / **`_paint_platform(ci, rect, kind, b, style)`**: bridges (gold-trimmed), lane outcrops, jungle stairs, column ledges.

## `painter.gd` — `Painter` (static helpers)

Every function draws onto the given `CanvasItem` (`ci`) from inside its `_draw()`. Shapes are kept simple so
triangulation never fails.
- **`gradient_rect(ci, r, top, bottom)`**: vertical gradient rectangle.
- **`fade_band(ci, x0, x1, edge_y, height, color)`**: band fading from `color` at `edge_y` to transparent.
- **`blob(ci, c, r, color, rng, points, jitter)`**: irregular round shape.
- **`glow_texture()`**: shared radial falloff texture (cached). **`glow(ci, c, radius, color)`**: a soft glow (use with additive blending for light).
- **`trunk(...)`**, **`branch(...)`**: tapered bending trunk; a branch.
- **`pine(...)`**: snow-laden pine. **`round_tree(...)`**: broad-leaf tree with clustered canopy and blossoms/bright leaves. **`jungle_tree(...)`**: buttress roots, slim trunk, fronds, vines.
- **`frond(...)`**, **`hanging_vine(...)`**, **`tuft(...)`**, **`icicle(...)`**, **`fern(...)`**, **`big_leaf(...)`**: foliage pieces.
- **`lantern(...)`**: lumafly-style lantern post (glow drawn separately).
- **`ridge(ci, x0, x1, base_y, height, color, rng, step)`**: hill silhouette.
- **`dot_texture(size, hardness)`**, **`leaf_texture(w, h)`**: particle textures.
- Japanese winter set: **`matsu(...)`** (black pine with snow pads), **`torii(...)`** (on two ground heights),
  **`toro(...)`** (stone lantern), **`chochin(...)`** (paper lantern), **`pagoda(...)`**, **`peak(...)`**,
  **`camellia(...)`**, **`bamboo_fence(...)`**.
- Jungle set: **`giant_trunk(...)`**, **`root_curtain(...)`**, **`glow_mushroom(...)`**.

## Smaller nodes
- **`art_chunk.gd` — `ArtChunk`**: `_draw()` calls its `paint` callable once; Godot caches the commands and culls the node off screen.
- **`parallax_node.gd` — `ParallaxNode`**: `factor` < 1 = far, > 1 = foreground. **`_physics_process()`** shifts
  x by `camera_centre_x × (1 − factor)` per tick (in step with the interpolated camera). **`content_range(factor, view_width, margin)`** (static): the world x range that can appear on screen for a factor.
- **`season_palette.gd` — `SeasonPalette`**: `PALETTES` per season (sky, fog, far/mid/near, foliage, accents,
  rock, cap, glow, moon, shafts, particles, torii, lamps, bio glows...). **`get_palette(season)`**, **`for_band(b)`**.
- **`season_particles.gd` — `SeasonParticles`** (CPUParticles2D): **`configure(season, palette, area)`** sets snow / petals / spores / leaves; **`_process()`** keeps the emitter under the camera.
- **`fog_wisps.gd` — `FogWisps`**: **`setup(area, color, seed)`**, **`_process()`** (time), **`_draw()`**: 9 drifting fog banks around the camera.
- **`critters.gd` — `Critters`**: **`setup(kind, area, colors, seed)`** places butterflies/fireflies (or one bird flock); **`_process()`**, **`_draw()`** animate those near the camera.

## Shaders
- **`sway.gdshader`**: wind sway for foliage, with gusts that swell and fade (~20 s).
- **`flicker.gdshader`**: additive light flicker, out of phase by world x.
- **`vignette.gdshader`**: dark screen-edge vignette (Rift only).
