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
