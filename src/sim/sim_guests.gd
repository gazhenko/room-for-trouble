class_name SimGuests
extends RefCounted
## Guest lifecycle (§5.1, §8): announced → lobby → walking → staying →
## departing, or lobby → cozy corner. Nonblocking deterministic navigation.

const Q := SimC.HOTEL_Q_PER_S

static func make_guest(sim: HotelSim, gid: int, fam: String, variant: String, a: Dictionary) -> Dictionary:
	var gdef: Dictionary = sim.content.guest_def(fam)
	var out := sim.L.outside
	return {
		"id": gid, "fam": fam, "var": variant, "ai": int(a.get("arrival_index", 0)), "wave": int(a.get("wave", 0)),
		"state": "announced", "arrive_q": int(a["arrive_s"]) * Q, "announce_q": int(a["announce_s"]) * Q,
		"slot": -1, "ticket": 0, "room": "", "patience_q": SimC.PATIENCE_S * Q,
		"stay_start_q": 0, "stay_s": 0, "stay_len": int(gdef.get("stay_s", 70)), "checkout_q": 0,
		"welcomed": false, "reqs": [], "comf_s": 0, "occ_s": 0, "samples": [], "streak": 0,
		"quirk": "pending", "quirk_q": 0, "quirk_mech": false,
		"helper_used": false, "helper_ready": false, "moved": false, "move_ticket": 0, "relocating": false,
		"admitted": false, "abandoned": false,
		"x": int(out.x * SimC.UM), "z": int(out.y * SimC.UM), "path": [], "pi": 0, "walk_q": 0,
		"trail_n": 0, "trail_d": 0, "leave_q": 0, "happy": 70, "mood": "content", "need": "",
		"last_fail_q": -999 * Q, "comfortable": true, "dest": [0, 0], "anim": "walk", "face": 1,
		"cozy_q": 0, "vent_mark_s": -999, "watered": false, "water_comf": false, "quiet_howls": 0,
		"announced": false, "hold_stay": false,
	}

# ============================================================ per tick

static func step_tick(sim: HotelSim) -> void:
	var hq: int = sim.s["hotel_q"]
	var pace: int = sim.s["pace"]
	for gid in sim.s["guests"]:
		var g: Dictionary = sim.s["guests"][gid]
		match g["state"]:
			"announced":
				if not g["announced"] and hq >= g["announce_q"]:
					g["announced"] = true
					sim.emit("guest_announce", {"id": gid, "fam": g["fam"]})
				if hq >= g["arrive_q"]:
					_arrive(sim, g)
			"lobby":
				if not sim.s["cozy"] and not g.get("tut", false) and not g.get("play", false):
					g["patience_q"] -= pace
					if g["patience_q"] <= 0:
						_to_cozy_corner(sim, g)
				_walk(sim, g, pace)
			"walking":
				_walk(sim, g, pace)
				g["walk_q"] += pace
				if g["pi"] >= g["path"].size():
					_reach_room(sim, g)
				elif g["walk_q"] >= SimC.WALK_BOUND_S * Q:
					sim.emit("guest_sparkle", {"id": gid})
					g["x"] = g["dest"][0]; g["z"] = g["dest"][1]
					g["pi"] = g["path"].size()
					_reach_room(sim, g)
			"staying":
				if g["relocating"]:
					_walk(sim, g, pace)
					g["walk_q"] += pace
					if g["pi"] >= g["path"].size() or g["walk_q"] >= SimC.WALK_BOUND_S * Q:
						if g["pi"] < g["path"].size():
							g["x"] = g["dest"][0]; g["z"] = g["dest"][1]
							g["pi"] = g["path"].size()
							sim.emit("guest_sparkle", {"id": gid})
						_finish_relocation(sim, g)
				_step_requests(sim, g, hq)
				_step_quirk_timer(sim, g, hq)
				if not g["hold_stay"] and _checkout_due(sim, g, hq):
					_checkout(sim, g)
			"departing":
				_walk(sim, g, pace)
				g["leave_q"] += pace
				if g["pi"] >= g["path"].size() or g["leave_q"] >= 20 * Q:
					g["state"] = "gone"
					sim.emit("guest_gone", {"id": gid})
			"cozy":
				g["cozy_q"] += pace
				if g["cozy_q"] >= SimC.COZY_CORNER_S * Q:
					g["state"] = "gone"
					sim.emit("guest_gone", {"id": gid})

static func step_tick_paused(sim: HotelSim) -> void:
	pass

static func _arrive(sim: HotelSim, g: Dictionary) -> void:
	var slot := _free_pedestal(sim)
	var tid := sim.new_item("ticket", {"loc": "sock", "g": g["id"]})
	g["ticket"] = tid
	if slot >= 0:
		sim.s["pedestals"][slot] = g["id"]
		g["slot"] = slot
		sim.item(tid)["sock"] = "ped:%d" % slot
		sim.item(tid)["home"] = str(slot)
	else:
		sim.s["bench"].append(g["id"])
		sim.item(tid)["sock"] = "bench"
		sim.item(tid)["home"] = ""
	g["state"] = "lobby"
	var spot := queue_spot(sim, g)
	g["path"] = path_to(sim, g["x"], g["z"], spot.x, spot.y)
	g["pi"] = 0
	sim.emit("guest_arrive", {"id": g["id"], "fam": g["fam"], "slot": slot})

