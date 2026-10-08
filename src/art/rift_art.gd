@tool
class_name RiftArt
extends Node2D
## Builds all of the map's visuals procedurally (no image assets) from RiftLayout:
## per band a sky gradient, light shafts, far and mid parallax tree layers, fog, ground decor,
## particles and a swaying foreground; plus rock, platforms, jump pads and the two base sanctuaries.
## Art is split into ArtChunk nodes so off-screen pieces are culled. Runs in the editor too (@tool).

const Z_SKY := -60
const Z_GLOW := -56
const Z_FAR := -50
const Z_SHAFT := -46
const Z_MID := -40
const Z_HAZE := -38
const Z_WISPS := -37
const Z_BIRDS := -48
const Z_CRITTERS := -7
const Z_FOG := -36
const Z_COLUMN := -30
const Z_PARTICLES := -14
const Z_ROCK := -10
const Z_DECOR := -8
const Z_LIGHT := -6
const Z_FRONT := 20
const CHUNK := 800.0
const W := RiftLayout.WORLD_W
const S := RiftLayout.Season

const SWAY_SHADER := preload("res://src/art/sway.gdshader")
const FLICKER_SHADER := preload("res://src/art/flicker.gdshader")
const TORII_X: Array[float] = [1150.0, 2650.0, 3750.0, 5250.0]  ## winter lane gates (mirrored)

@export var art_seed := 7
@export var rebuild := false:
	set(value):
		if value and is_inside_tree():
			_build()

var _add: CanvasItemMaterial
var _sway: ShaderMaterial
var _sway_soft: ShaderMaterial
var _flicker: ShaderMaterial


func _ready() -> void:
	_build()


func _build() -> void:
	for c in get_children():
		c.free()
	_add = CanvasItemMaterial.new()
	_add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_sway = ShaderMaterial.new()
	_sway.shader = SWAY_SHADER
	_sway_soft = ShaderMaterial.new()
	_sway_soft.shader = SWAY_SHADER
	_sway_soft.set_shader_parameter("amplitude", 1.6)
	_sway_soft.set_shader_parameter("speed", 0.8)
	_flicker = ShaderMaterial.new()
	_flicker.shader = FLICKER_SHADER
	var g := RiftLayout.build()
	for b in RiftLayout.FLOORS.size():
		_build_band(b)
	_build_columns()
	_build_rock(g["solids"])
	_build_platforms(g["platforms"])
	_build_pads(g["pads"])


# ------------------------------------------------------------------ helpers

func _layer(factor: float, z: int, layer_name: String) -> Node2D:
	var n: Node2D
	if is_equal_approx(factor, 1.0):
		n = Node2D.new()
	else:
		var p := ParallaxNode.new()
		p.factor = factor
		n = p
	n.name = layer_name
	n.z_index = z
	add_child(n)
	return n


func _chunk(parent: Node2D, paint: Callable, mat: Material = null) -> void:
	var c := ArtChunk.new()
	c.paint = paint
	c.material = mat
	parent.add_child(c)


func _rng(a: int, b: int, c: float) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash([art_seed, a, b, int(c)])
	return r


## Chunk start positions covering [x0, x1).
func _chunks(x0: float, x1: float) -> Array[float]:
	var out: Array[float] = []
	var x := floorf(x0 / CHUNK) * CHUNK
	while x < x1:
		out.append(x)
		x += CHUNK
	return out


func _gy(b: int, x: float) -> float:
	return RiftLayout.ground_y(b, x)


func _near_torii(b: int, x: float, margin: float) -> bool:
	if RiftLayout.BAND_SEASON[b] != S.WINTER:
		return false
	for t in TORII_X:
		if absf(x - t) < margin:
			return true
	return false


func _lane_x_range(b: int) -> Vector2:
	return Vector2(RiftLayout.JUNGLE_X0, RiftLayout.JUNGLE_X1) if RiftLayout.is_jungle(b) else Vector2(RiftLayout.COL_W, W - RiftLayout.COL_W)


func _near_connector_or_pad(b: int, x: float, margin: float) -> bool:
	for i in [b - 1, b]:
		if i >= 0 and RiftLayout.CONNECTORS.has(i):
			for c: float in RiftLayout.CONNECTORS[i]:
				if absf(x - c) < margin:
					return true
	return false


# ------------------------------------------------------------------ bands

