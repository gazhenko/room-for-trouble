class_name PracticeScreen
extends Screen
## Practice door: tutorials (always available), Playground and Quick Shift.

func _init() -> void:
	super._init()
	var v := card(Loc.t("ui.hub.practice"), 600, "sys_coach")
	for tid in ["T01", "T02", "T03"]:
		var st: String = SaveService.profile["tutorial_status"].get(tid, "unseen")
		var b := add_button(v, "%s  %s" % [Loc.t("tut.%s.title" % tid), "✓" if st == "done" else ""], "sys_stamp" if st == "done" else "sys_coach", func(): Session.start_tutorial(tid))
	add_button(v, Loc.t("ui.menu.playground"), "ui_playground", func(): Session.start_playground())
	add_button(v, Loc.t("ui.select.quick"), "ui_quick", func(): Session.open_quick_shift())
	add_button(v, Loc.t("ui.back"), "ui_arrow_left", func(): Session.pop())
	on_back(func(): Session.pop())
