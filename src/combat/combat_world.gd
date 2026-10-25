class_name CombatWorld
extends Node2D
## Owns the level geometry and fighters and advances the simulation one fixed tick at a time:
## read inputs → tick fighters → resolve hits → age effects.
## Nothing here depends on frame rate or Godot physics, so the same code can run in tests,
## in the client, and on a headless server.

signal combat_event(kind: StringName, info: Dictionary)

const TEXT_GOLD := Color("ffc443")
const TEXT_RED := Color("ff5b5e")

var tick := 0
var solids: Array[Rect2] = []
var one_ways: Array[Rect2] = []
var jump_pads: Array[Vector2] = []  ## centre of each pad, on the floor surface
var grounds: Array[GroundStrip] = []  ## rolling-hill terrain on top of floors
var fighters: Array[Fighter] = []
var monsters: Array[Monster] = []
var minions: Array[Minion] = []
var structures: Array[Structure] = []
var shots: Array[Dictionary] = []  ## homing orbs from towers and ranged minions
var lane: LaneMatch  ## match rules (waves, economy, respawns), when this world is a match
var effects: Array[Dictionary] = []
var training_mode := false  ## fighters can't drop below 1 HP
var debug_draw := false
var shake := 0.0
var auto_tick := true


func add_solid(rect: Rect2, one_way := false) -> void:
	if one_way:
		one_ways.append(rect)
	else:
		solids.append(rect)


func add_fighter(f: Fighter, controller: FighterController) -> void:
	f.world = self
	f.controller = controller
	fighters.append(f)
	if f.get_parent() == null:
		add_child(f)


func add_monster(m: Monster) -> void:
	m.world = self
	monsters.append(m)
	if m.get_parent() == null:
		add_child(m)


func add_minion(m: Minion) -> void:
	m.world = self
	minions.append(m)
	if m.get_parent() == null:
		add_child(m)


func add_structure(s: Structure) -> void:
	s.world = self
	structures.append(s)
	if s.get_parent() == null:
		add_child(s)


func minutes() -> float:
	return tick / float(CombatRules.TICK_RATE * 60)


## True for a living fighter, minion, structure or monster (false for null or freed ones, so it is
## untyped: a freed object can't be passed as a typed argument).
static func alive(n: Variant) -> bool:
	if n == null or not is_instance_valid(n):
		return false
	if n is Fighter:
		return not (n as Fighter).is_ko()
	return n.call(&"is_alive")


func step() -> void:
	tick += 1
	for f in fighters:
		f.read_input()
	for f in fighters:
		f.sim_tick()
	for m in monsters:
		m.sim_tick()
	for s in structures:
		s.sim_tick()
	for m in minions:
		m.sim_tick()
	_tick_shots()
	_resolve_hits()
	_remove_dead_minions()
	if lane != null:
		lane.tick()
	_age_effects()


# ---------------------------------------------------------------- movement

