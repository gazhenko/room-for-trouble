class_name SimDirector
extends RefCounted
## Incident director (§9.8) plus the authored event timeline (§15.1) and the
## P5 shutter state machine (§12.4). Enough trouble, never a pile-on.

const Q := SimC.HOTEL_Q_PER_S
const PRIO := {"teaching": 0, "level": 1, "quirk": 2, "threshold": 3}
const MECHANICAL := ["sneeze", "hiccup", "howl", "bloom_puddle", "steam", "frost", "overflow",
	"thermal_pulse", "humidity_pulse", "concert_pulse", "fixture_trip", "puddle_patch"]

static func _d(sim: HotelSim) -> Dictionary:
	if not sim.s.has("director"):
		sim.s["director"] = {}
	var d: Dictionary = sim.s["director"]
	if not d.has("pending"):
		d["pending"] = []
		d["active"] = []
		d["last_start_s"] = -9999
		d["room_last"] = {}
		d["seq"] = 0
	return d

## Queue an incident. Effects apply only once the budget allows (§9.8).
static func request(sim: HotelSim, prio: String, kind: String, room: String, data: Dictionary) -> void:
	var d := _d(sim)
	d["seq"] += 1
	d["pending"].append({"prio": PRIO.get(prio, 3), "prio_name": prio, "kind": kind, "room": room, "data": data,
		"req_s": sim.s["hotel_s"], "seq": d["seq"]})
	_try_start(sim)

static func _active_count(sim: HotelSim) -> int:
	return _d(sim)["active"].size()

static func _try_start(sim: HotelSim) -> void:
	var d := _d(sim)
	var pending: Array = d["pending"]
	pending.sort_custom(func(a, b): return [a["prio"], a["req_s"], a["seq"]] < [b["prio"], b["req_s"], b["seq"]])
	var keep: Array = []
	var now: int = sim.s["hotel_s"]
	for e in pending:
		if _can_start(sim, e):
			_start(sim, e)
		elif now - int(e["req_s"]) >= 10:
			sim.emit("incident_cosmetic", {"kind": e["kind"], "room": e["room"]})
		else:
			if not e.get("deferred_shown", false):
				e["deferred_shown"] = true
				sim.emit("incident_deferred", {"kind": e["kind"], "room": e["room"]})
			keep.append(e)
	d["pending"] = keep

static func _can_start(sim: HotelSim, e: Dictionary) -> bool:
	var d := _d(sim)
	var now: int = sim.s["hotel_s"]
	if _active_count(sim) >= int(sim.s["incident_cap"]):
		return false
	if not e["data"].get("paired_teaching", false) and now - int(d["last_start_s"]) < 10 and d["last_start_s"] > -9999:
		return false
	var room: String = e["room"]
	if room != "" and not e["data"].get("paired_teaching", false) and now - int(d["room_last"].get(room, -9999)) < 20:
		return false
	if e["kind"] == "steam" and sim.s["clouds"].size() >= int(sim.s["cloud_cap"]):
		return false
	return true

static func _start(sim: HotelSim, e: Dictionary) -> void:
	var d := _d(sim)
	var now: int = sim.s["hotel_s"]
	d["last_start_s"] = now
	if e["room"] != "":
		d["room_last"][e["room"]] = now
	var warn := int(e["data"].get("warn_s", 0))
	var inc := {"kind": e["kind"], "room": e["room"], "data": e["data"], "start_s": now, "fire_s": now + warn,
		"fired": false, "until_s": now + warn + 6, "ref": 0}
	d["active"].append(inc)
	if warn > 0:
		sim.emit("incident_warn", {"kind": e["kind"], "room": e["room"], "fire_s": now + warn, "guest": e["data"].get("guest", 0)})
	else:
		_fire(sim, inc)