static func queue_spot(sim: HotelSim, g: Dictionary) -> Vector2i:
	if g["slot"] >= 0:
		var p: Vector2i = sim.L.fixtures["pedestals"][g["slot"]]
		return Vector2i(p.x * SimC.UM, int((p.y + sim.L.queue_offset_z) * SimC.UM))
	var idx: int = sim.s["bench"].find(g["id"])
	var b := sim.L.outside_bench
	return Vector2i(int(b.x * SimC.UM), int((b.y + 0.6 * idx) * SimC.UM))

static func _free_pedestal(sim: HotelSim) -> int:
	var peds: Array = sim.s["pedestals"]
	for i in peds.size():
		if peds[i] == 0:
			return i
	return -1

static func _release_pedestal(sim: HotelSim, g: Dictionary) -> void:
	if g["slot"] >= 0:
		sim.s["pedestals"][g["slot"]] = 0
		g["slot"] = -1
	else:
		sim.s["bench"].erase(g["id"])
	_promote_bench(sim)

static func _promote_bench(sim: HotelSim) -> void:
	while not sim.s["bench"].is_empty():
		var slot := _free_pedestal(sim)
		if slot < 0:
			return
		var gid: int = sim.s["bench"].pop_front()
		var g := sim.guest(gid)
		sim.s["pedestals"][slot] = gid
		g["slot"] = slot
		var t := sim.item(g["ticket"])
		if not t.is_empty() and t["loc"] == "sock" and t["sock"] == "bench":
			t["sock"] = "ped:%d" % slot
		if not t.is_empty():
			t["home"] = str(slot)
		var spot := queue_spot(sim, g)
		g["path"] = path_to(sim, g["x"], g["z"], spot.x, spot.y)
		g["pi"] = 0

static func _to_cozy_corner(sim: HotelSim, g: Dictionary) -> void:
	if g["ticket"] != 0:
		var t := sim.item(g["ticket"])
		if not t.is_empty() and t["loc"] == "held":
			var st := sim.staff_by_seat(t["seat"])
			if not st.is_empty():
				st["held"] = 0
		sim.consume_item(g["ticket"], "timeout")
		g["ticket"] = 0
	_release_pedestal(sim, g)
	g["state"] = "cozy"
	g["abandoned"] = true
	g["cozy_q"] = 0
	var c := sim.L.cozy_corner
	g["path"] = path_to(sim, g["x"], g["z"], int(c.x * SimC.UM), int(c.y * SimC.UM))
	g["pi"] = 0
	sim.emit("guest_cozy", {"id": g["id"], "fam": g["fam"]})

# ============================================================ assignment

static func bedside(sim: HotelSim, letter: String) -> Vector2i:
	var gr: Dictionary = sim.L.rooms[letter]
	var b: Vector2i = gr["bed"]
	var dz := 0.75 if gr["side"] == "north" else -0.75
	return Vector2i(b.x * SimC.UM, int((b.y + dz) * SimC.UM))

static func assign(sim: HotelSim, gid: int, letter: String, seat: int) -> void:
	var g := sim.guest(gid)
	var r := sim.room(letter)
	r["reserved"] = gid
	g["room"] = letter
	g["ticket"] = 0
	g["admitted"] = true
	_release_pedestal(sim, g)
	g["state"] = "walking"
	g["walk_q"] = 0
	var dest := bedside(sim, letter)
	g["dest"] = [dest.x, dest.y]
	g["path"] = path_to(sim, g["x"], g["z"], dest.x, dest.y)
	g["pi"] = 0
	g["trail_d"] = 0
	sim.emit("assign", {"guest": gid, "room": letter, "seat": seat, "fam": g["fam"]})
	SimScore.note_admit(sim, g, seat)

static func cancel_reservation(sim: HotelSim, letter: String, seat: int) -> void:
	var r := sim.room(letter)
	var g := sim.guest(r["reserved"])
	if g.is_empty() or g["state"] != "walking":
		return
	r["reserved"] = 0
	g["room"] = ""
	g["state"] = "lobby"
	g["admitted"] = false
	var slot := _free_pedestal(sim)
	var tid := sim.new_item("ticket", {"loc": "sock", "g": g["id"]})
	g["ticket"] = tid
	if slot >= 0:
		sim.s["pedestals"][slot] = g["id"]
		g["slot"] = slot
		sim.item(tid)["sock"] = "ped:%d" % slot
		sim.item(tid)["home"] = str(slot)
	else:
		g["slot"] = -1
		sim.s["bench"].append(g["id"])
		sim.item(tid)["sock"] = "bench"
	var spot := queue_spot(sim, g)
	g["path"] = path_to(sim, g["x"], g["z"], spot.x, spot.y)
	g["pi"] = 0
	SimScore.unnote_admit(sim, g)
	sim.emit("reservation_cancel", {"guest": g["id"], "room": letter, "seat": seat})