func move_body(f: Fighter) -> void:
	var hw := f.body_size.x * 0.5
	var h := f.body_size.y
	var p := f.position
	var old_x := p.x
	p.x += f.vel.x
	for s in solids:
		if p.x + hw > s.position.x and p.x - hw < s.end.x and p.y > s.position.y + 0.01 and p.y - h < s.end.y:
			if f.vel.x > 0.0:
				p.x = s.position.x - hw
			elif f.vel.x < 0.0:
				p.x = s.end.x + hw
			else:
				p.x = (s.position.x - hw) if p.x < s.get_center().x else (s.end.x + hw)
			f.vel.x = 0.0
	# Terrain cliffs: a rise steeper than a step blocks you sideways (jump over it instead).
	if p.x != old_x:
		for g in grounds:
			if not g.contains(p.x) or p.y > g.base_y + 6.0:
				continue
			if p.y > g.height_at(p.x) + CombatRules.STEP_UP:
				var inside_already := g.contains(old_x) and p.y > g.height_at(old_x) + CombatRules.STEP_UP
				if not inside_already:
					p.x = old_x
					f.vel.x = 0.0
				break
	var prev_y := p.y
	var was_grounded := f.grounded
	p.y += f.vel.y
	f.grounded = false
	f.on_one_way = false
	for s in solids:
		if p.x + hw > s.position.x and p.x - hw < s.end.x and p.y > s.position.y and p.y - h < s.end.y:
			if f.vel.y >= 0.0 and prev_y <= s.position.y + 1.0:
				p.y = s.position.y
				f.vel.y = 0.0
				f.grounded = true
			elif f.vel.y < 0.0:
				p.y = s.end.y + h
				f.vel.y = 0.0
	if f.vel.y >= 0.0 and f.drop_timer <= 0:
		for o in one_ways:
			if p.x > o.position.x - 6.0 and p.x < o.end.x + 6.0 and prev_y <= o.position.y + 0.5 and p.y >= o.position.y:
				p.y = o.position.y
				f.vel.y = 0.0
				f.grounded = true
				f.on_one_way = true
	for g in grounds:
		if not g.contains(p.x) or p.y > g.base_y + 6.0:
			continue
		var gy := g.height_at(p.x)
		if f.vel.y >= 0.0:
			# land, walk uphill, stick to the slope when walking downhill, or get pushed out if inside
			var snap := 14.0 if was_grounded else 0.0
			if p.y >= gy - snap:
				p.y = gy
				f.vel.y = 0.0
				f.grounded = true
				f.on_one_way = false
		elif p.y > gy:
			p.y = gy  # rising inside a hill (e.g. knocked into its side): push out on top
	f.position = p


# ---------------------------------------------------------------- hits

func _resolve_hits() -> void:
	for f in fighters:
		if f.hitstop > 0:
			continue
		var hb := f.active_hitbox()
		if not hb.has_area():
			continue
		var m := f.move
		for t in fighters:
			if f.move != m or f.state != &"attack":
				break
			if t == f or t.team == f.team or f.hit_ids.has(t.get_instance_id()):
				continue
			if not hb.intersects(t.hurtbox()):
				continue
			f.hit_ids[t.get_instance_id()] = true
			apply_hit(f, t, m, f.facing, f.ex)
		for mon in monsters:
			if f.move != m or f.state != &"attack":
				break
			if not mon.is_alive() or f.hit_ids.has(mon.get_instance_id()) or not hb.intersects(mon.hurtbox()):
				continue
			f.hit_ids[mon.get_instance_id()] = true
			_hit_monster(f, mon, m)
		for mn in minions:
			if f.move != m or f.state != &"attack":
				break
			if mn.team == f.team or not mn.is_alive() or f.hit_ids.has(mn.get_instance_id()) or not hb.intersects(mn.hurtbox()):
				continue
			f.hit_ids[mn.get_instance_id()] = true
			_hit_minion(f, mn, m)
		for st in structures:
			if f.move != m or f.state != &"attack":
				break
			if st.team == f.team or not st.is_alive() or f.hit_ids.has(st.get_instance_id()) or not hb.intersects(st.hurtbox()):
				continue
			f.hit_ids[st.get_instance_id()] = true
			_hit_structure(f, st, m)


