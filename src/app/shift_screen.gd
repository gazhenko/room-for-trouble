class_name ShiftScreen
extends Control
## Runs one shift: fixed 30 Hz simulation ticks (local) or snapshot playback
## (online), interpolated rendering, HUD, audio/caption feedback, pause menu,
## and hand-off to results. The same presentation serves both paths.

signal finished(result: Dictionary)
signal left_shift

const TICK := 1.0 / 30.0

var sim: HotelSim
var view: HotelView
var hud: Hud
var captions: Captions
var stage: PixelStage
var cfg: Dictionary = {}
var acc := 0.0
var paused := false
var pause_menu: Control
var online := false
var net_state: Dictionary = {}
var router_to_sim: Dictionary = {}   # router seat -> sim seat
var sim_to_router: Dictionary = {}
var _invalid_cd := 0.0
var _last_music_level := -1
var _done := false
var _gag_played: Dictionary = {}
var _fam_cache: Array = []
var _story_hook: Callable
var frame_source: Callable   # dev/autoplay: replaces InputRouter frames
var dev_hold := false         # DevOverlay inspector: hold the clock…
var dev_steps := 0            # …and run this many single ticks
var _focused := false
var _local_frames := 0

func setup(p_stage: PixelStage, p_captions: Captions, p_cfg: Dictionary) -> void:
	stage = p_stage
	captions = p_captions
	cfg = p_cfg
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	online = cfg.get("online", false)
	var i := 0
	for rs in InputRouter.active_seats():
		router_to_sim[rs] = cfg.get("seat_map", {}).get(rs, i)
		sim_to_router[router_to_sim[rs]] = rs
		i += 1
	if not online:
		sim = HotelSim.new(Content, cfg)
	_build_view()
	_focused = DisplayServer.window_is_focused()

func _build_view() -> void:
	for c in stage.world.get_children():
		c.queue_free()
	var systems: Dictionary
	var L: LayoutDef
	if online:
		L = Content.layout(cfg["layout"], cfg.get("mirror", false))
		systems = {}
		for k in cfg.get("systems", []):
			systems[k] = true
	else:
		L = sim.L
		systems = sim.systems
	view = HotelView.new()
	view.build(stage, L, systems, cfg)
	view.local_seats = router_to_sim.values()
	hud = Hud.new()
	hud.view = view
	hud.level = sim.level if sim else cfg.get("level_def", {})
	hud.local_seats = router_to_sim.values()
	hud.seat_device = sim_to_router
	hud.ui_scale = Settings.effective_ui_scale()
	hud.show_clock = cfg.get("mode", "campaign") in ["campaign", "quick"] or online
	add_child(hud)
	stage.set_pixel_lines(Settings.pixel_lines())
	stage.set_outlines(Settings.g("outlines") and Settings.g("graphics") != "low")
	stage.set_quality(str(Settings.g("graphics")))
	if sim:
		_fam_cache = SimInteract.introduced_families(sim)
		view.capture_tick(sim.s)
		view.capture_tick(sim.s)
		view.prewarm(sim.s)
		SimGuests.warm_paths(sim)
	InputRouter.gameplay = true
	InputRouter.clear_edges()
	if not InputRouter.menu_pause.is_connected(_on_pause_pressed):
		InputRouter.menu_pause.connect(_on_pause_pressed)
	InputRouter.device_missing.connect(_on_device_missing)
	InputRouter.device_restored.connect(_on_device_restored)
	var chapter := int(hud.level.get("chapter", 1))
	if cfg.get("mode", "") in ["tutorial"]:
		chapter = 1
	Audio.preload_chapter(maxi(1, chapter))
	Audio.play_music("planning")
	_planning_intro()
	if DevOverlay.enabled():
		add_child(DevOverlay.new(self))

func _planning_intro() -> void:
	if sim and sim.s["phase"] == "planning":
		captions.bark("bark.shift_start", "nana")

func _exit_tree() -> void:
	InputRouter.gameplay = false
	if captions:
		captions.bottom_offset = 70.0
	if InputRouter.menu_pause.is_connected(_on_pause_pressed):
		InputRouter.menu_pause.disconnect(_on_pause_pressed)
	if InputRouter.device_missing.is_connected(_on_device_missing):
		InputRouter.device_missing.disconnect(_on_device_missing)
	if InputRouter.device_restored.is_connected(_on_device_restored):
		InputRouter.device_restored.disconnect(_on_device_restored)

