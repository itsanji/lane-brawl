@tool
class_name Painter
extends RefCounted
## Procedural drawing helpers. Every function draws onto the given CanvasItem from inside its _draw().
## Shapes are kept simple (star-shaped blobs, tapered quads, polylines) so triangulation never fails.


static func gradient_rect(ci: CanvasItem, r: Rect2, top: Color, bottom: Color) -> void:
	ci.draw_polygon(
		PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]),
		PackedColorArray([top, top, bottom, bottom]))


## Horizontal band that fades from `color` at `edge_y` to transparent `height` px away (negative = upward).
static func fade_band(ci: CanvasItem, x0: float, x1: float, edge_y: float, height: float, color: Color) -> void:
	var clear := Color(color, 0.0)
	gradient_rect(ci, Rect2(x0, minf(edge_y, edge_y + height), x1 - x0, absf(height)),
		clear if height < 0.0 else color, color if height < 0.0 else clear)


## Irregular round shape.
static func blob(ci: CanvasItem, c: Vector2, r: Vector2, color: Color, rng: RandomNumberGenerator, points := 14, jitter := 0.16) -> void:
	var pts := PackedVector2Array()
	var phase := rng.randf() * TAU
	for k in points:
		var a := phase + TAU * k / points
		var j := 1.0 + rng.randf_range(-jitter, jitter)
		pts.append(c + Vector2(cos(a) * r.x, sin(a) * r.y) * j)
	ci.draw_colored_polygon(pts, color)


static var _glow_texture: GradientTexture2D


## Smooth radial falloff texture shared by every glow.
static func glow_texture() -> GradientTexture2D:
	if _glow_texture == null:
		var g := Gradient.new()
		g.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CUBIC
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.18, Color(1, 1, 1, 0.62))
		g.add_point(0.5, Color(1, 1, 1, 0.16))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 128
		t.height = 128
		_glow_texture = t
	return _glow_texture


## Soft glow; `color.a` is the peak intensity (draw on a node with additive blending for light).
static func glow(ci: CanvasItem, c: Vector2, radius: float, color: Color) -> void:
	ci.draw_texture_rect(glow_texture(), Rect2(c - Vector2.ONE * radius, Vector2.ONE * radius * 2.0), false, color)


## Tapered trunk from base (wide) to top (narrow), bending by `bend`.
static func trunk(ci: CanvasItem, base: Vector2, height: float, width: float, bend: float, color: Color) -> void:
	var top := base + Vector2(bend, -height)
	var mid := base + Vector2(bend * 0.35, -height * 0.5)
	ci.draw_colored_polygon(PackedVector2Array([
		base + Vector2(-width * 0.5, 0), base + Vector2(width * 0.5, 0),
		mid + Vector2(width * 0.32, 0), top + Vector2(width * 0.12, 0),
		top + Vector2(-width * 0.12, 0), mid + Vector2(-width * 0.32, 0)]), color)


static func branch(ci: CanvasItem, from: Vector2, to: Vector2, width: float, color: Color) -> void:
	var mid := (from + to) * 0.5 + (to - from).orthogonal().normalized() * (to - from).length() * 0.12
	ci.draw_polyline(PackedVector2Array([from, mid, to]), color, width, true)


## Snow-laden pine (winter).
static func pine(ci: CanvasItem, base: Vector2, h: float, w: float, body: Color, snow: Color, rng: RandomNumberGenerator, snow_amount := 1.0) -> void:
	ci.draw_rect(Rect2(base.x - w * 0.05, base.y - h * 0.18, w * 0.1, h * 0.18), body.darkened(0.25))
	var tiers := rng.randi_range(4, 6)
	for t in tiers:
		var k := float(t) / tiers
		var tier_w := w * (1.0 - k * 0.75) * rng.randf_range(0.92, 1.08)
		var y0 := base.y - h * 0.12 - h * 0.82 * k
		var y1 := y0 - h * 0.34
		var droop := tier_w * 0.12
		ci.draw_colored_polygon(PackedVector2Array([
			Vector2(base.x - tier_w * 0.5, y0 + droop), Vector2(base.x - tier_w * 0.2, y0),
			Vector2(base.x + tier_w * 0.2, y0), Vector2(base.x + tier_w * 0.5, y0 + droop),
			Vector2(base.x, y1)]), body)
		if snow_amount > 0.0:
			var sw := tier_w * 0.82
			ci.draw_colored_polygon(PackedVector2Array([
				Vector2(base.x - sw * 0.42, y0 - h * 0.05 + droop * 0.5), Vector2(base.x, y1 + h * 0.015),
				Vector2(base.x + sw * 0.42, y0 - h * 0.05 + droop * 0.5), Vector2(base.x, y0 - h * 0.11)]),
				Color(snow, snow.a * snow_amount))


