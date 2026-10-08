extends TestSuite

var _scene: Node


func teardown() -> void:
	super.teardown()
	if is_instance_valid(_scene):
		_scene.free()


func rift_world() -> CombatWorld:
	var w := CombatWorld.new()
	var g := RiftLayout.build()
	w.solids.assign(g["solids"])
	w.one_ways.assign(g["one_ways"])
	w.jump_pads.assign(g["pads"])
	w.grounds.assign(g["grounds"])
	_worlds.append(w)
	return w


func test_layout_has_pads_under_every_connector() -> void:
	var g := RiftLayout.build()
	var expected := 0
	for i: int in RiftLayout.CONNECTORS:
		expected += (RiftLayout.CONNECTORS[i] as Array).size()
	eq((g["pads"] as Array).size(), expected, "one pad per connector")
	eq(RiftLayout.BAND_SEASON, [RiftLayout.Season.WINTER, RiftLayout.Season.SUMMER, RiftLayout.Season.SPRING, RiftLayout.Season.SUMMER, RiftLayout.Season.FALL], "seasons top to bottom")


func test_pad_launches_from_mid_lane_into_upper_jungle() -> void:
	var w := rift_world()
	var f := spawn(w, 0, 1800, 1, RiftLayout.FLOORS[2])
	run(w, 2)
	eq(RiftLayout.band_of(f.position.y), 2, "starts in the middle lane")
	pad(f).y = -1
	run(w, 3)
	pad(f).y = 0
	check(f.vel.y < -20.0, "launched upward, vy=%s" % f.vel.y)
	check(run_until(w, func() -> bool: return f.grounded and f.vel.y >= 0.0, 120), "lands")
	eq(f.position.y, RiftLayout.FLOORS[1], "standing on the connector into the upper jungle")
	eq(RiftLayout.band_of(f.position.y), 1, "now in the upper jungle")


func test_pad_needs_up_held() -> void:
	var w := rift_world()
	var f := spawn(w, 0, 1800, 1, RiftLayout.FLOORS[2])
	run(w, 30)
	check(f.grounded and f.position.y == RiftLayout.FLOORS[2], "standing on a pad without Up does nothing")


func test_drop_through_connector_from_lane_into_jungle() -> void:
	var w := rift_world()
	var f := spawn(w, 0, 2000, 1, RiftLayout.FLOORS[0])
	run(w, 2)
	tap(w, f, &"jump", 1)
	check(run_until(w, func() -> bool: return f.grounded and f.position.y > RiftLayout.FLOORS[0], 120), "falls and lands")
	eq(RiftLayout.band_of(f.position.y), 1, "dropped into the upper jungle")


func test_climb_from_base_to_upper_lane() -> void:
	var w := rift_world()
	var f := spawn(w, 0, 200, 1, RiftLayout.FLOORS[2])
	run(w, 2)
	for t in 900:
		var p := pad(f)
		p.jump = t % 10 < 2
		w.step()
		if RiftLayout.band_of(f.position.y) == 0 and f.grounded:
			break
	eq(RiftLayout.band_of(f.position.y), 0, "reached the upper lane level by jumping up the ledges")


func test_rift_scene_builds_and_runs() -> void:
	_scene = (load("res://scenes/rift.tscn") as PackedScene).instantiate()
	tree.root.add_child(_scene)
	var stage := _scene as CombatWorld
	stage.auto_tick = false
	eq(stage.jump_pads.size(), 10, "pads loaded")
	var art := _scene.get_node("Art")
	check(art.get_child_count() > 40, "art layers built (%d)" % art.get_child_count())
	for _i in 120:
		stage.step()
	var player: Fighter = stage.get("player")
	check(player.grounded, "player standing in the base")
	eq(player.position.y, RiftLayout.FLOORS[2], "on the middle floor of the base")


func test_terrain_is_mirrored_and_flat_at_anchors() -> void:
	for i in RiftLayout.FLOORS.size():
		for x in [600.0, 1000.0, 1500.0, 2300.0, 2800.0, 3100.0]:
			check(absf(RiftLayout.ground_y(i, x) - RiftLayout.ground_y(i, RiftLayout.WORLD_W - x)) < 0.01, "floor %d mirrored at x=%d" % [i, x])
	for i: int in RiftLayout.CONNECTORS:
		for c: float in RiftLayout.CONNECTORS[i]:
			eq(RiftLayout.ground_y(i, c - 80.0), RiftLayout.FLOORS[i], "floor %d flat next to connector %d" % [i, c])
			eq(RiftLayout.ground_y(i + 1, c), RiftLayout.FLOORS[i + 1], "pad under connector %d is flat" % c)
	eq(RiftLayout.ground_y(2, RiftLayout.COL_W + 20.0), RiftLayout.FLOORS[2], "flat at the base entrance")


func test_lanes_have_real_hills() -> void:
	for lane in RiftLayout.LANES:
		var highest := 0.0
		var x := RiftLayout.COL_W
		while x < RiftLayout.WORLD_W - RiftLayout.COL_W:
			highest = maxf(highest, -RiftLayout.ground_offset(lane, x))
			x += 10.0
		check(highest > 45.0, "lane %d has hills (highest %d px)" % [lane, int(highest)])


func test_walking_over_hills_follows_the_ground() -> void:
	var w := rift_world()
	var f := spawn(w, 0, 450, 1, RiftLayout.FLOORS[2])
	run(w, 3)
	pad(f).x = 1
	var airborne := 0
	var worst := 0.0
	for _i in 380:  # ~2200 px of rolling hills
		w.step()
		if not f.grounded:
			airborne += 1
		else:
			worst = maxf(worst, absf(f.position.y - RiftLayout.ground_y(2, f.position.x)))
	check(f.position.x > 2400.0, "kept walking, x=%d" % int(f.position.x))
	eq(airborne, 0, "never left the ground while walking")
	check(worst < 0.5, "feet stay on the surface (worst %.2f px)" % worst)


func test_falls_onto_a_hilltop() -> void:
	var w := rift_world()
	var best_x := 0.0
	var best := 0.0
	var x := 500.0
	while x < 2900.0:  # stay clear of the ledge over the lane centre
		if -RiftLayout.ground_offset(4, x) > best:
			best = -RiftLayout.ground_offset(4, x)
			best_x = x
		x += 10.0
	var f := spawn(w, 0, best_x, 1, RiftLayout.FLOORS[4] - 200.0)  # below the floor above
	check(run_until(w, func() -> bool: return f.grounded, 120), "lands")
	check(absf(f.position.y - RiftLayout.ground_y(4, best_x)) < 0.5, "on top of the hill, not the flat floor under it")


func test_respawning_inside_a_hill_pops_onto_the_surface() -> void:
	var w := rift_world()
	var x := 500.0
	var best_x := 500.0
	while x < 2900.0:
		if RiftLayout.ground_offset(2, x) < RiftLayout.ground_offset(2, best_x):
			best_x = x
		x += 10.0
	var f := spawn(w, 0, best_x, 1, RiftLayout.FLOORS[2])  # flat-floor height = inside the hill
	run(w, 2)
	check(f.grounded, "grounded")
	check(absf(f.position.y - RiftLayout.ground_y(2, best_x)) < 0.5, "pushed up onto the hill surface")
