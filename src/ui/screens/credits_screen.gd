class_name CreditsScreen
extends Screen
## Credits and third-party licence notices, readable with a controller.

func _init() -> void:
	super._init()
	var v := card(Loc.t("ui.menu.credits"), 900, "ui_credits")
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(860, 460)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var body := UiKit.vbox(6)
	body.custom_minimum_size = Vector2(840, 0)
	scroll.add_child(body)
	var data = JSON.parse_string(FileAccess.get_file_as_string("res://data/credits.json")) if FileAccess.file_exists("res://data/credits.json") else {}
	if data is Dictionary:
		for sec in data.get("sections", []):
			body.add_child(UiKit.label(sec.get("title", ""), 26, UiKit.PLUM.darkened(0.3)))
			for line in sec.get("lines", []):
				var l := UiKit.label(line, 18)
				l.custom_minimum_size = Vector2(820, 0)
				body.add_child(l)
			body.add_child(UiKit.label(" ", 10))
	var up := add_button(v, Loc.t("ui.credits.scroll"), "ui_arrow_down", func(): scroll.scroll_vertical += 240, false, 300)
	add_button(v, Loc.t("ui.back"), "ui_arrow_left", func(): Session.pop(), false, 300)
	on_back(func(): Session.pop())
