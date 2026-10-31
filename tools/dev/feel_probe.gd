extends SceneTree
## Dev: measures movement/interaction feel numbers straight from the sim
## (input-to-motion latency, acceleration and stop distances, turn-around,
## Quick Step gain, action lock-outs, and travel-vs-work seconds for common
## jobs).  godot --headless --path . --script res://tools/dev/feel_probe.gd -- [L06]

var sim: HotelSim
var seat := 0

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var lid := args[0] if args.size() > 0 else "L06"
	var reg = load("res://src/content/content_registry.gd").new()
	reg.load_all()
	sim = HotelSim.new(reg, {"mode": "campaign", "level_id": lid, "humans": 1,
		"seats": [{"seat": 0, "char": "pip", "assists": {"auto_catch": true}}],
		"difficulty": "family", "seed": 3, "gus": false})
	sim.start_now()
	for i in 95:
		_step(0, 0, 0)
	print("phase=%s tick=%d speed=%.2f m/s accel=%.1f m/s2 decel=%.1f m/s2 tick=%.1f ms" % [sim.s["phase"], sim.s["tick"],
		SimC.SPEED / 1e6 * 30, SimC.ACCEL / 1e6 * 900, SimC.DECEL / 1e6 * 900, 1000.0 / SimC.TICK_HZ])
	_accel_stop()
	_turn()
	_quick_step()
	_pickup_lock()
	_travel_matrix()
	reg.free()
	quit()

func _st() -> Dictionary:
	return sim.s["staff"][seat]

## Middle row of the hall (the free walking lane) and a clear spot on it.
func _lane_z() -> float:
	return float(sim.L.hall.position.y) + (sim.L.hall.size.y - 1) * 0.5

func _lane_x() -> float:
	return float(sim.L.hall.position.x) + (sim.L.hall.size.x - 1) * 0.5

func _step(ax: int, az: int, pressed: int, held := 0) -> void:
	sim.step([{"seat": seat, "ax": ax, "az": az, "held": held, "pressed": pressed, "pick": -1}])

func _teleport(x_m: float, z_m: float) -> void:
	var st := _st()
	st["x"] = int(x_m * 1e6); st["z"] = int(z_m * 1e6)
	st["vx"] = 0; st["vz"] = 0
	st["held"] = 0 if st["held"] == 0 else st["held"]

func _accel_stop() -> void:
	print("\n== accelerate from rest (full stick +x) ==")
	_teleport(_lane_x() - 2.0, _lane_z())
	var x0: int = _st()["x"]
	var full := -1
	var first := -1
	for t in 12:
		var before: int = _st()["x"]
		_step(127, 0, 0)
		var dx: int = _st()["x"] - before
		if dx > 0 and first < 0:
			first = t + 1
		if _st()["vx"] >= SimC.SPEED and full < 0:
			full = t + 1
		print("  tick %2d  vx=%6.2f m/s  dx=%5.1f cm" % [t + 1, _st()["vx"] / 1e6 * 30, dx / 1e4])
	print("  first motion on tick %d (%.0f ms); full speed on tick %d (%.0f ms) after %.2f m" % [first, first * 1000.0 / 30, full, full * 1000.0 / 30, (_st()["x"] - x0) / 1e6])
	print("== release stick at full speed ==")
	var xs: int = _st()["x"]
	var stop := -1
	for t in 8:
		_step(0, 0, 0)
		print("  tick %2d  vx=%6.2f m/s" % [t + 1, _st()["vx"] / 1e6 * 30])
		if _st()["vx"] == 0 and stop < 0:
			stop = t + 1
	print("  stopped on tick %d (%.0f ms), %.2f m slide" % [stop, stop * 1000.0 / 30, (_st()["x"] - xs) / 1e6])

func _turn() -> void:
	print("\n== turn-around (+x full speed, then -x) ==")
	_teleport(_lane_x() - 2.0, _lane_z())
	for t in 8:
		_step(127, 0, 0)
	var xs: int = _st()["x"]
	var rev := -1
	var full := -1
	for t in 10:
		_step(-127, 0, 0)
		if _st()["vx"] < 0 and rev < 0:
			rev = t + 1
		if _st()["vx"] <= -SimC.SPEED and full < 0:
			full = t + 1
	print("  reversing on tick %d, full reverse on tick %d (%.0f ms); overshoot %.2f m" % [rev, full, full * 1000.0 / 30, maxf(0.0, (_st()["x"] - xs) / 1e6)])

