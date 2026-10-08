class_name MoveData
extends Resource
## Frame data for one attack.
## hitbox: position.x = forward offset from the body centre, position.y = top edge
## relative to the feet (negative is up), size = width and height. Mirrored when facing left.

enum Kind { LIGHT, HEAVY, GRAB, SKILL, ULT }

@export var id: StringName
@export var display_name := ""
@export var kind: Kind = Kind.LIGHT

@export_group("Timing")
@export var startup := 4
@export var active := 3
@export var recovery := 10
@export var cooldown := 0.0  ## seconds; skills only

@export_group("Hit")
@export var damage := 0.0
@export var hitbox := Rect2()
@export var hitstun := 16
@export var knockback := Vector2.ZERO
@export var juggle_cost := -1      ## -1 = 1 if the target is already airborne, else 0
@export var guard_damage := -1.0   ## -1 = half the damage
@export var hitstop := 0           ## 0 = 5 for heavy kinds, 3 otherwise
@export var launch := false
@export var knockdown := false
@export var grab := false
@export var unblockable := false
@export var multi_hit_interval := 0  ## re-hit the same target every N active frames

@export_group("Flow")
@export var air := false            ## air normals end when you land
@export var chain_light: StringName ## next move if Light is pressed during this one
@export var chain_heavy: StringName
@export var jump_cancel := false    ## Jump cancels this move on hit
@export var then_move: StringName   ## starts automatically when this move ends

@export_group("Self")
@export var self_velocity := Vector2.ZERO  ## applied from the first active frame
@export var self_frames := 0
@export var invuln_from := -1
@export var invuln_to := -1


func total_frames() -> int:
	return startup + active + recovery


func is_active_frame(frame: int) -> bool:
	return frame > startup and frame <= startup + active


func is_normal() -> bool:
	return kind == Kind.LIGHT or kind == Kind.HEAVY


func get_hitstop() -> int:
	if hitstop > 0:
		return hitstop
	return 5 if kind == Kind.HEAVY else 3
