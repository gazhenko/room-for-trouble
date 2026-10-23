extends Node
## SessionFlow (§2, §19.2): title → play mode → seats → hub → shift select →
## story beat → planning/shift → results → postcard → bridge/ending → hub.

var main
var party := {"mode": "couch", "difficulty": "family", "pace_milli": 1000}
var current_shift: ShiftScreen
var current_cfg: Dictionary = {}
var screen: Control
var _stack: Array = []
var last_result: Dictionary = {}

func boot(m) -> void:
	main = m
	party["difficulty"] = Settings.g("difficulty")
	party["pace_milli"] = int(Settings.g("pace_milli"))
	if SaveService.recovered_from != "":
		call_deferred("toast", Loc.t("ui.save.recovered"), "sys_postcard")
	Net.notice.connect(func(key: String):
		if key != "" and key != "ui.pause.title":
			toast(Loc.t(key), "ui_online"))
	Net.client_disconnected.connect(_on_net_lost)
	show_title()

## The service is gone for good during an online shift: never pretend the
## local client is authoritative; offer the way home (§11.5).
func _on_net_lost(reason_key: String) -> void:
	if current_shift == null or not current_cfg.get("online", false) or not is_instance_valid(current_shift):
		return
	InputRouter.gameplay = false
	var c := ChoiceScreen.new()
	c.setup(Loc.t("ui.online.lost_title"), Loc.t(reason_key), [
		[Loc.t("ui.online.return_hub"), "ui_hub", func():
			current_shift = null
			Net.leave_room()
			Net.disconnect_client()
			show_hub()]], "ui_online")
	overlay(c)

# ------------------------------------------------------------ screen stack

func _clear_ui() -> void:
	for c in main.ui_root.get_children():
		c.queue_free()
	_stack.clear()
	screen = null

func _set_screen(c: Control) -> void:
	_clear_ui()
	screen = c
	main.ui_root.add_child(c)

func push(c: Control) -> void:
	if screen:
		screen.visible = false
		_stack.append(screen)
	screen = c
	main.ui_root.add_child(c)

func pop() -> void:
	if screen:
		screen.queue_free()
	screen = _stack.pop_back() if not _stack.is_empty() else null
	if screen:
		screen.visible = true
		if screen is Screen:
			(screen as Screen).focus_first()

func overlay(c: Control) -> void:
	main.ui_root.add_child(c)

func toast(text: String, icon := "sys_postcard") -> void:
	var t := Toast.new()
	t.setup(text, icon)
	main.toast_layer.add_child(t)

func backdrop(kind := "title") -> void:
	for c in main.stage.world.get_children():
		c.queue_free()
	var bd := Backdrop.new()
	bd.build(main.stage, kind)

# ------------------------------------------------------------ menus

func show_title() -> void:
	InputRouter.gameplay = false
	InputRouter.reset_all()
	backdrop("title")
	Audio.play_music("title_loop")
	_set_screen(TitleScreen.new())

func show_main_menu() -> void:
	backdrop("title")
	Audio.play_music("title_loop")
	_set_screen(MainMenuScreen.new())

func start_lobby(mode: String) -> void:
	party["mode"] = mode
	if mode == "online":
		_set_screen(OnlineScreen.new())
		return
	var lobby := SeatLobby.new()
	lobby.setup(mode)
	_set_screen(lobby)

func after_lobby() -> void:
	if party["mode"] == "playground":
		start_playground()
		return
	if not SaveService.story_seen("O00"):
		play_story("O00", func(): _offer_first_lesson())
		return
	show_hub()

func _offer_first_lesson() -> void:
	SaveService.mark_story_seen("O00")
	var c := ChoiceScreen.new()
	c.setup(Loc.t("ui.first.title"), Loc.t("ui.first.body"), [
		[Loc.t("ui.first.tutorial"), "sys_coach", func(): start_tutorial("T01")],
		[Loc.t("ui.first.skip"), "ui_hub", func(): show_hub()]])
	_set_screen(c)

