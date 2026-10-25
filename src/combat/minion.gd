class_name Minion
extends Node2D
## A lane minion: walks toward the enemy base, fights the nearest enemy minion, then structures, then
## fighters who come close. Melee minions hit directly, ranged ones throw homing orbs.
## Part of the deterministic simulation (ticked by CombatWorld); drawing only reads its state.

enum Kind { MELEE, RANGED, SUPER }

const DEFS := {
	Kind.MELEE: {"name": "Husk", "hp": 280.0, "damage": 20.0, "range": 46.0, "cooldown": 50, "speed": 2.2,
		"size": Vector2(26, 38), "gold": 20, "xp": 30.0},
	Kind.RANGED: {"name": "Lanternling", "hp": 200.0, "damage": 18.0, "range": 250.0, "cooldown": 60, "speed": 2.2,
		"size": Vector2(24, 34), "gold": 17, "xp": 26.0},
	Kind.SUPER: {"name": "Husk Brute", "hp": 950.0, "damage": 48.0, "range": 56.0, "cooldown": 55, "speed": 2.0,
		"size": Vector2(40, 54), "gold": 45, "xp": 60.0},
}
const WINDUP := 12
const MINION_SIGHT := 260.0
const FIGHTER_SIGHT := 170.0
const HURT_HEIGHT := 64.0

var kind := Kind.MELEE
var def: Dictionary
var team := 0
var world: CombatWorld
var id := 0
var hp := 0.0
var max_hp := 0.0
var damage := 0.0
var empowered := false
var facing := 1
var target: Node2D
var windup := 0
var cooldown := 20
var knock := 0.0
var flash := 0
var anim := 0
var last_fighter: Fighter  ## who hit it last (last-hit gold)


func setup(minion_kind: Kind, team_id: int, at: Vector2, minutes: float, is_empowered := false) -> void:
	kind = minion_kind
	def = DEFS[kind]
	team = team_id
	position = at
	empowered = is_empowered
	var em := 1.6 if empowered else 1.0
	max_hp = float(def["hp"]) * (1.0 + 0.07 * minutes) * em
	hp = max_hp
	damage = float(def["damage"]) * (1.0 + 0.05 * minutes) * em
	facing = march_dir()


func march_dir() -> int:
	return 1 if team == 0 else -1


func is_alive() -> bool:
	return hp > 0.0


func body_size() -> Vector2:
	var s: Vector2 = def["size"]
	return s * 1.2 if empowered else s


## Taller than the body so a fighter's standing attacks (chest height) connect on these small bugs.
func hurtbox() -> Rect2:
	var s := body_size()
	var h := maxf(s.y, HURT_HEIGHT)
	return Rect2(position.x - s.x * 0.5 - 4.0, position.y - h, s.x + 8.0, h)


func sim_tick() -> void:
	anim += 1
	flash = maxi(0, flash - 1)
	if knock != 0.0:
		position.x += knock
		knock *= 0.78
		if absf(knock) < 0.2:
			knock = 0.0
	cooldown = maxi(0, cooldown - 1)
	if (world.tick + id) % 10 == 0 or not CombatWorld.alive(target):
		target = _pick_target()
	var t: Node2D = target if CombatWorld.alive(target) else null
	if windup > 0:
		windup -= 1
		if windup == 0 and t != null:
			_strike(t)
	elif t != null:
		var dx := t.position.x - position.x
		if dx != 0.0:
			facing = int(signf(dx))
		var reach: float = def["range"]
		if t is Structure:
			reach += (t as Structure).body_size().x * 0.5
		if absf(dx) > reach:
			position.x += signf(dx) * float(def["speed"])
		elif cooldown <= 0:
			windup = WINDUP
			cooldown = def["cooldown"]
	else:
		facing = march_dir()
		position.x += facing * float(def["speed"])
	position.x = clampf(position.x, 20.0, RiftLayout.WORLD_W - 20.0)
	var gy := world.surface_y(position.x, RiftLayout.FLOORS[RiftLayout.band_of(position.y)])
	# climb terrain smoothly instead of popping up cliffs; drop down with a little fall
	position.y = move_toward(position.y, gy, 9.0 if gy < position.y else 12.0)
	if is_inside_tree():
		queue_redraw()


func _pick_target() -> Node2D:
	var best: Node2D = null
	var bd := MINION_SIGHT
	for m in world.minions:
		if m.team != team and m.is_alive() and absf(m.position.y - position.y) < 160.0:
			var d := absf(m.position.x - position.x)
			if d < bd:
				bd = d
				best = m
	if best != null:
		return best
	bd = MINION_SIGHT
	for s in world.structures:
		if s.team != team and s.is_alive():
			var d := absf(s.position.x - position.x) - s.body_size().x * 0.5
			if d < bd and absf(s.position.y - position.y) < 200.0:
				bd = d
				best = s
	if best != null:
		return best
	bd = FIGHTER_SIGHT
	for f in world.fighters:
		if f.team != team and not f.is_ko() and absf(f.position.y - position.y) < 140.0:
			var d := absf(f.position.x - position.x)
			if d < bd:
				bd = d
				best = f
	return best


