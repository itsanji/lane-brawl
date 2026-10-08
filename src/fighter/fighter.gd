class_name Fighter
extends Node2D
## One fighter: simulation state, the per-tick state machine, and simple shape drawing.
## `position` is the centre of the feet. The simulation never uses Godot's physics engine,
## so it is deterministic and runs headless in tests (and later on an authoritative server).

const ACTIONABLE: Array[StringName] = [&"idle", &"run", &"air", &"guard"]
const HIT_STATES: Array[StringName] = [&"hitstun", &"airhit", &"held", &"tumble", &"knockdown"]

var data: FighterData
var team := 0
var world: CombatWorld
var controller: FighterController
var body_size := CombatRules.BODY_SIZE

var vel := Vector2.ZERO
var facing := 1
var grounded := false
var on_one_way := false
var state: StringName = &"air"
var state_timer := 0

var move: MoveData
var move_id: StringName
var move_frame := 0
var hit_ids := {}
var connected := false  ## current move has hit or been blocked (enables chains and cancels)
var ex := false

var hp := 0.0
var meter := 0.0
var guard := CombatRules.GUARD_MAX
var cooldowns := {&"S1": 0, &"S2": 0}
var combo := 0          ## hits taken in the current combo
var combo_damage := 0.0
var juggle := 0
var invuln := 0
var hitstop := 0
var air_jumps := 1
var drop_timer := 0
var dodge_dir := 0
var dodge_cooldown := 0
var parry_timer := 0
var counter_timer := 0
var wake_invuln := 0
var knock_on_land := false
var flash := 0

var input := InputFrame.new()
var prev_input := InputFrame.new()
var buffered: StringName = &""
var buffer_timer := 0
var buffer_y := 0


func setup(fighter_data: FighterData, team_id: int, spawn: Vector2, face: int) -> void:
	data = fighter_data
	team = team_id
	reset_to(spawn, face)


func reset_to(spawn: Vector2, face: int) -> void:
	position = spawn
	facing = face
	vel = Vector2.ZERO
	grounded = false
	state = &"air"
	state_timer = 0
	move = null
	move_id = &""
	move_frame = 0
	hit_ids.clear()
	connected = false
	ex = false
	hp = data.max_hp
	meter = 0.0
	guard = CombatRules.GUARD_MAX
	cooldowns = {&"S1": 0, &"S2": 0}
	end_combo()
	invuln = 0
	hitstop = 0
	air_jumps = data.air_jumps
	drop_timer = 0
	dodge_cooldown = 0
	parry_timer = 0
	counter_timer = 0
	knock_on_land = false
	buffered = &""
	buffer_timer = 0


func is_actionable() -> bool:
	return state in ACTIONABLE


func is_in_hit_state() -> bool:
	return state in HIT_STATES


func end_combo() -> void:
	combo = 0
	combo_damage = 0.0
	juggle = 0


func add_meter(amount: float) -> void:
	meter = minf(CombatRules.METER_MAX, meter + amount)


func hurtbox() -> Rect2:
	return Rect2(position.x - body_size.x * 0.5, position.y - body_size.y, body_size.x, body_size.y)


## World-space hitbox of the current move, or an empty Rect2 when not on an active frame.
func active_hitbox() -> Rect2:
	if state != &"attack" or move == null or not move.hitbox.has_area() or not move.is_active_frame(move_frame):
		return Rect2()
	var hb := move.hitbox
	var x := (position.x + hb.position.x) if facing > 0 else (position.x - hb.position.x - hb.size.x)
	return Rect2(x, position.y + hb.position.y, hb.size.x, hb.size.y)


# ---------------------------------------------------------------- input

func read_input() -> void:
	prev_input = input
	input = controller.read(self, world) if controller != null else InputFrame.new()
	# Several buttons pressed on the same tick: Guard has the lowest priority,
	# so Guard + Light is a grab and Guard + Heavy is a burst.
	var pressed: StringName = &""
	for b in InputFrame.BUTTONS:
		if input.get(b) and not prev_input.get(b) and (pressed == &"" or pressed == &"guard"):
			pressed = b
	if pressed != &"":
		buffered = pressed
		buffer_timer = CombatRules.BUFFER_FRAMES
		buffer_y = input.y


func _clear_buffer() -> void:
	buffered = &""
	buffer_timer = 0


# ---------------------------------------------------------------- tick