func show_hub() -> void:
	InputRouter.gameplay = false
	var hub := HubScreen.new()
	_clear_ui()
	screen = hub
	main.ui_root.add_child(hub)
	hub.setup_hub(main.stage, main.captions, _base_cfg({"mode": "hub", "layout": "P1"}))
	Audio.play_music("title_loop")

func open_shift_select() -> void:
	var s := ShiftSelectScreen.new()
	push(s)

func open_settings(_from: Node = null) -> void:
	push(SettingsScreen.new())

func open_scrapbook() -> void:
	push(ScrapbookScreen.new())

func open_credits() -> void:
	push(CreditsScreen.new())

func open_wardrobe() -> void:
	push(WardrobeScreen.new())

func open_practice() -> void:
	push(PracticeScreen.new())

func open_quick_shift() -> void:
	push(QuickShiftScreen.new())

# ------------------------------------------------------------ shift config

func _seats_cfg() -> Array:
	var out: Array = []
	var i := 0
	for rs in InputRouter.active_seats():
		var s: Dictionary = InputRouter.seats[rs]
		out.append({"seat": i, "char": s["char"], "cos": s["cos"], "assists": Settings.seat_assists(rs)})
		i += 1
	if out.is_empty():
		out.append({"seat": 0, "char": "pip", "cos": "default", "assists": Settings.seat_assists(0)})
	return out

func _base_cfg(extra: Dictionary) -> Dictionary:
	var seats := _seats_cfg()
	var cfg := {"humans": seats.size(), "seats": seats, "difficulty": party["difficulty"],
		"pace_milli": int(party.get("pace_milli", SimC.DIFFICULTY_PACE.get(party["difficulty"], 1000))),
		"seed": int(Time.get_unix_time_from_system()) % 1000003, "modifiers": [],
		"gus": Settings.g("gus_assist") or seats.size() == 1,
		"first_visit_coaches": _unseen_coaches(),
		"assist_signature": Settings.assist_signature(InputRouter.active_seats())}
	if party["difficulty"] != "custom":
		cfg["pace_milli"] = SimC.DIFFICULTY_PACE.get(party["difficulty"], 1000)
	for k in extra:
		cfg[k] = extra[k]
	return cfg

func _unseen_coaches() -> Array:
	var out: Array = []
	for c in ["sprout_first_water", "shutter_bypass", "luggage_lift"]:
		if not c in SaveService.profile["seen_coaches"]:
			out.append(c)
	return out

func start_level(level_id: String, extra := {}) -> void:
	var cfg := _base_cfg({"mode": extra.get("mode", "campaign"), "level_id": level_id})
	for k in extra:
		cfg[k] = extra[k]
	var pre := "%s.pre" % level_id
	if Content.story.has(pre) and cfg["mode"] == "campaign":
		play_story(pre, func(): _run_shift(cfg))
	else:
		_run_shift(cfg)

func start_tutorial(tid: String) -> void:
	var cfg := _base_cfg({"mode": "tutorial", "tutorial_id": tid, "gus": true})
	_run_shift(cfg)

func start_playground() -> void:
	var cfg := _base_cfg({"mode": "playground", "layout": "P6", "difficulty": "cozy", "gus": false})
	cfg["pace_milli"] = 1000
	_run_shift(cfg)

func start_quick(level_id: String, difficulty: String, seed_v: int, mods: Array) -> void:
	var prev: String = party["difficulty"]
	party["difficulty"] = difficulty
	var cfg := _base_cfg({"mode": "quick", "level_id": level_id, "seed": seed_v, "modifiers": mods})
	party["difficulty"] = prev
	_run_shift(cfg)

func _run_shift(cfg: Dictionary) -> void:
	current_cfg = cfg
	_clear_ui()
	main.captions.clear()
	var sh: ShiftScreen
	if cfg.get("mode", "") == "playground":
		sh = PlaygroundScreen.new()
	else:
		sh = ShiftScreen.new()
	sh.setup(main.stage, main.captions, cfg)
	sh.finished.connect(_on_shift_finished)
	sh.left_shift.connect(func(): show_hub())
	current_shift = sh
	screen = sh
	main.ui_root.add_child(sh)
	var susp: Dictionary = SaveService.profile.get("suspended_shift", {})
	if cfg.get("resume", false) and not susp.is_empty():
		if not sh.restore_suspended(susp):
			toast(Loc.t("ui.resume.incompatible"), "sys_help")
		SaveService.profile["suspended_shift"] = {}
		SaveService.save()

