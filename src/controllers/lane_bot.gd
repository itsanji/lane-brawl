class_name LaneBot
extends FighterController
## A laner bot for the lane match. It plays through InputFrames like a person would (only reading what
## is on screen) and reacts with a delay, so it can be out-played:
## - macro: stays behind its minions, last-hits, clears the wave when no enemy fighter is near, hits
##   structures while its minions tank the tower, never stands in enemy tower range without minions,
##   goes home to heal when low.
## - micro: spacing, Light-Light-Heavy strings, launcher air combos, Rising Fang as anti-air, Phantom
##   Dash to close gaps, ult to finish, burst out of long combos; guards, parries and dodges after its
##   reaction time.
## Deterministic: its "dice" come from a seeded RNG, never from the sim.

enum Difficulty { EASY, NORMAL, HARD }
const NAMES: Array[String] = ["Easy", "Normal", "Hard"]
const TUNING := {
	Difficulty.EASY: {"react": 24, "guard": 0.25, "parry": 0.0, "dodge": 0.0, "followup": 0.4, "aggro": 0.45, "lasthit": 0.5, "think": 18, "retreat": 0.35},
	Difficulty.NORMAL: {"react": 15, "guard": 0.55, "parry": 0.15, "dodge": 0.4, "followup": 0.75, "aggro": 0.75, "lasthit": 0.85, "think": 10, "retreat": 0.25},
	Difficulty.HARD: {"react": 9, "guard": 0.8, "parry": 0.45, "dodge": 0.8, "followup": 1.0, "aggro": 1.0, "lasthit": 1.0, "think": 6, "retreat": 0.2},
}
const ENGAGE_RANGE := 380.0
const CHASE_RANGE := 700.0  ## a low enemy gets chased further (not under its tower)
const HOLD_BEHIND := 70.0

var difficulty := Difficulty.NORMAL
var t: Dictionary = TUNING[Difficulty.NORMAL]
var rng := RandomNumberGenerator.new()
var retreating := false
var passive := false  ## only defends (practice / tests): never starts attacks

var _seq: Array = []        ## queued inputs: [tick offset, {button/axis: value}]
var _seq_t := 0
var _seq_check := -1        ## offset at which the combo continues only if it connected
var _guard_until := -1      ## holding guard until this world tick
var _seen_move: MoveData    ## the enemy attack currently being watched
var _seen_at := 0           ## world tick we saw it start
var _reacted := false
var _jump_hold := 0
var _last_x := 0.0
var _stuck := 0
var _next_think := 0
var _plan: StringName = &"lane"
var _plan_target: Node2D


func _init(level := Difficulty.NORMAL, seed_value := 1) -> void:
	set_difficulty(level)
	rng.seed = seed_value


func set_difficulty(level: Difficulty) -> void:
	difficulty = level
	t = TUNING[level]


func difficulty_name() -> String:
	return NAMES[difficulty]


func read(f: Fighter, w: CombatWorld) -> InputFrame:
	var i := InputFrame.new()
	if f.is_ko():
		_seq.clear()
		return i
	var enemy := _nearest_enemy(f, w)
	_watch(enemy, w)
	# getting comboed: burst out of long strings when there's meter
	if f.is_in_hit_state():
		_seq.clear()
		if f.combo >= 3 and f.meter >= CombatRules.BURST_COST and rng.randf() < t["followup"]:
			i.guard = true
			i.heavy = w.tick % 2 == 0
		return i
	if f.state == &"blockstun" or w.tick < _guard_until:
		i.guard = true
		i.x = 0
		return i
	if _defend(f, enemy, w, i):
		return i
	if passive:
		return i
	if not _seq.is_empty():
		_run_seq(f, enemy, i)
		return i
	if _jump_hold > 0:
		_jump_hold -= 1
		i.jump = true
	if w.tick >= _next_think:
		_next_think = w.tick + int(t["think"])
		_think(f, enemy, w)
	_act(f, enemy, w, i)
	return i


# ---------------------------------------------------------------- perception and defence

func _nearest_enemy(f: Fighter, w: CombatWorld) -> Fighter:
	var best: Fighter = null
	for e in w.fighters:
		if e.team != f.team and not e.is_ko() and e.invuln < 900 and absf(e.position.y - f.position.y) < 200.0:
			if best == null or absf(e.position.x - f.position.x) < absf(best.position.x - f.position.x):
				best = e
	return best


func _watch(enemy: Fighter, w: CombatWorld) -> void:
	var m: MoveData = enemy.move if enemy != null and enemy.state == &"attack" else null
	if m != _seen_move:
		_seen_move = m
		_seen_at = w.tick
		_reacted = false


