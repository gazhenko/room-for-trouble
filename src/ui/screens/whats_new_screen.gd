class_name WhatsNewScreen
extends Screen
## "What's new in 2.0": one card, one line per change with its icon, readable
## with a controller (Back leaves). Reached from the main menu and the hub menu.

const LINES := [
	["ui_hub", "ui.whatsnew.floors"],
	["sys_star", "ui.whatsnew.cards"],
	["sys_move", "ui.whatsnew.hands"],
	["sys_warm", "ui.whatsnew.middle"],
	["tool_can", "ui.whatsnew.sprout_trunk"],
	["sys_frost", "ui.whatsnew.hazards"],
	["sys_sun_moon", "ui.whatsnew.light"],
	["sys_check", "ui.whatsnew.readable"],
	["sys_clock", "ui.whatsnew.saves"],
]

func _init() -> void:
	super._init()
	var v := card(Loc.t("ui.whatsnew.title"), 820, "sys_star")
	v.add_child(UiKit.label(Loc.t("ui.whatsnew.intro"), 20, UiKit.PLUM.darkened(0.3), HORIZONTAL_ALIGNMENT_CENTER))
	var body := UiKit.vbox(8)
	v.add_child(body)
	for ln in LINES:
		var row := UiKit.hbox(12)
		row.add_child(UiKit.icon(ln[0], 30))
		var l := UiKit.label(Loc.t(ln[1]), 19)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(700, 0)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		body.add_child(row)
	v.add_child(UiKit.label(Loc.t("ui.whatsnew.outro"), 17, Color("#6E655B"), HORIZONTAL_ALIGNMENT_CENTER))
	var btns := UiKit.hbox(10)
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(btns)
	add_button(btns, Loc.t("ui.back"), "ui_arrow_left", func(): Session.pop(), false, 240)
	on_back(func(): Session.pop())