## Broad-leaf tree with a clustered canopy; accents are blossoms (spring) or bright leaves (fall).
static func round_tree(ci: CanvasItem, base: Vector2, h: float, canopy: float, bark: Color, leaves: Array,
		accent: Color, accent_count: int, rng: RandomNumberGenerator) -> void:
	var bend := rng.randf_range(-0.15, 0.15) * h
	trunk(ci, base, h, canopy * 0.22, bend, bark)
	var top := base + Vector2(bend, -h)
	for k in rng.randi_range(2, 3):
		var side := -1.0 if k % 2 == 0 else 1.0
		var from := base + Vector2(bend * 0.5, -h * rng.randf_range(0.45, 0.7))
		branch(ci, from, from + Vector2(side * canopy * rng.randf_range(0.5, 0.8), -canopy * rng.randf_range(0.3, 0.6)), canopy * 0.07, bark)
	var centre := top + Vector2(0, canopy * 0.15)
	for k in rng.randi_range(6, 9):
		var off := Vector2(rng.randf_range(-1, 1) * canopy * 0.75, rng.randf_range(-0.7, 0.45) * canopy * 0.7)
		var col: Color = leaves[rng.randi() % leaves.size()]
		blob(ci, centre + off, Vector2.ONE * canopy * rng.randf_range(0.38, 0.55), col, rng, 12, 0.14)
	for k in accent_count:
		var off := Vector2(rng.randf_range(-1, 1) * canopy * 0.95, rng.randf_range(-0.8, 0.55) * canopy * 0.8)
		ci.draw_circle(centre + off, canopy * rng.randf_range(0.035, 0.07), accent)


## Tall jungle tree: buttress roots, a slim trunk and drooping fronds with hanging vines (summer).
static func jungle_tree(ci: CanvasItem, base: Vector2, h: float, bark: Color, leaves: Array, vine: Color, rng: RandomNumberGenerator) -> void:
	var bend := rng.randf_range(-0.12, 0.12) * h
	trunk(ci, base, h, h * 0.07, bend, bark)
	for side: float in [-1.0, 1.0]:
		ci.draw_colored_polygon(PackedVector2Array([
			base + Vector2(side * h * 0.12, 0), base + Vector2(side * h * 0.02, -h * 0.16), base + Vector2(0, 0)]), bark)
	var top := base + Vector2(bend, -h)
	for k in rng.randi_range(5, 7):
		var a := lerpf(-PI * 0.95, -PI * 0.05, (k + rng.randf_range(-0.3, 0.3)) / 6.0)
		var length := h * rng.randf_range(0.28, 0.42)
		var tip := top + Vector2(cos(a), sin(a) * 0.55) * length + Vector2(0, length * 0.35)
		var col: Color = leaves[rng.randi() % leaves.size()]
		frond(ci, top, tip, length * 0.16, col)
		if rng.randf() < 0.6:
			hanging_vine(ci, tip, rng.randf_range(0.2, 0.45) * h, vine, rng)


## Long curved leaf from `from` to `to`.
static func frond(ci: CanvasItem, from: Vector2, to: Vector2, width: float, color: Color) -> void:
	var d := to - from
	var n := d.orthogonal().normalized()
	var mid := from + d * 0.5 + Vector2(0, -d.length() * 0.12)
	ci.draw_colored_polygon(PackedVector2Array([from, mid + n * width, to, mid - n * width * 0.6]), color)


static func hanging_vine(ci: CanvasItem, top: Vector2, length: float, color: Color, rng: RandomNumberGenerator, leafy := true) -> void:
	var pts := PackedVector2Array()
	var phase := rng.randf() * TAU
	for k in 9:
		var t := k / 8.0
		pts.append(top + Vector2(sin(phase + t * 4.0) * 6.0 * t, length * t))
	ci.draw_polyline(pts, color, 2.0, true)
	if leafy:
		for k in range(2, 9, 2):
			var p := pts[k]
			var s := 1.0 if k % 4 == 0 else -1.0
			ci.draw_colored_polygon(PackedVector2Array([p, p + Vector2(s * 8, -3), p + Vector2(s * 4, 4)]), color)


