# Combat core — `src/combat/`, `src/data/`

The deterministic simulation. Everything here runs at a fixed 60 ticks/s with no Godot physics, so the same
code runs in the client, in tests and (later) on a headless server. Rendering code may *read* these objects but
never changes them.

Units: pixels, pixels/tick, ticks. A unit's `position` is the centre of its feet; y grows downward.

---

## `combat_rules.gd` — `CombatRules`

All tuning constants. Change numbers here, not in logic files.

| Group | Constants |
|---|---|
| Time | `TICK_RATE` 60 |
| Movement | `GRAVITY`, `MAX_FALL`, `JUMP_VELOCITY`, `AIR_JUMP_VELOCITY`, `AIR_CONTROL`, `RUN_ACCEL`, `RUN_DECEL`, `TURN_DECEL`, `JUMPSQUAT_FRAMES` (3), `JUMP_CUT_VELOCITY` (release jump early = short hop), `DASH_SPEED`/`DASH_FRAMES`/`DASH_COOLDOWN`, `BODY_SIZE` (34×82), `DROP_FRAMES` (drop-through time), `STEP_UP` (14 px — larger terrain rises are cliffs), `PAD_*` (jump pads) |
| Inputs / defence | `BUFFER_FRAMES` (8), `EX_CHECK_FRAME` (skill held on this frame = EX), `PARRY_WINDOW` (9), `PARRY_REWARD_FRAMES` (next hit +50%), `PARRY_STAGGER`, `DODGE_*` |
| Juggles | `JUGGLE_MAX` (4), `KNOCKDOWN_FRAMES`, `WAKE_INVULN`, `TUMBLE_*` |
| Guard | `GUARD_MAX`, `GUARD_REGEN`, `GUARD_BREAK_FRAMES` |
| Meter | `METER_MAX` 300 (3 bars of `METER_BAR` 100), `BURST_COST` 200, `BURST_RADIUS`, `METER_ON_HIT`, `METER_ON_HURT` |
| Lane | `FIRST_WAVE` (0:05), `WAVE_INTERVAL` (25 s), `WAVE_SPACING`, `TOWER_RANGE`, `CORE_RANGE`, `TOWER_AGGRO_FRAMES`, `BACKDOOR_MULT`/`BACKDOOR_RADIUS` |
| Economy / levels | `MAX_LEVEL` 10, `START_GOLD`, `PASSIVE_GOLD` (per second), `KILL_GOLD`, `ASSIST_GOLD`, `KILL_XP` (+20/victim level), `ASSIST_XP`, `ASSIST_WINDOW` (600 ticks), `XP_RADIUS`, `RESPAWN_BASE` + `RESPAWN_PER_LEVEL` (seconds), `RESPAWN_INVULN`, `FOUNTAIN_HEAL`, `WYRM_BUFF`, `TITAN_BUFF_FRAMES` |

### Functions
- **`combo_scale(hits_before: int) -> float`** (static): damage multiplier for the next hit of a combo,
  `max(0.3, 1 - 0.1·hits_before)` — −10% per hit already taken, never below 30%.
- **`xp_to_next(level: int) -> float`** (static): XP needed to go from `level` to `level+1`: `140 + 90·(level−1)`.

---

## `input_frame.gd` — `InputFrame`

One tick of input: `x`, `y` (−1/0/1) and the buttons in `BUTTONS` (`jump light heavy s1 s2 ult dash guard`).
Every controller (player, bot, test, future network) produces these; the sim reads nothing else.
Buttons are *held* states; `Fighter` turns them into presses by comparing with the previous frame.

- **`copy() -> InputFrame`**: a deep copy (used to remember `prev_input`).

---

## `move_data.gd` — `MoveData` (Resource)

Frame data for one attack. `Kind`: `LIGHT, HEAVY, GRAB, SKILL, ULT`.
Key fields: `startup/active/recovery` (frames), `cooldown` (seconds, skills only), `damage`, `hitbox`
(`Rect2(forward offset, top relative to feet, w, h)`, mirrored when facing left), `hitstun`, `knockback`,
`juggle_cost` (−1 = 1 if target airborne), `guard_damage` (−1 = half damage), `hitstop` (0 = auto),
flags `launch knockdown grab unblockable`, `multi_hit_interval`, flow `air chain_light chain_heavy jump_cancel then_move`,
self movement `self_velocity self_frames`, invulnerability `invuln_from invuln_to`.

