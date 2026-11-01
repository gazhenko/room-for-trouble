extends Node
## Dev: boots the real Main scene and screenshots each front-end screen.
##   godot --path . res://tools/dev/ui_tour.tscn -- --out=build/shots/tour [--only=name]
var out := "build/shots/tour"
var only := ""
var main: Node

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.substr(6)
		elif a.begins_with("--only="): only = a.substr(7)
		elif a == "--pseudo": Loc.pseudo = true
		elif a.begins_with("--set="):
			var kv := a.substr(6).split("=", true, 1)
			var v: Variant = kv[1]
			if kv[1] in ["true", "false"]: v = kv[1] == "true"
			elif kv[1].is_valid_float(): v = float(kv[1])
			Settings.data[kv[0]] = v
	DisplayServer.window_set_size(Vector2i(1280, 720))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://").path_join(out))
	main = load("res://src/app/main.tscn").instantiate()
	add_child(main)
	await _wait(1.0)
	var steps := [
		["title", func(): pass],
		["main_menu", func(): Session.show_main_menu()],
		["lobby", func():
			InputRouter.join("kb1")
			InputRouter.join("kb2")
			Session.start_lobby("couch")],
		["opening", func(): Session.play_story("O00", func(): pass)],
		["opening_5", func():
			for i in 4: Session.screen._next()],
		["hub", func(): Session.show_hub()],
		["shift_select", func(): Session.open_shift_select()],
		["quick", func(): Session.open_quick_shift()],
		["settings", func(): Session.open_settings()],
		["scrapbook", func(): Session.open_scrapbook()],
		["wardrobe", func(): Session.open_wardrobe()],
		["credits", func(): Session.open_credits()],
		["licences", func():
			Session.open_credits()
			Session.screen._licences(Session.screen.body_box)],
		["level_pre", func(): Session.play_story("L05.pre", func(): pass)],
		["level_pre_L12", func(): Session.play_story("L12.pre", func(): pass)],
		["level_pre_L20", func(): Session.play_story("L20.pre", func(): pass)],
		["planning", func(): Session._run_shift(Session._base_cfg({"mode": "campaign", "level_id": "L08"}))],
		["pause", func(): Session.current_shift.open_pause(0)],
		["tutorial", func(): Session.start_tutorial("T01")],
		["results", func():
			var res := {"level": "L06", "percent": 82, "stars": 2, "components": {"admission": 140000, "welcome": 120000, "service": 110000, "comfort": 204000},
				"scheduled": 7, "admitted": 7, "ribbons": [{"label": "Two Kinds of Cozy", "earned": true, "value": 2, "target": 2}, {"label": "A Little Separation", "earned": false, "value": 1, "target": 2}],
				"staff": ["pip", "moss"], "gus": false, "result_id": "tour"}
			var rs := ResultsScreen.new()
			rs.setup(res, {"unlocks": [], "postcard": "", "ribbons": []}, {"mode": "campaign"})
			Session._set_screen(rs)],
		["postcard", func(): Session.play_story("L06.post", func(): pass)],
		["online", func(): Session.start_lobby("online")],
		["playground", func(): Session.start_playground()],
		["ending", func(): Session.play_story("E00", func(): pass)],
	]
	if DevOverlay.enabled():
		steps.append(["dev_tools", func():
			Session.show_main_menu()
			var dt := DevToolsScreen.new()
			Session.push(dt)
			dt.level_id = "L14"
			dt.out.text = DevToolsScreen.validate("L14") + "\n\n" + DevToolsScreen.preview_waves("L14")])
		steps.append(["dev_overlay", func():
			Session._run_shift(Session._base_cfg({"mode": "campaign", "level_id": "L14", "seed": 5}))
			Session.current_shift.sim.start_now()
			var ev := InputEventKey.new()
			ev.keycode = KEY_F2
			ev.pressed = true
			Input.parse_input_event(ev)])
	# Every panel of the cinematics (--only=cine_).
	for scene in [["O00", 9], ["B01", 4], ["B02", 4], ["B03", 4], ["B04", 4], ["B05", 4], ["E00", 10]]:
		for pi in scene[1]:
			var sid2: String = scene[0]
			var adv: int = pi
			steps.append(["cine_%s_%d" % [sid2, pi], func():
				Session.play_story(sid2, func(): pass)
				await get_tree().process_frame
				for k in adv:
					Session.screen._next()])
	# Every pre-shift beat and every postcard, for set-dressing review
	# (--only=pre_ / --only=post_).
	for i in range(1, 25):
		var sid := "L%02d.pre" % i
		steps.append(["pre_L%02d" % i, func(): Session.play_story(sid, func(): pass)])
	for i in range(1, 25):
		var sid := "L%02d.post" % i
		steps.append(["post_L%02d" % i, func(): Session.play_story(sid, func(): pass)])
	for st in steps:
		if only != "" and not only in st[0]:
			continue
		st[1].call()
		await _wait(1.6)
		var img := get_viewport().get_texture().get_image()
		img.save_png(ProjectSettings.globalize_path("res://").path_join(out).path_join(st[0] + ".png"))
		print("shot ", st[0])
		# Story beats report where heads land and what blocks the speaker's face.
		if Session.screen is StoryPlayer and is_instance_valid(Session.screen):
			print("CHECK %s %s" % [st[0], JSON.stringify((Session.screen as StoryPlayer).frame_report())])
	get_tree().quit()

func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout
