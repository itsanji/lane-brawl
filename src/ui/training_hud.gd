class_name TrainingHud
extends Control
## Training HUD: bars, combo counter, frame data of your last move and the controls.

const PANEL := Color(0.06, 0.08, 0.12, 0.86)
const GOLD := Color("ffc443")
const MUTED := Color("97a3b8")
const GREEN := Color("9fd356")
const HELP := "Move A/D · Jump W/Space (hold = higher) · Dash Shift · Light J · Heavy K (W+K launch, S+K sweep) · Skills U, I · Ult O · Guard L"
const HELP2 := "Guard+direction dodge · Guard+J grab · Guard+K burst (when hit) · S+Space drop · F1 hitboxes · F2 dummy · F3 reset · F4 meter"

var stage: CombatWorld
var _combo := {"hits": 0, "damage": 0.0, "juggle": 0, "tick": -999}
var _last_move: MoveData
var _last_result := ""


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.combat_event.connect(_on_combat_event)
	var bar := SkillBar.new()
	bar.fighter = stage.get("player")
	bar.show_vitals = false
	bar.bottom_margin = 92.0
	add_child(bar)


func _process(_delta: float) -> void:
	queue_redraw()


func _on_combat_event(kind: StringName, info: Dictionary) -> void:
	var player: Fighter = stage.get("player")
	match kind:
		&"move_started":
			if info["fighter"] == player:
				_last_move = info["move"]
				_last_result = "whiff"
		&"hit":
			if info["attacker"] == player:
				var t: Fighter = info["target"]
				_combo = {"hits": t.combo, "damage": t.combo_damage, "juggle": t.juggle, "tick": stage.tick}
				_last_result = "counter hit" if info["counter"] else "hit"
		&"block":
			if info["attacker"] == player:
				_last_result = "guard break" if info["result"] == &"guard_break" else "blocked"
		&"parry":
			if info["attacker"] == player:
				_last_result = "parried"


func _draw() -> void:
	if stage == null:
		return
	var font := ThemeDB.fallback_font
	var vp := get_viewport_rect().size
	var player: Fighter = stage.get("player")
	var dummy: Fighter = stage.get("dummy")
	var dummy_ctrl: DummyController = stage.get("dummy_controller")

	# Player panel
	draw_rect(Rect2(10, 10, 290, 104), PANEL)
	draw_string(font, Vector2(20, 34), "%s · %s" % [player.data.display_name.to_upper(), player.data.role], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, player.data.color)
	_bar(Vector2(20, 42), Vector2(270, 14), player.hp / player.max_hp(), GREEN)
	draw_string(font, Vector2(24, 54), "%d / %d" % [ceili(player.hp), int(player.max_hp())], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.04, 0.06, 0.09))
	for k in 3:
		var fill := clampf((player.meter - k * CombatRules.METER_BAR) / CombatRules.METER_BAR, 0.0, 1.0)
		_bar(Vector2(20 + k * 64, 62), Vector2(60, 9), fill, GOLD if fill >= 1.0 else Color("8a6a22"))
	draw_string(font, Vector2(216, 71), "METER", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, MUTED)
	_bar(Vector2(20, 78), Vector2(130, 5), player.guard / CombatRules.GUARD_MAX, Color("a0d2ff") if player.guard > 30.0 else Color("ff5b5e"))
	draw_string(font, Vector2(156, 84), "GUARD", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, MUTED)
	var s1: int = player.cooldowns[&"S1"]
	var s2: int = player.cooldowns[&"S2"]
	var skills := "U %s   I %s   O %s" % [
		"ready" if s1 <= 0 else "%.1fs" % (s1 / 60.0),
		"ready" if s2 <= 0 else "%.1fs" % (s2 / 60.0),
		"READY" if player.meter >= CombatRules.METER_MAX else "%d%%" % int(player.meter / 3.0)]
	draw_string(font, Vector2(20, 104), skills, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)

	# Dummy panel
	var dx := vp.x - 300
	draw_rect(Rect2(dx, 10, 290, 64), PANEL)
	draw_string(font, Vector2(dx + 10, 32), "DUMMY · F2: %s" % dummy_ctrl.mode_name(), HORIZONTAL_ALIGNMENT_LEFT, 270, 14, Color("ffb0b2"))
	_bar(Vector2(dx + 10, 40), Vector2(270, 12), dummy.hp / dummy.max_hp(), Color("ff5b5e"))
	_bar(Vector2(dx + 10, 58), Vector2(130, 5), dummy.guard / CombatRules.GUARD_MAX, Color("a0d2ff"))
	draw_string(font, Vector2(dx + 146, 64), "state: %s" % dummy.state, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, MUTED)

	# Combo counter
	var age: int = stage.tick - int(_combo["tick"])
	if int(_combo["hits"]) >= 2 and age < 90:
		var a := 1.0 - maxf(0.0, age - 60.0) / 30.0
		var hits := "%d HITS" % int(_combo["hits"])
		draw_string(font, Vector2(vp.x - 30 - font.get_string_size(hits, HORIZONTAL_ALIGNMENT_LEFT, -1, 44).x, 170), hits, HORIZONTAL_ALIGNMENT_LEFT, -1, 44, Color(GOLD, a))
		var sub := "%d damage · juggle %d/%d" % [int(_combo["damage"]), int(_combo["juggle"]), CombatRules.JUGGLE_MAX]
		draw_string(font, Vector2(vp.x - 30 - font.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x, 192), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 1, 1, a))

	# Frame data of your last move
	if _last_move != null:
		var m := _last_move
		var label := m.display_name if m.display_name != "" else String(m.id)
		var line := "%s — startup %d · active %d · recovery %d · damage %d · %s" % [label, m.startup, m.active, m.recovery, int(m.damage), _last_result]
		draw_rect(Rect2(10, vp.y - 82, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 20, 24), PANEL)
		draw_string(font, Vector2(20, vp.y - 65), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)

	# Controls
	draw_rect(Rect2(0, vp.y - 50, vp.x, 50), PANEL)
	draw_string(font, Vector2(12, vp.y - 30), HELP, HORIZONTAL_ALIGNMENT_LEFT, vp.x - 24, 13, MUTED)
	draw_string(font, Vector2(12, vp.y - 12), HELP2, HORIZONTAL_ALIGNMENT_LEFT, vp.x - 24, 13, GOLD)


func _bar(at: Vector2, bar_size: Vector2, fill: float, color: Color) -> void:
	draw_rect(Rect2(at, bar_size), Color(0, 0, 0, 0.55))
	draw_rect(Rect2(at, Vector2(bar_size.x * clampf(fill, 0.0, 1.0), bar_size.y)), color)
