class_name RiftHud
extends Control
## Map HUD: minimap, Hollow Knight-style area title card when you enter a band, and a short controls hint.

const MAP_SIZE := Vector2(340, 124)
const GOLD := Color("d8c38f")
const TITLE_IN := 0.6
const TITLE_HOLD := 2.2
const TITLE_OUT := 1.0
const HINT := "Hold W on a glowing mushroom to bounce up · S + Space drops through · Base columns: jump up the ledges · F2 dummy · F3 back to base"

var stage: CombatWorld
var _band := -1
var _title_time := 99.0
var _hint_time := 0.0
var _title_font: SystemFont
var _font: Font


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_font = SystemFont.new()
	_title_font.font_names = PackedStringArray(["Cinzel", "Trajan Pro", "Cormorant Garamond", "Georgia", "DejaVu Serif", "Noto Serif", "serif"])
	_title_font.font_weight = 500
	_font = ThemeDB.fallback_font


func _process(delta: float) -> void:
	_title_time += delta
	_hint_time += delta
	var player: Fighter = stage.get("player")
	var b := RiftLayout.band_of(player.position.y)
	if RiftLayout.in_column(player.position.x):
		b = -2  # sanctuary
	if b != _band:
		_band = b
		_title_time = 0.0
	queue_redraw()


func _draw() -> void:
	var vp := get_viewport_rect().size
	_draw_minimap(Vector2(vp.x - MAP_SIZE.x - 16, 14))
	_draw_title(vp)
	if _hint_time < 14.0:
		var a := clampf(14.0 - _hint_time, 0.0, 1.0)
		draw_rect(Rect2(0, vp.y - 30, vp.x, 30), Color(0.02, 0.03, 0.05, 0.7 * a))
		draw_string(_font, Vector2(12, vp.y - 10), HINT, HORIZONTAL_ALIGNMENT_LEFT, vp.x - 24, 13, Color(0.85, 0.88, 0.93, a))


