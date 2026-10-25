class_name LaneMatch
extends RefCounted
## The match rules for one lane (the middle lane, Bloomway): each team's structure chain
## (outer tower → inner tower → gate → core), minion waves, gold and XP, levels, death and respawn,
## jungle monster rewards and team buffs, and the winner (whoever breaks the enemy core).
## Ticked by CombatWorld.step() after the simulation, so it is deterministic too.

const LANE := RiftLayout.STRUCTURE_FLOOR
## Blue's structures [kind, x]; Red's are mirrored. Each one is sealed until the previous one falls.
const LAYOUT := [[Structure.Kind.OUTER, &"outer"], [Structure.Kind.INNER, &"inner"], [Structure.Kind.GATE, &"gate"], [Structure.Kind.CORE, &"core"]]
const WAVE := [Minion.Kind.MELEE, Minion.Kind.MELEE, Minion.Kind.MELEE, Minion.Kind.RANGED, Minion.Kind.RANGED]
const MONSTER_REWARDS := {Monster.Kind.CAMP: [70, 90.0], Monster.Kind.WYRM: [80, 120.0], Monster.Kind.TITAN: [120, 160.0]}
const TEAM_NAMES: Array[String] = ["Blue", "Red"]

var world: CombatWorld
var winner := -1
var end_tick := -1
var team_kills: Array[int] = [0, 0]
var wyrm_stacks: Array[int] = [0, 0]
var titan_timer: Array[int] = [0, 0]
var spawn_points := {}   ## Fighter -> where it respawns
var feed: Array[Dictionary] = []  ## newest first: {"text", "team", "tick"}
var _chain: Array = [[], []]  ## per team, outer → core
var _recent := {}        ## victim Fighter -> {attacker Fighter: tick of last hit}
var _next_minion := 0


func setup(w: CombatWorld) -> void:
	world = w
	w.lane = self
	for team in 2:
		var prev: Structure = null
		for entry: Array in LAYOUT:
			var bx: float = RiftLayout.STRUCTURE_X[entry[1]]
			var x := bx if team == 0 else RiftLayout.WORLD_W - bx
			var st := Structure.new()
			st.setup(entry[0], team, Vector2(x, RiftLayout.ground_y(LANE, x)), prev)
			st.name = "%s_%s" % [TEAM_NAMES[team], st.display_name().replace(" ", "")]
			w.add_structure(st)
			_chain[team].append(st)
			prev = st
	for f in w.fighters:
		f.gold = CombatRules.START_GOLD
	w.combat_event.connect(_on_event)


func structure(team: int, kind: Structure.Kind) -> Structure:
	for st: Structure in _chain[team]:
		if st.kind == kind:
			return st
	return null


func base_spawn(team: int) -> Vector2:
	return Vector2(200.0 if team == 0 else RiftLayout.WORLD_W - 200.0, RiftLayout.FLOORS[LANE])


## Seconds of match time.
func clock() -> float:
	return (end_tick if end_tick >= 0 else world.tick) / float(CombatRules.TICK_RATE)


func ticks_to_next_wave() -> int:
	if world.tick < CombatRules.FIRST_WAVE:
		return CombatRules.FIRST_WAVE - world.tick
	return CombatRules.WAVE_INTERVAL - (world.tick - CombatRules.FIRST_WAVE) % CombatRules.WAVE_INTERVAL


func tick() -> void:
	var t := world.tick
	if winner < 0:
		if t >= CombatRules.FIRST_WAVE and (t - CombatRules.FIRST_WAVE) % CombatRules.WAVE_INTERVAL == 0:
			spawn_wave()
		if t % CombatRules.TICK_RATE == 0:
			for f in world.fighters:
				f.gold += CombatRules.PASSIVE_GOLD
	for team in 2:
		titan_timer[team] = maxi(0, titan_timer[team] - 1)
	for f in world.fighters:
		f.damage_buff = CombatRules.WYRM_BUFF * wyrm_stacks[f.team]
		if f.is_ko():
			if f.respawn_timer > 0:
				f.respawn_timer -= 1
				if f.respawn_timer == 0:
					_respawn(f)
		elif _in_own_base(f) and f.hp < f.max_hp():
			f.hp = minf(f.max_hp(), f.hp + f.max_hp() * CombatRules.FOUNTAIN_HEAL)


func spawn_wave() -> void:
	for team in 2:
		var dir := 1 if team == 0 else -1
		var kinds: Array = WAVE.duplicate()
		if not structure(1 - team, Structure.Kind.GATE).is_alive():
			kinds.push_front(Minion.Kind.SUPER)
		var gate := structure(team, Structure.Kind.GATE)
		var x0 := gate.position.x + dir * 60.0
		for i in kinds.size():
			var x := x0 - dir * i * CombatRules.WAVE_SPACING
			var mn := Minion.new()
			mn.id = _next_minion
			_next_minion += 1
			mn.setup(kinds[i], team, Vector2(x, RiftLayout.ground_y(LANE, x)), world.minutes(), titan_timer[team] > 0)
			world.add_minion(mn)


func _in_own_base(f: Fighter) -> bool:
	return f.position.x < RiftLayout.COL_W if f.team == 0 else f.position.x > RiftLayout.WORLD_W - RiftLayout.COL_W


func _respawn(f: Fighter) -> void:
	var meter := f.meter
	var at: Vector2 = spawn_points.get(f, base_spawn(f.team))
	f.reset_to(at, 1 if f.team == 0 else -1)
	f.meter = meter
	f.invuln = CombatRules.RESPAWN_INVULN
	world.add_effect(&"ring", at + Vector2(0, -40), {"radius": 90.0, "life": 20, "color": Color("ffc443")})


