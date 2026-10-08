@tool
class_name GroundStrip
extends RefCounted
## Walkable terrain whose surface height varies with x (rolling hills), sampled every STEP px.
## Hills only rise above `base_y`; the flat floor rect under them still blocks from below.

const STEP := 8.0

var x0 := 0.0
var x1 := 0.0
var base_y := 0.0
var heights := PackedFloat32Array()


func contains(x: float) -> bool:
	return x >= x0 and x <= x1


func height_at(x: float) -> float:
	var t := clampf((x - x0) / STEP, 0.0, heights.size() - 1.001)
	var i := int(t)
	return lerpf(heights[i], heights[i + 1], t - i)
