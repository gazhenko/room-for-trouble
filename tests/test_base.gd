class_name TestBase
extends RefCounted
## Tiny headless test harness: subclasses define test_* methods.

var content
var failures: PackedStringArray = []
var current := ""
var checks := 0

func check(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		failures.append("%s: %s" % [current, msg])

func eq(a, b, msg: String) -> void:
	checks += 1
	if a != b:
		failures.append("%s: %s (got %s, want %s)" % [current, msg, str(a), str(b)])

func make_sim(level_id: String, humans: int = 1, extra: Dictionary = {}) -> HotelSim:
	var seats: Array = []
	for i in humans:
		seats.append({"seat": i, "char": SimC.STAFF_IDS[i % 4], "assists": {"auto_catch": true}})
	var cfg := {"mode": "campaign", "level_id": level_id, "humans": humans, "seats": seats,
		"difficulty": "family", "seed": 1234, "modifiers": [], "gus": humans == 1}
	for k in extra:
		cfg[k] = extra[k]
	var sim := HotelSim.new(content, cfg)
	return sim

static func frame(seat: int, ax: int = 0, az: int = 0, held: int = 0, pressed: int = 0) -> Dictionary:
	return {"seat": seat, "ax": ax, "az": az, "held": held, "pressed": pressed}

func run_ticks(sim: HotelSim, n: int, frames: Array = []) -> void:
	for i in n:
		sim.step(frames)

func activate(sim: HotelSim) -> void:
	sim.start_now()
	run_ticks(sim, 91)