## Applies one hit from `att` to `tgt`. Returns &"hit", &"block", &"parry" or &"whiff".
func apply_hit(att: Fighter, tgt: Fighter, m: MoveData, dir: int, is_ex := false) -> StringName:
	if tgt.invuln > 0 or tgt.state == &"ko":
		return &"whiff"
	var dmg := m.damage * att.power()
	if is_ex:
		dmg *= 1.5
	var rel := att.position.x - tgt.position.x
	var side := int(signf(rel)) if rel != 0.0 else -dir
	var front := side == tgt.facing
	var defendable := not m.grab and not m.unblockable

	# Parry: Guard tapped just before the hit.
	if defendable and front and tgt.parry_timer > 0 and (tgt.state == &"guard" or tgt.is_actionable()):
		tgt.parry_timer = 0
		tgt.counter_timer = CombatRules.PARRY_REWARD_FRAMES
		tgt.guard = minf(CombatRules.GUARD_MAX, tgt.guard + 25.0)
		if absf(rel) < 220.0:
			att.state = &"hitstun"
			att.state_timer = CombatRules.PARRY_STAGGER
			att.move = null
			att.vel.x = 0.0
			att.hitstop = 10
		tgt.hitstop = 10
		tgt.add_meter(40.0)
		add_text(tgt.position + Vector2(0, -110), "PARRY", TEXT_GOLD, 24)
		add_effect(&"ring", tgt.position + Vector2(tgt.facing * 20, -50), {"radius": 70.0, "life": 12, "color": TEXT_GOLD})
		shake = maxf(shake, 6.0)
		combat_event.emit(&"parry", {"attacker": att, "target": tgt})
		return &"parry"

	# Grabs only catch grounded targets that aren't mid-attack (attacks beat grabs).
	if m.grab:
		if not tgt.grounded:
			return &"whiff"
		if tgt.state == &"attack" and tgt.move != null and tgt.move_frame > tgt.move.startup:
			return &"whiff"

	# Guard: blocks attacks from the front.
	if defendable and front and (tgt.state == &"guard" or tgt.state == &"blockstun"):
		var gd := m.guard_damage if m.guard_damage >= 0.0 else m.damage * 0.5
		tgt.guard -= gd
		tgt.state = &"blockstun"
		tgt.state_timer = maxi(8, roundi(m.hitstun * 0.6))
		tgt.vel.x = dir * maxf(2.0, absf(m.knockback.x) * 0.6)
		if m.kind == MoveData.Kind.SKILL or m.kind == MoveData.Kind.ULT:
			tgt.hp = maxf(1.0, tgt.hp - dmg * 0.15)
		att.connected = true
		att.hitstop = 3
		tgt.hitstop = 3
		tgt.add_meter(gd * 0.3)
		add_effect(&"block", tgt.position + Vector2(tgt.facing * 22, -50), {"life": 10})
		var result := &"block"
		if tgt.guard <= 0.0:
			tgt.guard = 0.0
			tgt.state = &"guardbreak"
			tgt.state_timer = CombatRules.GUARD_BREAK_FRAMES
			tgt.hitstop = 8
			add_text(tgt.position + Vector2(0, -110), "GUARD BREAK", TEXT_RED, 22)
			shake = maxf(shake, 8.0)
			result = &"guard_break"
		combat_event.emit(&"block", {"attacker": att, "target": tgt, "move": m, "result": result})
		return &"block"

	# Clean hit.
	var counter_hit := tgt.state == &"attack" and tgt.move != null and tgt.move_frame <= tgt.move.startup + tgt.move.active
	if counter_hit:
		dmg *= 1.25
	if att.counter_timer > 0:
		dmg *= 1.5
		att.counter_timer = 0
	dmg *= CombatRules.combo_scale(tgt.combo)
	var dealt := roundf(dmg)
	tgt.hp -= dealt
	if training_mode:
		tgt.hp = maxf(1.0, tgt.hp)
	tgt.add_meter(dealt * CombatRules.METER_ON_HURT)
	att.add_meter(dealt * CombatRules.METER_ON_HIT)
	att.connected = true
	tgt.combo += 1
	tgt.combo_damage += dealt
	var stop := m.get_hitstop()
	tgt.hitstop = stop
	att.hitstop = stop
	tgt.move = null
	tgt.parry_timer = 0
	add_text(tgt.position + Vector2(0, -tgt.body_size.y - 10), str(int(dealt)), TEXT_GOLD if counter_hit else Color.WHITE, 16)
	add_effect(&"spark", tgt.position + Vector2(-dir * 6, -50), {"life": 10, "color": att.data.color, "big": stop >= 6})
	if counter_hit:
		add_text(tgt.position + Vector2(0, -128), "COUNTER", TEXT_GOLD, 18)
	if stop >= 6:
		shake = maxf(shake, float(stop))
	_tower_aggro(att, tgt)
	if tgt.hp <= 0.0:
		tgt.knock_out(dir)
		combat_event.emit(&"ko", {"attacker": att, "target": tgt})
		return &"hit"

	var hs := m.hitstun + (8 if counter_hit else 0) + (8 if is_ex else 0)
	var airborne := not tgt.grounded or tgt.state in [&"airhit", &"held", &"tumble"]
	tgt.vel.x = m.knockback.x * dir
	if m.launch or airborne or m.knockback.y <= -7.0 or m.knockdown:
		if m.knockback.y != 0.0:
			tgt.vel.y = m.knockback.y
		else:
			tgt.vel.y = -4.0 if airborne else 0.0
		tgt.state = &"airhit"
		tgt.state_timer = hs
		tgt.grounded = false
		tgt.knock_on_land = m.knockdown
		if m.juggle_cost >= 0:
			tgt.juggle += m.juggle_cost
		elif airborne:
			tgt.juggle += 1
	else:
		tgt.state = &"hitstun"
		tgt.state_timer = hs
		if m.knockback.y != 0.0:
			tgt.vel.y = m.knockback.y
	if tgt.juggle >= CombatRules.JUGGLE_MAX and tgt.state != &"hitstun":
		tgt.state = &"tumble"
		tgt.invuln = 999
		tgt.vel.y = maxf(tgt.vel.y, -3.0)
		add_text(tgt.position + Vector2(0, -120), "DROP", Color("97a3b8"), 16)
	if not att.grounded and att.move != null and m.air:
		# Air hits carry the attacker up with the target so air strings connect;
		# the shared juggle limit keeps this from looping forever.
		att.vel.y = minf(att.vel.y, tgt.vel.y)
		att.vel.x = tgt.vel.x
	combat_event.emit(&"hit", {"attacker": att, "target": tgt, "move": m, "damage": dealt, "counter": counter_hit})
	return &"hit"


