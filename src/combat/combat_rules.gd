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
const RUN_ACCEL := 1.2               ## ground speed gained per tick (full speed in ~5 ticks)
const RUN_DECEL := 1.6
const TURN_DECEL := 2.6
const JUMPSQUAT_FRAMES := 3          ## pressing an attack during these turns the jump into a ground attack (W+K = launcher)
const JUMP_CUT_VELOCITY := -6.0      ## releasing jump while rising cuts the jump short (tap = hop, hold = full)
const DASH_SPEED := 15.0
const DASH_FRAMES := 10
const DASH_COOLDOWN := 40            ## ticks; one air dash per jump
const BODY_SIZE := Vector2(34, 82)
const DROP_FRAMES := 14
const STEP_UP := 14.0              ## terrain rise you can walk up in one tick; more is a cliff
const PAD_VELOCITY := -29.5         ## jump pad launch (hold Up on a pad)
const PAD_HALF_WIDTH := 36.0
const PAD_FLIGHT_FRAMES := 40       ## reduced air control while pad-launched

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

# ---------------------------------------------------------------- lane, economy, levels

const FIRST_WAVE := 5 * TICK_RATE        ## first minion wave
const WAVE_INTERVAL := 25 * TICK_RATE    ## then one wave per team every 25 s
const WAVE_SPACING := 34.0
const TOWER_RANGE := 450.0
const CORE_RANGE := 520.0
const TOWER_AGGRO_FRAMES := 180          ## a tower targets whoever hits its team's fighters in range
const BACKDOOR_MULT := 0.5               ## fighters deal half damage to structures without their own minions nearby
const BACKDOOR_RADIUS := 520.0
const MAX_LEVEL := 10
const START_GOLD := 450
const PASSIVE_GOLD := 3                  ## per second
const KILL_GOLD := 250
const ASSIST_GOLD := 100
const KILL_XP := 120.0                   ## + 20 per victim level
const ASSIST_XP := 60.0
const ASSIST_WINDOW := 600               ## ticks a hit counts towards an assist
const XP_RADIUS := 900.0                 ## minion and monster XP is shared by allies this close
const RESPAWN_BASE := 4.0                ## seconds, + RESPAWN_PER_LEVEL per level
const RESPAWN_PER_LEVEL := 1.2
const RESPAWN_INVULN := 90
const FOUNTAIN_HEAL := 0.012             ## share of max HP per tick inside your base
const WYRM_BUFF := 0.1                   ## team damage per Wyrm kill, stacks to 3
const TITAN_BUFF_FRAMES := 60 * TICK_RATE  ## empowered minions after a Titan kill


static func xp_to_next(level: int) -> float:
	return 140.0 + 90.0 * (level - 1)