static func _reach_room(sim: HotelSim, g: Dictionary) -> void:
	var r := sim.room(g["room"])
	r["reserved"] = 0
	r["guest"] = g["id"]
	g["state"] = "staying"
	g["stay_start_q"] = sim.s["hotel_q"]
	g["checkout_q"] = g["stay_start_q"] + g["stay_len"] * Q
	g["quirk_q"] = g["stay_start_q"] + SimC.QUIRK_AT_S * Q
	_build_requests(sim, g)
	if r["gift"] != 0 and sim.item(r["gift"]).get("k", "") == "welcome_" + g["fam"]:
		_set_welcomed(sim, g, -1)
	g["comfortable"] = comfort_test(sim, g["fam"], r)
	sim.emit("guest_room", {"id": g["id"], "room": g["room"], "fam": g["fam"]})
	if sim.tutorial != null:
		sim.tutorial.on_guest_room(sim, g)

static func _build_requests(sim: HotelSim, g: Dictionary) -> void:
	var n := int(sim.level.get("service_count", 1))
	var offs := [22] if n == 1 else [15, 40]
	var order := ["towel", "snack"] if g["ai"] % 2 == 0 else ["snack", "towel"]
	var mods: Array = sim.cfg.get("modifiers", [])
	g["reqs"] = []
	for i in offs.size():
		var k: String = order[i]
		if "extra_towels" in mods: k = "towel"
		elif "snack_social" in mods: k = "snack"
		var at: int = g["stay_start_q"] + int(offs[i]) * Q
		var dl: int = at + SimC.REQUEST_S * Q
		var late: int = mini(dl + SimC.LATE_S * Q, g["checkout_q"])
		g["reqs"].append({"k": k, "at": at, "dl": dl, "late": late, "st": "wait", "i": i})

# ============================================================ relocation

static func relocate(sim: HotelSim, gid: int, dest_letter: String, seat: int) -> void:
	var g := sim.guest(gid)
	if g.is_empty() or g["state"] != "staying" or g["moved"]:
		return
	var src := sim.room(g["room"])
	var dst := sim.room(dest_letter)
	src["guest"] = 0
	src["bed"] = "Dirty"
	src["mess"] = 100
	src["mess_milli"] = 100_000
	dst["reserved"] = gid
	var from_room: String = g["room"]
	g["room"] = dest_letter
	g["moved"] = true
	g["relocating"] = true
	g["move_ticket"] = 0
	g["walk_q"] = 0
	var dest := bedside(sim, dest_letter)
	g["dest"] = [dest.x, dest.y]
	g["path"] = path_to(sim, g["x"], g["z"], dest.x, dest.y)
	g["pi"] = 0
	SimScore.bump(sim, "relocations")
	sim.emit("relocate", {"guest": gid, "from": from_room, "to": dest_letter, "seat": seat})

static func _finish_relocation(sim: HotelSim, g: Dictionary) -> void:
	var r := sim.room(g["room"])
	r["reserved"] = 0
	r["guest"] = g["id"]
	g["relocating"] = false
	if r["gift"] != 0 and sim.item(r["gift"]).get("k", "") == "welcome_" + g["fam"]:
		_set_welcomed(sim, g, -1)
	sim.emit("guest_room", {"id": g["id"], "room": g["room"], "fam": g["fam"], "relocated": true})

# ============================================================ requests

static func open_request(sim: HotelSim, g: Dictionary, kind: String) -> int:
	if g.is_empty():
		return -1
	for rq in g["reqs"]:
		if rq["k"] == kind and rq["st"] == "open":
			return rq["i"]
	return -1

static func any_open_request(sim: HotelSim, g: Dictionary) -> bool:
	for rq in g["reqs"]:
		if rq["st"] == "open":
			return true
	return false

static func _step_requests(sim: HotelSim, g: Dictionary, hq: int) -> void:
	for rq in g["reqs"]:
		if rq["st"] == "wait" and hq >= rq["at"]:
			rq["st"] = "open"
			sim.emit("request_open", {"guest": g["id"], "room": g["room"], "k": rq["k"]})
		elif rq["st"] == "open" and not sim.s["cozy"] and hq > rq["late"]:
			rq["st"] = "missed"
			g["last_fail_q"] = hq
			sim.emit("request_missed", {"guest": g["id"], "room": g["room"], "k": rq["k"]})

static func fulfill(sim: HotelSim, g: Dictionary, idx: int, seat: int, item_id: int) -> void:
	var rq: Dictionary = g["reqs"][idx]
	var hq: int = sim.s["hotel_q"]
	var late: bool = not sim.s["cozy"] and hq > rq["dl"]
	rq["st"] = "late" if late else "done"
	SimScore.note_consumed(sim, sim.item(item_id), seat, "service")
	SimScore.bump(sim, "requests")
	sim.emit("request_done", {"guest": g["id"], "room": g["room"], "k": rq["k"], "late": late, "seat": seat})
	if sim.tutorial != null:
		sim.tutorial.on_request_done(sim, g)