func burst_from(f: Fighter) -> void:
	for e in fighters:
		if e.team == f.team or e.state == &"ko" or e.position.distance_to(f.position) > CombatRules.BURST_RADIUS:
			continue
		var d := int(signf(e.position.x - f.position.x))
		if d == 0:
			d = 1
		e.move = null
		e.state = &"airhit"
		e.state_timer = 22
		e.vel = Vector2(d * 11.0, -8.0)
		e.grounded = false
	add_effect(&"ring", f.position + Vector2(0, -40), {"radius": CombatRules.BURST_RADIUS, "life": 18, "color": TEXT_GOLD})
	add_text(f.position + Vector2(0, -110), "BURST", TEXT_GOLD, 24)
	shake = maxf(shake, 10.0)
	combat_event.emit(&"burst", {"fighter": f})


# ---------------------------------------------------------------- monsters

## Ground height at x for something standing near height y: the terrain of the floor just below y
## (hills rise at most ~130 px above a floor's flat level).
func surface_y(x: float, near_y: float) -> float:
	var best: GroundStrip = null
	for g in grounds:
		if g.contains(x) and g.base_y >= near_y - 1.0 and g.base_y - near_y < 200.0 and (best == null or g.base_y < best.base_y):
			best = g
	return best.height_at(x) if best != null else near_y