func _draw_minimap(at: Vector2) -> void:
	var size := MAP_SIZE
	var frame := Rect2(at, size)
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.03, 0.04, 0.065, 0.88)
	box.set_corner_radius_all(12)
	box.set_border_width_all(1)
	box.border_color = Color(GOLD, 0.55)
	draw_style_box(box, frame)
	var inner := Rect2(at + Vector2(30, 10), size - Vector2(42, 20))
	var sx := inner.size.x / RiftLayout.WORLD_W
	var sy := inner.size.y / (RiftLayout.FLOORS[4] + 30.0 - RiftLayout.TOP)
	var to_map := func(v: Vector2) -> Vector2: return inner.position + Vector2(v.x * sx, (v.y - RiftLayout.TOP) * sy)
	draw_rect(inner, Color(0.025, 0.03, 0.05))
	# bands: season colours fading into the floor
	for b in RiftLayout.FLOORS.size():
		var p := SeasonPalette.for_band(b)
		var xr := RiftLayout.ground_x_range(b) if RiftLayout.is_jungle(b) else Vector2(0, RiftLayout.WORLD_W)
		var tl: Vector2 = to_map.call(Vector2(xr.x, RiftLayout.band_top(b)))
		var br: Vector2 = to_map.call(Vector2(xr.y, RiftLayout.FLOORS[b]))
		var top_c := Color(p["sky_top"]).lerp(Color(p["sky_bottom"]), 0.4)
		var bot_c := Color(p["sky_bottom"]).lerp(Color(p["cap"]), 0.35)
		draw_polygon(PackedVector2Array([tl, Vector2(br.x, tl.y), br, Vector2(tl.x, br.y)]), PackedColorArray([top_c, top_c, bot_c, bot_c]))
		# terrain line
		var line := PackedVector2Array()
		var x := maxf(xr.x, RiftLayout.COL_W)
		while x <= minf(xr.y, RiftLayout.WORLD_W - RiftLayout.COL_W):
			line.append(to_map.call(Vector2(x, RiftLayout.ground_y(b, x))))
			x += 60.0
		draw_polyline(line, Color(p["cap"]).lightened(0.2), 1.5, true)
		_season_glyph(Vector2(at.x + 15, (tl.y + br.y) * 0.5), RiftLayout.BAND_SEASON[b], Color(p["cap"]).lightened(0.25))
	# bases: team crystals
	for team in [0, 1]:
		var cx := RiftLayout.COL_W * 0.5 if team == 0 else RiftLayout.WORLD_W - RiftLayout.COL_W * 0.5
		var tc := Color("4ea4ff") if team == 0 else Color("ff5b5e")
		var tl: Vector2 = to_map.call(Vector2(cx - RiftLayout.COL_W * 0.5, RiftLayout.TOP))
		draw_rect(Rect2(tl, Vector2(RiftLayout.COL_W * sx, inner.size.y)), Color(tc, 0.18))
		var c: Vector2 = to_map.call(Vector2(cx, RiftLayout.FLOORS[2] - 150.0))
		draw_texture_rect(Painter.glow_texture(), Rect2(c - Vector2(14, 14), Vector2(28, 28)), false, Color(tc, 0.6))
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, -7), c + Vector2(4, 0), c + Vector2(0, 7), c + Vector2(-4, 0)]), tc.lightened(0.3))
	for pad in stage.jump_pads:
		draw_circle(to_map.call(pad) + Vector2(0, -1.5), 1.4, Color(GOLD, 0.9))
	# fighters
	var player: Fighter = stage.get("player")
	for f in stage.fighters:
		if f == player:
			continue
		var c: Vector2 = to_map.call(f.position) + Vector2(0, -3)
		draw_circle(c, 3.2, Color(0, 0, 0, 0.8))
		draw_circle(c, 2.3, Color("4ea4ff") if f.team == 0 else Color("ff5b5e"))
	var pc: Vector2 = to_map.call(player.position) + Vector2(0, -4)
	draw_texture_rect(Painter.glow_texture(), Rect2(pc - Vector2(12, 12), Vector2(24, 24)), false, Color(GOLD, 0.7))
	draw_colored_polygon(PackedVector2Array([pc + Vector2(0, -5), pc + Vector2(4, 0), pc + Vector2(0, 5), pc + Vector2(-4, 0)]), Color("fff3cf"))
	draw_line(pc + Vector2(player.facing * 4, 0), pc + Vector2(player.facing * 8, 0), Color("fff3cf"), 1.5)
	# camera view
	var cam := get_viewport().get_camera_2d()
	if cam != null:
		var cc := cam.get_screen_center_position()
		var half := get_viewport_rect().size * 0.5
		var a: Vector2 = to_map.call(cc - half)
		var b2: Vector2 = to_map.call(cc + half)
		var view := Rect2(a, b2 - a).intersection(inner)
		var vb := StyleBoxFlat.new()
		vb.bg_color = Color(1, 1, 1, 0.05)
		vb.set_corner_radius_all(3)
		vb.set_border_width_all(1)
		vb.border_color = Color(1, 1, 1, 0.55)
		draw_style_box(vb, view)
	# ornaments: corner gems, top crest, area name
	for corner in [frame.position, Vector2(frame.end.x, frame.position.y), frame.end, Vector2(frame.position.x, frame.end.y)]:
		var k: Vector2 = corner + (frame.get_center() - corner).sign() * 5.0
		draw_colored_polygon(PackedVector2Array([k + Vector2(0, -3), k + Vector2(3, 0), k + Vector2(0, 3), k + Vector2(-3, 0)]), Color(GOLD, 0.8))
	var crest := Vector2(frame.get_center().x, frame.position.y)
	draw_line(crest - Vector2(30, 0), crest + Vector2(30, 0), Color(GOLD, 0.9), 1.0)
	draw_colored_polygon(PackedVector2Array([crest + Vector2(0, -5), crest + Vector2(5, 0), crest + Vector2(0, 5), crest + Vector2(-5, 0)]), GOLD)
	var label := "Sanctuary" if _band == -2 else RiftLayout.BAND_TITLE[maxi(_band, 0)]
	var lw := _title_font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
	var ly := frame.end.y + 18.0
	draw_string_outline(_title_font, Vector2(frame.get_center().x - lw * 0.5, ly), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, 4, Color(0, 0, 0, 0.7))
	draw_string(_title_font, Vector2(frame.get_center().x - lw * 0.5, ly), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("e9e2cf"))
	draw_line(Vector2(frame.get_center().x - lw * 0.5 - 30, ly - 5), Vector2(frame.get_center().x - lw * 0.5 - 8, ly - 5), Color(GOLD, 0.7), 1.0)
	draw_line(Vector2(frame.get_center().x + lw * 0.5 + 8, ly - 5), Vector2(frame.get_center().x + lw * 0.5 + 30, ly - 5), Color(GOLD, 0.7), 1.0)


