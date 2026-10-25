extends SceneTree
## Records scripted gameplay scenarios on the Rift as PNG frames (30 fps, real-time speed) with a caption.
## Needs a display (use xvfb-run). Usage:
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 -s res://tools/record.gd -- <scenario> <out_dir>
## Scenarios: lanes, climb, descend, cliffs, fight, monsters, moves
## Then: ffmpeg -framerate 30 -i <out_dir>/f%04d.png -pix_fmt yuv420p <scenario>.mp4

var stage: CombatWorld
var player: Fighter
var dummy: Fighter
var camera: Camera2D
var out_dir := ""
var frame := 0
var caption: Label


func _initialize() -> void:
	physics_interpolation = false  # we step the sim by hand here
	var args := OS.get_cmdline_user_args()
	var scenario := args[0] if args.size() > 0 else "lanes"
	out_dir = args[1] if args.size() > 1 else "user://record_" + scenario
	DirAccess.make_dir_recursive_absolute(out_dir)
	stage = (load("res://scenes/rift.tscn") as PackedScene).instantiate()
	stage.set("lane_enabled", false)  # free-roam sandbox: no structures or minions
	root.add_child(stage)
	await process_frame
	stage.auto_tick = false
	player = stage.get("player")
	dummy = stage.get("dummy")
	camera = stage.get("camera")
	var layer := CanvasLayer.new()
	layer.layer = 5
	root.add_child(layer)
	caption = Label.new()
	caption.add_theme_font_size_override("font_size", 22)
	caption.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	caption.add_theme_constant_override("outline_size", 8)
	caption.position = Vector2(24, 16)
	layer.add_child(caption)
	match scenario:
		"lanes": await _lanes()
		"climb": await _route(Vector2(2050, RiftLayout.FLOORS[2]), 0, "Climbing: middle lane → upper jungle → upper lane")
		"descend": await _route(Vector2(4600 + 120, RiftLayout.FLOORS[0]), 4, "Dropping down: upper lane → jungle → middle lane → jungle → lower lane")
		"cliffs": await _cliffs()
		"fight": await _fight()
		"monsters": await _monsters()
		"moves": await _moves()
	print("frames ", frame)
	quit()


# ------------------------------------------------------------------ helpers

func _teleport(f: Fighter, at: Vector2) -> void:
	var b := RiftLayout.band_of(at.y)
	if not RiftLayout.in_column(at.x) and RiftLayout.FLOORS.has(at.y):
		at.y = RiftLayout.ground_y(b, at.x)
	f.reset_to(at, 1)


func _snap_camera() -> void:
	stage.step()
	camera.position = stage.call("_camera_target")
	for _i in 6:
		await process_frame


## Advances one sim tick; saves a frame every other tick (60 ticks/s → 30 fps video).
func _tick(t: int) -> void:
	stage.step()
	if t % 2 == 0:
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(out_dir.path_join("f%04d.png" % frame))
		frame += 1


func _hold(ticks: int) -> void:
	for t in ticks:
		await _tick(t)


class Scripted extends FighterController:
	var fn: Callable
	var tick := 0

	func read(f: Fighter, w: CombatWorld) -> InputFrame:
		tick += 1
		var i := InputFrame.new()
		fn.call(i, f, w, tick)
		return i


func _script(f: Fighter, fn: Callable) -> void:
	var s := Scripted.new()
	s.fn = fn
	f.controller = s


# ------------------------------------------------------------------ scenarios

func _lanes() -> void:
	var segments := [
		[Vector2(2250, RiftLayout.FLOORS[0]), "Frostveil — upper lane, Japanese winter"],
		[Vector2(2450, RiftLayout.FLOORS[2]), "Bloomway — middle lane, spring"],
		[Vector2(2700, RiftLayout.FLOORS[1]), "Verdant Deep — the jungles between lanes"],
		[Vector2(2150, RiftLayout.FLOORS[4]), "Emberfall — lower lane, fall"],
	]
	for seg: Array in segments:
		_teleport(player, seg[0])
		caption.text = seg[1]
		_script(player, func(i: InputFrame, f: Fighter, _w: CombatWorld, t: int) -> void:
			i.x = 1
			var p := t % 80
			i.jump = (p >= 50 and p < 62) or (p >= 64 and p < 76))  # hold = full jump, then a double jump
		await _snap_camera()
		await _hold(220)


