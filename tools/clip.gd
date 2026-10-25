extends SceneTree
## Records PNG frames of the player walking through areas of the Rift (needs a display; use xvfb-run).
## Turn them into a video with ffmpeg:  ffmpeg -framerate 30 -i <dir>/f%04d.png -pix_fmt yuv420p clip.mp4
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 -s res://tools/clip.gd -- <out_dir>

const SEGMENTS := [Vector3(2300, 620, 200), Vector3(2500, 1980, 160), Vector3(2350, 3340, 140)]  ## x, y (a floor), ticks


class Walker extends FighterController:
	var tick := 0

	func read(_f: Fighter, _w: CombatWorld) -> InputFrame:
		tick += 1
		var i := InputFrame.new()
		i.x = 1
		i.jump = tick % 70 == 40
		return i


func _initialize() -> void:
	physics_interpolation = false  # we step the sim by hand here
	var args := OS.get_cmdline_user_args()
	var out_dir := args[0] if args.size() > 0 else "user://clip"
	DirAccess.make_dir_recursive_absolute(out_dir)
	var stage: CombatWorld = (load("res://scenes/rift.tscn") as PackedScene).instantiate()
	root.add_child(stage)
	await process_frame
	stage.auto_tick = false
	var player: Fighter = stage.get("player")
	var camera: Camera2D = stage.get("camera")
	player.controller = Walker.new()
	var frame := 0
	for seg: Vector3 in SEGMENTS:
		var band := RiftLayout.band_of(seg.y)
		player.reset_to(Vector2(seg.x, RiftLayout.ground_y(band, seg.x)), 1)
		stage.step()
		camera.position = stage.call("_camera_target")
		for _i in 20:
			await process_frame
		for t in int(seg.z):
			stage.step()
			if t % 2 == 0:
				await process_frame
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(out_dir.path_join("f%04d.png" % frame))
				frame += 1
	print("frames ", frame)
	quit()
