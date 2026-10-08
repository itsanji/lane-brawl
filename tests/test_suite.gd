class_name TestSuite
extends RefCounted
## Base class for test suites: assertions plus helpers to build a small world and drive fighters.

const FLOOR_Y := 400.0
const PLATFORM := Rect2(300, 280, 200, 12)

var failures: Array[String] = []
var tree: SceneTree
var _worlds: Array[CombatWorld] = []


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func eq(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [message, str(expected), str(actual)])


func teardown() -> void:
	for w in _worlds:
		if is_instance_valid(w):
			w.free()
	_worlds.clear()


## A flat floor at FLOOR_Y plus one one-way platform.
func make_world() -> CombatWorld:
	var w := CombatWorld.new()
	w.add_solid(Rect2(-2000, FLOOR_Y, 6000, 200))
	w.add_solid(PLATFORM, true)
	_worlds.append(w)
	return w


func spawn(w: CombatWorld, team: int, x: float, face: int, y := FLOOR_Y) -> Fighter:
	var f := Fighter.new()
	f.setup(Roster.fighter(&"kael"), team, Vector2(x, y), face)
	w.add_fighter(f, ManualController.new())
	return f


func pad(f: Fighter) -> InputFrame:
	return (f.controller as ManualController).frame


func run(w: CombatWorld, ticks: int) -> void:
	for _i in ticks:
		w.step()


## Press a button for one tick, then release it.
func tap(w: CombatWorld, f: Fighter, button: StringName, y := 0, x := 0) -> void:
	var p := pad(f)
	p.set(button, true)
	p.y = y
	p.x = x
	w.step()
	p.set(button, false)
	p.y = 0
	p.x = 0


func run_until(w: CombatWorld, cond: Callable, max_ticks := 120) -> bool:
	for _i in max_ticks:
		if cond.call():
			return true
		w.step()
	return cond.call()


func scaled(base: float, hits_before: int, mult := 1.06) -> float:
	return roundf(base * mult * CombatRules.combo_scale(hits_before))