# ---------------------------------------------------------------- rewards

func give_gold(f: Fighter, amount: int, show := true) -> void:
	f.gold += amount
	if show:
		world.add_text(f.position + Vector2(0, -122), "+%d" % amount, CombatWorld.TEXT_GOLD, 14)


func give_xp(f: Fighter, amount: float) -> void:
	if f.level >= CombatRules.MAX_LEVEL:
		return
	f.xp += amount
	while f.level < CombatRules.MAX_LEVEL and f.xp >= CombatRules.xp_to_next(f.level):
		f.xp -= CombatRules.xp_to_next(f.level)
		var before := f.max_hp()
		f.level += 1
		if not f.is_ko():
			f.hp = minf(f.max_hp(), f.hp + (f.max_hp() - before) + f.max_hp() * 0.1)
		world.add_text(f.position + Vector2(0, -140), "LEVEL %d" % f.level, CombatWorld.TEXT_GOLD, 20)
		world.add_effect(&"ring", f.position + Vector2(0, -45), {"radius": 70.0, "life": 18, "color": CombatWorld.TEXT_GOLD})
	if f.level >= CombatRules.MAX_LEVEL:
		f.xp = 0.0


## XP shared by the team's fighters near `at` (65% each when shared).
func _share_xp(team: int, at: Vector2, amount: float) -> void:
	var near: Array[Fighter] = []
	for f in world.fighters:
		if f.team == team and not f.is_ko() and absf(f.position.x - at.x) < CombatRules.XP_RADIUS \
				and RiftLayout.band_of(f.position.y) == RiftLayout.band_of(at.y):
			near.append(f)
	for f in near:
		give_xp(f, amount * (0.65 if near.size() > 1 else 1.0))


func _post(text: String, team: int) -> void:
	feed.push_front({"text": text, "team": team, "tick": world.tick})
	if feed.size() > 5:
		feed.resize(5)


func _on_event(kind: StringName, info: Dictionary) -> void:
	match kind:
		&"hit":
			var att: Fighter = info["attacker"]
			var tgt: Fighter = info["target"]
			if not _recent.has(tgt):
				_recent[tgt] = {}
			_recent[tgt][att] = world.tick
		&"ko":
			_fighter_ko(info["target"], info["attacker"])
		&"minion_slain":
			var mn: Minion = info["minion"]
			var by: Node2D = info["by"]
			if by is Fighter and by.team != mn.team:
				var f := by as Fighter
				f.cs += 1
				give_gold(f, roundi(float(mn.def["gold"]) * (1.5 if mn.empowered else 1.0)))
			_share_xp(1 - mn.team, mn.position, mn.def["xp"])
		&"structure_destroyed":
			var st: Structure = info["structure"]
			var winners := 1 - st.team
			for f in world.fighters:
				if f.team == winners:
					give_gold(f, st.def["gold"], st.def["gold"] > 0)
					give_xp(f, st.def["xp"])
			_post("%s %s destroyed" % [TEAM_NAMES[st.team], st.display_name()], winners)
			if st.kind == Structure.Kind.CORE and winner < 0:
				winner = winners
				end_tick = world.tick
				_post("%s wins!" % TEAM_NAMES[winners], winners)
		&"monster_slain":
			var mon: Monster = info["monster"]
			var f: Fighter = info["by"]
			var reward: Array = MONSTER_REWARDS[mon.kind]
			give_gold(f, reward[0])
			_share_xp(f.team, mon.position, reward[1])
			match mon.kind:
				Monster.Kind.WYRM:
					wyrm_stacks[f.team] = mini(3, wyrm_stacks[f.team] + 1)
					_post("%s slew the Lumen Wyrm: +10%% damage" % TEAM_NAMES[f.team], f.team)
				Monster.Kind.TITAN:
					titan_timer[f.team] = CombatRules.TITAN_BUFF_FRAMES
					_post("%s slew the Hollow Titan: empowered minions" % TEAM_NAMES[f.team], f.team)


func _fighter_ko(v: Fighter, att: Node2D) -> void:
	if v.respawn_timer > 0:
		return
	v.deaths += 1
	v.respawn_timer = roundi((CombatRules.RESPAWN_BASE + CombatRules.RESPAWN_PER_LEVEL * v.level) * CombatRules.TICK_RATE)
	var hits: Dictionary = _recent.get(v, {})
	var killer: Fighter = att if att is Fighter and (att as Fighter).team != v.team else null
	if killer == null:  # killed by a tower, minion or monster: credit the last fighter who hit them
		var best := world.tick - CombatRules.ASSIST_WINDOW
		for a: Fighter in hits:
			if hits[a] > best:
				best = hits[a]
				killer = a
	team_kills[1 - v.team] += 1
	if killer != null:
		killer.kills += 1
		give_gold(killer, CombatRules.KILL_GOLD)
		give_xp(killer, CombatRules.KILL_XP + 20.0 * v.level)
		_post("%s slew %s" % [killer.data.display_name, v.data.display_name], killer.team)
	else:
		_post("%s was slain" % v.data.display_name, 1 - v.team)
	for a: Fighter in hits:
		if a != killer and is_instance_valid(a) and hits[a] > world.tick - CombatRules.ASSIST_WINDOW:
			a.assists += 1
			give_gold(a, CombatRules.ASSIST_GOLD)
			give_xp(a, CombatRules.ASSIST_XP)
	_recent.erase(v)
