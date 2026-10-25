class_name SkillBar
extends Control
## Ability slots for one fighter (Dash, Skill 1, Skill 2, Ultimate) with cooldown sweeps and seconds left,
## a meter ring on the Ultimate, EX pips, and optionally health + meter orbs. Bottom of the screen.

const GOLD := Color("d8c38f")
const BG := Color(0.03, 0.04, 0.065, 0.88)
const R := 25.0
const GAP := 64.0

var fighter: Fighter
var show_vitals := true
var bottom_margin := 16.0
var _ready_flash := {}   ## slot -> ticks of "ready!" pulse left
var _was_ready := {}
var _font: Font


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font


func _process(_delta: float) -> void:
	queue_redraw()


func _slots() -> Array:
	var f := fighter
	return [
		{"id": &"dash", "key": "Shift", "name": "Dash", "left": f.dash_cooldown, "total": CombatRules.DASH_COOLDOWN},
		{"id": &"S1", "key": "U", "name": f.data.get_move(&"S1").display_name, "left": f.cooldowns[&"S1"], "total": int(f.data.get_move(&"S1").cooldown * CombatRules.TICK_RATE)},
		{"id": &"S2", "key": "I", "name": f.data.get_move(&"S2").display_name, "left": f.cooldowns[&"S2"], "total": int(f.data.get_move(&"S2").cooldown * CombatRules.TICK_RATE)},
		{"id": &"ULT", "key": "O", "name": f.data.get_move(&"ULT").display_name, "left": 0, "total": 1},
	]


func _draw() -> void:
	if fighter == null:
		return
	var vp := get_viewport_rect().size
	var slots := _slots()
	var y := vp.y - bottom_margin - R - 18.0
	var x0 := vp.x - 24.0 - R - GAP * (slots.size() - 1)
	for k in slots.size():
		_draw_slot(Vector2(x0 + GAP * k, y), slots[k])
	if show_vitals:
		_draw_vitals(Vector2(24, vp.y - bottom_margin - 44.0))


func _draw_slot(c: Vector2, slot: Dictionary) -> void:
	var f := fighter
	var id: StringName = slot["id"]
	var left: int = slot["left"]
	var total: int = maxi(1, slot["total"])
	var ready := left <= 0
	var ult := id == &"ULT"
	if ult:
		ready = f.meter >= CombatRules.METER_MAX
	if ready and not _was_ready.get(id, true):
		_ready_flash[id] = 20
	_was_ready[id] = ready
	var flash: int = _ready_flash.get(id, 0)
	if flash > 0:
		_ready_flash[id] = flash - 1
	draw_circle(c, R, BG)
	var accent := f.data.color if not ult else GOLD
	# icon
	var icon_col := Color(0.92, 0.9, 0.85) if ready else Color(0.5, 0.52, 0.58)
	_icon(id, c, icon_col)
	if ult:
		var fill := clampf(f.meter / CombatRules.METER_MAX, 0.0, 1.0)
		draw_arc(c, R - 2.0, -PI / 2.0, -PI / 2.0 + TAU * fill, 40, Color(GOLD, 0.95), 4.0, true)
		if ready:
			var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.008)
			draw_texture_rect(Painter.glow_texture(), Rect2(c - Vector2.ONE * R * 1.9, Vector2.ONE * R * 3.8), false, Color(GOLD, 0.25 + 0.25 * pulse))
		else:
			_label_center("%d%%" % int(fill * 100.0), c + Vector2(0, 5), 12, Color(0.85, 0.85, 0.8))
	elif not ready:
		var frac := float(left) / float(total)
		var pts := PackedVector2Array([c])
		for k in 33:
			var a := -PI / 2.0 + TAU * (1.0 - frac) + TAU * frac * k / 32.0
			pts.append(c + Vector2(cos(a), sin(a)) * (R - 1.0))
		draw_colored_polygon(pts, Color(0, 0, 0, 0.6))
		_label_center("%.1f" % (left / float(CombatRules.TICK_RATE)), c + Vector2(0, 6), 15, Color(1, 1, 1, 0.95))
	var ring := Color(accent, 0.95) if ready else Color(0.35, 0.37, 0.42, 0.9)
	draw_arc(c, R, 0, TAU, 40, ring, 2.0, true)
	if flash > 0:
		draw_arc(c, R + 6.0 - flash * 0.2, 0, TAU, 40, Color(accent, flash / 20.0), 3.0, true)
	if (id == &"S1" or id == &"S2") and f.meter >= CombatRules.METER_BAR:
		draw_colored_polygon(PackedVector2Array([c + Vector2(R * 0.72, -R * 0.72 - 4), c + Vector2(R * 0.72 + 4, -R * 0.72), c + Vector2(R * 0.72, -R * 0.72 + 4), c + Vector2(R * 0.72 - 4, -R * 0.72)]), GOLD)
	# key label
	var key: String = slot["key"]
	var kw := _font.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	var kr := Rect2(c.x - kw * 0.5 - 6, c.y + R + 4, kw + 12, 16)
	draw_rect(kr, Color(0.1, 0.12, 0.17, 0.9))
	draw_rect(kr, Color(0.4, 0.42, 0.5, 0.8), false, 1.0)
	draw_string(_font, Vector2(kr.position.x + 6, kr.position.y + 12), key, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.92, 0.92, 0.95))


