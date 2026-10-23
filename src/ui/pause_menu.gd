class_name PauseMenu
extends Screen
## Pause (§11.5): Resume, Settings, Find Tools, Back to Lobby, Restart Shift,
## Suspend, Leave Shift. Local pause is immediate for everyone.

var shift: ShiftScreen
var seat := 0

func setup(p_shift: ShiftScreen, p_seat: int) -> void:
	shift = p_shift
	seat = p_seat
	var v := card(Loc.t("ui.pause.title"), 520, "ui_settings")
	var missing := InputRouter.missing_seats()
	if not missing.is_empty():
		var l := UiKit.label(Loc.t("ui.pause.controller_missing", {"n": missing.size()}), 20, UiKit.CORAL.darkened(0.3), HORIZONTAL_ALIGNMENT_CENTER)
		v.add_child(l)
	add_button(v, Loc.t("ui.pause.resume"), "ui_play", shift.resume)
	add_button(v, Loc.t("ui.pause.settings"), "ui_settings", func(): Session.open_settings(self))
	add_button(v, Loc.t("ui.pause.find_tools"), "sys_inspect", shift.find_tools)
	add_button(v, Loc.t("ui.pause.back_to_lobby"), "sys_move", func(): shift.back_to_lobby(seat))
	if not shift.online:
		add_button(v, Loc.t("ui.pause.restart"), "ui_quick", func(): Session.restart_shift())
		if shift.cfg.get("mode", "") in ["campaign", "quick"]:
			add_button(v, Loc.t("ui.pause.suspend"), "sys_clock", func(): Session.suspend_shift())
	add_button(v, Loc.t("ui.pause.leave"), "ui_arrow_left", func(): Session.leave_shift())
	on_back(shift.resume)