func sim_tick() -> void:
	if hitstop > 0:
		hitstop -= 1
		return
	_tick_timers()
	match state:
		&"idle", &"run", &"air", &"guard":
			_neutral()
		&"attack":
			_step_attack()
		&"hitstun":
			if not _try_burst():
				vel.x *= 0.85
				state_timer -= 1
				if state_timer <= 0:
					state = &"idle"
					end_combo()
		&"blockstun":
			vel.x *= 0.8
			state_timer -= 1
			if state_timer <= 0:
				state = &"guard" if input.guard else &"idle"
		&"airhit":
			if not _try_burst():
				vel.x *= 0.95
				state_timer -= 1
				if grounded and vel.y >= 0.0:
					state = &"knockdown"
					state_timer = CombatRules.KNOCKDOWN_FRAMES
					wake_invuln = CombatRules.WAKE_INVULN
					vel.x *= 0.5
				elif state_timer <= 0 and not knock_on_land:
					state = &"air"
					end_combo()
		&"held":
			vel = Vector2.ZERO
			state_timer -= 1
			if state_timer <= 0:
				state = &"airhit"
				state_timer = 14
		&"tumble":
			invuln = 2
			if grounded and vel.y >= 0.0:
				state = &"knockdown"
				state_timer = CombatRules.TUMBLE_KNOCKDOWN_FRAMES
				wake_invuln = CombatRules.TUMBLE_WAKE_INVULN
		&"knockdown":
			invuln = 2
			vel.x *= 0.8
			knock_on_land = false
			state_timer -= 1
			if state_timer <= 0:
				state = &"idle"
				invuln = wake_invuln
				end_combo()
		&"guardbreak":
			vel.x *= 0.8
			state_timer -= 1
			if state_timer <= 0:
				state = &"idle"
				guard = CombatRules.GUARD_MAX * 0.5
		&"dodge":
			vel.x = dodge_dir * CombatRules.DODGE_SPEED * maxf(0.2, state_timer / float(CombatRules.DODGE_FRAMES))
			if state_timer > 10:
				invuln = maxi(invuln, 1)
			state_timer -= 1
			if state_timer <= 0:
				state = &"idle" if grounded else &"air"
		&"ko":
			vel.x *= 0.85
	_apply_physics()
	if buffer_timer > 0:
		buffer_timer -= 1
		if buffer_timer == 0:
			buffered = &""
	if is_inside_tree():
		queue_redraw()


func _tick_timers() -> void:
	for k: StringName in cooldowns:
		if cooldowns[k] > 0:
			cooldowns[k] -= 1
	invuln = maxi(0, invuln - 1)
	parry_timer = maxi(0, parry_timer - 1)
	counter_timer = maxi(0, counter_timer - 1)
	dodge_cooldown = maxi(0, dodge_cooldown - 1)
	drop_timer = maxi(0, drop_timer - 1)
	flash = maxi(0, flash - 1)
	if state != &"guard" and state != &"blockstun":
		guard = minf(CombatRules.GUARD_MAX, guard + CombatRules.GUARD_REGEN)


func _neutral() -> void:
	var i := input
	var b := buffered
	if b == &"ult" and meter >= CombatRules.METER_MAX and data.moves.has(&"ULT"):
		start_move(&"ULT")
		return
	if b == &"s1" and cooldowns[&"S1"] <= 0 and data.moves.has(&"S1"):
		start_move(&"S1")
		return
	if b == &"s2" and cooldowns[&"S2"] <= 0 and data.moves.has(&"S2"):
		start_move(&"S2")
		return
	if b == &"light" and i.guard and grounded:
		start_move(&"GRAB")
		return
	if b == &"guard" and i.x != 0 and dodge_cooldown <= 0:
		_clear_buffer()
		state = &"dodge"
		state_timer = CombatRules.DODGE_FRAMES
		dodge_dir = i.x
		dodge_cooldown = CombatRules.DODGE_COOLDOWN
		invuln = maxi(invuln, CombatRules.DODGE_INVULN)
		return
	if i.guard and grounded:
		if b == &"guard":
			parry_timer = CombatRules.PARRY_WINDOW
			_clear_buffer()
		state = &"guard"
		vel.x *= 0.5
		return
	if state == &"guard":
		state = &"idle"
	if b == &"heavy":
		var dir_y := buffer_y if buffer_y != 0 else i.y
		if grounded:
			start_move(&"UH" if dir_y < 0 else (&"DH" if dir_y > 0 else &"H"))
		else:
			start_move(&"AH")
		return
	if b == &"light":
		start_move(&"L1" if grounded else &"AL")
		return
	if b == &"jump":
		_clear_buffer()
		if grounded:
			if i.y > 0 and on_one_way:
				drop_timer = CombatRules.DROP_FRAMES
				position.y += 3.0
			else:
				vel.y = CombatRules.JUMP_VELOCITY
			grounded = false
		elif air_jumps > 0:
			air_jumps -= 1
			vel.y = CombatRules.AIR_JUMP_VELOCITY
			world.add_effect(&"ring", position, {"radius": 34.0, "life": 10, "color": Color(1, 1, 1, 0.5)})
	if grounded:
		vel.x = i.x * data.run_speed
		state = &"run" if i.x != 0 else &"idle"
	else:
		vel.x += (i.x * data.run_speed - vel.x) * CombatRules.AIR_CONTROL
		state = &"air"
	if i.x != 0:
		facing = i.x