static func _fire(sim: HotelSim, inc: Dictionary) -> void:
	inc["fired"] = true
	var room: String = inc["room"]
	var data: Dictionary = inc["data"]
	var now: int = sim.s["hotel_s"]
	match inc["kind"]:
		"sneeze", "hiccup":
			var own := -25 if inc["kind"] == "sneeze" else 25
			var nb := -8 if inc["kind"] == "sneeze" else 8
			SimEnv.heat_pulse(sim, room, own)
			for e in sim.L.thermal_edges:
				if not sim.s["gates"].get(e, false):
					continue
				var ab := sim.L.edge_rooms(e)
				if ab[0] == room and sim.room(ab[1])["active"]:
					SimEnv.heat_pulse(sim, ab[1], nb)
				elif ab[1] == room and sim.room(ab[0])["active"]:
					SimEnv.heat_pulse(sim, ab[0], nb)
			inc["until_s"] = now + 3
		"howl":
			SimEnv.queue_pulse(sim, room, 72, {"kind": "howl", "guest": data.get("guest", 0)})
			if sim.L.rooms.has(room):
				var dp := SimInteract.door_pos(sim, room)
				SimInteract.startle_near(sim, dp.x, dp.y, SimC.STARTLE_RADIUS)
			inc["until_s"] = now + 2
		"concert_pulse":
			SimEnv.queue_pulse(sim, room, int(data.get("amplitude", 60)), {"kind": "concert"})
			inc["until_s"] = now + 2
		"bloom_puddle", "overflow":
			var p := SimInteract.plaque_pos(sim, room)
			var spot := SimEnv.safe_puddle_near(sim, p.x, p.y)
			if spot.x != -1:
				inc["ref"] = SimEnv.add_puddle(sim, spot.x, spot.y, inc["kind"])
			inc["until_s"] = now + 3
		"steam":
			var cx := int(data.get("x", 0))
			var cz := int(data.get("z", 0))
			inc["ref"] = SimEnv.add_cloud(sim, cx, cz, data.get("edge", room))
			inc["until_s"] = now + SimC.STEAM_LIFE_S
		"frost":
			SimEnv.set_frost(sim, room)
			inc["until_s"] = now + 60
		"thermal_pulse":
			SimEnv.heat_pulse(sim, room, int(data.get("delta", 0)))
			inc["until_s"] = now + 2
		"humidity_pulse":
			SimEnv.humidity_pulse(sim, room, int(data.get("delta", 0)))
			inc["until_s"] = now + 2
		"fixture_trip":
			SimEnv.trip(sim, data["fixture"])
			inc["until_s"] = now + SimC.TRIP_AUTO_S
		"puddle_patch":
			var ids: Array = []
			for pos in data.get("positions", []):
				var px := int(pos[0]) * SimC.UM
				px = sim.L.mirror_x_um(px)
				var spot2 := SimEnv.safe_puddle_near(sim, px, int(pos[1]) * SimC.UM)
				if spot2.x != -1:
					ids.append(SimEnv.add_puddle(sim, spot2.x, spot2.y, "patch"))
			inc["ref_list"] = ids
			inc["until_s"] = now + 3
	sim.emit("incident", {"kind": inc["kind"], "room": room, "fixture": data.get("fixture", ""), "guest": data.get("guest", 0)})

static func step_second(sim: HotelSim) -> void:
	var d := _d(sim)
	var now: int = sim.s["hotel_s"]
	var still: Array = []
	for inc in d["active"]:
		if not inc["fired"] and now >= int(inc["fire_s"]):
			_fire(sim, inc)
		var alive := now < int(inc["until_s"])
		match inc["kind"]:
			"steam":
				alive = inc["fired"] and sim.s["clouds"].has(inc["ref"]) or not inc["fired"]
			"frost":
				alive = not inc["fired"] or sim.room(inc["room"]).get("frost", false)
			"fixture_trip":
				alive = not inc["fired"] or SimInteract.station_tripped(sim, inc["data"]["fixture"])
		if alive:
			still.append(inc)
	d["active"] = still
	_try_start(sim)
	_shutter_second(sim)

# ------------------------------------------------------------- authored events

static func step_events(sim: HotelSim) -> void:
	var hq: int = sim.s["hotel_q"]
	var evs: Array = sim.level.get("events", [])
	if evs.is_empty():
		return
	var sorted := evs.duplicate()
	sorted.sort_custom(func(a, b): return [int(a["at"]), a["id"]] < [int(b["at"]), b["id"]])
	for ev in sorted:
		var eid: String = ev["id"]
		var at_q := int(ev["at"]) * Q
		var warn_q := maxi(0, int(ev["at"]) - int(ev.get("warning_s", 0))) * Q
		if int(ev.get("warning_s", 0)) > 0 and hq >= warn_q and not sim.s["warnings"].has(eid):
			sim.s["warnings"][eid] = true
			sim.emit("event_warning", {"id": eid, "etype": ev["type"], "args": ev.get("args", {}), "fire_s": int(ev["at"])})
		if hq >= at_q and not sim.s["fired"].has(eid):
			sim.s["fired"][eid] = true
			_fire_event(sim, ev)

