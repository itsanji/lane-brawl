@tool
class_name Critters
extends Node2D
## Small living things, drawn every frame near the camera: butterflies (spring), fireflies (summer),
## birds crossing the sky (fall and winter).

enum Kind { BUTTERFLY, FIREFLY, BIRD }

var kind := Kind.BUTTERFLY
var area := Rect2()
var colors: Array[Color] = []
var _anchors: Array[Vector3] = []  ## x, y, phase
var _t := 0.0


func setup(critter_kind: Kind, band_area: Rect2, palette_colors: Array[Color], seed_value: int) -> void:
	kind = critter_kind
	area = band_area
	colors = palette_colors
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	var spacing: float = {Kind.BUTTERFLY: 260.0, Kind.FIREFLY: 140.0, Kind.BIRD: 0.0}[kind]
	if kind == Kind.BIRD:
		for k in 7:  # one flock, positions relative to the flock leader
			_anchors.append(Vector3(-k * r.randf_range(26, 40), (k % 2) * r.randf_range(10, 20) + k * 3.0, r.randf() * TAU))
	else:
		var x := area.position.x + r.randf_range(0, spacing)
		while x < area.end.x:
			var y := lerpf(area.position.y + area.size.y * (0.35 if kind == Kind.FIREFLY else 0.45), area.end.y - 30.0, r.randf())
			_anchors.append(Vector3(x, y, r.randf() * TAU))
			x += spacing * r.randf_range(0.6, 1.4)


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var cam := get_viewport().get_camera_2d()
	if cam == null or Engine.is_editor_hint():
		return
	var c := cam.get_screen_center_position()
	if absf(c.y - area.get_center().y) > area.size.y + 300.0:
		return
	match kind:
		Kind.BUTTERFLY:
			for a in _anchors:
				if absf(a.x - c.x) > 620.0:
					continue
				var p := Vector2(a.x + sin(_t * 0.6 + a.z) * 70.0, a.y + sin(_t * 1.3 + a.z * 2.0) * 28.0)
				var flap := absf(sin(_t * 13.0 + a.z * 5.0))
				var col := colors[int(a.z * 10.0) % colors.size()]
				for side: float in [-1.0, 1.0]:
					draw_colored_polygon(PackedVector2Array([p, p + Vector2(side * 7.0, -6.0 * flap - 1.0), p + Vector2(side * 5.0, 3.0 * flap + 1.0)]), col)
				draw_line(p + Vector2(0, -3), p + Vector2(0, 3), Color(0.1, 0.1, 0.1), 1.0)
		Kind.FIREFLY:
			for a in _anchors:
				if absf(a.x - c.x) > 620.0:
					continue
				var p := Vector2(a.x + sin(_t * 0.4 + a.z) * 40.0, a.y + sin(_t * 0.7 + a.z * 1.7) * 30.0)
				var pulse := 0.5 + 0.5 * sin(_t * 2.2 + a.z * 3.0)
				Painter.glow(self, p, 26.0, Color(colors[0], 0.5 * pulse))
				draw_circle(p, 2.0, Color(1, 1, 0.85, 0.6 + 0.4 * pulse))
		Kind.BIRD:
			var span := 2400.0
			var lead_x := c.x - span * 0.5 + fposmod(_t * 55.0, span)
			var lead_y := area.position.y + area.size.y * 0.22 + sin(_t * 0.3) * 20.0
			for a in _anchors:
				var p := Vector2(lead_x + a.x, lead_y + a.y)
				var flap := sin(_t * 7.0 + a.z)
				var col := colors[0]
				draw_polyline(PackedVector2Array([p + Vector2(-7, -3.0 * flap), p, p + Vector2(7, -3.0 * flap)]), col, 2.0, true)
