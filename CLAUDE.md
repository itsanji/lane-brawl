# Lane Brawl

A 2D side-view **5v5 MOBA with fighting-game combat** (LoL structure + Smash/Brawlhalla-style fights), crossplay PC + mobile. Built in **Godot 4.7, GDScript**. The full game design lives in the playable HTML prototype `prototype/lane-brawl-demo.html` (roster, moves, items, map, AI) — port from it rather than reinventing.

Scenes: `scenes/rift.tscn` (main) — the full 5v5 map with seasonal art and a **one-lane match** in the middle lane (you = Blue Kael vs a Red Kael played by a `LaneBot`, minion waves, towers, gate, core; F2 = bot difficulty); set `lane_enabled = false` before adding it for a free-roam sandbox; `scenes/training.tscn` — combat training room.

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
env -u DRI_PRIME xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 -s res://tools/climb_clip.gd -- /tmp/climb  # lane → jungle → lane climb
ffmpeg -framerate 30 -i /tmp/clip/f%04d.png -pix_fmt yuv420p clip.mp4
```

**Careful with the user's PC: it freezes under heavy load (15 GB RAM, usually busy).** Run renders, encodes and imports one at a time, never in parallel, and use `tools/render_video.sh` (memory-capped via systemd-run, low priority, frames deleted after encoding). Check `free -h` before heavy jobs.

Videos: `tools/render_video.sh <lanes|climb|descend|cliffs|fight|monsters|moves> <out_dir>` (scenarios in `tools/record.gd`, sandbox mode).
Bot-vs-bot lane match in the real game loop (Hard `LaneBot` plays you): `tools/autoplay.gd` — record with Godot's movie maker (command in its header, wrap it in the same `systemd-run … MemoryMax=2G` cap; ~4 min for 87 s), or dry-run headless and fast with `godot --headless --path . -s res://tools/autoplay.gd -- fast` (prints KOs with the bot's plan, structure kills, per-fighter stats, hit counts and how long Blue spent in each plan — use it to tune the bot).

The user often can't play-test. Verify behaviour with tests (`tests/`) and look at screenshots (`tools/screenshot.gd`, edit its SCRIPT/SHOTS for the scenario) instead of assuming.

## Architecture