func run_online_shift(cfg: Dictionary) -> void:
	party["mode"] = "online"
	_run_shift(cfg)

func back_to_online_room() -> void:
	InputRouter.gameplay = false
	backdrop("title")
	_set_screen(OnlineScreen.new())

func restart_shift() -> void:
	var cfg := current_cfg.duplicate(true)
	cfg["seed"] = int(cfg.get("seed", 1)) + 1
	_run_shift(cfg)

func leave_shift() -> void:
	InputRouter.gameplay = false
	current_shift = null
	if current_cfg.get("online", false):
		Net.leave_room()
		Net.disconnect_client()
		show_main_menu()
		return
	show_hub()

func suspend_shift() -> void:
	if current_shift:
		SaveService.profile["suspended_shift"] = current_shift.suspend()
		SaveService.save()
		toast(Loc.t("ui.pause.suspended"), "sys_clock")
	leave_shift()

func resume_suspended() -> void:
	var d: Dictionary = SaveService.profile.get("suspended_shift", {})
	if d.is_empty():
		return
	var cfg: Dictionary = d["cfg"].duplicate(true)
	cfg["resume"] = true
	_run_shift(cfg)

# ------------------------------------------------------------ results flow

func _on_shift_finished(res: Dictionary) -> void:
	last_result = res
	var mode: String = current_cfg.get("mode", "campaign")
	if mode == "tutorial":
		var tid: String = current_cfg.get("tutorial_id", "")
		SaveService.mark_tutorial(tid, "done")
		for c in res.get("coach_seen", []):
			SaveService.mark_coach_seen(c)
		var after := ""
		if tid == "T02" or tid == "T03":
			after = ""
		toast(Loc.t("tut.%s.final" % tid), "sys_stamp")
		show_hub()
		return
	for c in res.get("coach_seen", []):
		SaveService.mark_coach_seen(c)
	var delta := SaveService.apply_result(res)
	if Net.is_online():
		Net.client_report_result(res)
	var rs := ResultsScreen.new()
	rs.setup(res, delta, current_cfg)
	_set_screen(rs)

func after_results(next_action: String) -> void:
	var lid: String = last_result.get("level", "")
	var after_story := "%s.post" % lid
	var then := func(): _after_post(next_action)
	if Content.story.has(after_story) and current_cfg.get("mode", "") == "campaign":
		play_story(after_story, then)
	else:
		then.call()

func _after_post(next_action: String) -> void:
	if current_cfg.get("online", false):
		back_to_online_room()
		return
	var lid: String = last_result.get("level", "")
	var idx := Content.level_index(lid)
	var bridge := ""
	if idx >= 0 and (idx + 1) % 4 == 0 and idx < 20:
		bridge = "B%02d" % ((idx + 1) / 4)
	if lid == "L24" and current_cfg.get("mode", "") == "campaign":
		play_story("E00", func(): show_hub())
		return
	var go := func():
		match next_action:
			"next":
				var nxt := Content.next_level_id(lid)
				if nxt != "":
					start_level(nxt)
				else:
					show_hub()
			"retry":
				start_level(lid, {"mode": current_cfg.get("mode", "campaign"), "modifiers": current_cfg.get("modifiers", []), "seed": current_cfg.get("seed", 1)})
			_:
				show_hub()
	if bridge != "" and current_cfg.get("mode", "") == "campaign" and not SaveService.story_seen(bridge):
		play_story(bridge, func():
			SaveService.mark_story_seen(bridge)
			go.call())
	else:
		go.call()

# ------------------------------------------------------------ story

func play_story(scene_id: String, then: Callable) -> void:
	var sc: Dictionary = Content.story.get(scene_id, {})
	if sc.is_empty():
		then.call()
		return
	_clear_ui()
	var sp := StoryPlayer.new()
	sp.setup(main.stage, main.captions, sc, then)
	screen = sp
	main.ui_root.add_child(sp)