# ------------------------------------------------------------ loop

func _process(dt: float) -> void:
	if _invalid_cd > 0.0:
		_invalid_cd -= dt
	if paused or _done:
		if view:
			view.sync(1.0, 0.0 if paused else dt)
		return
	if online:
		_process_online(dt)
		return
	if dev_hold:
		while dev_steps > 0 and not _done:
			dev_steps -= 1
			_tick()
		view.sync(1.0, dt)
		return
	# A frame gap this long means the machine slept (a Deck suspend): come back paused.
	_local_frames += 1
	if dt > 1.5 and _local_frames > 10 and not frame_source.is_valid():
		_auto_pause()
		return
	acc += minf(dt, 0.25)
	var ticks := 0
	while acc >= TICK and ticks < 8:
		acc -= TICK
		ticks += 1
		_tick()
		if _done:
			break
	view.sync(clampf(acc / TICK, 0.0, 1.0), dt)

func _tick() -> void:
	var frames: Array = frame_source.call() if frame_source.is_valid() else InputRouter.build_frames(router_to_sim)
	sim.step(frames)
	view.capture_tick(sim.s)
	_decorate_state(sim.s)
	hud.feed(sim.s, sim.events)
	view.on_events(sim.events)
	_feedback(sim.events)
	_gag_tick(sim.events)
	if sim.tutorial != null:
		_tutorial_hud()
	if sim.s["phase"] == "done" and not _done:
		_done = true
		_finish()

func _decorate_state(st: Dictionary) -> void:
	st["_families"] = _fam_cache
	st["_can_finish"] = sim.can_finish_early() if sim else false
	if sim and not sim.level.get("ribbons", []).is_empty():
		st["_ribbons"] = SimScore.ribbons(sim)
	st["_jobs"] = useful_jobs(st)
	var warn := {}
	for k in st.get("warnings", {}):
		if not st.get("fired", {}).has(k):
			for ev in (sim.level.get("events", []) if sim else []):
				if ev["id"] == k and ev["type"] == "fixture_trip":
					warn[ev["args"]["fixture"]] = true
	st["_warn_fixtures"] = warn
	hud.hint_level = sim.tutorial.hint_level() if sim and sim.tutorial != null else 0

## Up to three optional suggestions (§5.3, §6.2): overdue/nearest request,
## unassigned guest patience, then dirty room; stable ID tie-breaks.
func useful_jobs(st: Dictionary) -> Array:
	var reqs: Array = []
	var lobby: Array = []
	var dirty: Array = []
	for gid in st.get("guests", {}):
		var g: Dictionary = st["guests"][gid]
		if g["state"] == "staying":
			for rq in g["reqs"]:
				if rq["st"] == "open":
					reqs.append([int(rq["dl"]), int(gid), {"icon": Hud.ITEM_ICON.get(rq["k"], "sys_help"), "pos": view.anchor_for_key("guest:%d" % int(gid)) - Vector3(0, 1.0, 0)}])
		elif g["state"] == "lobby":
			var pp := Vector3.ZERO
			if int(g["slot"]) >= 0:
				var p2: Vector2i = view.L.fixtures["pedestals"][int(g["slot"])]
				pp = Vector3(p2.x, 0, p2.y)
			lobby.append([int(g["patience_q"]), int(gid), {"icon": "item_ticket", "pos": pp}])
	for letter in view.L.active_rooms:
		var r: Dictionary = st["rooms"][letter]
		if int(r["guest"]) == 0 and int(r["reserved"]) == 0 and (r["bed"] != "Made" or int(r["mess"]) > 0):
			var bp: Vector2i = view.L.rooms[letter]["bed"]
			dirty.append([letter.unicode_at(0), 0, {"icon": "sys_bed_dirty", "pos": Vector3(bp.x, 0, bp.y)}])
	reqs.sort(); lobby.sort(); dirty.sort()
	var out: Array = []
	for lst in [reqs, lobby, dirty]:
		for e in lst:
			if out.size() < 3:
				out.append(e[2])
	return out

