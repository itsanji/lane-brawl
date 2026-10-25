# Fighters and controllers — `src/fighter/`, `src/controllers/`

## `src/fighter/fighter.gd` — `Fighter` (Node2D)

One fighter: simulation state, the per-tick state machine, and drawing. `position` = centre of the feet.

### States
`ACTIONABLE` = `idle run air guard` (can start anything). Others: `jumpsquat` (3 pre-jump frames), `dash`,
`attack`, `dodge`, `hitstun`, `blockstun`, `airhit`, `held`, `tumble` (juggle limit reached, invulnerable),
`knockdown`, `guardbreak`, `ko`. `HIT_STATES` = `hitstun airhit held tumble knockdown` (Burst is possible from
the first two).

### Main fields
- Setup: `data` (`FighterData`), `team`, `world`, `controller`, `body_size`.
- Physics: `vel`, `facing`, `grounded`, `on_one_way`, `state`, `state_timer`.
- Current move: `move`, `move_id`, `move_frame`, `hit_ids` (targets already hit), `connected` (hit or blocked —
  enables chains/cancels), `ex`.
- Resources: `hp`, `meter`, `guard`, `cooldowns` (`S1`, `S2` in ticks), `dash_cooldown`, `dodge_cooldown`.
- Combo taken: `combo`, `combo_damage`, `juggle`.
- Timers: `invuln`, `hitstop`, `drop_timer`, `pad_timer`, `parry_timer`, `counter_timer` (parry reward),
  `wake_invuln`, `flash`, `land_squash` (visual), `ko_ticks`.
- Match progression (kept across deaths): `level`, `xp`, `gold`, `kills`, `deaths`, `assists`, `cs`,
  `respawn_timer`, `damage_buff`.
- Input: `input`, `prev_input`, `buffered` (last pressed button), `buffer_timer` (8 frames), `buffer_y`
  (direction held when it was pressed).