func _build_band(b: int) -> void:
	var p := SeasonPalette.for_band(b)
	var season: RiftLayout.Season = RiftLayout.BAND_SEASON[b]
	var top := RiftLayout.band_top(b)
	var floor_y: float = RiftLayout.FLOORS[b]
	var h := floor_y - top

	var sky := _layer(1.0, Z_SKY, "Sky%d" % b)
	_chunk(sky, func(ci: CanvasItem) -> void:
		Painter.gradient_rect(ci, Rect2(-400, top - 2, W + 800, h + 24), p["sky_top"], p["sky_bottom"]))

	var glow_layer := _layer(0.05, Z_GLOW, "Glow%d" % b)
	var gr := ParallaxNode.content_range(0.05)
	_chunk(glow_layer, func(ci: CanvasItem) -> void:
		var r := _rng(b, 0, 0)
		for k in 3:
			var x := lerpf(gr.x + 300.0, gr.y - 300.0, (k + r.randf_range(0.2, 0.8)) / 3.0)
			if season == S.WINTER:
				if k == 1:  # the moon
					var mc := Vector2(x, top + h * 0.3)
					Painter.glow(ci, mc, h * 1.1, Color(p["moon"], 0.35))
					Painter.glow(ci, mc, 70.0, Color(p["moon"], 0.5))
					ci.draw_circle(mc, 34.0, Color(p["moon"], 0.85))
				continue
			Painter.glow(ci, Vector2(x, top + h * r.randf_range(0.2, 0.45)), h * r.randf_range(0.7, 1.0), Color(p["glow"], 0.32)), _add)

	var shafts := _layer(0.15, Z_SHAFT, "Shafts%d" % b)
	var sr := ParallaxNode.content_range(0.15)
	for x0 in _chunks(sr.x, sr.y):
		_chunk(shafts, func(ci: CanvasItem) -> void: _paint_shafts(ci, b, p, x0, top, floor_y), _add)

	var far := _layer(0.3, Z_FAR, "Far%d" % b)
	var fr := ParallaxNode.content_range(0.3)
	for x0 in _chunks(fr.x, fr.y):
		_chunk(far, func(ci: CanvasItem) -> void: _paint_far(ci, b, season, p, x0, top, floor_y))

	var mid := _layer(0.6, Z_MID, "Mid%d" % b)
	var mr := ParallaxNode.content_range(0.6)
	for x0 in _chunks(mr.x, mr.y):
		_chunk(mid, func(ci: CanvasItem) -> void: _paint_mid(ci, b, season, p, x0, top, floor_y), _sway_soft)

	var haze := _layer(1.0, Z_HAZE, "Haze%d" % b)
	var haze_alpha: float = {S.WINTER: 0.22, S.SPRING: 0.2, S.SUMMER: 0.14, S.FALL: 0.18}[season]
	_chunk(haze, func(ci: CanvasItem) -> void:
		Painter.gradient_rect(ci, Rect2(-400, top, W + 800, h), Color(p["fog"], haze_alpha * 0.6), Color(p["fog"], haze_alpha)))

	var wisps := FogWisps.new()
	wisps.name = "Wisps%d" % b
	wisps.z_index = Z_WISPS
	add_child(wisps)
	wisps.setup(Rect2(-400, top, W + 800, h), Color(p["fog"]), hash([art_seed, b, "wisps"]))

	var fog := _layer(1.0, Z_FOG, "Fog%d" % b)
	_chunk(fog, func(ci: CanvasItem) -> void:
		Painter.fade_band(ci, -400, W + 400, floor_y + 4, -h * 0.32, Color(p["fog"], 0.42))
		Painter.fade_band(ci, -400, W + 400, top, h * 0.18, Color(p["near"], 0.35)))

	var decor := _layer(1.0, Z_DECOR, "Decor%d" % b)
	var lights := _layer(1.0, Z_LIGHT, "Lights%d" % b)
	var lr := _lane_x_range(b)
	for x0 in _chunks(lr.x, lr.y):
		_chunk(decor, func(ci: CanvasItem) -> void: _paint_decor(ci, b, season, p, maxf(x0, lr.x), minf(x0 + CHUNK, lr.y), floor_y))
		_chunk(lights, func(ci: CanvasItem) -> void: _paint_lantern_glows(ci, b, p, maxf(x0, lr.x), minf(x0 + CHUNK, lr.y)), _flicker)

	var front := _layer(1.2, Z_FRONT, "Front%d" % b)
	var frr := ParallaxNode.content_range(1.2)
	for x0 in _chunks(frr.x, frr.y):
		_chunk(front, func(ci: CanvasItem) -> void: _paint_front(ci, b, season, p, x0, top, floor_y), _sway)

	var particles := SeasonParticles.new()
	particles.name = "Particles%d" % b
	particles.z_index = Z_PARTICLES
	add_child(particles)
	particles.configure(season, p, Rect2(lr.x, top, lr.y - lr.x, h))

	var critters := Critters.new()
	critters.name = "Critters%d" % b
	var area := Rect2(lr.x, top, lr.y - lr.x, h)
	match season:
		S.SPRING:
			critters.z_index = Z_CRITTERS
			critters.setup(Critters.Kind.BUTTERFLY, area, [Color("ffd9e7"), Color("fff6e0"), Color("f4a9c6"), Color("ffe08a")] as Array[Color], hash([art_seed, b, "c"]))
		S.SUMMER:
			critters.z_index = Z_CRITTERS
			critters.material = _add
			critters.setup(Critters.Kind.FIREFLY, area, [Color(p["particle"])] as Array[Color], hash([art_seed, b, "c"]))
		_:
			critters.z_index = Z_BIRDS
			critters.setup(Critters.Kind.BIRD, area, [Color(p["near"]).lerp(Color(p["far"]), 0.3)] as Array[Color], hash([art_seed, b, "c"]))
	add_child(critters)


