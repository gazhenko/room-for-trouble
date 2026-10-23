class_name SimTutorial
extends RefCounted
## Interactive tutorial state machine (§13). Steps are data (tutorials.json);
## any participant can satisfy a step. Hints escalate at 15/30/60 action
## seconds; at 60 s "Try it for me" lets Nana finish that single step.

var def: Dictionary = {}
var step_i := 0
var step_t := 0
var tags: Dictionary = {}       # tag -> guest id
var circles: Array = []         # [[x,z,touched]]
var flags: Dictionary = {}
var done := false
var allow_goodbye: Dictionary = {}

func begin(sim: HotelSim, d: Dictionary) -> void:
	def = d
	for op in d.get("init", []):
		_op(sim, op)
	sim.s["humans_tut"] = sim.s["humans"]
	_enter(sim)

func save_state() -> Dictionary:
	return {"step_i": step_i, "step_t": step_t, "tags": tags.duplicate(), "circles": circles.duplicate(true),
		"flags": flags.duplicate(), "done": done, "allow_goodbye": allow_goodbye.duplicate()}

func load_state(d: Dictionary) -> void:
	step_i = int(d.get("step_i", 0)); step_t = int(d.get("step_t", 0))
	tags = d.get("tags", {}); circles = d.get("circles", []); flags = d.get("flags", {})
	done = bool(d.get("done", false)); allow_goodbye = d.get("allow_goodbye", {})

func current() -> Dictionary:
	var steps: Array = def.get("steps", [])
	if step_i < steps.size():
		return steps[step_i]
	return {}

func room_allowed(sim: HotelSim, letter: String) -> bool:
	return letter in def.get("assignable", [])

func hotel_paused(sim: HotelSim) -> bool:
	return false

func goodbye_allowed(sim: HotelSim, g: Dictionary) -> bool:
	return allow_goodbye.has(str(g["id"]))

func hint_level() -> int:
	if step_t >= 1800: return 3
	if step_t >= 900: return 2
	if step_t >= 450: return 1
	return 0

func _enter(sim: HotelSim) -> void:
	step_t = 0
	flags = {}
	var st := current()
	if st.is_empty():
		done = true
		sim.emit("tutorial_done", {"id": def["id"]})
		return
	sim.s["pace"] = int(st.get("pace", 1000))
	for op in st.get("ops", []):
		_op(sim, op)
	sim.emit("tutorial_step", {"id": st["id"], "index": step_i, "caption": st.get("caption", ""), "speaker": st.get("speaker", "nana")})

func step(sim: HotelSim) -> void:
	if done:
		return
	step_t += 1
	var st := current()
	for p in circles:
		if p[2]:
			continue
		for s2 in sim.s["staff"]:
			if absi(s2["x"] - p[0]) < 650_000 and absi(s2["z"] - p[1]) < 650_000:
				p[2] = true
				sim.emit("circle_touched", {})
	for s3 in sim.s["staff"]:
		if s3["inspect"]:
			flags["inspect_t"] = int(flags.get("inspect_t", 0)) + 1
		if (s3["pressed_btn"] & SimC.BTN_HINT) != 0 and hint_level() >= 3:
			_auto(sim)
			return
	for e in sim.events:
		match e["type"]:
			"hamper_in": flags["hamper"] = true
			"bell": flags["bell"] = true
			"ping": flags["ping"] = true
			"sound_pulse":
				if e.get("kind", "") == "howl":
					flags["howl"] = true
					var wg := sim.guest(int(tags.get("whisp", 0)))
					if not wg.is_empty() and wg.get("room", "") != "":
						if sim.room(wg["room"])["noise"] <= 20:
							flags["quiet"] = true
	if _complete(sim, st.get("complete", {})):
		_advance(sim)

func _advance(sim: HotelSim) -> void:
	circles.clear()
	step_i += 1
	_enter(sim)

func _auto(sim: HotelSim) -> void:
	var st := current()
	sim.emit("nana_helps", {"step": st.get("id", "")})
	for op in st.get("auto", []):
		_op(sim, op)
	_advance(sim)

