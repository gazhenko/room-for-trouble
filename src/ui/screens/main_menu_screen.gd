class_name MainMenuScreen
extends Screen
## Title → Play Together / Solo / Playground / Settings / Scrapbook / Credits (§2).

var sub := ""

func _init() -> void:
	super._init()
	_build_main()

func _build_main() -> void:
	for c in get_children():
		c.queue_free()
	_first_focus = null
	var v := card("", 520)
	# The lockup heads the card; the tagline sits under it like a postcard caption.
	v.add_child(LogoLockup.header(0.56))
	v.add_child(UiKit.label(Loc.t("ui.title.tagline"), 20, UiKit.CORAL.darkened(0.35), HORIZONTAL_ALIGNMENT_CENTER))
	var susp: Dictionary = SaveService.profile.get("suspended_shift", {})
	if not susp.is_empty():
		add_button(v, Loc.t("ui.menu.resume"), "sys_clock", func():
			_join_menu_device()
			Session.resume_suspended())
	add_button(v, Loc.t("ui.menu.play_together"), "sys_team", _play_together)
	add_button(v, Loc.t("ui.menu.solo"), "ui_solo", func(): Session.start_lobby("solo"))
	add_button(v, Loc.t("ui.menu.playground"), "ui_playground", func(): Session.start_lobby("playground"))
	add_button(v, Loc.t("ui.menu.settings"), "ui_settings", func(): Session.open_settings())
	add_button(v, Loc.t("ui.menu.scrapbook"), "ui_scrapbook", func(): Session.open_scrapbook())
	add_button(v, Loc.t("ui.menu.whats_new"), "sys_star", func(): Session.open_whats_new())
	add_button(v, Loc.t("ui.menu.credits"), "ui_credits", func(): Session.open_credits())
	if DevOverlay.enabled():
		add_button(v, "Developer tools", "sys_help", func():
			_join_menu_device()
			Session.push(DevToolsScreen.new()))
	if not OS.has_feature("web"):
		add_button(v, Loc.t("ui.menu.quit"), "ui_close", func(): get_tree().quit())
	on_back(func(): Session.show_title())
	focus_first()

func _join_menu_device() -> void:
	if InputRouter.active_seats().is_empty():
		InputRouter.join_last_menu_device()

func _play_together() -> void:
	for c in get_children():
		c.queue_free()
	_first_focus = null
	var v := card(Loc.t("ui.menu.play_together"), 520, "sys_team")
	add_button(v, Loc.t("ui.menu.couch"), "ui_couch", func(): Session.start_lobby("couch"))
	add_button(v, Loc.t("ui.menu.online"), "ui_online", func(): Session.start_lobby("online"))
	add_button(v, Loc.t("ui.back"), "ui_arrow_left", _build_main)
	on_back(_build_main)
	focus_first()
