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
	run(w, 10)
	check(absf(f.position.x - (100 + 10 * f.data.run_speed)) < 0.01, "moved run_speed per tick, x=%s" % f.position.x)
	eq(f.state, &"run", "state")
	eq(f.facing, 1, "turns to face movement")


func test_jump_and_one_air_jump() -> void:
	var w := make_world()
	var f := spawn(w, 0, 100, 1)
	run(w, 2)
	tap(w, f, &"jump")
	check(not f.grounded, "airborne after jump")
	run(w, 5)
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
	tap(w, f, &"jump")
	run(w, 6)
	tap(w, f, &"jump")  # double jump reaches the platform at y=280
	check(run_until(w, func() -> bool: return f.grounded, 120), "lands somewhere")
	eq(f.position.y, PLATFORM.position.y, "standing on the one-way platform")
	check(f.on_one_way, "flagged as on one-way")
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