static func _checkout_due(sim: HotelSim, g: Dictionary, hq: int) -> bool:
	if g["relocating"] or g.get("play", false):
		return false
	if hq < g["checkout_q"]:
		return false
	if sim.s["cozy"]:
		for rq in g["reqs"]:
			if rq["st"] in ["open", "wait"]:
				return false
	return true

static func goodbye_available(sim: HotelSim, g: Dictionary) -> bool:
	if g["state"] != "staying" or g["relocating"]:
		return false
	if sim.tutorial != null and sim.tutorial.goodbye_allowed(sim, g):
		return true
	if g.get("play", false):
		return true
	if sim.s["cozy"] and sim.s["hotel_q"] >= g["checkout_q"]:
		return true
	return false

static func wave_goodbye(sim: HotelSim, gid: int, seat: int) -> void:
	var g := sim.guest(gid)
	if g.is_empty() or not goodbye_available(sim, g):
		return
	for rq in g["reqs"]:
		if rq["st"] in ["open", "wait"]:
			rq["st"] = "missed"
	g["hold_stay"] = false
	g["checkout_q"] = mini(g["checkout_q"], sim.s["hotel_q"])
	sim.emit("wave_goodbye", {"guest": gid, "seat": seat})
	_checkout(sim, g)

static func _checkout(sim: HotelSim, g: Dictionary) -> void:
	var r := sim.room(g["room"])
	r["guest"] = 0
	r["bed"] = "Dirty"
	r["mess"] = 100
	r["mess_milli"] = 100_000
	if r["gift"] != 0 and sim.item(r["gift"]).get("k", "") == "welcome_" + g["fam"]:
		sim.consume_item(r["gift"], "checkout_return")
		r["gift"] = 0
	for rq in g["reqs"]:
		if rq["st"] in ["open", "wait"]:
			rq["st"] = "missed"
	g["state"] = "departing"
	g["leave_q"] = 0
	var o := sim.L.outside
	g["path"] = path_to(sim, g["x"], g["z"], int(o.x * SimC.UM), int(o.y * SimC.UM))
	g["pi"] = 0
	g["trail_d"] = 0
	SimScore.note_departure(sim, g)
	sim.emit("checkout", {"guest": g["id"], "room": g["room"], "fam": g["fam"]})
	if sim.tutorial != null:
		sim.tutorial.on_checkout(sim, g)

static func wrap_montage(sim: HotelSim) -> void:
	for gid in sim.s["guests"]:
		var g: Dictionary = sim.s["guests"][gid]
		if g["state"] in ["announced", "lobby"]:
			g["state"] = "gone"
			if g["ticket"] != 0:
				sim.consume_item(g["ticket"], "wrap")
				g["ticket"] = 0
		elif g["state"] == "walking":
			g["state"] = "gone"
		g["wrap_wave"] = true

# ============================================================ welcome

static func on_gift_installed(sim: HotelSim, letter: String, gift_id: int, seat: int) -> void:
	var r := sim.room(letter)
	var it := sim.item(gift_id)
	sim.emit("gift_placed", {"room": letter, "seat": seat, "k": it["k"]})
	if r["guest"] == 0:
		return
	var g := sim.guest(r["guest"])
	if g.is_empty() or g["state"] != "staying":
		return
	if it["k"] == "welcome_" + g["fam"]:
		SimScore.note_consumed(sim, it, seat, "gift")
		_set_welcomed(sim, g, seat)
	else:
		sim.emit("gift_wrong", {"room": letter, "guest": g["id"]})

static func _set_welcomed(sim: HotelSim, g: Dictionary, seat: int) -> void:
	if g["welcomed"]:
		return
	g["welcomed"] = true
	if g["fam"] == "slime":
		g["slippers_on"] = true
	SimScore.bump(sim, "welcome_matches")
	sim.emit("welcome", {"guest": g["id"], "room": g["room"], "fam": g["fam"], "seat": seat})
	if sim.tutorial != null:
		sim.tutorial.on_welcome(sim, g)

static func matching_gift_present(sim: HotelSim, g: Dictionary) -> bool:
	if g["room"] == "":
		return false
	var r := sim.room(g["room"])
	return r["gift"] != 0 and sim.item(r["gift"]).get("k", "") == "welcome_" + g["fam"]

# ============================================================ comfort per second

static func comfort_test(sim: HotelSim, fam: String, r: Dictionary) -> bool:
	var c: Dictionary = sim.content.guest_def(fam).get("comfort", {})
	if c.has("heat_min") and (r["heat"] < int(c["heat_min"]) or r["heat"] > int(c["heat_max"])):
		return false
	if c.has("noise_max") and r["noise"] > int(c["noise_max"]):
		return false
	if c.has("humidity_min") and r["hum"] < int(c["humidity_min"]):
		return false
	return true