### Functions
- **`setup(fighter_data, team_id, spawn, face)`**: assigns data and team, then `reset_to`.
- **`reset_to(spawn, face)`**: full reset of position and combat state (HP = `max_hp()`, meter 0, cooldowns,
  timers, buffer). Match progression is *not* reset. Calls `reset_physics_interpolation()` (it's a teleport).
- **`max_hp() -> float`**: base HP × (1 + 8% per level above 1).
- **`power() -> float`**: damage multiplier = fighter `damage_mult` × (1 + 5%/level) × (1 + team buff).
- **`is_ko()`, `is_actionable()`, `is_in_hit_state()`**: state checks.
- **`end_combo()`**: resets `combo`, `combo_damage`, `juggle` (called when the victim recovers).
- **`add_meter(amount)`**: adds meter, capped at `METER_MAX`.
- **`hurtbox() -> Rect2`**: the body rectangle in world space.
- **`active_hitbox() -> Rect2`**: the current move's hitbox in world space (mirrored by `facing`), or an empty
  rect when not on an active frame.
- **`read_input()`**: asks the controller for this tick's `InputFrame`, detects newly pressed buttons and
  buffers the most important one: attacks/skills/dash beat jump, jump beats guard. That priority is what makes
  Guard+Light a grab, Guard+Heavy a burst and W+K a launcher.
- **`_clear_buffer()`**: forgets the buffered press.
- **`sim_tick()`**: one tick. Skips everything during hitstop. Ticks timers, then runs the current state
  (neutral, attack, jumpsquat, dash, hitstun, blockstun, airhit → knockdown on landing, held, tumble,
  knockdown → wake-up invulnerability, guardbreak, dodge, ko), then `_apply_physics()`, then ages the buffer.
- **`_tick_timers()`**: decrements every cooldown/timer and regenerates guard when not guarding.
- **`_neutral()`**: what an actionable fighter does with the buffered press, in priority order: Ult (full
  meter) → S1 → S2 → dash → grab (Guard+Light on the ground) → dodge (Guard tap + direction) → guard (a fresh
  tap opens the parry window) → heavy (Up = `UH` launcher, Down = `DH` sweep, else `H`; `AH` in the air) →
  light (`L1` or `AL`) → jump (drop through a one-way with Down; jumpsquat on the ground; air jump). Then
  releasing jump while rising cuts it short, and running/air control with accel/decel/turn rates.
- **`start_move(id)`**: starts a move (if the fighter has it): resets per-move state, faces the held
  direction, starts skill cooldowns, spends the full meter for `ULT`, emits `move_started`.
- **`_step_attack()`**: advances the current move one frame: EX check at frame 8 (skill still held + 1 bar),
  invulnerability frames, self movement, multi-hit resets, air moves end on landing; then cancels — chain
  Light/Heavy (after a hit, or after the active frames), normals → skills/ult/dash on hit, jump-cancel on hit;
  at the end, `then_move` (e.g. `ULT` → `ULT2`) or back to idle/air.
- **`_start_dash(dir)`**: 10-frame dash with cooldown; uses up the air dash when airborne.
- **`_step_jumpsquat()`**: the 3 pre-jump frames. An attack pressed now becomes a *ground* attack (W+K =
  launcher); otherwise it jumps.
- **`_try_burst() -> bool`**: in hitstun/airhit, Guard+Heavy with 2 bars → Burst (invulnerable, knocks enemies away via `world.burst_from`).
- **`knock_out(dir)`**: enters `ko` with a small launch; effectively invulnerable.
- **`_apply_physics()`**: gravity (not while dashing), `world.move_body`, landing resets air jumps/air dash,
  landing dust, jump pads (hold Up on a pad).
- Drawing (visual only): **`_draw()`** — the bug knight (legs, cloak with team hem, scarf, nail pose by state,
  horned mask, slash crescent, guard/parry/EX/invuln cues, debug boxes with F1; hidden 70 ticks after a KO);
  **`_draw_slash(local)`**, **`_draw_ellipse(center, radii, color)`**, **`_draw_ellipse_arc(...)`**.

---

## Controllers — `src/controllers/`

All controllers extend `FighterController` and only produce `InputFrame`s, so a fighter behaves identically
whoever drives it.

### `fighter_controller.gd` — `FighterController`
- **`read(fighter, world) -> InputFrame`**: base class; returns an empty frame.

### `manual_controller.gd` — `ManualController`
- **`read(...)`**: returns a copy of `frame`. Tests set `frame` before each `step()`.

### `player_controller.gd` — `PlayerController`
- **`_init()`**: makes sure the input actions exist (`InputBindings.register()`).
- **`read(...)`**: reads the InputMap: stick/keys → `x`/`y` with dead zones, buttons → held states.

### `input_bindings.gd` — `InputBindings`
All input actions are registered here in code (never in project settings), so bindings are versioned and
identical in editor, builds and headless tests.
- **`register()`** (static): adds every action once — movement (WASD/arrows/d-pad/stick), `jump` (Space/W/Up/A),
  `light` J/X, `heavy` K/Y, `s1` U/LB, `s2` I/RB, `ult` O/RT, `guard` L/B, `dash` Shift/LT, `debug_hitboxes` F1,
  `training_dummy_mode` F2/Back, `training_reset` F3/Start, `training_meter` F4, `match_restart` Enter/Start.
- **`_add(action, keys, buttons, axis, axis_value)`** (static): creates one action with its key, joypad button and axis events.

### `dummy_controller.gd` — `DummyController`
The training dummy (and the red fighter in the sandbox). Modes (F2): Stand, Guard everything, Jump, Attack
(L-L-H), Burst out of combos.
- **`next_mode()`**: cycles the mode.
- **`mode_name() -> String`**: label for the HUD.
- **`read(f, world)`**: if `home_x` is set and it was knocked away, walks back home first; otherwise acts out
  its mode against `target` (guarding turns to face first, since guard is front-only).

### `route_follower.gd` — `RouteFollower`
Drives a fighter along a route of standing surfaces from `RiftRoutes.plan()`.
- **`done() -> bool`**: reached the last surface.
- **`read(f, world)`**: moves toward the next surface; going up = full jump, then a double jump near the apex;
  going down through a one-way = Down+Jump. Records `visited_bands` (used by tests).

### `lane_bot.gd` — `LaneBot`
The enemy laner. Plays only through inputs, with a reaction delay, and its randomness comes from its own
seeded `rng` (never the sim) so matches are reproducible.

**Difficulty** (`Difficulty.EASY/NORMAL/HARD`, `TUNING`): `react` (ticks before it can respond to an attack:
24/15/9), `guard`/`parry`/`dodge` chances, `followup` (keeps combos going / bursts), `aggro`, `lasthit`
accuracy, `think` (ticks between macro decisions: 18/10/6), `retreat` (HP fraction that sends it home:
35/25/20%). Constants `ENGAGE_RANGE` 380, `CHASE_RANGE` 700, `HOLD_BEHIND` 70. `passive = true` = defend only.

Plans (`_plan`): `home`, `leave_tower`, `fight`, `last_hit`, `clear`, `siege`, `hold`.

Functions:
- **`_init(level, seed_value)`**: difficulty and RNG seed.
- **`set_difficulty(level)`**, **`difficulty_name()`**.
- **`read(f, w)`**: per tick, in priority order: KO → nothing; being comboed → burst if 3+ hits and meter;
  blockstun / guard hold → keep guarding; `_defend`; (passive stops here); run a queued input sequence;
  otherwise `_think` on its cadence and `_act`.
- **`_nearest_enemy(f, w) -> Fighter`**: closest living, targetable enemy fighter on roughly the same level.
- **`_watch(enemy, w)`**: notices when the enemy starts a new attack (time-stamps it for the reaction delay).
- **`_defend(f, e, w, i) -> bool`**: once the reaction time has passed and the attack is close and aimed at
  it: dodge an ult, turn to face, parry if the hit is 1–7 frames away, or hold guard through the active frames.
- **`_think(f, e, w)`**: macro decision. Retreat when HP < threshold (unless winning; stop at 90%); fight back
  if cornered by a weaker enemy; leave uncovered enemy tower range; fight within engage (or chase) range if
  `_want_fight`; last-hit if safe; clear the wave if safe; siege if the enemy is far; else hold.
- **`_want_fight(f, e, w, lane) -> bool`**: not under their tower (unless they're < 25%); all-in if they're
  < 35% and we have more HP; otherwise compare HP fractions scaled by aggression, or fight if very close.
- **`_act(f, e, w, i)`**: executes the plan (walk home — Hard dashes —, back out of tower range, `_fight`,
  `_strike_at` minions/structures, or hold position facing the enemy).
- **`_hold_x(f, w, lane) -> float`**: where to wait: `HOLD_BEHIND` px behind the front-most friendly minion,
  or in front of its first standing tower when there's no wave.
- **`_fight(f, e, w, i)`**: micro. Tower safety first (never step into uncovered tower range, never past
  their first tower unless `sure`: enemy < 150 HP, us > 600 HP, within 160 px). Then: ult to finish, S1
  anti-air, S2 gap close, walk/dash in, turn to face, grab vs guard, or a combo sequence — launcher air combo
  (`UH`, jump, `AL`, `AL`, `AH`) or `L1-L2-LH(-S1)` — that stops if the first hit didn't connect.
- **`_face_then(f, dir, i, press)`**: turn first, press next tick.
- **`_strike_at(f, target, i, full_combo, reach := 52)`**: walk into reach of a minion/structure and hit it (single Light for last hits, L-L-H otherwise).
- **`_start_seq(steps, check_at)`**: queues timed inputs `[tick offset, {button: value}]`; `check_at` = offset where it aborts if nothing connected.
- **`_run_seq(f, e, i)`**: plays the sequence one tick at a time, drifting toward the enemy between moves.
- **`_walk_to(f, x, i, slack)`**: walks toward `x`; jumps when stuck against a cliff.
- **`_nearest_enemy_minion(f, w, r)`**, **`_last_hit_target(f, w)`** (a minion one Light kills; may "misjudge" on lower difficulties),
  **`_siege_target(f, w, lane)`** (first vulnerable enemy structure tanked by our minions and not aiming at us),
  **`_first_enemy_tower(lane, team)`**, **`_tower_covering(w, lane, team, x)`** (a team's shooting structure whose range covers x),
  **`_enemy_tower_threat(f, w, lane)`** (a tower that would shoot us now), **`_covered(f, w, st)`** (our minions are
  in its range to take the shots), **`_safe_spot(f, w, lane, x)`** (x is outside enemy tower range or covered).
