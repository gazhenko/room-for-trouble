class_name SimEnv
extends RefCounted
## Environmental systems integrated exactly once per elapsed hotel second (§9).

const Q := SimC.HOTEL_Q_PER_S

static func integrate_second(sim: HotelSim) -> void:
	if sim.has_sys("thermal"):
		_thermal(sim)
	else:
		for letter in sim.s["rooms"]:
			var r: Dictionary = sim.s["rooms"][letter]
			r["heat"] = clampi(r["heat"] + r["pend_heat"], SimC.HEAT_MIN, SimC.HEAT_MAX)
			r["pend_heat"] = 0
	_sound(sim)
	_moisture(sim)
	_steam_and_puddles(sim)
	_thresholds(sim)
	_trips(sim)

# ------------------------------------------------------------- thermal §9.2

static func _thermal(sim: HotelSim) -> void:
	var rooms: Dictionary = sim.s["rooms"]
	var snap := {}
	for letter in rooms:
		snap[letter] = rooms[letter]["heat"]
	var delta := {}
	for letter in rooms:
		delta[letter] = 0
	# 2. edges
	for e in sim.L.thermal_edges:
		if not sim.s["gates"].get(e, false):
			continue
		var ab := sim.L.edge_rooms(e)
		var a: String = ab[0]
		var b: String = ab[1]
		if not rooms[a]["active"] or not rooms[b]["active"]:
			continue
		var f := SimC.round_half_away(8 * (snap[b] - snap[a]), 100)
		f = clampi(f, -8, 8)
		delta[a] += f
		delta[b] -= f
	# 3. occupant sources
	for letter in rooms:
		var r: Dictionary = rooms[letter]
		if r["guest"] != 0:
			var g := sim.guest(r["guest"])
			if g.get("state", "") == "staying":
				delta[letter] += int(sim.content.guest_def(g["fam"]).get("occupied_heat", 0))
	# 4. ambient relaxation
	for letter in rooms:
		delta[letter] -= SimC.sign_(snap[letter])
	# 5–6. radiator requests and shared capacity
	var hot_req: Array = []
	var cold_req: Array = []
	for letter in rooms:
		var r: Dictionary = rooms[letter]
		if not r["active"]:
			continue
		if SimInteract.station_tripped(sim, "radiator_" + letter):
			continue
		var regulate: bool = r["guest"] != 0 or r["reserved"] != 0 or r["prepare"]
		if not regulate:
			continue
		var target := 0
		if r["thermo"] == "warm": target = SimC.TARGET_WARM
		elif r["thermo"] == "cool": target = SimC.TARGET_COOL
		var err: int = target - snap[letter]
		if err > 4:
			hot_req.append(letter)
		elif err < -4:
			cold_req.append(letter)
	var caps := {"balanced": [2, 2], "warm": [3, 1], "cool": [1, 3]}
	var cap: Array = caps.get(sim.s["st"]["pump"], [2, 2])
	var rot: int = sim.s["st"]["rot"]
	_allocate(hot_req, cap[0] * 8, 8, delta, rot)
	_allocate(cold_req, cap[1] * 8, -8, delta, rot)
	sim.s["st"]["rot"] = (rot + 1) % 6
	sim.s["st"]["hot_demand"] = hot_req.size()
	sim.s["st"]["cold_demand"] = cold_req.size()
	# 7. queued direct effects, clamp
	for letter in rooms:
		var r: Dictionary = rooms[letter]
		r["heat"] = clampi(snap[letter] + delta[letter] + r["pend_heat"], SimC.HEAT_MIN, SimC.HEAT_MAX)
		r["pend_heat"] = 0
	# Hot meets cold: humidity and limited steam (§9.4, §9.7)
	for e in sim.L.thermal_edges:
		if not sim.s["gates"].get(e, false):
			continue
		var ab2 := sim.L.edge_rooms(e)
		if not rooms[ab2[0]]["active"] or not rooms[ab2[1]]["active"]:
			continue
		if absi(snap[ab2[0]] - snap[ab2[1]]) >= 70:
			rooms[ab2[0]]["pend_hum"] += 3
			rooms[ab2[1]]["pend_hum"] += 3
			var key = "edge_steam_" + e
			var last := int(sim.s["director"].get(key, -9999)) if sim.s.has("director") else -9999
			if sim.s["hotel_s"] - last >= 25:
				if not sim.s.has("director"):
					sim.s["director"] = {}
				sim.s["director"][key] = sim.s["hotel_s"]
				var gp: Vector2i = sim.L.gates[e]
				SimDirector.request(sim, "threshold", "steam", "", {"x": gp.x * SimC.UM, "z": gp.y * SimC.UM, "edge": e})