func _strike(t: Node2D) -> void:
	if kind == Kind.RANGED:
		world.add_shot(self, t, damage, 8.0, Vector2(position.x + facing * 12.0, position.y - body_size().y * 0.7))
	else:
		world.unit_hits(self, t, damage * (1.6 if t is Structure else 1.0))


## Called by the world when anything damages it.
func take_damage(amount: float, by: Node2D, dir := 0) -> void:
	hp -= amount
	flash = 6
	if by is Fighter:
		last_fighter = by
		knock = dir * 3.0
		cooldown += 6


# ---------------------------------------------------------------- drawing: small husk bugs in team colours

const SHELL := Color("1a1d27")
const MASK := Color("e6e0d2")


func _draw() -> void:
	var s := body_size()
	var tc := Color("4ea4ff") if team == 0 else Color("ff5b5e")
	var tint := Color(1.7, 1.7, 1.7) if flash > 0 else Color(1, 1, 1)
	var walk := windup == 0 and knock == 0.0
	var bob := absf(sin(anim * 0.22 + id)) * 2.5 if walk else 0.0
	var lunge := 0.0
	if windup > 0:
		lunge = -facing * 3.0 if windup > 4 else facing * 7.0
	_ellipse(Vector2(0, 0), Vector2(s.x * 0.55, 3.5), Color(0, 0, 0, 0.3))
	for k in 2:  # legs
		var lx := (k - 0.5) * s.x * 0.4
		var swing := sin(anim * 0.3 + k * PI + id) * 4.0 if walk else 0.0
		draw_line(Vector2(lx + lunge * 0.3, -s.y * 0.3), Vector2(lx + swing, 0), Color("0b0d12"), 3.0)
	var body := Vector2(lunge, -s.y * 0.48 - bob)
	_ellipse(body, Vector2(s.x * 0.5, s.y * 0.36), SHELL * tint)
	draw_line(body + Vector2(-s.x * 0.45, s.y * 0.2), body + Vector2(s.x * 0.45, s.y * 0.2), Color(tc, 0.85), 3.0)  # team hem
	var head := body + Vector2(facing * s.x * 0.12, -s.y * 0.32)
	var hr := Vector2(s.x * 0.34, s.y * 0.22)
	if kind == Kind.SUPER:
		for side: float in [-1.0, 1.0]:
			var b := head + Vector2(side * hr.x * 0.6, -hr.y * 0.5)
			draw_colored_polygon(PackedVector2Array([b + Vector2(-3, 2), b + Vector2(3, 2), b + Vector2(side * 10, -16)]), MASK * tint)
	var mask_col := MASK * tint
	if windup > 0:
		mask_col = mask_col.lerp(tc, 0.35)
	_ellipse(head, hr, mask_col)
	for side: float in [-1.0, 1.0]:
		_ellipse(head + Vector2(side * hr.x * 0.4 + facing * 2.0, hr.y * 0.1), Vector2(hr.x * 0.18, hr.y * 0.38), Color("0b0d14"))
	match kind:
		Kind.RANGED:  # a staff with a glowing lantern orb
			var hand := body + Vector2(facing * s.x * 0.45, -2)
			draw_line(hand + Vector2(0, 10), hand + Vector2(facing * 4, -s.y * 0.55), Color("3a3026"), 2.0)
			var orb := hand + Vector2(facing * 4, -s.y * 0.6)
			draw_circle(orb, 7.0, Color(tc, 0.25))
			draw_circle(orb, 3.5 + (2.0 if windup > 0 else 0.0), tc.lightened(0.4))
		_:  # a little nail
			var hand := body + Vector2(facing * s.x * 0.4, 2)
			var tip := hand + Vector2(facing * (s.x * 0.5 + (10.0 if windup > 0 and windup <= 4 else 0.0)), -6.0 if windup > 4 else 0.0)
			draw_line(hand, tip, Color("d9dde6"), 2.5 if kind == Kind.SUPER else 2.0)
	if empowered:
		draw_arc(body, s.x * 0.62, 0, TAU, 20, Color("ffc443", 0.5), 1.5)
	if hp < max_hp:
		var bw := s.x + 6.0
		draw_rect(Rect2(-bw * 0.5, -s.y - 10, bw, 4), Color(0, 0, 0, 0.65))
		draw_rect(Rect2(-bw * 0.5, -s.y - 10, bw * clampf(hp / max_hp, 0.0, 1.0), 4), tc.lightened(0.15))


func _ellipse(c: Vector2, r: Vector2, color: Color) -> void:
	var pts := PackedVector2Array()
	for k in 16:
		var a := TAU * k / 16.0
		pts.append(c + Vector2(cos(a) * r.x, sin(a) * r.y))
	draw_colored_polygon(pts, color)
