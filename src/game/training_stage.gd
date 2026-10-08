extends CombatWorld
## Training room: you (Kael) against a dummy with selectable behaviour.
## F1 hitboxes · F2 dummy behaviour · F3 reset positions · F4 fill your meter.

const PLAYER_SPAWN := Vector2(700, 440)
const DUMMY_SPAWN := Vector2(900, 440)
const REFILL_AFTER := 45  ## idle ticks before a fighter's HP and guard refill

var player: Fighter
var dummy: Fighter
var dummy_controller: DummyController
var camera: Camera2D
var hud: TrainingHud
var _dummy_idle := 0
var _player_idle := 0


func _ready() -> void:
	InputBindings.register()
	training_mode = true
	for node in $Level.get_children():
		if node is SolidBlock:
			add_solid(node.world_rect(), node.one_way)

	player = Fighter.new()
	player.name = "Player"
	player.setup(Roster.fighter(&"kael"), 0, PLAYER_SPAWN, 1)
	add_fighter(player, PlayerController.new())

	dummy = Fighter.new()
	dummy.name = "Dummy"
	dummy.setup(Roster.fighter(&"kael"), 1, DUMMY_SPAWN, -1)
	dummy_controller = DummyController.new()
	dummy_controller.target = player
	add_fighter(dummy, dummy_controller)

	var fx := EffectsLayer.new()
	fx.world = self
	fx.z_index = 10
	add_child(fx)

	camera = Camera2D.new()
	camera.limit_left = 0
	camera.limit_right = 1920
	camera.limit_top = -260
	camera.limit_bottom = 640
	camera.position = player.position + Vector2(0, -120)
	add_child(camera)
	camera.make_current()

	var layer := CanvasLayer.new()
	add_child(layer)
	hud = TrainingHud.new()
	hud.stage = self
	layer.add_child(hud)


func _physics_process(_delta: float) -> void:
	if auto_tick:
		step()


func step() -> void:
	super.step()
	_apply_training_rules()


func _process(delta: float) -> void:
	if camera == null:
		return
	var target := player.position + Vector2(player.facing * 60.0, -120.0)
	camera.position = camera.position.lerp(target, 1.0 - exp(-8.0 * delta))
	camera.offset = Vector2(randf_range(-shake, shake), randf_range(-shake, shake)) if shake > 0.0 else Vector2.ZERO


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"debug_hitboxes"):
		debug_draw = not debug_draw
	elif event.is_action_pressed(&"training_dummy_mode"):
		dummy_controller.next_mode()
	elif event.is_action_pressed(&"training_reset"):
		reset_positions()
	elif event.is_action_pressed(&"training_meter"):
		player.meter = CombatRules.METER_MAX


func reset_positions() -> void:
	var meter := player.meter
	player.reset_to(PLAYER_SPAWN, 1)
	player.meter = meter
	dummy.reset_to(DUMMY_SPAWN, -1)


func _apply_training_rules() -> void:
	_dummy_idle = _dummy_idle + 1 if dummy.combo == 0 and dummy.is_actionable() else 0
	if _dummy_idle > REFILL_AFTER:
		dummy.hp = dummy.data.max_hp
		dummy.guard = CombatRules.GUARD_MAX
	_player_idle = _player_idle + 1 if player.combo == 0 and player.is_actionable() else 0
	if _player_idle > REFILL_AFTER * 4:
		player.hp = player.data.max_hp
	if dummy_controller.mode == DummyController.Mode.BURST:
		dummy.meter = CombatRules.METER_MAX
	for f in fighters:
		if f.position.y > 900.0:  # fell out of the level somehow
			f.reset_to(PLAYER_SPAWN if f == player else DUMMY_SPAWN, f.facing)