func _tutorial_hud() -> void:
	var tdef: Dictionary = sim.tutorial.current()
	# Captions sit above the tutorial card while it is shown.
	captions.bottom_offset = 70.0 if tdef.is_empty() else 165.0
	if tdef.is_empty():
		hud.tutorial = {}
		return
	var cap_key: String = tdef.get("caption", "")
	if tdef.has("caption_multi") and sim.s["humans"] >= 2:
		cap_key = tdef["caption_multi"]
	hud.tutorial = {"caption": Loc.t(cap_key), "speaker": tdef.get("speaker", "nana"), "icon": tdef.get("icon", "sys_help"),
		"circles": sim.tutorial.circles}
	# Highlight the step's hint targets in the world after 15 s (icon pulse) /
	# 30 s (pointing arrow) of no progress.
	var lvl: int = sim.tutorial.hint_level()
	if lvl >= 1:
		var keys: Array = tdef.get("hint", [])
		var jobs: Array = []
		for k in keys:
			var kk: String = k
			if kk.contains(":mallow") or kk.contains(":whisp"):
				var tag := kk.split(":")[1]
				kk = kk.split(":")[0] + ":%d" % int(sim.tutorial.tags.get(tag, 0))
			var a := view.anchor_for_key(kk)
			if a != Vector3.ZERO and jobs.size() < 3:
				jobs.append({"icon": "sys_help", "pos": a - Vector3(0, 1.0, 0)})
		sim.s["_jobs"] = jobs
		for st in sim.s["staff"]:
			st["hint_t"] = 30 if lvl >= 2 else 0
			st["hint_i"] = 0

# ------------------------------------------------------------ feedback

const SFX := {"pickup": "pickup", "place": "place", "handoff": "handoff", "work_start": "work_start",
	"work_done": "work_finish", "bed_made": "bed_make", "bed_stripped": "bed_strip", "room_mopped": "mop",
	"watered": "watering", "can_filled": "watering", "curtain_hung": "curtain_swish", "curtain_removed": "curtain_swish",
	"gate": "gate", "thermostat": "thermostat", "pump": "pump_mode", "hamper_in": "hamper", "laundry_done": "laundry_done",
	"stock_refill": "stock_refill", "take_stock": "pickup", "take_gift": "pickup", "take_curtain": "pickup",
	"gift_placed": "gift_place", "assign": "ticket_assign", "guest_arrive": "arrival", "guest_announce": "chime",
	"request_open": "request_appear", "request_done": "request_done", "request_missed": "request_late",
	"checkout": "goodbye", "trip_reset": "trip_reset", "bell": "bell_ring", "lift_depart": "lift_depart",
	"lift_arrive": "lift_arrive", "trunk_delivered": "trunk_open", "parcel_installed": "parcel_place",
	"wet_feet": "wet_squeak", "quick_step": "quick_step", "frost": "frost_ting", "cloud": "steam_puff",
	"trip": "trip", "puddle": "overflow", "grip": "pickup", "release": "place", "kiosk_cycle": "ui_move",
	"pressed_linen": "linen_fold", "dock": "place", "frost_cleared": "work_finish", "cloud_gone": "fan",
	"relocate": "ticket_assign", "move_ticket": "pickup", "tool_home": "gus_rattle", "find_tools": "gus_rattle"}

