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


# ------------------------------------------------------------------ platforming routes

func test_every_lane_reaches_every_lane_through_a_jungle() -> void:
	for from in RiftLayout.LANES:
		for to in RiftLayout.LANES:
			if from == to:
				continue
			var path := RiftRoutes.plan(RiftRoutes.lane_surface(from, 2000.0), to)
			check(not path.is_empty(), "lane %d → lane %d reachable without the bases" % [from, to])
			var via_jungle := path.any(func(r: Rect2) -> bool: return RiftLayout.is_jungle(RiftLayout.band_of(r.position.y)))
			check(via_jungle, "lane %d → lane %d goes through a jungle" % [from, to])


func test_climbs_from_middle_lane_up_to_upper_lane() -> void:
	var w := rift_world()
	var start := RiftRoutes.lane_surface(2, 2050.0)  # next to the ledges under the bridge at 2200
	var path := RiftRoutes.plan(start, 0)
	check(path.size() > 6, "route has a real climb (%d surfaces)" % path.size())
	var f := spawn(w, 0, 2050, 1, RiftLayout.FLOORS[2])
	var climber := RouteFollower.new()
	climber.route = path.slice(1)
	f.controller = climber
	var reached := false
	for _i in 2400:
		w.step()
		if RiftLayout.band_of(f.position.y) == 0 and f.grounded:
			reached = true
			break
	check(reached, "fighter platformed up into the upper lane (stuck at surface %d of %d, pos %s)" % [climber.index, climber.route.size(), str(f.position)])
	var visited_jungle := climber.visited_bands.has(1)
	check(visited_jungle, "the climb went through the upper jungle")


# ------------------------------------------------------------------ terrain

func test_terrain_is_mirrored_and_flat_at_anchors() -> void:
	for i in RiftLayout.FLOORS.size():
		for x in [600.0, 1000.0, 1500.0, 2300.0, 2800.0, 3100.0]:
			check(absf(RiftLayout.ground_y(i, x) - RiftLayout.ground_y(i, RiftLayout.WORLD_W - x)) < 0.01, "floor %d mirrored at x=%d" % [i, x])
		for a in RiftLayout.anchors(i):
			var gy := RiftLayout.ground_y(i, a + (40.0 if a < 3200.0 else -40.0))
			check(absf(gy - RiftLayout.FLOORS[i]) < 0.05, "floor %d flat near anchor %d (%.3f)" % [i, a, gy])


func test_lanes_go_up_and_down() -> void:
	for lane in RiftLayout.LANES:
		var highest := 0.0
		var x := RiftLayout.COL_W
		while x < RiftLayout.WORLD_W - RiftLayout.COL_W:
			highest = maxf(highest, -RiftLayout.ground_offset(lane, x))
			x += 10.0
		check(highest > 90.0, "lane %d has big height changes (highest %d px)" % [lane, int(highest)])


func test_cliff_blocks_walking_but_can_be_jumped() -> void:
	var w := rift_world()
	var f := spawn(w, 0, 2020, 1, RiftLayout.ground_y(0, 2020))
	run(w, 2)
	pad(f).x = 1
	run(w, 90)
	check(f.position.x < 2160.0, "stopped at the cliff (x=%d)" % int(f.position.x))
	check(f.grounded, "standing at the foot of the cliff")
	var low := f.position.y
	pad(f).x = 1  # keep holding right
	hold(w, f, &"jump", 40, 0, 1)
	check(f.position.x > 2170.0 and f.position.y < low - 80.0, "jumped up onto the plateau (pos %s)" % str(f.position))


func test_walking_over_ramps_follows_the_ground() -> void:
	var w := rift_world()
	var f := spawn(w, 0, 450, 1, RiftLayout.ground_y(0, 450))
	run(w, 3)
	pad(f).x = 1
	var worst := 0.0
	for _i in 200:  # over the ramped plateau at 650–1350
		w.step()
		if f.grounded:
			worst = maxf(worst, absf(f.position.y - RiftLayout.ground_y(0, f.position.x)))
	check(f.position.x > 1500.0, "walked across the ramps, x=%d" % int(f.position.x))
	check(worst < 0.5, "feet stay on the surface (worst %.2f px)" % worst)


func test_respawning_inside_a_hill_pops_onto_the_surface() -> void:
	var w := rift_world()
	var f := spawn(w, 0, 1000, 1, RiftLayout.FLOORS[2])  # flat-floor height = inside the plateau
	run(w, 2)
	check(f.grounded, "grounded")
	check(absf(f.position.y - RiftLayout.ground_y(2, 1000)) < 0.5, "pushed up onto the surface")


func test_drop_through_bridge_from_lane_into_jungle() -> void:
	var w := rift_world()
	var f := spawn(w, 0, 1800, 1, RiftLayout.FLOORS[0])
	run(w, 2)
	tap(w, f, &"jump", 1)
	check(run_until(w, func() -> bool: return f.grounded and f.position.y > RiftLayout.FLOORS[0] + 10.0, 200), "falls and lands")
	eq(RiftLayout.band_of(f.position.y), 1, "dropped into the upper jungle")


func test_climb_from_base_to_upper_lane() -> void:
	var w := rift_world()
	var f := spawn(w, 0, 200, 1, RiftLayout.FLOORS[2])
	run(w, 2)
	for t in 1500:
		pad(f).jump = t % 24 < 20  # hold for full height, release briefly to jump again
		w.step()
		if RiftLayout.band_of(f.position.y) == 0 and f.grounded:
			break
	eq(RiftLayout.band_of(f.position.y), 0, "reached the upper lane level by jumping up the base ledges")


