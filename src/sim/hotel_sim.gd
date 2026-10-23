class_name HotelSim
extends RefCounted
## Pure authoritative hotel state machine (§19.2). Accepts per-seat input frames
## once per 30 Hz action tick, updates integer state, and emits semantic events.
## The renderer, audio and UI only read `s` and `events`; they never mutate them.
## Systems live in static modules (SimMove, SimInteract, SimGuests, SimEnv,
## SimDirector, SimScore, SimGus) so there are no reference cycles.

var content                     # ContentRegistry node
var L: LayoutDef
var level: Dictionary = {}
var cfg: Dictionary = {}
var s: Dictionary = {}          # all mutable mechanical state
var rng := FixedRng.new(1)      # mechanical stream
var cos_rng := FixedRng.new(2)  # cosmetic stream (§9.8)
var events: Array = []          # emitted this tick
var systems: Dictionary = {}    # enabled systems set
var schedule: Array = []        # arrival schedule
var input_log: Array = []       # [tick, frames] for replay
var record_inputs := true
var hashes: Array = []          # [tick, hash] every 5 action s
var tutorial = null             # SimTutorial state machine (optional)
var _last_frames: Dictionary = {}

func _init(content_registry, setup: Dictionary) -> void:
	content = content_registry
	cfg = setup.duplicate(true)
	_setup()

# ---------------------------------------------------------------- setup

func _setup() -> void:
	var mode: String = cfg.get("mode", "campaign")
	var mods: Array = cfg.get("modifiers", [])
	var template_id := "P1"
	if mode in ["campaign", "quick"]:
		level = content.level(cfg["level_id"])
		template_id = level["layout"]
		for sname in level.get("systems", []):
			systems[sname] = true
	elif mode == "tutorial":
		var tdef: Dictionary = content.tutorials[cfg["tutorial_id"]]
		template_id = tdef["layout"]
		for sname in tdef.get("systems", ["core"]):
			systems[sname] = true
		level = {"id": cfg["tutorial_id"], "duration_hotel_s": 0, "waves": [], "service_count": 1,
			"events": [], "ribbons": [], "required_goal_ids": [], "initial_rooms": {}, "chapter": 0}
	elif mode == "hub":
		template_id = cfg.get("layout", "P1")
		level = {"id": "HUB", "duration_hotel_s": 0, "waves": [], "service_count": 1, "events": [],
			"ribbons": [], "required_goal_ids": [], "initial_rooms": {}, "chapter": 1}
	else:
		template_id = cfg.get("layout", "P6")
		for sname in ["core", "thermal", "sound", "moisture", "festival"]:
			systems[sname] = true
		if template_id == "P5":
			systems["shutter"] = true
			systems["lift"] = true
		level = {"id": "PLAY", "duration_hotel_s": 0, "waves": [], "service_count": 2, "events": [],
			"ribbons": [], "required_goal_ids": [], "initial_rooms": {}, "chapter": 0}
	systems["core"] = true
	L = content.layout(template_id, "mirror_hall" in mods)
	rng.reseed(int(cfg.get("seed", 1)))
	cos_rng.reseed(int(cfg.get("seed", 1)) * 7919 + 17)
	var humans := clampi(int(cfg.get("humans", 1)), 1, 4)
	var pace := int(cfg.get("pace_milli", SimC.DIFFICULTY_PACE.get(cfg.get("difficulty", "family"), 1000)))
	s = {
		"tick": 0, "hotel_q": 0, "hotel_s": 0, "phase": cfg.get("start_phase", "planning"),
		"phase_t": 0, "next_id": 1, "humans": humans, "pace": pace,
		"difficulty": cfg.get("difficulty", "family"),
		"cozy": cfg.get("difficulty", "family") == "cozy",
		"room_cap": mini(SimC.ROOM_CAP_BY_HUMANS[humans - 1], L.active_rooms.size()),
		"incident_cap": SimC.INCIDENT_CAP_BY_HUMANS[humans - 1],
		"cloud_cap": 1 if humans == 1 else 2,
		"staff": [], "items": {}, "rooms": {}, "guests": {}, "puddles": {}, "clouds": {},
		"trunks": {}, "lifts": {}, "pings": {}, "incidents": [], "deferred": [],
		"pedestals": [0, 0, 0, 0, 0, 0], "bench": [],
		"gates": {}, "st": {}, "fired": {}, "warnings": {}, "goals": {},
		"shutter": {"active": false, "state": "open", "t_q": 0, "defer_t": 0},
		"hotel_paused": false, "coach": "", "coach_seen": [], "finish_t": 0,
		"last_mech_q": -999999999, "gus": {"on": bool(cfg.get("gus", humans == 1)), "t": 0, "task": {}},
		"stats": {}, "ribbon_prog": {}, "story_flags": {}, "cues": {},
		"wrap_reason": "", "arrivals_done": false, "final_arrival_s": 0,
		"bell_cd": 0, "last_comic_t": -999,
		"hint_always": "helpful_house" in mods,
	}
	if "helpful_house" in mods:
		s["gus"]["on"] = true
	_setup_rooms()
	_setup_stations()
	_setup_staff()
	_setup_schedule()
	SimScore.init_stats(self)
	if mode == "tutorial":
		tutorial = SimTutorial.new()
		tutorial.begin(self, content.tutorials[cfg["tutorial_id"]])
	if mode in ["playground", "hub"]:
		s["phase"] = "active"
	emit("shift_setup", {"layout": L.id, "mode": mode})

