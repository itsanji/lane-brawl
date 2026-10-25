@tool
class_name RiftLayout
extends RefCounted
## Geometry of the 5v5 map ("the Rift").
## Five stacked bands, top to bottom: upper lane, upper jungle, middle lane, lower jungle, lower lane.
## Lanes are open-air and seasonal; tall jungles separate them. Moving between lanes means platforming:
## each floor between a lane and a jungle has one-way "bridges" over openings. From a lane you drop
## through a bridge into the jungle below; to go up you climb a zig-zag of ledges (lane-side or jungle)
## that ends right under a bridge, then jump through it. Base columns at both ends also connect the lanes.

enum Season { WINTER, SPRING, SUMMER, FALL }

const WORLD_W := 6400.0
const TOP := 100.0
const LANE_AIR := 520.0      ## open air above a lane's baseline floor
const JUNGLE_AIR := 760.0    ## open air inside a jungle
const FLOOR_T := 40.0
const FLOORS: Array[float] = [
	TOP + LANE_AIR,                                                   # 620  upper lane floor
	TOP + LANE_AIR + FLOOR_T + JUNGLE_AIR,                            # 1420 upper jungle floor
	TOP + LANE_AIR * 2.0 + FLOOR_T * 2.0 + JUNGLE_AIR,                # 1980 middle lane floor
	TOP + LANE_AIR * 2.0 + FLOOR_T * 3.0 + JUNGLE_AIR * 2.0,          # 2780 lower jungle floor
	TOP + LANE_AIR * 3.0 + FLOOR_T * 4.0 + JUNGLE_AIR * 2.0,          # 3340 lower lane floor
]
const WORLD_H := 3460.0
const COL_W := 400.0
const JUNGLE_X0 := 1400.0
const JUNGLE_X1 := 5000.0
## Bridges (one-way openings) in floor i, which separates band i (above) from band i+1 (below).
const BRIDGES := {0: [1800.0, 4600.0], 1: [2200.0, 4200.0], 2: [2200.0, 4200.0], 3: [1800.0, 4600.0]}
## Jungle monsters: [band, x, kind]. Camps on both sides (mirrored), a boss in each jungle's centre.
const MONSTERS := [
	[1, 2550.0, Monster.Kind.CAMP], [1, 3850.0, Monster.Kind.CAMP], [1, 3200.0, Monster.Kind.TITAN],
	[3, 2550.0, Monster.Kind.CAMP], [3, 3850.0, Monster.Kind.CAMP], [3, 3200.0, Monster.Kind.WYRM],
]
const BRIDGE_W := 140.0
const STAIR_STEP := 140.0    ## vertical spacing of climbing ledges (a single jump reaches 160)
const STAIR_SHIFT := 150.0   ## horizontal zig-zag of climbing ledges
const STAIR_W := 150.0
const LANES: Array[int] = [0, 2, 4]

const BAND_SEASON: Array[Season] = [Season.WINTER, Season.SUMMER, Season.SPRING, Season.SUMMER, Season.FALL]
const BAND_TITLE: Array[String] = ["Frostveil", "Verdant Deep", "Bloomway", "Verdant Deep", "Emberfall"]
const BAND_SUBTITLE: Array[String] = ["Upper lane", "Upper jungle", "Middle lane", "Lower jungle", "Lower lane"]

## Terrain. Lanes get plateaus (cliff = must jump, ramp = walkable) on top of gentle hills; jungle
## floors get small hills only. Plateaus are defined for the left half and mirrored around the centre:
## [x_start, x_end, height, cliff_on_left, cliff_on_right]
const PLATEAUS := {
	0: [[650.0, 1350.0, 80.0, false, false], [2150.0, 2850.0, 110.0, true, false]],
	2: [[700.0, 1500.0, 100.0, true, false], [2600.0, 3800.0, 70.0, false, false]],
	4: [[600.0, 1450.0, 90.0, false, true], [2150.0, 2900.0, 120.0, true, true]],
}
## Lane structures (towers, gate; Blue side, Red mirrored) stand on level pads cut into the terrain.
const STRUCTURE_FLOOR := 2
const STRUCTURE_X := {&"outer": 2650.0, &"inner": 1250.0, &"gate": 560.0, &"core": 200.0}
const PAD_HALF := 62.0     ## flat half-width of a structure pad
const PAD_RAMP := 60.0     ## blend back into the terrain
const HILL_AMP: Array[float] = [40.0, 30.0, 40.0, 30.0, 40.0]
const HILL_FLAT := 110.0   ## flat radius around each anchor (bridges, climbing stairs, base entrances)
const HILL_RAMP := 220.0
const CLIFF_W := 6.0
const RAMP_W := 180.0


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


static func ground_x_range(i: int) -> Vector2:
	return Vector2(JUNGLE_X0, JUNGLE_X1) if is_jungle(i) else Vector2(COL_W, WORLD_W - COL_W)


## Surface height of floor i at x (FLOORS[i] where flat; smaller = higher).
static func ground_y(i: int, x: float) -> float:
	return FLOORS[i] + ground_offset(i, x)


static func ground_offset(i: int, x: float) -> float:
	var off := _terrain_offset(i, x)
	if i == STRUCTURE_FLOOR:
		var d := minf(x, WORLD_W - x)
		for px: float in STRUCTURE_X.values():
			var k := clampf((absf(d - px) - PAD_HALF) / PAD_RAMP, 0.0, 1.0)
			if k < 1.0:
				off = lerpf(roundf(_terrain_offset(i, px)), off, k * k * (3.0 - 2.0 * k))
	return off


static func _terrain_offset(i: int, x: float) -> float:
	var r := ground_x_range(i)
	if x <= r.x or x >= r.y:
		return 0.0
	var d := minf(x, WORLD_W - x)  # mirrored coordinate
	var ph := i * 1.7
	var n := 0.55 * sin(d * 0.0042 + ph) + 0.3 * sin(d * 0.0105 + ph * 2.3) + 0.15 * sin(d * 0.021 + ph * 0.7)
	var hills := HILL_AMP[i] * pow((n + 1.0) * 0.5, 1.6)
	return -(hills + _plateau(i, d)) * _envelope(i, x)


static func _plateau(i: int, d: float) -> float:
	var best := 0.0
	for p: Array in PLATEAUS.get(i, []):
		var wl: float = CLIFF_W if p[3] else RAMP_W
		var wr: float = CLIFF_W if p[4] else RAMP_W
		var el := clampf((d - p[0]) / wl, 0.0, 1.0)
		var er := clampf((p[1] - d) / wr, 0.0, 1.0)
		var e := minf(el * el * (3.0 - 2.0 * el), er * er * (3.0 - 2.0 * er))
		best = maxf(best, p[2] * e)
	return best


## Places that must stay flat on floor i: its own bridges, stairs standing on it, base entrances.
static func anchors(i: int) -> Array[float]:
	var r := ground_x_range(i)
	var out: Array[float] = [r.x, r.y]
	if BRIDGES.has(i):
		out.append_array(BRIDGES[i])
	if BRIDGES.has(i - 1):
		out.append_array(BRIDGES[i - 1])
	return out


static func _envelope(i: int, x: float) -> float:
	var e := 1.0
	for a in anchors(i):
		var k := clampf((absf(x - a) - HILL_FLAT) / HILL_RAMP, 0.0, 1.0)
		e *= k * k * (3.0 - 2.0 * k)
	return e


## Climbing ledges under the bridge at (x, floor i): from the floor of band i+1 up to the bridge.
## The top ledge is centred under the opening so you can jump straight through it.
static func stair(i: int, x: float) -> Array[Rect2]:
	var out: Array[Rect2] = []
	var bridge_y := FLOORS[i]
	var ground := FLOORS[i + 1]
	var k := 1
	var side := 1.0 if x < WORLD_W * 0.5 else -1.0
	while bridge_y + STAIR_STEP * k < ground - 60.0:
		var cx := x if k % 2 == 1 else x + side * STAIR_SHIFT
		out.append(Rect2(cx - STAIR_W * 0.5, bridge_y + STAIR_STEP * k, STAIR_W, 12))
		k += 1
	return out


## Builds collision geometry and a description of every platform for the art:
## {"solids", "one_ways", "pads", "grounds", "platforms": [{"rect", "kind", "band"}]}
## kinds: &"column" (base ledges), &"bridge", &"stair" (jungle climbs), &"outcrop" (lane-side climbs).
static func build() -> Dictionary:
	var solids: Array[Rect2] = []
	var one_ways: Array[Rect2] = []
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
		for c: float in BRIDGES[i]:
			solids.append(Rect2(cur, fy, c - BRIDGE_W / 2.0 - cur, FLOOR_T))
			_one_way(one_ways, platforms, Rect2(c - BRIDGE_W / 2.0, fy, BRIDGE_W, 12), &"bridge")
			cur = c + BRIDGE_W / 2.0
			for r in stair(i, c):
				_one_way(one_ways, platforms, r, &"outcrop" if is_jungle(i) else &"stair")
		solids.append(Rect2(cur, fy, WORLD_W - COL_W - cur, FLOOR_T))
	for b in [1, 3]:                                                    # rock closing the jungle bands
		var y0 := FLOORS[b - 1] + FLOOR_T
		var h := FLOORS[b] - y0
		solids.append(Rect2(COL_W, y0, JUNGLE_X0 - COL_W, h))
		solids.append(Rect2(JUNGLE_X1, y0, WORLD_W - COL_W - JUNGLE_X1, h))
	var y := FLOORS[4] - 135.0
	while y > TOP + 110.0:                                              # climbing ledges in the base columns
		var near_floor := false
		for f in FLOORS:
			if absf(f - y) < 50.0:
				near_floor = true
		if not near_floor:
			for x0 in [40.0, WORLD_W - COL_W + 40.0]:
				_one_way(one_ways, platforms, Rect2(x0, y, COL_W - 80.0, 12), &"column")
		y -= 135.0
	var grounds: Array[GroundStrip] = []
	for i in FLOORS.size():
		var r := ground_x_range(i)
		var cuts: Array[float] = [r.x]
		if BRIDGES.has(i):
			for c: float in BRIDGES[i]:
				cuts.append(c - BRIDGE_W / 2.0)
				cuts.append(c + BRIDGE_W / 2.0)
		cuts.append(r.y)
		for ci in range(0, cuts.size(), 2):
			grounds.append(_make_ground(i, cuts[ci], cuts[ci + 1]))
	var pads: Array[Vector2] = []
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