func _paint_shafts(ci: CanvasItem, b: int, p: Dictionary, x0: float, top: float, floor_y: float) -> void:
	var r := _rng(b, 1, x0)
	var shaft: Color = p["shaft"]
	var h := floor_y - top
	for k in r.randi_range(1, 2):
		var x := x0 + r.randf_range(0, CHUNK)
		var wt := r.randf_range(30, 80)
		var drift := h * r.randf_range(0.35, 0.6)
		var wb := wt * r.randf_range(2.0, 3.0)
		var a := Color(shaft, shaft.a * r.randf_range(0.6, 1.4))
		ci.draw_polygon(PackedVector2Array([
			Vector2(x, top), Vector2(x + wt, top), Vector2(x + drift + wb, floor_y), Vector2(x + drift, floor_y)]),
			PackedColorArray([a, a, Color(a, 0.0), Color(a, 0.0)]))


func _tree(ci: CanvasItem, season: RiftLayout.Season, base: Vector2, th: float, body: Color, leaves: Array,
		accent: Color, accent_count: int, snow: Color, r: RandomNumberGenerator) -> void:
	match season:
		S.WINTER:
			Painter.matsu(ci, base, th, body.darkened(0.15), leaves[r.randi() % leaves.size()], snow, r)
		S.SUMMER:
			Painter.jungle_tree(ci, base, th, body, leaves, body, r)
		_:
			Painter.round_tree(ci, base, th, th * r.randf_range(0.28, 0.36), body, leaves, accent, accent_count, r)


func _paint_far(ci: CanvasItem, b: int, season: RiftLayout.Season, p: Dictionary, x0: float, top: float, floor_y: float) -> void:
	var r := _rng(b, 2, x0)
	var h := floor_y - top
	var far: Color = p["far"]
	var sky_bottom: Color = p["sky_bottom"]
	if season == S.WINTER:
		Painter.peak(ci, Vector2(x0 + r.randf_range(100, CHUNK - 100), floor_y), h * r.randf_range(0.6, 0.85), r.randf_range(520, 760), far.lerp(sky_bottom, 0.5), Color(p["accent2"], 0.8))
	if not RiftLayout.is_jungle(b):
		Painter.ridge(ci, x0 - 40, x0 + CHUNK + 40, floor_y, h * 0.42, far.lerp(sky_bottom, 0.45), r, 40.0)
	if season == S.WINTER and r.randf() < 0.55:
		Painter.pagoda(ci, Vector2(x0 + r.randf_range(80, CHUNK - 80), floor_y - h * 0.18), h * r.randf_range(0.42, 0.55), far.darkened(0.12), Color(p["accent2"], 0.7))
	var x := x0
	while x < x0 + CHUNK:
		var th := h * r.randf_range(0.32, 0.62)
		var col := far.lerp(sky_bottom, r.randf_range(0.0, 0.3))
		_tree(ci, season, Vector2(x, floor_y + 6), th, col, [col.darkened(0.04), col, col.lightened(0.05)],
			col.lightened(0.18), 6 if season == S.SPRING else 0, Color(p["accent"], 0.55), r)
		x += r.randf_range(110, 180) if season == S.WINTER else r.randf_range(45, 95)
	if RiftLayout.is_jungle(b):
		x = x0
		while x < x0 + CHUNK:
			Painter.hanging_vine(ci, Vector2(x, top - 4), r.randf_range(30, h * 0.45), far.darkened(0.1), r)
			x += r.randf_range(25, 60)


func _paint_mid(ci: CanvasItem, b: int, season: RiftLayout.Season, p: Dictionary, x0: float, top: float, floor_y: float) -> void:
	var r := _rng(b, 3, x0)
	var h := floor_y - top
	var body: Color = p["mid"]
	var leaves: Array = []
	for c: Color in p["foliage"]:
		leaves.append(c if season == S.WINTER else c.lerp(body, 0.45 if season == S.FALL else 0.55))
	var accent: Color = p["accent"]
	var x := x0 + r.randf_range(0, 80)
	while x < x0 + CHUNK:
		var th := h * r.randf_range(0.55, 0.92)
		var count := 0
		match season:
			S.SPRING: count = 26
			S.FALL: count = 14
		_tree(ci, season, Vector2(x, floor_y + 10), th, body, leaves, accent.lerp(Color(p["fog"]), 0.3), count, Color(p["accent"], 0.92), r)
		x += r.randf_range(210, 340) if season == S.WINTER else r.randf_range(110, 210)
	if RiftLayout.is_jungle(b):
		x = x0
		while x < x0 + CHUNK:
			Painter.hanging_vine(ci, Vector2(x, top - 4), r.randf_range(40, h * 0.6), body.darkened(0.15), r)
			x += r.randf_range(35, 80)
	elif season == S.FALL:
		for k in 10:  # leaves lying in the mid distance
			Painter.blob(ci, Vector2(x0 + r.randf_range(0, CHUNK), floor_y + 2), Vector2(r.randf_range(14, 30), 6), leaves[r.randi() % leaves.size()], r, 10, 0.2)