func _feedback(events: Array) -> void:
	for e in events:
		var t: String = e["type"]
		var seat: int = int(e.get("seat", -1))
		if SFX.has(t):
			Audio.sfx(SFX[t])
		match t:
			"invalid":
				if _invalid_cd <= 0.0:
					Audio.sfx("target_invalid")
					_invalid_cd = 0.7
				_rumble(seat, 0.2, 0.0, 0.08)
			"handoff":
				_rumble(int(e.get("to", -1)), 0.3, 0.1, 0.1)
				if randi() % 3 == 0:
					captions.bark("bark.handoff", "nana")
			"useful_handoff":
				captions.bark("bark.handoff", "nana")
			"shared_work":
				Audio.sfx("cheer", -8.0)
				captions.bark("bark.shared_work", "nana")
			"welcome":
				var fam: String = e.get("fam", "slime")
				Audio.sfx("guest_%s_delight" % fam)
				var g: Dictionary = sim.guest(int(e["guest"])) if sim else {}
				if g.get("var", "") != "":
					captions.push(g["var"], Loc.t("guest.%s.delight" % g["var"]), "bark")
				if "musical_welcome" in cfg.get("modifiers", []):
					Audio.sfx("sting_star", -4.0, 1.0 + 0.1 * (int(e["guest"]) % 6), "Music")
				pass
			"request_done":
				_rumble(seat, 0.25, 0.0, 0.08)
			"request_missed":
				captions.bark("bark.missed_request", "nana")
			"guest_cozy":
				captions.bark("bark.lobby_timeout", "nana")
			"incident_warn":
				var k: String = e.get("kind", "")
				var gg: Dictionary = sim.guest(int(e.get("guest", 0))) if sim else {}
				if not gg.is_empty():
					Audio.warning("guest_%s_quirk_warn" % gg["fam"])
			"incident":
				var k2: String = e.get("kind", "")
				match k2:
					"howl": Audio.sfx("howl_note")
					"sneeze": Audio.sfx("guest_yeti_quirk")
					"hiccup": Audio.sfx("guest_dragon_quirk")
				if k2 in ["thermal_pulse", "humidity_pulse"]:
					Audio.sfx("steam_puff", -6.0)
			"quirk_cosmetic":
				var gg2: Dictionary = sim.guest(int(e.get("guest", 0))) if sim else {}
				if not gg2.is_empty():
					Audio.sfx("guest_%s_quirk" % gg2["fam"], -6.0)
			"helper":
				Audio.sfx("guest_%s_helper" % e.get("fam", "slime"))
			"comfort_recovered":
				if randi() % 2 == 0:
					captions.bark("bark.recovered_comfort", "nana")
			"comfort_lost":
				var gg3: Dictionary = sim.guest(int(e.get("guest", 0))) if sim else {}
				if not gg3.is_empty() and randi() % 3 == 0:
					Audio.sfx("guest_%s_need" % gg3["fam"], -4.0)
					if gg3["fam"] in ["dragon", "yeti"]:
						captions.bark("bark.thermal_conflict_" + gg3["fam"], gg3["fam"])
					elif gg3["fam"] == "ghost":
						captions.bark("bark.quiet_request", "ghost")
			"watered":
				captions.bark("bark.watering", "nana")
			"ping":
				Audio.sfx("ping_" + str(e.get("phrase", "help_here")).replace("help_here", "help").replace("bringing_it", "bringing").replace("room_ready", "ready").replace("thank_you", "thanks"))
			"shutter":
				Audio.sfx("shutter_" + ("warn" if e["state"] == "warn" else ("close" if e["state"] == "closed" else "open")))
			"countdown":
				Audio.stop_music()
				Audio.sting("sting_shift_start")
			"shift_start":
				Audio.sfx("countdown_go")
				Audio.start_chapter(clampi(int(hud.level.get("chapter", 1)), 1, 6))
			"wrap":
				Audio.sting("sting_wrap")
				captions.bark("bark.timer_wraps", "nana")
			"finish_prompt":
				Audio.sfx("bell_ring")
			"tutorial_step":
				# The tutorial card already shows the step with its speaker; the
				# caption bar would only repeat it on top of the card.
				Audio.sfx("chime", -8.0)
			"nana_helps":
				captions.push("nana", Loc.t("tut.nana_helps"), "teaching", 3.0)
			"coach":
				captions.push("nana", Loc.t("coach.%s.body" % e.get("id", "")), "teaching", 5.0)
			"gus_start":
				if randi() % 2 == 0:
					captions.push("gus", Loc.t("bark.gus_lift"), "bark", 2.0)
				Audio.sfx("gus_squeak", -6.0)
			"announce":
				var tk: String = e.get("text_key", "")
				if not tk.ends_with(".mid"):
					captions.push("nana", Loc.t(tk), "story", 4.0)
			"tool_home":
				pass
	# Music intensity from pending useful tasks and active guests.
	if sim and sim.s["phase"] == "active":
		var tasks := 0
		for gid in sim.s["guests"]:
			var g2: Dictionary = sim.s["guests"][gid]
			if g2["state"] == "lobby": tasks += 1
			elif g2["state"] == "staying":
				tasks += 1 if SimGuests.any_open_request(sim, g2) else 0
		var lvl := 0 if tasks <= 1 else (1 if tasks <= 3 else 2)
		if sim.s["cues"].has("level.L24.music"):
			lvl = 3
		if lvl != _last_music_level:
			Audio.set_intensity(lvl)
			_last_music_level = lvl

