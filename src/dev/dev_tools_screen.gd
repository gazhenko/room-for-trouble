class_name DevToolsScreen
extends Screen
## Content-author tools (§19.5), reachable from the main menu only when the
## game is launched with `-- --dev`: Validate Level, Play Level as 1/2/3/4
## (seat 1 is you, other seats use the reference driver), Preview Wave and
## Preview Story Panel. Reset to Seed lives in the in-shift DevOverlay (F9).

var level_id := "L01"
var out: Label

func _init() -> void:
	super._init()
	_build()

func _build() -> void:
	var keep := focus_index()
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_first_focus = null
	var v := card("Developer tools", 1000, "sys_help")
	var ids: Array = []
	for L in Content.levels:
		ids.append(L["id"])
	var labels: Array = []
	for id in ids:
		labels.append("%s %s" % [id, Loc.t("level.%s.title" % id)])
	add_cycle(v, "Level", ids, labels, level_id, func(val):
		level_id = val
		out.text = "")
	var row := UiKit.hbox(8)
	v.add_child(row)
	add_button(row, "Validate", "sys_help", func(): out.text = validate(level_id), false, 180)
	add_button(row, "Preview waves", "sys_team", func(): out.text = preview_waves(level_id), false, 220)
	add_button(row, "Pre story", "ui_photo", func(): Session.play_story(level_id + ".pre", func(): Session.show_main_menu()), false, 180)
	add_button(row, "Postcard", "sys_postcard", func(): Session.play_story(level_id + ".post", func(): Session.show_main_menu()), false, 180)
	var row2 := UiKit.hbox(8)
	v.add_child(row2)
	for n in [1, 2, 3, 4]:
		var nn: int = n
		add_button(row2, "Play as %d" % n, "ui_play", func(): play_as(level_id, nn), false, 180)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(960, 330)
	v.add_child(scroll)
	out = Label.new()
	out.add_theme_font_size_override("font_size", 14)
	out.add_theme_color_override("font_color", UiKit.INK)
	out.custom_minimum_size = Vector2(940, 0)
	out.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	scroll.add_child(out)
	add_button(v, Loc.t("ui.back"), "ui_arrow_left", func(): Session.pop(), false, 220)
	on_back(func(): Session.pop())
	restore_focus_index(keep)

## Schedules, reserves, ribbon bounds and event references at 1–4 players.
static func validate(lid: String) -> String:
	var L: Dictionary = Content.level(lid)
	var lay: LayoutDef = Content.layout(L["layout"])
	var lines: PackedStringArray = ["%s %s — layout %s, %d s, systems %s" % [lid, L["title"], L["layout"], L["duration_hotel_s"], ", ".join(L["systems"])]]
	var problems := 0
	for h in range(1, 5):
		var sched := ArrivalPlan.schedule(L, h, lay.active_rooms.size())
		var last := 0
		for a in sched:
			last = maxi(last, int(a["arrive_s"]))
		var reserve := int(L["duration_hotel_s"]) - last
		var ok := reserve >= 148 and not sched.is_empty()
		if not ok:
			problems += 1
		lines.append("  %d player%s: %d guests, last arrival %ds, reserve %ds %s" % [h, "" if h == 1 else "s", sched.size(), last, reserve, "✓" if ok else "✗"])
		for rb in L["ribbons"]:
			var tgt := int(rb["targets_1_to_4"][h - 1])
			if rb["predicate"] in ["welcome_matches", "cozy_departures", "helpful_guests", "relocations"] and tgt > sched.size():
				problems += 1
				lines.append("    ✗ ribbon %s target %d > %d guests" % [rb["label"], tgt, sched.size()])
	for ev in L["events"]:
		var known: bool = ev["type"] in ["announce", "coach", "thermal_pulse", "humidity_pulse", "steam_cloud", "frost_patch",
			"concert_pulse", "fixture_trip", "puddle_patch", "shutter_cycle", "trunk_spawn", "parcels_spawn"]
		if not known:
			problems += 1
		lines.append("  event %s %s @%ds %s" % [ev["id"], ev["type"], int(ev["at"]), "✓" if known else "✗ unknown type"])
	for sid in [lid + ".pre", lid + ".post"]:
		var has: bool = Content.story.has(sid)
		if not has:
			problems += 1
		lines.append("  story %s %s" % [sid, "✓" if has else "✗ missing"])
	lines.insert(1, "  %s" % ("no problems found" if problems == 0 else "%d problem(s)" % problems))
	return "\n".join(lines)

## Expanded rosters with arrival and announcement times for 1–4 players.
static func preview_waves(lid: String) -> String:
	var L: Dictionary = Content.level(lid)
	var lay: LayoutDef = Content.layout(L["layout"])
	var lines: PackedStringArray = []
	for h in range(1, 5):
		lines.append("%d player%s:" % [h, "" if h == 1 else "s"])
		var sched := ArrivalPlan.schedule(L, h, lay.active_rooms.size())
		var by_wave := {}
		for a in sched:
			var w := int(a["wave"])
			if not by_wave.has(w):
				by_wave[w] = []
			by_wave[w].append("%s@%ds" % [Loc.t("guest.%s.name" % a["family"]), int(a["arrive_s"])])
		for w in by_wave:
			lines.append("   wave %d: %s" % [int(w) + 1, ", ".join(by_wave[w])])
	return "\n".join(lines)

## Seat 1 is the local player; seats 2..n are driven by the reference bot.
static func play_as(lid: String, n: int) -> void:
	if InputRouter.active_seats().is_empty():
		InputRouter.join_last_menu_device()
	var seats: Array = []
	for i in n:
		seats.append({"seat": i, "char": SimC.STAFF_IDS[i % 4], "assists": Settings.seat_assists(0) if i == 0 else {"auto_catch": true}})
	var cfg := Session._base_cfg({"mode": "campaign", "level_id": lid, "humans": n, "seats": seats, "gus": n == 1})
	Session._run_shift(cfg)
	var sh: ShiftScreen = Session.current_shift
	if sh == null or n == 1:
		return
	var bot := ReferenceBot.new(sh.sim)
	sh.frame_source = func():
		var frames: Array = []
		for f in InputRouter.build_frames(sh.router_to_sim):
			if int(f["seat"]) == 0:
				frames.append(f)
		for f2 in bot.frames():
			if int(f2["seat"]) != 0:
				frames.append(f2)
		return frames
