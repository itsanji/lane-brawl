extends TestSuite
## The one-lane match: structures, minion waves, towers, economy, levels, death/respawn, winning.

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


func at(x: float) -> Vector2:
	return Vector2(x, RiftLayout.ground_y(LaneMatch.LANE, x))


func lane_fighter(w: CombatWorld, team: int, x: float, face: int) -> Fighter:
	var f := spawn(w, team, x, face, RiftLayout.ground_y(LaneMatch.LANE, x))
	run(w, 2)
	return f


func minion(w: CombatWorld, team: int, x: float, kind := Minion.Kind.MELEE) -> Minion:
	var m := Minion.new()
	m.setup(kind, team, at(x), 0.0)
	w.add_minion(m)
	return m


func test_structures_fall_in_order() -> void:
	var w := lane_world()
	eq(w.structures.size(), 8, "4 structures per team")
	var outer := lane.structure(1, Structure.Kind.OUTER)
	var inner := lane.structure(1, Structure.Kind.INNER)
	check(outer.vulnerable(), "outer tower can be damaged")
	check(not inner.vulnerable(), "inner tower is sealed while the outer stands")
	check(not lane.structure(1, Structure.Kind.CORE).vulnerable(), "core sealed")
	w.damage_structure(inner, 500.0, null)
	eq(inner.hp, inner.max_hp, "sealed structure takes no damage")
	w.damage_structure(outer, 99999.0, null)
	check(not outer.is_alive(), "outer tower destroyed")
	check(inner.vulnerable(), "inner tower unsealed")


func test_structures_stand_on_level_ground() -> void:
	var w := lane_world()
	for st in w.structures:
		var hw := st.body_size().x * 0.5 + 8.0
		for dx: float in [-hw, -hw * 0.5, 0.0, hw * 0.5, hw]:
			var gy := RiftLayout.ground_y(LaneMatch.LANE, st.position.x + dx)
			check(absf(gy - st.position.y) < 0.5, "%s: ground level under its base (off by %.1f at %+d)" % [st.name, gy - st.position.y, int(dx)])


func test_waves_spawn_and_march() -> void:
	var w := lane_world()
	run(w, CombatRules.FIRST_WAVE - 1)
	eq(w.minions.size(), 0, "no minions before the first wave")
	run(w, 1)
	eq(w.minions.size(), 10, "5 minions per team")
	var blue := w.minions.filter(func(m: Minion) -> bool: return m.team == 0)
	var x0: float = blue[0].position.x
	run(w, 60)
	check(blue[0].position.x > x0 + 80.0, "blue minions march toward the enemy")
	run(w, CombatRules.WAVE_INTERVAL - 60)
	check(w.minions.size() >= 10, "second wave arrives (%d minions)" % w.minions.size())


func test_minions_fight_each_other() -> void:
	var w := lane_world()
	var a := minion(w, 0, 3000.0)
	var b := minion(w, 1, 3200.0)
	check(run_until(w, func() -> bool: return not a.is_alive() or not b.is_alive(), 1200), "one of two fighting minions dies")


func test_super_minion_after_enemy_gate_falls() -> void:
	var w := lane_world()
	lane.structure(1, Structure.Kind.GATE).hp = 0.0
	lane.spawn_wave()
	var supers := w.minions.filter(func(m: Minion) -> bool: return m.kind == Minion.Kind.SUPER)
	eq(supers.size(), 1, "one super minion")
	eq(supers[0].team, 0, "for the team that broke the gate")


func test_tower_shoots_minions_before_fighters() -> void:
	var w := lane_world()
	var tower := lane.structure(0, Structure.Kind.OUTER)
	var m := minion(w, 1, tower.position.x + 300.0)
	var f := lane_fighter(w, 1, tower.position.x + 200.0, -1)
	check(run_until(w, func() -> bool: return not w.shots.is_empty(), 120), "tower fires")
	check(w.shots[0]["target"] == m, "at the minion, not the fighter")
	check(run_until(w, func() -> bool: return not m.is_alive(), 900), "tower kills the minion")
	var hp := f.hp
	check(run_until(w, func() -> bool: return f.hp < hp, 300), "then shoots the fighter")


func test_tower_aggro_on_fighter_hitting_ally() -> void:
	var w := lane_world()
	var tower := lane.structure(0, Structure.Kind.OUTER)
	var red_m := minion(w, 1, tower.position.x + 420.0)
	var blue_f := lane_fighter(w, 0, tower.position.x + 250.0, 1)
	var red_f := lane_fighter(w, 1, tower.position.x + 290.0, -1)
	red_m.hp = 99999.0
	tap(w, red_f, &"light")
	run(w, 6)
	check(blue_f.hp < blue_f.max_hp(), "red hit blue")
	eq(tower.aggro, red_f, "tower now targets the attacker")


func test_last_hit_gives_gold_and_xp() -> void:
	var w := lane_world()
	var f := lane_fighter(w, 0, 3000.0, 1)
	var m := minion(w, 1, 3040.0)
	m.hp = 5.0
	var gold := f.gold
	tap(w, f, &"light")
	run(w, 8)
	check(not m.is_alive() or not w.minions.has(m), "minion slain")
	eq(f.cs, 1, "creep score")
	eq(f.gold, gold + 20, "melee minion gold")
	check(f.xp > 0.0, "XP from the kill")


