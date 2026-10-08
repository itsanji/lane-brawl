extends TestSuite


## Attacker A at x=300 facing right, defender B at x=360 facing left, both standing.
func duel() -> Array:
	var w := make_world()
	var a := spawn(w, 0, 300, 1)
	var b := spawn(w, 1, 360, -1)
	run(w, 2)
	return [w, a, b]


func test_light_hits_in_range() -> void:
	var d := duel()
	var w: CombatWorld = d[0]
	var a: Fighter = d[1]
	var b: Fighter = d[2]
	tap(w, a, &"light")
	run(w, 10)
	eq(b.hp, b.data.max_hp - scaled(30, 0), "B took one Light")
	eq(b.combo, 1, "combo count")
	check(a.connected, "attacker registered the hit")
	check(a.meter > 0.0 and b.meter > 0.0, "both gain meter")


func test_light_light_heavy_chain_with_damage_scaling() -> void:
	var d := duel()
	var w: CombatWorld = d[0]
	var a: Fighter = d[1]
	var b: Fighter = d[2]
	tap(w, a, &"light")
	run(w, 6)
	tap(w, a, &"light")
	run(w, 6)
	tap(w, a, &"heavy")
	run(w, 30)
	eq(b.combo, 3, "three hits landed")
	var expected := scaled(30, 0) + scaled(32, 1) + scaled(60, 2)
	eq(b.combo_damage, expected, "scaled combo damage")


func test_up_heavy_launches() -> void:
	var d := duel()
	var w: CombatWorld = d[0]
	var a: Fighter = d[1]
	var b: Fighter = d[2]
	tap(w, a, &"heavy", -1)
	check(run_until(w, func() -> bool: return b.combo > 0, 30), "launcher connects")
	eq(b.state, &"airhit", "B launched")
	eq(b.juggle, 1, "launcher costs 1 juggle")
	run(w, 16)  # 7 frames of hitstop, then rising
	check(b.position.y < FLOOR_Y - 40.0, "B is high in the air, y=%s" % b.position.y)


func test_juggle_limit_shared_by_three_attackers() -> void:
	var w := make_world()
	var b := spawn(w, 1, 500, -1)
	var attackers: Array[Fighter] = [spawn(w, 0, 440, 1), spawn(w, 0, 450, 1), spawn(w, 0, 460, 1)]
	run(w, 2)
	var air_light := b.data.get_move(&"AL")
	eq(w.apply_hit(attackers[0], b, b.data.get_move(&"UH"), 1), &"hit", "launcher")
	for k in 3:
		b.hitstop = 0
		eq(w.apply_hit(attackers[(k + 1) % 3], b, air_light, 1), &"hit", "air hit %d" % (k + 1))
	eq(b.juggle, CombatRules.JUGGLE_MAX, "juggle budget spent")
	eq(b.state, &"tumble", "victim drops")
	eq(w.apply_hit(attackers[0], b, air_light, 1), &"whiff", "no more hits while dropping")
	check(run_until(w, func() -> bool: return b.state == &"knockdown", 120), "lands in knockdown")
	check(run_until(w, func() -> bool: return b.state == &"idle", 60), "gets up")
	eq(b.combo, 0, "combo reset on wake-up")
	check(b.invuln > 0, "wake-up invulnerability")


func test_guard_blocks_from_the_front() -> void:
	var d := duel()
	var w: CombatWorld = d[0]
	var a: Fighter = d[1]
	var b: Fighter = d[2]
	pad(b).guard = true
	run(w, 20)  # past the parry window
	tap(w, a, &"heavy")
	run(w, 20)
	eq(b.hp, b.data.max_hp, "no damage through guard")
	check(b.guard < CombatRules.GUARD_MAX, "guard meter drained")
	eq(b.combo, 0, "no combo")


func test_guard_fails_from_behind() -> void:
	var d := duel()
	var w: CombatWorld = d[0]
	var a: Fighter = d[1]
	var b: Fighter = d[2]
	b.facing = 1  # back turned to A
	pad(b).guard = true
	run(w, 20)
	tap(w, a, &"heavy")
	run(w, 20)
	check(b.hp < b.data.max_hp, "hit lands from behind")


func test_grab_beats_guard() -> void:
	var d := duel()
	var w: CombatWorld = d[0]
	var a: Fighter = d[1]
	var b: Fighter = d[2]
	b.position.x = 340
	pad(b).guard = true
	run(w, 20)
	pad(a).guard = true
	tap(w, a, &"light")
	pad(a).guard = false
	eq(a.move_id, &"GRAB", "Guard + Light is a grab")
	run(w, 12)
	eq(b.hp, b.data.max_hp - scaled(56, 0), "grab damage through guard")
	check(b.state == &"airhit" or b.state == &"knockdown", "grab knocks down, state=%s" % b.state)


func test_parry_staggers_the_attacker() -> void:
	var d := duel()
	var w: CombatWorld = d[0]
	var a: Fighter = d[1]
	var b: Fighter = d[2]
	tap(w, a, &"heavy")  # Heavy is active on its 13th frame
	run(w, 8)
	pad(b).guard = true  # tap Guard ~4 frames before the hit
	run(w, 10)
	eq(b.hp, b.data.max_hp, "no damage on parry")
	eq(a.state, &"hitstun", "attacker staggered")
	check(b.counter_timer > 0, "parry reward window open")


