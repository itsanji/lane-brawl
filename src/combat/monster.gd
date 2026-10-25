class_name Monster
extends Node2D
## A jungle monster: wanders near home, fights back when hit, telegraphs every attack (guard, parry or
## dodge it), gives up and heals if pulled too far from home (leash), and respawns after dying.
## Part of the deterministic simulation (ticked by CombatWorld); drawing only reads its state.

enum Kind { CAMP, WYRM, TITAN }

const DEFS := {
	Kind.CAMP: {"name": "Mossback", "hp": 700.0, "size": Vector2(72, 48), "damage": 34.0, "reach": 70.0,
		"windup": 30, "recover": 36, "cooldown": 60, "speed": 1.7, "leash": 380.0, "respawn": 45.0,
		"knockback": Vector2(6, -6), "hitstun": 20, "wander": 30.0, "light": true, "both_sides": false},
	Kind.WYRM: {"name": "Lumen Wyrm", "hp": 3200.0, "size": Vector2(160, 90), "damage": 70.0, "reach": 150.0,
		"windup": 40, "recover": 50, "cooldown": 90, "speed": 1.1, "leash": 520.0, "respawn": 150.0,
		"knockback": Vector2(9, -9), "hitstun": 26, "wander": 20.0, "light": false, "both_sides": true},
	Kind.TITAN: {"name": "Hollow Titan", "hp": 6000.0, "size": Vector2(130, 170), "damage": 105.0, "reach": 190.0,
		"windup": 48, "recover": 60, "cooldown": 110, "speed": 0.8, "leash": 520.0, "respawn": 180.0,
		"knockback": Vector2(11, -10), "hitstun": 30, "wander": 10.0, "light": false, "both_sides": true},
}

var kind := Kind.CAMP
var def: Dictionary
var world: CombatWorld
var home := Vector2.ZERO
var hp := 0.0
var max_hp := 0.0
var state: StringName = &"idle"   ## idle, chase, windup, recover, stagger, return, dead
var timer := 0
var cooldown := 0
var facing := -1
var target: Fighter
var hitstop := 0
var flash := 0
var anim := 0


func setup(monster_kind: Kind, at: Vector2) -> void:
	kind = monster_kind
	def = DEFS[kind]
	home = at
	position = at
	max_hp = def["hp"]
	hp = max_hp
	facing = -1 if at.x > RiftLayout.WORLD_W * 0.5 else 1


func display_name() -> String:
	return def["name"]


func is_alive() -> bool:
	return state != &"dead"


func is_boss() -> bool:
	return kind != Kind.CAMP


func body_size() -> Vector2:
	return def["size"]


func hurtbox() -> Rect2:
	var s := body_size()
	return Rect2(position.x - s.x * 0.5, position.y - s.y, s.x, s.y)


## Where the next attack lands: in front for camps, both sides for the bosses' sweeps and slams.
func attack_box() -> Rect2:
	var s := body_size()
	var reach: float = def["reach"]
	if def["both_sides"]:
		return Rect2(position.x - s.x * 0.5 - reach, position.y - s.y - 40.0, s.x + reach * 2.0, s.y + 40.0)
	var front := position.x + facing * s.x * 0.5
	return Rect2(front if facing > 0 else front - reach, position.y - s.y * 0.9, reach, s.y * 0.9)


func sim_tick() -> void:
	anim += 1
	if hitstop > 0:
		hitstop -= 1
		return
	flash = maxi(0, flash - 1)
	cooldown = maxi(0, cooldown - 1)
	match state:
		&"dead":
			timer -= 1
			if timer <= 0:
				hp = max_hp
				position = home
				state = &"idle"
				target = null
		&"idle":
			hp = minf(max_hp, hp + max_hp * 0.004)
			position.x = home.x + sin(anim * 0.012 + home.x) * float(def["wander"])
		&"chase":
			if not _target_valid():
				state = &"return"
				target = null
			else:
				var dx := target.position.x - position.x
				if dx != 0.0:
					facing = int(signf(dx))
				var reach_x: float = float(def["reach"]) * 0.75 + body_size().x * 0.5
				if absf(dx) > reach_x:
					_walk(signf(dx) * float(def["speed"]))
				elif cooldown <= 0:
					state = &"windup"
					timer = def["windup"]
		&"windup":
			timer -= 1
			if timer <= 0:
				cooldown = def["cooldown"]
				world.monster_strike(self)
				if state == &"windup":  # a parry may have staggered us during the strike
					state = &"recover"
					timer = def["recover"]
		&"recover", &"stagger":
			timer -= 1
			if timer <= 0:
				state = &"chase"
		&"return":
			hp = minf(max_hp, hp + max_hp * 0.01)
			var dx := home.x - position.x
			if absf(dx) < 4.0:
				state = &"idle"
			else:
				facing = int(signf(dx))
				position.x += signf(dx) * minf(absf(dx), float(def["speed"]) * 1.6)
	position.y = world.surface_y(position.x, home.y)
	if is_inside_tree():
		queue_redraw()


