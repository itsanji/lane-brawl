class_name InputBindings
extends RefCounted
## Registers the game's input actions in code, so bindings are versioned with the scripts
## and identical in the editor, exported builds and headless tests.


static func register() -> void:
	if InputMap.has_action(&"light"):
		return
	_add(&"move_left", [KEY_A, KEY_LEFT], [JOY_BUTTON_DPAD_LEFT], JOY_AXIS_LEFT_X, -1.0)
	_add(&"move_right", [KEY_D, KEY_RIGHT], [JOY_BUTTON_DPAD_RIGHT], JOY_AXIS_LEFT_X, 1.0)
	_add(&"move_up", [KEY_W, KEY_UP], [JOY_BUTTON_DPAD_UP], JOY_AXIS_LEFT_Y, -1.0)
	_add(&"move_down", [KEY_S, KEY_DOWN], [JOY_BUTTON_DPAD_DOWN], JOY_AXIS_LEFT_Y, 1.0)
	_add(&"jump", [KEY_SPACE], [JOY_BUTTON_A])
	_add(&"light", [KEY_J], [JOY_BUTTON_X])
	_add(&"heavy", [KEY_K], [JOY_BUTTON_Y])
	_add(&"s1", [KEY_U], [JOY_BUTTON_LEFT_SHOULDER])
	_add(&"s2", [KEY_I], [JOY_BUTTON_RIGHT_SHOULDER])
	_add(&"ult", [KEY_O], [], JOY_AXIS_TRIGGER_RIGHT, 1.0)
	_add(&"guard", [KEY_L, KEY_SHIFT], [JOY_BUTTON_B])
	_add(&"debug_hitboxes", [KEY_F1])
	_add(&"training_dummy_mode", [KEY_F2], [JOY_BUTTON_BACK])
	_add(&"training_reset", [KEY_F3], [JOY_BUTTON_START])
	_add(&"training_meter", [KEY_F4])


static func _add(action: StringName, keys: Array = [], buttons: Array = [], axis := -1, axis_value := 0.0) -> void:
	InputMap.add_action(action, 0.4)
	for k: int in keys:
		var e := InputEventKey.new()
		e.physical_keycode = k as Key
		InputMap.action_add_event(action, e)
	for b: int in buttons:
		var j := InputEventJoypadButton.new()
		j.button_index = b as JoyButton
		InputMap.action_add_event(action, j)
	if axis >= 0:
		var mo := InputEventJoypadMotion.new()
		mo.axis = axis as JoyAxis
		mo.axis_value = axis_value
		InputMap.action_add_event(action, mo)
