class_name CombatRules
extends RefCounted
## Shared tuning constants for the combat simulation.
## Velocities are pixels per tick and durations are ticks; the sim runs at 60 ticks per second.

const TICK_RATE := 60

const GRAVITY := 0.9
const MAX_FALL := 18.0
const JUMP_VELOCITY := -17.0
const AIR_JUMP_VELOCITY := -15.0
const AIR_CONTROL := 0.18
const BODY_SIZE := Vector2(34, 82)
const DROP_FRAMES := 14

const BUFFER_FRAMES := 8
const EX_CHECK_FRAME := 8            ## a skill still held on this frame becomes EX
const PARRY_WINDOW := 9              ## frames after a Guard tap that count as a parry
const PARRY_REWARD_FRAMES := 45      ## next hit within this window deals +50%
const PARRY_STAGGER := 34
const DODGE_FRAMES := 22
const DODGE_INVULN := 12
const DODGE_COOLDOWN := 120
const DODGE_SPEED := 9.0

const JUGGLE_MAX := 4
const KNOCKDOWN_FRAMES := 22
const WAKE_INVULN := 16
const TUMBLE_KNOCKDOWN_FRAMES := 26
const TUMBLE_WAKE_INVULN := 40

const GUARD_MAX := 100.0
const GUARD_REGEN := 0.35
const GUARD_BREAK_FRAMES := 60

const METER_MAX := 300.0
const METER_BAR := 100.0
const BURST_COST := 200.0
const BURST_RADIUS := 190.0
const METER_ON_HIT := 0.35           ## share of damage dealt the attacker gains as meter
const METER_ON_HURT := 0.22          ## share of damage taken the victim gains as meter


## Damage multiplier for the next hit when the victim has already taken `hits_before` hits.
static func combo_scale(hits_before: int) -> float:
	return maxf(0.3, 1.0 - 0.1 * hits_before)