- **`total_frames() -> int`**: startup + active + recovery.
- **`is_active_frame(frame) -> bool`**: true while `startup < frame ≤ startup+active` (the hitbox is out).
- **`is_normal() -> bool`**: LIGHT or HEAVY (normals can chain and be cancelled into skills).
- **`get_hitstop() -> int`**: explicit `hitstop`, else 5 for HEAVY and 3 for everything else.

## `fighter_data.gd` — `FighterData` (Resource)

Per-fighter stats: `id display_name role archetype color max_hp run_speed damage_mult air_jumps` and `moves`
(`StringName → MoveData`).

- **`get_move(move_id) -> MoveData`**: the move, or `null` if this fighter doesn't have it.

## `src/data/roster.gd` — `Roster`

Fighters and moves as dictionaries, ported from the HTML prototype. `NORMALS` are shared by every fighter
(`L1 L2 L3 LH H UH DH AL AH GRAB`); each fighter (only `KAEL` so far: `S1` Rising Fang, `S2` Phantom Dash,
`ULT`/`ULT2` Thousand Cuts) can add or override moves. `FIGHTERS` maps id → definition.

- **`fighter(fighter_id) -> FighterData`** (static): builds a `FighterData` — copies stats, then adds NORMALS, then the fighter's own moves.
- **`make_move(move_id, def) -> MoveData`** (static): builds a `MoveData` from a dictionary; unknown keys raise `push_error` (catches typos).

---

## `combat_world.gd` — `CombatWorld` (Node2D)

Owns geometry, every unit and the tick loop. `RiftStage` and `TrainingStage` extend it.

**Signal** `combat_event(kind, info)` — kinds: `hit`, `block`, `parry`, `ko`, `burst`, `monster_hit`,
`monster_slain`, `minion_slain`, `structure_destroyed`. `LaneMatch`, tests, the HUD and tools listen to it.