func _quick_step() -> void:
	print("\n== Quick Step while running +x ==")
	_teleport(_lane_x() - 2.0, _lane_z())
	for t in 8:
		_step(127, 0, 0)
	var xs: int = _st()["x"]
	_step(127, 0, SimC.BTN_STEP)
	var n := 1
	while _st()["step_t"] > 0:
		_step(127, 0, 0)
		n += 1
	var stepped: int = _st()["x"] - xs
	print("  dash: %.2f m in %d ticks (%.0f ms) = %.1f m/s; walking the same ticks = %.2f m; gain = %.2f m (%.1f%%); cooldown %d ticks" % [
		stepped / 1e6, n, n * 1000.0 / 30, stepped / 1e6 * 30 / n, n * SimC.SPEED / 1e6, (stepped - n * SimC.SPEED) / 1e6,
		100.0 * (stepped - n * SimC.SPEED) / float(n * SimC.SPEED), SimC.STEP_COOLDOWN])
	print("  character capsule radius %.2f m; dash length / body width = %.1f" % [SimC.RADIUS / 1e6, SimC.STEP_DIST / float(2 * SimC.RADIUS)])

## Ticks the avatar still refuses stick input after the last press.
func _lock_left() -> int:
	var n := 0
	while not _st()["act"].is_empty() and _st()["act"].get("lock", false) and _st()["act"].get("move_lock", true) and n < 60:
		_step(-127, 0, 0)
		n += 1
	return n + 1 if n > 0 else 0

func _locked_ticks() -> int:
	var st := _st()
	var locked := 0
	var x0: int = st["x"]
	for t in 40:
		_step(-127, 0, 0)
		if st["x"] == x0:
			locked += 1
		else:
			break
	return locked

func _pickup_lock() -> void:
	print("\n== take a towel from the shelf ==")
	var tp: Vector2i = sim.L.fixtures["towel_shelf"]
	_teleport(tp.x + 0.0, tp.y - 0.9)
	var st := _st()
	st["fx"] = 0; st["fz"] = 1000
	_step(0, 0, 0)
	print("  highlight carry=%s ok=%s" % [st["hl_c"], st["hl_c_ok"]])
	_step(0, 0, SimC.BTN_CARRY)
	print("  after press: held=%d act=%s" % [st["held"], st["act"]])
	var wait := 0
	while st["held"] == 0 and wait < 60:
		_step(0, 0, 0)
		wait += 1
	print("  towel in hands after %d more ticks standing still (%.2f s total)" % [wait, (wait + 1) / 30.0])
	var locked := _lock_left()
	print("  then movement input ignored for %d more ticks (%.0f ms)" % [locked, locked * 1000.0 / 30])
	print("== walk away and put it on the floor ==")
	for t in 8:
		_step(-127, 0, 0)
	_step(0, 0, SimC.BTN_CARRY)
	print("  after press: held=%d act=%s" % [st["held"], st["act"]])
	locked = _lock_left()
	print("  movement input ignored for %d ticks (%.0f ms) after the put-down" % [locked, locked * 1000.0 / 30])
	print("== pick it back up from the floor ==")
	for iid in sim.s["items"]:
		var it: Dictionary = sim.s["items"][iid]
		if it["loc"] == "world" and it["k"] == "towel":
			var dx: int = it["x"] - st["x"]; var dz: int = it["z"] - st["z"]
			var m := maxi(1, SimC.isqrt(dx * dx + dz * dz))
			st["fx"] = dx * 1000 / m; st["fz"] = dz * 1000 / m
	_step(0, 0, 0)
	print("  highlight carry=%s ok=%s" % [st["hl_c"], st["hl_c_ok"]])
	_step(0, 0, SimC.BTN_CARRY)
	print("  after press: held=%d act=%s" % [st["held"], st["act"]])
	locked = _lock_left()
	print("  movement input ignored for %d ticks (%.0f ms) after the floor pick-up" % [locked, locked * 1000.0 / 30])
	print("  (ticket assign locks %d ticks = %.1f s, fulfil %d = %.1f s, hamper %d = %.1f s; dispense gift channels %d = %.1f s)" % [
		SimC.T_ASSIGN, SimC.T_ASSIGN / 30.0, SimC.T_FULFILL, SimC.T_FULFILL / 30.0, SimC.T_HAMPER, SimC.T_HAMPER / 30.0, SimC.T_DISPENSE_GIFT, SimC.T_DISPENSE_GIFT / 30.0])
	_snags()