func _paint_decor(ci: CanvasItem, b: int, season: RiftLayout.Season, p: Dictionary, x0: float, x1: float, _floor_y: float) -> void:
	var r := _rng(b, 4, x0)
	var near: Color = p["near"]
	var cap: Color = p["cap"]
	var cap2: Color = p["cap2"]
	var accent: Color = p["accent"]
	# Bushes and rocks sitting on the ground, slightly lifted from the darkness.
	var x := x0 + r.randf_range(20, 120)
	while x < x1:
		if not _near_connector_or_pad(b, x, 110.0) and not _near_torii(b, x, 150.0):
			var gy := _gy(b, x)
			var bush := near.lerp(p["mid"], 0.35)
			match season:
				S.WINTER:
					if r.randf() < 0.55:
						Painter.camellia(ci, Vector2(x, gy + 4), r.randf_range(20, 30), Color("1b2a33"), Color(p["camellia"]), cap, r)
					else:
						Painter.blob(ci, Vector2(x, gy - 8), Vector2(r.randf_range(30, 46), 11), cap2, r, 14, 0.12)
						Painter.blob(ci, Vector2(x + 6, gy - 12), Vector2(r.randf_range(20, 30), 8), cap, r, 14, 0.1)
				_:
					for k in r.randi_range(2, 4):
						var bx := x + r.randf_range(-30, 30)
						Painter.blob(ci, Vector2(bx, _gy(b, bx) - r.randf_range(4, 14)), Vector2(r.randf_range(18, 34), r.randf_range(12, 22)), bush, r, 12, 0.18)
			match season:
				S.SPRING:
					for k in 5:
						ci.draw_circle(Vector2(x + r.randf_range(-34, 34), gy - r.randf_range(10, 26)), r.randf_range(2, 3.5), accent)
				S.FALL:
					for k in 6:
						ci.draw_circle(Vector2(x + r.randf_range(-34, 34), gy - r.randf_range(8, 24)), r.randf_range(2.5, 4), [cap, cap2, accent][k % 3])
				S.SUMMER:
					ci.draw_circle(Vector2(x + 18, gy - 9), 4.0, Color(p["accent"], 0.9))
		x += r.randf_range(140, 320)
	# Grass, ferns and small seasonal details all along the ground.
	x = x0
	while x < x1:
		if not _near_connector_or_pad(b, x, 80.0):
			var gy := _gy(b, x)
			match season:
				S.WINTER:
					if r.randf() < 0.35:
						Painter.tuft(ci, Vector2(x, gy + 1), r.randf_range(8, 13), Color("3b4a63"), r, 3)
				S.SPRING:
					Painter.tuft(ci, Vector2(x, gy + 1), r.randf_range(10, 20), cap.darkened(0.25), r, 4)
					if r.randf() < 0.35:
						var stem := Vector2(x + 3, gy)
						ci.draw_line(stem, stem + Vector2(1, -14), cap.darkened(0.3), 1.5)
						ci.draw_circle(stem + Vector2(1, -15), 2.6, [accent, Color("fff6e0"), p["accent2"]][r.randi() % 3])
				S.SUMMER:
					Painter.tuft(ci, Vector2(x, gy + 1), r.randf_range(14, 28), cap.darkened(0.2), r, 6)
				S.FALL:
					Painter.tuft(ci, Vector2(x, gy + 1), r.randf_range(8, 14), Color("6b4a2a"), r, 3)
					Painter.blob(ci, Vector2(x + 8, gy - 2), Vector2(r.randf_range(6, 12), 3.5), [cap, cap2, Color(accent, 1)][r.randi() % 3], r, 8, 0.25)
		x += r.randf_range(14, 34)
	if season == S.WINTER:
		_paint_shrine(ci, b, p, x0, x1, r)
	# Lanterns (their light is drawn by _paint_lantern_glows).
	for lx in _lantern_positions(b, x0, x1):
		if season == S.WINTER:
			Painter.toro(ci, Vector2(lx, _gy(b, lx)), 70.0, Color("39435a"), Color(p["lamp"]), cap)
		else:
			Painter.lantern(ci, Vector2(lx, _gy(b, lx)), 92, near, Color(p["glow"], 0.9))


## Winter lane: vermilion torii you walk under, with paper lanterns, and bamboo fences.
func _paint_shrine(ci: CanvasItem, b: int, p: Dictionary, x0: float, x1: float, r: RandomNumberGenerator) -> void:
	var cap: Color = p["cap"]
	for tx in TORII_X:
		if tx < x0 or tx >= x1:
			continue
		var h := 210.0
		var half := h * 0.5 * 0.78
		Painter.torii(ci, tx, _gy(b, tx - half), _gy(b, tx + half), h, Color(p["torii"]), Color("1a1420"), cap)
		var beam_y := minf(_gy(b, tx - half), _gy(b, tx + half)) - h + h * 0.27
		for side: float in [-1.0, 1.0]:
			Painter.chochin(ci, Vector2(tx + side * h * 0.22, beam_y), 18.0, Color(p["lamp"]).lerp(Color("ffffff"), 0.15), Color("1a1420"))
	var fx := x0 + r.randf_range(100, 500)
	if fx + 120.0 < x1 and not _near_connector_or_pad(b, fx, 160.0) and not _near_torii(b, fx + 60.0, 220.0):
		Painter.bamboo_fence(ci, fx, fx + 112.0, func(x: float) -> float: return _gy(b, x) + 2.0, 34.0, Color("4a5a3a"), cap)