func _hit_monster(f: Fighter, mon: Monster, m: MoveData) -> void:
	var dmg := roundf(m.damage * f.power() * (1.5 if f.ex else 1.0))
	mon.take_hit(f, dmg, f.facing)
	f.connected = true
	var stop := maxi(2, m.get_hitstop() - 1)
	f.hitstop = stop
	mon.hitstop = stop
	f.add_meter(dmg * 0.12)
	add_text(mon.position + Vector2(0, -mon.body_size().y - 12), str(int(dmg)), Color.WHITE, 16)
	add_effect(&"spark", mon.position + Vector2(-f.facing * 10, -mon.body_size().y * 0.5), {"life": 10, "color": f.data.color, "big": stop >= 5})
	if not mon.is_alive():
		add_text(mon.position + Vector2(0, -mon.body_size().y - 40), mon.display_name().to_upper() + " SLAIN", TEXT_GOLD, 22 if mon.is_boss() else 16)
		add_effect(&"ring", mon.position + Vector2(0, -mon.body_size().y * 0.5), {"radius": mon.body_size().x * 1.4, "life": 20, "color": Color("8affd0")})
		shake = maxf(shake, 10.0 if mon.is_boss() else 4.0)
		combat_event.emit(&"monster_slain", {"monster": mon, "by": f})


## A monster's telegraphed attack lands: everyone inside its attack box gets hit (guard and parry work).
func monster_strike(mon: Monster) -> void:
	var box := mon.attack_box()
	for f in fighters:
		if f.state != &"ko" and f.invuln <= 0 and box.intersects(f.hurtbox()):
			_monster_hits_fighter(mon, f)
	add_effect(&"ring", mon.position + Vector2(0, -12), {"radius": box.size.x * 0.5, "life": 14, "color": Color("ff8a6a")})
	if mon.is_boss():
		shake = maxf(shake, 7.0)


func _monster_hits_fighter(mon: Monster, t: Fighter) -> void:
	var r := env_hit(mon, mon.position.x, t, mon.def["damage"], mon.def["knockback"], mon.def["hitstun"], true)
	if r == &"parry":
		mon.hitstop = 10
		mon.state = &"stagger"
		mon.timer = 70
	elif r == &"hit":
		mon.hitstop = 4
		combat_event.emit(&"monster_hit", {"monster": mon, "target": t})


## A hit on a fighter from the environment (monster, tower): can be guarded from the front, and
## parried if `parryable`. Returns &"parry", &"block", &"hit" or &"whiff".
func env_hit(source: Node2D, from_x: float, t: Fighter, dmg: float, kb: Vector2, hitstun: int, parryable: bool) -> StringName:
	if t.is_ko() or t.invuln > 0:
		return &"whiff"
	var dir := int(signf(t.position.x - from_x))
	if dir == 0:
		dir = 1
	var front := -dir == t.facing
	if parryable and front and t.parry_timer > 0 and (t.state == &"guard" or t.is_actionable()):
		t.parry_timer = 0
		t.counter_timer = CombatRules.PARRY_REWARD_FRAMES
		t.hitstop = 10
		t.add_meter(40.0)
		add_text(t.position + Vector2(0, -110), "PARRY", TEXT_GOLD, 24)
		return &"parry"
	if front and (t.state == &"guard" or t.state == &"blockstun"):
		t.guard -= dmg * 0.6
		t.state = &"blockstun"
		t.state_timer = 14
		t.vel.x = dir * 4.0
		t.hp = maxf(1.0, t.hp - dmg * 0.1)
		t.hitstop = 4
		add_effect(&"block", t.position + Vector2(t.facing * 22, -50), {"life": 10})
		if t.guard <= 0.0:
			t.guard = 0.0
			t.state = &"guardbreak"
			t.state_timer = CombatRules.GUARD_BREAK_FRAMES
			add_text(t.position + Vector2(0, -110), "GUARD BREAK", TEXT_RED, 22)
		return &"block"
	var dealt := roundf(dmg)
	t.hp -= dealt
	if training_mode:
		t.hp = maxf(1.0, t.hp)
	t.move = null
	t.hitstop = 6
	t.vel = Vector2(kb.x * dir, kb.y)
	t.state = &"airhit"
	t.state_timer = hitstun
	t.grounded = false
	t.knock_on_land = false
	t.add_meter(dealt * CombatRules.METER_ON_HURT)
	add_text(t.position + Vector2(0, -t.body_size.y - 10), str(int(dealt)), TEXT_RED, 16)
	add_effect(&"spark", t.position + Vector2(-dir * 6, -50), {"life": 10, "color": Color("ff8a6a"), "big": true})
	if t.hp <= 0.0:
		t.knock_out(dir)
		combat_event.emit(&"ko", {"attacker": source, "target": t})
	return &"hit"


