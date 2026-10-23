class_name HubMenu
extends Screen
## Conventional hub menu: every hub function without physical navigation.

func _init() -> void:
	super._init()
	var v := card(Loc.t("ui.hub.title"), 520, "ui_hub")
	add_button(v, Loc.t("ui.hub.start"), "ui_play", func(): _swap(func(): Session.open_shift_select()))
	add_button(v, Loc.t("ui.hub.practice"), "sys_coach", func(): _swap(func(): Session.open_practice()))
	add_button(v, Loc.t("ui.hub.wardrobe"), "badge_first_hello", func(): _swap(func(): Session.open_wardrobe()))
	add_button(v, Loc.t("ui.menu.scrapbook"), "ui_scrapbook", func(): _swap(func(): Session.open_scrapbook()))
	add_button(v, Loc.t("ui.menu.settings"), "ui_settings", func(): _swap(func(): Session.open_settings()))
	add_button(v, Loc.t("ui.hub.change_seats"), "sys_team", func(): Session.start_lobby(Session.party.get("mode", "couch")))
	add_button(v, Loc.t("ui.hub.main_menu"), "ui_arrow_left", func(): Session.show_main_menu())
	add_button(v, Loc.t("ui.back"), "ui_close", func(): Session.pop())
	on_back(func(): Session.pop())

func _swap(open: Callable) -> void:
	Session.pop()
	open.call()
