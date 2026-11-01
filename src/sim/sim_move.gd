class_name SimMove
extends RefCounted
## Collision-safe staff movement (§6.2, §19.4). Staff are points against static
## AABBs expanded by the capsule radius; the dominant axis resolves first, then
## the other slides. Players never collide with each other or guests.

static func step_all(sim: HotelSim) -> void:
	for st in sim.s["staff"]:
		if st["transp_t"] > 0:
			st["transp_t"] -= 1
		if st["step_cd"] > 0:
			st["step_cd"] -= 1
		if st["bump_t"] > 0:
			st["bump_t"] -= 1
		if int(st.get("stun_t", 0)) > 0:
			st["stun_t"] = int(st["stun_t"]) - 1
		if not st["present"]:
			st["vx"] = 0; st["vz"] = 0
			continue
		if st["grip"] != 0:
			continue   # trunk carriers move with the trunk
		_step_staff(sim, st)
	SimGoals.step_trunks(sim)

static func input_vec(st: Dictionary) -> Vector2i:
	var ax: int = st["ax"]
	var az: int = st["az"]
	var m2 := ax * ax + az * az
	if m2 < SimC.AXIS_DEADZONE * SimC.AXIS_DEADZONE:
		return Vector2i.ZERO
	var m := SimC.isqrt(m2)
	if m > 127:
		ax = ax * 127 / m
		az = az * 127 / m
	return Vector2i(ax, az)

static func _step_staff(sim: HotelSim, st: Dictionary) -> void:
	var inp := input_vec(st)
	var locked: bool = not st["act"].is_empty() and st["act"].get("lock", false) and st["act"].get("move_lock", true)
	if locked or int(st.get("stun_t", 0)) > 0:
		inp = Vector2i.ZERO
	# Quick step
	if st["step_t"] > 0:
		st["step_t"] -= 1
		var per := SimC.STEP_DIST / SimC.STEP_TICKS
		_sweep(sim, st, st["sdx"] * per / 1000, st["sdz"] * per / 1000)
		if st["step_t"] == 0:
			st["vx"] = st["sdx"] * SimC.SPEED / 1000
			st["vz"] = st["sdz"] * SimC.SPEED / 1000
		return
	if (st["pressed_btn"] & SimC.BTN_STEP) != 0 and st["step_cd"] == 0 and not locked \
			and not st.get("assists", {}).get("no_step", false) and sim.s["phase"] in ["planning", "active"]:
		var dx: int = st["fx"]; var dz: int = st["fz"]
		if inp != Vector2i.ZERO:
			var m := SimC.isqrt(inp.x * inp.x + inp.y * inp.y)
			dx = inp.x * 1000 / m; dz = inp.y * 1000 / m
		st["sdx"] = dx; st["sdz"] = dz
		st["step_t"] = SimC.STEP_TICKS
		st["step_cd"] = SimC.STEP_COOLDOWN
		sim.emit("quick_step", {"seat": st["seat"]})
		SimEnv.staff_step_noise(sim, st)
		return
	var speed := SimC.SPEED_CARRY if st["held"] != 0 else SimC.SPEED
	if _in_cloud(sim, st):
		speed = speed * SimC.CLOUD_SLOW_MILLI / 1000   # steam: you can still push through, slowly
	var tvx := inp.x * speed / 127
	var tvz := inp.y * speed / 127
	var accel := SimC.ACCEL
	var decel := SimC.DECEL
	if st["slide_t"] > 0:
		st["slide_t"] -= 1
		accel = accel * 3 / 10
	var dvx: int = tvx - st["vx"]
	var dvz: int = tvz - st["vz"]
	var dv := SimC.isqrt(dvx * dvx + dvz * dvz)
	var cur2: int = st["vx"] * st["vx"] + st["vz"] * st["vz"]
	var tgt2 := tvx * tvx + tvz * tvz
	var lim := accel if tgt2 > cur2 else decel
	if dv > lim:
		dvx = dvx * lim / dv
		dvz = dvz * lim / dv
	st["vx"] += dvx
	st["vz"] += dvz
	if inp != Vector2i.ZERO:
		var m2 := SimC.isqrt(inp.x * inp.x + inp.y * inp.y)
		st["fx"] = inp.x * 1000 / m2
		st["fz"] = inp.y * 1000 / m2
		st["idle_t"] = 0
	else:
		st["idle_t"] += 1
	st["moving"] = st["vx"] != 0 or st["vz"] != 0
	if st["moving"]:
		var blocked := _sweep(sim, st, st["vx"], st["vz"])
		if blocked.x != 0:
			st["vx"] = 0
		if blocked.y != 0:
			st["vz"] = 0
		if (blocked.x != 0 or blocked.y != 0) and inp != Vector2i.ZERO:
			_corner_assist(sim, st, inp, blocked)
	_puddle_contact(sim, st)