## Grass / fern tuft standing on `base`.
static func tuft(ci: CanvasItem, base: Vector2, h: float, color: Color, rng: RandomNumberGenerator, blades := 5) -> void:
	for k in blades:
		var lean := rng.randf_range(-0.6, 0.6)
		var bh := h * rng.randf_range(0.6, 1.0)
		var b0 := base + Vector2(rng.randf_range(-4, 4), 0)
		ci.draw_colored_polygon(PackedVector2Array([b0 + Vector2(-2, 0), b0 + Vector2(lean * bh * 0.5, -bh), b0 + Vector2(2, 0)]), color)


static func icicle(ci: CanvasItem, top: Vector2, length: float, color: Color) -> void:
	ci.draw_colored_polygon(PackedVector2Array([top + Vector2(-length * 0.12, 0), top + Vector2(length * 0.12, 0), top + Vector2(0, length)]), color)


## Lumafly-style lantern on a post: dark post and cage (draw the glow separately, additively).
static func lantern(ci: CanvasItem, base: Vector2, h: float, dark: Color, glass: Color) -> void:
	ci.draw_line(base, base + Vector2(0, -h), dark, 4.0)
	ci.draw_line(base + Vector2(0, -h), base + Vector2(14, -h - 6), dark, 3.0)
	var c := base + Vector2(14, -h + 10)
	ci.draw_line(base + Vector2(14, -h - 6), c + Vector2(0, -10), dark, 2.0)
	ci.draw_circle(c, 9.0, glass)
	ci.draw_arc(c, 10.0, 0, TAU, 16, dark, 2.5)


## Hill/ridge silhouette across [x0, x1] with its base at `base_y`.
static func ridge(ci: CanvasItem, x0: float, x1: float, base_y: float, height: float, color: Color, rng: RandomNumberGenerator, step := 60.0) -> void:
	var pts := PackedVector2Array([Vector2(x0, base_y)])
	var x := x0
	var phase := rng.randf() * 10.0
	while x <= x1:
		var y := base_y - height * (0.55 + 0.25 * sin(x * 0.004 + phase) + 0.2 * sin(x * 0.011 + phase * 2.0))
		pts.append(Vector2(x, y))
		x += step
	pts.append(Vector2(x1, base_y))
	ci.draw_colored_polygon(pts, color)


## Small soft white dot texture for particles.
static func dot_texture(size := 16, hardness := 0.5) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := (size - 1) / 2.0
	for y in size:
		for x in size:
			var d := Vector2(x - c, y - c).length() / c
			var a := clampf((1.0 - d) / (1.0 - hardness), 0.0, 1.0) if d < 1.0 else 0.0
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)


## Leaf/petal texture (white, tinted by the particle colour).
static func leaf_texture(w := 14, h := 8) -> ImageTexture:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var u := (x - (w - 1) / 2.0) / (w / 2.0)
			var v := (y - (h - 1) / 2.0) / (h / 2.0)
			var inside := u * u + v * v * (1.0 + absf(u)) < 1.0
			img.set_pixel(x, y, Color(1, 1, 1, 1.0 if inside else 0.0))
	return ImageTexture.create_from_image(img)


# ------------------------------------------------------------------ Japanese winter

## Japanese black pine (matsu): leaning trunk, horizontal branches ending in flat cloud-like pads with snow.
static func matsu(ci: CanvasItem, base: Vector2, h: float, bark: Color, needles: Color, snow: Color, rng: RandomNumberGenerator) -> void:
	var lean := rng.randf_range(-0.35, 0.35) * h
	var pts := PackedVector2Array()
	for k in 7:
		var t := k / 6.0
		pts.append(base + Vector2(lean * t * t + sin(t * 3.0) * h * 0.04, -h * t))
	ci.draw_polyline(pts, bark, h * 0.055, true)
	var pads := rng.randi_range(4, 6)
	for k in pads:
		var t := lerpf(0.42, 1.0, float(k) / (pads - 1))
		var at := base + Vector2(lean * t * t, -h * t)
		var side := -1.0 if k % 2 == 0 else 1.0
		var reach := h * rng.randf_range(0.16, 0.3) * (1.15 - t * 0.5)
		var tip := at + Vector2(side * reach, rng.randf_range(-0.04, 0.03) * h)
		branch(ci, at, tip, h * 0.022, bark)
		var pad := Vector2(rng.randf_range(0.1, 0.15) * h, rng.randf_range(0.032, 0.045) * h)
		blob(ci, tip, pad, needles, rng, 14, 0.12)
		blob(ci, tip + Vector2(0, -pad.y * 0.6), Vector2(pad.x * 0.8, pad.y * 0.42), Color(snow, snow.a * 0.85), rng, 12, 0.1)
	var crown := base + Vector2(lean, -h)
	blob(ci, crown, Vector2(h * 0.12, h * 0.045), needles, rng, 14, 0.12)
	blob(ci, crown + Vector2(0, -h * 0.028), Vector2(h * 0.1, h * 0.022), Color(snow, snow.a * 0.85), rng, 12, 0.1)


