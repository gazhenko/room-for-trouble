class_name ResultsScreen
extends Screen
## Wrap-up (§10.4–10.6): team photograph, one transparent team result, stars,
## optional ribbons, completion stamp, unlocks. No individual blame ledger.

var res: Dictionary
var delta: Dictionary
var cfg: Dictionary
var _t := 0.0
var _stars_shown := 0
var photo: PixelStage
var stats_box: VBoxContainer

func setup(p_res: Dictionary, p_delta: Dictionary, p_cfg: Dictionary) -> void:
	res = p_res
	delta = p_delta
	cfg = p_cfg

func _ready() -> void:
	Audio.stop_music()
	Audio.sting("sting_results")
	var bg := ColorRect.new()
	bg.color = Color(0.13, 0.16, 0.2, 0.45)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var row := UiKit.hbox(24)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cc.add_child(row)
	add_child(cc)
	fit_to_screen(row)
	# Photo in a polaroid frame.
	var frame := UiKit.panel("card")
	frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var fv := UiKit.vbox(8)
	frame.add_child(fv)
	photo = PhotoStudio.make_stage(Vector2(520, 330), 200)
	fv.add_child(photo)
	var lid: String = res.get("level", "")
	PhotoStudio.stage_photo(photo, res.get("staff", ["pip"]), PhotoStudio.families_of(lid), {"outfit": res.get("outfit", "default")})
	var cap := UiKit.label(Loc.t("level.%s.title" % lid), 24, UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER)
	fv.add_child(cap)
	row.add_child(frame)
	# Score card.
	var card_p := UiKit.panel("cream")
	card_p.custom_minimum_size = Vector2(500, 0)
	var v := UiKit.vbox(10)
	card_p.add_child(v)
	row.add_child(card_p)
	var practice: bool = res.get("practice", false)
	var head := Loc.t("ui.res.practice") if practice else Loc.t("ui.res.title")
	v.add_child(UiKit.title(head, 30))
	var pct := UiKit.label(Loc.t("ui.res.percent", {"n": int(res.get("percent", 0))}), 40, UiKit.CORAL.darkened(0.25), HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(pct)
	stats_box = UiKit.vbox(6)
	v.add_child(stats_box)
	var comp: Dictionary = res.get("components", {})
	var sched := maxi(1, int(res.get("scheduled", 1)))
	for k in ["admission", "welcome", "service", "comfort"]:
		var max_pts = {"admission": 20, "welcome": 20, "service": 20, "comfort": 40}[k] * sched
		var got := float(comp.get(k, 0)) / 1000.0
		var h := UiKit.hbox(8)
		h.add_child(UiKit.icon({"admission": "item_ticket", "welcome": "gift_slime", "service": "item_towel", "comfort": "sys_cozy"}[k], 28))
		var l := UiKit.label(Loc.t("ui.res." + k), 20)
		l.custom_minimum_size = Vector2(170, 0)
		h.add_child(l)
		var bar := ProgressBar.new()
		bar.max_value = max_pts
		bar.value = got
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(200, 18)
		var fill := UiKit._box(UiKit.SAGE, UiKit.WALNUT, 2, 4, 0)
		var bgb := UiKit._box(Color("#E9DCC8"), UiKit.WALNUT, 2, 4, 0)
		bar.add_theme_stylebox_override("fill", fill)
		bar.add_theme_stylebox_override("background", bgb)
		h.add_child(bar)
		stats_box.add_child(h)
	var guests := UiKit.label(Loc.t("ui.res.guests", {"n": int(res.get("admitted", 0)), "of": sched}), 18, UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(guests)
	var rb_box := UiKit.vbox(4)
	v.add_child(rb_box)
	for rb in res.get("ribbons", []):
		var hh := UiKit.hbox(8)
		hh.add_child(UiKit.icon("sys_ribbon" if rb["earned"] else "sys_wait", 24))
		hh.add_child(UiKit.label("%s  (%d/%d)" % [rb["label"], int(rb["value"]), int(rb["target"])], 18, UiKit.INK if rb["earned"] else Color("#7A7268")))
		rb_box.add_child(hh)
	if res.get("gus", false):
		var gh := UiKit.hbox(8)
		gh.add_child(UiKit.icon("sys_assist", 24))
		gh.add_child(UiKit.label(Loc.t("ui.res.gus"), 16, Color("#6E655B")))
		v.add_child(gh)
	var bark := Loc.t("bark.low_score") if int(res.get("stars", 0)) == 0 else Loc.t("bark.any_completion")
	v.add_child(UiKit.label(bark, 18, UiKit.PLUM.darkened(0.3), HORIZONTAL_ALIGNMENT_CENTER))
	var btns := UiKit.hbox(10)
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(btns)
	var campaign: bool = cfg.get("mode", "") == "campaign"
	if practice:
		add_button(btns, Loc.t("ui.res.try_again"), "ui_quick", func(): Session.after_results("retry"), false, 220)
		add_button(btns, Loc.t("ui.res.keep_going"), "ui_play", func(): Session.after_results("next" if campaign else "hub"), false, 220)
	else:
		if campaign and Content.next_level_id(res.get("level", "")) != "":
			add_button(btns, Loc.t("ui.res.next"), "ui_play", func(): Session.after_results("next"), false, 200)
		add_button(btns, Loc.t("ui.res.try_again"), "ui_quick", func(): Session.after_results("retry"), false, 200)
		add_button(btns, Loc.t("ui.res.hub"), "ui_hub", func(): Session.after_results("hub"), false, 160)
	on_back(func(): Session.after_results("hub"))
	focus_first()
	for u in delta.get("unlocks", []):
		Session.toast(Loc.t("ui.res.unlock", {"name": Loc.t("cos.%s.name" % u)}), "badge_" + u)
		Audio.sting("sting_unlock")
	if delta.get("postcard", "") != "":
		Session.toast(Loc.t("ui.res.postcard"), "sys_postcard")
	for r in delta.get("ribbons", []):
		Session.toast(Loc.t("ui.res.ribbon", {"name": r}), "sys_ribbon")

func _process(dt: float) -> void:
	_t += dt
	var target := int(res.get("stars", 0))
	var due := int(_t / 0.6)
	if _stars_shown < target and due > _stars_shown and _t > 0.8:
		_stars_shown += 1
		Audio.sfx("sting_star", -2.0, 1.0 + 0.12 * _stars_shown, "Music")
	queue_redraw()

func _draw() -> void:
	var c := Vector2(size.x * 0.5, 54)
	for i in 3:
		var p := c + Vector2((i - 1) * 64, 0)
		var lit := i < _stars_shown
		var sc := 1.0 + (0.25 * maxf(0.0, 1.0 - (_t - 0.8 - i * 0.6) * 4.0) if lit and not Settings.g("reduced_motion") else 0.0)
		UiKit.draw_icon(self, "sys_star" if lit else "sys_star_empty", p, 56 * sc)
	if res.get("level", "") != "":
		UiKit.draw_icon(self, "sys_stamp", Vector2(size.x * 0.5 + 170, 54), 52)
