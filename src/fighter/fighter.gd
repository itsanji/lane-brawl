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
var pad_timer := 0
var dash_cooldown := 0
var dash_dir := 0
var air_dash_used := false
var jump_rising := false  ## a held-jump that can still be cut short
var land_squash := 0      ## visual only
var dodge_dir := 0
var dodge_cooldown := 0
var parry_timer := 0
var counter_timer := 0
var wake_invuln := 0
var knock_on_land := false
var flash := 0
var ko_ticks := 0

# match progression (kept across deaths; reset_to doesn't touch them)
var level := 1
var xp := 0.0
var gold := 0
var kills := 0
var deaths := 0
var assists := 0
var cs := 0              ## minions last-hit
var respawn_timer := 0   ## ticks until respawn while KO'd in a match
var damage_buff := 0.0   ## team buffs (Wyrm)

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
	hp = max_hp()
	meter = 0.0
	ko_ticks = 0
	guard = CombatRules.GUARD_MAX
	cooldowns = {&"S1": 0, &"S2": 0}
	end_combo()
	invuln = 0
	hitstop = 0
	air_jumps = data.air_jumps
	drop_timer = 0
	pad_timer = 0
	dash_cooldown = 0
	air_dash_used = false
	jump_rising = false
	dodge_cooldown = 0
	parry_timer = 0
	counter_timer = 0
	knock_on_land = false
	buffered = &""
	buffer_timer = 0
	if is_inside_tree():
		reset_physics_interpolation()  # teleport: don't smear between old and new position


## Max HP grows 8% per level.
func max_hp() -> float:
	return data.max_hp * (1.0 + 0.08 * (level - 1))


## Damage multiplier: fighter base, +5% per level, team buffs.
func power() -> float:
	return data.damage_mult * (1.0 + 0.05 * (level - 1)) * (1.0 + damage_buff)


func is_ko() -> bool:
	return state == &"ko"


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
	# Several buttons pressed on the same tick: attacks, skills and dash win over jump, and jump over
	# guard — so Guard + Light is a grab, Guard + Heavy a burst and W + K (up + heavy) a launcher.
	var pressed: StringName = &""
	var best := -1
	for b in InputFrame.BUTTONS:
		if input.get(b) and not prev_input.get(b):
			var rank := 0 if b == &"guard" else (1 if b == &"jump" else 2)
			if rank > best:
				best = rank
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
		&"jumpsquat":
			_step_jumpsquat()
		&"dash":
			vel.x = dash_dir * CombatRules.DASH_SPEED
			if state_timer % 2 == 0:
				world.add_effect(&"ghost", position, {"life": 12, "color": data.color, "facing": facing})
			state_timer -= 1
			if state_timer <= 0:
				state = &"idle" if grounded else &"air"
				vel.x = dash_dir * data.run_speed
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
			ko_ticks += 1
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
	pad_timer = maxi(0, pad_timer - 1)
	dash_cooldown = maxi(0, dash_cooldown - 1)
	land_squash = maxi(0, land_squash - 1)
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
	if b == &"dash" and dash_cooldown <= 0 and (grounded or not air_dash_used):
		_start_dash(i.x if i.x != 0 else facing)
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
				grounded = false
			else:
				state = &"jumpsquat"
				state_timer = CombatRules.JUMPSQUAT_FRAMES
				return
		elif air_jumps > 0:
			air_jumps -= 1
			vel.y = CombatRules.AIR_JUMP_VELOCITY
			jump_rising = true
			world.add_effect(&"ring", position, {"radius": 34.0, "life": 10, "color": Color(1, 1, 1, 0.5)})
	if jump_rising and not i.jump and vel.y < CombatRules.JUMP_CUT_VELOCITY:
		vel.y = CombatRules.JUMP_CUT_VELOCITY  # released early: short hop
		jump_rising = false
	if grounded:
		var target := i.x * data.run_speed
		var rate := CombatRules.RUN_DECEL
		if i.x != 0:
			rate = CombatRules.TURN_DECEL if vel.x * target < 0.0 else CombatRules.RUN_ACCEL
		vel.x = move_toward(vel.x, target, rate)
		state = &"run" if i.x != 0 or absf(vel.x) > 0.5 else &"idle"
	elif pad_timer > 0:
		vel.x *= 0.85  # flying straight up through the connector above
		state = &"air"
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
			if buffered == &"dash" and dash_cooldown <= 0 and (grounded or not air_dash_used):
				_clear_buffer()
				move = null
				_start_dash(input.x if input.x != 0 else facing)
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