## Tiny season symbol: snowflake, blossom, sun, maple leaf.
func _season_glyph(c: Vector2, season: RiftLayout.Season, color: Color) -> void:
	match season:
		RiftLayout.Season.WINTER:
			for k in 3:
				var d := Vector2.from_angle(PI * k / 3.0) * 5.5
				draw_line(c - d, c + d, color, 1.3)
		RiftLayout.Season.SPRING:
			for k in 5:
				draw_circle(c + Vector2.from_angle(TAU * k / 5.0 - PI / 2.0) * 3.2, 2.2, color)
			draw_circle(c, 1.4, Color("ffe08a"))
		RiftLayout.Season.SUMMER:
			draw_circle(c, 2.6, color)
			for k in 8:
				var d := Vector2.from_angle(TAU * k / 8.0)
				draw_line(c + d * 4.0, c + d * 6.0, color, 1.2)
		RiftLayout.Season.FALL:
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -6), c + Vector2(2, -2), c + Vector2(6, -2), c + Vector2(3, 1), c + Vector2(4, 5),
				c + Vector2(0, 3), c + Vector2(-4, 5), c + Vector2(-3, 1), c + Vector2(-6, -2), c + Vector2(-2, -2)]), color)


func _draw_title(vp: Vector2) -> void:
	var t := _title_time
	if t > TITLE_IN + TITLE_HOLD + TITLE_OUT:
		return
	var a := clampf(t / TITLE_IN, 0.0, 1.0) * clampf((TITLE_IN + TITLE_HOLD + TITLE_OUT - t) / TITLE_OUT, 0.0, 1.0)
	var title := "Sanctuary" if _band == -2 else RiftLayout.BAND_TITLE[_band]
	var sub := "Your base" if _band == -2 else RiftLayout.BAND_SUBTITLE[_band]
	var accent := Color("e9edf4") if _band == -2 else Color(SeasonPalette.for_band(_band)["glow"])
	var y := vp.y * 0.36
	var shade := Color(0, 0, 0, 0.38 * a)
	var clear := Color(0, 0, 0, 0)
	draw_polygon(PackedVector2Array([Vector2(0, y - 70), Vector2(vp.x, y - 70), Vector2(vp.x, y - 10), Vector2(0, y - 10)]), PackedColorArray([clear, clear, shade, shade]))
	draw_polygon(PackedVector2Array([Vector2(0, y - 10), Vector2(vp.x, y - 10), Vector2(vp.x, y + 70), Vector2(0, y + 70)]), PackedColorArray([shade, shade, clear, clear]))
	var size := 46
	var w := _title_font.get_string_size(title.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var x := (vp.x - w) * 0.5
	draw_string_outline(_title_font, Vector2(x, y), title.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, size, 6, Color(0, 0, 0, 0.55 * a))
	draw_string(_title_font, Vector2(x, y), title.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(1, 1, 1, a))
	# ornament: thin lines with a diamond, like an area title card
	var cx := vp.x * 0.5
	var ly := y + 18
	var reach := w * 0.5 + 40.0 * clampf(t / TITLE_IN, 0.0, 1.0)
	draw_line(Vector2(cx - reach, ly), Vector2(cx - 10, ly), Color(accent, 0.8 * a), 1.5)
	draw_line(Vector2(cx + 10, ly), Vector2(cx + reach, ly), Color(accent, 0.8 * a), 1.5)
	draw_colored_polygon(PackedVector2Array([Vector2(cx, ly - 6), Vector2(cx + 6, ly), Vector2(cx, ly + 6), Vector2(cx - 6, ly)]), Color(accent, a))
	var sw := _title_font.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
	draw_string(_title_font, Vector2(cx - sw * 0.5, ly + 28), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.85, 0.88, 0.93, 0.9 * a))