func _setup_rooms() -> void:
	var overrides: Dictionary = level.get("initial_rooms", {})
	var mods: Array = cfg.get("modifiers", [])
	for letter in SimC.ROOM_LETTERS:
		var g: Dictionary = L.rooms[letter]
		var hum := int(L.initial_humidity.get(letter, SimC.HUMIDITY_BASE))
		if "damp_start" in mods and systems.has("moisture"):
			hum = 60
		var r := {
			"L": letter, "num": g["number"], "active": g["active"],
			"bed": "Made", "mess": 0, "gift": 0, "thermo": "neutral",
			"prepare": systems.has("thermal"), "heat": 0, "hum": hum, "noise": 0,
			"curtain": 0, "tray": 0, "frost": false, "frost_cold": 0, "frost_warm": 0, "frost_cd": 0,
			"puff_hot": 0, "puff_cd": 0, "over_n": 0, "over_cd": 0,
			"guest": 0, "reserved": 0, "last_inc_s": -9999, "pend_heat": 0, "pend_hum": 0,
			"pulses": [], "comfort_view": 0, "trip_q": 0,
		}
		if overrides.has(letter):
			var o: Dictionary = overrides[letter]
			if o.has("bed"): r["bed"] = o["bed"]
			if o.has("mess"): r["mess"] = int(o["mess"])
			if o.has("heat"): r["heat"] = int(o["heat"])
			if o.has("humidity"): r["hum"] = int(o["humidity"])
		s["rooms"][letter] = r
	for e in L.thermal_edges:
		s["gates"][e] = not ("closed_vents" in mods)

func _setup_stations() -> void:
	var active_count := L.active_rooms.size()
	var humans: int = s["humans"]
	var curtain_pool := 0
	if systems.has("sound"):
		curtain_pool = 2 if humans <= 2 else 3
		if cfg.get("mode") == "playground":
			curtain_pool = 6
	s["st"] = {
		"linen": mini(SimC.LINEN_CAP, active_count + 2), "hamper_q": 0, "hamper_t": 0, "laundry_hold": 0,
		"hamper_pad": [], "towels": SimC.STOCK_START, "towel_t": 0, "snacks": SimC.STOCK_START, "snack_t": 0,
		"kiosk_sel": 0, "curtains_free": curtain_pool, "curtain_pool": curtain_pool, "pump": "balanced",
		"trips": {}, "press_user": -1, "rot": 0,
	}
	var mods: Array = cfg.get("modifiers", [])
	if "quiet_start" in mods and systems.has("sound"):
		s["st"]["curtain_pool"] = L.active_rooms.size()
		s["st"]["curtains_free"] = 0
		for letter in L.active_rooms:
			var cid := new_item("curtain_roll", {"loc": "sock", "sock": "curtain:" + letter})
			s["rooms"][letter]["curtain"] = cid
	# Tools: 2 mops always; breezer chapter 2+ (thermal); can(s) when moisture.
	var mops: Array = L.fixtures.get("mop_docks", [])
	for i in mops.size():
		new_item("mop", {"loc": "sock", "sock": "dock:mop:%d" % i, "home": "dock:mop:%d" % i})
	if systems.has("thermal") or cfg.get("mode") == "playground":
		new_item("breezer", {"loc": "sock", "sock": "dock:breezer:0", "home": "dock:breezer:0"})
	if systems.has("moisture"):
		var cans := 2 if humans >= 3 else 1
		for i in cans:
			new_item("watering_can", {"loc": "sock", "sock": "dock:can:%d" % i, "home": "dock:can:%d" % i, "ch": 0})
	if systems.has("lift") and L.lift_pads.size() == 2:
		s["lifts"] = {"busy": false, "t": 0, "item": 0, "rider": -1, "from": 0, "pad": [0, 0], "send_from": -1}