func on_bell(sim: HotelSim, seat: int) -> void:
	var st := current()
	for op in st.get("on_bell", []):
		_op(sim, op)

func on_ping(sim: HotelSim, seat: int, phrase: String) -> void:
	flags["ping"] = true

func on_guest_room(sim: HotelSim, g: Dictionary) -> void:
	if g.get("tut", false):
		g["hold_stay"] = true

func on_welcome(sim: HotelSim, g: Dictionary) -> void:
	pass

func on_request_done(sim: HotelSim, g: Dictionary) -> void:
	flags["request_done_%d" % g["id"]] = true

func on_checkout(sim: HotelSim, g: Dictionary) -> void:
	pass

func on_guest_second(sim: HotelSim, g: Dictionary) -> void:
	pass

func _g(sim: HotelSim, tag: String) -> Dictionary:
	return sim.guest(int(tags.get(tag, 0)))

func _complete(sim: HotelSim, c: Dictionary) -> bool:
	match c.get("type", ""):
		"circles":
			if circles.is_empty():
				return false
			for p in circles:
				if not p[2]:
					return false
			return true
		"room_bed":
			return sim.room(c["room"])["bed"] == c["bed"]
		"guest_in_room":
			return _g(sim, c["tag"]).get("state", "") == "staying" and not _g(sim, c["tag"]).get("relocating", false)
		"guests_in_rooms":
			for t in c["tags"]:
				if _g(sim, t).get("state", "") != "staying":
					return false
			return true
		"welcomed":
			return _g(sim, c["tag"]).get("welcomed", false)
		"request_done":
			return flags.has("request_done_%d" % int(tags.get(c["tag"], 0)))
		"guest_departed":
			return _g(sim, c["tag"]).get("state", "") in ["departing", "gone"]
		"room_reset":
			var r := sim.room(c["room"])
			return r["bed"] == "Made" and r["mess"] == 0 and flags.has("hamper")
		"bell":
			return flags.has("bell")
		"inspect":
			return int(flags.get("inspect_t", 0)) >= 20
		"rooms_filled":
			for letter in c["rooms"]:
				var r2 := sim.room(letter)
				if r2["guest"] == 0 and r2["reserved"] == 0:
					return false
			return true
		"guests_comfy":
			for t in c["tags"]:
				if int(_g(sim, t).get("streak", 0)) < int(c.get("streak", 6)):
					return false
			return true
		"gate_closed":
			return not sim.s["gates"].get(c["edge"], true)
		"no_clouds":
			return sim.s["clouds"].is_empty()
		"frost_cleared":
			return not sim.room(c["room"])["frost"]
		"howl_landed":
			return flags.has("howl")
		"curtain_any":
			for letter in c["rooms"]:
				if sim.room(letter)["curtain"] != 0:
					return true
			return false
		"quiet_howl":
			return flags.has("quiet")
		"ping_and_delivery":
			return flags.has("ping") and flags.has("request_done_%d" % int(tags.get(c["tag"], 0)))
	return false