func _walk(v: float) -> void:
	var nx := position.x + v
	if absf(nx - home.x) <= float(def["leash"]):
		position.x = nx


func _target_valid() -> bool:
	return target != null and target.state != &"ko" and absf(target.position.x - home.x) < float(def["leash"]) + 120.0 \
		and absf(target.position.y - position.y) < 260.0


## Called by the world when a fighter's attack connects.
func take_hit(att: Fighter, dmg: float, dir: int) -> void:
	hp -= dmg
	flash = 8
	target = att
	if state == &"idle" or state == &"return":
		state = &"chase"
	if def["light"] and state != &"windup":
		_walk(dir * 6.0)
	if hp <= 0.0:
		hp = 0.0
		state = &"dead"
		timer = int(float(def["respawn"]) * CombatRules.TICK_RATE)
		target = null


# ---------------------------------------------------------------- drawing (Hollow Knight-like bugs)

const MASK := Color("e9e4d6")
const SHELL := Color("14211c")
const BIO := Color("5cf2c4")


func _draw() -> void:
	if not is_alive():
		return
	var s := body_size()
	var t := float(anim)
	var tint := Color(1, 1, 1, 1) if flash <= 0 else Color(1.6, 1.6, 1.6, 1)
	if state == &"windup":  # telegraph: where the attack will land, and a red-hot mask
		var box := attack_box()
		var k := 1.0 - float(timer) / float(def["windup"])
		draw_rect(Rect2(box.position - position, box.size), Color(1, 0.25, 0.2, 0.08 + 0.18 * k))
	match kind:
		Kind.CAMP:
			_draw_mossback(s, t, tint)
		Kind.WYRM:
			_draw_wyrm(s, t, tint)
		Kind.TITAN:
			_draw_titan(s, t, tint)
	if hp < max_hp or is_boss():
		var bw := s.x + 20.0
		var by := -s.y - (34.0 if is_boss() else 16.0)
		draw_rect(Rect2(-bw * 0.5 - 1, by - 1, bw + 2, 7), Color(0, 0, 0, 0.7))
		draw_rect(Rect2(-bw * 0.5, by, bw * hp / max_hp, 5), Color("c9e86a"))
		if is_boss():
			var font := ThemeDB.fallback_font
			var w := font.get_string_size(display_name().to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
			draw_string_outline(font, Vector2(-w * 0.5, by - 6), display_name().to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, 4, Color(0, 0, 0, 0.7))
			draw_string(font, Vector2(-w * 0.5, by - 6), display_name().to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("e9e2cf"))


func _ellipse(c: Vector2, r: Vector2, color: Color, from := 0.0, to := TAU, n := 20) -> void:
	var pts := PackedVector2Array()
	for k in n + 1:
		var a := lerpf(from, to, float(k) / n)
		pts.append(c + Vector2(cos(a) * r.x, sin(a) * r.y))
	draw_colored_polygon(pts, color)


func _mask(c: Vector2, r: Vector2, tint: Color, horns: float) -> void:
	var red := state == &"windup"
	var mask_col := MASK * tint
	if red:
		mask_col = mask_col.lerp(Color("ff6a5a"), 0.35)
	if horns > 0.0:
		for side: float in [-1.0, 1.0]:
			var b := c + Vector2(side * r.x * 0.5, -r.y * 0.6)
			draw_colored_polygon(PackedVector2Array([b + Vector2(-3, 0), b + Vector2(3, 0), b + Vector2(side * horns * 0.5, -horns * 0.7), b + Vector2(side * horns * 0.7, -horns)]), mask_col)
	_ellipse(c, r, mask_col)
	for side: float in [-1.0, 1.0]:
		_ellipse(c + Vector2(side * r.x * 0.38 + facing * r.x * 0.12, r.y * 0.1), Vector2(r.x * 0.18, r.y * 0.3), Color("0b0d14"))


func _draw_mossback(s: Vector2, t: float, tint: Color) -> void:
	var lunge := 0.0
	if state == &"recover" and timer > int(def["recover"]) - 8:
		lunge = facing * 14.0
	elif state == &"windup":
		lunge = -facing * 6.0
	var moving := state == &"chase" or state == &"return"
	for k in 4:  # legs
		var lx := (k - 1.5) * s.x * 0.25 + lunge
		var swing := sin(t * 0.35 + k * 1.7) * 4.0 if moving else 0.0
		draw_line(Vector2(lx, -8), Vector2(lx + swing, 0), Color("0b120f"), 3.0)
	var c := Vector2(lunge, -s.y * 0.45)
	_ellipse(c, Vector2(s.x * 0.5, s.y * 0.5), SHELL * tint, PI, TAU)
	draw_rect(Rect2(c.x - s.x * 0.5, c.y - 1, s.x, 8), SHELL.darkened(0.3) * tint)
	for k in 5:  # moss on the shell
		_ellipse(c + Vector2((k - 2) * s.x * 0.17, -s.y * (0.36 + 0.06 * (k % 2))), Vector2(s.x * 0.12, s.y * 0.1), Color("2f7a55") * tint)
	for k in 3:
		draw_circle(c + Vector2((k - 1) * s.x * 0.2, -s.y * 0.18), 2.5, BIO)
	_mask(c + Vector2(facing * s.x * 0.48, -2), Vector2(11, 10), tint, 0.0)


func _draw_wyrm(s: Vector2, t: float, tint: Color) -> void:
	var raise := 0.0
	if state == &"windup":
		raise = 30.0 * (1.0 - float(timer) / float(def["windup"]))
	var segs := 8
	for k in range(segs - 1, -1, -1):
		var u := float(k) / (segs - 1)
		var x := facing * (s.x * 0.5 - u * s.x)
		var y := -24.0 - sin(t * 0.08 + u * 4.0) * 10.0 - (1.0 - u) * raise
		var r := lerpf(26.0, 12.0, u)
		_ellipse(Vector2(x, y), Vector2(r, r * 0.85), Color("12332c") * tint)
		draw_circle(Vector2(x, y - r * 0.3), 3.0, Color(BIO, 0.9))
	var head := Vector2(facing * s.x * 0.5, -40.0 - raise)
	_ellipse(head, Vector2(30, 24), Color("0e2a24") * tint)
	_mask(head + Vector2(facing * 10, -6), Vector2(17, 14), tint, 20.0)


func _draw_titan(s: Vector2, t: float, tint: Color) -> void:
	var breathe := sin(t * 0.05) * 3.0
	var arms_up := 0.0
	if state == &"windup":
		arms_up = 70.0 * (1.0 - float(timer) / float(def["windup"]))
	var body := Color("141821") * tint
	for side: float in [-1.0, 1.0]:  # arms
		var sh := Vector2(side * s.x * 0.42, -s.y * 0.68 + breathe)
		var hand := sh + Vector2(side * 26.0, s.y * 0.55 - arms_up * 1.6)
		draw_line(sh, hand, body, 26.0)
		_ellipse(hand, Vector2(18, 14), body.lightened(0.05))
	_ellipse(Vector2(0, -s.y * 0.42 + breathe), Vector2(s.x * 0.5, s.y * 0.44), body)
	for k in 4:
		_ellipse(Vector2((k - 1.5) * s.x * 0.24, -s.y * 0.78 + breathe), Vector2(s.x * 0.16, s.y * 0.07), Color("2a4a3a") * tint)
	_mask(Vector2(facing * 10.0, -s.y * 0.82 + breathe), Vector2(30, 34), tint, 46.0)
	for side: float in [-1.0, 1.0]:
		draw_circle(Vector2(facing * 10.0 + side * 12.0 + facing * 4.0, -s.y * 0.8 + breathe), 4.0, Color("ffb35c"))
