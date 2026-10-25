class_name RouteFollower
extends FighterController
## Follows a list of standing surfaces (from RiftRoutes.plan): walks, jumps, double-jumps near the
## apex and drops through one-way platforms.

var route: Array[Rect2] = []
var index := 0
var visited_bands := {}
var _wait := 0
var _held := false


func done() -> bool:
	return index >= route.size()


func read(f: Fighter, _w: CombatWorld) -> InputFrame:
	var i := InputFrame.new()
	visited_bands[RiftLayout.band_of(f.position.y)] = true
	if done():
		return i
	var t := route[index]
	var on_target := f.grounded and absf(f.position.y - t.position.y) < 1.5 and f.position.x > t.position.x - 4 and f.position.x < t.end.x + 4
	if on_target:
		index += 1
		return i
	var cx := clampf(f.position.x, t.position.x + 30.0, t.end.x - 30.0) if t.size.x > 60.0 else t.get_center().x
	var dx := cx - f.position.x
	if absf(dx) > 6.0:
		i.x = int(signf(dx))
	if _wait > 0:
		_wait -= 1
	if t.position.y < f.position.y - 4.0:  # going up: hold jump for full height
		if f.grounded or f.state == &"jumpsquat":
			if absf(dx) < t.size.x * 0.5 + 60.0 and (_wait == 0 or f.state == &"jumpsquat"):
				i.jump = not _held or f.state == &"jumpsquat"
				_wait = 6
		elif f.vel.y < -1.5:
			i.jump = true
		elif f.air_jumps > 0 and f.position.y > t.position.y - 8.0:
			i.jump = not _held  # release one tick, then press again: double jump
	elif f.grounded and f.on_one_way and absf(dx) < 8.0 and t.position.y > f.position.y + 4.0 and _wait == 0:
		i.y = 1
		i.jump = true
		_wait = 10
	_held = i.jump
	return i
