extends SceneTree
## Runs the real game (normal game loop, physics interpolation on) as bot vs bot: a Hard LaneBot plays
## your Blue Kael against the Red LaneBot. For recording with Godot's movie maker:
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 \
##     --write-movie out.avi --fixed-fps 30 -s res://tools/autoplay.gd [-- seconds]
## The walk out with the first wave is simulated before recording starts.
## Dry run without rendering, as fast as possible: godot --headless --path . -s res://tools/autoplay.gd -- fast [seconds]

const PRESIM := CombatRules.FIRST_WAVE + 900
const PLAN_TEXT := {&"home": "low HP: going home to heal", &"leave_tower": "backing out of tower range",
	&"fight": "fighting the enemy Kael", &"last_hit": "last-hitting a minion", &"clear": "clearing the enemy wave",
	&"siege": "hitting the tower while minions tank", &"hold": "holding behind its minions"}

var stage: CombatWorld
var caption: Label
var blue: LaneBot
var seconds := 90.0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var fast := "fast" in args
	for a in args:
		if a.is_valid_float():
			seconds = a.to_float()
	stage = (load("res://scenes/rift.tscn") as PackedScene).instantiate()
	root.add_child(stage)
	var layer := CanvasLayer.new()
	layer.layer = 5
	root.add_child(layer)
	caption = Label.new()
	caption.add_theme_font_size_override("font_size", 18)
	caption.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	caption.add_theme_constant_override("outline_size", 8)
	caption.position = Vector2(24, 64)
	layer.add_child(caption)
	await process_frame
	var player: Fighter = stage.get("player")
	blue = LaneBot.new(LaneBot.Difficulty.HARD, 21)
	player.controller = blue
	stage.combat_event.connect(_log)
	stage.auto_tick = false
	for _i in PRESIM:
		stage.step()
	if fast:
		while stage.tick < PRESIM + int(seconds * 60.0) and stage.lane.winner < 0:
			stage.step()
			plans[blue._plan] = plans.get(blue._plan, 0) + 1
		_summary()
		quit()
		return
	var camera: Camera2D = stage.get("camera")
	camera.position = stage.call(&"_camera_target")
	camera.reset_physics_interpolation()
	stage.auto_tick = true


func _physics_process(_delta: float) -> bool:
	if stage == null or blue == null or not stage.auto_tick:
		return false
	var enemy: Fighter = stage.get("dummy")
	var red: LaneBot = enemy.controller
	caption.text = "Bot vs bot — Blue (Hard bot playing you): %s\nRed: %s bot" % [PLAN_TEXT.get(blue._plan, ""), red.difficulty_name()]
	if stage.get("player").is_ko():
		caption.text = "Bot vs bot — Blue was slain"
	if stage.tick >= PRESIM + int(seconds * 60.0) or (stage.lane.winner >= 0 and stage.tick > stage.lane.end_tick + 240):
		_summary()
		quit()
	return false


var hits := {}
var plans := {}


func _log(kind: StringName, info: Dictionary) -> void:
	if kind == &"hit" or kind == &"block" or kind == &"parry":
		var key := "%s %s on %s" % [kind, info["attacker"].name, info["target"].name]
		hits[key] = hits.get(key, 0) + 1
	if kind == &"ko" or kind == &"structure_destroyed":
		var who: Variant = info.get("attacker", info.get("by"))
		var subject: Variant = info.get("target", info.get("structure"))
		var bot: Variant = subject.get("controller") if subject is Fighter else null
		var plan := " (was: %s, hp %d)" % [bot._plan, 0] if bot is LaneBot else ""
		print("  %s %s: %s by %s%s" % [_clock(), kind, subject.name, who.name if is_instance_valid(who) else "?", plan])


func _summary() -> void:
	for f: Fighter in stage.fighters:
		print("%s %s: lv %d, %d gold, cs %d, k/d/a %d/%d/%d" % [_clock(), f.name, f.level, f.gold, f.cs, f.kills, f.deaths, f.assists])
	var down := []
	for st in stage.structures:
		if not st.is_alive():
			down.append(st.name)
	print("down: ", down, " winner: ", stage.lane.winner)
	print("fighter hits: ", hits)
	print("blue plan ticks: ", plans)


func _clock() -> String:
	var s := int(stage.tick / 60)
	return "%d:%02d" % [s / 60, s % 60]
