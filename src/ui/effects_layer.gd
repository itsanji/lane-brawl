class_name EffectsLayer
extends Node2D
## Draws CombatWorld.effects (sparks, rings, block flashes, floating text) in world space.

var world: CombatWorld


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if world == null:
		return
	var font := ThemeDB.fallback_font
	for sh in world.shots:  # tower and lanternling orbs
		var c: Color = sh["color"]
		var r: float = sh["size"]
		var p0: Vector2 = sh["pos"]
		draw_texture_rect(Painter.glow_texture(), Rect2(p0 - Vector2(r, r) * 3.0, Vector2(r, r) * 6.0), false, Color(c, 0.55))
		draw_circle(p0, r, c)
		draw_circle(p0, r * 0.5, Color(1, 1, 1, 0.9))
	for e in world.effects:
		var k := float(e["t"]) / float(e["life"])
		var p: Vector2 = e["pos"]
		match e["kind"]:
			&"spark":
				var color: Color = e.get("color", Color.WHITE)
				var big: bool = e.get("big", false)
				var r := (34.0 if big else 22.0) * (0.4 + k)
				for a in 8:
					var an := TAU * a / 8.0 + p.x
					var d := Vector2(cos(an), sin(an))
					draw_line(p + d * r * 0.4, p + d * r, Color(color, 1.0 - k), 4.0 if big else 3.0)
				draw_circle(p, (12.0 if big else 7.0) * (1.0 - k), Color(1, 1, 1, 1.0 - k))
			&"ring":
				var color: Color = e.get("color", Color.WHITE)
				var radius: float = e.get("radius", 40.0)
				draw_arc(p, 8.0 + (radius - 8.0) * k, 0, TAU, 40, Color(color, color.a * (1.0 - k)), 3.0)
			&"ghost":  # dash afterimage
				var color: Color = e.get("color", Color.WHITE)
				var fc: int = e.get("facing", 1)
				var a := 0.45 * (1.0 - k)
				draw_colored_polygon(PackedVector2Array([p + Vector2(-11, -54), p + Vector2(11, -54), p + Vector2(17 - fc * 6, -8), p + Vector2(-17 - fc * 6, -8)]), Color(0.11, 0.12, 0.18, a))
				draw_circle(p + Vector2(fc * 2, -67), 11.0, Color(0.94, 0.91, 0.86, a))
				draw_line(p + Vector2(-fc * 6, -56), p + Vector2(-fc * 26, -50), Color(color, a), 3.0)
			&"dust":  # little puffs at the feet (jump, land, dash)
				var dir: int = e.get("dir", 0)
				for j in 5:
					var off := Vector2((j - 2) * 7.0 + dir * 26.0 * k, -4.0 - 10.0 * k * (1.0 + (j % 2)))
					draw_circle(p + off, (5.0 - j % 2 * 1.5) * (1.0 - k * 0.6), Color(0.85, 0.85, 0.8, 0.35 * (1.0 - k)))
			&"puff":  # something broke apart: a burst of dark shards and dust
				var color: Color = e.get("color", Color.WHITE)
				var big: bool = e.get("big", false)
				var n := 14 if big else 8
				var spread := (90.0 if big else 34.0) * (0.3 + k)
				for j in n:
					var d := Vector2.from_angle(TAU * j / n + p.x * 0.01)
					var q := p + d * spread + Vector2(0, 30.0 * k * k)
					draw_circle(q, (7.0 if big else 4.0) * (1.0 - k), Color(color, 0.9 * (1.0 - k)))
				draw_circle(p, (40.0 if big else 16.0) * (0.4 + k), Color(0.8, 0.8, 0.78, 0.25 * (1.0 - k)))
			&"block":
				draw_arc(p, 14.0 + 16.0 * k, 0, TAU, 24, Color(0.81, 0.9, 1, 1.0 - k), 4.0)
			&"text":
				var size: int = e.get("size", 16)
				var color: Color = e.get("color", Color.WHITE)
				var alpha := 1.0 - maxf(0.0, float(e["t"]) - 30.0) / 20.0
				var text: String = e["text"]
				var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
				var at := p - Vector2(width / 2.0, 0)
				draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 4, Color(0.02, 0.03, 0.04, alpha))
				draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(color, alpha))