func start_move(id: StringName) -> void:
	var m := data.get_move(id)
	if m == null:
		return
	_clear_buffer()
	state = &"attack"
	move = m
	move_id = id
	move_frame = 0
	hit_ids.clear()
	connected = false
	ex = false
	if input.x != 0:
		facing = input.x
	if id == &"S1" or id == &"S2":
		cooldowns[id] = int(round(m.cooldown * CombatRules.TICK_RATE))
	if id == &"ULT":
		meter = 0.0
		world.add_text(position + Vector2(0, -130), m.display_name.to_upper(), data.color, 26)
		world.add_effect(&"ring", position + Vector2(0, -40), {"radius": 140.0, "life": 16, "color": data.color})
	world.combat_event.emit(&"move_started", {"fighter": self, "move": m})


func _step_attack() -> void:
	var m := move
	move_frame += 1
	var t := move_frame
	if (move_id == &"S1" or move_id == &"S2") and t == CombatRules.EX_CHECK_FRAME \
			and meter >= CombatRules.METER_BAR and input.get(String(move_id).to_lower()):
		ex = true
		meter -= CombatRules.METER_BAR
		flash = 12
		world.add_text(position + Vector2(0, -112), "EX", Color("ffc443"), 20)
	if m.invuln_from >= 0 and t >= m.invuln_from and t <= m.invuln_to:
		invuln = maxi(invuln, 1)
	if m.self_frames > 0 and t > m.startup and t <= m.startup + m.self_frames:
		vel.x = m.self_velocity.x * facing
		if m.self_velocity.y != 0.0:
			vel.y = m.self_velocity.y
			grounded = false
	elif grounded:
		vel.x *= 0.7
	else:
		vel.x *= 0.97
	if m.multi_hit_interval > 0 and t > m.startup + 1 and (t - m.startup - 1) % m.multi_hit_interval == 0:
		hit_ids.clear()
	if m.air and grounded and t > 2:
		move = null
		state = &"idle"
		return
	if buffered != &"" and t > m.startup:
		var ok := connected or t >= m.startup + m.active
		if buffered == &"light" and m.chain_light != &"" and ok:
			start_move(m.chain_light)
			return
		if buffered == &"heavy" and m.chain_heavy != &"" and ok:
			start_move(m.chain_heavy)
			return
		if connected and m.is_normal():
			if buffered == &"s1" and cooldowns[&"S1"] <= 0 and data.moves.has(&"S1"):
				start_move(&"S1")
				return
			if buffered == &"s2" and cooldowns[&"S2"] <= 0 and data.moves.has(&"S2"):
				start_move(&"S2")
				return
			if buffered == &"ult" and meter >= CombatRules.METER_MAX and data.moves.has(&"ULT"):
				start_move(&"ULT")
				return
		if buffered == &"jump" and connected and m.jump_cancel:
			_clear_buffer()
			move = null
			state = &"air"
			if grounded:
				vel.y = CombatRules.JUMP_VELOCITY
				grounded = false
			elif air_jumps > 0:
				air_jumps -= 1
				vel.y = CombatRules.AIR_JUMP_VELOCITY
			return
	if t >= m.total_frames():
		if m.then_move != &"":
			start_move(m.then_move)
			return
		move = null
		state = &"idle" if grounded else &"air"


func _try_burst() -> bool:
	if buffered == &"heavy" and input.guard and meter >= CombatRules.BURST_COST:
		_clear_buffer()
		meter -= CombatRules.BURST_COST
		invuln = 30
		state = &"idle" if grounded else &"air"
		vel.y = minf(vel.y, -5.0)
		end_combo()
		world.burst_from(self)
		return true
	return false


func knock_out(dir: int) -> void:
	state = &"ko"
	move = null
	vel = Vector2(dir * 6.0, -8.0)
	grounded = false
	invuln = 999999


