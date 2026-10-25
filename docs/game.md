# Game layer — `src/game/`

The scenes' root scripts (both extend `CombatWorld`) and the lane match rules.

## `rift_stage.gd` (root of `scenes/rift.tscn`, extends `CombatWorld`)

The main game: the full map with seasonal art and a one-lane match in the middle lane — you (Blue Kael) vs a
Red Kael played by a `LaneBot`. Keys: F1 hitboxes · F2 bot difficulty (dummy mode in the sandbox) · F3 back to
base · F4 fill meter · Enter new match after it ends.

Fields: `spawn` (Blue base, x 200), `dummy_spawn` (sandbox only), `bot_difficulty` (**static**, so it survives
"new match" scene reloads), `lane_enabled` (set to `false` *before* adding the scene for a free-roam sandbox:
no structures/minions, red fighter = training dummy, nobody dies), `player`, `dummy` (the red fighter),
`dummy_controller`, `bot`, `camera`.

- **`_ready()`**: registers inputs; builds the map from `RiftLayout.build()` (solids, one-ways, pads,
  ground strips); creates the player (`PlayerController`) and the red fighter (`LaneBot` at the red base in a
  match, `DummyController` in the sandbox); spawns every monster from `RiftLayout.MONSTERS`; creates and
  sets up `LaneMatch` (respawn point for the player); adds `EffectsLayer`, the camera, the vignette shader
  layer and the `RiftHud`.
- **`_physics_process(delta)`**: one `step()` per physics tick (if `auto_tick`), then the camera.
- **`_update_camera()`**: moves the camera once per tick toward `_camera_target()` plus a look-ahead that eases toward where you're facing/moving.
- **`step()`**: `CombatWorld.step()`; in the sandbox also refills the dummy's HP when idle and slowly regenerates the player.
- **`_camera_target() -> Vector2`**: keeps the band you're in on screen (lanes framed, jungles followed
  vertically but never past their floor/ceiling).
- **`_process(delta)`**: screen-shake offset (visual randomness only).
- **`_unhandled_input(event)`**: Enter reloads the scene after a win; F1 debug draw; F2 cycles bot difficulty
  (and remembers it) or dummy mode; F3 teleports the player home (not while KO); F4 fills meter.

## `training_stage.gd` (root of `scenes/training.tscn`, extends `CombatWorld`)

A small room: Kael vs a dummy (`DummyController`), `training_mode = true` (nobody drops below 1 HP).

- **`_ready()`**: turns every `SolidBlock` under `$Level` into a solid/one-way, creates player and dummy, effects, camera and `TrainingHud`.
- **`_physics_process`**, **`_update_camera`**, **`_camera_target`**, **`_process`**: as in the Rift (camera fixed relative to the player).
- **`step()`**: `CombatWorld.step()` then `_apply_training_rules()`.
- **`_unhandled_input(event)`**: F1 debug, F2 dummy mode, F3 `reset_positions()`, F4 full meter.
- **`reset_positions()`**: puts both fighters back at their spawns (keeps the player's meter).
- **`_apply_training_rules()`**: refills the dummy's HP and guard after 45 idle ticks (the player's after 180),
  gives the dummy full meter in Burst mode, and resets anyone who falls out of the level.

## `lane_match.gd` — `LaneMatch` (RefCounted)

The rules of a one-lane match. Created by `RiftStage`, stored in `CombatWorld.lane`, ticked at the end of every
`CombatWorld.step()` — deterministic like the rest of the sim.

Constants: `LANE` (= `RiftLayout.STRUCTURE_FLOOR`, the middle lane), `LAYOUT` (Blue's chain
outer → inner → gate → core, x from `RiftLayout.STRUCTURE_X`; Red mirrored), `WAVE` (3 melee + 2 ranged),
`MONSTER_REWARDS` (gold, XP per monster kind), `TEAM_NAMES`.

State: `winner` (−1 until a core falls), `end_tick`, `team_kills`, `wyrm_stacks`, `titan_timer`,
`spawn_points` (Fighter → respawn position), `feed` (kill feed, newest first, max 5), `_chain` (per team,
outer → core), `_recent` (victim → {attacker: tick of last hit}, for kill credit and assists).

- **`setup(w)`**: links itself to the world, builds both structure chains on the terrain (each guarded by
  the previous one), gives every fighter `START_GOLD`, listens to `combat_event`.
- **`structure(team, kind) -> Structure`**: looks up one of a team's structures.
- **`base_spawn(team) -> Vector2`**: default respawn point at each base.
- **`clock() -> float`**: match seconds (frozen at `end_tick` once someone wins).
- **`ticks_to_next_wave() -> int`**: for the HUD's wave timer.
- **`tick()`**: per tick — spawn a wave at 0:05 then every 25 s; passive gold every second; Titan buff timer;
  Wyrm damage buff on each fighter; respawn countdown → `_respawn`; fountain healing inside your own base.
- **`spawn_wave()`**: spawns both teams' waves just in front of their gate (plus a super minion if the enemy
  gate is down; empowered if the team has the Titan buff), scaled by match minutes.
- **`_in_own_base(f) -> bool`**: inside the team's base column.
- **`_respawn(f)`**: puts a KO'd fighter back at its spawn point with full HP, keeping meter, with `RESPAWN_INVULN`.
- **`give_gold(f, amount, show := true)`**: adds gold (with a floating "+N").
- **`give_xp(f, amount)`**: adds XP and handles level-ups (max level 10): +max HP is added to current HP plus 10% heal, "LEVEL N" text.
- **`_share_xp(team, at, amount)`**: XP for allies within `XP_RADIUS` on the same band (65% each when shared).
- **`_post(text, team)`**: adds a kill-feed line.
- **`_on_event(kind, info)`**: reacts to sim events — `hit` (remember who hit whom), `ko` → `_fighter_ko`,
  `minion_slain` (last-hit gold + CS to the fighter who killed it; XP shared), `structure_destroyed` (gold/XP to
  the other team, feed; a core sets `winner`), `monster_slain` (gold/XP; Wyrm +10% damage up to ×3; Titan
  empowers minions for 60 s).
- **`_fighter_ko(v, att)`**: deaths, respawn timer (4 s + 1.2 s × level); the killer is the attacking fighter,
  or — for deaths to towers, minions or monsters — the enemy fighter who hit last within `ASSIST_WINDOW`; kill
  gold/XP, kill feed, assists for every other recent attacker.
