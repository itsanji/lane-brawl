@tool
class_name FogWisps
extends Node2D
## Slow, soft fog banks drifting across a band around the camera.

const COUNT := 9

var area := Rect2()
var color := Color.WHITE
var _seed := 0
var _t := 0.0


func setup(band_area: Rect2, fog_color: Color, seed_value: int) -> void:
	area = band_area
	color = fog_color
	_seed = seed_value


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var cam := get_viewport().get_camera_2d()
	var cx := cam.get_screen_center_position().x if cam != null and not Engine.is_editor_hint() else area.get_center().x
	var cy := cam.get_screen_center_position().y if cam != null and not Engine.is_editor_hint() else area.get_center().y
	if absf(cy - area.get_center().y) > area.size.y + 400.0:
		return
	var r := RandomNumberGenerator.new()
	r.seed = _seed
	var tex := Painter.glow_texture()
	for k in COUNT:
		var speed := r.randf_range(8.0, 22.0)
		var w := r.randf_range(380.0, 720.0)
		var h := r.randf_range(50.0, 110.0)
		var span := 2200.0
		var x := cx - span * 0.5 + fposmod(r.randf() * span + _t * speed, span)
		var y := lerpf(area.position.y + area.size.y * 0.45, area.end.y - 10.0, r.randf())
		var a := r.randf_range(0.12, 0.22) * (0.7 + 0.3 * sin(_t * 0.2 + k))
		draw_texture_rect(tex, Rect2(x - w * 0.5, y - h * 0.5, w, h), false, Color(color, a))