static func step_second(sim: HotelSim) -> void:
	for gid in sim.s["guests"]:
		var g: Dictionary = sim.s["guests"][gid]
		if g["state"] != "staying":
			continue
		var r := sim.room(g["room"])
		var ok := comfort_test(sim, g["fam"], r)
		var was: bool = g["comfortable"]
		g["comfortable"] = ok
		if not g["hold_stay"]:
			g["stay_s"] += 1
			g["occ_s"] += 1
			if ok:
				g["comf_s"] += 1
		var samples: Array = g["samples"]
		samples.append(1 if ok else 0)
		while samples.size() > 12:
			samples.pop_front()
		g["streak"] = g["streak"] + 1 if ok else 0
		if ok and not was:
			sim.emit("comfort_recovered", {"guest": gid, "room": g["room"]})
		elif was and not ok:
			sim.emit("comfort_lost", {"guest": gid, "room": g["room"]})
		_update_happiness(sim, g)
		_update_helper(sim, g)
		SimScore.on_guest_second(sim, g, ok)
		if sim.tutorial != null:
			sim.tutorial.on_guest_second(sim, g)

static func _update_happiness(sim: HotelSim, g: Dictionary) -> void:
	var samples: Array = g["samples"]
	var cur := 1 if g["comfortable"] else 0
	var sum := 0
	for v in samples:
		sum += v
	sum += cur * (12 - samples.size())
	var welcome := 1 if matching_gift_present(sim, g) else 0
	var nofail := 1 if sim.s["hotel_q"] - g["last_fail_q"] > 12 * Q else 0
	g["happy"] = (70 * sum + 6) / 12 + 15 * welcome + 15 * nofail
	g["mood"] = "delighted" if g["happy"] >= 85 else ("content" if g["happy"] >= 55 else "inconvenienced")
	var need := ""
	if any_open_request(sim, g):
		need = "service"
	elif not g["comfortable"]:
		need = "comfort"
	elif not g["welcomed"]:
		need = "welcome"
	elif g["helper_ready"]:
		need = "helper"
	g["need"] = need

static func _update_helper(sim: HotelSim, g: Dictionary) -> void:
	var overdue := false
	for rq in g["reqs"]:
		if rq["st"] == "open" and sim.s["hotel_q"] > rq["dl"]:
			overdue = true
	var ready: bool = not g["helper_used"] and g["streak"] >= SimC.HELPER_STREAK_S and matching_gift_present(sim, g) and not overdue
	if ready and not g["helper_ready"]:
		sim.emit("helper_ready", {"guest": g["id"], "room": g["room"], "fam": g["fam"]})
	g["helper_ready"] = ready

# ============================================================ quirks (§8.2)

static func _step_quirk_timer(sim: HotelSim, g: Dictionary, hq: int) -> void:
	if g["quirk"] != "pending" or g["relocating"] or g["hold_stay"]:
		return
	if hq < g["quirk_q"]:
		return
	g["quirk"] = "done"
	var r := sim.room(g["room"])
	var comfy := comfort_test(sim, g["fam"], r)
	match g["fam"]:
		"slime":
			sim.emit("quirk_cosmetic", {"guest": g["id"], "room": g["room"], "gag": "slipper_flip"})
		"yeti":
			if comfy:
				sim.emit("quirk_cosmetic", {"guest": g["id"], "room": g["room"], "gag": "mitten_sneeze"})
			else:
				SimDirector.request(sim, "quirk", "sneeze", g["room"], {"guest": g["id"], "warn_s": 4})
		"dragon":
			if comfy:
				sim.emit("quirk_cosmetic", {"guest": g["id"], "room": g["room"], "gag": "kettle_hiccup"})
			else:
				SimDirector.request(sim, "quirk", "hiccup", g["room"], {"guest": g["id"], "warn_s": 4})
		"ghost":
			if r["noise"] > 20:
				_ghost_float_towel(sim, g)
			else:
				sim.emit("quirk_cosmetic", {"guest": g["id"], "room": g["room"], "gag": "sheet_hat"})
		"moonwolf":
			SimDirector.request(sim, "quirk", "howl", g["room"], {"guest": g["id"], "warn_s": 4})
		"sprout":
			if r["hum"] > 85:
				SimDirector.request(sim, "quirk", "bloom_puddle", g["room"], {"guest": g["id"], "warn_s": 0})
			else:
				sim.emit("quirk_cosmetic", {"guest": g["id"], "room": g["room"], "gag": "flower_pop"})

static func _ghost_float_towel(sim: HotelSim, g: Dictionary) -> void:
	var drop := SimInteract.um(sim.L.rooms[g["room"]]["drop"])
	for iid in sim.s["items"]:
		var it: Dictionary = sim.s["items"][iid]
		if it["k"] == "towel" and it["loc"] == "world" and SimMove.dist(it["x"], it["z"], g["x"], g["z"]) <= 2_000_000:
			it["x"] = drop.x; it["z"] = drop.y
			sim.emit("quirk_cosmetic", {"guest": g["id"], "room": g["room"], "gag": "towel_float", "item": iid})
			return
	sim.emit("quirk_cosmetic", {"guest": g["id"], "room": g["room"], "gag": "sheet_face"})