# ---------------------------------------------------------------- lane: minions, structures, shots

func add_shot(source: Node2D, target: Node2D, dmg: float, speed: float, at: Vector2) -> void:
	var tower := source is Structure
	var tc := Color("8fc4ff") if source.get(&"team") == 0 else Color("ff9c9e")
	shots.append({"pos": at, "target": target, "source": source, "damage": dmg, "speed": speed, "tower": tower,
		"color": tc, "size": 9.0 if tower else 5.0, "life": 150, "from_x": at.x})


func _tick_shots() -> void:
	for sh in shots:
		sh["life"] -= 1
		if not alive(sh["target"]):
			sh["life"] = 0
			continue
		var t: Node2D = sh["target"]
		var aim: Vector2 = (t.call(&"hurtbox") as Rect2).get_center()
		var p: Vector2 = sh["pos"]
		var d := aim - p
		var spd: float = sh["speed"]
		if d.length() <= spd + 6.0:
			sh["life"] = 0
			var src: Node2D = sh["source"] if is_instance_valid(sh["source"]) else null
			unit_hits(src, t, sh["damage"], p.x - signf(d.x) * 20.0, sh["tower"])
			add_effect(&"spark", aim, {"life": 8, "color": sh["color"], "big": sh["tower"]})
		else:
			sh["pos"] = p + d.normalized() * spd
	shots = shots.filter(func(sh: Dictionary) -> bool: return sh["life"] > 0)


## Damage from a minion or tower (melee strike or orb) to anything.
func unit_hits(source: Node2D, t: Node2D, dmg: float, from_x := INF, tower := false) -> void:
	if from_x == INF:
		from_x = source.position.x if source != null else t.position.x
	if t is Minion:
		damage_minion(t, dmg, source, int(signf(t.position.x - from_x)))
	elif t is Structure:
		damage_structure(t, dmg, source)
	elif t is Fighter:
		var f := t as Fighter
		if tower:
			env_hit(source, from_x, f, dmg, Vector2(2, -2), 14, false)
			return
		# minions chip fighters but never interrupt them; guard soaks most of it
		if f.is_ko() or f.invuln > 0:
			return
		var front := int(signf(from_x - f.position.x)) == f.facing
		if front and (f.state == &"guard" or f.state == &"blockstun"):
			dmg *= 0.25
			f.guard = maxf(0.0, f.guard - 4.0)
		var dealt := roundf(dmg)
		f.hp -= dealt
		if training_mode:
			f.hp = maxf(1.0, f.hp)
		f.flash = 4
		add_text(f.position + Vector2(0, -f.body_size.y - 10), str(int(dealt)), TEXT_RED, 13)
		if f.hp <= 0.0:
			f.knock_out(int(signf(f.position.x - from_x)))
			combat_event.emit(&"ko", {"attacker": source, "target": f})


func damage_minion(mn: Minion, dmg: float, by: Node2D, dir := 0) -> void:
	if not mn.is_alive():
		return
	mn.take_damage(dmg, by, dir)
	if not mn.is_alive():
		add_effect(&"puff", mn.position + Vector2(0, -mn.body_size().y * 0.5), {"life": 18, "color": Color("4ea4ff") if mn.team == 0 else Color("ff5b5e")})
		combat_event.emit(&"minion_slain", {"minion": mn, "by": by})