func _setup_staff() -> void:
	var seats: Array = cfg.get("seats", [{"seat": 0, "char": "pip"}])
	var starts: Array = L.fixtures["staff_starts"]
	for i in seats.size():
		var sd: Dictionary = seats[i]
		var p: Vector2i = starts[i % starts.size()]
		s["staff"].append({
			"seat": int(sd.get("seat", i)), "char": sd.get("char", SimC.STAFF_IDS[i % 4]),
			"cos": sd.get("cos", "default"), "present": true, "assists": sd.get("assists", {}).duplicate(),
			"x": p.x * SimC.UM, "z": p.y * SimC.UM, "vx": 0, "vz": 0, "fx": 0, "fz": 1000,
			"held": 0, "step_t": 0, "step_cd": 0, "sdx": 0, "sdz": 0,
			"act": {}, "work_key": "", "work_toggle": false, "grip": 0, "grip_h": -1, "grip_grace": 0,
			"slide_t": 0, "transp_t": 0, "last_carry_t": -999, "ready": false,
			"hl_c": "", "hl_c_ok": false, "hl_c_why": "", "hl_w": "", "hl_w_ok": false, "hl_w_why": "",
			"noise_s": -1, "inspect": false, "ax": 0, "az": 0, "idle_t": 0, "moving": false,
			"ping_cd": 0, "hint_i": -1, "hint_t": 0, "work_anim": "", "bump_t": 0,
		})

func _setup_schedule() -> void:
	schedule.clear()
	if not cfg.get("mode", "campaign") in ["campaign", "quick"]:
		s["arrivals_done"] = true
		return
	var max_stay := 0
	for f in SimC.FAMILIES:
		max_stay = maxi(max_stay, int(content.guest_def(f)["stay_s"]))
	var reserve := 150
	schedule = ArrivalPlan.schedule(level, s["humans"], L.active_rooms.size(), reserve)
	var variants_used := {}
	for a in schedule:
		var gid := alloc_id()
		var fam: String = a["family"]
		var gdef: Dictionary = content.guest_def(fam)
		var variant := ""
		if not variants_used.has(fam):
			variant = gdef.get("named_variant", "")
			variants_used[fam] = true
		var g := SimGuests.make_guest(self, gid, fam, variant, a)
		s["guests"][gid] = g
		s["final_arrival_s"] = maxi(s["final_arrival_s"], int(a["arrive_s"]))
	s["scheduled_count"] = schedule.size()

# ---------------------------------------------------------------- ids/items

func alloc_id() -> int:
	var i: int = s["next_id"]
	s["next_id"] = i + 1
	return i

func new_item(kind: String, fields: Dictionary = {}) -> int:
	var iid := alloc_id()
	var it := {"id": iid, "k": kind, "loc": "world", "seat": -1, "x": 0, "z": 0, "sock": "",
		"g": 0, "ch": 0, "home": "", "idle": 0, "born": s.get("tick", 0), "last_holder": -1,
		"holders": [], "handoff_t": -999, "handoff_from": -1, "lift_t": -999, "claim": -1, "claim_t": 0}
	for k in fields:
		it[k] = fields[k]
	s["items"][iid] = it
	emit("item_spawn", {"id": iid, "k": kind})
	return iid

func item(iid: int) -> Dictionary:
	return s["items"].get(iid, {})

func consume_item(iid: int, reason: String = "") -> void:
	var it: Dictionary = s["items"].get(iid, {})
	if it.is_empty():
		return
	if it["loc"] == "held":
		var st := staff_by_seat(it["seat"])
		if not st.is_empty() and st["held"] == iid:
			st["held"] = 0
	s["items"].erase(iid)
	emit("item_gone", {"id": iid, "k": it["k"], "why": reason})

func staff_by_seat(seat: int) -> Dictionary:
	for st in s["staff"]:
		if st["seat"] == seat:
			return st
	return {}

func room(letter: String) -> Dictionary:
	return s["rooms"].get(letter, {})

func guest(gid: int) -> Dictionary:
	return s["guests"].get(gid, {})

func emit(type: String, data: Dictionary = {}) -> void:
	data["type"] = type
	data["tick"] = s.get("tick", 0)
	events.append(data)

func hotel_now_s() -> int:
	return int(s["hotel_q"] / SimC.HOTEL_Q_PER_S)

func has_sys(name: String) -> bool:
	return systems.has(name)

