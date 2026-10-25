# Tests and tools — `tests/`, `tools/`

The user often can't play-test, so behaviour is verified with headless tests and rendered screenshots/videos.

## Running
```bash
tools/check.sh                                              # import + all tests + main scene 300 frames; fails on any script error
godot --headless --path . -s res://tests/test_runner.gd     # tests only
```

## Test harness
### `tests/test_runner.gd` (SceneTree script)
- **`_initialize()`**: waits one frame (so scenes added by tests get `_ready()`), runs every `test_*` method of
  each suite listed in `SUITES`, calls `teardown()` after each, prints ok/FAIL with messages, exits 1 on failure.
  **Add new suites to `SUITES`.**

### `tests/test_suite.gd` — `TestSuite`
Base class with assertions and world helpers (flat floor at `FLOOR_Y` 400, one one-way `PLATFORM`).
- **`check(condition, message)`**, **`eq(actual, expected, message)`**: record a failure (tests keep running).
- **`teardown()`**: frees worlds created by `make_world()`.
- **`make_world() -> CombatWorld`**: the small test world.
- **`spawn(w, team, x, face, y) -> Fighter`**: a Kael with a `ManualController`.
- **`pad(f) -> InputFrame`**: the fighter's manual input frame.
- **`run(w, ticks)`**: step N ticks.
- **`tap(w, f, button, y, x)`**: press for one tick then release. **`hold(w, f, button, ticks, y, x)`**: hold for N ticks.
- **`run_until(w, cond, max_ticks) -> bool`**: step until `cond` is true.
- **`scaled(base, hits_before, mult)`**: expected damage after combo scaling (Kael's 1.06 multiplier).

## Suites (66 tests)
| Suite | What it proves |
|---|---|
| `test_movement.gd` (9) | falling/landing, running, jump + one air jump, one-way land and drop-through, dodge invulnerability, short hop vs full jump, dash (ground + one air dash), W+K = launcher, Heavy during jumpsquat = launcher |
| `test_combat.gd` (16) | Light range, L-L-H chain with damage scaling, launcher, juggle limit shared by 3 attackers, guard front/back, grab beats guard, parry stagger, dodge, hitstop, jump cancel, EX skill, skill tap = not EX + cooldown, ult needs full meter, burst, the signature 4-hit air combo. Helper `duel()` |
| `test_training_scene.gd` (2) | training scene builds/runs; dummy Attack mode hits the player |
| `test_rift.gd` (16) | every lane reaches every lane through a jungle (routes), climbing middle → upper lane, mirrored terrain flat at anchors, lanes have hills, cliffs block walking but can be jumped, ramps followed, respawn inside a hill pops up, drop through a bridge, base climb, Rift scene runs, drop upper → lower lane, monsters spawn, camps fight back, guard/parry vs monster, leash + heal, monster death + respawn. Helpers `rift_world()`, `monster_world()` |
| `test_lane.gd` (16) | structures fall in order, stand on level ground, waves spawn and march, minions fight, super minion after gate, towers prefer minions, tower aggro, last-hit gold/XP, backdoor half damage, core kill wins, KO/respawn/kill reward, tower kill credit, levels, monster rewards + Wyrm buff, fountain, Rift scene runs a match. Helpers `lane_world()`, `at()`, `lane_fighter()`, `minion()` |
| `test_bot.gd` (7) | bot walks out and holds behind its minions, climbs cliffs, fights an enemy, Hard passive bot guards heavies, retreats when low, respects enemy tower, bot vs bot is deterministic and sane over 150 s. Helpers `lane_world()`, `ground()`, `bot_fighter()` |

## Tools — `tools/`
**Careful with the PC (15 GB RAM, freezes under load):** run renders/encodes one at a time, check `free -h`
first, and cap them (`systemd-run --user --scope -q -p MemoryMax=2G -p CPUQuota=300%`, `nice -n 10`,
`LP_NUM_THREADS=2`). Renders go through Xvfb + Mesa llvmpipe (`env -u DRI_PRIME xvfb-run ... --rendering-driver opengl3`).

| Tool | Purpose |
|---|---|
| `check.sh` | import → tests → run the main scene 300 frames; fails on test failures or any script/parse error; prints warnings |
| `render_video.sh <scenario> <out_dir>` | renders a `record.gd` scenario to MP4 under memory/CPU caps, deletes frames afterwards |
| `record.gd` | scripted Rift scenarios (sandbox mode) as PNG frames with captions: `lanes climb descend cliffs fight monsters moves` |
| `autoplay.gd` | the real game loop, bot vs bot (Hard `LaneBot` plays Blue). Record with `--write-movie out.avi --fixed-fps 30`, or `-- fast [seconds]` headless for a stats dry run |
| `screenshot.gd` | training-room screenshots from a scripted input timeline (`SCRIPT`/`SHOTS`) |
| `map_tour.gd` | a screenshot of every map area |
| `clip.gd` | frames of the player walking through areas |
| `climb_clip.gd` | frames of a lane → jungle → lane climb (`RouteFollower`) |

### Functions in tools
- `record.gd`: **`_initialize()`** (parse scenario, build the sandbox Rift, run it), **`_teleport(f, at)`**,
  **`_snap_camera()`**, **`_tick(t)`** (one sim tick, a frame every other tick → 30 fps), **`_hold(ticks)`**,
  **`_script(f, fn)`** (drive a fighter with a callable controller — inner class `ScriptController.read`),
  scenarios **`_lanes()`**, **`_route(start, goal_band, text)`**, **`_cliffs()`**, **`_fight()`**, **`_moves()`**,
  **`_monster_fight(mon, from_x, ticks, react, text)`** (guard / dash / parry a monster), **`_monsters()`**.
- `autoplay.gd`: **`_initialize()`** (load the Rift, give Blue a Hard `LaneBot`, presimulate the first walk out;
  fast mode runs to the end and prints), **`_physics_process()`** (caption with Blue's plan, quits at the end),
  **`_log(kind, info)`** (counts fighter hits/blocks/parries, prints KOs and structure kills with the bot's plan),
  **`_summary()`** (per-fighter level/gold/CS/KDA, structures down, winner, hit counts, plan ticks), **`_clock()`**.
- `screenshot.gd`: inner controller **`read()`** replays the `SCRIPT` timeline; **`_initialize()`** renders `SHOTS`.
- `map_tour.gd`, `clip.gd`, `climb_clip.gd`: **`_initialize()`** does the whole job (clip's inner controller walks right).