func damage_structure(st: Structure, dmg: float, by: Node2D) -> void:
	if not st.is_alive() or not st.vulnerable():
		return
	st.take_damage(dmg)
	if not st.is_alive():
		add_text(st.position + Vector2(0, -st.body_size().y - 30), st.display_name().to_upper() + " DESTROYED", TEXT_GOLD, 24)
		add_effect(&"ring", st.position + Vector2(0, -st.body_size().y * 0.5), {"radius": 220.0, "life": 26, "color": Color("ffc443")})
		add_effect(&"puff", st.position + Vector2(0, -st.body_size().y * 0.4), {"life": 30, "color": Color("9aa3b5"), "big": true})
		shake = maxf(shake, 14.0)
		combat_event.emit(&"structure_destroyed", {"structure": st, "by": by})


func _hit_minion(f: Fighter, mn: Minion, m: MoveData) -> void:
	var dmg := roundf(m.damage * f.power() * (1.5 if f.ex else 1.0))
	f.connected = true
	f.hitstop = maxi(f.hitstop, 2)
	f.add_meter(dmg * 0.05)
	add_text(mn.position + Vector2(0, -mn.body_size().y - 12), str(int(dmg)), Color.WHITE, 14)
	add_effect(&"spark", mn.position + Vector2(-f.facing * 6, -mn.body_size().y * 0.5), {"life": 8, "color": f.data.color, "big": false})
	damage_minion(mn, dmg, f, f.facing)


func _hit_structure(f: Fighter, st: Structure, m: MoveData) -> void:
	f.connected = true
	f.hitstop = maxi(f.hitstop, 3)
	var at := Vector2(f.position.x + f.facing * 30.0, f.position.y - 50.0)
	if not st.vulnerable():
		add_effect(&"block", at, {"life": 10})
		if st.flash == 0:
			add_text(st.position + Vector2(0, -st.body_size().y * 0.5), "SEALED", Color("aab3c2"), 15)
		st.flash = 6
		return
	var dmg := m.damage * f.power() * (1.5 if f.ex else 1.0)
	var supported := minions.any(func(mn: Minion) -> bool:
		return mn.team == f.team and mn.is_alive() and absf(mn.position.x - st.position.x) < CombatRules.BACKDOOR_RADIUS)
	if not supported:
		dmg *= CombatRules.BACKDOOR_MULT
	dmg = roundf(dmg)
	f.add_meter(dmg * 0.05)
	add_text(st.position + Vector2(f.facing * -10, -st.body_size().y * 0.6), str(int(dmg)), Color.WHITE if supported else Color("aab3c2"), 16)
	add_effect(&"spark", at, {"life": 10, "color": f.data.color, "big": m.get_hitstop() >= 6})
	damage_structure(st, dmg, f)


## A tower targets an enemy fighter who hits one of its team's fighters in its range.
func _tower_aggro(att: Fighter, victim: Fighter) -> void:
	for st in structures:
		if st.team == victim.team and st.is_alive() and st.shoots() and st.in_range(att):
			st.aggro = att
			st.aggro_timer = CombatRules.TOWER_AGGRO_FRAMES


func _remove_dead_minions() -> void:
	if minions.all(func(mn: Minion) -> bool: return mn.is_alive()):
		return
	for mn in minions:
		if not mn.is_alive():
			mn.queue_free()
	minions = minions.filter(func(mn: Minion) -> bool: return mn.is_alive())


# ---------------------------------------------------------------- effects (visual only)

func add_effect(kind: StringName, at: Vector2, extra := {}) -> void:
	var e := {"kind": kind, "pos": at, "t": 0, "life": 12}
	e.merge(extra, true)
	effects.append(e)


func add_text(at: Vector2, text: String, color: Color, size := 16) -> void:
	add_effect(&"text", at, {"text": text, "color": color, "size": size, "life": 50})


func _age_effects() -> void:
	for e in effects:
		e["t"] += 1
		if e["kind"] == &"text":
			e["pos"] += Vector2(0, -0.6)
	effects = effects.filter(func(e: Dictionary) -> bool: return e["t"] < e["life"])
	if effects.size() > 120:
		effects = effects.slice(effects.size() - 120)
	shake = shake * 0.85 if shake > 0.3 else 0.0
