class_name Structure
extends Node2D
## A lane structure: outer tower → inner tower → gate → core, one chain per team. Each one is sealed
## (takes no damage) until the one in front of it falls. Towers and the core shoot homing orbs: enemy
## minions first, then fighters — but a fighter who hits one of the team's fighters in range draws aggro.
## Destroying the enemy core wins the match. Part of the simulation; drawing only reads its state.

enum Kind { OUTER, INNER, GATE, CORE }

const DEFS := {
	Kind.OUTER: {"name": "Outer Tower", "hp": 1700.0, "size": Vector2(64, 176), "shoots": true, "range": 450.0, "rate": 70, "gold": 150, "xp": 100.0},
	Kind.INNER: {"name": "Inner Tower", "hp": 1900.0, "size": Vector2(64, 186), "shoots": true, "range": 450.0, "rate": 70, "gold": 150, "xp": 100.0},
	Kind.GATE: {"name": "Gate", "hp": 2000.0, "size": Vector2(96, 200), "shoots": false, "range": 0.0, "rate": 0, "gold": 100, "xp": 120.0},
	Kind.CORE: {"name": "Core", "hp": 3400.0, "size": Vector2(110, 190), "shoots": true, "range": 520.0, "rate": 50, "gold": 0, "xp": 0.0},
}

var kind := Kind.OUTER
var def: Dictionary
var team := 0
var world: CombatWorld
var guards: Structure  ## must fall before this one can be damaged
var hp := 0.0
var max_hp := 0.0
var cooldown := 30
var aggro: Fighter
var aggro_timer := 0
var aiming_at: Fighter  ## the fighter it is shooting at, if any (drawn as a warning line)
var has_target := false  ## visual: the crystal charges up between shots
var flash := 0
var anim := 0


func setup(structure_kind: Kind, team_id: int, at: Vector2, protected_by: Structure) -> void:
	kind = structure_kind
	def = DEFS[kind]
	team = team_id
	position = at
	guards = protected_by
	max_hp = def["hp"]
	hp = max_hp


func display_name() -> String:
	return def["name"]


func is_alive() -> bool:
	return hp > 0.0


func vulnerable() -> bool:
	return guards == null or not guards.is_alive()


func shoots() -> bool:
	return def["shoots"]


func body_size() -> Vector2:
	return def["size"]


func hurtbox() -> Rect2:
	var s := body_size()
	return Rect2(position.x - s.x * 0.5, position.y - s.y, s.x, s.y)


func in_range(n: Node2D) -> bool:
	return absf(n.position.x - position.x) < float(def["range"]) and absf(n.position.y - position.y) < 320.0


## Where its orbs come from.
func muzzle() -> Vector2:
	return position + Vector2(0, -body_size().y + (60.0 if kind == Kind.CORE else 18.0))


func sim_tick() -> void:
	anim += 1
	flash = maxi(0, flash - 1)
	if not is_alive() or not shoots():
		aiming_at = null
		has_target = false
		return
	if aggro_timer > 0:
		aggro_timer -= 1
		if aggro_timer == 0:
			aggro = null
	var t := _pick_target()
	aiming_at = t as Fighter
	has_target = t != null
	cooldown = maxi(0, cooldown - 1)
	if t == null or cooldown > 0:
		return
	var dmg := 85.0
	if t is Fighter:
		dmg = 115.0 * (1.0 + 0.06 * world.minutes())
	world.add_shot(self, t, dmg, 9.0, muzzle())
	cooldown = def["rate"]


func _pick_target() -> Node2D:
	if aggro != null and not aggro.is_ko() and in_range(aggro):
		return aggro
	var best: Node2D = null
	var bd := INF
	for m in world.minions:
		if m.team != team and m.is_alive() and in_range(m) and absf(m.position.x - position.x) < bd:
			bd = absf(m.position.x - position.x)
			best = m
	if best != null:
		return best
	for f in world.fighters:
		if f.team != team and not f.is_ko() and f.invuln < 900 and in_range(f) and absf(f.position.x - position.x) < bd:
			bd = absf(f.position.x - position.x)
			best = f
	return best


func take_damage(amount: float) -> void:
	hp = maxf(0.0, hp - amount)
	flash = 6


# ---------------------------------------------------------------- drawing
# Bone-and-stone spires holding a team-coloured lantern crystal, a horned gate arch with a banner,
# and a floating core crystal. Destroyed structures leave rubble.

const STONE := Color("1a1f2b")
const STONE_LIT := Color("2b3344")
const BONE := Color("e2dccb")


