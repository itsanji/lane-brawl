class_name PlayerController
extends FighterController
## Reads the local keyboard / gamepad through the InputMap actions in InputBindings.


func _init() -> void:
	InputBindings.register()


func read(_fighter: Fighter, _world: CombatWorld) -> InputFrame:
	var i := InputFrame.new()
	var ax := Input.get_axis(&"move_left", &"move_right")
	var ay := Input.get_axis(&"move_up", &"move_down")
	i.x = 0 if absf(ax) < 0.4 else int(signf(ax))
	i.y = 0 if absf(ay) < 0.5 else int(signf(ay))
	for b in InputFrame.BUTTONS:
		i.set(b, Input.is_action_pressed(b))
	return i