static func _fire_event(sim: HotelSim, ev: Dictionary) -> void:
	var args: Dictionary = ev.get("args", {})
	var t: String = ev["type"]
	var mx := func(p: Array) -> Array: return [sim.L.mirror_x_um(int(p[0]) * SimC.UM), int(p[1]) * SimC.UM]
	match t:
		"announce":
			sim.s["cues"][args.get("text_key", "")] = true
			sim.emit("announce", {"id": ev["id"], "text_key": args.get("text_key", ""), "icon": args.get("icon", "")})
		"coach":
			var cid: String = args.get("coach_id", "")
			if cid in sim.cfg.get("first_visit_coaches", []):
				sim.s["coach_pending"] = cid
				_maybe_activate_coach(sim)
		"thermal_pulse", "humidity_pulse":
			request(sim, "level", t, args["room"], {"delta": int(args["delta"])})
		"steam_cloud":
			var p: Array = mx.call(args["position"])
			request(sim, "level", "steam", "", {"x": p[0], "z": p[1]})
		"frost_patch":
			request(sim, "level", "frost", args["room"], {})
		"concert_pulse":
			request(sim, "level", "concert_pulse", args["room"], {"amplitude": int(args.get("amplitude", 60))})
		"fixture_trip":
			var fx: String = args["fixture"]
			var room := fx.substr(9) if fx.begins_with("radiator_") else ""
			request(sim, "level", "fixture_trip", room, {"fixture": fx})
		"puddle_patch":
			request(sim, "level", "puddle_patch", "", {"positions": args["positions"]})
		"shutter_cycle":
			if sim.has_sys("shutter") and sim.L.shutter.x >= 0:
				var sh: Dictionary = sim.s["shutter"]
				sh["active"] = true
				sh["state"] = "warn"
				sh["t"] = 0
				sh["period"] = int(args.get("period", 45))
				sh["warning"] = int(args.get("warning", 5))
				sh["closed"] = int(args.get("closed", 8))
				sim.emit("shutter", {"state": "warn"})
		"trunk_spawn":
			SimGoals.spawn_trunk(sim, args["object_id"], args["position"], args.get("goal", "festival_stand"))
		"parcels_spawn":
			SimGoals.spawn_parcels(sim, args["object_ids"], args["positions"])
	sim.emit("event_fired", {"id": ev["id"], "etype": t})

static func _maybe_activate_coach(sim: HotelSim) -> void:
	var cid: String = sim.s.get("coach_pending", "")
	if cid == "":
		return
	var trigger := true
	if cid == "sprout_first_water":
		trigger = false
		for gid in sim.s["guests"]:
			var g: Dictionary = sim.s["guests"][gid]
			if g["fam"] == "sprout" and g["announced"]:
				trigger = true
	if trigger:
		sim.s["coach"] = cid
		sim.s["coach_pending"] = ""
		sim.s["coach_t"] = 0
		sim.emit("coach", {"id": cid})

static func coach_tick(sim: HotelSim) -> void:
	if sim.s.get("coach_pending", "") != "":
		_maybe_activate_coach(sim)
	var cid: String = sim.s["coach"]
	if cid == "":
		return
	sim.s["coach_t"] = int(sim.s.get("coach_t", 0)) + 1
	var done := false
	for e in sim.events:
		match cid:
			"sprout_first_water":
				if e["type"] == "watered": done = true
			"luggage_lift":
				if e["type"] in ["lift_depart", "lift_ride"]: done = true
	if cid == "shutter_bypass" and sim.s["coach_t"] >= 150:
		done = true
	for st in sim.s["staff"]:
		if (st["pressed_btn"] & SimC.BTN_HINT) != 0 and sim.s["coach_t"] > 15:
			done = true
	if done:
		if not cid in sim.s["coach_seen"]:
			sim.s["coach_seen"].append(cid)
		sim.s["coach"] = ""
		sim.emit("coach_done", {"id": cid})

# ------------------------------------------------------------- shutter §12.4

static func _shutter_second(sim: HotelSim) -> void:
	var sh: Dictionary = sim.s["shutter"]
	if not sh.get("active", false):
		return
	sh["t"] = int(sh["t"]) + 1
	var w: int = sh["warning"]
	var c: int = sh["closed"]
	var period: int = sh["period"]
	var t: int = sh["t"] % period
	var want := "open"
	if t < w:
		want = "warn"
	elif t < w + c:
		want = "closed"
	if want != sh["state"]:
		sh["state"] = want
		sim.emit("shutter", {"state": want})
