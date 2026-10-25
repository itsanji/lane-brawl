class_name DummyController
extends FighterController
## Training dummy behaviours, cycled with F2.

enum Mode { STAND, GUARD, JUMP, ATTACK, BURST }
const MODE_NAMES := ["Stand still", "Guard everything", "Jump", "Attack (Light, Light, Heavy)", "Burst out of combos"]

var mode := Mode.STAND
var target: Fighter
var home_x := NAN  ## when set, the dummy walks back to this x after being knocked away (Rift sparring)
var _t := 0
var _phase := 0


func next_mode() -> void:
	mode = ((mode + 1) % Mode.size()) as Mode
	_phase = 0


func mode_name() -> String:
	return MODE_NAMES[mode]


func read(f: Fighter, _world: CombatWorld) -> InputFrame:
	_t += 1
	var i := InputFrame.new()
	if target == null:
		return i
	var dx := target.position.x - f.position.x
	var dir := int(signf(dx)) if dx != 0.0 else f.facing
	if not is_nan(home_x) and f.is_actionable() and f.combo == 0 and absf(f.position.x - home_x) > 40.0 \
			and (mode == Mode.STAND or absf(dx) > 200.0):
		i.x = int(signf(home_x - f.position.x))
		return i
	match mode:
		Mode.GUARD:
			if f.is_actionable() and f.state != &"guard" and f.facing != dir:
				i.x = dir  # turn to face first; guard only blocks from the front
			else:
				i.guard = true
		Mode.JUMP:
			i.jump = _t % 50 == 0
		Mode.ATTACK:
			if absf(dx) > 75.0 and f.is_actionable():
				i.x = dir
				_phase = 0
			else:
				_phase += 1
				if _phase == 1:
					i.x = dir
					i.light = true
				elif _phase == 12:
					i.light = true
				elif _phase == 24:
					i.heavy = true
				elif _phase >= 100:
					_phase = 0
		Mode.BURST:
			if f.is_in_hit_state() and f.combo >= 3:
				i.guard = true
				i.heavy = _t % 2 == 0
	return i
