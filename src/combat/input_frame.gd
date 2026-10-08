class_name InputFrame
extends RefCounted
## One tick of input. Humans, bots, tests and (later) the network all produce these,
## and the simulation only ever reads these.

const BUTTONS: Array[StringName] = [&"jump", &"light", &"heavy", &"s1", &"s2", &"ult", &"guard"]

var x := 0  ## -1 left, 0, 1 right
var y := 0  ## -1 up, 0, 1 down
var jump := false
var light := false
var heavy := false
var s1 := false
var s2 := false
var ult := false
var guard := false


func copy() -> InputFrame:
	var c := InputFrame.new()
	c.x = x
	c.y = y
	for b in BUTTONS:
		c.set(b, get(b))
	return c
