extends TestSuite


func test_falls_and_lands_on_floor() -> void:
	var w := make_world()
	var f := spawn(w, 0, 100, 1, 200)
	run(w, 60)
	check(f.grounded, "should be grounded")
	eq(f.position.y, FLOOR_Y, "feet on floor")
	eq(f.state, &"idle", "state after landing")


func test_runs_right() -> void:
	var w := make_world()
	var f := spawn(w, 0, 100, -1)
	run(w, 2)
	pad(f).x = 1
	run(w, 3)
	check(f.vel.x > 0.0 and f.vel.x < f.data.run_speed, "accelerating, vx=%s" % f.vel.x)
	run(w, 7)
	check(absf(f.vel.x - f.data.run_speed) < 0.001, "reached full run speed (vx=%s)" % f.vel.x)
	eq(f.state, &"run", "state")
	eq(f.facing, 1, "turns to face movement")
	pad(f).x = 0
	run(w, 2)
	check(f.vel.x > 0.0 and f.vel.x < f.data.run_speed, "slides to a stop, not instantly")
	run(w, 10)
	eq(f.vel.x, 0.0, "stopped")


func test_jump_and_one_air_jump() -> void:
	var w := make_world()
	var f := spawn(w, 0, 100, 1)
	run(w, 2)
	tap(w, f, &"jump")
	eq(f.state, &"jumpsquat", "a few frames of jumpsquat first")
	run(w, CombatRules.JUMPSQUAT_FRAMES)
	check(not f.grounded, "airborne after jumpsquat")
	run(w, 3)
	tap(w, f, &"jump")
	eq(f.air_jumps, 0, "air jump used")
	var vy := f.vel.y
	run(w, 2)
	tap(w, f, &"jump")
	check(f.vel.y > vy, "third jump ignored (still falling slower→faster), vy=%s" % f.vel.y)
	run(w, 120)
	check(f.grounded, "lands again")
	eq(f.air_jumps, f.data.air_jumps, "air jumps restored on landing")


func test_lands_on_one_way_from_below_and_drops_through() -> void:
	var w := make_world()
	var f := spawn(w, 0, 400, 1)
	run(w, 2)
	hold(w, f, &"jump", 10)
	hold(w, f, &"jump", 20)  # held double jump reaches the platform at y=280
	check(run_until(w, func() -> bool: return f.grounded, 120), "lands somewhere")
	eq(f.position.y, PLATFORM.position.y, "standing on the one-way platform")
	check(f.on_one_way, "flagged as on one-way")
	run(w, 2)  # let go of jump first so the next press counts
	tap(w, f, &"jump", 1)  # Down + Jump
	run(w, 3)
	check(f.position.y > PLATFORM.position.y, "dropped below the platform top")
	check(run_until(w, func() -> bool: return f.grounded, 120), "lands again")
	eq(f.position.y, FLOOR_Y, "back on the floor")


func test_dodge_moves_and_grants_invulnerability() -> void:
	var w := make_world()
	var f := spawn(w, 0, 100, 1)
	run(w, 2)
	var x0 := f.position.x
	pad(f).guard = true
	tap(w, f, &"guard", 0, 1)
	pad(f).guard = false
	eq(f.state, &"dodge", "state")
	check(f.invuln > 0, "invulnerable at dodge start")
	run(w, 25)
	check(f.position.x > x0 + 60.0, "rolled forward, dx=%s" % (f.position.x - x0))
	check(f.dodge_cooldown > 0, "dodge on cooldown")


func test_tap_jump_is_a_short_hop_hold_is_full_height() -> void:
	var heights := []
	for ticks in [1, 30]:
		var w := make_world()
		var f := spawn(w, 0, 900, 1)
		run(w, 2)
		var best := 0.0
		pad(f).jump = true
		for t in 60:
			if t == ticks:
				pad(f).jump = false
			w.step()
			best = maxf(best, FLOOR_Y - f.position.y)
		heights.append(best)
	check(heights[0] < 70.0, "tap = short hop (%d px)" % int(heights[0]))
	check(heights[1] > 150.0, "hold = full jump (%d px)" % int(heights[1]))


func test_dash_bursts_forward_on_ground_and_once_in_air() -> void:
	var w := make_world()
	var f := spawn(w, 0, 900, 1)
	run(w, 2)
	var x0 := f.position.x
	tap(w, f, &"dash", 0, 1)
	eq(f.state, &"dash", "dashing")
	run(w, CombatRules.DASH_FRAMES)
	check(f.position.x - x0 > 130.0, "covered ground fast (dx=%d)" % int(f.position.x - x0))
	check(f.dash_cooldown > 0, "dash on cooldown")
	tap(w, f, &"dash", 0, 1)
	check(f.state != &"dash", "can't dash again while on cooldown")
	run(w, CombatRules.DASH_COOLDOWN)
	hold(w, f, &"jump", 12)
	var y0 := f.position.y
	tap(w, f, &"dash", 0, -1)
	eq(f.state, &"dash", "air dash")
	run(w, 4)
	check(absf(f.position.y - y0) < 4.0, "air dash flies straight (dy=%.1f)" % (f.position.y - y0))
	run(w, CombatRules.DASH_FRAMES)  # let the first dash finish
	f.dash_cooldown = 0  # skip the cooldown while still airborne
	tap(w, f, &"dash", 0, -1)
	check(not f.grounded, "still in the air")
	check(f.state != &"dash", "only one air dash per jump")


func test_w_plus_k_is_a_launcher_not_a_jump() -> void:
	var w := make_world()
	var a := spawn(w, 0, 300, 1)
	var b := spawn(w, 1, 350, -1)
	run(w, 2)
	var p := pad(a)
	p.y = -1        # W is both "up" and "jump"
	p.jump = true
	p.heavy = true
	w.step()
	p.heavy = false
	w.step()
	p.jump = false
	p.y = 0
	eq(a.move_id, &"UH", "pressed together → Up+Heavy launcher")
	check(run_until(w, func() -> bool: return b.combo > 0, 30), "launcher connects")
	eq(b.state, &"airhit", "target launched")


func test_heavy_during_jumpsquat_becomes_the_launcher() -> void:
	var w := make_world()
	var a := spawn(w, 0, 300, 1)
	run(w, 2)
	var p := pad(a)
	p.y = -1
	p.jump = true
	w.step()        # W first ...
	p.heavy = true  # ... K a frame later, still in jumpsquat
	w.step()
	p.heavy = false
	p.jump = false
	p.y = 0
	eq(a.move_id, &"UH", "jump turned into the launcher")
	check(a.grounded, "never left the ground")