func _route(start: Vector2, goal_band: int, text: String) -> void:
	caption.text = text
	_teleport(player, start)
	var follower := RouteFollower.new()
	var band := RiftLayout.band_of(start.y)
	follower.route = RiftRoutes.plan(RiftRoutes.lane_surface(band, start.x), goal_band).slice(1)
	player.controller = follower
	await _snap_camera()
	var after := 0
	for t in 3000:
		await _tick(t)
		if RiftLayout.band_of(player.position.y) == goal_band and player.grounded:
			after += 1
			if after > 70:
				break


func _cliffs() -> void:
	caption.text = "Lanes go up and down: walk the ramps, jump the cliffs"
	_teleport(player, Vector2(1900, RiftLayout.FLOORS[4]))
	_script(player, func(i: InputFrame, f: Fighter, w: CombatWorld, _t: int) -> void:
		i.x = 1
		# jump when a cliff blocks the way (standing still while pushing right)
		var ahead := RiftLayout.ground_y(4, f.position.x + 20.0)
		if f.grounded and ahead < f.position.y - 20.0:
			i.jump = true
		elif not f.grounded and f.vel.y > -1.0 and f.air_jumps > 0 and RiftLayout.ground_y(4, f.position.x + 30.0) < f.position.y - 10.0:
			i.jump = true)
	await _snap_camera()
	await _hold(420)


func _fight() -> void:
	# A short combat showcase against the dummy in Bloomway.
	var x0 := 3300.0
	_teleport(player, Vector2(x0, RiftLayout.FLOORS[2]))
	_teleport(dummy, Vector2(x0 + 140, RiftLayout.FLOORS[2]))
	dummy.facing = -1
	var dc: DummyController = stage.get("dummy_controller")
	dc.mode = DummyController.Mode.STAND
	await _snap_camera()
	var phases := [
		["Light, Light, Heavy chain", ["approach", "L", 8, "L", 8, "H", 50]],
		["Up+Heavy launcher → jump → air combo", ["approach", "UH", "jc", "air", "air", "airH", 70]],
		["The dummy guards: Guard + Light grabs through it", ["guard_on", "approach", "L", 30, "grab", 70, "guard_off"]],
		["Ultimate: Thousand Cuts", ["approach", "meter", "ULT", 170]],
	]
	for ph: Array in phases:
		caption.text = ph[0]
		var steps: Array = ph[1]
		var k := 0
		var wait := 0
		var t := 0
		while k < steps.size() and t < 600:
			var step: Variant = steps[k]
			var i := InputFrame.new()
			var dx := dummy.position.x - player.position.x
			var dir := int(signf(dx)) if dx != 0.0 else player.facing
			var advance := false
			if step is int:
				wait += 1
				advance = wait >= int(step)
			else:
				match step:
					"approach":
						if absf(dx) > 62.0:
							i.x = dir
						else:
							advance = player.is_actionable()
							if player.facing != dir:
								i.x = dir
					"L": i.light = true; advance = true
					"H": i.heavy = true; advance = true
					"UH": i.y = -1; i.heavy = true; advance = true
					"jc":
						if dummy.combo > 0 and player.hitstop == 0:
							i.jump = true
							advance = true
					"air", "airH":
						if not player.grounded and player.state == &"air" and absf(dx) < 70.0 and absf(dummy.position.y - player.position.y) < 70.0:
							if step == "airH":
								i.heavy = true
							else:
								i.light = true
							advance = true
						i.x = dir
						if player.grounded and t > 40:
							advance = true
					"grab": i.guard = true; i.light = true; advance = true
					"guard_on": dc.mode = DummyController.Mode.GUARD; advance = true
					"guard_off": dc.mode = DummyController.Mode.STAND; advance = true
					"meter": player.meter = CombatRules.METER_MAX; advance = true
					"ULT": i.ult = true; advance = true
			var s := Scripted.new()
			s.fn = func(out: InputFrame, _f: Fighter, _w: CombatWorld, _tt: int) -> void:
				out.x = i.x
				out.y = i.y
				for b in InputFrame.BUTTONS:
					out.set(b, i.get(b))
			player.controller = s
			await _tick(t)
			t += 1
			if advance:
				k += 1
				wait = 0
		player.controller = null
		await _hold(30)



