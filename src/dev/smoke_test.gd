extends Node
## Shipping smoke test (§24.5), run from an exported artifact:
##   RoomForTrouble --smoke-test [--smoke-out=DIR] [--smoke-endpoint=ws://host:port]
## Boots the real flow, plays L01 solo with the reference driver at high
## speed, verifies the completion is saved, visits Playground/Settings, and
## optionally creates an online room. Writes smoke_report.json + screenshots.

var main
var out_dir := "user://smoke"
var endpoint := ""
var timeout_s := 120   # wall-clock guard for the L01 run; raise for software renderers
var report := {"ok": false, "steps": [], "errors": []}
var _t0 := 0

func setup(m) -> void:
	main = m
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--smoke-out="): out_dir = a.substr(12)
		elif a.begins_with("--smoke-endpoint="): endpoint = a.substr(17)
		elif a.begins_with("--smoke-timeout="): timeout_s = int(a.substr(16))

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_t0 = Time.get_ticks_msec()
	DirAccess.make_dir_recursive_absolute(out_dir)
	report["version"] = ProjectSettings.get_setting("application/config/version")
	report["engine"] = Engine.get_version_info()["string"]
	report["os"] = OS.get_name()
	report["renderer"] = RenderingServer.get_current_rendering_method()
	report["adapter"] = RenderingServer.get_video_adapter_name()
	report["content_hash"] = Content.content_hash
	report["content_errors"] = Content.errors
	run()

func step(name: String, ok: bool, detail := "") -> void:
	report["steps"].append({"name": name, "ok": ok, "detail": detail, "t_ms": Time.get_ticks_msec() - _t0})
	print("[smoke] %s %s %s" % ["PASS" if ok else "FAIL", name, detail])
	if not ok:
		report["errors"].append(name + ": " + detail)

func shot(name: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	if img != null and not img.is_empty():
		img.save_png(out_dir.path_join(name + ".png"))

func wait(s: float) -> void:
	await get_tree().create_timer(s, true, false, true).timeout

func run() -> void:
	# Never touch the player's own scrapbook: use a fresh throwaway profile.
	for suffix in ["", ".bak1", ".bak2", ".bak3", ".tmp"]:
		var p := SaveService.path_for("smoke_test", suffix)
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
	SaveService.load_profile("smoke_test")
	await wait(1.0)
	step("boot_title", Session.screen is TitleScreen, str(Session.screen))
	await shot("01_title")
	Session.show_main_menu()
	await wait(0.4)
	step("main_menu", Session.screen is MainMenuScreen)
	InputRouter.reset_all()
	InputRouter.join("kb1")
	SaveService.mark_story_seen("O00")
	var before := SaveService.is_completed("L01")
	Session.party["difficulty"] = "family"
	Session._run_shift(Session._base_cfg({"mode": "campaign", "level_id": "L01", "seed": 42}))
	await wait(0.5)
	var sh: ShiftScreen = Session.current_shift
	step("shift_started", sh != null and sh.sim != null)
	if sh == null:
		return _finish()
	var bot := ReferenceBot.new(sh.sim)
	sh.frame_source = bot.frames
	sh.sim.start_now()
	await wait(1.0)
	await shot("02_shift")
	Engine.time_scale = 12.0
	var guard := Time.get_ticks_msec()
	while Session.screen == sh and Time.get_ticks_msec() - guard < timeout_s * 1000:
		await get_tree().process_frame
	Engine.time_scale = 1.0
	var res_ok := Session.screen is ResultsScreen
	step("shift_finished_results", res_ok, "last_result=%s%%" % Session.last_result.get("percent", -1))
	await wait(1.2)
	await shot("03_results")
	step("progress_saved", SaveService.is_completed("L01") and SaveService.is_accessible("L02"), "before=%s" % before)
	# Reload the profile from disk to prove persistence.
	SaveService.load_profile(SaveService.profile_id)
	step("profile_reload", SaveService.is_completed("L01"))
	Session.start_playground()
	await wait(1.5)
	step("playground", Session.current_shift is PlaygroundScreen)
	await shot("04_playground")
	Session.show_main_menu()
	Session.open_settings()
	await wait(0.5)
	step("settings", Session.screen is SettingsScreen)
	Session.open_credits()
	await wait(0.4)
	step("credits", Session.screen is CreditsScreen)
	if endpoint != "":
		await _online()
	_finish()

func _online() -> void:
	var st := {"joined": false, "code": ""}
	Net.room_joined.connect(func(info):
		st["joined"] = true
		st["code"] = info.get("room_code", ""))
	Net.client_connected.connect(func(): Net.create_room(1, ["pip"]))
	Net.connect_to(endpoint)
	var t := Time.get_ticks_msec()
	while not st["joined"] and Time.get_ticks_msec() - t < 10_000:
		await get_tree().process_frame
	step("online_create_room", st["joined"], "code=" + NetProtocol.pretty_code(st["code"]))
	Net.leave_room()
	Net.disconnect_client()

func _finish() -> void:
	report["ok"] = report["errors"].is_empty()
	report["duration_ms"] = Time.get_ticks_msec() - _t0
	var f := FileAccess.open(out_dir.path_join("smoke_report.json"), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(report, "\t"))
		f.close()
	print("[smoke] %s (%d errors) report: %s" % ["OK" if report["ok"] else "FAILED", report["errors"].size(), ProjectSettings.globalize_path(out_dir)])
	get_tree().quit(0 if report["ok"] else 1)
