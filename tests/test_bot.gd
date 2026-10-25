extends TestSuite
## LaneBot: an enemy fighter that plays the lane and fights back.

var lane: LaneMatch


func lane_world() -> CombatWorld:
	var w := CombatWorld.new()
	var g := RiftLayout.build()
	w.solids.assign(g["solids"])
	w.one_ways.assign(g["one_ways"])
	w.grounds.assign(g["grounds"])
	_worlds.append(w)
	lane = LaneMatch.new()
	lane.setup(w)
	return w


func ground(x: float) -> float:
	return RiftLayout.ground_y(LaneMatch.LANE, x)


func bot_fighter(w: CombatWorld, team: int, x: float, level := LaneBot.Difficulty.NORMAL, seed_value := 3) -> Fighter:
	var f := Fighter.new()
	f.setup(Roster.fighter(&"kael"), team, Vector2(x, ground(x)), 1 if team == 0 else -1)
	w.add_fighter(f, LaneBot.new(level, seed_value))
	return f


func test_walks_out_and_holds_behind_its_minions() -> void:
	var w := lane_world()
	var b := bot_fighter(w, 1, RiftLayout.WORLD_W - 200.0)
	run(w, CombatRules.FIRST_WAVE + 900)
	var front := INF
	for mn in w.minions:
		if mn.team == 1:
			front = minf(front, mn.position.x)
	check(b.position.x < RiftLayout.WORLD_W - 1500.0, "left the base (x=%d)" % int(b.position.x))
	check(b.position.x > front, "stays behind its front minion (bot %d, front %d)" % [int(b.position.x), int(front)])


func test_climbs_the_cliffs_on_the_way() -> void:
	var w := lane_world()
	var b := bot_fighter(w, 0, 200.0)
	(b.controller as LaneBot)._plan = &"hold"
	check(run_until(w, func() -> bool: return b.position.x > 1600.0, 900), "got past the plateau cliff (x=%d)" % int(b.position.x))


func test_fights_an_enemy_fighter() -> void:
	var w := lane_world()
	var b := bot_fighter(w, 1, 3260.0)
	var p := spawn(w, 0, 3140.0, 1, ground(3140.0))
	run(w, 240)
	check(p.hp < p.max_hp(), "bot damaged the idle player (%d)" % int(p.hp))


func test_guards_against_heavies() -> void:
	var w := lane_world()
	var b := bot_fighter(w, 1, 3240.0, LaneBot.Difficulty.HARD)
	(b.controller as LaneBot).passive = true
	var p := spawn(w, 0, 3180.0, 1, ground(3180.0))
	var blocks := [0]
	w.combat_event.connect(func(kind: StringName, info: Dictionary) -> void:
		if (kind == &"block" or kind == &"parry") and info["target"] == b:
			blocks[0] += 1)
	for _k in 8:
		tap(w, p, &"heavy")
		run(w, 50)
	check(blocks[0] >= 2, "Hard bot guards/parries some heavies (%d of 8)" % blocks[0])


func test_retreats_when_low() -> void:
	var w := lane_world()
	var b := bot_fighter(w, 1, 3300.0)
	b.hp = b.max_hp() * 0.2
	run(w, 240)
	check(b.position.x > 4300.0, "heading home (x=%d)" % int(b.position.x))
	check(run_until(w, func() -> bool: return b.hp >= b.max_hp() * 0.9, 1500), "healed in its base")


func test_respects_enemy_tower() -> void:
	var w := lane_world()
	var b := bot_fighter(w, 1, 3300.0)
	var tower := lane.structure(0, Structure.Kind.OUTER)
	var deepest := INF
	for _i in 600:
		w.step()
		deepest = minf(deepest, b.position.x)
	check(deepest > tower.position.x + float(tower.def["range"]) - 40.0, "stays out of tower range without minions (deepest x=%d)" % int(deepest))


func test_bot_vs_bot_lane_is_deterministic_and_sane() -> void:
	var results := []
	for run_i in 2:
		var w := lane_world()
		var a := bot_fighter(w, 0, 200.0, LaneBot.Difficulty.HARD, 11)
		var b := bot_fighter(w, 1, RiftLayout.WORLD_W - 200.0, LaneBot.Difficulty.NORMAL, 12)
		run(w, 60 * 150)
		results.append([a.position, b.position, a.hp, b.hp, a.cs, b.cs, a.kills, b.kills, w.minions.size()])
		check(a.cs + b.cs > 5, "bots last-hit minions (%d, %d)" % [a.cs, b.cs])
		check(a.level > 1 and b.level > 1, "bots level up (%d, %d)" % [a.level, b.level])
	eq(results[0], results[1], "same match twice")