func _lantern_positions(b: int, x0: float, x1: float) -> Array[float]:
	var out: Array[float] = []
	var r := _rng(b, 5, x0)
	var x := x0 + r.randf_range(200, 600)
	while x < x1 - 40:
		if not _near_connector_or_pad(b, x, 140.0) and absf(x - 3200.0) > 160.0 and not _near_torii(b, x, 200.0):
			out.append(x)
		x += r.randf_range(600, 900)
	return out


func _paint_lantern_glows(ci: CanvasItem, b: int, p: Dictionary, x0: float, x1: float) -> void:
	var winter := RiftLayout.BAND_SEASON[b] == S.WINTER
	for lx in _lantern_positions(b, x0, x1):
		var gy := _gy(b, lx)
		var c := Vector2(lx, gy - 46) if winter else Vector2(lx + 14, gy - 82)
		Painter.glow(ci, c, 150.0, Color(p["glow"], 0.42))
		Painter.glow(ci, c, 26.0 if winter else 30.0, Color(1, 1, 1, 0.8))
	if winter:
		for tx in TORII_X:
			if tx < x0 or tx >= x1:
				continue
			var half := 210.0 * 0.5 * 0.78
			var beam_y := minf(_gy(b, tx - half), _gy(b, tx + half)) - 210.0 + 210.0 * 0.27
			for side: float in [-1.0, 1.0]:
				var c := Vector2(tx + side * 210.0 * 0.22, beam_y + 20.0)
				Painter.glow(ci, c, 110.0, Color(p["lamp"], 0.5))
				Painter.glow(ci, c, 22.0, Color(1, 0.95, 0.85, 0.7))


func _paint_front(ci: CanvasItem, b: int, season: RiftLayout.Season, p: Dictionary, x0: float, top: float, floor_y: float) -> void:
	var r := _rng(b, 6, x0)
	var near: Color = p["near"]
	var accent: Color = p["accent"]
	for k in r.randi_range(1, 2):
		var x := x0 + r.randf_range(0, CHUNK)
		var t := Vector2(x, top - 6)
		match season:
			S.WINTER:
				for i in r.randi_range(4, 8):
					Painter.icicle(ci, t + Vector2(i * 14 + r.randf_range(-4, 4), 0), r.randf_range(25, 70), Color(near, 0.95))
				Painter.blob(ci, t + Vector2(50, 4), Vector2(80, 18), near, r, 14, 0.2)
			S.SUMMER:
				for i in r.randi_range(4, 7):
					Painter.hanging_vine(ci, t + Vector2(i * 18, 0), r.randf_range(60, 140), near, r)
				Painter.blob(ci, t + Vector2(60, 6), Vector2(90, 22), near, r, 14, 0.25)
				for i in 3:
					Painter.frond(ci, t + Vector2(40 + i * 30, 10), t + Vector2(20 + i * 50, r.randf_range(70, 110)), 14, near)
			S.SPRING:
				var tip := t + Vector2(r.randf_range(140, 220), r.randf_range(60, 100))
				Painter.branch(ci, t, tip, 7.0, near)
				Painter.branch(ci, t.lerp(tip, 0.5), t.lerp(tip, 0.5) + Vector2(50, -10), 4.0, near)
				for i in 16:
					ci.draw_circle(t.lerp(tip, r.randf()) + Vector2(r.randf_range(-16, 16), r.randf_range(-10, 14)), r.randf_range(3, 6), accent.darkened(0.35))
			S.FALL:
				var tip := t + Vector2(r.randf_range(140, 220), r.randf_range(50, 90))
				Painter.branch(ci, t, tip, 6.0, near)
				Painter.branch(ci, t.lerp(tip, 0.6), t.lerp(tip, 0.6) + Vector2(30, 40), 3.0, near)
				for i in 7:
					Painter.blob(ci, t.lerp(tip, r.randf()) + Vector2(r.randf_range(-12, 12), r.randf_range(-6, 12)), Vector2(7, 4), (p["foliage"] as Array)[i % 3], r, 8, 0.2)
	if r.randf() < 0.7:  # tall grass silhouettes in front of the floor edge
		var gx := x0 + r.randf_range(0, CHUNK)
		for i in r.randi_range(4, 9):
			Painter.tuft(ci, Vector2(gx + i * 9, maxf(_gy(b, gx), floor_y - 40.0) + 34), r.randf_range(40, 70), near, r, 3)


# ------------------------------------------------------------------ rock and structures

func _build_rock(solids: Array) -> void:
	var rock := _layer(1.0, Z_ROCK, "Rock")
	for rect: Rect2 in solids:
		var x0 := maxf(rect.position.x, -300.0)
		var x1 := minf(rect.end.x, W + 300.0)
		for cx in _chunks(x0, x1):
			var piece := Rect2(maxf(cx, x0), rect.position.y, minf(cx + CHUNK, x1) - maxf(cx, x0), rect.size.y)
			_chunk(rock, func(ci: CanvasItem) -> void: _paint_rock(ci, piece, rect))


