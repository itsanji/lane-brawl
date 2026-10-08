@tool
class_name RiftLayout
extends RefCounted
## Geometry of the 5v5 map ("the Rift"), ported from the HTML prototype.
## Five stacked bands, top to bottom: upper lane, upper jungle, middle lane, lower jungle, lower lane.
## Base columns at both ends connect the lanes vertically; one-way "connectors" with jump pads
## below them connect each lane to the jungle next to it.

enum Season { WINTER, SPRING, SUMMER, FALL }

const WORLD_W := 6400.0
const WORLD_H := 2200.0
const TOP := 100.0
const FLOORS: Array[float] = [500.0, 900.0, 1300.0, 1700.0, 2100.0]  ## feet level of each band's floor
const FLOOR_T := 40.0
const COL_W := 400.0
const JUNGLE_X0 := 1400.0
const JUNGLE_X1 := 5000.0
## One-way gaps in floor i (between band i and band i+1), with a jump pad under each.
const CONNECTORS := {0: [2000.0, 3200.0, 4400.0], 1: [1800.0, 4600.0], 2: [1800.0, 4600.0], 3: [2000.0, 3200.0, 4400.0]}
const CONNECTOR_W := 140.0
const LANES: Array[int] = [0, 2, 4]

const BAND_SEASON: Array[Season] = [Season.WINTER, Season.SUMMER, Season.SPRING, Season.SUMMER, Season.FALL]
const BAND_TITLE: Array[String] = ["Frostveil", "Verdant Deep", "Bloomway", "Verdant Deep", "Emberfall"]
const BAND_SUBTITLE: Array[String] = ["Upper lane", "Upper jungle", "Middle lane", "Lower jungle", "Lower lane"]


## Peak hill height (px) on each floor. Hills flatten out near connectors, pads and base entrances,
## and the profile is mirrored around the map centre so both teams get the same terrain.
const HILL_AMP: Array[float] = [85.0, 45.0, 80.0, 45.0, 85.0]
const HILL_FLAT := 110.0   ## flat radius around each anchor
const HILL_RAMP := 220.0   ## distance over which hills fade in


static func ground_x_range(i: int) -> Vector2:
	return Vector2(JUNGLE_X0, JUNGLE_X1) if is_jungle(i) else Vector2(COL_W, WORLD_W - COL_W)


## Surface height of floor i at x (FLOORS[i] where flat, smaller = higher).
static func ground_y(i: int, x: float) -> float:
	return FLOORS[i] + ground_offset(i, x)


static func ground_offset(i: int, x: float) -> float:
	var r := ground_x_range(i)
	if x <= r.x or x >= r.y:
		return 0.0
	var d := absf(x - WORLD_W * 0.5)
	var ph := i * 1.7
	var n := 0.55 * sin(d * 0.0042 + ph) + 0.3 * sin(d * 0.0105 + ph * 2.3) + 0.15 * sin(d * 0.021 + ph * 0.7)
	return -HILL_AMP[i] * pow((n + 1.0) * 0.5, 1.6) * _envelope(i, x)


static func _envelope(i: int, x: float) -> float:
	var r := ground_x_range(i)
	var anchors: Array[float] = [r.x, r.y]
	if CONNECTORS.has(i):
		anchors.append_array(CONNECTORS[i])       # gaps in this floor
	if CONNECTORS.has(i - 1):
		anchors.append_array(CONNECTORS[i - 1])   # pads standing on this floor
	var e := 1.0
	for a in anchors:
		var k := clampf((absf(x - a) - HILL_FLAT) / HILL_RAMP, 0.0, 1.0)
		e *= k * k * (3.0 - 2.0 * k)
	return e


static func band_top(b: int) -> float:
	return TOP if b == 0 else FLOORS[b - 1] + FLOOR_T


## Playable air space of band b (without the floor under it).
static func band_rect(b: int) -> Rect2:
	var top := band_top(b)
	return Rect2(0, top, WORLD_W, FLOORS[b] - top)


static func band_of(y: float) -> int:
	for i in FLOORS.size():
		if y <= FLOORS[i] + 2.0:
			return i
	return FLOORS.size() - 1


static func is_jungle(b: int) -> bool:
	return b == 1 or b == 3


static func in_column(x: float) -> bool:
	return x < COL_W or x > WORLD_W - COL_W