# ============================================================ helpers (§8.2)

static func helper_preview(sim: HotelSim, g: Dictionary) -> Dictionary:
	var stv: Dictionary = sim.s["st"]
	var r := sim.room(g["room"])
	match g["fam"]:
		"slime":
			var n := _puddles_near(sim, g, 8_000_000).size()
			return {"useful": n > 0, "text": "helper.slime", "n": mini(3, n)}
		"yeti":
			var useful: bool = stv["snacks"] < SimC.STOCK_CAP or r["heat"] != -35
			return {"useful": useful, "text": "helper.yeti"}
		"dragon":
			return {"useful": stv["hamper_q"] > 0 or stv["linen"] < SimC.LINEN_CAP, "text": "helper.dragon"}
		"ghost":
			return {"useful": _ghost_delivery_item(sim, g) != 0, "text": "helper.ghost"}
		"moonwolf":
			var any := false
			for gid in sim.s["guests"]:
				var o: Dictionary = sim.s["guests"][gid]
				if o["state"] == "lobby" and o["patience_q"] < SimC.PATIENCE_S * Q:
					any = true
			return {"useful": any, "text": "helper.moonwolf"}
		"sprout":
			return {"useful": r["hum"] < 80 or not sim.s["puddles"].is_empty(), "text": "helper.sprout"}
	return {"useful": false, "text": ""}

static func _puddles_near(sim: HotelSim, g: Dictionary, radius: int) -> Array:
	var door := SimInteract.door_pos(sim, g["room"])
	var out: Array = []
	for pid in sim.s["puddles"]:
		var p: Dictionary = sim.s["puddles"][pid]
		var d := SimMove.dist(p["x"], p["z"], door.x, door.y)
		if d <= radius:
			out.append([d, pid])
	out.sort()
	return out

static func _ghost_delivery_item(sim: HotelSim, g: Dictionary) -> int:
	var drop := SimInteract.um(sim.L.rooms[g["room"]]["drop"])
	var door := SimInteract.plaque_pos(sim, g["room"])
	for iid in sim.s["items"]:
		var it: Dictionary = sim.s["items"][iid]
		if it["loc"] != "world" or not it["k"] in ["towel", "snack"]:
			continue
		if open_request(sim, g, it["k"]) < 0:
			continue
		if SimMove.dist(it["x"], it["z"], drop.x, drop.y) <= 900_000 or SimMove.dist(it["x"], it["z"], door.x, door.y) <= 1_800_000:
			return iid
	return 0

static func invoke_helper(sim: HotelSim, gid: int, seat: int) -> void:
	var g := sim.guest(gid)
	if g.is_empty() or not g["helper_ready"] or g["helper_used"]:
		return
	var pv := helper_preview(sim, g)
	if not pv["useful"]:
		sim.emit("helper_idle", {"guest": gid})
		return
	var stv: Dictionary = sim.s["st"]
	var r := sim.room(g["room"])
	match g["fam"]:
		"slime":
			var list := _puddles_near(sim, g, 8_000_000)
			for i in mini(3, list.size()):
				sim.s["puddles"].erase(list[i][1])
				sim.emit("puddle_gone", {"id": list[i][1], "helper": gid})
		"yeti":
			var h: int = r["heat"]
			r["heat"] = mini(h + 20, -35) if h < -35 else maxi(h - 20, -35)
			stv["snacks"] = mini(SimC.STOCK_CAP, stv["snacks"] + 1)
		"dragon":
			if stv["hamper_q"] > 0:
				stv["hamper_q"] -= 1
				stv["hamper_t"] = 0
				stv["linen"] = mini(SimC.LINEN_CAP, stv["linen"] + 1)
				SimScore.bump(sim, "laundry_cycles")
			else:
				stv["linen"] = mini(SimC.LINEN_CAP, stv["linen"] + 1)
		"ghost":
			var iid := _ghost_delivery_item(sim, g)
			var it := sim.item(iid)
			var rq := open_request(sim, g, it["k"])
			fulfill(sim, g, rq, -1, iid)
			sim.consume_item(iid, "ghost_helper")
		"moonwolf":
			for ogid in sim.s["guests"]:
				var o: Dictionary = sim.s["guests"][ogid]
				if o["state"] == "lobby":
					o["patience_q"] = mini(SimC.PATIENCE_S * Q, o["patience_q"] + 10 * Q)
		"sprout":
			r["hum"] = mini(80, r["hum"] + 20) if r["hum"] < 80 else r["hum"]
			if not sim.s["puddles"].is_empty():
				var list2 := _puddles_near(sim, g, 30_000_000)
				if not list2.is_empty():
					sim.s["puddles"].erase(list2[0][1])
					sim.emit("puddle_gone", {"id": list2[0][1], "helper": gid})
	g["helper_used"] = true
	g["helper_ready"] = false
	SimScore.bump(sim, "helpful_guests")
	sim.emit("helper", {"guest": gid, "fam": g["fam"], "room": g["room"], "seat": seat})