## Reacts to an attack it has had time to see: parry, dodge or guard. Returns true if it acted.
func _defend(f: Fighter, e: Fighter, w: CombatWorld, i: InputFrame) -> bool:
	if e == null or _seen_move == null or _reacted or not f.is_actionable() or not f.grounded:
		return false
	if w.tick - _seen_at < int(t["react"]):
		return false
	var dx := e.position.x - f.position.x
	var facing_me := int(signf(-dx)) == e.facing
	var frames_left := _seen_move.startup + _seen_move.active - e.move_frame
	if not facing_me or absf(dx) > 170.0 or frames_left <= 0:
		return false
	_reacted = true
	_seq.clear()
	var dir := int(signf(dx)) if dx != 0.0 else f.facing
	if _seen_move.kind == MoveData.Kind.ULT and f.dodge_cooldown == 0 and rng.randf() < t["dodge"]:
		i.guard = true  # dodge away (Guard tap + direction)
		i.x = -dir
		return true
	if f.facing != dir:
		i.x = dir  # turn to face it first; guard only works from the front
		_reacted = false
		return true
	var to_active := _seen_move.startup - e.move_frame
	if to_active >= 1 and to_active <= 7 and rng.randf() < t["parry"]:
		i.guard = true  # a tap right before the hit: parry
		return true
	if rng.randf() < t["guard"]:
		i.guard = true
		_guard_until = w.tick + frames_left + 4
		return true
	return false


# ---------------------------------------------------------------- decisions

func _think(f: Fighter, e: Fighter, w: CombatWorld) -> void:
	var lane: LaneMatch = w.lane
	var hp_k := f.hp / f.max_hp()
	var winning := e != null and e.hp < f.hp and absf(e.position.x - f.position.x) < 220.0
	if retreating and hp_k > 0.9:
		retreating = false
	if not retreating and hp_k < float(t["retreat"]) and not winning:
		retreating = true
	if retreating and winning and _tower_covering(w, lane, 1 - f.team, e.position.x) == null:
		_plan = &"fight"  # cornered by someone weaker: turn and finish it
		_plan_target = e
		return
	if retreating:
		_plan = &"home"
		return
	var tower := _enemy_tower_threat(f, w, lane)
	if tower != null:
		_plan = &"leave_tower"
		_plan_target = tower
		return
	var e_dist := absf(e.position.x - f.position.x) if e != null else INF
	var e_low := e != null and e.hp / e.max_hp() < 0.3
	if e_dist < (CHASE_RANGE if e_low else ENGAGE_RANGE) and _want_fight(f, e, w, lane):
		_plan = &"fight"
		_plan_target = e
		return
	var prey := _last_hit_target(f, w)
	if prey != null and _safe_spot(f, w, lane, prey.position.x):
		_plan = &"last_hit"
		_plan_target = prey
		return
	# push the wave: hit their minions (while trading, too, unless their fighter is right on top of you)
	var mn := _nearest_enemy_minion(f, w, 300.0)
	if mn != null and _safe_spot(f, w, lane, mn.position.x) and (e_dist > 200.0 or rng.randf() < 0.5 * float(t["aggro"])):
		_plan = &"clear"
		_plan_target = mn
		return
	if e_dist > 300.0:
		var st := _siege_target(f, w, lane)
		if st != null:
			_plan = &"siege"
			_plan_target = st
			return
	_plan = &"hold"


func _want_fight(f: Fighter, e: Fighter, w: CombatWorld, lane: LaneMatch) -> bool:
	if lane != null:
		var their_tower := _tower_covering(w, lane, 1 - f.team, e.position.x)
		if their_tower != null and e.hp / e.max_hp() > 0.25:
			return false  # don't chase under their tower
	var mine := f.hp / f.max_hp()
	var theirs := e.hp / e.max_hp()
	if theirs < 0.35 and f.hp > e.hp:
		return true  # all in
	return mine >= theirs * (1.2 - 0.5 * float(t["aggro"])) or absf(e.position.x - f.position.x) < 120.0


func _act(f: Fighter, e: Fighter, w: CombatWorld, i: InputFrame) -> void:
	var lane: LaneMatch = w.lane
	var dir := 1 if f.team == 0 else -1
	match _plan:
		&"home":
			var home := lane.base_spawn(f.team).x if lane != null else f.position.x
			_walk_to(f, home, i, 30.0)
			i.dash = difficulty == Difficulty.HARD and absf(home - f.position.x) > 300.0 and f.dash_cooldown == 0 and w.tick % 7 == 0
		&"leave_tower":
			var tw := _plan_target as Structure
			_walk_to(f, tw.position.x - dir * (float(tw.def["range"]) + 60.0), i, 20.0)
		&"fight":
			if CombatWorld.alive(_plan_target):
				_fight(f, _plan_target as Fighter, w, i)
		&"last_hit", &"clear":
			if CombatWorld.alive(_plan_target):
				_strike_at(f, _plan_target, i, _plan == &"clear")
		&"siege":
			if CombatWorld.alive(_plan_target):
				var st := _plan_target as Structure
				_strike_at(f, st, i, true, st.body_size().x * 0.5 + 18.0)
		_:
			_walk_to(f, _hold_x(f, w, lane), i, 30.0)
			if i.x == 0 and e != null and f.grounded and absf(f.vel.x) < 0.5 and f.facing != int(signf(e.position.x - f.position.x)):
				i.x = int(signf(e.position.x - f.position.x))  # turn to watch the enemy


