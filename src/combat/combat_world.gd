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


func step() -> void:
	tick += 1
	for f in fighters:
		f.read_input()
	for f in fighters:
		f.sim_tick()
	_resolve_hits()
	_age_effects()


# ---------------------------------------------------------------- movement

func move_body(f: Fighter) -> void:
	var hw := f.body_size.x * 0.5
	var h := f.body_size.y
	var p := f.position
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


## Applies one hit from `att` to `tgt`. Returns &"hit", &"block", &"parry" or &"whiff".
func apply_hit(att: Fighter, tgt: Fighter, m: MoveData, dir: int, is_ex := false) -> StringName:
	if tgt.invuln > 0 or tgt.state == &"ko":
		return &"whiff"
	var dmg := m.damage * att.data.damage_mult
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
