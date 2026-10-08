@tool
class_name SeasonParticles
extends CPUParticles2D
## Ambient particles for one band (snow, petals, fireflies, leaves). The emitter follows the camera
## horizontally while particles live in world space, so the whole band always has weather.

var _area := Rect2()


func configure(season: RiftLayout.Season, palette: Dictionary, area: Rect2) -> void:
	_area = area
	local_coords = false
	position = Vector2(area.position.x + 480.0, area.get_center().y)
	emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	emission_rect_extents = Vector2(640, area.size.y * 0.5)
	preprocess = 6.0
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0))
	fade.set_color(1, Color(1, 1, 1, 0))
	fade.add_point(0.15, Color.WHITE)
	fade.add_point(0.85, Color.WHITE)
	color_ramp = fade
	color = palette["particle"]
	match season:
		RiftLayout.Season.WINTER:
			amount = 160
			lifetime = 8.0
			texture = Painter.dot_texture(16, 0.35)
			direction = Vector2(0.3, 1)
			spread = 20.0
			gravity = Vector2(6, 16)
			initial_velocity_min = 12.0
			initial_velocity_max = 34.0
			scale_amount_min = 0.25
			scale_amount_max = 0.65
		RiftLayout.Season.SPRING:
			amount = 70
			lifetime = 9.0
			texture = Painter.leaf_texture(12, 7)
			direction = Vector2(1, 0.25)
			spread = 30.0
			gravity = Vector2(10, 12)
			initial_velocity_min = 18.0
			initial_velocity_max = 40.0
			angular_velocity_min = -140.0
			angular_velocity_max = 140.0
			angle_min = 0.0
			angle_max = 360.0
			scale_amount_min = 0.6
			scale_amount_max = 1.0
		RiftLayout.Season.SUMMER:
			amount = 55
			lifetime = 6.0
			texture = Painter.dot_texture(16, 0.1)
			direction = Vector2(0, -1)
			spread = 180.0
			gravity = Vector2(0, -2)
			initial_velocity_min = 4.0
			initial_velocity_max = 16.0
			scale_amount_min = 0.25
			scale_amount_max = 0.55
			var add := CanvasItemMaterial.new()
			add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
			material = add
		RiftLayout.Season.FALL:
			amount = 65
			lifetime = 9.0
			texture = Painter.leaf_texture(14, 8)
			direction = Vector2(0.6, 1)
			spread = 25.0
			gravity = Vector2(14, 20)
			initial_velocity_min = 16.0
			initial_velocity_max = 36.0
			angular_velocity_min = -220.0
			angular_velocity_max = 220.0
			angle_min = 0.0
			angle_max = 360.0
			scale_amount_min = 0.7
			scale_amount_max = 1.2
			var tints := Gradient.new()
			tints.set_color(0, Color("c4571f"))
			tints.set_color(1, Color("f2b14a"))
			tints.add_point(0.5, Color("a83a1c"))
			color_initial_ramp = tints
			color = Color.WHITE
	emitting = true


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	var cam := get_viewport().get_camera_2d()
	if cam != null:
		position.x = clampf(cam.get_screen_center_position().x, _area.position.x - 200.0, _area.end.x + 200.0)
