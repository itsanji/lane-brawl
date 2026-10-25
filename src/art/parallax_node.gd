@tool
class_name ParallaxNode
extends Node2D
## Horizontal parallax: children drawn at world x appear shifted by camera_centre_x * (1 - factor).
## factor < 1 = further away (moves slower), > 1 = foreground (moves faster). Vertical stays 1:1
## so each band's art stays inside its band.

@export var factor := 1.0


func _physics_process(_delta: float) -> void:  # per tick, in step with the camera (both get interpolated)
	if Engine.is_editor_hint():
		position.x = 0.0
		return
	var cam := get_viewport().get_camera_2d()
	if cam != null:
		position.x = cam.get_screen_center_position().x * (1.0 - factor)


## World-space x range that can appear on screen for this factor (for generating content).
static func content_range(factor: float, view_width := 960.0, margin := 300.0) -> Vector2:
	var half := view_width * 0.5
	var c0 := half
	var c1 := RiftLayout.WORLD_W - half
	return Vector2(minf(c0 * factor, c1 * factor) - half - margin, maxf(c0 * factor, c1 * factor) + half + margin)