func test_dodge_avoids_a_hit() -> void:
	var d := duel()
	var w: CombatWorld = d[0]
	var a: Fighter = d[1]
	var b: Fighter = d[2]
	tap(w, a, &"light")
	pad(b).guard = true
	tap(w, b, &"guard", 0, -1)  # dodge through A
	pad(b).guard = false
	run(w, 12)
	eq(b.hp, b.data.max_hp, "invulnerable during dodge")


func test_hitstop_freezes_both_fighters() -> void:
	var d := duel()
	var w: CombatWorld = d[0]
	var a: Fighter = d[1]
	var b: Fighter = d[2]
	tap(w, a, &"light")
	check(run_until(w, func() -> bool: return b.combo > 0, 20), "hit lands")
	var frame := a.move_frame
	var bx := b.position.x
	w.step()
	eq(a.move_frame, frame, "attacker frozen")
	eq(b.position.x, bx, "defender frozen")


func test_jump_cancel_after_launcher() -> void:
	var d := duel()
	var w: CombatWorld = d[0]
	var a: Fighter = d[1]
	var b: Fighter = d[2]
	tap(w, a, &"heavy", -1)
	check(run_until(w, func() -> bool: return b.combo > 0, 30), "launcher connects")
	tap(w, a, &"jump")
	run_until(w, func() -> bool: return a.hitstop == 0 and a.state != &"attack", 20)
	eq(a.state, &"air", "jump-cancelled into the air")
	check(a.vel.y < 0.0, "rising after the cancel")


func test_ex_skill_spends_one_bar() -> void:
	var d := duel()
	var w: CombatWorld = d[0]
	var a: Fighter = d[1]
	var b: Fighter = d[2]
	b.position.x = 900  # out of range, so no meter is gained from hitting
	a.meter = 150.0
	pad(a).s1 = true
	run(w, 12)
	pad(a).s1 = false
	eq(a.move_id, &"S1", "Rising Fang")
	check(a.ex, "held past frame 8 → EX")
	eq(a.meter, 50.0, "one bar spent")


func test_skill_tap_is_not_ex_and_starts_cooldown() -> void:
	var d := duel()
	var w: CombatWorld = d[0]
	var a: Fighter = d[1]
	a.meter = 150.0
	tap(w, a, &"s1")
	run(w, 10)
	check(not a.ex, "tap is a normal skill")
	check(a.cooldowns[&"S1"] > 0, "cooldown started")
	run(w, 60)
	var cd: int = a.cooldowns[&"S1"]
	tap(w, a, &"s1")
	check(a.cooldowns[&"S1"] < cd, "cannot recast while on cooldown")


func test_ultimate_needs_full_meter() -> void:
	var d := duel()
	var w: CombatWorld = d[0]
	var a: Fighter = d[1]
	var b: Fighter = d[2]
	a.meter = 200.0
	tap(w, a, &"ult")
	check(a.state != &"attack", "no ult with 2 bars")
	a.meter = CombatRules.METER_MAX
	tap(w, a, &"ult")
	eq(a.move_id, &"ULT", "ult starts")
	eq(a.meter, 0.0, "meter spent")
	run(w, 120)
	check(b.combo_damage > 200.0 or b.combo >= 5, "multi-hit ult connected, combo=%d dmg=%s" % [b.combo, b.combo_damage])


func test_burst_escapes_a_combo() -> void:
	var d := duel()
	var w: CombatWorld = d[0]
	var a: Fighter = d[1]
	var b: Fighter = d[2]
	b.meter = 250.0
	tap(w, a, &"heavy", -1)
	check(run_until(w, func() -> bool: return b.combo > 0, 30), "launched")
	run(w, 12)
	var before := b.meter  # includes meter gained from being hit
	pad(b).guard = true
	tap(w, b, &"heavy")
	pad(b).guard = false
	run_until(w, func() -> bool: return b.hitstop == 0, 15)
	eq(b.meter, before - CombatRules.BURST_COST, "burst costs 2 bars")
	eq(b.combo, 0, "combo ended")
	eq(a.state, &"airhit", "attacker pushed away")


func test_signature_air_combo_lands_four_hits() -> void:
	# Up+Heavy launcher → jump cancel → Air Light, Air Light, Air Heavy (uses the whole juggle budget).
	# Flat world: a platform overhead would catch the target and end the combo early.
	var w := make_world()
	w.one_ways.clear()
	var a := spawn(w, 0, 300, 1)
	var b := spawn(w, 1, 350, -1)
	run(w, 2)
	tap(w, a, &"heavy", -1)
	var presses: Array[StringName] = [&"light", &"light", &"heavy"]
	var next := 0
	var jumped := false
	var best := 0
	for t in 160:
		var p := InputFrame.new()
		var toward := int(signf(b.position.x - a.position.x))
		if not jumped and b.combo > 0 and a.hitstop == 0:
			p.jump = true
			jumped = true
		elif jumped and next < presses.size() and a.state == &"air" and t % 2 == 0 \
				and absf(b.position.x - a.position.x) < 70.0 and absf(b.position.y - a.position.y) < 70.0:
			p.set(presses[next], true)
			p.x = toward
			next += 1
		elif jumped:
			p.x = toward
		(a.controller as ManualController).frame = p
		w.step()
		best = maxi(best, b.combo)
	eq(best, 4, "launcher + 3 air hits in one combo")
