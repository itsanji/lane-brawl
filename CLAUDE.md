# Lane Brawl

A 2D side-view **5v5 MOBA with fighting-game combat** (LoL structure + Smash/Brawlhalla-style fights), crossplay PC + mobile. Built in **Godot 4.7, GDScript**. The full game design lives in the playable HTML prototype `prototype/lane-brawl-demo.html` (roster, moves, items, map, AI) — port from it rather than reinventing.

Scenes: `scenes/rift.tscn` (main) — the full 5v5 map with seasonal art, you + a dummy in the middle lane; `scenes/training.tscn` — combat training room.

## Commands

```bash
tools/check.sh          # import + all tests + run the main scene 300 frames; fails on any script error. Run after every change.
godot --headless --path . -s res://tests/test_runner.gd     # tests only
godot --path .          # play (main scene = the Rift map)
godot --path . res://scenes/training.tscn   # combat training room
godot -e --path .       # open the editor
# Screenshots without a window (renders through Xvfb + Mesa llvmpipe):
env -u DRI_PRIME xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 -s res://tools/screenshot.gd -- /tmp/shots   # combat
env -u DRI_PRIME xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 -s res://tools/map_tour.gd -- /tmp/map      # every map area
env -u DRI_PRIME xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 -s res://tools/clip.gd -- /tmp/clip        # frames for a video
ffmpeg -framerate 30 -i /tmp/clip/f%04d.png -pix_fmt yuv420p clip.mp4
```

The user often can't play-test. Verify behaviour with tests (`tests/`) and look at screenshots (`tools/screenshot.gd`, edit its SCRIPT/SHOTS for the scenario) instead of assuming.

## Architecture

- **Simulation is pure GDScript, fixed 60 ticks/s, no physics engine.** `CombatWorld.step()` = read inputs → `Fighter.sim_tick()` → resolve hits → age effects. Deterministic and headless-safe, so it can later run on an authoritative server (and maybe rollback).
- **Everything acts through `InputFrame`s.** `FighterController` subclasses produce them: `PlayerController` (InputMap), `DummyController` (training), `ManualController` (tests), later bots and network.
- **Rendering only reads sim state.** `Fighter._draw()`, `EffectsLayer`, `TrainingHud`. Visual-only randomness (camera shake) is fine; never use `randf()` inside the sim.
- Level geometry: the Rift comes from `RiftLayout.build()` (solids, one-ways, jump pads, platform kinds, `GroundStrip` terrain); the training room uses `SolidBlock` nodes under `Level`.
- **Terrain:** lanes and jungles roll up and down. `RiftLayout.ground_y(floor, x)` is the surface; hills only rise above the flat floor rect, are mirrored around the map centre (fairness) and flatten near connectors, pads and base entrances. `CombatWorld.move_body` snaps fighters onto `GroundStrip`s (landing, uphill, downhill stick, push-out if inside). Place anything that stands on the ground at `ground_y`.
- **Map art is procedural, no image assets** (`src/art/`): `RiftArt` (@tool, so the editor shows it) builds per band a sky gradient, glows, light shafts, far/mid parallax tree layers (`ParallaxNode`, factor = distance), haze, drifting `FogWisps`, fog, ground decor, lanterns (flickering via `flicker.gdshader`), swaying mid and foreground (`sway.gdshader`, with wind gusts), `SeasonParticles` and `Critters` (butterflies, fireflies, birds); plus rock, platforms, bounce-mushroom pads and base sanctuaries. Everything is drawn by `Painter` helpers into `ArtChunk`s (800 px wide, culled off screen) with seeded RNG, so it is deterministic. Colours live in `SeasonPalette`.
- Art direction: Hollow Knight-like — one dominant hue per area, light foggy backgrounds, darker hazy midground, near-black foreground silhouettes, sparse glowing accents, vignette. Original art only; never copy Hollow Knight assets.
- Seasons: upper lane = winter (Frostveil, **Japanese winter**: dusk, moon, Fuji-like peaks, pagodas, matsu pines, vermilion torii at `RiftArt.TORII_X`, tōrō and chōchin lanterns, camellias, bamboo fences), jungles = summer (Verdant Deep), middle lane = spring (Bloomway), lower lane = fall (Emberfall).
- Characters are small Hollow Knight-like bug knights drawn in `Fighter._draw()`: pale horned mask, dark cloak with a team-coloured hem and ring, scarf in the fighter's colour, nail; crescent slash fx on active frames. Keep them simple and readable.
- Minimap (`RiftHud`): ornate framed panel top-right with season glyphs, terrain lines, base crystals, pads and the area name.

