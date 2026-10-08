extends SceneTree
## Renders the training scene with a scripted player and saves PNG screenshots.
## Needs a display (use xvfb-run when headless):
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path . -s res://tools/screenshot.gd -- <out_dir>

## Player inputs by tick: [from_tick, to_tick, {InputFrame fields}]; "approach" walks into range of the dummy.
const SCRIPT := [
	[1, 22, {"x": 1}],
	[30, 30, {"light": true}],
	[38, 38, {"light": true}],
	[46, 46, {"heavy": true}],
	[90, 108, {"approach": true}],
	[110, 110, {"y": -1, "heavy": true}],
	[124, 124, {"jump": true}],
	[132, 132, {"light": true}],
	[142, 142, {"light": true}],
	[152, 152, {"heavy": true}],
]
const SHOTS := {58: "01_chain_heavy", 128: "02_launcher", 146: "03_air_combo", 158: "04_hitboxes"}
const LAST_TICK := 170


class ScriptedController extends FighterController:
	var tick := 0
	var dummy: Fighter

	func read(_f: Fighter, _w: CombatWorld) -> InputFrame:
		tick += 1
		var i := InputFrame.new()
		for entry: Array in SCRIPT:
			if tick >= entry[0] and tick <= entry[1]:
				var fields: Dictionary = entry[2]
				for key: String in fields:
					if key == "approach":
						var dx: float = dummy.position.x - _f.position.x
						i.x = int(signf(dx)) if absf(dx) > 55.0 else 0
					else:
						i.set(key, fields[key])
		return i


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir := args[0] if args.size() > 0 else "user://screenshots"
	DirAccess.make_dir_recursive_absolute(out_dir)
	var stage: CombatWorld = (load("res://scenes/training.tscn") as PackedScene).instantiate()
	root.add_child(stage)
	await process_frame
	stage.auto_tick = false
	var player: Fighter = stage.get("player")
	var ctrl := ScriptedController.new()
	ctrl.dummy = stage.get("dummy")
	player.controller = ctrl
	for t in range(1, LAST_TICK + 1):
		stage.step()
		if t == 150:
			stage.debug_draw = true
		await process_frame
		if SHOTS.has(t):
			await RenderingServer.frame_post_draw
			var path := out_dir.path_join(SHOTS[t] + ".png")
			root.get_texture().get_image().save_png(path)
			print("saved ", path)
	quit()
