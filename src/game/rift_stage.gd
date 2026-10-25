extends CombatWorld
## The full 5v5 map with seasonal art. For now: you (Kael, Blue) play a one-lane match in the middle
## lane — minion waves, towers, gate and core (LaneMatch) — against a red Kael played by a LaneBot.
## F1 hitboxes · F2 bot difficulty (dummy behaviour in the sandbox) · F3 back to base · F4 fill meter ·
## Enter: new match after it ends.
## Set `lane_enabled = false` before adding the scene for a free-roam sandbox (no structures or minions).

var spawn := Vector2(200, RiftLayout.FLOORS[2])
var dummy_spawn := Vector2(3200, RiftLayout.ground_y(2, 3200))  ## sandbox only
static var bot_difficulty := LaneBot.Difficulty.NORMAL  ## kept across "new match" reloads
var lane_enabled := true
const VIGNETTE_SHADER := preload("res://src/art/vignette.gdshader")

var player: Fighter
var dummy: Fighter  ## the red fighter: a training dummy in the sandbox, the LaneBot's fighter in a match
var dummy_controller: DummyController
var bot: LaneBot
var camera: Camera2D
var _dummy_idle := 0
var _look := 0.0


func _ready() -> void:
	InputBindings.register()
	training_mode = not lane_enabled
	var g := RiftLayout.build()
	solids.assign(g["solids"])
	one_ways.assign(g["one_ways"])
	jump_pads.assign(g["pads"])
	grounds.assign(g["grounds"])

	player = Fighter.new()
	player.name = "Player"
	player.setup(Roster.fighter(&"kael"), 0, spawn, 1)
	add_fighter(player, PlayerController.new())

	dummy = Fighter.new()
	if lane_enabled:
		dummy.name = "Enemy"
		var red_base := Vector2(RiftLayout.WORLD_W - spawn.x, spawn.y)
		dummy.setup(Roster.fighter(&"kael"), 1, red_base, -1)
		bot = LaneBot.new(bot_difficulty, 7)
		add_fighter(dummy, bot)
	else:
		dummy.name = "Dummy"
		dummy.setup(Roster.fighter(&"kael"), 1, dummy_spawn, -1)
		dummy_controller = DummyController.new()
		dummy_controller.target = player
		add_fighter(dummy, dummy_controller)

	for spot: Array in RiftLayout.MONSTERS:
		var mon := Monster.new()
		var x: float = spot[1]
		mon.setup(spot[2], Vector2(x, RiftLayout.ground_y(spot[0], x)))
		mon.name = "%s_%d_%d" % [mon.display_name().replace(" ", ""), spot[0], int(x)]
		add_monster(mon)

	if lane_enabled:
		var rules := LaneMatch.new()
		rules.setup(self)
		rules.spawn_points[player] = spawn

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
	camera.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
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
	_update_camera()


## Moves the camera once per tick (physics interpolation then smooths it on high-refresh screens).
## Look-ahead eases toward where you're facing/moving instead of snapping on every turn.
func _update_camera() -> void:
	if camera == null:
		return
	_look = lerpf(_look, player.facing * 45.0 + player.vel.x * 6.0, 0.05)
	var target := _camera_target()
	camera.position = Vector2(lerpf(camera.position.x, target.x + _look, 0.16), lerpf(camera.position.y, target.y, 0.1))


func step() -> void:
	super.step()
	if lane_enabled:
		return
	_dummy_idle = _dummy_idle + 1 if dummy.combo == 0 and dummy.is_actionable() else 0
	if _dummy_idle > 45:
		dummy.hp = dummy.data.max_hp
	if player.combo == 0 and player.is_actionable() and player.hp < player.data.max_hp and tick % 4 == 0:
		player.hp = minf(player.data.max_hp, player.hp + 2.0)


## Keeps the band you're in on screen: lanes stay framed (a little more ground than sky); in the tall
## jungles the camera follows your climb but never shows past the jungle's floor or ceiling.
func _camera_target() -> Vector2:
	var b := RiftLayout.band_of(player.position.y)
	var half_h := get_viewport_rect().size.y * 0.5 if is_inside_tree() else 270.0
	var lo := RiftLayout.band_top(b) + half_h - 30.0
	var hi := RiftLayout.FLOORS[b] + 70.0 - half_h
	var y := clampf(player.position.y - 110.0, minf(lo, hi), maxf(lo, hi))
	return Vector2(player.position.x, y)


func _process(_delta: float) -> void:
	if camera == null:
		return
	camera.offset = Vector2(randf_range(-shake, shake), randf_range(-shake, shake)) if shake > 0.0 else Vector2.ZERO


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"match_restart") and lane != null and lane.winner >= 0:
		get_tree().reload_current_scene()
	elif event.is_action_pressed(&"debug_hitboxes"):
		debug_draw = not debug_draw
	elif event.is_action_pressed(&"training_dummy_mode"):
		if bot != null:
			bot.set_difficulty(((bot.difficulty + 1) % LaneBot.NAMES.size()) as LaneBot.Difficulty)
			bot_difficulty = bot.difficulty
			add_text(player.position + Vector2(0, -150), "Enemy bot: " + bot.difficulty_name(), TEXT_GOLD, 18)
		else:
			dummy_controller.next_mode()
	elif event.is_action_pressed(&"training_reset") and not player.is_ko():
		var meter := player.meter
		player.reset_to(spawn, 1)
		player.meter = meter
	elif event.is_action_pressed(&"training_meter"):
		player.meter = CombatRules.METER_MAX
