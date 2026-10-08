class_name Roster
extends RefCounted
## Fighter definitions, ported from the HTML prototype (prototype/lane-brawl-demo.html).
## Each move is a dictionary of MoveData property names; unknown keys are reported as errors.

const L := MoveData.Kind.LIGHT
const H := MoveData.Kind.HEAVY

## Normals every fighter shares unless their own move list overrides them.
const NORMALS := {
	&"L1": {"startup": 4, "active": 3, "recovery": 10, "damage": 30.0, "hitbox": Rect2(6, -68, 58, 32),
		"hitstun": 18, "knockback": Vector2(2.5, 0), "chain_light": &"L2", "kind": L},
	&"L2": {"startup": 5, "active": 3, "recovery": 11, "damage": 32.0, "hitbox": Rect2(6, -64, 62, 32),
		"hitstun": 18, "knockback": Vector2(2.5, 0), "chain_light": &"L3", "chain_heavy": &"LH", "kind": L},
	&"L3": {"startup": 7, "active": 4, "recovery": 18, "damage": 44.0, "hitbox": Rect2(4, -72, 70, 42),
		"hitstun": 22, "knockback": Vector2(7, -4), "hitstop": 5, "kind": L},
	&"LH": {"startup": 9, "active": 4, "recovery": 20, "damage": 60.0, "hitbox": Rect2(4, -74, 74, 46),
		"hitstun": 26, "knockback": Vector2(9, -5), "hitstop": 6, "guard_damage": 26.0, "kind": H},
	&"H": {"startup": 12, "active": 4, "recovery": 20, "damage": 66.0, "hitbox": Rect2(4, -74, 76, 46),
		"hitstun": 26, "knockback": Vector2(9, -5), "hitstop": 6, "guard_damage": 30.0, "kind": H},
	&"UH": {"startup": 10, "active": 4, "recovery": 22, "damage": 46.0, "hitbox": Rect2(-6, -118, 64, 100),
		"hitstun": 32, "knockback": Vector2(1.2, -17), "launch": true, "juggle_cost": 1, "jump_cancel": true,
		"hitstop": 7, "kind": H},
	&"DH": {"startup": 9, "active": 4, "recovery": 20, "damage": 42.0, "hitbox": Rect2(0, -26, 84, 26),
		"hitstun": 24, "knockback": Vector2(3, -7), "knockdown": true, "hitstop": 5, "kind": H},
	&"AL": {"startup": 4, "active": 5, "recovery": 9, "damage": 28.0, "hitbox": Rect2(-4, -76, 60, 56),
		"hitstun": 26, "knockback": Vector2(2, -7), "air": true, "juggle_cost": 1, "jump_cancel": true, "kind": L},
	&"AH": {"startup": 8, "active": 5, "recovery": 14, "damage": 46.0, "hitbox": Rect2(-4, -64, 64, 64),
		"hitstun": 24, "knockback": Vector2(5, 9), "air": true, "juggle_cost": 1, "hitstop": 6, "kind": H},
	&"GRAB": {"startup": 5, "active": 2, "recovery": 26, "damage": 56.0, "hitbox": Rect2(4, -74, 40, 64),
		"hitstun": 30, "knockback": Vector2(7, -9), "grab": true, "knockdown": true, "hitstop": 8,
		"kind": MoveData.Kind.GRAB},
}

const KAEL := {
	"display_name": "Kael", "role": "Duelist", "archetype": "Rushdown", "color": Color("f0a43a"),
	"max_hp": 1150.0, "run_speed": 5.9, "damage_mult": 1.06, "air_jumps": 1,
	"moves": {
		&"S1": {"display_name": "Rising Fang", "startup": 8, "active": 8, "recovery": 22, "damage": 68.0,
			"hitbox": Rect2(-8, -128, 58, 128), "hitstun": 34, "knockback": Vector2(2, -18), "launch": true,
			"juggle_cost": 1, "self_velocity": Vector2(3, -13), "self_frames": 1, "invuln_from": 0,
			"invuln_to": 12, "jump_cancel": true, "cooldown": 7.0, "hitstop": 7, "kind": MoveData.Kind.SKILL},
		&"S2": {"display_name": "Phantom Dash", "startup": 8, "active": 10, "recovery": 14, "damage": 50.0,
			"hitbox": Rect2(-24, -82, 64, 82), "hitstun": 22, "knockback": Vector2(5, -7),
			"self_velocity": Vector2(17, 0), "self_frames": 10, "invuln_from": 8, "invuln_to": 16,
			"cooldown": 6.0, "kind": MoveData.Kind.SKILL},
		&"ULT": {"display_name": "Thousand Cuts", "startup": 8, "active": 42, "recovery": 6, "damage": 22.0,
			"hitbox": Rect2(-10, -96, 110, 96), "hitstun": 24, "knockback": Vector2(0.6, -1.5),
			"multi_hit_interval": 6, "juggle_cost": 0, "invuln_from": 0, "invuln_to": 50, "then_move": &"ULT2",
			"hitstop": 3, "kind": MoveData.Kind.ULT},
		&"ULT2": {"display_name": "Thousand Cuts", "startup": 2, "active": 4, "recovery": 26, "damage": 120.0,
			"hitbox": Rect2(-10, -100, 120, 100), "hitstun": 36, "knockback": Vector2(12, -11), "launch": true,
			"juggle_cost": 0, "hitstop": 12, "kind": MoveData.Kind.ULT},
	},
}

const FIGHTERS := {&"kael": KAEL}


static func fighter(fighter_id: StringName) -> FighterData:
	assert(FIGHTERS.has(fighter_id), "Unknown fighter %s" % fighter_id)
	var def: Dictionary = FIGHTERS[fighter_id]
	var fd := FighterData.new()
	fd.id = fighter_id
	for key: String in def:
		if key != "moves":
			fd.set(key, def[key])
	for move_id: StringName in NORMALS:
		fd.moves[move_id] = make_move(move_id, NORMALS[move_id])
	var own: Dictionary = def.get("moves", {})
	for move_id: StringName in own:
		fd.moves[move_id] = make_move(move_id, own[move_id])
	return fd


static func make_move(move_id: StringName, def: Dictionary) -> MoveData:
	var m := MoveData.new()
	m.id = move_id
	for key: String in def:
		if not key in m:
			push_error("Move %s: unknown property '%s'" % [move_id, key])
			continue
		m.set(key, def[key])
	return m