func test_hitting_structures_needs_minion_support() -> void:
	var w := lane_world()
	var tower := lane.structure(1, Structure.Kind.OUTER)
	var f := lane_fighter(w, 0, tower.position.x - 45.0, 1)
	f.invuln = 9999  # ignore the tower's shots here
	tap(w, f, &"light")
	run(w, 10)
	var alone := tower.max_hp - tower.hp
	check(alone > 0.0, "fighter damages the outer tower")
	tower.hp = tower.max_hp
	var helper := minion(w, 0, tower.position.x - 120.0)
	helper.hp = 99999.0
	helper.cooldown = 99999  # only there for support; doesn't attack
	run(w, 30)
	tap(w, f, &"light")
	run(w, 10)
	var supported := tower.max_hp - tower.hp
	eq(supported, roundf(alone / CombatRules.BACKDOOR_MULT), "full damage with own minions nearby")


func test_destroying_the_core_wins() -> void:
	var w := lane_world()
	var f := lane_fighter(w, 0, 3000.0, 1)
	var gold := f.gold
	for kind in [Structure.Kind.OUTER, Structure.Kind.INNER, Structure.Kind.GATE]:
		w.damage_structure(lane.structure(1, kind), 99999.0, f)
	check(f.gold >= gold + 400, "structure gold for the team")
	check(f.level > 1, "structure XP levels you up")
	eq(lane.winner, -1, "no winner yet")
	w.damage_structure(lane.structure(1, Structure.Kind.CORE), 99999.0, f)
	eq(lane.winner, 0, "Blue wins")


func test_ko_respawn_and_kill_reward() -> void:
	var w := lane_world()
	var a := lane_fighter(w, 0, 3000.0, 1)
	var b := lane_fighter(w, 1, 3040.0, -1)
	lane.spawn_points[b] = at(3500.0)
	b.hp = 5.0
	var gold := a.gold
	tap(w, a, &"light")
	run(w, 8)
	check(b.is_ko(), "B is KO'd")
	eq(a.kills, 1, "kill counted")
	eq(b.deaths, 1, "death counted")
	check(a.gold >= gold + CombatRules.KILL_GOLD, "kill gold")
	var wait := b.respawn_timer
	var full := roundi((CombatRules.RESPAWN_BASE + CombatRules.RESPAWN_PER_LEVEL) * 60.0)
	check(wait <= full and wait > full - 10, "respawn timer by level (%d of %d)" % [wait, full])
	run(w, wait + 2)
	check(not b.is_ko(), "B respawned")
	check(absf(b.position.x - 3500.0) < 1.0, "at its spawn point")
	eq(b.hp, b.max_hp(), "full health")
	check(b.invuln > 0, "spawn protection")


func test_tower_kill_credits_last_fighter() -> void:
	var w := lane_world()
	var a := lane_fighter(w, 0, 3000.0, 1)
	var b := lane_fighter(w, 1, 3040.0, -1)
	tap(w, a, &"light")
	run(w, 10)
	check(b.hp < b.max_hp(), "A hit B")
	b.hp = 1.0
	b.invuln = 0
	w.env_hit(lane.structure(0, Structure.Kind.OUTER), 2650.0, b, 115.0, Vector2(2, -2), 14, false)
	check(b.is_ko(), "tower finished B")
	eq(a.kills, 1, "A gets the kill for its recent hit")


func test_levels_raise_stats() -> void:
	var w := lane_world()
	var f := lane_fighter(w, 0, 3000.0, 1)
	var hp := f.max_hp()
	var power := f.power()
	lane.give_xp(f, CombatRules.xp_to_next(1) + 1.0)
	eq(f.level, 2, "level 2")
	check(f.max_hp() > hp and f.power() > power, "more HP and damage")
	lane.give_xp(f, 99999.0)
	eq(f.level, CombatRules.MAX_LEVEL, "capped at max level")


func test_monster_rewards_and_wyrm_buff() -> void:
	var w := lane_world()
	var f := spawn(w, 0, 3000.0, 1, RiftLayout.FLOORS[3])
	run(w, 2)
	var wyrm := Monster.new()
	wyrm.setup(Monster.Kind.WYRM, Vector2(3200.0, RiftLayout.FLOORS[3]))
	w.add_monster(wyrm)
	var gold := f.gold
	wyrm.hp = 1.0
	w.combat_event.emit(&"monster_slain", {"monster": wyrm, "by": f})
	eq(f.gold, gold + 80, "Wyrm gold")
	eq(lane.wyrm_stacks[0], 1, "Wyrm stack")
	run(w, 1)
	check(is_equal_approx(f.damage_buff, CombatRules.WYRM_BUFF), "team damage buff")


func test_fountain_heals() -> void:
	var w := lane_world()
	var f := lane_fighter(w, 0, 200.0, 1)
	f.hp = 100.0
	run(w, 120)
	eq(f.hp, f.max_hp(), "healed to full in base")


func test_rift_scene_runs_a_match() -> void:
	var scene: CombatWorld = (load("res://scenes/rift.tscn") as PackedScene).instantiate()
	scene.auto_tick = false
	tree.root.add_child(scene)
	check(scene.lane != null, "the Rift is a lane match")
	for _i in CombatRules.FIRST_WAVE + 1200:
		scene.step()
	check(scene.minions.size() > 0, "minions on the lane")
	check(not scene.training_mode, "fighters can die")
	scene.free()