```
src/combat/   combat_rules.gd (tuning constants), combat_world.gd (step, movement/collision, apply_hit),
              move_data.gd, fighter_data.gd, input_frame.gd
src/fighter/  fighter.gd — state machine: idle/run/air/guard/attack/hitstun/blockstun/airhit/held/tumble/knockdown/guardbreak/dodge/ko
src/data/     roster.gd — fighters and moves as dictionaries (NORMALS shared + per-fighter moves)
src/controllers/  input_bindings.gd (all InputMap actions, registered in code), player/dummy/manual controllers
src/game/     training_stage.gd (extends CombatWorld)
src/ui/       effects_layer.gd, training_hud.gd
src/world/    rift_layout.gd (map geometry, terrain, seasons, band helpers), ground_strip.gd, solid_block.gd (@tool)
src/art/      rift_art.gd, painter.gd, season_palette.gd, parallax_node.gd, art_chunk.gd, season_particles.gd, fog_wisps.gd, critters.gd, *.gdshader
src/game/rift_stage.gd, src/ui/rift_hud.gd (minimap + area title cards)
tests/        test_runner.gd (SceneTree script) + TestSuite subclasses
```

## Conventions

- Typed GDScript, tabs, `snake_case`; `class_name` for reusable scripts. Keep warnings at zero (check.sh prints them).
- Units: pixels, pixels/tick, ticks. Position of a fighter = centre of the feet. y grows downward.
- Move hitbox `Rect2(forward_offset, top_from_feet, w, h)`; mirrored automatically when facing left.
- New moves/fighters: add to `src/data/roster.gd` (unknown keys raise an error). New mechanics: constant in `combat_rules.gd`, logic in `fighter.gd`/`combat_world.gd`, **and a test**.
- Input actions are defined only in `InputBindings.register()` — don't add them in project settings.
- Commit `*.uid` files; `.godot/` is ignored.

## Combat rules implemented (match the prototype)

Chains L→L→L / L→L→H; Up+H launcher, Down+H sweep, air L/H; jump-cancel on hit (launcher, air L); skills cancel normals on hit; 8-frame input buffer (Guard has lowest priority when buttons are pressed together); hitstop; counter-hits (+25%); guard (front only, guard meter, guard break); grab = Guard+Light (beats guard, loses to attacks); parry = Guard tap ≤9 frames before a hit; dodge = Guard tap + direction; juggle limit 4 shared by all attackers → tumble + wake-up invulnerability; damage scaling −10%/hit (min 30%); 3-bar meter: Ult (3), EX skill (hold skill past frame 8, 1 bar), Burst = Guard+Heavy while hit (2 bars). Air hits carry the attacker up with the target so air strings connect. Jump pads: hold Up on a pad (`CombatWorld.jump_pads`).

## Roadmap

1. ✅ Combat prototype (Kael vs dummy, tests, screenshots)
2. ✅ Rift map geometry + seasonal procedural art
3. ✅ Rolling terrain, Japanese-winter Frostveil, living effects, minimap, bug-knight characters
3b. Towers/gates/cores art; per-fighter looks for the other 4 fighters
4. Touch controls (virtual stick + buttons) and Android export; port the other 4 fighters (projectiles, specials)
5. One lane: minions, towers, gold, levels
6. Online 1v1: headless Godot server running `CombatWorld`, client prediction
7. 5v5 vertical slice: full map, Nakama matchmaking
