class_name QuickShiftScreen
extends Screen
## Quick Shift (§16.4): any accessible level, a difficulty, a visible seed and
## up to two compatible modifiers. Shows exactly what changes before Ready.

var level_id := "L01"
var difficulty := "family"
var seed_v := 1
var mods: Array = []
var desc: Label

func _init() -> void:
	super._init()
	var acc: Array = SaveService.profile["accessible_levels"]
	level_id = acc[acc.size() - 1] if not acc.is_empty() else "L01"
	difficulty = Session.party.get("difficulty", "family")
	if difficulty == "custom":
		difficulty = "family"
	seed_v = randi() % 100000
	_build()

func _compatible(mid: String) -> bool:
	var m: Dictionary = Content.modifiers.get(mid, {})
	var L: Dictionary = Content.level(level_id)
	for req in m.get("requires_systems", []):
		if not req in L.get("systems", []):
			return false
	for other in mods:
		if other in m.get("conflicts", []):
			return false
	return true

func _build() -> void:
	# Rebuilds keep the controller's place: refocus the control with the same name.
	var refocus := ""
	var fo := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	if fo != null and is_ancestor_of(fo):
		refocus = fo.name
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_first_focus = null
	var v := card(Loc.t("ui.select.quick"), 900, "ui_quick")
	var ids: Array = []
	var labels: Array = []
	for L in Content.levels:
		if SaveService.is_accessible(L["id"]) or SaveService.is_completed(L["id"]):
			ids.append(L["id"])
			labels.append("%s %s" % [L["id"], Loc.t("level.%s.title" % L["id"])])
	if ids.is_empty():
		ids = ["L01"]; labels = ["L01"]
	add_cycle(v, Loc.t("ui.quick.level"), ids, labels, level_id, func(val):
		level_id = val
		mods = mods.filter(func(m): return _compatible_after(m))
		_build()).name = "level"
	var diffs := ["cozy", "family", "busy"]
	var dl: Array = []
	for d in diffs:
		dl.append(Loc.t("ui.diff." + d))
	add_cycle(v, Loc.t("ui.diff.label"), diffs, dl, difficulty, func(val): difficulty = val).name = "difficulty"
	var reseed := func():
		seed_v = randi() % 100000
		_build()
	add_button(v, Loc.t("ui.quick.seed", {"seed": seed_v}), "ui_quick", reseed, false, 460).name = "seed"
	v.add_child(UiKit.label(Loc.t("ui.quick.mods", {"n": mods.size()}), 20, UiKit.PLUM.darkened(0.3)))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 8)
	v.add_child(grid)
	for mid in Content.modifiers:
		var on = mid in mods
		var ok = on or (_compatible(mid) and mods.size() < 2)
		var b := UiKit.button(("✓ " if on else "") + Loc.t("mod.%s.name" % mid), Content.modifiers[mid].get("icon", "sys_help"), 400)
		b.name = "mod_" + mid
		b.disabled = not ok
		var mv: String = mid
		b.pressed.connect(func():
			if mv in mods:
				mods.erase(mv)
			elif mods.size() < 2:
				mods.append(mv)
			_build())
		b.focus_entered.connect(func(): desc.text = Loc.t("mod.%s.desc" % mv))
		grid.add_child(b)
	desc = UiKit.label(Loc.t("ui.quick.mods_hint"), 18, UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER)
	desc.custom_minimum_size = Vector2(840, 50)
	v.add_child(desc)
	var row := UiKit.hbox(10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(row)
	add_button(row, Loc.t("ui.quick.start"), "ui_play", func(): Session.start_quick(level_id, difficulty, seed_v, mods), false, 280)
	add_button(row, Loc.t("ui.back"), "ui_arrow_left", func(): Session.pop(), false, 200)
	on_back(func(): Session.pop())
	var again := find_child(refocus, true, false) if refocus != "" else null
	if again is Control:
		(again as Control).call_deferred("grab_focus")
	else:
		focus_first()

func _compatible_after(mid: String) -> bool:
	var m: Dictionary = Content.modifiers.get(mid, {})
	var L: Dictionary = Content.level(level_id)
	for req in m.get("requires_systems", []):
		if not req in L.get("systems", []):
			return false
	return true
