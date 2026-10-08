class_name FighterController
extends RefCounted
## Produces one InputFrame per tick for a fighter. Subclass for humans, bots, replays or the network.


func read(_fighter: Fighter, _world: CombatWorld) -> InputFrame:
	return InputFrame.new()