**State**: `tick`, `solids`, `one_ways`, `jump_pads`, `grounds` (`GroundStrip`s), `fighters`, `monsters`,
`minions`, `structures`, `shots` (homing orb dictionaries), `lane` (`LaneMatch` or null), `effects` (visual only),
`training_mode` (fighters can't drop below 1 HP), `debug_draw`, `shake`, `auto_tick`.

### Setup
- **`add_solid(rect, one_way := false)`**: adds a solid rectangle, or a one-way platform you can jump through from below and drop through.
- **`add_fighter(f, controller)`**: registers a fighter with its controller and parents it under the world.
- **`add_monster(m)`, `add_minion(m)`, `add_structure(s)`**: register the unit, set its `world`, parent it.
- **`minutes() -> float`**: match time in minutes (minion and tower damage scale with it).
- **`alive(n: Variant) -> bool`** (static): true for a living fighter/minion/structure/monster; false for null
  or **freed** objects. Deliberately untyped — a freed object can't be passed to a typed parameter. Use it for
  anything that may hold a minion (they get `queue_free`d).

### Tick
- **`step()`**: one simulation tick, in this exact order: `tick += 1` → every fighter `read_input()` → fighters
  `sim_tick()` → monsters → structures → minions → `_tick_shots()` → `_resolve_hits()` → `_remove_dead_minions()`
  → `lane.tick()` → `_age_effects()`. Order matters for determinism; don't reorder casually.

### Movement
- **`move_body(f)`**: moves a fighter by its velocity with collision. X first: pushes out of solids, and blocks
  sideways movement into a terrain rise higher than `STEP_UP` (a cliff — jump it). Then Y: lands on solids
  (and bonks heads on them), lands on one-ways unless `drop_timer` is running, then follows `GroundStrip`
  terrain — snapping down up to 14 px while walking downhill so you stick to slopes, and pushing you out on
  top if you're inside a hill. Sets `grounded` and `on_one_way`.
- **`surface_y(x, near_y) -> float`**: the ground height at `x` for something standing around height `near_y`
  (the terrain strip of the floor just below it). Monsters, minions and structure range lines use it.

### Fighter vs fighter hits
- **`_resolve_hits()`**: for each fighter with an active hitbox (and not in hitstop), checks it against enemy
  fighters, monsters, enemy minions and enemy structures. Each target can be hit once per move (`hit_ids`;
  multi-hit moves clear it). Stops early if the attacker's move changed during the loop (e.g. it got parried).
- **`apply_hit(att, tgt, m, dir, is_ex := false) -> StringName`**: the core of combat. Returns `&"hit"`, `&"block"`,
  `&"parry"` or `&"whiff"`. In order:
  1. Whiff if the target is invulnerable or KO.
  2. **Parry**: target tapped guard within `PARRY_WINDOW`, is facing the attacker, move is defendable → attacker
     staggers (if close), target gains +50% next hit, meter and guard.
  3. **Grab** whiffs on airborne targets and on targets past the startup of their own attack (attacks beat grabs).
  4. **Guard** (front only): guard meter damage, blockstun, push back; skills/ults chip 15% HP; guard reaching 0
     → `guardbreak`.
  5. **Clean hit**: damage = move damage × `att.power()` × EX 1.5 × counter-hit 1.25 × parry reward 1.5 ×
     `combo_scale`. Gives meter to both, increases combo, applies hitstop, draws numbers/sparks, triggers tower
     aggro, KOs at 0 HP (emits `ko`). Otherwise puts the target into `hitstun` (grounded) or `airhit`
     (launches, airborne targets, big upward knockback, knockdowns) and adds juggle cost; at `JUGGLE_MAX` the
     target `tumble`s, invulnerable until it gets up. Air hits pull the attacker along with the target so air
     strings connect. Emits `hit`.
- **`burst_from(f)`**: Burst — knocks every nearby enemy (within `BURST_RADIUS`) away and up. The fighter pays the meter.

### Monsters and environment hits
- **`_hit_monster(f, mon, m)`**: a fighter's move hits a monster: damage, hitstop on both, meter, effects; emits `monster_slain` when it dies.
- **`monster_strike(mon)`**: a monster's telegraphed attack lands — every fighter inside `mon.attack_box()` is hit via `_monster_hits_fighter`.
- **`_monster_hits_fighter(mon, t)`**: wraps `env_hit`; a parry staggers the monster for 70 ticks.
- **`env_hit(source, from_x, t, dmg, kb, hitstun, parryable) -> StringName`**: a hit from the environment
  (monster, tower) on a fighter. Parry if allowed, guard from the front (60% guard damage, 10% chip), otherwise
  a clean hit into `airhit`. KOs emit `ko` with `source` as the attacker.

### Lane: minions, structures, shots
- **`add_shot(source, target, dmg, speed, at)`**: spawns a homing orb (towers: big, ranged minions: small), team coloured.
- **`_tick_shots()`**: moves each orb toward its target's hurtbox centre; on arrival calls `unit_hits`. Orbs
  whose target died vanish; orbs live at most 150 ticks.
- **`unit_hits(source, t, dmg, from_x := INF, tower := false)`**: damage from a minion or tower to anything.
  Minions → `damage_minion`; structures → `damage_structure`; fighters → `env_hit` for tower shots, otherwise
  *chip* damage that never interrupts (guarding from the front takes 25%).
- **`damage_minion(mn, dmg, by, dir := 0)`**: damages a minion; emits `minion_slain` (with `by`, used for last-hit gold).
- **`damage_structure(st, dmg, by)`**: damages a structure if it's alive and not sealed; emits `structure_destroyed`.
- **`_hit_minion(f, mn, m)`**: a fighter's move hits a minion.
- **`_hit_structure(f, st, m)`**: a fighter hits a structure. Sealed → "SEALED", no damage. Without friendly
  minions within `BACKDOOR_RADIUS` → half damage (anti-backdoor).
- **`_tower_aggro(att, victim)`**: when `att` hits `victim`, every living tower of the victim's team that has `att` in range targets `att` for `TOWER_AGGRO_FRAMES`.
- **`_remove_dead_minions()`**: frees dead minions and removes them from `minions`.

### Effects (visual only, but ticked by the sim so they're deterministic)
- **`add_effect(kind, at, extra := {})`**: queues an effect dictionary (`spark`, `ring`, `block`, `puff`, `text`, ...) drawn by `EffectsLayer`.
- **`add_text(at, text, color, size := 16)`**: a floating text (damage numbers, "PARRY", "+25" gold).
- **`_age_effects()`**: ages and drops finished effects (cap 120), floats texts upward, decays screen shake.

---

## `minion.gd` — `Minion` (Node2D)

Lane minions. `Kind`: `MELEE` (Husk), `RANGED` (Lanternling, throws orbs), `SUPER` (Husk Brute, after the enemy
gate falls). `DEFS` hold hp, damage, range, cooldown, speed, size, gold, xp. HP and damage grow with match minutes
(+7% / +5% per minute); Titan-empowered minions get ×1.6.
`HURT_HEIGHT` 64 makes the hurtbox tall enough for fighters' standing attacks to connect.

- **`setup(kind, team, at, minutes, is_empowered := false)`**: initialises stats and position.
- **`march_dir() -> int`**: +1 for Blue (marches right), −1 for Red.
- **`is_alive() -> bool`**: hp > 0.
- **`body_size() -> Vector2`**: drawing size (×1.2 when empowered).
- **`hurtbox() -> Rect2`**: at least 64 px tall and 8 px wider than the body.
- **`sim_tick()`**: knockback decay → retarget every 10 ticks (staggered by `id`) or when the target died →
  wind up (12 ticks) then strike, or walk toward the target, or march toward the enemy base. Follows the terrain
  smoothly (no popping up cliffs).
- **`_pick_target() -> Node2D`**: nearest enemy minion within 260 px; else nearest enemy structure; else an enemy fighter within 170 px.
- **`_strike(t)`**: ranged → `world.add_shot`; melee → `world.unit_hits` (×1.6 vs structures).
- **`take_damage(amount, by, dir := 0)`**: lose HP, flash; if hit by a fighter remember `last_fighter`, get knocked back and delayed.
- **`_draw()`, `_ellipse()`**: small husk bugs in team colours (mask, hem, staff orb for ranged, horns for super, HP bar).

## `structure.gd` — `Structure` (Node2D)

`Kind`: `OUTER`, `INNER` (towers), `GATE` (no attack), `CORE` (shoots faster, losing it loses the match).
`guards` = the structure in front; this one is sealed until that one falls.

- **`setup(kind, team, at, protected_by)`**: initialises it.
- **`display_name()`, `is_alive()`, `shoots()`, `body_size()`, `hurtbox()`**: accessors.
- **`vulnerable() -> bool`**: true once the guarding structure is gone.
- **`in_range(n) -> bool`**: horizontally within its range and within 320 px vertically.
- **`muzzle() -> Vector2`**: where orbs leave from.
- **`sim_tick()`**: counts down aggro, picks a target, sets `aiming_at`/`has_target` (for drawing), fires every
  `rate` ticks: 85 damage to minions, 115 × (1 + 6%/minute) to fighters.
- **`_pick_target() -> Node2D`**: aggro'd fighter in range → nearest enemy minion → nearest enemy fighter.
- **`take_damage(amount)`**: lose HP, flash.
- Drawing: **`_draw()`** (dispatch + HP bar + warning line at `aiming_at`), **`_draw_range()`** (range line on the
  ground when an enemy fighter is near), **`_draw_tower()`**, **`_draw_gate()`**, **`_draw_core()`**,
  **`_rubble()`** (destroyed), **`_draw_hp()`** (lock ring when sealed).

## `monster.gd` — `Monster` (Node2D)

Jungle monsters. `Kind`: `CAMP` (Mossback), `WYRM` (Lumen Wyrm, lower jungle boss), `TITAN` (Hollow Titan, upper
jungle boss). States: `idle → chase → windup (telegraphed) → strike → recover`, plus `stagger` (parried),
`return` (leashed: walks home and heals) and `dead` (respawn timer).

- **`setup(kind, at)`**: sets home, HP and facing (toward the map centre).
- **`display_name()`, `is_alive()`, `is_boss()`, `body_size()`, `hurtbox()`**: accessors.
- **`attack_box() -> Rect2`**: where the next attack lands — in front for camps, both sides for bosses.
- **`sim_tick()`**: the state machine above; stays on the terrain via `world.surface_y`.
- **`_walk(v)`**: moves unless that would leave the leash radius.
- **`_target_valid() -> bool`**: target is alive, inside the leash (+120) and roughly on the same level.
- **`take_hit(att, dmg, dir)`**: lose HP, aggro on the attacker, light camps get pushed; at 0 HP → `dead` with a respawn timer.
- Drawing: **`_draw()`** (telegraph box, body, HP bar/boss name), **`_ellipse()`**, **`_mask()`**,
  **`_draw_mossback()`**, **`_draw_wyrm()`**, **`_draw_titan()`**.
