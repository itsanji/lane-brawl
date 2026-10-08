@tool
class_name SolidBlock
extends Node2D
## A rectangle of level geometry; its position is the top-left corner. Edit size in the inspector.
## One-way blocks can be jumped through from below and dropped through with Down + Jump.

@export var size := Vector2(200, 40):
	set(value):
		size = value
		queue_redraw()
@export var one_way := false:
	set(value):
		one_way = value
		queue_redraw()


func world_rect() -> Rect2:
	return Rect2(global_position, size)


func _draw() -> void:
	if one_way:
		draw_rect(Rect2(Vector2.ZERO, Vector2(size.x, 10)), Color("3b4558"))
		draw_rect(Rect2(Vector2.ZERO, Vector2(size.x, 3)), Color("66728c"))
	else:
		draw_rect(Rect2(Vector2.ZERO, size), Color("2a3243"))
		draw_rect(Rect2(Vector2.ZERO, Vector2(size.x, 4)), Color("4b566e"))
		var x := 80.0
		while x < size.x:
			draw_rect(Rect2(x, 8, 2, minf(28.0, size.y - 10.0)), Color("222a39"))
			x += 80.0
