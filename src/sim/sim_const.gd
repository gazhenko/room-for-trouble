class_name SimC
extends RefCounted
## Canonical simulation constants (sections 6–10). Distances are micrometres (µm),
## action time is integer ticks at 30 Hz, hotel time is integer quanta
## (30,000 quanta = 1 hotel second).

const TICK_HZ := 30
const UM := 1_000_000                 # µm per metre
const HOTEL_Q_PER_S := 30_000         # hotel quanta per hotel second
const PROTOCOL_VERSION := 1
const SIM_VERSION := "1.0.0"

# Buttons in an InputFrame bitmask.
const BTN_CARRY := 1
const BTN_WORK := 2
const BTN_STEP := 4
const BTN_PING := 8
const BTN_HINT := 16
const BTN_INSPECT := 32
const BTN_READY := 64
const BTN_PING_HOLD := 128

# Motion (§6.2), converted to µm and ticks.
const SPEED := 120_000               # 3.6 m/s
const SPEED_CARRY := 113_333         # 3.4 m/s
const ACCEL := 31_111                # 28 m/s² per tick²
const DECEL := 40_000                # 36 m/s² per tick²
const RADIUS := 280_000              # 0.28 m capsule
const REACH := 1_250_000
const PICKUP_REACH := 1_050_000
const HANDOFF_REACH := 1_600_000
const BREEZER_REACH := 1_500_000
const HYSTERESIS := 200_000
const CONE_COS_MILLI := 574          # cos(55°): half of the 110° cone
const STEP_TICKS := 6                # 0.18 s rounded up
const STEP_DIST := 800_000
const STEP_COOLDOWN := 30
const CATCH_WINDOW := 11             # 0.35 s
const FLOOR_PLACE_RADIUS := 800_000
const FLOOR_LATTICE := 250_000
const ITEM_RADIUS := 150_000
const ITEM_SPACING := 300_000
const AXIS_DEADZONE := 20            # of 127

# Trunk (§6.5)
const TRUNK_HALF_LEN := 900_000
const TRUNK_HALF_WID := 300_000
const TRUNK_HANDLE_OFF := 1_250_000  # handle position from centre
const TRUNK_SPEED_ONE := 46_667      # 1.4 m/s per tick
const TRUNK_SPEED_TWO := 100_000     # 3.0 m/s per tick
const TRUNK_GRACE := 8               # 0.25 s

# Action durations, ticks (quantised upward).
const T_TAKE := 5
const T_ASSIGN := 18
const T_STRIP := 36
const T_MAKE := 45
const T_MOP_ROOM := 60
const T_MOP_PUDDLE := 30
const T_DISPENSE_GIFT := 36
const T_DISPENSE_STOCK := 30
const T_FULFILL := 12
const T_THERMO := 18
const T_GATE := 21
const T_PUMP := 24
const T_CURTAIN := 36
const T_FILL := 45
const T_WATER := 36
const T_BREEZER := 54
const T_FROST := 45
const T_RESET := 45
const T_HAMPER := 9
const T_PRESS := 90
const T_MOVE_ROOM := 45
const T_CANCEL := 18
const T_HELPER := 24
const T_LIFT_SEND := 24
const T_LIFT_TRANSIT := 60
const T_GOODBYE := 24
const T_RING := 1

const WORK_ONE := 1000
const WORK_TWO := 1600
const SHARED_MIN_TICKS := 15         # 0.5 action s from each of two players

# Stations (§7.3)
const LINEN_CAP := 12
const HAMPER_CYCLE := 240            # 8 action s
const HAMPER_QUEUE_CAP := 8
const STOCK_START := 4
const STOCK_CAP := 6
const STOCK_REGEN := 120             # 4 action s
const BELL_COOLDOWN := 120
const TICKET_RETURN := 240           # 8 action s
const TOOL_OOB_RETURN := 60          # 2 action s
const GUS_INTERVAL := 360            # 12 action s
const GUS_BUNDLE_REST := 120
const GUS_TOOL_IDLE := 300
const PING_TICKS := 120
const PING_COOLDOWN := 45
const CLAIM_TICKS := 240
const HANDOFF_USE_WINDOW := 300      # 10 action s
const LIFT_USE_WINDOW := 450         # 15 action s
const TRANSPARENT_TICKS := 30

# Guests (§8), hotel seconds.
const PATIENCE_S := 50
const WALK_BOUND_S := 15
const REQUEST_S := 25
const LATE_S := 6
const QUIRK_AT_S := 32
const HELPER_STREAK_S := 12
const COZY_CORNER_S := 8
const DEPART_S := 3
const ANNOUNCE_S := 8
const GUEST_WALK_SPEED := 70_000     # 2.1 m/s per tick at Family pace

# Environment (§9)
const HEAT_MIN := -100
const HEAT_MAX := 100
const TARGET_WARM := 35
const TARGET_COOL := -35
const NOISE_DECAY := 6
const HUMIDITY_BASE := 20
const STEAM_LIFE_S := 18
const STEAM_RADIUS := 1_100_000
const PUDDLE_LIFE_S := 45
const PUDDLE_BOARD_CAP := 12
const TRIP_AUTO_S := 12
const TRIP_WARN_S := 5

const DIFFICULTY_PACE := {"cozy": 650, "family": 1000, "busy": 1200}
const PLAYER_SCALE_MILLI := [650, 1000, 1250, 1500]
const ROOM_CAP_BY_HUMANS := [2, 4, 5, 6]
const INCIDENT_CAP_BY_HUMANS := [1, 2, 3, 3]

const FAMILIES := ["slime", "yeti", "dragon", "ghost", "moonwolf", "sprout"]
const ROOM_LETTERS := ["A", "B", "C", "D", "E", "F"]
const STAFF_IDS := ["pip", "pebble", "moss", "button"]

static func secs_to_q(s: int) -> int:
	return s * HOTEL_Q_PER_S

static func round_half_away(numer: int, denom: int) -> int:
	# Integer round-half-away-from-zero of numer/denom (denom > 0).
	if numer >= 0:
		return (numer * 2 + denom) / (denom * 2)
	return -((-numer * 2 + denom) / (denom * 2))

static func round_half_up_milli(value_milli: int) -> int:
	# round_half_up(value_milli / 1000) for nonnegative values.
	return (value_milli + 500) / 1000

static func isqrt(v: int) -> int:
	if v <= 0:
		return 0
	var r := int(sqrt(float(v)))
	while r * r > v:
		r -= 1
	while (r + 1) * (r + 1) <= v:
		r += 1
	return r

static func clampi_(v: int, lo: int, hi: int) -> int:
	return lo if v < lo else (hi if v > hi else v)

static func sign_(v: int) -> int:
	return 1 if v > 0 else (-1 if v < 0 else 0)