- **Simulation is pure GDScript, fixed 60 ticks/s, no physics engine.** `CombatWorld.step()` = read inputs → `Fighter.sim_tick()` → resolve hits → age effects. Deterministic and headless-safe, so it can later run on an authoritative server (and maybe rollback).
- **Everything acts through `InputFrame`s.** `FighterController` subclasses produce them: `PlayerController` (InputMap), `DummyController` (training), `ManualController` (tests), later bots and network.
- **Physics interpolation is on** (the user's monitor is 100 Hz, the sim is 60 Hz): anything that moves must move in `_physics_process`/sim ticks (fighters, monsters, camera via `_update_camera`, `ParallaxNode`). Call `reset_physics_interpolation()` on teleports. Tools that step the sim by hand set `physics_interpolation = false`.
- **Rendering only reads sim state.** `Fighter._draw()`, `EffectsLayer`, `TrainingHud`. Visual-only randomness (camera shake) is fine; never use `randf()` inside the sim.
- Level geometry: the Rift comes from `RiftLayout.build()` (solids, one-ways, platform kinds, `GroundStrip` terrain); the training room uses `SolidBlock` nodes under `Level`.
- **Map structure:** lanes (520 px air, open sky, seasonal) alternate with tall jungles (760 px, enclosed). Lanes connect **only by platforming through a jungle**: gold-trimmed one-way **bridges** sit in the floors (`RiftLayout.BRIDGES`); you drop down through them, and climb up via `RiftLayout.stair()` zig-zags (kind `outcrop` inside lanes, `stair` inside jungles) whose top ledge is centred under the bridge. No jump pads on the Rift (pad support stays in `CombatWorld`). Base columns are also climbable.
- `RiftRoutes.plan()` finds a surface-to-surface route using real jump limits; `RouteFollower` drives a fighter along it (tests prove lane→jungle→lane works; bots will reuse this).
- **Terrain:** lanes have plateaus (`RiftLayout.PLATEAUS`: ramp edges you walk, cliff edges ≤120 px you must jump) on rolling hills; jungle floors have small hills. `ground_y(floor, x)` is the surface; it only rises above the flat floor rect, is mirrored around the centre (fairness) and is flat near anchors (bridges, stairs, base entrances). `CombatWorld.move_body` snaps fighters onto `GroundStrip`s and blocks rises steeper than `CombatRules.STEP_UP` per tick (cliffs). Place anything standing on the ground at `ground_y`.
- **Map art is procedural, no image assets** (`src/art/`): `RiftArt` (@tool, so the editor shows it) gives lanes and jungles different compositions (see its header for the full layer stack: lanes have ridges 0.12, far 0.28, mid-far 0.45, mid 0.62, near-mid 0.82, front 1.2 and near-camera front 1.5; jungles have bioluminescent glows, giant trunks, root curtains, glowing mushrooms and light beams falling through the bridges). Also drifting `FogWisps`, lanterns flickering via `flicker.gdshader`, foliage swaying with gusts (`sway.gdshader`), `SeasonParticles` and `Critters`; plus rock, platforms, bounce-mushroom pads and base sanctuaries. Everything is drawn by `Painter` helpers into `ArtChunk`s (800 px wide, culled off screen) with seeded RNG, so it is deterministic. Colours live in `SeasonPalette`.
- Art direction: Hollow Knight-like — one dominant hue per area, light foggy backgrounds, darker hazy midground, near-black foreground silhouettes, sparse glowing accents, vignette. Original art only; never copy Hollow Knight assets.
- Seasons: upper lane = winter (Frostveil, **Japanese winter**: dusk, moon, Fuji-like peaks, pagodas, matsu pines, vermilion torii at `RiftArt.TORII_X`, tōrō and chōchin lanterns, camellias, bamboo fences), jungles = summer (Verdant Deep: enclosed, dark, bioluminescent — deliberately unlike any lane), middle lane = spring (Bloomway), lower lane = fall (Emberfall).
- Characters are small Hollow Knight-like bug knights drawn in `Fighter._draw()`: pale horned mask, dark cloak with a team-coloured hem and ring, scarf in the fighter's colour, nail; crescent slash fx on active frames. Keep them simple and readable.
- **Jungle monsters** (`src/combat/monster.gd`, spots in `RiftLayout.MONSTERS`): 2 Mossback camps per jungle (mirrored) + a boss in each jungle centre (Hollow Titan upper, Lumen Wyrm lower). States idle → chase → windup (telegraphed, red area) → strike → recover; leash home + heal; respawn. Strikes can be guarded or parried (parry staggers). `CombatWorld.monster_strike`/`_hit_monster` do the combat; rewards come with the economy milestone.
- **Lane match** (`src/game/lane_match.gd`, `LaneMatch`, set as `CombatWorld.lane` and ticked at the end of `step()`): per team a chain of `Structure`s (`src/combat/structure.gd`: outer tower 2650 → inner tower 1250 → gate 560 → core 200, Red mirrored) — each sealed until the one in front falls; towers/core shoot homing orbs (`CombatWorld.shots`), minions first, fighters otherwise, and aggro a fighter who hits their team's fighter in range; fighters deal half damage to structures without their own minions within 520 px. `Minion`s (`src/combat/minion.gd`: melee, ranged lanternlings, super after the enemy gate falls) spawn every 25 s from 0:05 and fight minions → structures → nearby fighters; their hurtbox is ≥64 px tall so standing attacks hit them. Economy and levels on `Fighter` (`gold`, `xp`, `level` 1–10: `max_hp()` +8%/level, `power()` +5%/level and team buffs): last hits, kills/assists (credit to the last fighter who hit within 10 s, even for tower/minion kills), structures, monsters (Wyrm: +10% team damage ×3; Titan: empowered minions 60 s). KO → respawn timer 4 s + 1.2 s/level at `spawn_points`; your base heals you; breaking the enemy core sets `winner` (Enter restarts). Structures stand on level pads (`RiftLayout.STRUCTURE_X`, terrain flattened around them in `ground_offset`).
- **Enemy bot** (`src/controllers/lane_bot.gd`, `LaneBot`, a `FighterController`): Easy/Normal/Hard (`TUNING`: reaction ticks, guard/parry/dodge chance, combo follow-up, aggression, last-hit accuracy, think rate, retreat HP). Macro each "think": retreat home when low → leave uncovered enemy tower range → fight (engage 380 px, chase a low enemy 700 px, never past their first tower unless a sure kill) → last-hit → clear the wave → siege while its minions tank → hold behind its front minion. Micro: L-L-H strings and launcher air combos as input sequences (continue only if they connected), grab vs guard, Rising Fang anti-air, Phantom Dash gap-closer, ult to finish, burst out of 3+ hit combos, reaction-delayed parry/guard/dodge, jumps cliffs when stuck. Seeded RNG, so matches are deterministic. `passive = true` = defend-only. In the sandbox (`lane_enabled = false`) the red fighter is still the training dummy (`DummyController`, `home_x` makes it walk back to its post). Things that can be freed (minions) go through `CombatWorld.alive()` (untyped on purpose).
- HUD `SkillBar` (both scenes): Dash/S1/S2/Ult slots with cooldown sweeps, Ult meter ring, EX pips; vitals on the Rift.
- Minimap (`RiftHud`): ornate framed panel top-right with season glyphs, terrain lines, base crystals, structures, minions and the area name. In a match `RiftHud` also draws the score/clock/structure bar, kill feed, "SLAIN — respawning" and VICTORY/DEFEAT.

```
src/combat/   combat_rules.gd (tuning constants, lane/economy too), combat_world.gd (step, movement/collision, apply_hit, monster
              and lane combat, shots), move_data.gd, fighter_data.gd, input_frame.gd, monster.gd, minion.gd, structure.gd
src/fighter/  fighter.gd — state machine: idle/run/air/jumpsquat/dash/guard/attack/hitstun/blockstun/airhit/held/tumble/knockdown/guardbreak/dodge/ko
src/data/     roster.gd — fighters and moves as dictionaries (NORMALS shared + per-fighter moves)
src/controllers/  input_bindings.gd (all InputMap actions, registered in code), player/dummy/manual controllers, route_follower.gd
src/game/     training_stage.gd (extends CombatWorld)
src/ui/       effects_layer.gd, training_hud.gd, skill_bar.gd
src/world/    rift_layout.gd (map geometry, terrain, bridges/stairs, seasons), rift_routes.gd (route planning), ground_strip.gd, solid_block.gd (@tool)
src/art/      rift_art.gd, painter.gd, season_palette.gd, parallax_node.gd, art_chunk.gd, season_particles.gd, fog_wisps.gd, critters.gd, *.gdshader
src/game/rift_stage.gd, lane_match.gd, src/ui/rift_hud.gd (minimap, area title cards, match HUD)
tests/        test_runner.gd (SceneTree script) + TestSuite subclasses
```

## Conventions

- Typed GDScript, tabs, `snake_case`; `class_name` for reusable scripts. Keep warnings at zero (check.sh prints them).
- Units: pixels, pixels/tick, ticks. Position of a fighter = centre of the feet. y grows downward.
- Move hitbox `Rect2(forward_offset, top_from_feet, w, h)`; mirrored automatically when facing left.
- New moves/fighters: add to `src/data/roster.gd` (unknown keys raise an error). New mechanics: constant in `combat_rules.gd`, logic in `fighter.gd`/`combat_world.gd`, **and a test**.
- Input actions are defined only in `InputBindings.register()` — don't add them in project settings.
- Commit `*.uid` files; `.godot/` is ignored.

## Controls

A/D move · **W or Space jump** (3-frame jumpsquat; tap = short hop, hold = full; W+K together or K during jumpsquat = Up+Heavy launcher) · **Shift dash** (all fighters, 10 frames, 40-tick cooldown, one air dash per jump, cancels normals on hit) · J light · K heavy · U/I skills · O ult · L guard (tap+direction dodge, +J grab) · S+Space drop through. Ground movement accelerates/decelerates (`RUN_ACCEL`, `RUN_DECEL`, `TURN_DECEL`).

## Combat rules implemented (match the prototype)

Chains L→L→L / L→L→H; Up+H launcher, Down+H sweep, air L/H; jump-cancel on hit (launcher, air L); skills cancel normals on hit; 8-frame input buffer (Guard has lowest priority when buttons are pressed together); hitstop; counter-hits (+25%); guard (front only, guard meter, guard break); grab = Guard+Light (beats guard, loses to attacks); parry = Guard tap ≤9 frames before a hit; dodge = Guard tap + direction; juggle limit 4 shared by all attackers → tumble + wake-up invulnerability; damage scaling −10%/hit (min 30%); 3-bar meter: Ult (3), EX skill (hold skill past frame 8, 1 bar), Burst = Guard+Heavy while hit (2 bars). Air hits carry the attacker up with the target so air strings connect. Jump pads: hold Up on a pad (`CombatWorld.jump_pads`).

## Roadmap

1. ✅ Combat prototype (Kael vs dummy, tests, screenshots)
2. ✅ Rift map geometry + seasonal procedural art
3. ✅ Rolling terrain, Japanese-winter Frostveil, living effects, minimap, bug-knight characters
3a. ✅ Taller jungles between lanes; lane → jungle → lane platforming; plateaus and cliffs; deeper parallax
3b. ✅ Dash, W-jump with jumpsquat + variable height, smoother movement (interpolation), cooldown HUD, jungle monsters
3c. Per-fighter looks for the other 4 fighters
3d. ✅ One-lane match: minion waves, towers/gate/core (with art), gold/XP/levels, death/respawn, monster rewards + buffs, win
4. Touch controls (virtual stick + buttons) and Android export; port the other 4 fighters (projectiles, specials)
5. ✅ Enemy bot fighter (`LaneBot`, 3 difficulties)
5a. Shop for gold, sound, other two lanes, jungle routes for bots (`RouteFollower`)
6. Online 1v1: headless Godot server running `CombatWorld`, client prediction
7. 5v5 vertical slice: full map, Nakama matchmaking
