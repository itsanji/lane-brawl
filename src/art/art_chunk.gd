@tool
class_name ArtChunk
extends Node2D
## A piece of static procedural art. `paint` is called with this node from _draw(), once;
## Godot caches the commands and culls the chunk when it is off screen.

var paint: Callable


func _draw() -> void:
	if paint.is_valid():
		paint.call(self)