## Live gags (§15.2): one cue per level (story.<level>.mid) fired by its
## condition or fallback time; never twice; played in wrap-up if missed.
func _level_gag(trigger: String) -> void:
	if not sim or cfg.get("mode", "") != "campaign":
		return
	var lid: String = sim.level.get("id", "")
	var g: Dictionary = Content.gags.get(lid, {})
	if g.is_empty() or (g.get("trigger", "") != trigger and trigger != "_force"):
		return
	if sim.s["cues"].get("gag_played", false):
		return
	sim.s["cues"]["gag_played"] = true
	captions.push(g.get("speaker", "nana"), Loc.t(g.get("caption", "")), "story", 4.5)
	Audio.sfx("gus_squeak" if g.get("speaker", "") == "gus" else "chime", -6.0)
	view.nana_react("happy", 1.5)

func _gag_tick(events: Array) -> void:
	if not sim or cfg.get("mode", "") != "campaign" or sim.s["cues"].get("gag_played", false):
		return
	var lid: String = sim.level.get("id", "")
	var g: Dictionary = Content.gags.get(lid, {})
	if g.is_empty():
		return
	var trig: String = g.get("trigger", "")
	var st: Dictionary = sim.s["stats"]
	for e in events:
		var t: String = e["type"]
		match trig:
			"first_welcome": if t == "welcome": _level_gag(trig)
			"first_delivery": if t == "request_done": _level_gag(trig)
			"first_laundry": if t == "laundry_done": _level_gag(trig)
			"trunk_delivered": if t == "trunk_delivered": _level_gag(trig)
			"first_steam": if t == "cloud": _level_gag(trig)
			"first_vent": if t in ["gate", "thermostat"] and sim.s["phase"] == "active": _level_gag(trig)
			"recovery": if t in ["frost_cleared", "trip_reset", "cloud_gone", "comfort_recovered"]: _level_gag(trig)
			"quiet_howl": if t == "quiet_howl": _level_gag(trig)
			"first_watering": if t == "watered": _level_gag(trig)
			"first_shared": if t == "shared_work": _level_gag(trig)
			"shutter_closed": if t == "shutter" and e.get("state", "") == "closed": _level_gag(trig)
			"first_lift": if t == "lift_arrive": _level_gag(trig)
			"first_relocation": if t == "relocate": _level_gag(trig)
			"first_parcel": if t == "parcel_installed": _level_gag(trig)
			"second_trunk":
				if t == "trunk_delivered":
					var n := 0
					for k in sim.s["goals"]:
						if sim.s["goals"][k].get("done", false) and sim.s["goals"][k].get("kind", "") == "trunk":
							n += 1
					if n >= 2: _level_gag(trig)
			"two_helpers": if t == "helper" and int(st.get("helpful_guests", 0)) >= 2: _level_gag(trig)
			"three_cozy": if t == "cozy_departure" and int(st.get("cozy_departures", 0)) >= 3: _level_gag(trig)
		if t == "wrap":
			_level_gag("_force")
		if t == "announce" and str(e.get("text_key", "")) == "level.%s.mid" % lid:
			_level_gag("_force")
	var fb := int(g.get("fallback_s", 0))
	if fb > 0 and int(sim.s["hotel_s"]) >= fb:
		_level_gag("_force")

func _rumble(seat: int, weak: float, strong: float, dur: float) -> void:
	if seat < 0 or not sim_to_router.has(seat):
		return
	InputRouter.rumble(sim_to_router[seat], weak, strong, dur)

# ------------------------------------------------------------ pause

func _notification(what: int) -> void:
	# Leaving the game mid-shift (alt-tab, the Steam overlay) pauses local play.
	if what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_focused = true
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT and _focused:
		_auto_pause()

func _auto_pause() -> void:
	if online or paused or _done or frame_source.is_valid() or not is_inside_tree():
		return
	var seats: Array = router_to_sim.keys()
	open_pause(seats.min() if not seats.is_empty() else 0)

func _on_pause_pressed(router_seat: int) -> void:
	if _done:
		return
	if paused:
		resume()
	else:
		open_pause(router_seat)

func open_pause(router_seat := 0) -> void:
	if online:
		Net.lobby(router_to_sim.get(router_seat, 0), "pause", "break")
	paused = true
	InputRouter.gameplay = false
	Audio.set_paused_filter(true)
	pause_menu = PauseMenu.new()
	pause_menu.setup(self, router_seat)
	get_parent().add_child(pause_menu)