## Torii gate standing on two (possibly different) ground heights. `x` is the centre.
static func torii(ci: CanvasItem, x: float, ground_left: float, ground_right: float, h: float, red: Color, dark: Color, snow: Color) -> void:
	var half := h * 0.5
	var top := minf(ground_left, ground_right) - h
	for side: float in [-1.0, 1.0]:
		var px := x + side * half * 0.78
		var gy := ground_left if side < 0.0 else ground_right
		ci.draw_colored_polygon(PackedVector2Array([
			Vector2(px - h * 0.045, gy), Vector2(px + h * 0.045, gy),
			Vector2(px + h * 0.035, top + h * 0.1), Vector2(px - h * 0.035, top + h * 0.1)]), red)
		ci.draw_rect(Rect2(px - h * 0.055, gy - h * 0.05, h * 0.11, h * 0.05), dark)       # black footing
	ci.draw_rect(Rect2(x - half * 0.95, top + h * 0.22, half * 1.9, h * 0.05), red)          # nuki
	ci.draw_rect(Rect2(x - h * 0.03, top + h * 0.08, h * 0.06, h * 0.15), red)               # gakuzuka
	var k := PackedVector2Array([                                                              # kasagi, upturned ends
		Vector2(x - half * 1.18, top - h * 0.03), Vector2(x - half * 0.9, top + h * 0.02), Vector2(x + half * 0.9, top + h * 0.02),
		Vector2(x + half * 1.18, top - h * 0.03), Vector2(x + half * 1.1, top + h * 0.06), Vector2(x - half * 1.1, top + h * 0.06)])
	ci.draw_colored_polygon(k, dark)
	ci.draw_rect(Rect2(x - half * 1.02, top + h * 0.06, half * 2.04, h * 0.045), red)
	ci.draw_colored_polygon(PackedVector2Array([
		Vector2(x - half * 1.16, top - h * 0.035), Vector2(x - half * 0.9, top - h * 0.005), Vector2(x + half * 0.9, top - h * 0.005),
		Vector2(x + half * 1.16, top - h * 0.035), Vector2(x + half * 0.8, top - h * 0.06), Vector2(x - half * 0.8, top - h * 0.06)]), snow)


## Stone lantern (tōrō); the window is drawn with `light`, add a glow on top separately.
static func toro(ci: CanvasItem, base: Vector2, h: float, stone: Color, light: Color, snow: Color) -> void:
	var w := h * 0.42
	ci.draw_rect(Rect2(base.x - w * 0.5, base.y - h * 0.08, w, h * 0.08), stone)
	ci.draw_rect(Rect2(base.x - w * 0.12, base.y - h * 0.5, w * 0.24, h * 0.42), stone)
	ci.draw_rect(Rect2(base.x - w * 0.36, base.y - h * 0.56, w * 0.72, h * 0.07), stone)
	ci.draw_rect(Rect2(base.x - w * 0.3, base.y - h * 0.76, w * 0.6, h * 0.2), stone)
	ci.draw_rect(Rect2(base.x - w * 0.16, base.y - h * 0.72, w * 0.32, h * 0.12), light)
	ci.draw_colored_polygon(PackedVector2Array([
		Vector2(base.x - w * 0.62, base.y - h * 0.74), Vector2(base.x + w * 0.62, base.y - h * 0.74),
		Vector2(base.x + w * 0.3, base.y - h * 0.88), Vector2(base.x - w * 0.3, base.y - h * 0.88)]), stone)
	ci.draw_colored_polygon(PackedVector2Array([
		Vector2(base.x - w * 0.56, base.y - h * 0.77), Vector2(base.x + w * 0.56, base.y - h * 0.77),
		Vector2(base.x + w * 0.26, base.y - h * 0.9), Vector2(base.x - w * 0.26, base.y - h * 0.9)]), snow)
	ci.draw_circle(base + Vector2(0, -h * 0.94), w * 0.1, stone)