## Moves st by (dx,dz) with axis-separated sweeps. Returns which axes were blocked.
static func _sweep(sim: HotelSim, st: Dictionary, dx: int, dz: int) -> Vector2i:
	var bx := 0
	var bz := 0
	if absi(dx) >= absi(dz):
		var nx := sweep_axis(sim, st["x"], st["z"], dx, true, SimC.RADIUS)
		if nx != st["x"] + dx: bx = 1
		st["x"] = nx
		var nz := sweep_axis(sim, st["x"], st["z"], dz, false, SimC.RADIUS)
		if nz != st["z"] + dz: bz = 1
		st["z"] = nz
	else:
		var nz := sweep_axis(sim, st["x"], st["z"], dz, false, SimC.RADIUS)
		if nz != st["z"] + dz: bz = 1
		st["z"] = nz
		var nx := sweep_axis(sim, st["x"], st["z"], dx, true, SimC.RADIUS)
		if nx != st["x"] + dx: bx = 1
		st["x"] = nx
	return Vector2i(bx, bz)

## Returns the reachable coordinate along one axis. Boxes are expanded by r.
static func sweep_axis(sim: HotelSim, x: int, z: int, d: int, along_x: bool, r: int, ignore_dynamic := false) -> int:
	if d == 0:
		return x if along_x else z
	var pos := x if along_x else z
	var target := pos + d
	var other := z if along_x else x
	var boxes := solid_boxes_near(sim, x, z, ignore_dynamic)
	for b in boxes:
		var o0: int = (b[1] if along_x else b[0]) - r
		var o1: int = (b[3] if along_x else b[2]) + r
		if other <= o0 or other >= o1:
			continue
		var a0: int = (b[0] if along_x else b[1]) - r
		var a1: int = (b[2] if along_x else b[3]) + r
		if d > 0:
			if pos <= a0 and target > a0:
				target = a0
		else:
			if pos >= a1 and target < a1:
				target = a1
	return target

static func solid_boxes_near(sim: HotelSim, x: int, z: int, ignore_dynamic := false) -> Array:
	var out: Array = []
	var tx := LayoutDef.tile_of(x)
	var tz := LayoutDef.tile_of(z)
	var L := sim.L
	for j in range(tz - 2, tz + 3):
		for i in range(tx - 2, tx + 3):
			if L.is_wall_tile(i, j) or _dynamic_solid(sim, i, j, ignore_dynamic):
				out.append([i * SimC.UM - 500_000, j * SimC.UM - 500_000, i * SimC.UM + 500_000, j * SimC.UM + 500_000])
	for b in L.boxes:
		if absi((b[0] + b[2]) / 2 - x) < 3_000_000 and absi((b[1] + b[3]) / 2 - z) < 3_000_000:
			out.append(b)
	return out

static func _dynamic_solid(sim: HotelSim, i: int, j: int, ignore_dynamic: bool) -> bool:
	if ignore_dynamic:
		return false
	var sh: Vector2i = sim.L.shutter
	if sh.x == i and sh.y == j and sim.s["shutter"]["state"] == "closed":
		return true
	return false

static func point_free(sim: HotelSim, x: int, z: int, r: int) -> bool:
	if x < -500_000 + r or z < -500_000 + r or x > 27_500_000 - r or z > 19_500_000 - r:
		return false
	for b in solid_boxes_near(sim, x, z):
		if x > b[0] - r and x < b[2] + r and z > b[1] - r and z < b[3] + r:
			return false
	return true