func test_rift_scene_builds_and_runs() -> void:
	_scene = (load("res://scenes/rift.tscn") as PackedScene).instantiate()
	tree.root.add_child(_scene)
	var stage := _scene as CombatWorld
	stage.auto_tick = false
	eq(stage.jump_pads.size(), 0, "no jump pads: lanes connect through jungle platforming")
	var art := _scene.get_node("Art")
	check(art.get_child_count() > 60, "art layers built (%d)" % art.get_child_count())
	for _i in 120:
		stage.step()
	var player: Fighter = stage.get("player")
	check(player.grounded, "player standing in the base")
	eq(player.position.y, RiftLayout.FLOORS[2], "on the middle floor of the base")


func test_drops_from_upper_lane_down_to_lower_lane() -> void:
	var w := rift_world()
	var start := RiftRoutes.lane_surface(0, 4720.0)
	var path := RiftRoutes.plan(start, 4)
	check(path.size() > 3, "route found (%d surfaces)" % path.size())
	var f := spawn(w, 0, 4720, 1, RiftLayout.ground_y(0, 4720))
	var follower := RouteFollower.new()
	follower.route = path.slice(1)
	f.controller = follower
	var reached := false
	for _i in 3000:
		w.step()
		if RiftLayout.band_of(f.position.y) == 4 and f.grounded:
			reached = true
			break
	check(reached, "dropped all the way to the lower lane (stuck at surface %d of %d, pos %s)" % [follower.index, follower.route.size(), str(f.position)])
	for band in [1, 2, 3]:
		check(follower.visited_bands.has(band), "passed through band %d" % band)


# ------------------------------------------------------------------ jungle monsters

func monster_world(kind := Monster.Kind.CAMP, x := 2550.0) -> Array:
	var w := rift_world()
	var m := Monster.new()
	m.setup(kind, Vector2(x, RiftLayout.ground_y(1, x)))
	w.add_monster(m)
	return [w, m]


func test_monsters_spawn_in_the_jungles() -> void:
	_scene = (load("res://scenes/rift.tscn") as PackedScene).instantiate()
	tree.root.add_child(_scene)
	var stage := _scene as CombatWorld
	stage.auto_tick = false
	eq(stage.monsters.size(), 6, "4 camps + 2 bosses")
	var bosses := stage.monsters.filter(func(m: Monster) -> bool: return m.is_boss())
	eq(bosses.size(), 2, "one boss per jungle")
	for _i in 30:
		stage.step()
	for m in stage.monsters:
		check(RiftLayout.is_jungle(RiftLayout.band_of(m.position.y)), "%s lives in a jungle" % m.name)
		check(absf(m.position.y - RiftLayout.ground_y(RiftLayout.band_of(m.position.y), m.position.x)) < 0.5, "%s stands on the ground" % m.name)


func test_camp_fights_back_when_hit() -> void:
	var d := monster_world()
	var w: CombatWorld = d[0]
	var m: Monster = d[1]
	var f := spawn(w, 0, 2470, 1, RiftLayout.ground_y(1, 2470))
	run(w, 3)
	f.position.x = m.position.x - 70.0
	tap(w, f, &"light")
	run(w, 10)
	check(m.hp < m.max_hp, "camp took damage")
	check(m.state == &"chase" or m.state == &"windup", "camp is angry (%s)" % m.state)
	var hp0 := f.hp
	check(run_until(w, func() -> bool: return f.hp < hp0, 240), "camp telegraphs and hits back")


func test_guard_blocks_a_monster_strike_and_parry_staggers_it() -> void:
	var d := monster_world()
	var w: CombatWorld = d[0]
	var m: Monster = d[1]
	var f := spawn(w, 0, 2480, 1, RiftLayout.ground_y(1, 2480))
	run(w, 3)
	m.take_hit(f, 1.0, 1)
	pad(f).guard = true
	check(run_until(w, func() -> bool: return m.state == &"windup", 200), "camp winds up")
	var hp0 := f.hp
	check(run_until(w, func() -> bool: return m.state == &"recover", 80), "strike lands")
	check(f.hp > hp0 - m.def["damage"] * 0.5, "guard blocked most of it (%d → %d)" % [int(hp0), int(f.hp)])
	pad(f).guard = false
	run(w, 2)
	check(run_until(w, func() -> bool: return m.state == &"windup", 200), "winds up again")
	run_until(w, func() -> bool: return m.timer <= 4, 60)
	tap(w, f, &"guard")  # tap Guard just before the strike
	run(w, 8)
	eq(m.state, &"stagger", "parry staggers the monster")


func test_camp_leashes_home_and_heals() -> void:
	var d := monster_world()
	var w: CombatWorld = d[0]
	var m: Monster = d[1]
	var f := spawn(w, 0, 2470, 1, RiftLayout.ground_y(1, 2470))
	run(w, 3)
	m.take_hit(f, 300.0, 1)
	f.reset_to(Vector2(1600, RiftLayout.ground_y(1, 1600)), 1)  # run far away
	check(run_until(w, func() -> bool: return m.state == &"idle", 600), "gives up and goes home")
	check(absf(m.position.x - m.home.x) < 40.0, "back home")
	check(run_until(w, func() -> bool: return m.hp >= m.max_hp, 600), "heals to full")


func test_monster_dies_and_respawns() -> void:
	var d := monster_world()
	var w: CombatWorld = d[0]
	var m: Monster = d[1]
	var f := spawn(w, 0, 2470, 1, RiftLayout.ground_y(1, 2470))
	run(w, 2)
	m.hp = 10.0
	f.position.x = m.position.x - 70.0
	tap(w, f, &"light")
	run(w, 10)
	check(not m.is_alive(), "slain")
	run(w, int(float(m.def["respawn"]) * CombatRules.TICK_RATE) + 2)
	check(m.is_alive(), "respawned")
	eq(m.hp, m.max_hp, "at full health")