## Runs the length of the hall lane (and a few offsets toward the station rows)
## and through a room door at a small offset, counting ticks where the avatar is
## stopped by collision while the stick is held. All positions come from the layout.
func _snags() -> void:
	print("\n== collision snags ==")
	var hz := _lane_z()
	var x0 := float(sim.L.hall.position.x) + 1.5
	var x1 := float(sim.L.hall.end.x - 1) - 1.5
	var run_m := x1 - x0
	for z in [hz - 0.8, hz - 0.6, hz - 0.4, hz, hz + 0.4, hz + 0.6]:
		_teleport(x0, z)
		var stalls := 0
		var stall_runs := 0
		var was_stalled := false
		var where: Array = []
		var ticks := 0
		var budget := int(run_m / 3.6 * 30) * 2 + 30
		for t in budget:
			var before: int = _st()["x"]
			_step(127, 0, 0)
			ticks += 1
			var stalled: bool = _st()["x"] == before
			if stalled:
				stalls += 1
				if not was_stalled:
					stall_runs += 1
					where.append("x=%.2f" % (_st()["x"] / 1e6))
			was_stalled = stalled
			if _st()["x"] > int(x1 * 1e6):
				break
		print("  hall run at z=%.1f (lane %+.1f m): %d snags at %s, %d stalled ticks (%.0f ms); %d ticks for %.1f m (free run would be %d)" % [z, z - hz, stall_runs, where, stalls, stalls * 1000.0 / 30, ticks, run_m, int(run_m / 3.6 * 30)])
	# Door entry: room B's door, approached straight from the hall lane with x offsets.
	var d: Vector2i = sim.L.rooms["B"]["door"]
	var dirz := -1 if d.y < sim.L.hall.position.y else 1
	for off in [0.0, 0.15, 0.3, 0.45]:
		_teleport(d.x + off, hz)
		var stalls := 0
		var ticks := 0
		for t in 90:
			var before: int = _st()["z"]
			_step(0, 127 * dirz, 0)
			ticks += 1
			if _st()["z"] == before:
				stalls += 1
			if (dirz < 0 and _st()["z"] < (d.y - 1) * SimC.UM) or (dirz > 0 and _st()["z"] > (d.y + 1) * SimC.UM):
				break
		print("  door entry, stick straight at the door, %.0f cm off centre: %d stalled ticks, %d ticks to get through (%.0f ms), ended at x=%.2f" % [off * 100, stalls, ticks, ticks * 1000.0 / 30, _st()["x"] / 1e6])

func _path_m(bot: ReferenceBot, a: Vector2i, b: Vector2i) -> float:
	var pts := bot.path(a, b)
	var d := 0.0
	var prev := a
	for p in pts:
		d += Vector2(p - prev).length() / 1e6
		prev = p
	return d

func _travel_matrix() -> void:
	print("\n== travel vs work for common jobs (%s, bot path lengths) ==" % sim.L.id)
	var bot := ReferenceBot.new(sim)
	var F: Dictionary = sim.L.fixtures
	var um := func(t: Vector2i) -> Vector2i: return Vector2i(t.x * SimC.UM, t.y * SimC.UM)
	var rooms: Array = sim.L.active_rooms
	var speed := SimC.SPEED / 1e6 * 30
	var carry := SimC.SPEED_CARRY / 1e6 * 30
	var jobs := [
		["ticket: pedestal -> door plaque -> back to hall", F["pedestals"][2], "door", SimC.T_TAKE + SimC.T_ASSIGN],
		["towel: shelf -> guest at bed", F["towel_shelf"], "bed", SimC.T_DISPENSE_STOCK + SimC.T_FULFILL],
		["gift: kiosk -> plinth", F["welcome_kiosk"], "plinth", SimC.T_DISPENSE_GIFT + SimC.T_FULFILL],
		["linen: shelf -> bed (make)", F["linen_shelf"], "bed", SimC.T_TAKE + SimC.T_MAKE],
		["dirty linen: bed -> hamper", F["hamper"], "bed", SimC.T_STRIP + SimC.T_HAMPER],
		["thermostat: hall centre -> room thermostat", Vector2i(sim.L.hall.position.x + sim.L.hall.size.x / 2, sim.L.hall.position.y + sim.L.hall.size.y / 2), "thermostat", SimC.T_THERMO],
	]
	var tot_travel := 0.0
	var tot_work := 0.0
	for j in jobs:
		var line := "  %-46s" % j[0]
		var sum := 0.0
		for letter in rooms:
			var g: Dictionary = sim.L.rooms[letter]
			var dest: Vector2i = g[j[2]]
			var a: Vector2i = um.call(j[1])
			var b: Vector2i = um.call(dest)
			var d: float = _path_m(bot, a, b)
			var secs: float = d / carry
			sum += secs
			line += " %s:%4.1fs" % [letter, secs]
		var mean := sum / rooms.size()
		var work := float(j[3]) / 30.0
		tot_travel += mean
		tot_work += work
		line += "  | mean one-way %.1f s, hands-on %.1f s" % [mean, work]
		print(line)
	print("  across these jobs: mean one-way walk %.1f s vs %.1f s of hands-on action (%.0f%% walking, one way only)" % [tot_travel / jobs.size(), tot_work / jobs.size(), 100.0 * tot_travel / (tot_travel + tot_work)])
	var hall_w := float(sim.L.hall.size.x)
	print("  hall is %.0f m wide: crossing it takes %.1f s at %.1f m/s; the built floor is %d x %d tiles" % [hall_w, hall_w / speed, speed, sim.L.used.size.x, sim.L.used.size.y])
