extends TestSuite

var _scene: Node


func teardown() -> void:
	super.teardown()
	if is_instance_valid(_scene):
		_scene.free()


func test_training_scene_builds_and_runs() -> void:
	_scene = (load("res://scenes/training.tscn") as PackedScene).instantiate()
	tree.root.add_child(_scene)
	var stage := _scene as CombatWorld
	check(stage != null, "root is a CombatWorld")
	stage.auto_tick = false
	eq(stage.fighters.size(), 2, "player and dummy")
	check(stage.solids.size() >= 3 and stage.one_ways.size() >= 3, "level geometry collected")
	for _i in 120:
		stage.step()
	for f in stage.fighters:
		check(f.grounded, "%s standing" % f.name)
		eq(f.position.y, 440.0, "%s on the floor" % f.name)


func test_dummy_attack_mode_hits_the_player() -> void:
	_scene = (load("res://scenes/training.tscn") as PackedScene).instantiate()
	tree.root.add_child(_scene)
	var stage := _scene as CombatWorld
	stage.auto_tick = false
	var ctrl: DummyController = stage.get("dummy_controller")
	var player: Fighter = stage.get("player")
	ctrl.mode = DummyController.Mode.ATTACK
	var hit := false
	for _i in 300:
		stage.step()
		if player.combo > 0:
			hit = true
			break
	check(hit, "dummy walks up and lands its string")