func is_active() -> bool:
	return s["phase"] == "active"

func occupied_count() -> int:
	var n := 0
	for letter in s["rooms"]:
		var r: Dictionary = s["rooms"][letter]
		if r["guest"] != 0 or r["reserved"] != 0:
			n += 1
	return n

func room_assignable(letter: String) -> String:
	## "" when assignable, otherwise a reason key.
	var r := room(letter)
	if r.is_empty() or not r["active"]:
		return "ui.reason.room_closed"
	if r["guest"] != 0 or r["reserved"] != 0:
		return "ui.reason.room_taken"
	if r["bed"] != "Made" or r["mess"] > 0:
		return "ui.reason.room_not_ready"
	if tutorial != null and not tutorial.room_allowed(self, letter):
		return "ui.reason.tutorial_room"
	if occupied_count() >= s["room_cap"]:
		return "ui.reason.room_cap"
	return ""

# ---------------------------------------------------------------- step

## frames: Array of {seat, ax, az, held, pressed}
func step(frames: Array) -> void:
	# Events emitted during setup (e.g. the first tutorial step) surface on tick 0.
	if s["tick"] > 0:
		events.clear()
	var fmap := {}
	for f in frames:
		fmap[int(f.get("seat", 0))] = f
	if record_inputs:
		var compact: Array = []
		for f in frames:
			if int(f.get("ax", 0)) != 0 or int(f.get("az", 0)) != 0 or int(f.get("held", 0)) != 0 or int(f.get("pressed", 0)) != 0:
				compact.append([int(f["seat"]), int(f.get("ax", 0)), int(f.get("az", 0)), int(f.get("held", 0)), int(f.get("pressed", 0))])
		if not compact.is_empty():
			input_log.append([s["tick"], compact])
	_last_frames = fmap
	var phase: String = s["phase"]
	# 1. lobby/ready/pause-like changes
	for st in s["staff"]:
		var f: Dictionary = fmap.get(st["seat"], {})
		st["ax"] = int(f.get("ax", 0)); st["az"] = int(f.get("az", 0))
		st["held_btn"] = int(f.get("held", 0)); st["pressed_btn"] = int(f.get("pressed", 0))
		st["ping_pick"] = int(f.get("pick", -1))
		if not st["present"]:
			st["ax"] = 0; st["az"] = 0; st["held_btn"] = 0; st["pressed_btn"] = 0
		st["inspect"] = (st["held_btn"] & SimC.BTN_INSPECT) != 0
		if phase == "planning" and (st["pressed_btn"] & SimC.BTN_READY) != 0:
			st["ready"] = not st["ready"]
			emit("ready", {"seat": st["seat"], "ready": st["ready"]})
	if phase in ["planning", "countdown", "active", "wrap"]:
		# 2. movement
		SimMove.step_all(self)
		# 3–4. interaction, work, commits
		SimInteract.step_all(self)
	# 5. action timers
	if phase == "active":
		SimInteract.step_timers(self)
		SimDirector.coach_tick(self)
		if s["gus"]["on"]:
			SimGus.step(self)
	# 6–9. hotel time
	if phase == "active":
		_advance_hotel()
	elif phase == "planning":
		_planning_checks()
	elif phase == "countdown":
		s["phase_t"] += 1
		if s["phase_t"] >= 90:
			_set_phase("active")
			emit("shift_start", {})
	elif phase == "wrap":
		s["phase_t"] += 1
		if s["phase_t"] >= 90:
			_set_phase("done")
			SimScore.finalize(self)
			emit("shift_done", {})
	if tutorial != null:
		tutorial.step(self)
	s["tick"] += 1
	if s["tick"] % 150 == 0:
		hashes.append([s["tick"], state_hash()])

func _set_phase(p: String) -> void:
	s["phase"] = p
	s["phase_t"] = 0
	emit("phase", {"phase": p})

func _planning_checks() -> void:
	if cfg.get("mode") in ["tutorial", "playground", "hub"]:
		_set_phase("active")
		return
	var all_ready := true
	var any := false
	for st in s["staff"]:
		if st["present"]:
			any = true
			if not st["ready"]:
				all_ready = false
	if any and all_ready:
		_set_phase("countdown")
		emit("countdown", {})

func start_now() -> void:
	## Skip planning (used by tests, quick replays and "Start with ready players").
	if s["phase"] == "planning":
		_set_phase("countdown")

func force_active() -> void:
	_set_phase("active")