# ============================================================ walking & trails

static func _walk(sim: HotelSim, g: Dictionary, pace: int) -> void:
	var path: Array = g["path"]
	if g["pi"] >= path.size():
		g["anim"] = "idle"
		return
	var budget := SimC.GUEST_WALK_SPEED * pace / 1000
	var moved := 0
	while budget > 0 and g["pi"] < path.size():
		var wp: Array = path[g["pi"]]
		var dx: int = wp[0] - g["x"]
		var dz: int = wp[1] - g["z"]
		var d := SimC.isqrt(dx * dx + dz * dz)
		if d <= budget:
			g["x"] = wp[0]; g["z"] = wp[1]
			budget -= d
			moved += d
			g["pi"] += 1
		else:
			g["x"] += dx * budget / d
			g["z"] += dz * budget / d
			moved += budget
			budget = 0
		if absi(dx) > 10:
			g["face"] = 1 if dx > 0 else -1
	g["anim"] = "walk"
	if g["fam"] == "slime" and g["state"] in ["walking", "departing"]:
		_slime_trail(sim, g, moved)

static func _slime_trail(sim: HotelSim, g: Dictionary, moved: int) -> void:
	if g["state"] == "departing" and g.get("slippers_on", false):
		return
	g["trail_d"] += moved
	if g["trail_d"] < 3_000_000:
		return
	g["trail_d"] -= 3_000_000
	if g["trail_n"] >= 3 or sim.s["puddles"].size() >= SimC.PUDDLE_BOARD_CAP:
		return
	var tx := LayoutDef.tile_of(g["x"])
	var tz := LayoutDef.tile_of(g["z"])
	if not sim.L.hall.has_point(Vector2i(tx, tz)):
		return
	if not SimEnv.puddle_spot_ok(sim, g["x"], g["z"]):
		return
	g["trail_n"] += 1
	SimEnv.add_puddle(sim, g["x"], g["z"], "trail")

# ============================================================ navigation

static func path_to(sim: HotelSim, fx: int, fz: int, tx: int, tz: int) -> Array:
	var L := sim.L
	var s0 := LayoutDef.nav_cell_of(fx, fz)
	var s1 := LayoutDef.nav_cell_of(tx, tz)
	var out: Array = []
	# Outside the envelope (arrival/exit lane): straight segments to the entrance.
	var ent: Vector2i = L.entrance[0]
	var ent_pt := Vector2i(ent.x * SimC.UM, int((ent.y + 0.5) * SimC.UM))
	var from_out := L.nav_blocked(s0.x, s0.y) and fx < 0
	var to_out := tx < 0
	if from_out:
		out.append([ent_pt.x - 600_000, ent_pt.y])
		out.append([ent_pt.x, ent_pt.y])
		s0 = LayoutDef.nav_cell_of(ent_pt.x, ent_pt.y)
	var goal := s1
	if to_out:
		goal = LayoutDef.nav_cell_of(ent_pt.x, ent_pt.y)
	var cells := _astar(L, s0, goal)
	var pts: Array = []
	for c in cells:
		var cc := LayoutDef.nav_cell_center(c.x, c.y)
		pts.append([cc.x, cc.y])
	pts = _smooth(L, pts)
	out.append_array(pts)
	if to_out:
		out.append([ent_pt.x, ent_pt.y])
		out.append([ent_pt.x - 600_000, ent_pt.y])
		out.append([tx, tz])
	else:
		out.append([tx, tz])
	return out

## Fills the layout's path cache for the common guest trips (queue → room,
## room → room, room → exit/Cozy Corner) so the first assignment never costs
## a frame. Pure: results are identical with or without warming.
static func warm_paths(sim: HotelSim) -> void:
	var L := sim.L
	var starts: Array = []
	for p in L.fixtures["pedestals"]:
		starts.append(Vector2i(p.x * SimC.UM, int((p.y + L.queue_offset_z) * SimC.UM)))
	var ends: Array = []
	for letter in L.active_rooms:
		ends.append(bedside(sim, letter))
	var ent: Vector2i = L.entrance[0]
	var exit_pt := Vector2i(ent.x * SimC.UM - 2_000_000, int((ent.y + 0.5) * SimC.UM))
	var cozy := Vector2i(int(L.cozy_corner.x * SimC.UM), int(L.cozy_corner.y * SimC.UM))
	for a in starts:
		for b in ends + [cozy]:
			path_to(sim, a.x, a.y, b.x, b.y)
	for a2 in ends:
		for b2 in ends + [exit_pt]:
			if a2 != b2:
				path_to(sim, a2.x, a2.y, b2.x, b2.y)