## Paper lantern (chōchin) hanging from `top` on a short cord.
static func chochin(ci: CanvasItem, top: Vector2, size: float, paper: Color, dark: Color) -> void:
	var c := top + Vector2(0, size * 1.1)
	ci.draw_line(top, c - Vector2(0, size * 0.6), dark, 1.5)
	var pts := PackedVector2Array()
	for k in 16:
		var a := TAU * k / 16.0
		pts.append(c + Vector2(cos(a) * size * 0.42, sin(a) * size * 0.6))
	ci.draw_colored_polygon(pts, paper)
	ci.draw_rect(Rect2(c.x - size * 0.25, c.y - size * 0.66, size * 0.5, size * 0.12), dark)
	ci.draw_rect(Rect2(c.x - size * 0.25, c.y + size * 0.54, size * 0.5, size * 0.12), dark)


## Distant pagoda silhouette.
static func pagoda(ci: CanvasItem, base: Vector2, h: float, color: Color, snow: Color) -> void:
	var tiers := 4
	var w := h * 0.42
	for t in tiers:
		var k := float(t) / tiers
		var y := base.y - h * 0.82 * k
		var tw := w * (1.0 - k * 0.45)
		ci.draw_rect(Rect2(base.x - tw * 0.3, y - h * 0.16, tw * 0.6, h * 0.16), color)
		var roof := PackedVector2Array([  # flared eaves, outline in one direction
			Vector2(base.x - tw * 0.62, y - h * 0.14), Vector2(base.x - tw * 0.45, y - h * 0.19), Vector2(base.x, y - h * 0.27),
			Vector2(base.x + tw * 0.45, y - h * 0.19), Vector2(base.x + tw * 0.62, y - h * 0.14), Vector2(base.x, y - h * 0.17)])
		ci.draw_colored_polygon(roof, color)
		ci.draw_colored_polygon(PackedVector2Array([
			Vector2(base.x - tw * 0.5, y - h * 0.2), Vector2(base.x + tw * 0.5, y - h * 0.2), Vector2(base.x, y - h * 0.27)]), snow)
	ci.draw_line(base + Vector2(0, -h * 0.9), base + Vector2(0, -h * 1.08), color, 3.0)


## Snow-capped mountain peak (Fuji-like) silhouette.
static func peak(ci: CanvasItem, base: Vector2, h: float, w: float, rock: Color, snow: Color) -> void:
	var top := base + Vector2(0, -h)
	ci.draw_colored_polygon(PackedVector2Array([base + Vector2(-w * 0.5, 0), top + Vector2(-w * 0.06, 0), top + Vector2(w * 0.06, 0), base + Vector2(w * 0.5, 0)]), rock)
	var cap := 0.3
	ci.draw_colored_polygon(PackedVector2Array([
		top + Vector2(-w * 0.06, 0), top + Vector2(w * 0.06, 0), top + Vector2(w * 0.5 * cap + w * 0.03, h * cap),
		top + Vector2(w * 0.08, h * cap * 0.8), top + Vector2(0, h * cap), top + Vector2(-w * 0.1, h * cap * 0.75),
		top + Vector2(-w * 0.5 * cap - w * 0.03, h * cap)]), snow)


## Camellia bush in snow: dark leaves, red flowers, snow on top.
static func camellia(ci: CanvasItem, base: Vector2, size: float, leaves: Color, flower: Color, snow: Color, rng: RandomNumberGenerator) -> void:
	for k in 3:
		blob(ci, base + Vector2((k - 1) * size * 0.55, -size * rng.randf_range(0.4, 0.6)), Vector2(size * 0.5, size * 0.42), leaves, rng, 12, 0.18)
	for k in 6:
		ci.draw_circle(base + Vector2(rng.randf_range(-size, size), -size * rng.randf_range(0.3, 0.9)), size * 0.09, flower)
	blob(ci, base + Vector2(0, -size * 0.85), Vector2(size * 0.95, size * 0.2), snow, rng, 12, 0.15)


## Short bamboo fence segment.
static func bamboo_fence(ci: CanvasItem, x0: float, x1: float, ground: Callable, h: float, color: Color, snow: Color) -> void:
	var x := x0
	while x <= x1:
		var gy: float = ground.call(x)
		ci.draw_rect(Rect2(x - 2.5, gy - h, 5, h), color)
		ci.draw_rect(Rect2(x - 3.5, gy - h - 3, 7, 3), snow)
		x += 14.0
	for frac: float in [0.35, 0.75]:
		ci.draw_line(Vector2(x0 - 6, ground.call(x0) - h * frac), Vector2(x1 + 6, ground.call(x1) - h * frac), color.darkened(0.3), 3.0)