func _paint_rock(ci: CanvasItem, piece: Rect2, whole: Rect2) -> void:
	var r := _rng(int(whole.position.y), int(whole.position.x), piece.position.x)
	var b_above := RiftLayout.band_of(whole.position.y - 1.0)
	var b_below := RiftLayout.band_of(whole.end.y + 50.0)
	var p_top := SeasonPalette.for_band(b_above)
	var p_bottom := SeasonPalette.for_band(b_below)
	var is_floor := RiftLayout.FLOORS.has(whole.position.y) and whole.size.y <= RiftLayout.FLOOR_T + 1.0 or whole.position.y == RiftLayout.FLOORS[4]
	var is_wall := whole.position.y > RiftLayout.TOP and not is_floor
	var p := SeasonPalette.for_band(RiftLayout.band_of(whole.get_center().y)) if is_wall else p_top
	var rock: Color = p["rock"]
	ci.draw_rect(piece, rock)
	var floor_index := RiftLayout.FLOORS.find(whole.position.y) if is_floor else -1
	if floor_index >= 0:  # rolling hills rise above the flat floor rect
		var hill := PackedVector2Array([Vector2(piece.end.x, piece.position.y + 2), Vector2(piece.position.x, piece.position.y + 2)])
		var hx := piece.position.x
		while hx < piece.end.x:
			hill.append(Vector2(hx, _gy(floor_index, hx)))
			hx += 12.0
		hill.append(Vector2(piece.end.x, _gy(floor_index, piece.end.x)))
		ci.draw_colored_polygon(hill, rock)
	# texture: darker and lighter pebbles
	var n := int(clampf(piece.get_area() / 3500.0, 4, 70))
	for k in n:
		var c := Vector2(r.randf_range(piece.position.x, piece.end.x), r.randf_range(piece.position.y + 6, piece.end.y))
		Painter.blob(ci, c, Vector2(r.randf_range(6, 22), r.randf_range(4, 12)), rock.lightened(0.05) if k % 3 == 0 else rock.darkened(0.25), r, 9, 0.25)
	if is_floor:
		_paint_cap(ci, piece, p_top, RiftLayout.BAND_SEASON[b_above], r, floor_index)
	if whole.position.y < RiftLayout.TOP or (is_floor and whole.position.y < RiftLayout.FLOORS[4]):
		_paint_underside(ci, piece, p_bottom, RiftLayout.BAND_SEASON[b_below], r)
	if is_wall:
		var rim: Color = p["rock_rim"]
		for edge_x in [whole.position.x, whole.end.x]:
			if edge_x > piece.position.x - 1.0 and edge_x < piece.end.x + 1.0 and edge_x > RiftLayout.COL_W + 1.0 and edge_x < W - RiftLayout.COL_W - 1.0:
				var y := piece.position.y
				while y < piece.end.y:
					Painter.blob(ci, Vector2(edge_x, y), Vector2(r.randf_range(10, 22), r.randf_range(14, 26)), rock, r, 10, 0.2)
					y += r.randf_range(16, 30)
				ci.draw_line(Vector2(edge_x, piece.position.y), Vector2(edge_x, piece.end.y), Color(rim, 0.25), 2.0)
				var vy := piece.position.y
				while vy < piece.end.y - 60:
					Painter.hanging_vine(ci, Vector2(edge_x + (8.0 if edge_x == whole.end.x else -8.0), vy), r.randf_range(30, 80), Color(p["cap"]).darkened(0.3), r)
					vy += r.randf_range(50, 110)


func _paint_cap(ci: CanvasItem, piece: Rect2, p: Dictionary, season: RiftLayout.Season, r: RandomNumberGenerator, floor_index := -1) -> void:
	var rim: Color = p["rock_rim"]
	var surface := func(px: float) -> float: return _gy(floor_index, px) if floor_index >= 0 else piece.position.y
	var rim_line := PackedVector2Array()
	var rx := piece.position.x
	while rx <= piece.end.x:
		rim_line.append(Vector2(rx, surface.call(rx) + 1.0))
		rx += 12.0
	ci.draw_polyline(rim_line, Color(rim, 0.55), 2.0, true)
	var cap: Color = p["cap"]
	var cap2: Color = p["cap2"]
	var x := piece.position.x
	while x < piece.end.x:
		var y: float = surface.call(x)
		match season:
			S.WINTER:
				Painter.blob(ci, Vector2(x, y + 3), Vector2(r.randf_range(12, 22), r.randf_range(5, 8)), cap if r.randf() < 0.7 else cap2, r, 10, 0.12)
			S.SPRING:
				Painter.blob(ci, Vector2(x, y + 4), Vector2(r.randf_range(10, 18), r.randf_range(4, 7)), cap if r.randf() < 0.6 else cap2, r, 10, 0.2)
			S.SUMMER:
				Painter.blob(ci, Vector2(x, y + 4), Vector2(r.randf_range(10, 18), r.randf_range(4, 7)), cap.darkened(0.15), r, 10, 0.2)
			S.FALL:
				Painter.blob(ci, Vector2(x, y + 3), Vector2(r.randf_range(8, 14), r.randf_range(3, 6)), [cap, cap2, Color(p["accent2"])][r.randi() % 3], r, 9, 0.25)
		x += r.randf_range(10, 20)


