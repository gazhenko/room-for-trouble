class_name PlaygroundBoard
extends Screen
## Controller-accessible playground board (§16.5).

var pg: PlaygroundScreen

func setup(p: PlaygroundScreen) -> void:
	pg = p
	var v := card(Loc.t("ui.pg.title"), 760, "ui_playground")
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	v.add_child(grid)
	for fam in SimC.FAMILIES:
		var b := add_button(grid, Loc.t("guest.%s.name" % fam), "fam_" + fam, func(): _do(func(): SimPlayground.spawn_guest(pg.sim, fam)), false, 230)
	var row := GridContainer.new()
	row.columns = 2
	row.add_theme_constant_override("h_separation", 10)
	row.add_theme_constant_override("v_separation", 10)
	v.add_child(row)
	add_button(row, Loc.t("ui.pg.arrangement"), "sys_check", func(): _do(func(): SimPlayground.good_arrangement(pg.sim)), false, 350)
	add_button(row, Loc.t("ui.pg.clear"), "sys_wave", func(): _confirm(func(): SimPlayground.clear_guests(pg.sim)), false, 350)
	add_button(row, Loc.t("ui.pg.dirty"), "sys_bed_dirty", func(): _do(func(): SimPlayground.set_rooms_dirty(pg.sim, true)), false, 350)
	add_button(row, Loc.t("ui.pg.make"), "sys_bed", func(): _do(func(): SimPlayground.set_rooms_dirty(pg.sim, false)), false, 350)
	add_button(row, Loc.t("ui.pg.warm"), "sys_warm", func(): _do(func(): SimPlayground.set_env(pg.sim, "heat", 60)), false, 350)
	add_button(row, Loc.t("ui.pg.cool"), "sys_cold", func(): _do(func(): SimPlayground.set_env(pg.sim, "heat", -60)), false, 350)
	add_button(row, Loc.t("ui.pg.damp"), "sys_humid", func(): _do(func(): SimPlayground.set_env(pg.sim, "hum", 75)), false, 350)
	add_button(row, Loc.t("ui.pg.noisy"), "sys_noise", func(): _do(func(): SimPlayground.set_env(pg.sim, "noise", 60)), false, 350)
	add_button(row, Loc.t("ui.pg.quirk"), "sys_steam", func(): _do(func(): SimPlayground.demo_quirk(pg.sim)), false, 350)
	add_button(row, Loc.t("ui.pg.helper"), "sys_heart", func(): _do(func(): SimPlayground.demo_helper(pg.sim)), false, 350)
	var lay := ["P1v2", "P2v2", "P3v2", "P4v2", "P5v2", "P6v2"]
	var labels: Array = []
	for l in lay:
		labels.append(Loc.t("layout.%s.name" % l.substr(0, 2)))
	add_cycle(v, Loc.t("ui.pg.floor"), lay, labels, pg.cfg.get("layout", "P6v2"), func(val): pg.switch_layout(val))
	add_button(v, Loc.t("ui.pause.settings"), "ui_settings", func(): Session.open_settings(self))
	add_button(v, Loc.t("ui.pg.resume"), "ui_play", _close)
	add_button(v, Loc.t("ui.pause.leave"), "ui_arrow_left", func(): Session.leave_shift())
	on_back(_close)

func _do(op: Callable) -> void:
	op.call()
	_close()

func _confirm(op: Callable) -> void:
	var c := ChoiceScreen.new()
	c.setup(Loc.t("ui.pg.reset_q"), Loc.t("ui.pg.reset_body"), [
		[Loc.t("ui.yes"), "sys_check", func():
			c.queue_free()
			_do(op)],
		[Loc.t("ui.no"), "ui_arrow_left", func(): c.queue_free()]])
	get_parent().add_child(c)

func _close() -> void:
	pg.resume()
