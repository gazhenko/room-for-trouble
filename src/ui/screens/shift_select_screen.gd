class_name ShiftSelectScreen
extends Screen
## Start-shift desk (§16.2): chapters, 24 shift cards with completion stamps,
## best stars and ribbons; access depends only on completion stamps. Team-wide
## difficulty (Cozy/Family/Busy/Custom pace) and the Gus assist.

var chapter := 1
var cards_box: VBoxContainer
var info: Label
var diff_btn: Button

func _init() -> void:
	super._init()
	var highest := 1
	for lid in SaveService.profile["accessible_levels"]:
		var L: Dictionary = Content.level(lid)
		if not L.is_empty():
			highest = maxi(highest, int(L["chapter"]))
	chapter = highest
	_build()

func _build() -> void:
	for c in get_children():
		c.queue_free()
	_first_focus = null
	var v := card(Loc.t("ui.select.title"), 980, "ui_play")
	var tabs := UiKit.hbox(8)
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(tabs)
	for ch in range(1, 7):
		var b := UiKit.button(Loc.t("ui.select.chapter_short", {"n": ch}), "ch%d" % ch, 150)
		b.toggle_mode = true
		b.button_pressed = ch == chapter
		var chv := ch
		b.pressed.connect(func():
			chapter = chv
			_build())
		tabs.add_child(b)
		if ch == chapter:
			_first_focus = b
	v.add_child(UiKit.label(Loc.t("chapter.%d.title" % chapter) + "  —  " + Loc.t("chapter.%d.theme" % chapter), 22, UiKit.PLUM.darkened(0.3), HORIZONTAL_ALIGNMENT_CENTER))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	v.add_child(grid)
	var catch_up := SaveService.catch_up_levels()
	var first_card: Button = null
	for L in Content.chapter_levels(chapter):
		var lid: String = L["id"]
		var acc := SaveService.is_accessible(lid) or lid in catch_up
		var done := SaveService.is_completed(lid)
		var stars := _best_stars(lid)
		var ribbons := _ribbons_for(lid)
		var line2 := ""
		if not acc:
			line2 = Loc.t("ui.select.locked")
		else:
			line2 = "★".repeat(stars) + "☆".repeat(3 - stars) + "   " + Loc.t("ui.select.ribbons", {"n": ribbons, "of": 3})
			if lid in catch_up:
				line2 += "   · " + Loc.t("ui.select.catch_up")
		var b2 := UiKit.button("%s  %s\n%s" % [lid, Loc.t("level.%s.title" % lid), line2], "sys_stamp" if done else ("ui_play" if acc else "sys_lock"), 470)
		b2.custom_minimum_size = Vector2(470, 74)
		b2.disabled = not acc
		b2.pressed.connect(func(): Session.start_level(lid))
		b2.focus_entered.connect(func(): _show_info(lid))
		grid.add_child(b2)
		if acc and first_card == null:
			first_card = b2
	if first_card != null:
		_first_focus = first_card
	info = UiKit.label("", 18, UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER)
	info.custom_minimum_size = Vector2(900, 48)
	v.add_child(info)
	var row := UiKit.hbox(10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(row)
	var diffs := ["cozy", "family", "busy"]
	var dl: Array = []
	for d in diffs:
		dl.append(Loc.t("ui.diff." + d))
	add_cycle(row, Loc.t("ui.diff.label"), diffs, dl, Session.party["difficulty"], func(val):
		Session.party["difficulty"] = val
		Settings.set_value("difficulty", val))
	add_toggle(row, Loc.t("ui.assist.gus"), bool(Settings.g("gus_assist")), func(val): Settings.set_value("gus_assist", val))
	var row2 := UiKit.hbox(10)
	row2.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(row2)
	add_button(row2, Loc.t("ui.select.quick"), "ui_quick", func(): Session.open_quick_shift(), false, 300)
	add_button(row2, Loc.t("ui.back"), "ui_arrow_left", func(): Session.pop(), false, 220)
	on_back(func(): Session.pop())
	focus_first()

func _show_info(lid: String) -> void:
	var L: Dictionary = Content.level(lid)
	if info:
		var fams := {}
		for w in L["waves"]:
			for f in w["roster"]:
				fams[f] = true
		var names: Array = []
		for f in fams:
			names.append(Loc.t("guest.%s.name" % f))
		info.text = Loc.t("level.%s.blurb" % lid) + "\n" + Loc.t("ui.select.guests", {"list": ", ".join(names)})

func _best_stars(lid: String) -> int:
	var best := 0
	for k in SaveService.profile["best_results"]:
		if str(k).begins_with(lid + "|"):
			best = maxi(best, int(SaveService.profile["best_results"][k].get("stars", 0)))
	return best

func _ribbons_for(lid: String) -> int:
	var n := 0
	for r in SaveService.profile["earned_ribbons"]:
		if str(r).begins_with(lid + ":"):
			n += 1
	return n