func _moves() -> void:
	_teleport(player, Vector2(2300, RiftLayout.FLOORS[2]))
	await _snap_camera()
	var beats := [
		["Tap W: short hop", 60, func(i: InputFrame, t: int) -> void: i.jump = t == 5],
		["Hold W: full jump · press again in the air: double jump", 90, func(i: InputFrame, t: int) -> void: i.jump = (t >= 5 and t < 22) or (t >= 26 and t < 45)],
		["Shift: dash", 70, func(i: InputFrame, t: int) -> void:
			i.x = 1
			i.dash = t == 10],
		["Jump + Shift: air dash (once per jump) — watch the cooldown on the bottom right", 100, func(i: InputFrame, t: int) -> void:
			i.x = -1
			i.jump = t >= 5 and t < 18
			i.dash = t == 20],
		["Run and dash through the lane", 120, func(i: InputFrame, t: int) -> void:
			i.x = 1
			i.dash = t % 50 == 10
			i.jump = (t % 50) >= 30 and (t % 50) < 42],
	]
	for beat: Array in beats:
		caption.text = beat[0]
		var fn: Callable = beat[2]
		_script(player, func(i: InputFrame, _f: Fighter, _w: CombatWorld, t: int) -> void: fn.call(i, t))
		await _hold(int(beat[1]))


## Fights a jungle monster with a simple reactive script. react: "guard" its strikes, "dash" out of them,
## or "parry" them (tap Guard just before the hit).
func _monster_fight(mon: Monster, from_x: float, ticks: int, react: String, text: String) -> void:
	caption.text = text
	var band := RiftLayout.band_of(mon.home.y)
	_teleport(player, Vector2(from_x, RiftLayout.FLOORS[band]))
	mon.state = &"idle"
	mon.hp = mon.max_hp
	await _snap_camera()
	var mem := {"phase": 0, "back": 0}
	_script(player, func(i: InputFrame, f: Fighter, _w: CombatWorld, t: int) -> void:
		var dx := mon.position.x - f.position.x
		var dir := int(signf(dx)) if dx != 0.0 else f.facing
		var reach := mon.body_size().x * 0.5 + 40.0
		if mem["back"] > 0:  # dashing away, then come back
			mem["back"] -= 1
			i.x = -dir
			return
		if mon.state == &"windup" and absf(dx) < mon.attack_box().size.x:
			match react:
				"guard":
					if f.facing != dir and f.state != &"guard":
						i.x = dir
					else:
						i.guard = true
				"dash":
					if mon.timer < 30 and f.dash_cooldown == 0:
						i.x = -dir
						i.dash = true
						mem["back"] = 24
				"parry":
					if f.facing != dir:
						i.x = dir
					i.guard = mon.timer == 4
			return
		if absf(dx) > reach:
			i.x = dir
			return
		if f.facing != dir:
			i.x = dir
			return
		var k := t % 36  # Light, Light, Heavy string
		i.light = k == 0 or k == 8
		i.heavy = k == 16)
	await _hold(ticks)


func _monsters() -> void:
	var by_kind := {}
	for m in stage.monsters:
		if not by_kind.has(m.kind):
			by_kind[m.kind] = m
	await _monster_fight(by_kind[Monster.Kind.CAMP], by_kind[Monster.Kind.CAMP].home.x - 240.0, 420, "guard",
		"Jungle camp — Mossback: it telegraphs (red), guard its bite")
	await _monster_fight(by_kind[Monster.Kind.TITAN], 2950.0, 420, "dash",
		"Boss — Hollow Titan: read the slam, dash out, come back in")
	await _monster_fight(by_kind[Monster.Kind.WYRM], 2950.0, 420, "parry",
		"Boss — Lumen Wyrm: tap Guard just before the sweep to parry and stagger it")