## Nudges a blocked avatar around door corners and station corners so 1 m
## doorways feel generous and brushing a 0.75 m fixture slides you past it
## (probes reach 0.72 m: a fixture half-width plus the capsule radius).
static func _corner_assist(sim: HotelSim, st: Dictionary, inp: Vector2i, blocked: Vector2i) -> void:
	var primary_x := absi(inp.x) > absi(inp.y)
	if primary_x and blocked.x == 0:
		return
	if not primary_x and blocked.y == 0:
		return
	var probe := 140_000
	var dir_main := SimC.sign_(inp.x if primary_x else inp.y)
	for off in [120_000, -120_000, 240_000, -240_000, 360_000, -360_000, 480_000, -480_000, 600_000, -600_000, 720_000, -720_000]:
		var px: int = st["x"] + (0 if primary_x else off)
		var pz: int = st["z"] + (off if primary_x else 0)
		var qx: int = px + (dir_main * probe if primary_x else 0)
		var qz: int = pz + (0 if primary_x else dir_main * probe)
		if point_free(sim, px, pz, SimC.RADIUS) and point_free(sim, qx, qz, SimC.RADIUS):
			var stepv := 60_000 * SimC.sign_(off)
			if primary_x:
				st["z"] = sweep_axis(sim, st["x"], st["z"], stepv, false, SimC.RADIUS)
			else:
				st["x"] = sweep_axis(sim, st["x"], st["z"], stepv, true, SimC.RADIUS)
			return

## True while the avatar stands inside a steam cloud.
static func _in_cloud(sim: HotelSim, st: Dictionary) -> bool:
	for cid in sim.s.get("clouds", {}):
		var c: Dictionary = sim.s["clouds"][cid]
		var dx: int = int(c["x"]) - int(st["x"])
		var dz: int = int(c["z"]) - int(st["z"])
		if dx * dx + dz * dz < SimC.STEAM_RADIUS * SimC.STEAM_RADIUS:
			return true
	return false

## Puddles and frozen doorsteps send a running avatar into a short slide.
static func _puddle_contact(sim: HotelSim, st: Dictionary) -> void:
	if st.get("assists", {}).get("steady_feet", false):
		return
	for pid in sim.s["puddles"]:
		var p: Dictionary = sim.s["puddles"][pid]
		var dx: int = p["x"] - st["x"]
		var dz: int = p["z"] - st["z"]
		if dx * dx + dz * dz < 420_000 * 420_000:
			if st["slide_t"] == 0 and (st["vx"] != 0 or st["vz"] != 0):
				st["slide_t"] = SimC.SLIDE_TICKS
				sim.emit("wet_feet", {"seat": st["seat"], "puddle": pid})
			return
	for letter in sim.L.active_rooms:
		if not sim.s["rooms"][letter].get("frost", false):
			continue
		var d: Vector2i = sim.L.rooms[letter]["door"]
		var fx: int = d.x * SimC.UM - st["x"]
		var fz: int = d.y * SimC.UM - st["z"]
		if fx * fx + fz * fz < 650_000 * 650_000:
			if st["slide_t"] == 0 and (st["vx"] != 0 or st["vz"] != 0):
				st["slide_t"] = SimC.SLIDE_TICKS
				sim.emit("slip", {"seat": st["seat"], "kind": "frost", "room": letter})
			return

static func dist(ax: int, az: int, bx: int, bz: int) -> int:
	var dx := ax - bx
	var dz := az - bz
	return SimC.isqrt(dx * dx + dz * dz)

## True when the segment between two points crosses no wall tile.
static func line_clear(sim: HotelSim, ax: int, az: int, bx: int, bz: int) -> bool:
	var d := dist(ax, az, bx, bz)
	var n := maxi(1, d / 100_000)
	for i in range(1, n):
		var px := ax + (bx - ax) * i / n
		var pz := az + (bz - az) * i / n
		var tx := LayoutDef.tile_of(px)
		var tz := LayoutDef.tile_of(pz)
		if sim.L.is_wall_tile(tx, tz) or _dynamic_solid(sim, tx, tz, false):
			return false
	return true
