extends Node
## Controller check with real OS-level devices (§24.4), run from an exported
## Linux build:  RoomForTrouble.x86_64 -- --gamepad-test --gamepad-out=DIR
## tools/gamepad_driver.py creates kernel (uinput/evdev) gamepads and presses
## their buttons; this harness drives the screens, announces each phase in
## DIR/phase.txt and records what the game actually received. Checks: four pads
## (mixed Xbox/PlayStation) join four seats, each stick moves only its own
## staff, Start pauses and B resumes, an unplugged pad marks its seat missing
## and pauses, and a different pad pressing Carry takes the seat over.

var main
var out_dir := "user://gamepad_test"
var report := {"ok": false, "steps": [], "errors": [], "pads": []}
var _t0 := 0

func setup(m) -> void:
	main = m
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--gamepad-out="): out_dir = a.substr(14)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_t0 = Time.get_ticks_msec()
	DirAccess.make_dir_recursive_absolute(out_dir)
	report["renderer"] = RenderingServer.get_current_rendering_method()
	run()

func _phase(name: String) -> void:
	var f := FileAccess.open(out_dir.path_join("phase.txt"), FileAccess.WRITE)
	f.store_string(name)
	f.close()
	print("[pads] phase ", name)

func step(name: String, ok: bool, detail := "") -> void:
	report["steps"].append({"name": name, "ok": ok, "detail": detail, "t_ms": Time.get_ticks_msec() - _t0})
	print("[pads] %s %s %s" % ["PASS" if ok else "FAIL", name, detail])
	if not ok:
		report["errors"].append(name + ": " + detail)

func wait_until(cond: Callable, secs: float) -> bool:
	var t := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t < secs * 1000.0:
		if cond.call():
			return true
		await get_tree().process_frame
	return cond.call()

func wait(s: float) -> void:
	await get_tree().create_timer(s, true, false, true).timeout

func run() -> void:
	SaveService.load_profile("gamepad_test")
	SaveService.mark_story_seen("O00")
	_phase("connect")
	var ok := await wait_until(func(): return Input.get_connected_joypads().size() >= 4, 30.0)
	var pads: Array = Input.get_connected_joypads()
	pads.sort()
	for j in pads:
		report["pads"].append({"id": j, "name": Input.get_joy_name(j), "guid": Input.get_joy_guid(j), "known": Input.is_joy_known(j)})
	step("four_pads_connected", ok, str(report["pads"]))
	if not ok:
		return _finish()
	# The first pad touches the menu (D-pad), so it opens the seat lobby and
	# becomes seat 1; the other three then press Carry to join, in order.
	InputRouter.reset_all()
	InputRouter.last_menu_device = "kb1"
	Session.show_main_menu()
	_phase("menu")
	ok = await wait_until(func(): return InputRouter.last_menu_device.begins_with("pad"), 20.0)
	step("pad_drives_menu", ok, InputRouter.last_menu_device)
	Session.start_lobby("couch")
	await wait(0.5)
	_phase("join")
	ok = await wait_until(func(): return InputRouter.active_seats().size() >= 4, 20.0)
	var dev := []
	for s in InputRouter.active_seats():
		dev.append("%d:%s%d/%s" % [s, InputRouter.seats[s]["device"], InputRouter.seats[s]["joy"], InputRouter.pad_family(s)])
	step("four_seats_joined_by_carry", ok, ", ".join(dev))
	var fams := {}
	for s2 in InputRouter.active_seats():
		fams[InputRouter.pad_family(s2)] = true
	step("mixed_glyph_families", fams.has("xbox") and fams.has("playstation"), str(fams.keys()))
	step("playstation_glyph_shown", _any_glyph("✕"), "carry glyphs " + str(_glyphs()))
	# Shift: every stick pushes its own staff a different way.
	Session._run_shift(Session._base_cfg({"mode": "campaign", "level_id": "L01", "seed": 5}))
	await wait(0.5)
	var sh: ShiftScreen = Session.current_shift
	sh.sim.start_now()
	await wait_until(func(): return sh.sim.s["phase"] == "active", 10.0)
	var start := {}
	for st in sh.sim.s["staff"]:
		start[int(st["seat"])] = Vector2(st["x"], st["z"]) / 1e6
	_phase("move")
	await wait(3.5)
	var dirs := {0: Vector2(1, 0), 1: Vector2(-1, 0), 2: Vector2(0, 1), 3: Vector2(0, -1)}
	var moved: Array = []
	var all_ok := true
	for st2 in sh.sim.s["staff"]:
		var seat := int(st2["seat"])
		var d: Vector2 = Vector2(st2["x"], st2["z"]) / 1e6 - start[seat]
		var want: Vector2 = dirs.get(seat, Vector2.ZERO)
		var good := d.length() > 0.4 and d.normalized().dot(want) > 0.7
		all_ok = all_ok and good
		moved.append("seat%d %.1f,%.1f" % [seat, d.x, d.y])
	step("each_stick_moves_only_its_seat", all_ok, ", ".join(moved))
	_phase("pause")
	ok = await wait_until(func(): return sh.paused, 6.0)
	step("start_pauses", ok)
	_phase("resume")
	ok = await wait_until(func(): return not sh.paused, 6.0)
	step("b_resumes", ok)
	_phase("unplug")
	ok = await wait_until(func(): return InputRouter.seats[1]["missing"], 10.0)
	var absent: bool = not bool(sh.sim.staff_by_seat(1).get("present", true))
	step("unplugged_seat_marked_missing", ok and absent, "sim present=%s" % (not absent))
	step("unplug_pauses_team", sh.paused)
	_phase("replug")
	ok = await wait_until(func(): return not InputRouter.seats[1]["missing"], 15.0)
	step("new_pad_takes_seat_with_carry", ok, "seat1 joy=%d family=%s" % [InputRouter.seats[1]["joy"], InputRouter.pad_family(1)])
	step("seat_present_again", sh.sim.staff_by_seat(1).get("present", false))
	_phase("resume2")
	ok = await wait_until(func(): return not sh.paused, 6.0)
	step("play_resumes_after_reclaim", ok)
	_finish()

func _glyphs() -> Array:
	var out: Array = []
	for s in InputRouter.active_seats():
		out.append(InputRouter.glyph(s, "carry").get("text", "?"))
	return out

func _any_glyph(txt: String) -> bool:
	return txt in _glyphs()

func _finish() -> void:
	_phase("done")
	report["ok"] = report["errors"].is_empty()
	var f := FileAccess.open(out_dir.path_join("gamepad_report.json"), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(report, "\t"))
		f.close()
	print("[pads] %s (%d errors)" % ["OK" if report["ok"] else "FAILED", report["errors"].size()])
	get_tree().quit(0 if report["ok"] else 1)