func _icon(id: StringName, c: Vector2, col: Color) -> void:
	match id:
		&"dash":
			for k in 2:
				var o := c + Vector2(-6 + k * 9, 0)
				draw_polyline(PackedVector2Array([o + Vector2(-5, -8), o + Vector2(3, 0), o + Vector2(-5, 8)]), col, 3.0, true)
		&"S1":
			draw_arc(c + Vector2(4, 6), 13.0, PI * 1.05, PI * 1.75, 12, col, 4.0, true)
			draw_polyline(PackedVector2Array([c + Vector2(-2, -10), c + Vector2(5, -14), c + Vector2(6, -6)]), col, 2.5, true)
		&"S2":
			draw_line(c + Vector2(-12, 0), c + Vector2(10, 0), col, 3.0)
			draw_polyline(PackedVector2Array([c + Vector2(4, -7), c + Vector2(12, 0), c + Vector2(4, 7)]), col, 3.0, true)
			for k in 3:
				draw_line(c + Vector2(-14 + k * 4, -8 + k * 8), c + Vector2(-6 + k * 4, -8 + k * 8), Color(col, 0.5), 1.5)
		&"ULT":
			var pts := PackedVector2Array()
			for k in 12:
				var a := -PI / 2.0 + TAU * k / 12.0
				pts.append(c + Vector2(cos(a), sin(a)) * (12.0 if k % 2 == 0 else 5.0))
			draw_colored_polygon(pts, col)


func _draw_vitals(at: Vector2) -> void:
	var f := fighter
	var w := 230.0
	draw_rect(Rect2(at - Vector2(10, 22), Vector2(w + 20, 64)), BG)
	draw_rect(Rect2(at - Vector2(10, 22), Vector2(w + 20, 64)), Color(GOLD, 0.35), false, 1.0)
	draw_string(_font, at + Vector2(0, -6), "%s · LV %d · %d / %d" % [f.data.display_name.to_upper(), f.level, ceili(maxf(f.hp, 0.0)), int(f.max_hp())], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.92, 0.9, 0.85))
	var gold := "%d" % f.gold
	var gw := _font.get_string_size(gold, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	draw_string(_font, at + Vector2(w - gw, -6), gold, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("ffc443"))
	var gc := at + Vector2(w - gw - 10, -11)
	draw_colored_polygon(PackedVector2Array([gc + Vector2(0, -5), gc + Vector2(4, 0), gc + Vector2(0, 5), gc + Vector2(-4, 0)]), Color("ffc443"))
	draw_rect(Rect2(at, Vector2(w, 10)), Color(0, 0, 0, 0.6))
	draw_rect(Rect2(at, Vector2(w * clampf(f.hp / f.max_hp(), 0.0, 1.0), 10)), Color("c9e86a"))
	var xp_k := 1.0 if f.level >= CombatRules.MAX_LEVEL else f.xp / CombatRules.xp_to_next(f.level)
	draw_rect(Rect2(at + Vector2(0, 12), Vector2(w, 3)), Color(0, 0, 0, 0.6))
	draw_rect(Rect2(at + Vector2(0, 12), Vector2(w * clampf(xp_k, 0.0, 1.0), 3)), Color("b38cff"))
	for k in 3:  # meter orbs
		var c := at + Vector2(10 + k * 26, 29)
		var fill := clampf((f.meter - k * CombatRules.METER_BAR) / CombatRules.METER_BAR, 0.0, 1.0)
		draw_circle(c, 9.0, Color(0, 0, 0, 0.6))
		if fill > 0.0:
			draw_circle(c, 8.0 * fill, Color(GOLD, 0.95 if fill >= 1.0 else 0.6))
		draw_arc(c, 9.0, 0, TAU, 20, Color(GOLD, 0.7), 1.0, true)
	var bw := 110.0
	draw_rect(Rect2(at + Vector2(w - bw, 26), Vector2(bw, 5)), Color(0, 0, 0, 0.6))
	draw_rect(Rect2(at + Vector2(w - bw, 26), Vector2(bw * f.guard / CombatRules.GUARD_MAX, 5)), Color("a0d2ff") if f.guard > 30.0 else Color("ff5b5e"))
	draw_string(_font, at + Vector2(w - bw - 44, 32), "GUARD", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.6, 0.65, 0.72))


func _label_center(text: String, at: Vector2, size: int, col: Color) -> void:
	var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string_outline(_font, Vector2(at.x - w * 0.5, at.y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 3, Color(0, 0, 0, 0.8))
	draw_string(_font, Vector2(at.x - w * 0.5, at.y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
