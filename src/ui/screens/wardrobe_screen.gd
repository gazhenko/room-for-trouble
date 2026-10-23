class_name WardrobeScreen
extends Screen
## Cosmetic wardrobe (§16.3): eight unlockable sets plus the default palettes.
## Visual resources only — never stat modifiers.

func _init() -> void:
	super._init()
	var v := card(Loc.t("ui.hub.wardrobe"), 860, "badge_first_hello")
	var have: Array = SaveService.profile["unlocked_cosmetic_sets"]
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	v.add_child(grid)
	for cs in Content.cosmetics:
		var id: String = cs["id"]
		var got := id in have
		var badge: String = cs.get("badge", "badge_first_hello")
		var label := Loc.t("cos.%s.name" % id) if got else Loc.t("cos.%s.unlock" % id)
		var b := UiKit.button(label, badge if got else "sys_lock", 270)
		b.disabled = not got
		b.pressed.connect(func():
			for s in InputRouter.active_seats():
				InputRouter.seats[s]["cos"] = id
			SaveService.profile["selected_cosmetic_set"] = id
			SaveService.save()
			Session.toast(Loc.t("ui.wardrobe.wearing", {"name": Loc.t("cos.%s.name" % id)}), badge)
			Session.pop()
			Session.show_hub())
		grid.add_child(b)
	v.add_child(UiKit.label(Loc.t("ui.wardrobe.note"), 16, Color("#6E655B"), HORIZONTAL_ALIGNMENT_CENTER))
	add_button(v, Loc.t("ui.back"), "ui_arrow_left", func(): Session.pop(), false, 240)
	on_back(func(): Session.pop())