func _op(sim: HotelSim, op: Dictionary) -> void:
	match op["op"]:
		"set_room":
			var r := sim.room(op["room"])
			if op.has("bed"): r["bed"] = op["bed"]
			if op.has("mess"):
				r["mess"] = int(op["mess"]); r["mess_milli"] = r["mess"] * 1000
			if op.has("heat"): r["heat"] = int(op["heat"])
		"circles":
			circles.clear()
			for p in op["positions"]:
				circles.append([sim.L.mirror_x_um(int(p[0]) * SimC.UM), int(p[1]) * SimC.UM, false])
		"touch_circles":
			for p in circles:
				p[2] = true
		"spawn_guest":
			var gid := sim.alloc_id()
			var g := SimGuests.make_guest(sim, gid, op["fam"], op.get("variant", ""), {"arrive_s": 0, "announce_s": 0, "arrival_index": tags.size()})
			g["tut"] = true
			g["arrive_q"] = sim.s["hotel_q"]
			g["announce_q"] = sim.s["hotel_q"]
			sim.s["guests"][gid] = g
			tags[op["tag"]] = gid
			SimGuests._arrive(sim, g)
			g["announced"] = true
		"kiosk":
			sim.s["st"]["kiosk_sel"] = SimC.FAMILIES.find(op["fam"])
		"force_request":
			var g2 := _g(sim, op["tag"])
			if not g2.is_empty():
				g2["reqs"] = [{"k": op["kind"], "at": sim.s["hotel_q"], "dl": sim.s["hotel_q"] + 99999 * SimC.HOTEL_Q_PER_S,
					"late": sim.s["hotel_q"] + 99999 * SimC.HOTEL_Q_PER_S, "st": "open", "i": 0}]
				sim.emit("request_open", {"guest": g2["id"], "room": g2["room"], "k": op["kind"]})
		"allow_goodbye":
			var g3 := _g(sim, op["tag"])
			if not g3.is_empty():
				allow_goodbye[str(g3["id"])] = true
				g3["checkout_q"] = sim.s["hotel_q"]
		"goodbye":
			var g4 := _g(sim, op["tag"])
			if not g4.is_empty():
				SimGuests.wave_goodbye(sim, g4["id"], -1)
		"assign":
			var g5 := _g(sim, op["tag"])
			if not g5.is_empty() and g5["state"] == "lobby":
				if g5["ticket"] != 0:
					var t := sim.item(g5["ticket"])
					if t.get("loc", "") == "held":
						var holder := sim.staff_by_seat(t["seat"])
						if not holder.is_empty():
							holder["held"] = 0
					sim.consume_item(g5["ticket"], "nana")
				var r3 := sim.room(op["room"])
				r3["bed"] = "Made"; r3["mess"] = 0
				SimGuests.assign(sim, g5["id"], op["room"], -1)
		"welcome":
			var g6 := _g(sim, op["tag"])
			if not g6.is_empty() and g6["room"] != "":
				var r4 := sim.room(g6["room"])
				if r4["gift"] == 0:
					var gid2 := sim.new_item("welcome_" + g6["fam"], {"loc": "sock", "sock": "plinth:" + g6["room"]})
					r4["gift"] = gid2
				SimGuests._set_welcomed(sim, g6, -1)
		"fulfill":
			var g7 := _g(sim, op["tag"])
			if not g7.is_empty():
				for rq in g7["reqs"]:
					if rq["st"] == "open":
						rq["st"] = "done"
				flags["request_done_%d" % g7["id"]] = true
		"cloud":
			var p: Array = op["position"]
			SimEnv.add_cloud(sim, sim.L.mirror_x_um(int(p[0]) * SimC.UM), int(p[1]) * SimC.UM, "teaching")
		"clear_clouds":
			sim.s["clouds"].clear()
		"frost":
			SimEnv.set_frost(sim, op["room"])
		"unfrost":
			sim.room(op["room"])["frost"] = false
		"gate":
			sim.s["gates"][op["edge"]] = bool(op["open"])
		"fix_thermostats":
			for t2 in tags:
				var gg := _g(sim, t2)
				if gg.is_empty() or gg["room"] == "":
					continue
				var rr := sim.room(gg["room"])
				if gg["fam"] == "yeti":
					rr["thermo"] = "cool"; rr["heat"] = -35
				elif gg["fam"] == "dragon":
					rr["thermo"] = "warm"; rr["heat"] = 35
				gg["streak"] = 6
		"howl":
			var g8 := _g(sim, op["tag"])
			if not g8.is_empty() and g8["room"] != "":
				SimDirector.request(sim, "teaching", "howl", g8["room"], {"guest": g8["id"], "warn_s": 4, "paired_teaching": true})
		"curtain":
			var r5 := sim.room(op["room"])
			if r5["curtain"] == 0:
				var cid := sim.new_item("curtain_roll", {"loc": "sock", "sock": "curtain:" + op["room"]})
				r5["curtain"] = cid
				if sim.s["st"]["curtains_free"] > 0:
					sim.s["st"]["curtains_free"] -= 1
		"ring":
			flags["bell"] = true
		"note":
			flags[op["what"]] = true
