class_name ManualController
extends FighterController
## Returns whatever is in `frame`; tests (and replays) set it before each step.

var frame := InputFrame.new()


func read(_fighter: Fighter, _world: CombatWorld) -> InputFrame:
	return frame.copy()