## Builds collision geometry: {"solids": Array[Rect2], "one_ways": Array[Rect2], "pads": Array[Vector2],
## "platforms": Array[Dictionary]} where platforms carry a kind (&"column", &"connector", &"ledge") for the art.
static func build() -> Dictionary:
	var solids: Array[Rect2] = []
	var one_ways: Array[Rect2] = []
	var pads: Array[Vector2] = []
	var platforms: Array[Dictionary] = []
	solids.append(Rect2(-200, -200, WORLD_W + 400, TOP + 200))           # ceiling
	solids.append(Rect2(-200, 0, 200, WORLD_H + 200))                    # outer walls
	solids.append(Rect2(WORLD_W, 0, 200, WORLD_H + 200))
	for i in FLOORS.size():
		var fy := FLOORS[i]
		if i == FLOORS.size() - 1:
			solids.append(Rect2(0, fy, WORLD_W, WORLD_H - fy + 200))
			continue
		for x0 in [0.0, WORLD_W - COL_W]:
			_one_way(one_ways, platforms, Rect2(x0, fy, COL_W, 12), &"column")
		var cur := COL_W
		for c: float in CONNECTORS[i]:
			solids.append(Rect2(cur, fy, c - CONNECTOR_W / 2.0 - cur, FLOOR_T))
			_one_way(one_ways, platforms, Rect2(c - CONNECTOR_W / 2.0, fy, CONNECTOR_W, 12), &"connector")
			pads.append(Vector2(c, FLOORS[i + 1]))
			cur = c + CONNECTOR_W / 2.0
		solids.append(Rect2(cur, fy, WORLD_W - COL_W - cur, FLOOR_T))
	for b in [1, 3]:                                                    # rock closing the jungle bands
		var y0 := FLOORS[b - 1] + FLOOR_T
		var h := FLOORS[b] - y0
		solids.append(Rect2(COL_W, y0, JUNGLE_X0 - COL_W, h))
		solids.append(Rect2(JUNGLE_X1, y0, WORLD_W - COL_W - JUNGLE_X1, h))
	var k := 1
	while true:                                                         # climbing ledges in the base columns
		var y := roundf(FLOORS[4] - k * 133.333)
		k += 1
		if y < TOP + 110.0:
			break
		if FLOORS.any(func(f: float) -> bool: return absf(f - y) < 4.0):
			continue
		for x0 in [40.0, WORLD_W - COL_W + 40.0]:
			_one_way(one_ways, platforms, Rect2(x0, y, COL_W - 80.0, 12), &"column")
	for b in [1, 3]:
		var fy := FLOORS[b]
		for x in [1680.0, 2400.0, 2900.0, 3500.0, 4000.0, 4720.0]:
			_one_way(one_ways, platforms, Rect2(x - 75.0, fy - 140.0, 150, 12), &"ledge")
		_one_way(one_ways, platforms, Rect2(3200.0 - 110.0, fy - 265.0, 220, 12), &"ledge")
	for b in LANES:
		_one_way(one_ways, platforms, Rect2(3200.0 - 120.0, FLOORS[b] - 150.0, 240, 12), &"ledge")
	var grounds: Array[GroundStrip] = []
	for i in FLOORS.size():
		var r := ground_x_range(i)
		var cuts: Array[float] = [r.x]
		if CONNECTORS.has(i):
			for c: float in CONNECTORS[i]:
				cuts.append(c - CONNECTOR_W / 2.0)
				cuts.append(c + CONNECTOR_W / 2.0)
		cuts.append(r.y)
		for ci in range(0, cuts.size(), 2):
			grounds.append(_make_ground(i, cuts[ci], cuts[ci + 1]))
	return {"solids": solids, "one_ways": one_ways, "pads": pads, "platforms": platforms, "grounds": grounds}


static func _make_ground(i: int, x0: float, x1: float) -> GroundStrip:
	var g := GroundStrip.new()
	g.x0 = x0
	g.x1 = x1
	g.base_y = FLOORS[i]
	var x := x0
	while x < x1 + GroundStrip.STEP:
		g.heights.append(ground_y(i, minf(x, x1)))
		x += GroundStrip.STEP
	return g


static func _one_way(one_ways: Array[Rect2], platforms: Array[Dictionary], r: Rect2, kind: StringName) -> void:
	one_ways.append(r)
	platforms.append({"rect": r, "kind": kind, "band": band_of(r.position.y)})