## Divides requests proportionally; integer remainder in rotating room order.
static func _allocate(reqs: Array, available: int, each: int, delta: Dictionary, rot: int) -> void:
	if reqs.is_empty():
		return
	var need := reqs.size() * absi(each)
	var sgn := SimC.sign_(each)
	if need <= available:
		for letter in reqs:
			delta[letter] += each
		return
	var base := available / reqs.size()
	var rem := available - base * reqs.size()
	var ordered: Array = []
	var letters: Array = delta.keys()
	for i in letters.size():
		var letter: String = letters[(i + rot) % letters.size()]
		if letter in reqs:
			ordered.append(letter)
	for letter in ordered:
		var amt := base
		if rem > 0:
			amt += 1
			rem -= 1
		delta[letter] += sgn * amt

static func heat_pulse(sim: HotelSim, letter: String, d: int) -> void:
	sim.room(letter)["pend_heat"] += d

# ------------------------------------------------------------- sound §9.3

static func _sound(sim: HotelSim) -> void:
	var rooms: Dictionary = sim.s["rooms"]
	for letter in rooms:
		var r: Dictionary = rooms[letter]
		r["noise"] = maxi(0, r["noise"] - SimC.NOISE_DECAY)
	for letter in rooms:
		var r: Dictionary = rooms[letter]
		var pulses: Array = r["pulses"]
		r["pulses"] = []
		for p in pulses:
			_emit_pulse(sim, letter, int(p["amp"]), p)

static func queue_pulse(sim: HotelSim, letter: String, amp: int, meta: Dictionary = {}) -> void:
	var p := meta.duplicate()
	p["amp"] = amp
	sim.room(letter)["pulses"].append(p)

static func _emit_pulse(sim: HotelSim, src: String, amp: int, meta: Dictionary) -> void:
	var rooms: Dictionary = sim.s["rooms"]
	var src_curt: bool = rooms[src]["curtain"] != 0
	var own := amp
	if src_curt:
		own = SimC.round_half_away(amp * 2, 10)
	rooms[src]["noise"] = mini(100, rooms[src]["noise"] + own)
	var received := {}
	if sim.has_sys("sound"):
		for e in sim.L.acoustic_edges:
			var ab := sim.L.edge_rooms(e)
			var dst := ""
			if ab[0] == src: dst = ab[1]
			elif ab[1] == src: dst = ab[0]
			if dst == "" or not rooms[dst]["active"]:
				continue
			# round(2/3 × amp × [0.2] × [0.2]) — one rounding after all multipliers.
			var num := amp * 2
			var den := 3
			if src_curt:
				num *= 2; den *= 10
			if rooms[dst]["curtain"] != 0:
				num *= 2; den *= 10
			var v := SimC.round_half_away(num, den)
			rooms[dst]["noise"] = mini(100, rooms[dst]["noise"] + v)
			received[dst] = v
	sim.emit("sound_pulse", {"room": src, "amp": amp, "own": own, "recv": received,
		"curtain_src": src_curt, "kind": meta.get("kind", "pulse")})
	if meta.get("kind", "") == "howl":
		SimScore.note_howl(sim, src, received)