func _apply_physics() -> void:
	if state == &"held":
		return
	vel.y = minf(CombatRules.MAX_FALL, vel.y + CombatRules.GRAVITY)
	world.move_body(self)
	if grounded:
		air_jumps = data.air_jumps


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	var w := body_size.x
	var h := body_size.y
	var team_color := Color("4ea4ff") if team == 0 else Color("ff5b5e")
	var alpha := 0.5 if (invuln > 0 and invuln < 900 and state != &"knockdown" and state != &"tumble" and (Engine.get_physics_frames() >> 2) % 2 == 1) else 1.0
	draw_set_transform(Vector2.ZERO)
	_draw_ellipse(Vector2(0, 0), Vector2(22, 5), Color(0, 0, 0, 0.35))
	var rot := 0.0
	match state:
		&"airhit":
			rot = -facing * 0.45
		&"tumble":
			rot = Engine.get_physics_frames() * 0.35
		&"knockdown", &"ko":
			rot = -facing * PI / 2.0
		&"hitstun", &"guardbreak":
			rot = -facing * 0.16
	var pivot := Vector2(0, -h / 2.0)
	draw_set_transform(pivot, rot)
	var body := Rect2(-w / 2.0, -h / 2.0 + 24.0, w, h - 24.0)
	var head := Vector2(0, -h / 2.0 + 12.0)
	var fill := Color(data.color, alpha)
	draw_rect(body, fill)
	draw_rect(body, Color(team_color, alpha), false, 3.0)
	draw_rect(Rect2(body.position.x + 2, body.position.y + 22, w - 4, 5), Color(team_color, alpha))
	draw_circle(head, 14.0, fill)
	draw_arc(head, 14.0, 0, TAU, 24, Color(team_color, alpha), 3.0)
	draw_rect(Rect2(head.x + (3 if facing > 0 else -12), head.y - 4, 9, 5), Color(0.04, 0.06, 0.09, alpha))
	if state == &"attack" and move != null and move_frame <= move.startup:
		var k := 0.25 + 0.5 * move_frame / maxf(1.0, move.startup)
		var tint := Color(1, 0.36, 0.37, k) if move.grab else Color(1, 1, 1, k)
		draw_rect(body, tint)
		draw_circle(head, 14.0, tint)
	if flash > 0:
		draw_rect(body, Color(1, 0.77, 0.26, flash / 14.0))
	draw_set_transform(Vector2.ZERO)
	if state == &"guard" or state == &"blockstun":
		var gp := guard / CombatRules.GUARD_MAX
		var gc := Color(0.63, 0.82, 1, 0.9) if gp > 0.5 else (Color(1, 0.77, 0.26, 0.9) if gp > 0.25 else Color(1, 0.36, 0.37, 0.9))
		var c := 0.0 if facing > 0 else PI
		draw_arc(Vector2(facing * 4, -h / 2.0), 40, c - 1.0, c + 1.0, 16, gc, 4.0)
		if parry_timer > 0:
			draw_arc(Vector2(facing * 4, -h / 2.0), 46, c - 1.0, c + 1.0, 16, Color("ffc443"), 2.0)
	var hb := active_hitbox()
	if hb.has_area():
		var local := Rect2(hb.position - position, hb.size)
		_draw_ellipse(local.get_center(), local.size / 2.0, Color(data.color, 0.5))
		var ex_arc := 0.0 if facing > 0 else PI
		_draw_ellipse_arc(local.get_center(), local.size / 2.0, ex_arc - 1.1, ex_arc + 1.1, Color(1, 1, 1, 0.8))
	if world != null and world.debug_draw:
		var hurt := hurtbox()
		draw_rect(Rect2(hurt.position - position, hurt.size), Color("9fd356"), false, 1.0)
		if hb.has_area():
			draw_rect(Rect2(hb.position - position, hb.size), Color(1, 0.24, 0.24, 0.35))
			draw_rect(Rect2(hb.position - position, hb.size), Color("ff5b5e"), false, 1.0)


func _draw_ellipse(center: Vector2, radii: Vector2, color: Color) -> void:
	var pts := PackedVector2Array()
	for k in 20:
		var a := TAU * k / 20.0
		pts.append(center + Vector2(cos(a) * radii.x, sin(a) * radii.y))
	draw_colored_polygon(pts, color)


func _draw_ellipse_arc(center: Vector2, radii: Vector2, from: float, to: float, color: Color) -> void:
	var pts := PackedVector2Array()
	for k in 13:
		var a := lerpf(from, to, k / 12.0)
		pts.append(center + Vector2(cos(a) * radii.x, sin(a) * radii.y))
	draw_polyline(pts, color, 2.0)