static func _astar(L: LayoutDef, a: Vector2i, b: Vector2i) -> Array:
	var W := LayoutDef.NAV_W
	var H := LayoutDef.NAV_H
	if L.nav_blocked(a.x, a.y):
		a = _nearest_open(L, a)
	if L.nav_blocked(b.x, b.y):
		b = _nearest_open(L, b)
	var start := a.y * W + a.x
	var goal := b.y * W + b.x
	# Guest nav is static per layout, so results are memoised on the layout.
	var ck := start * W * H + goal
	if L.astar_cache.has(ck):
		return (L.astar_cache[ck] as Array).duplicate()
	var cells := _astar_search(L, a, b, start, goal)
	L.astar_cache[ck] = cells
	return cells.duplicate()

static func _astar_search(L: LayoutDef, a: Vector2i, b: Vector2i, start: int, goal: int) -> Array:
	var W := LayoutDef.NAV_W
	var H := LayoutDef.NAV_H
	var g_cost := PackedInt32Array(); g_cost.resize(W * H); g_cost.fill(1 << 30)
	var came := PackedInt32Array(); came.resize(W * H); came.fill(-1)
	var closed := PackedByteArray(); closed.resize(W * H)
	var heap: Array = []   # [f, h, idx]
	g_cost[start] = 0
	_heap_push(heap, [_h(a, b), _h(a, b), start])
	var dirs := [[1, 0, 10], [-1, 0, 10], [0, 1, 10], [0, -1, 10], [1, 1, 14], [-1, 1, 14], [1, -1, 14], [-1, -1, 14]]
	while not heap.is_empty():
		var cur: Array = _heap_pop(heap)
		var ci: int = cur[2]
		if closed[ci] == 1:
			continue
		closed[ci] = 1
		if ci == goal:
			break
		var cx := ci % W
		var cz := ci / W
		for d in dirs:
			var nx: int = cx + d[0]
			var nz: int = cz + d[1]
			if L.nav_blocked(nx, nz):
				continue
			if d[2] == 14 and (L.nav_blocked(cx + d[0], cz) or L.nav_blocked(cx, cz + d[1])):
				continue
			var ni := nz * W + nx
			if closed[ni] == 1:
				continue
			var ng: int = g_cost[ci] + d[2]
			if ng < g_cost[ni]:
				g_cost[ni] = ng
				came[ni] = ci
				var hh := _h(Vector2i(nx, nz), b)
				_heap_push(heap, [ng + hh, hh, ni])
	var cells: Array = []
	var at := goal
	if came[goal] == -1 and goal != start:
		return [a, b]
	while at != -1:
		cells.push_front(Vector2i(at % W, at / W))
		if at == start:
			break
		at = came[at]
	return cells

static func _h(a: Vector2i, b: Vector2i) -> int:
	var dx := absi(a.x - b.x)
	var dz := absi(a.y - b.y)
	return 10 * (dx + dz) - 6 * mini(dx, dz)

static func _nearest_open(L: LayoutDef, c: Vector2i) -> Vector2i:
	for r in range(1, 6):
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if not L.nav_blocked(c.x + dx, c.y + dz):
					return Vector2i(c.x + dx, c.y + dz)
	return c

static func _heap_push(h: Array, v: Array) -> void:
	h.append(v)
	var i := h.size() - 1
	while i > 0:
		var p := (i - 1) / 2
		if _heap_less(h[i], h[p]):
			var t = h[i]; h[i] = h[p]; h[p] = t
			i = p
		else:
			break

static func _heap_pop(h: Array) -> Array:
	var top: Array = h[0]
	var last: Array = h.pop_back()
	if not h.is_empty():
		h[0] = last
		var i := 0
		while true:
			var l := 2 * i + 1
			var r := l + 1
			var m := i
			if l < h.size() and _heap_less(h[l], h[m]): m = l
			if r < h.size() and _heap_less(h[r], h[m]): m = r
			if m == i:
				break
			var t = h[i]; h[i] = h[m]; h[m] = t
			i = m
	return top

static func _heap_less(a: Array, b: Array) -> bool:
	if a[0] != b[0]: return a[0] < b[0]
	if a[1] != b[1]: return a[1] < b[1]
	return a[2] < b[2]

static func _smooth(L: LayoutDef, pts: Array) -> Array:
	if pts.size() <= 2:
		return pts
	var out: Array = [pts[0]]
	var i := 0
	while i < pts.size() - 1:
		var j := pts.size() - 1
		while j > i + 1 and not _nav_line(L, pts[i], pts[j]):
			j -= 1
		out.append(pts[j])
		i = j
	return out

static func _nav_line(L: LayoutDef, a: Array, b: Array) -> bool:
	var dx: int = b[0] - a[0]
	var dz: int = b[1] - a[1]
	var d := SimC.isqrt(dx * dx + dz * dz)
	var n := maxi(1, d / 150_000)
	for k in range(0, n + 1):
		var x: int = a[0] + dx * k / n
		var z: int = a[1] + dz * k / n
		for off in [[0, 0], [170_000, 0], [-170_000, 0], [0, 170_000], [0, -170_000]]:
			var c := LayoutDef.nav_cell_of(x + off[0], z + off[1])
			if L.nav_blocked(c.x, c.y):
				return false
	return true