static func staff_step_noise(sim: HotelSim, st: Dictionary) -> void:
	if not sim.is_active():
		return
	var letter := SimInteract.in_room(sim, st)
	if letter == "":
		return
	if st["noise_s"] == sim.s["hotel_s"]:
		return
	st["noise_s"] = sim.s["hotel_s"]
	queue_pulse(sim, letter, 12, {"kind": "step"})

# ------------------------------------------------------------- moisture §9.4

static func _moisture(sim: HotelSim) -> void:
	var rooms: Dictionary = sim.s["rooms"]
	var moist := sim.has_sys("moisture")
	for letter in rooms:
		var r: Dictionary = rooms[letter]
		var h: int = r["hum"]
		h += r["pend_hum"]
		r["pend_hum"] = 0
		if h > SimC.HUMIDITY_BASE: h -= 1
		elif h < SimC.HUMIDITY_BASE: h += 1
		if moist and r["tray"] > 0:
			r["tray"] -= 1
			if h < 75:
				h = mini(75, h + 3)
		if r["guest"] != 0:
			var g := sim.guest(r["guest"])
			if g.get("state", "") == "staying" and g["fam"] == "sprout":
				h += 1
		r["hum"] = clampi(h, 0, 100)
		if not moist:
			continue
		if r["over_cd"] > 0:
			r["over_cd"] -= 1
		if r["hum"] >= 90:
			r["over_n"] += 1
			if r["over_n"] >= 8 and r["over_cd"] == 0:
				r["over_n"] = 0
				r["hum"] -= 15
				r["over_cd"] = 25
				SimDirector.request(sim, "threshold", "overflow", letter, {})
		else:
			r["over_n"] = 0

static func humidity_pulse(sim: HotelSim, letter: String, d: int) -> void:
	sim.room(letter)["pend_hum"] += d

# ------------------------------------------------------------- steam & puddles

static func _steam_and_puddles(sim: HotelSim) -> void:
	var dead: Array = []
	for cid in sim.s["clouds"]:
		var c: Dictionary = sim.s["clouds"][cid]
		c["life"] -= 1
		if c["life"] <= 0:
			dead.append(cid)
	for cid in dead:
		sim.s["clouds"].erase(cid)
		sim.emit("cloud_gone", {"id": cid})
	dead.clear()
	for pid in sim.s["puddles"]:
		var p: Dictionary = sim.s["puddles"][pid]
		p["life"] -= 1
		if p["life"] <= 0:
			dead.append(pid)
	for pid in dead:
		sim.s["puddles"].erase(pid)
		sim.emit("puddle_gone", {"id": pid, "dried": true})

static func add_cloud(sim: HotelSim, x: int, z: int, why: String) -> int:
	if sim.s["clouds"].size() >= sim.s["cloud_cap"]:
		return 0
	var cid := sim.alloc_id()
	sim.s["clouds"][cid] = {"id": cid, "x": x, "z": z, "life": SimC.STEAM_LIFE_S, "why": why}
	sim.emit("cloud", {"id": cid, "why": why})
	return cid

static func puddle_spot_ok(sim: HotelSim, x: int, z: int) -> bool:
	var F: Dictionary = sim.L.fixtures
	var anchors: Array = []
	for p in F["pedestals"]:
		anchors.append(p)
	for k in ["reception", "group_bell", "linen_shelf", "hamper", "towel_shelf", "snack_tin", "welcome_kiosk", "return_shelf", "tap"]:
		if F.has(k):
			anchors.append(F[k])
	for p in F.get("mop_docks", []):
		anchors.append(p)
	for a in anchors:
		var ax: int = a.x * SimC.UM
		var az: int = a.y * SimC.UM
		if absi(ax - x) < 700_000 and absi(az - z) < 700_000:
			return false
	for pid in sim.s["puddles"]:
		var p: Dictionary = sim.s["puddles"][pid]
		if absi(p["x"] - x) < 600_000 and absi(p["z"] - z) < 600_000:
			return false
	return SimMove.point_free(sim, x, z, 200_000)