func resume() -> void:
	if online:
		Net.lobby(router_to_sim.values()[0] if not router_to_sim.is_empty() else 0, "resume")
	paused = false
	if is_instance_valid(pause_menu):
		pause_menu.queue_free()
	pause_menu = null
	InputRouter.gameplay = true
	InputRouter.clear_edges()
	Audio.set_paused_filter(false)

func find_tools() -> void:
	if sim:
		sim.find_tools()
	resume()

func back_to_lobby(router_seat: int) -> void:
	if sim:
		sim.back_to_lobby(router_to_sim.get(router_seat, 0))
	resume()

func _on_device_missing(router_seat: int) -> void:
	if sim and router_to_sim.has(router_seat):
		sim.set_present(router_to_sim[router_seat], false)
	if not paused:
		open_pause(router_seat)

func _on_device_restored(router_seat: int) -> void:
	if sim and router_to_sim.has(router_seat):
		sim.set_present(router_to_sim[router_seat], true)

func suspend() -> Dictionary:
	if not sim:
		return {}
	var snap := sim.snapshot()
	return {"cfg": cfg, "snap": snap, "content_hash": Content.content_hash, "saved_at": Time.get_unix_time_from_system()}

func restore_suspended(d: Dictionary) -> bool:
	if d.get("content_hash", "") != Content.content_hash:
		return false
	sim.restore(d["snap"])
	sim.s["phase"] = "planning" if sim.s["phase"] == "active" else sim.s["phase"]
	for st in sim.s["staff"]:
		st["ready"] = false
	sim.s["resumed"] = true
	view.capture_tick(sim.s)
	view.capture_tick(sim.s)
	return true

# ------------------------------------------------------------ finish

func _finish() -> void:
	InputRouter.gameplay = false
	var res: Dictionary = sim.s.get("result", {}).duplicate(true)
	res["result_id"] = "%s-%d-%d" % [cfg.get("level_id", cfg.get("tutorial_id", "X")), int(cfg.get("seed", 0)), int(Time.get_unix_time_from_system() * 1000) % 100000000]
	res["seed"] = cfg.get("seed", 0)
	res["staff"] = []
	for st in sim.s["staff"]:
		res["staff"].append(st["char"])
	res["outfit"] = cfg.get("cosmetic", "default")
	res["assist_signature"] = cfg.get("assist_signature", "none")
	res["modifier_signature"] = "+".join(cfg.get("modifiers", [])) if not cfg.get("modifiers", []).is_empty() else "none"
	res["mode"] = cfg.get("mode", "campaign")
	res["stats"] = sim.s["stats"].duplicate(true)
	res["gus"] = sim.s["gus"]["on"]
	res["coach_seen"] = sim.s.get("coach_seen", [])
	res["input_log_size"] = sim.input_log.size()
	_write_replay()
	finished.emit(res)

func _write_replay() -> void:
	# The last local shift is kept for bug reports (tools/dev/replay.gd).
	if cfg.get("mode", "") not in ["campaign", "quick"] or sim.s.get("resumed", false):
		return
	DirAccess.make_dir_recursive_absolute("user://replays")
	var f := FileAccess.open("user://replays/last_shift.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(SimReplay.capture(sim)))
		f.close()

func leave() -> void:
	InputRouter.gameplay = false
	left_shift.emit()

# ------------------------------------------------------------ online

func _process_online(dt: float) -> void:
	var frames := InputRouter.build_frames(router_to_sim)
	Net.client_send_frames(frames)
	var st: Dictionary = Net.client_state()
	if st.is_empty():
		return
	if st.get("_snap_id", -1) != net_state.get("_snap_id", -2):
		if net_state.is_empty():
			view.prewarm(st)
		net_state = st
		view.capture_tick(st)
		_decorate_online(st)
		var evs: Array = Net.client_take_events()
		hud.feed(st, evs)
		view.on_events(evs)
		_feedback(evs)
		if st.get("phase", "") == "done" and not _done:
			_done = true
			finished.emit(st.get("result", {}))
	view.sync(Net.client_alpha(), dt)

func _decorate_online(st: Dictionary) -> void:
	st["_families"] = SimC.FAMILIES
	st["_jobs"] = useful_jobs(st)
	hud.connection = Net.client_connection_map()