func _advance_hotel() -> void:
	var paused = bool(s["hotel_paused"]) or s["coach"] != ""
	if tutorial != null and tutorial.hotel_paused(self):
		paused = true
	if not paused:
		var before: int = s["hotel_q"]
		s["hotel_q"] = before + int(s["pace"])
		SimGuests.step_tick(self)
		SimDirector.step_events(self)
		var sec_before := before / SimC.HOTEL_Q_PER_S
		var sec_after: int = s["hotel_q"] / SimC.HOTEL_Q_PER_S
		while sec_before < sec_after:
			sec_before += 1
			s["hotel_s"] = sec_before
			SimEnv.integrate_second(self)
			SimGuests.step_second(self)
			SimDirector.step_second(self)
	else:
		SimGuests.step_tick_paused(self)
	SimScore.step(self)
	_terminal_checks()

func _terminal_checks() -> void:
	if cfg.get("mode") in ["tutorial", "playground", "hub"]:
		return
	if s["finish_t"] > 0:
		s["finish_t"] -= 1
		if s["finish_t"] == 0:
			begin_wrap("finished")
			return
	var dur := int(level.get("duration_hotel_s", 0))
	if not s["cozy"] and dur > 0 and s["hotel_q"] >= dur * SimC.HOTEL_Q_PER_S:
		begin_wrap("timer")

func can_finish_early() -> bool:
	if not is_active():
		return false
	if hotel_now_s() < int(s["final_arrival_s"]):
		return false
	for gid in s["guests"]:
		var g: Dictionary = s["guests"][gid]
		if not g["state"] in ["departing", "gone", "cozy"]:
			return false
	for gid_str in level.get("required_goal_ids", []):
		if not s["goals"].get(gid_str, {}).get("done", false):
			return false
	return true

func request_finish(seat: int) -> void:
	if can_finish_early() and s["finish_t"] == 0:
		s["finish_t"] = 90
		emit("finish_prompt", {"seat": seat})

func cancel_finish(seat: int) -> void:
	if s["finish_t"] > 0:
		s["finish_t"] = 0
		emit("finish_cancel", {"seat": seat})

func begin_wrap(reason: String) -> void:
	if s["phase"] != "active":
		return
	s["wrap_reason"] = reason
	SimInteract.release_all(self)
	SimGuests.wrap_montage(self)
	SimGoals.park_unfinished(self)
	_set_phase("wrap")
	emit("wrap", {"reason": reason})

# ---------------------------------------------------------------- staff presence

func set_present(seat: int, present: bool) -> void:
	var st := staff_by_seat(seat)
	if st.is_empty():
		return
	if not present:
		SimInteract.safe_release(self, st)
	st["present"] = present
	emit("staff_present", {"seat": seat, "present": present})

func back_to_lobby(seat: int) -> void:
	var st := staff_by_seat(seat)
	if st.is_empty():
		return
	SimInteract.safe_release(self, st)
	var starts: Array = L.fixtures["staff_starts"]
	var p: Vector2i = starts[0]
	var best := 1 << 62
	for sp in starts:
		var d: int = absi(sp.x * SimC.UM - st["x"]) + absi(sp.y * SimC.UM - st["z"])
		if d < best:
			best = d; p = sp
	st["x"] = p.x * SimC.UM; st["z"] = p.y * SimC.UM; st["vx"] = 0; st["vz"] = 0
	st["transp_t"] = SimC.TRANSPARENT_TICKS
	emit("back_to_lobby", {"seat": seat})

func find_tools() -> void:
	SimInteract.find_tools(self)

# ---------------------------------------------------------------- snapshots

func snapshot() -> Dictionary:
	return {"s": s.duplicate(true), "systems": systems.keys(), "layout": L.id, "mirror": L.mirrored,
		"level": level.get("id", ""), "rng": rng.state, "cos_rng": cos_rng.state,
		"tut": tutorial.save_state() if tutorial != null else {}}

func restore(snap: Dictionary) -> void:
	s = snap["s"].duplicate(true)
	rng.state = int(snap["rng"])
	cos_rng.state = int(snap["cos_rng"])
	if tutorial != null and snap.has("tut"):
		tutorial.load_state(snap["tut"])

func state_hash() -> String:
	# Mechanical state only (cosmetic RNG excluded, §19.5).
	var mech := s.duplicate(true)
	mech.erase("cues")
	for st in mech["staff"]:
		for k in ["hl_c", "hl_w", "hl_c_ok", "hl_w_ok", "hl_c_why", "hl_w_why", "hint_i", "hint_t", "work_anim", "inspect"]:
			st.erase(k)
	return JSON.stringify(mech, "", true).sha256_text().substr(0, 16) + ("%08x" % rng.state)