func _hold_x(f: Fighter, w: CombatWorld, lane: LaneMatch) -> float:
	var dir := 1.0 if f.team == 0 else -1.0
	var front := -INF
	for mn in w.minions:
		if mn.team == f.team:
			front = maxf(front, mn.position.x * dir)
	if front > -INF:
		return front * dir - dir * HOLD_BEHIND
	if lane != null:  # no wave: wait in front of your own first standing tower
		for st: Structure in lane._chain[f.team]:
			if st.is_alive():
				return st.position.x + dir * 160.0
	return f.position.x


# ---------------------------------------------------------------- fighting

func _fight(f: Fighter, e: Fighter, w: CombatWorld, i: InputFrame) -> void:
	var dx := e.position.x - f.position.x
	var dist := absf(dx)
	var dir := int(signf(dx)) if dx != 0.0 else f.facing
	if not f.is_actionable():
		return
	var lane: LaneMatch = w.lane
	if lane != null:  # never follow into a tower that would shoot you (unless it's a sure kill)
		var tw := _tower_covering(w, lane, 1 - f.team, f.position.x + dir * 60.0)
		var sure := e.hp < 150.0 and f.hp > 600.0 and dist < 160.0
		if tw != null and not _covered(f, w, tw) and not sure:
			_walk_to(f, tw.position.x - dir * (float(tw.def["range"]) + 60.0), i, 20.0)
			return
		var march := 1.0 if f.team == 0 else -1.0
		var first := _first_enemy_tower(lane, f.team)
		if first != null and not sure and (f.position.x + march * 60.0 - first.position.x) * march > 0.0:
			_walk_to(f, first.position.x - march * 120.0, i, 20.0)  # never chase past their tower
			return
	if f.meter >= CombatRules.METER_MAX and dist < 100.0 and e.hp / e.max_hp() < 0.45 and f.facing == dir:
		i.ult = true
		return
	if not e.grounded and dist < 70.0 and f.cooldowns[&"S1"] == 0 and e.position.y < f.position.y - 40.0:
		_face_then(f, dir, i, func() -> void: i.s1 = true)  # anti-air
		return
	var chasing := e.hp / e.max_hp() < 0.35
	if dist > 140.0 and dist < 230.0 and f.cooldowns[&"S2"] == 0 and (chasing or rng.randf() < 0.08 * float(t["aggro"])):
		_face_then(f, dir, i, func() -> void: i.s2 = true)  # gap closer
		return
	if dist > 62.0:
		i.x = dir
		if dist > 120.0 and f.dash_cooldown == 0 and (chasing or rng.randf() < 0.04 * float(t["aggro"])):
			i.dash = true
		return
	if f.facing != dir:
		i.x = dir
		return
	if e.state == &"guard" and difficulty != Difficulty.EASY and rng.randf() < 0.35:
		_start_seq([[0, {&"guard": true, &"light": true}]], -1)  # grab beats guard
		return
	if rng.randf() < 0.35 * float(t["followup"]):
		_start_seq([[0, {&"heavy": true, &"y": -1}], [15, {&"jump": true}], [16, {&"jump": true}], [17, {&"jump": true}],
			[18, {&"jump": true}], [21, {&"light": true}], [27, {&"light": true}], [33, {&"heavy": true}]], 14)
	else:
		_start_seq([[0, {&"light": true}], [8, {&"light": true}], [16, {&"heavy": true}], [26, {&"s1": rng.randf() < 0.3}]], 7)


func _face_then(f: Fighter, dir: int, i: InputFrame, press: Callable) -> void:
	if f.facing != dir:
		i.x = dir
	else:
		press.call()


func _strike_at(f: Fighter, target: Node2D, i: InputFrame, full_combo: bool, reach := 52.0) -> void:
	var dx := target.position.x - f.position.x
	var dir := int(signf(dx)) if dx != 0.0 else f.facing
	if absf(dx) > reach:
		_walk_to(f, target.position.x - dir * (reach - 10.0), i, 8.0)
		return
	if not f.is_actionable():
		return
	if f.facing != dir:
		i.x = dir
		return
	if full_combo:
		_start_seq([[0, {&"light": true}], [8, {&"light": true}], [16, {&"heavy": true}]], -1)
	else:
		i.light = true


