extends CombatWorld
## The full 5v5 map with seasonal art. For now: you (Kael) explore it, with a dummy in the middle lane.
## F1 hitboxes · F2 dummy behaviour · F3 back to base · F4 fill meter.

const SPAWN := Vector2(200, 1300)
var dummy_spawn := Vector2(3420, RiftLayout.ground_y(2, 3420))
const VIGNETTE_SHADER := preload("res://src/art/vignette.gdshader")

var player: Fighter
var dummy: Fighter
var dummy_controller: DummyController
var camera: Camera2D
var _dummy_idle := 0


func _ready() -> void:
	InputBindings.register()
	training_mode = true
	var g := RiftLayout.build()
	solids.assign(g["solids"])
	one_ways.assign(g["one_ways"])
	jump_pads.assign(g["pads"])
	grounds.assign(g["grounds"])

	player = Fighter.new()
	player.name = "Player"
	player.setup(Roster.fighter(&"kael"), 0, SPAWN, 1)
	add_fighter(player, PlayerController.new())

	dummy = Fighter.new()
	dummy.name = "Dummy"
	dummy.setup(Roster.fighter(&"kael"), 1, dummy_spawn, -1)
	dummy_controller = DummyController.new()
	dummy_controller.target = player
	add_fighter(dummy, dummy_controller)

	var fx := EffectsLayer.new()
	fx.world = self
	fx.z_index = 10
	add_child(fx)

	camera = Camera2D.new()
	camera.limit_left = 0
	camera.limit_right = int(RiftLayout.WORLD_W)
	camera.limit_top = 0
	camera.limit_bottom = int(RiftLayout.WORLD_H)
	camera.position = _camera_target()
	add_child(camera)
	camera.make_current()

	var vignette_layer := CanvasLayer.new()
	vignette_layer.layer = 1
	add_child(vignette_layer)
	var vignette := ColorRect.new()
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = VIGNETTE_SHADER
	vignette.material = mat
	vignette_layer.add_child(vignette)

	var hud_layer := CanvasLayer.new()
	hud_layer.layer = 2
	add_child(hud_layer)
	var hud := RiftHud.new()
	hud.stage = self
	hud_layer.add_child(hud)


func _physics_process(_delta: float) -> void:
	if auto_tick:
		step()


func step() -> void:
	super.step()
	_dummy_idle = _dummy_idle + 1 if dummy.combo == 0 and dummy.is_actionable() else 0
	if _dummy_idle > 45:
		dummy.hp = dummy.data.max_hp
	if player.combo == 0 and player.is_actionable() and player.hp < player.data.max_hp and tick % 4 == 0:
		player.hp = minf(player.data.max_hp, player.hp + 2.0)


## Frames the band you're in (a little more ground than sky), but follows you when you jump high.
func _camera_target() -> Vector2:
	var b := RiftLayout.band_of(player.position.y)
	var band_mid := (RiftLayout.band_top(b) + RiftLayout.FLOORS[b]) * 0.5 + 40.0
	return Vector2(player.position.x + player.facing * 70.0, minf(band_mid, player.position.y + 60.0))


func _process(delta: float) -> void:
	if camera == null:
		return
	camera.position = camera.position.lerp(_camera_target(), 1.0 - exp(-7.0 * delta))
	camera.offset = Vector2(randf_range(-shake, shake), randf_range(-shake, shake)) if shake > 0.0 else Vector2.ZERO


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"debug_hitboxes"):
		debug_draw = not debug_draw
	elif event.is_action_pressed(&"training_dummy_mode"):
		dummy_controller.next_mode()
	elif event.is_action_pressed(&"training_reset"):
		var meter := player.meter
		player.reset_to(SPAWN, 1)
		player.meter = meter
	elif event.is_action_pressed(&"training_meter"):
		player.meter = CombatRules.METER_MAX
