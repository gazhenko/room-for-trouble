class_name SettingsScreen
extends Screen
## Settings (§11.3): Gameplay, Controls (per seat: full remap, hold/toggle
## work, Auto Catch, quick step, deadzone, sensitivity, Steady Feet,
## vibration), Vision, Hearing, Comfort & reading, Online endpoint.

var tab := "gameplay"
var content: VBoxContainer
var scroll: ScrollContainer
var capture_label: Label
var seat_sel := 0
var _tab_switch := false

func _init() -> void:
	super._init()
	_build()

func _build() -> void:
	# Tab switches focus the new tab; other redraws keep the controller's place.
	var keep := -1 if _tab_switch else focus_index()
	_tab_switch = false
	for c in get_children():
		c.queue_free()
	_first_focus = null
	var v := card(Loc.t("ui.settings.title"), 940, "ui_settings")
	var tabs := UiKit.hbox(8)
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(tabs)
	for t in ["gameplay", "controls", "vision", "hearing", "comfort", "online"]:
		var b := UiKit.button(Loc.t("ui.settings.tab_" + t), "", 140)
		b.toggle_mode = true
		b.button_pressed = t == tab
		var tv = t
		b.pressed.connect(func():
			tab = tv
			_tab_switch = true
			_build())
		tabs.add_child(b)
		if t == tab:
			_first_focus = b
	scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(900, minf(440.0, get_viewport_rect().size.y - 230) if is_inside_tree() else 420.0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	v.add_child(scroll)
	content = UiKit.vbox(8)
	content.custom_minimum_size = Vector2(880, 0)
	scroll.add_child(content)
	match tab:
		"gameplay": _gameplay()
		"controls": _controls()
		"vision": _vision()
		"hearing": _hearing()
		"comfort": _comfort()
		"online": _online()
	var back := add_button(v, Loc.t("ui.back"), "ui_arrow_left", func(): Session.pop(), false, 260)
	on_back(func(): Session.pop())
	restore_focus_index(keep)

func _setter(key: String) -> Callable:
	return func(val): Settings.set_value(key, val)

func _heading(text: String) -> void:
	content.add_child(UiKit.label(text, 22, UiKit.PLUM.darkened(0.3)))

func _gameplay() -> void:
	_heading(Loc.t("ui.settings.h_difficulty"))
	var diffs := ["cozy", "family", "busy"]
	var dl: Array = []
	for d in diffs:
		dl.append(Loc.t("ui.diff." + d))
	add_cycle(content, Loc.t("ui.diff.label"), diffs, dl, Settings.g("difficulty"), func(val):
		Settings.set_value("difficulty", val)
		Session.party["difficulty"] = val)
	var paces := [500, 650, 800, 1000, 1100, 1200, 1350]
	var pl: Array = []
	for p in paces:
		pl.append("%.2f×" % (p / 1000.0))
	add_cycle(content, Loc.t("ui.settings.pace"), paces, pl, int(Settings.g("pace_milli")), func(val):
		Settings.set_value("pace_milli", val)
		Session.party["pace_milli"] = val
		Session.party["difficulty"] = "custom" if val != 1000 else Settings.g("difficulty"))
	content.add_child(UiKit.label(Loc.t("ui.settings.pace_note"), 16, Color("#6E655B")))
	add_toggle(content, Loc.t("ui.assist.gus"), Settings.g("gus_assist"), _setter("gus_assist"))
	add_toggle(content, Loc.t("ui.settings.hints"), Settings.g("hints"), _setter("hints"))
	add_toggle(content, Loc.t("ui.settings.discover"), SaveService.profile.get("discover_guests", false), func(val):
		SaveService.profile["discover_guests"] = val
		SaveService.save())
	_heading(Loc.t("ui.settings.h_tutorials"))
	add_button(content, Loc.t("ui.settings.replay_coaches"), "sys_coach", func():
		SaveService.profile["seen_coaches"] = []
		SaveService.save()
		Session.toast(Loc.t("ui.settings.coaches_reset"), "sys_coach"))

func _controls() -> void:
	var seats := InputRouter.active_seats()
	if seats.is_empty():
		content.add_child(UiKit.label(Loc.t("ui.settings.no_seats"), 20))
		return
	if not seat_sel in seats:
		seat_sel = seats[0]
	var labels: Array = []
	for s in seats:
		labels.append("P%d" % (s + 1))
	add_cycle(content, Loc.t("ui.settings.seat"), seats, labels, seat_sel, func(val):
		seat_sel = val
		_build())
	var st := Settings.seat(seat_sel)
	_heading(Loc.t("ui.settings.h_assists"))
	add_toggle(content, Loc.t("ui.assist.auto_catch"), st["auto_catch"], func(val): Settings.set_seat(seat_sel, "auto_catch", val))
	add_toggle(content, Loc.t("ui.assist.toggle_work"), st["toggle_work"], func(val): Settings.set_seat(seat_sel, "toggle_work", val))
	add_cycle(content, Loc.t("ui.assist.quick_step"), ["on", "toggle", "off"], [Loc.t("ui.assist.qs_on"), Loc.t("ui.assist.qs_toggle"), Loc.t("ui.assist.qs_off")], st["quick_step"], func(val): Settings.set_seat(seat_sel, "quick_step", val))
	add_toggle(content, Loc.t("ui.assist.steady_feet"), st["steady_feet"], func(val): Settings.set_seat(seat_sel, "steady_feet", val))
	var dzs := [0.05, 0.1, 0.15, 0.2, 0.25, 0.3, 0.35, 0.4]
	var dzl: Array = []
	for d in dzs:
		dzl.append("%.2f" % d)
	add_cycle(content, Loc.t("ui.settings.deadzone"), dzs, dzl, snappedf(float(st["deadzone"]), 0.05), func(val): Settings.set_seat(seat_sel, "deadzone", val))
	var sens := [0.6, 0.8, 1.0, 1.2, 1.4]
	var sl: Array = []
	for s2 in sens:
		sl.append("%.1f×" % s2)
	add_cycle(content, Loc.t("ui.settings.sensitivity"), sens, sl, float(st["sensitivity"]), func(val): Settings.set_seat(seat_sel, "sensitivity", val))
	add_slider(content, Loc.t("ui.settings.vibration"), float(st["vibration"]), func(val): Settings.set_seat(seat_sel, "vibration", val), 0.2)
	add_cycle(content, Loc.t("ui.settings.ui_scale_seat"), [1.0, 1.25, 1.5, 1.75], ["100%", "125%", "150%", "175%"], float(st.get("ui_scale", 1.0)), func(val): Settings.set_seat(seat_sel, "ui_scale", val))
	_heading(Loc.t("ui.settings.h_remap"))
	capture_label = UiKit.label("", 18, UiKit.CORAL.darkened(0.3))
	content.add_child(capture_label)
	for a in ["up", "down", "left", "right", "carry", "work", "step", "ping", "hint", "inspect", "pause"]:
		var g := InputRouter.glyph(seat_sel, a)
		var act = a
		var capture := func():
			capture_label.text = Loc.t("ui.settings.press_new", {"action": Loc.t("ui.action." + act)})
			InputRouter.begin_capture(seat_sel, act)
			if not InputRouter.rebind_captured.is_connected(_on_rebound):
				InputRouter.rebind_captured.connect(_on_rebound)
		add_button(content, "%s:   %s" % [Loc.t("ui.action." + a), g.get("text", "?")], "sys_controller" if InputRouter.seats[seat_sel]["device"] == "pad" else "sys_keyboard", capture, false, 560)
	add_button(content, Loc.t("ui.settings.reset_binds"), "ui_quick", func():
		InputRouter.reset_bindings(seat_sel)
		_build())
	content.add_child(UiKit.label(Loc.t("ui.settings.shared_kb_note"), 16, Color("#6E655B")))

func _on_rebound(_seat: int, _action: String, _b: Dictionary) -> void:
	if InputRouter.rebind_captured.is_connected(_on_rebound):
		InputRouter.rebind_captured.disconnect(_on_rebound)
	call_deferred("_build")

func _vision() -> void:
	add_cycle(content, Loc.t("ui.settings.ui_scale"), [1.0, 1.25, 1.5, 1.75], ["100%", "125%", "150%", "175%"], float(Settings.g("ui_scale")), _setter("ui_scale"))
	add_cycle(content, Loc.t("ui.settings.pixel_size"), ["chunky", "classic", "fine", "off"],
		[Loc.t("ui.settings.px_chunky"), Loc.t("ui.settings.px_classic"), Loc.t("ui.settings.px_fine"), Loc.t("ui.settings.px_off")], Settings.g("pixel_size"), _setter("pixel_size"))
	add_toggle(content, Loc.t("ui.settings.outlines"), Settings.g("outlines"), _setter("outlines"))
	add_toggle(content, Loc.t("ui.settings.high_contrast"), Settings.g("high_contrast"), _setter("high_contrast"))
	add_cycle(content, Loc.t("ui.settings.palette"), ["default", "deuteranopia", "protanopia", "tritanopia"],
		[Loc.t("ui.settings.pal_default"), Loc.t("ui.settings.pal_deut"), Loc.t("ui.settings.pal_prot"), Loc.t("ui.settings.pal_trit")], Settings.g("palette"), _setter("palette"))
	add_toggle(content, Loc.t("ui.settings.large_requests"), Settings.g("large_requests"), _setter("large_requests"))
	add_toggle(content, Loc.t("ui.settings.silhouettes"), Settings.g("persistent_silhouettes"), _setter("persistent_silhouettes"))
	add_toggle(content, Loc.t("ui.settings.reduced_transparency"), Settings.g("reduced_transparency"), _setter("reduced_transparency"))
	add_toggle(content, Loc.t("ui.settings.readable_font"), Settings.g("readable_font"), func(val):
		Settings.set_value("readable_font", val)
		_build())
	add_toggle(content, Loc.t("ui.settings.fullscreen"), Settings.g("fullscreen"), _setter("fullscreen"))
	add_toggle(content, Loc.t("ui.settings.vsync"), Settings.g("vsync"), _setter("vsync"))

func _hearing() -> void:
	for k in ["master", "music", "effects", "voices", "ui"]:
		add_slider(content, Loc.t("ui.settings.vol_" + k), float(Settings.g(k)), _setter(k), 0.1)
	add_toggle(content, Loc.t("ui.settings.mono"), Settings.g("mono"), func(val):
		Settings.set_value("mono", val)
		Audio.set_mono(val))
	add_toggle(content, Loc.t("ui.settings.gentle"), Settings.g("gentle_sound"), _setter("gentle_sound"))
	add_toggle(content, Loc.t("ui.settings.mute_chatter"), Settings.g("mute_chatter"), _setter("mute_chatter"))
	add_toggle(content, Loc.t("ui.settings.captions"), Settings.g("captions"), _setter("captions"))
	add_toggle(content, Loc.t("ui.settings.speaker_names"), Settings.g("speaker_names"), _setter("speaker_names"))
	add_toggle(content, Loc.t("ui.settings.sound_visuals"), Settings.g("sound_visuals"), _setter("sound_visuals"))

func _comfort() -> void:
	add_toggle(content, Loc.t("ui.settings.reduced_motion"), Settings.g("reduced_motion"), _setter("reduced_motion"))
	add_toggle(content, Loc.t("ui.settings.flashes"), Settings.g("flashes"), _setter("flashes"))
	add_toggle(content, Loc.t("ui.settings.camera_shake"), Settings.g("camera_shake"), _setter("camera_shake"))
	add_toggle(content, Loc.t("ui.settings.auto_advance"), Settings.g("reading_auto_advance"), _setter("reading_auto_advance"))
	var tts_ok := not DisplayServer.tts_get_voices().is_empty() if DisplayServer.get_name() != "headless" else false
	var b := add_toggle(content, Loc.t("ui.settings.read_aloud") + ("" if tts_ok else " (" + Loc.t("ui.settings.unavailable") + ")"), Settings.g("read_aloud"), _setter("read_aloud"))
	b.disabled = not tts_ok
	add_toggle(content, Loc.t("ui.settings.pseudo"), Settings.g("pseudo_loc"), func(val):
		Settings.set_value("pseudo_loc", val)
		_build())

func _online() -> void:
	content.add_child(UiKit.label(Loc.t("ui.settings.endpoint_note"), 18))
	var le := LineEdit.new()
	le.text = Settings.g("endpoint")
	le.custom_minimum_size = Vector2(760, 44)
	le.text_submitted.connect(func(t): Settings.set_value("endpoint", t.strip_edges()))
	le.focus_exited.connect(func(): Settings.set_value("endpoint", le.text.strip_edges()))
	content.add_child(le)
	content.add_child(UiKit.label(Loc.t("ui.settings.endpoint_local"), 16, Color("#6E655B")))