func _start_dash(dir: int) -> void:
	_clear_buffer()
	state = &"dash"
	state_timer = CombatRules.DASH_FRAMES
	dash_dir = dir
	facing = dir
	dash_cooldown = CombatRules.DASH_COOLDOWN
	vel.y = 0.0
	jump_rising = false
	if not grounded:
		air_dash_used = true
	world.add_effect(&"dust", position, {"life": 14, "dir": -dir})


## Pre-jump frames. An attack pressed here becomes a ground attack instead (W + K = launcher).
func _step_jumpsquat() -> void:
	vel.x *= 0.9
	if buffered == &"heavy" or buffered == &"light":
		var y := buffer_y if buffer_y != 0 else input.y
		if buffered == &"heavy":
			start_move(&"UH" if y < 0 else (&"DH" if y > 0 else &"H"))
		else:
			start_move(&"L1")
		return
	state_timer -= 1
	if state_timer <= 0:
		vel.y = CombatRules.JUMP_VELOCITY
		grounded = false
		jump_rising = true
		state = &"air"
		world.add_effect(&"dust", position, {"life": 12, "dir": 0})


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
	var was_grounded := grounded
	if state == &"dash":
		vel.y = 0.0  # dashes fly straight, even in the air
	else:
		vel.y = minf(CombatRules.MAX_FALL, vel.y + CombatRules.GRAVITY)
	world.move_body(self)
	if vel.y >= 0.0:
		jump_rising = false
	if grounded:
		air_jumps = data.air_jumps
		air_dash_used = false
		if not was_grounded:
			land_squash = 6
			world.add_effect(&"dust", position, {"life": 12, "dir": 0})
		if (state == &"idle" or state == &"run") and input.y < 0:
			for pad in world.jump_pads:
				if absf(position.y - pad.y) < 1.0 and absf(position.x - pad.x) < CombatRules.PAD_HALF_WIDTH:
					vel = Vector2(0, CombatRules.PAD_VELOCITY)
					grounded = false
					pad_timer = CombatRules.PAD_FLIGHT_FRAMES
					state = &"air"
					world.add_effect(&"ring", pad, {"radius": 60.0, "life": 14, "color": Color("ffc443")})
					break


# ---------------------------------------------------------------- drawing
# A small bug knight in the spirit of Hollow Knight: pale horned mask, dark cloak with a team-coloured
# hem, a scarf in the fighter's colour, and a nail. Purely visual; reads the sim state only.

const MASK := Color("efe8dc")
const CLOAK := Color("1b1f2e")
const EYE := Color("0b0d14")
const NAIL := Color("d9dde6")


func _draw() -> void:
	if state == &"ko" and ko_ticks > 70:
		return  # gone until respawn
	var team_color := Color("4ea4ff") if team == 0 else Color("ff5b5e")
	var t := float(world.tick) if world != null else 0.0
	var blink := invuln > 0 and invuln < 900 and state != &"knockdown" and state != &"tumble" and int(t / 4.0) % 2 == 1
	var alpha := 0.55 if blink else 1.0
	if grounded:
		_draw_ellipse(Vector2.ZERO, Vector2(20, 4.5), Color(0, 0, 0, 0.35))
		_draw_ellipse_arc(Vector2(0, -1), Vector2(19, 4.5), 0, TAU, Color(team_color, 0.5))

	var rot := 0.0
	match state:
		&"airhit":
			rot = -facing * 0.45
		&"tumble":
			rot = t * 0.35
		&"knockdown", &"ko":
			rot = -facing * PI / 2.0
		&"hitstun", &"guardbreak":
			rot = -facing * 0.18
		&"run":
			rot = facing * 0.08
		&"dash":
			rot = facing * 0.32
	draw_set_transform(Vector2(0, -36), rot)
	var o := Vector2(0, 36)  # local feet position in the rotated frame

	var speed := absf(vel.x)
	var stride := position.x * 0.09
	var air := not grounded
	var anticipation := state == &"attack" and move != null and move_frame <= move.startup
	var squash := 0.94 if anticipation else 1.0
	if state == &"jumpsquat":
		squash = 0.84
	elif land_squash > 0:
		squash = 1.0 - land_squash * 0.025
	elif not grounded and vel.y < -4.0:
		squash = 1.06  # stretch while rising
	var breathe := sin(t * 0.08) * 1.2 if state == &"idle" else 0.0

	# legs
	var leg_l := 0.0
	var leg_r := 0.0
	if state == &"run":
		leg_l = sin(stride) * 6.0
		leg_r = -leg_l
	var leg_len := 6.0 if air else 10.0
	for lx in [-5.0 + leg_l, 5.0 + leg_r]:
		draw_rect(Rect2(o + Vector2(lx - 1.8, -leg_len), Vector2(3.6, leg_len)), Color(CLOAK.darkened(0.3), alpha))

	# cloak: shoulders to a tattered hem that trails behind when moving
	var shoulder := o + Vector2(facing * minf(speed, 6.0) * 0.4, -54.0 * squash + breathe)
	var trail := -facing * minf(speed, 7.0) * 1.3 + (sin(t * 0.25) * 1.5 if air else 0.0)
	var hem_y := o.y - (12.0 if air else 9.0)
	var flare := 19.0 if air else 16.0
	var cloak := PackedVector2Array([
		shoulder + Vector2(-11, 0), shoulder + Vector2(11, 0),
		Vector2(o.x + flare + trail, hem_y), Vector2(o.x + flare * 0.45 + trail, hem_y + 5),
		Vector2(o.x + trail * 1.2, hem_y - 1), Vector2(o.x - flare * 0.45 + trail, hem_y + 5),
		Vector2(o.x - flare + trail, hem_y)])
	draw_colored_polygon(cloak, Color(CLOAK, alpha))
	draw_polyline(PackedVector2Array([cloak[2], cloak[3], cloak[4], cloak[5], cloak[6]]), Color(team_color, 0.85 * alpha), 2.0, true)

	# scarf: wraps the neck, tail streams behind
	var neck := shoulder + Vector2(0, -2)
	var tail_len := 14.0 + minf(speed, 7.0) * 3.0 + (8.0 if air else 0.0)
	var scarf := PackedVector2Array()
	for k in 5:
		var u := k / 4.0
		scarf.append(neck + Vector2(-facing * tail_len * u, u * 6.0 + sin(t * 0.3 + u * 4.0) * 3.0 * u))
	draw_rect(Rect2(neck + Vector2(-9, -3), Vector2(18, 5)), Color(data.color, alpha))
	draw_polyline(scarf, Color(data.color, alpha), 4.0, true)

	# nail: held low behind; raised behind the head while winding up; vertical in front when guarding
	if state != &"attack" or anticipation:
		var hand := shoulder + Vector2(facing * 7.0, 14.0)
		var tip := hand + Vector2(-facing * 20.0, 16.0)
		if anticipation:
			tip = hand + Vector2(-facing * 24.0, -14.0)
		elif state == &"guard" or state == &"blockstun":
			hand = shoulder + Vector2(facing * 13.0, 10.0)
			tip = hand + Vector2(facing * 3.0, -26.0)
		draw_line(hand, tip, Color(NAIL, alpha), 2.5, true)

	# mask with horns and eyes
	var head := shoulder + Vector2(facing * 2.0, -13.0)
	var mask_col := Color(1, 1, 1, alpha) if (state == &"hitstun" and state_timer > 10) or flash > 0 else Color(MASK, alpha)
	for side: float in [-1.0, 1.0]:
		var base := head + Vector2(side * 6.5, -8.0)
		draw_colored_polygon(PackedVector2Array([
			base + Vector2(-2.5, 0), base + Vector2(2.5, 0),
			base + Vector2(side * 4.0 + 1.0, -9.0), base + Vector2(side * 5.5, -15.0), base + Vector2(side * 2.0 - 1.5, -9.0)]), mask_col)
	_draw_ellipse(head, Vector2(11.5, 12.5) * Vector2(1.0, squash), mask_col)
	var eye_shift := facing * 2.5
	for ex: float in [-4.0, 4.0]:
		_draw_ellipse(head + Vector2(ex + eye_shift, 1.5), Vector2(2.6, 4.2), Color(EYE, alpha))
	if anticipation and move.grab:
		_draw_ellipse(head, Vector2(13, 14), Color(1, 0.36, 0.37, 0.35))
	draw_set_transform(Vector2.ZERO)

	if state == &"guard" or state == &"blockstun":
		var gp := guard / CombatRules.GUARD_MAX
		var gc := Color(0.63, 0.82, 1, 0.8) if gp > 0.5 else (Color(1, 0.77, 0.26, 0.8) if gp > 0.25 else Color(1, 0.36, 0.37, 0.8))
		var c := 0.0 if facing > 0 else PI
		draw_arc(Vector2(facing * 6, -40), 38, c - 1.0, c + 1.0, 18, gc, 3.0)
		if parry_timer > 0:
			draw_arc(Vector2(facing * 6, -40), 44, c - 1.0, c + 1.0, 18, Color("ffc443"), 2.0)

	# slash: a white crescent sweeping across the hitbox during active frames
	var hb := active_hitbox()
	if hb.has_area():
		_draw_slash(Rect2(hb.position - position, hb.size))

	if hp < max_hp() and state != &"ko":
		var bw := 36.0
		draw_rect(Rect2(-bw / 2.0, -104, bw, 3), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(-bw / 2.0, -104, bw * clampf(hp / max_hp(), 0.0, 1.0), 3), team_color)

	if world != null and world.debug_draw:
		var hurt := hurtbox()
		draw_rect(Rect2(hurt.position - position, hurt.size), Color("9fd356"), false, 1.0)
		if hb.has_area():
			draw_rect(Rect2(hb.position - position, hb.size), Color(1, 0.24, 0.24, 0.35))
			draw_rect(Rect2(hb.position - position, hb.size), Color("ff5b5e"), false, 1.0)


func _draw_slash(local: Rect2) -> void:
	var c := local.get_center()
	var radii := local.size * 0.5
	var progress := clampf(float(move_frame - move.startup) / maxf(1.0, move.active), 0.0, 1.0)
	var mid := 0.0 if facing > 0 else PI
	if local.size.y > local.size.x * 1.15:
		mid = -PI / 2.0  # launchers and risers sweep upward
		c.y += radii.y * 0.25
	var span := lerpf(0.9, 2.4, progress)
	var a0 := mid - span * 0.5
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	for k in 13:
		var a := lerpf(a0, a0 + span, k / 12.0)
		var thickness := sin(PI * k / 12.0)
		outer.append(c + Vector2(cos(a) * radii.x, sin(a) * radii.y))
		inner.append(c + Vector2(cos(a) * radii.x * (1.0 - 0.32 * thickness), sin(a) * radii.y * (1.0 - 0.32 * thickness)))
	inner.reverse()
	var shape := outer + inner
	draw_colored_polygon(shape, Color(1, 1, 1, 0.85 * (1.0 - progress * 0.4)))
	draw_polyline(outer, Color(data.color, 0.9), 2.0, true)


func _draw_ellipse(center: Vector2, radii: Vector2, color: Color) -> void:
	var pts := PackedVector2Array()
	for k in 20:
		var a := TAU * k / 20.0
		pts.append(center + Vector2(cos(a) * radii.x, sin(a) * radii.y))
	draw_colored_polygon(pts, color)


func _draw_ellipse_arc(center: Vector2, radii: Vector2, from: float, to: float, color: Color) -> void:
	var pts := PackedVector2Array()
	for k in 25:
		var a := lerpf(from, to, k / 24.0)
		pts.append(center + Vector2(cos(a) * radii.x, sin(a) * radii.y))
	draw_polyline(pts, color, 1.5)
