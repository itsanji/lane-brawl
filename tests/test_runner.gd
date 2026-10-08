extends SceneTree
## Headless test runner:  godot --headless --path . -s res://tests/test_runner.gd
## Runs every `test_*` method of each suite. Exit code 1 if any test fails.

const SUITES: Array[String] = [
	"res://tests/test_movement.gd",
	"res://tests/test_combat.gd",
	"res://tests/test_training_scene.gd",
]


func _initialize() -> void:
	await process_frame  # let the tree start so scenes added by tests get _ready()
	var passed := 0
	var failed := 0
	for path in SUITES:
		print("\n%s" % path.get_file())
		var suite: TestSuite = load(path).new()
		suite.tree = self
		for method in suite.get_method_list():
			var test_name: String = method["name"]
			if not test_name.begins_with("test_"):
				continue
			suite.failures.clear()
			suite.call(test_name)
			suite.teardown()
			if suite.failures.is_empty():
				passed += 1
				print("  ok    %s" % test_name)
			else:
				failed += 1
				print("  FAIL  %s" % test_name)
				for f in suite.failures:
					print("        - %s" % f)
	print("\n%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)
