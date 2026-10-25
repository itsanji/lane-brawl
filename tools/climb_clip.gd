extends SceneTree
## Records frames of a fighter platforming from the middle lane, through the upper jungle, into the
## upper lane (needs a display; use xvfb-run). Make a video with:
##   ffmpeg -framerate 30 -i <dir>/f%04d.png -pix_fmt yuv420p climb.mp4


func _initialize() -> void:
	physics_interpolation = false  # we step the sim by hand here
	var args := OS.get_cmdline_user_args()
	var out_dir := args[0] if args.size() > 0 else "user://climb"
	DirAccess.make_dir_recursive_absolute(out_dir)
	var stage: CombatWorld = (load("res://scenes/rift.tscn") as PackedScene).instantiate()
	root.add_child(stage)
	await process_frame
	stage.auto_tick = false
	var player: Fighter = stage.get("player")
	var camera: Camera2D = stage.get("camera")
	var follower := RouteFollower.new()
	follower.route = RiftRoutes.plan(RiftRoutes.lane_surface(2, 2050.0), 0).slice(1)
	player.controller = follower
	player.reset_to(Vector2(2050, RiftLayout.FLOORS[2]), 1)
	stage.step()
	camera.position = stage.call("_camera_target")
	for _i in 10:
		await process_frame
	var frame := 0
	var after := 0
	for t in 2400:
		stage.step()
		if t % 2 == 0:
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(out_dir.path_join("f%04d.png" % frame))
			frame += 1
		if RiftLayout.band_of(player.position.y) == 0 and player.grounded:
			after += 1
			if after > 60:
				break
	print("frames ", frame)
	quit()
