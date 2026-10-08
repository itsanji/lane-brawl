class_name FighterData
extends Resource
## Stats and move list for one fighter.

@export var id: StringName
@export var display_name := ""
@export var role := ""
@export var archetype := ""
@export var color := Color.WHITE
@export var max_hp := 1000.0
@export var run_speed := 5.5
@export var damage_mult := 1.0
@export var air_jumps := 1
@export var moves: Dictionary[StringName, MoveData] = {}


func get_move(move_id: StringName) -> MoveData:
	if moves.has(move_id):
		return moves[move_id]
	return null
