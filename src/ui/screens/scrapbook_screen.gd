class_name ScrapbookScreen
extends Screen
## Scrapbook (§16): 24 postcards, guest guide, teamwork ribbons and story
## replays. Postcards are generated locally from staged in-game scenes.

var tab := "postcards"
var detail: Control

func _init() -> void:
	super._init()
	_build()

func _build() -> void:
	for c in get_children():
		c.queue_free()
	_first_focus = null
	var v := card(Loc.t("ui.scrap.title"), 1000, "ui_scrapbook")
	var tabs := UiKit.hbox(8)
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(tabs)
	for t in ["postcards", "guide", "ribbons", "stories"]:
		var b := UiKit.button(Loc.t("ui.scrap.tab_" + t), "", 200)
		b.toggle_mode = true
		b.button_pressed = t == tab
		var tv = t
		b.pressed.connect(func():
			tab = tv
			_build())
		tabs.add_child(b)
		if t == tab:
			_first_focus = b
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(960, 430)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	v.add_child(scroll)
	var body := UiKit.vbox(10)
	body.custom_minimum_size = Vector2(940, 0)
	scroll.add_child(body)
	match tab:
		"postcards": _postcards(body)
		"guide": _guide(body)
		"ribbons": _ribbons(body)
		"stories": _stories(body)
	add_button(v, Loc.t("ui.back"), "ui_arrow_left", func(): Session.pop(), false, 240)
	on_back(func(): Session.pop())
	focus_first()

func _postcards(body: VBoxContainer) -> void:
	var have: Dictionary = SaveService.profile["postcards"]
	body.add_child(UiKit.label(Loc.t("ui.scrap.postcards_n", {"n": have.size(), "of": 24}), 20, UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER))
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	body.add_child(grid)
	for L in Content.levels:
		var lid: String = L["id"]
		var got := have.has(lid)
		var b := UiKit.button(lid if got else "?", "sys_postcard" if got else "sys_lock", 150)
		b.disabled = not got
		b.pressed.connect(func(): _show_postcard(lid))
		grid.add_child(b)

func _show_postcard(lid: String) -> void:
	var pc: Dictionary = SaveService.profile["postcards"].get(lid, {})
	var ov := PostcardView.new()
	ov.setup(lid, pc)
	add_child(ov)

func _guide(body: VBoxContainer) -> void:
	var discover: bool = SaveService.profile.get("discover_guests", false)
	var met := {}
	for lid in SaveService.profile["completed_levels"]:
		for f in PhotoStudio.families_of(lid):
			met[f] = true
	for fam in SimC.FAMILIES:
		var p := UiKit.panel("card")
		var h := UiKit.hbox(14)
		p.add_child(h)
		h.add_child(UiKit.icon("fam_" + fam, 72))
		var col := UiKit.vbox(4)
		h.add_child(col)
		var d: Dictionary = Content.guest_def(fam)
		col.add_child(UiKit.label("%s — %s" % [Loc.t("guest.%s.name" % fam), Loc.t("cast." + d.get("named_variant", ""))], 24))
		var needs := UiKit.hbox(8)
		needs.add_child(UiKit.icon(Hud._family_need_icon(fam), 28))
		needs.add_child(UiKit.label(Loc.t("guest.%s.comfort" % fam), 18))
		needs.add_child(UiKit.icon("gift_" + fam, 28))
		needs.add_child(UiKit.label(Loc.t("item.welcome_%s" % fam), 18))
		col.add_child(needs)
		if discover and not met.has(fam):
			col.add_child(UiKit.label(Loc.t("ui.scrap.not_met"), 16, Color("#7A7268")))
		else:
			var q := UiKit.label(Loc.t("guest.%s.quirk_text" % fam), 16)
			q.custom_minimum_size = Vector2(780, 0)
			col.add_child(q)
			var hl := UiKit.label(Loc.t("ui.scrap.helper") + " " + Loc.t("guest.%s.helper_text" % fam), 16, UiKit.PLUM.darkened(0.3))
			hl.custom_minimum_size = Vector2(780, 0)
			col.add_child(hl)
		body.add_child(p)

func _ribbons(body: VBoxContainer) -> void:
	var earned: Array = SaveService.profile["earned_ribbons"]
	body.add_child(UiKit.label(Loc.t("ui.scrap.ribbons_n", {"n": earned.size(), "of": 72}), 20, UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER))
	for L in Content.levels:
		var lid: String = L["id"]
		var h := UiKit.hbox(10)
		h.add_child(UiKit.label("%s  %s" % [lid, Loc.t("level.%s.title" % lid)], 18))
		for rb in L["ribbons"]:
			var got := ("%s:%s" % [lid, rb["label"]]) in earned
			h.add_child(UiKit.icon("sys_ribbon" if got else "sys_wait", 22))
			h.add_child(UiKit.label(rb["label"], 15, UiKit.INK if got else Color("#9A9187")))
		body.add_child(h)

func _stories(body: VBoxContainer) -> void:
	var ids := ["O00", "B01", "B02", "B03", "B04", "B05", "E00"]
	for sid in ids:
		var seen := SaveService.story_seen(sid)
		var b := UiKit.button(Loc.t("story.%s.title" % sid) if seen else Loc.t("ui.scrap.story_locked"), "ui_photo" if seen else "sys_lock", 600)
		b.disabled = not seen
		var sv = sid
		b.pressed.connect(func(): Session.play_story(sv, func(): Session.show_hub()))
		body.add_child(b)