func _paint_underside(ci: CanvasItem, piece: Rect2, p: Dictionary, season: RiftLayout.Season, r: RandomNumberGenerator) -> void:
	var y := piece.end.y
	var x := piece.position.x + r.randf_range(0, 40)
	var rock: Color = p["rock"]
	while x < piece.end.x:
		Painter.blob(ci, Vector2(x, y - 2), Vector2(r.randf_range(10, 26), r.randf_range(5, 12)), rock, r, 10, 0.25)
		match season:
			S.WINTER:
				if r.randf() < 0.6:
					Painter.icicle(ci, Vector2(x + r.randf_range(-10, 10), y), r.randf_range(12, 40), Color(p["accent2"], 0.85))
			S.SUMMER:
				if r.randf() < 0.55:
					Painter.hanging_vine(ci, Vector2(x, y), r.randf_range(25, 110), Color(p["cap"]).darkened(0.25), r)
			S.SPRING:
				if r.randf() < 0.35:
					var root_end := Vector2(x + r.randf_range(-20, 20), y + r.randf_range(20, 60))
					Painter.branch(ci, Vector2(x, y), root_end, 2.0, Color(p["mid"]))
					ci.draw_circle(root_end, 3.0, Color(p["accent"]))
			S.FALL:
				if r.randf() < 0.35:
					var root_end := Vector2(x + r.randf_range(-20, 20), y + r.randf_range(20, 55))
					Painter.branch(ci, Vector2(x, y), root_end, 2.0, Color(p["mid"]))
					Painter.blob(ci, root_end, Vector2(6, 4), Color(p["cap"]), r, 8, 0.2)
		x += r.randf_range(24, 52)


func _build_columns() -> void:
	var back := _layer(1.0, Z_COLUMN, "Sanctuaries")
	var glows := _layer(1.0, Z_LIGHT, "SanctuaryLights")
	for team in [0, 1]:
		var x0 := 0.0 if team == 0 else W - RiftLayout.COL_W
		var tc := Color("4ea4ff") if team == 0 else Color("ff5b5e")
		for cy in _chunks(RiftLayout.TOP, RiftLayout.FLOORS[4]):
			var seg := Rect2(x0, maxf(cy, RiftLayout.TOP), RiftLayout.COL_W, minf(cy + CHUNK, RiftLayout.FLOORS[4]) - maxf(cy, RiftLayout.TOP))
			_chunk(back, func(ci: CanvasItem) -> void: _paint_column(ci, seg, tc, team))
		_chunk(glows, func(ci: CanvasItem) -> void:
			for lane in RiftLayout.LANES:
				var fy: float = RiftLayout.FLOORS[lane]
				Painter.glow(ci, Vector2(x0 + RiftLayout.COL_W * 0.5, fy - 150), 240.0, Color(tc, 0.45))
			Painter.glow(ci, Vector2(x0 + RiftLayout.COL_W * 0.5, RiftLayout.FLOORS[2] - 150), 90.0, Color(1, 1, 1, 0.55)), _add)


func _paint_column(ci: CanvasItem, seg: Rect2, tc: Color, team: int) -> void:
	var stone := Color("12161e")
	Painter.gradient_rect(ci, seg, stone.lerp(tc, 0.06), stone.darkened(0.2))
	var r := _rng(9, team, seg.position.y)
	# pillars on both sides and carved arches between floors
	for side in [seg.position.x + 14.0, seg.end.x - 14.0]:
		ci.draw_rect(Rect2(side - 12, seg.position.y, 24, seg.size.y), Color("0b0e13"))
		ci.draw_line(Vector2(side - 12, seg.position.y), Vector2(side - 12, seg.end.y), Color(tc, 0.25), 2.0)
	for lane in RiftLayout.LANES:
		var fy: float = RiftLayout.FLOORS[lane]
		if fy < seg.position.y or fy - 360.0 > seg.end.y:
			continue
		var cx := seg.position.x + seg.size.x * 0.5
		ci.draw_arc(Vector2(cx, fy - 200), 150.0, PI, TAU, 32, Color(tc, 0.35), 3.0)
		ci.draw_arc(Vector2(cx, fy - 200), 162.0, PI, TAU, 32, Color("0b0e13"), 8.0)
		# team crystal
		var c := Vector2(cx, fy - 150)
		var crystal := PackedVector2Array([c + Vector2(0, -60), c + Vector2(26, -6), c + Vector2(0, 46), c + Vector2(-26, -6)])
		ci.draw_colored_polygon(crystal, tc.darkened(0.15))
		ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -60), c + Vector2(26, -6), c + Vector2(0, 6)]), tc.lightened(0.35))
		for k in 3:
			var sc := c + Vector2(r.randf_range(-110, 110), r.randf_range(-60, 80))
			ci.draw_colored_polygon(PackedVector2Array([sc + Vector2(0, -16), sc + Vector2(7, 0), sc + Vector2(0, 12), sc + Vector2(-7, 0)]), Color(tc, 0.6))


func _build_platforms(platforms: Array) -> void:
	var layer := _layer(1.0, Z_ROCK, "Platforms")
	for pl: Dictionary in platforms:
		var rect: Rect2 = pl["rect"]
		var kind: StringName = pl["kind"]
		var b: int = pl["band"]
		_chunk(layer, func(ci: CanvasItem) -> void: _paint_platform(ci, rect, kind, b))


func _paint_platform(ci: CanvasItem, rect: Rect2, kind: StringName, b: int) -> void:
	var p := SeasonPalette.for_band(b)
	var r := _rng(int(rect.position.x), int(rect.position.y), 11)
	var season: RiftLayout.Season = RiftLayout.BAND_SEASON[b]
	match kind:
		&"column":
			var team_color := Color("4ea4ff") if rect.position.x < W * 0.5 else Color("ff5b5e")
			var x0 := rect.position.x
			var x1 := rect.end.x
			var y := rect.position.y
			ci.draw_colored_polygon(PackedVector2Array([Vector2(x0, y), Vector2(x1, y), Vector2(x1 - 6, y + 14), Vector2(x0 + 6, y + 14)]), Color("1d232e"))
			ci.draw_rect(Rect2(x0, y, rect.size.x, 3), Color("6a7488"))
			for bx in [x0 + 22.0, x1 - 22.0]:  # brackets
				ci.draw_colored_polygon(PackedVector2Array([Vector2(bx - 9, y + 14), Vector2(bx + 9, y + 14), Vector2(bx, y + 34)]), Color("161b24"))
			var gem := Vector2((x0 + x1) * 0.5, y + 7)
			ci.draw_colored_polygon(PackedVector2Array([gem + Vector2(0, -5), gem + Vector2(5, 0), gem + Vector2(0, 5), gem + Vector2(-5, 0)]), team_color)
		&"connector":
			var wood := Color(p["mid"]).darkened(0.2)
			var x := rect.position.x
			while x < rect.end.x - 2:
				ci.draw_rect(Rect2(x, rect.position.y, 16, 10), wood)
				x += 20
			ci.draw_line(rect.position + Vector2(0, 1), rect.position + Vector2(rect.size.x, 1), Color("ffc443", 0.85), 2.0)
			for k in 3:
				ci.draw_circle(rect.position + Vector2(rect.size.x * (k + 0.5) / 3.0, 5), 2.0, Color("ffc443"))
		_:
			var stone: Color = p["rock"]
			var pts := PackedVector2Array([
				rect.position + Vector2(-6, 2), rect.position + Vector2(4, -2), Vector2(rect.end.x - 4, rect.position.y - 2),
				Vector2(rect.end.x + 6, rect.position.y + 2), Vector2(rect.end.x - 10, rect.position.y + 16),
				rect.position + Vector2(rect.size.x * 0.5, 22), rect.position + Vector2(10, 16)])
			ci.draw_colored_polygon(pts, stone)
			ci.draw_line(rect.position + Vector2(0, 0), rect.position + Vector2(rect.size.x, 0), Color(p["rock_rim"], 0.6), 2.0)
			_paint_cap(ci, Rect2(rect.position.x + 2, rect.position.y - 2, rect.size.x - 4, 4), p, season, r)
			for k in 2:
				var hx := rect.position.x + rect.size.x * (0.25 + 0.5 * k)
				if season == S.WINTER:
					Painter.icicle(ci, Vector2(hx, rect.position.y + 14), r.randf_range(14, 30), Color(p["accent2"], 0.85))
				else:
					Painter.hanging_vine(ci, Vector2(hx, rect.position.y + 14), r.randf_range(20, 50), Color(p["cap"]).darkened(0.3), r)


func _build_pads(pads: Array) -> void:
	var layer := _layer(1.0, Z_DECOR, "Pads")
	var glows := _layer(1.0, Z_LIGHT, "PadLights")
	for pad: Vector2 in pads:
		var b := RiftLayout.band_of(pad.y)
		var p := SeasonPalette.for_band(b)
		var cap: Color = p["pad"]
		_chunk(layer, func(ci: CanvasItem) -> void:
			# bounce mushroom: stem, domed cap, spots, and a chevron hinting "hold Up"
			ci.draw_colored_polygon(PackedVector2Array([pad + Vector2(-10, 0), pad + Vector2(10, 0), pad + Vector2(7, -26), pad + Vector2(-7, -26)]), Color("d9d2c3").darkened(0.35))
			var dome := PackedVector2Array()
			for k in 13:
				var a := PI + PI * k / 12.0
				dome.append(pad + Vector2(cos(a) * 40.0, -24.0 + sin(a) * 22.0))
			ci.draw_colored_polygon(dome, cap.darkened(0.15))
			ci.draw_line(pad + Vector2(-40, -24), pad + Vector2(40, -24), cap.darkened(0.45), 3.0)
			for k in 4:
				ci.draw_circle(pad + Vector2(-24 + k * 16, -34 - (k % 2) * 6), 3.5, Color(1, 1, 1, 0.7))
			for k in 2:
				var yy := -60.0 - k * 14.0
				ci.draw_polyline(PackedVector2Array([pad + Vector2(-10, yy + 7), pad + Vector2(0, yy), pad + Vector2(10, yy + 7)]), Color(cap, 0.8 - k * 0.3), 3.0, true))
		_chunk(glows, func(ci: CanvasItem) -> void: Painter.glow(ci, pad + Vector2(0, -36), 110.0, Color(cap, 0.5)), _add)
