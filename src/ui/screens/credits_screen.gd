class_name CreditsScreen
extends Screen
## Credits and third-party licence notices, readable with a controller.

var body_box: VBoxContainer

func _init() -> void:
	super._init()
	var v := card(Loc.t("ui.menu.credits"), 900, "ui_credits")
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(860, 460)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var body := UiKit.vbox(6)
	body_box = body
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
	var row := UiKit.hbox(10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(row)
	add_button(row, Loc.t("ui.credits.scroll"), "ui_arrow_down", func(): scroll.scroll_vertical += 240, false, 260)
	add_button(row, Loc.t("ui.credits.licences"), "sys_help", func():
		_licences(body)
		scroll.scroll_vertical = 0, false, 260)
	add_button(row, Loc.t("ui.back"), "ui_arrow_left", func(): Session.pop(), false, 220)
	on_back(func(): Session.pop())

## Full licence texts shipped with the game: the engine, its bundled
## components (by name and licence) and the two OFL fonts.
func _licences(body: VBoxContainer) -> void:
	for c in body.get_children():
		c.queue_free()
	var add := func(title: String, text: String):
		body.add_child(UiKit.label(title, 24, UiKit.PLUM.darkened(0.3)))
		var l := UiKit.label(text, 14)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(820, 0)
		body.add_child(l)
		body.add_child(UiKit.label(" ", 8))
	add.call("Godot Engine " + str(Engine.get_version_info()["string"]), Engine.get_license_text())
	for font in ["PixelifySans", "Nunito"]:
		var path := "res://assets/export/fonts/OFL-%s.txt" % font
		if FileAccess.file_exists(path):
			add.call(font + " — SIL Open Font License 1.1", FileAccess.get_file_as_string(path))
	var comps: PackedStringArray = []
	for comp in Engine.get_copyright_info():
		var lic := {}
		for part in comp["parts"]:
			lic[part.get("license", "")] = true
		comps.append("%s (%s)" % [comp["name"], ", ".join(lic.keys())])
	add.call(Loc.t("ui.credits.components"), "\n".join(comps))