func _start_seq(steps: Array, check_at: int) -> void:
	_seq = steps
	_seq_t = 0
	_seq_check = check_at


func _run_seq(f: Fighter, e: Fighter, i: InputFrame) -> void:
	if _seq_t == _seq_check and not f.connected and rng.randf() < t["followup"]:
		_seq.clear()  # it didn't hit: don't keep swinging into a guard
		return
	for step: Array in _seq:
		if step[0] == _seq_t:
			var d: Dictionary = step[1]
			for k: StringName in d:
				i.set(k, d[k])
	if e != null:
		var dx := e.position.x - f.position.x
		if f.state != &"attack" and absf(dx) > 20.0 and i.x == 0:
			i.x = int(signf(dx)) if absf(dx) > 70.0 else 0
	_seq_t += 1
	if _seq_t > (_seq.back() as Array)[0]:
		_seq.clear()


# ---------------------------------------------------------------- lane helpers

func _walk_to(f: Fighter, x: float, i: InputFrame, slack: float) -> void:
	var dx := x - f.position.x
	if absf(dx) <= slack:
		_stuck = 0
		return
	i.x = int(signf(dx))
	# blocked by a cliff: jump it
	if f.grounded and f.is_actionable() and absf(f.position.x - _last_x) < 0.5:
		_stuck += 1
		if _stuck > 4:
			_jump_hold = 14
			_stuck = 0
	else:
		_stuck = 0
	_last_x = f.position.x
	if _jump_hold > 0:
		i.jump = true


func _nearest_enemy_minion(f: Fighter, w: CombatWorld, r: float) -> Minion:
	var best: Minion = null
	for mn in w.minions:
		if mn.team != f.team and absf(mn.position.x - f.position.x) < r and absf(mn.position.y - f.position.y) < 160.0:
			if best == null or absf(mn.position.x - f.position.x) < absf(best.position.x - f.position.x):
				best = mn
	return best


## An enemy minion one Light would kill (with some misjudging on lower difficulties).
func _last_hit_target(f: Fighter, w: CombatWorld) -> Minion:
	var light := 30.0 * f.power()
	var best: Minion = null
	for mn in w.minions:
		if mn.team != f.team and mn.hp <= light * 1.4 and absf(mn.position.x - f.position.x) < 240.0 and absf(mn.position.y - f.position.y) < 160.0:
			if best == null or mn.hp < best.hp:
				best = mn
	if best != null and rng.randf() > float(t["lasthit"]):
		return null
	return best


## The enemy structure to hit while your minions tank it (only when it isn't aiming at you).
func _siege_target(f: Fighter, w: CombatWorld, lane: LaneMatch) -> Structure:
	if lane == null:
		return null
	for st: Structure in lane._chain[1 - f.team]:
		if not st.is_alive():
			continue
		if not st.vulnerable():
			return null
		var tanked := w.minions.any(func(mn: Minion) -> bool: return mn.team == f.team and absf(mn.position.x - st.position.x) < 240.0)
		if tanked and st.aiming_at == null and absf(st.position.x - f.position.x) < 700.0:
			return st
		return null
	return null


func _first_enemy_tower(lane: LaneMatch, team: int) -> Structure:
	for st: Structure in lane._chain[1 - team]:
		if st.is_alive() and st.shoots():
			return st
	return null


func _tower_covering(w: CombatWorld, lane: LaneMatch, team: int, x: float) -> Structure:
	for st: Structure in lane._chain[team]:
		if st.is_alive() and st.shoots() and absf(st.position.x - x) < float(st.def["range"]):
			return st
	return null


## An enemy tower that would shoot us: we're in range and none of our minions are there to take the shots.
func _enemy_tower_threat(f: Fighter, w: CombatWorld, lane: LaneMatch) -> Structure:
	if lane == null:
		return null
	var st := _tower_covering(w, lane, 1 - f.team, f.position.x)
	if st == null:
		return null
	if st.aiming_at == f:
		return st
	return null if _covered(f, w, st) else st


## Our minions are in that tower's range to take its shots.
func _covered(f: Fighter, w: CombatWorld, st: Structure) -> bool:
	return st.aiming_at != f and w.minions.any(func(mn: Minion) -> bool: return mn.team == f.team and st.in_range(mn) and mn.hp > 60.0)


func _safe_spot(f: Fighter, w: CombatWorld, lane: LaneMatch, x: float) -> bool:
	if lane == null:
		return true
	var st := _tower_covering(w, lane, 1 - f.team, x)
	if st == null:
		return true
	return w.minions.any(func(mn: Minion) -> bool: return mn.team == f.team and st.in_range(mn))
