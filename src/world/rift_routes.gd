class_name RiftRoutes
extends RefCounted
## Route planning over the Rift's standing surfaces (ground segments and one-way platforms) using the
## jumps a fighter can actually make. Used by tests today and by bots later.

const MAX_RISE := 150.0      ## a single jump reaches 160
const MAX_GAP_UP := 110.0    ## horizontal gap you can cover while jumping up


## Standing surfaces: ground segments (1 px tall rects at the floor baseline) and one-way platforms.
static func surfaces(include_bases := false) -> Array[Rect2]:
	var g := RiftLayout.build()
	var out: Array[Rect2] = []
	for gs: GroundStrip in g["grounds"]:
		out.append(Rect2(gs.x0, gs.base_y, gs.x1 - gs.x0, 1))
	for pl: Dictionary in g["platforms"]:
		if include_bases or pl["kind"] != &"column":
			out.append(pl["rect"])
	return out


## The ground segment of `lane` that contains x (empty Rect2 if x is over a bridge opening).
static func lane_surface(lane: int, x: float) -> Rect2:
	for s in surfaces():
		if s.size.y <= 1.0 and absf(s.position.y - RiftLayout.FLOORS[lane]) < 0.5 and x >= s.position.x and x <= s.end.x:
			return s
	return Rect2()


## Breadth-first search from `start` to any ground segment in `goal_band`; [] if unreachable.
## Moves are only allowed when the path is physically clear: jumps can't pass through solid floors,
## and drops happen through one-way platforms (bridges, ledges) or off the edge of a surface.
static func plan(start: Rect2, goal_band: int, include_bases := false) -> Array[Rect2]:
	var all := surfaces(include_bases)
	var g := RiftLayout.build()
	var solids: Array[Rect2] = []
	solids.assign(g["solids"])
	var one_ways: Array[Rect2] = []
	one_ways.assign(g["one_ways"])
	var prev := {}
	var queue: Array[Rect2] = [start]
	prev[start] = null
	while not queue.is_empty():
		var a: Rect2 = queue.pop_front()
		if RiftLayout.band_of(a.position.y) == goal_band and a.size.y <= 1.0:
			var path: Array[Rect2] = []
			var cur: Variant = a
			while cur != null:
				path.push_front(cur)
				cur = prev[cur]
			return path
		for b in all:
			if prev.has(b):
				continue
			var rise := a.position.y - b.position.y
			var gap := maxf(0.0, maxf(a.position.x - b.end.x, b.position.x - a.end.x))
			var ok := false
			if rise > 0.0:
				ok = rise <= MAX_RISE and gap <= MAX_GAP_UP and _jump_clear(a, b, solids)
			else:
				ok = _drop_clear(a, b, solids, one_ways)
			if ok:
				prev[b] = a
				queue.append(b)
	return []


## x positions where you could move between a and b: their overlap, or just past a's edges.
static func _columns(a: Rect2, b: Rect2, through_a: bool) -> Array[float]:
	var xs: Array[float] = []
	var lo := maxf(a.position.x, b.position.x)
	var hi := minf(a.end.x, b.end.x)
	if through_a and lo <= hi:
		xs.append((lo + hi) * 0.5)
	for x in [a.position.x - 20.0, a.end.x + 20.0]:
		if x >= b.position.x - 10.0 and x <= b.end.x + 10.0:
			xs.append(x)
	return xs


static func _hits_solid(x: float, y0: float, y1: float, solids: Array[Rect2]) -> bool:
	for s in solids:
		if x > s.position.x and x < s.end.x and s.position.y < y1 and s.end.y > y0:
			return true
	return false


## Falling from a to b: through a (if it's a one-way platform) or off its edge, with nothing solid or
## another platform in the way.
static func _drop_clear(a: Rect2, b: Rect2, solids: Array[Rect2], one_ways: Array[Rect2]) -> bool:
	if a.position.y == b.position.y:
		return _gap(a, b) <= 4.0  # walk across (e.g. ground onto a bridge)
	var through := one_ways.has(a)
	for x in _columns(a, b, through):
		if _hits_solid(x, a.position.y + 1.0, b.position.y - 1.0, solids):
			continue
		var blocked := false
		for o in one_ways:
			if o != a and o != b and x > o.position.x and x < o.end.x and o.position.y > a.position.y and o.position.y < b.position.y:
				blocked = true
				break
		if not blocked:
			return true
	return false


## Jumping from a up to b: some column between them with no solid in the way (one-ways are passable).
static func _jump_clear(a: Rect2, b: Rect2, solids: Array[Rect2]) -> bool:
	var lo := maxf(a.position.x, b.position.x)
	var hi := minf(a.end.x, b.end.x)
	var xs: Array[float] = []
	if lo <= hi:
		xs.append((lo + hi) * 0.5)
	else:
		xs.append(b.get_center().x)
		xs.append(clampf(b.get_center().x, a.position.x, a.end.x))
	for x in xs:
		if not _hits_solid(x, b.position.y - 90.0, a.position.y - 1.0, solids):
			return true
	return false


static func _gap(a: Rect2, b: Rect2) -> float:
	return maxf(0.0, maxf(a.position.x - b.end.x, b.position.x - a.end.x))