static func add_puddle(sim: HotelSim, x: int, z: int, why: String) -> int:
	if sim.s["puddles"].size() >= SimC.PUDDLE_BOARD_CAP:
		return 0
	var pid := sim.alloc_id()
	sim.s["puddles"][pid] = {"id": pid, "x": x, "z": z, "life": SimC.PUDDLE_LIFE_S, "why": why, "born_s": sim.s["hotel_s"]}
	sim.emit("puddle", {"id": pid, "why": why})
	return pid

## Nearest safe floor spot within 1.5 m of the requested point (§15.1).
static func safe_puddle_near(sim: HotelSim, x: int, z: int) -> Vector2i:
	if puddle_spot_ok(sim, x, z):
		return Vector2i(x, z)
	var best := Vector2i(-1, -1)
	var best_d := 1 << 62
	var stepu := 250_000
	for j in range(-6, 7):
		for i in range(-6, 7):
			var px := x + i * stepu
			var pz := z + j * stepu
			var d := (px - x) * (px - x) + (pz - z) * (pz - z)
			if d > 1_500_000 * 1_500_000:
				continue
			if not sim.L.hall.has_point(Vector2i(LayoutDef.tile_of(px), LayoutDef.tile_of(pz))):
				continue
			if puddle_spot_ok(sim, px, pz) and d < best_d:
				best_d = d
				best = Vector2i(px, pz)
	return best

# ------------------------------------------------------------- thresholds

static func _thresholds(sim: HotelSim) -> void:
	var rooms: Dictionary = sim.s["rooms"]
	for letter in rooms:
		var r: Dictionary = rooms[letter]
		if not r["active"]:
			continue
		if r["frost_cd"] > 0:
			r["frost_cd"] -= 1
		if r["puff_cd"] > 0:
			r["puff_cd"] -= 1
		if sim.has_sys("thermal"):
			if r["frost"]:
				if r["heat"] > -40:
					r["frost_warm"] += 1
					if r["frost_warm"] >= 6:
						r["frost"] = false
						r["frost_warm"] = 0
						r["frost_cd"] = 20
						sim.emit("frost_cleared", {"room": letter, "warmed": true})
				else:
					r["frost_warm"] = 0
			else:
				if r["heat"] <= -65:
					r["frost_cold"] += 1
					if r["frost_cold"] >= 4 and r["frost_cd"] == 0:
						r["frost_cold"] = 0
						SimDirector.request(sim, "threshold", "frost", letter, {})
				else:
					r["frost_cold"] = 0
			if r["heat"] >= 80:
				r["puff_hot"] += 1
				if r["puff_hot"] >= 4 and r["puff_cd"] == 0:
					r["puff_hot"] = 0
					r["puff_cd"] = 25
					var d := SimInteract.door_pos(sim, letter)
					SimDirector.request(sim, "threshold", "steam", letter, {"x": d.x, "z": d.y})
			else:
				r["puff_hot"] = 0

static func set_frost(sim: HotelSim, letter: String) -> void:
	var r := sim.room(letter)
	if r["frost"]:
		return
	r["frost"] = true
	r["frost_warm"] = 0
	sim.emit("frost", {"room": letter})

# ------------------------------------------------------------- trips §9.6

static func _trips(sim: HotelSim) -> void:
	var trips: Dictionary = sim.s["st"]["trips"]
	var done: Array = []
	for fx in trips:
		var t: Dictionary = trips[fx]
		if t.get("on", false):
			t["left"] -= 1
			if t["left"] <= 0:
				done.append(fx)
	for fx in done:
		trips.erase(fx)
		sim.emit("trip_reset", {"fixture": fx, "auto": true})

static func trip(sim: HotelSim, fixture: String) -> void:
	sim.s["st"]["trips"][fixture] = {"on": true, "left": SimC.TRIP_AUTO_S}
	sim.emit("trip", {"fixture": fixture})

static func reset_trip(sim: HotelSim, fixture: String, seat: int) -> void:
	if sim.s["st"]["trips"].has(fixture):
		sim.s["st"]["trips"].erase(fixture)
		sim.emit("trip_reset", {"fixture": fixture, "seat": seat})