func _draw() -> void:
	var tc := Color("4ea4ff") if team == 0 else Color("ff5b5e")
	var s := body_size()
	var tint := Color(1.5, 1.5, 1.5) if flash > 0 else Color(1, 1, 1)
	var t := float(anim)
	_draw_range(tc)
	match kind:
		Kind.OUTER, Kind.INNER:
			_draw_tower(s, tc, tint, t)
		Kind.GATE:
			_draw_gate(s, tc, tint, t)
		Kind.CORE:
			_draw_core(s, tc, tint, t)
	if is_alive():
		_draw_hp(s, tc)
	if aiming_at != null and is_alive():  # warning line at the fighter it's targeting
		var from := muzzle() - position
		var to := aiming_at.position + Vector2(0, -45) - position
		draw_line(from, to, Color(tc.lightened(0.3), 0.35 + 0.25 * sin(t * 0.3)), 2.0)


func _draw_range(tc: Color) -> void:
	if not is_alive() or not shoots():
		return
	var near := false
	for f in world.fighters:
		if f.team != team and not f.is_ko() and absf(f.position.x - position.x) < float(def["range"]) + 200.0 and absf(f.position.y - position.y) < 320.0:
			near = true
	if not near:
		return
	var r: float = def["range"]
	var pts := PackedVector2Array()
	var x := -r
	while x <= r:
		pts.append(Vector2(x, world.surface_y(position.x + x, position.y - 140.0) - position.y - 2.0))
		x += 24.0
	draw_polyline(pts, Color(tc, 0.28), 3.0)
	for side: float in [-1.0, 1.0]:
		var gy := world.surface_y(position.x + side * r, position.y - 140.0) - position.y
		draw_line(Vector2(side * r, gy), Vector2(side * r, gy - 40.0), Color(tc, 0.5), 2.0)


func _draw_tower(s: Vector2, tc: Color, tint: Color, t: float) -> void:
	var h := s.y
	# plinth
	draw_colored_polygon(PackedVector2Array([Vector2(-40, 0), Vector2(40, 0), Vector2(32, -16), Vector2(-32, -16)]), STONE.darkened(0.3) * tint)
	if not is_alive():
		_rubble(Vector2(0, -16), 46.0, tc)
		draw_colored_polygon(PackedVector2Array([Vector2(-22, -16), Vector2(22, -16), Vector2(18, -h * 0.32), Vector2(4, -h * 0.26),
			Vector2(-6, -h * 0.38), Vector2(-20, -h * 0.3)]), STONE * tint)
		return
	# tapered shaft with carved rings
	draw_colored_polygon(PackedVector2Array([Vector2(-22, -16), Vector2(22, -16), Vector2(15, -h + 44), Vector2(-15, -h + 44)]), STONE * tint)
	draw_line(Vector2(-22, -16), Vector2(-15, -h + 44), Color(STONE_LIT, 0.8), 2.0)
	for k in 4:
		var y := -30.0 - k * (h - 80.0) / 4.0
		var w := lerpf(22.0, 15.0, (-y - 16.0) / (h - 60.0))
		draw_line(Vector2(-w, y), Vector2(w, y), STONE_LIT * tint, 3.0)
		draw_circle(Vector2(0, y - 12), 2.0, Color(tc, 0.5))
	# bone horns cradling the lantern crystal
	var top := Vector2(0, -h + 44)
	for side: float in [-1.0, 1.0]:
		draw_colored_polygon(PackedVector2Array([top + Vector2(side * 6, 2), top + Vector2(side * 18, 0), top + Vector2(side * 30, -26),
			top + Vector2(side * 24, -50), top + Vector2(side * 20, -26)]), BONE * tint)
	var charge := 1.0 - clampf(float(cooldown) / 20.0, 0.0, 1.0) if has_target else 0.0
	var c := top + Vector2(0, -22 + sin(t * 0.04) * 2.0)
	Painter.glow(self, c, 60.0 + 20.0 * charge, Color(tc, 0.45 + 0.3 * charge))
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -18), c + Vector2(11, 0), c + Vector2(0, 18), c + Vector2(-11, 0)]), tc.lightened(0.15) * tint)
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -18), c + Vector2(11, 0), c + Vector2(0, 2)]), tc.lightened(0.55))
	if kind == Kind.INNER:  # inner towers wear a second crest
		draw_arc(top + Vector2(0, -4), 26.0, PI * 1.1, PI * 1.9, 12, BONE * tint, 3.0)


