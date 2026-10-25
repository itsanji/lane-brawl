extends SceneTree
## Renders screenshots of each area of the Rift (needs a display; use xvfb-run when headless):
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 -s res://tools/map_tour.gd -- <out_dir>

const STOPS := [
	["01_winter_frostveil", Vector2(2560, 620)],
	["02_spring_bloomway", Vector2(3300, 1980)],
	["03_fall_emberfall", Vector2(2700, 3340)],
	["04_jungle_floor", Vector2(2600, 1420)],
	["05_jungle_climb", Vector2(1800, 1000)],
	["06_lane_outcrops", Vector2(2350, 1980)],
	["07_blue_sanctuary", Vector2(260, 1980)],
]


func _initialize() -> void:
	physics_interpolation = false  # we step the sim by hand here
	var args := OS.get_cmdline_user_args()
	var out_dir := args[0] if args.size() > 0 else "user://map_tour"
	DirAccess.make_dir_recursive_absolute(out_dir)
	var stage: CombatWorld = (load("res://scenes/rift.tscn") as PackedScene).instantiate()
	root.add_child(stage)
	await process_frame
	stage.auto_tick = false
	var player: Fighter = stage.get("player")
	var camera: Camera2D = stage.get("camera")
	for stop: Array in STOPS:
		var at: Vector2 = stop[1]
		if not RiftLayout.in_column(at.x) and RiftLayout.FLOORS.has(at.y):
			at.y = RiftLayout.ground_y(RiftLayout.band_of(at.y), at.x)
		player.reset_to(at, 1)
		for _i in 40:
			stage.step()
		camera.position = stage.call("_camera_target")
		for _i in 40:  # let parallax, particles and the title card settle
			await process_frame
		await RenderingServer.frame_post_draw
		var path := out_dir.path_join(String(stop[0]) + ".png")
		root.get_texture().get_image().save_png(path)
		print("saved ", path)
	quit()