func _draw_gate(s: Vector2, tc: Color, tint: Color, t: float) -> void:
	var h := s.y
	var hw := s.x * 0.5
	for side: float in [-1.0, 1.0]:  # pillars
		var ph := h if is_alive() else h * (0.45 if side < 0 else 0.3)
		draw_rect(Rect2(side * hw - 12, -ph, 24, ph), STONE * tint)
		draw_line(Vector2(side * hw - 12, 0), Vector2(side * hw - 12, -ph), Color(STONE_LIT, 0.8), 2.0)
		draw_rect(Rect2(side * hw - 16, -ph - 8, 32, 10), STONE_LIT * tint)
	if not is_alive():
		_rubble(Vector2(0, 0), hw + 20.0, tc)
		return
	draw_arc(Vector2(0, -h + 6), hw, PI, TAU, 24, BONE * tint, 9.0)  # bone arch with horns
	for side: float in [-1.0, 1.0]:
		var b := Vector2(side * hw * 0.55, -h - hw * 0.75)
		draw_colored_polygon(PackedVector2Array([b + Vector2(-4, 4), b + Vector2(4, 4), b + Vector2(side * 16, -26)]), BONE * tint)
	# banner swaying under the arch
	var sway := sin(t * 0.04) * 5.0
	var top := -h + 20.0
	draw_colored_polygon(PackedVector2Array([Vector2(-26, top), Vector2(26, top), Vector2(24 + sway, top + 110), Vector2(sway, top + 92),
		Vector2(-24 + sway, top + 110)]), tc.darkened(0.45) * tint)
	draw_line(Vector2(-28, top), Vector2(28, top), Color("3a3026"), 4.0)
	var seal := Vector2(sway * 0.5, top + 46)
	draw_arc(seal, 13.0, 0, TAU, 20, tc.lightened(0.3), 2.0)
	draw_colored_polygon(PackedVector2Array([seal + Vector2(0, -8), seal + Vector2(6, 0), seal + Vector2(0, 8), seal + Vector2(-6, 0)]), tc.lightened(0.3))


func _draw_core(s: Vector2, tc: Color, tint: Color, t: float) -> void:
	draw_colored_polygon(PackedVector2Array([Vector2(-58, 0), Vector2(58, 0), Vector2(44, -22), Vector2(-44, -22)]), STONE * tint)
	draw_line(Vector2(-44, -22), Vector2(44, -22), BONE * tint, 3.0)
	if not is_alive():
		_rubble(Vector2(0, -22), 60.0, tc)
		for k in 4:
			var p := Vector2((k - 1.5) * 26.0, -30.0 - (k % 2) * 6.0)
			draw_colored_polygon(PackedVector2Array([p + Vector2(0, -12), p + Vector2(6, 0), p + Vector2(0, 6), p + Vector2(-6, 0)]), Color(tc.darkened(0.5), 0.9))
		return
	var c := Vector2(0, -s.y * 0.55 + sin(t * 0.03) * 5.0)
	Painter.glow(self, c, 150.0, Color(tc, 0.4))
	Painter.glow(self, c, 60.0, Color(1, 1, 1, 0.35))
	var hk := 0.7 + 0.3 * hp / max_hp  # the crystal dims as it cracks
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -70), c + Vector2(34, -8), c + Vector2(0, 56), c + Vector2(-34, -8)]), tc.darkened(0.1) * tint * Color(hk, hk, hk))
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -70), c + Vector2(34, -8), c + Vector2(0, 2)]), tc.lightened(0.5))
	if hp < max_hp * 0.66:
		draw_polyline(PackedVector2Array([c + Vector2(-10, -40), c + Vector2(2, -18), c + Vector2(-6, 4), c + Vector2(8, 30)]), Color(0, 0, 0, 0.6), 2.0)
	for k in 3:  # orbiting shards
		var a := t * 0.02 + TAU * k / 3.0
		var p := c + Vector2(cos(a) * 62.0, sin(a) * 16.0)
		draw_colored_polygon(PackedVector2Array([p + Vector2(0, -9), p + Vector2(5, 0), p + Vector2(0, 9), p + Vector2(-5, 0)]), Color(tc.lightened(0.3), 0.9))


func _rubble(at: Vector2, w: float, tc: Color) -> void:
	for k in 7:
		var x := at.x - w + (2.0 * w) * k / 6.0
		var r := 6.0 + float((k * 7) % 5) * 2.0
		draw_circle(Vector2(x, at.y - r * 0.4), r, STONE_LIT.darkened(0.2 + 0.1 * (k % 3)))
	draw_line(Vector2(at.x - w * 0.6, at.y - 4), Vector2(at.x + w * 0.5, at.y - 6), Color(tc, 0.35), 2.0)


func _draw_hp(s: Vector2, tc: Color) -> void:
	var bw := maxf(80.0, s.x + 20.0)
	var y := -s.y - (90.0 if kind == Kind.CORE else 66.0 if kind != Kind.GATE else 48.0)
	draw_rect(Rect2(-bw * 0.5 - 1, y - 1, bw + 2, 8), Color(0, 0, 0, 0.75))
	var col := tc if vulnerable() else Color(0.55, 0.58, 0.64)
	draw_rect(Rect2(-bw * 0.5, y, bw * hp / max_hp, 6), col)
	if not vulnerable():  # sealed: a little lock-ring
		var c := Vector2(bw * 0.5 + 10, y + 3)
		draw_arc(c, 6.0, 0, TAU, 14, Color(0.8, 0.82, 0.86), 2.0)
		draw_line(c + Vector2(-3, 0), c + Vector2(3, 0), Color(0.8, 0.82, 0.86), 2.0)
