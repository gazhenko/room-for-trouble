class_name OnlineScreen
extends Screen
## Online Room (§11.4, §20.2): local seats → Create Room / Join Room (code pad)
## → room lobby (each local seat readies independently; the leader picks the
## shift and pace; everyone sees the same selection) → shift.

var state := "menu"     # menu | connecting | code | room
var code_text := ""
var status_label: Label
var pending := ""        # "create" | "join"
var _room_recv_ms := 0

func _init() -> void:
	super._init()

func _ready() -> void:
	Net.client_connected.connect(_on_connected)
	Net.client_failed.connect(_on_failed)
	Net.room_joined.connect(_on_joined)
	Net.lobby_updated.connect(func(_v):
		_room_recv_ms = Time.get_ticks_msec()
		if state == "room": _build_room())
	Net.shift_started.connect(_on_shift)
	Net.client_disconnected.connect(_on_failed)
	InputRouter.unjoined_press.connect(_on_unjoined)
	InputRouter.menu_accept.connect(_on_seat_accept)
	InputRouter.menu_nav.connect(_on_seat_nav)
	if InputRouter.active_seats().is_empty():
		InputRouter.join_last_menu_device()
	if Net.is_online() and Net.c_room_id != "":
		state = "room"
		_build_room()
	else:
		_build_menu()

func _exit_tree() -> void:
	super._exit_tree()
	for pair in [[Net.client_connected, _on_connected], [Net.client_failed, _on_failed], [Net.room_joined, _on_joined],
			[Net.shift_started, _on_shift], [Net.client_disconnected, _on_failed], [InputRouter.unjoined_press, _on_unjoined],
			[InputRouter.menu_accept, _on_seat_accept], [InputRouter.menu_nav, _on_seat_nav]]:
		if pair[0].is_connected(pair[1]):
			pair[0].disconnect(pair[1])

func _clear() -> void:
	for c in get_children():
		c.queue_free()
	_first_focus = null

func _build_menu() -> void:
	_clear()
	state = "menu"
	var v := card(Loc.t("ui.menu.online"), 680, "ui_online")
	var seats := InputRouter.active_seats()
	v.add_child(UiKit.label(Loc.t("ui.online.local_seats", {"n": seats.size()}), 18, UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER))
	add_button(v, Loc.t("ui.online.create"), "ui_hub", func(): _go("create"))
	add_button(v, Loc.t("ui.online.join"), "ui_online", func(): _build_code())
	status_label = UiKit.label(Loc.t("ui.online.endpoint", {"url": Settings.g("endpoint")}), 16, Color("#6E655B"), HORIZONTAL_ALIGNMENT_CENTER)
	status_label.custom_minimum_size = Vector2(620, 0)
	v.add_child(status_label)
	v.add_child(UiKit.label(Loc.t("ui.online.self_host"), 15, Color("#6E655B"), HORIZONTAL_ALIGNMENT_CENTER))
	add_button(v, Loc.t("ui.menu.settings"), "ui_settings", func(): Session.open_settings())
	add_button(v, Loc.t("ui.back"), "ui_arrow_left", _back_out)
	on_back(_back_out)
	focus_first()

func _back_out() -> void:
	Net.leave_room()
	Net.disconnect_client()
	Session.show_main_menu()

func _build_code() -> void:
	_clear()
	state = "code"
	var v := card(Loc.t("ui.online.code"), 760, "ui_online")
	v.add_child(UiKit.label(Loc.t("ui.online.enter_code"), 18, UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER))
	var le := LineEdit.new()
	le.text = code_text
	le.max_length = 9
	le.alignment = HORIZONTAL_ALIGNMENT_CENTER
	le.add_theme_font_size_override("font_size", 36)
	le.custom_minimum_size = Vector2(420, 60)
	le.text_changed.connect(func(t): code_text = NetProtocol.normalize_code(t))
	le.text_submitted.connect(func(_t): _go("join"))
	v.add_child(le)
	var grid := GridContainer.new()
	grid.columns = 8
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	v.add_child(grid)
	for ch in NetProtocol.CODE_ALPHABET:
		var c: String = ch
		var add_char := func():
			if code_text.length() < 8:
				code_text += c
				le.text = NetProtocol.pretty_code(code_text)
		add_button(grid, c, "", add_char, false, 64)
	var row := UiKit.hbox(8)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(row)
	var erase := func():
		code_text = code_text.substr(0, maxi(0, code_text.length() - 1))
		le.text = NetProtocol.pretty_code(code_text)
	add_button(row, "⌫", "", erase, false, 120)
	add_button(row, Loc.t("ui.online.join"), "ui_play", func(): _go("join"), false, 220)
	add_button(row, Loc.t("ui.back"), "ui_arrow_left", _build_menu, false, 160)
	on_back(_build_menu)
	focus_first()

func _go(what: String) -> void:
	pending = what
	_clear()
	state = "connecting"
	var v := card(Loc.t("ui.online.connecting"), 520, "sys_wait")
	status_label = UiKit.label(str(Settings.g("endpoint")), 16, Color("#6E655B"), HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(status_label)
	add_button(v, Loc.t("ui.back"), "ui_arrow_left", _back_out)
	on_back(_back_out)
	if Net.is_online():
		_on_connected()
	else:
		Net.connect_to(str(Settings.g("endpoint")))

func _chars() -> Array:
	var out: Array = []
	for s in InputRouter.active_seats():
		out.append(InputRouter.seats[s]["char"])
	return out

func _on_connected() -> void:
	if pending == "create":
		Net.create_room(InputRouter.active_seats().size(), _chars())
	elif pending == "join":
		Net.join_room(code_text, InputRouter.active_seats().size(), _chars())

func _on_failed(reason: String) -> void:
	_build_menu()
	if status_label:
		status_label.text = Loc.t(reason)
		status_label.add_theme_color_override("font_color", UiKit.CORAL.darkened(0.3))

func _on_joined(_info: Dictionary) -> void:
	state = "room"
	_build_room()

func _seat_map() -> Dictionary:
	var m := {}
	var locals := InputRouter.active_seats()
	for i in mini(locals.size(), Net.c_seats.size()):
		m[locals[i]] = int(Net.c_seats[i])
	return m

func _on_unjoined(device: String, action: String) -> void:
	if state != "menu" or action != "carry":
		return
	if device.begins_with("pad:"):
		InputRouter.join("pad", int(device.substr(4)))
	else:
		InputRouter.join(device)
	_build_menu()

func _on_seat_accept(router_seat: int) -> void:
	if state != "room":
		return
	var m := _seat_map()
	if not m.has(router_seat):
		return
	var sid: int = m[router_seat]
	var mine: Dictionary = {}
	for s in Net.c_room.get("seats", []):
		if int(s["id"]) == sid:
			mine = s
	Net.lobby(sid, "unready" if mine.get("ready", false) else "ready")

func _on_seat_nav(router_seat: int, dir: Vector2i) -> void:
	if state != "room" or dir.x == 0:
		return
	var m := _seat_map()
	if not m.has(router_seat):
		return
	var sid: int = m[router_seat]
	var ch: String = InputRouter.seats[router_seat]["char"]
	var i := SimC.STAFF_IDS.find(ch)
	ch = SimC.STAFF_IDS[(i + dir.x + 4) % 4]
	InputRouter.seats[router_seat]["char"] = ch
	Net.lobby(sid, "char", ch)

func _build_room() -> void:
	var keep := focus_index()
	_clear()
	var view: Dictionary = Net.c_room
	var v := card(Loc.t("ui.online.room_title", {"code": NetProtocol.pretty_code(view.get("code", ""))}), 900, "ui_online")
	v.add_child(UiKit.label(Loc.t("ui.online.share"), 18, UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(UiKit.title(NetProtocol.pretty_code(view.get("code", "")), 46))
	var row := UiKit.hbox(10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(row)
	var mine := Net.c_seats
	for s in view.get("seats", []):
		var p := UiKit.panel("card")
		p.custom_minimum_size = Vector2(190, 200)
		var col := UiKit.vbox(4)
		p.add_child(col)
		col.add_child(UiKit.label("P%d%s" % [int(s["id"]) + 1, "  ★" if int(s["id"]) == int(view.get("leader", -1)) else ""], 20, HotelView.SEAT_COLORS[int(s["id"]) % 4].darkened(0.4)))
		col.add_child(UiKit.icon("staff_" + str(s["char"]), 96))
		col.add_child(UiKit.label(Loc.t("cast." + str(s["char"])), 18))
		var st := Loc.t("ui.lobby.is_ready") if s["ready"] else ("…" if s["connected"] else Loc.t("ui.online.disconnected"))
		col.add_child(UiKit.label(st + ("  (you)" if int(s["id"]) in mine else ""), 16, Color("#2F5A25") if s["ready"] else Color("#6E655B")))
		row.add_child(p)
	var leader := int(view.get("leader", -1)) in mine
	var sel: Dictionary = view.get("selection", {})
	if leader:
		var ids: Array = []
		var labels: Array = []
		for L in Content.levels:
			if SaveService.is_accessible(L["id"]) or SaveService.is_completed(L["id"]):
				ids.append(L["id"])
				labels.append("%s %s" % [L["id"], Loc.t("level.%s.title" % L["id"])])
		if ids.is_empty():
			ids = ["L01"]; labels = ["L01"]
		add_cycle(v, Loc.t("ui.quick.level"), ids, labels, sel.get("level_id", ids[0]), func(val): Net.lobby(int(view["leader"]), "select_level", val))
		var diffs := ["cozy", "family", "busy"]
		var dl: Array = []
		for d in diffs:
			dl.append(Loc.t("ui.diff." + d))
		add_cycle(v, Loc.t("ui.diff.label"), diffs, dl, sel.get("difficulty", "family"), func(val): Net.lobby(int(view["leader"]), "difficulty", val))
		# "Start with ready players" unlocks 20 s after the first seat readied (§11.4).
		var wait := float(view.get("ready_wait_s", -1.0))
		var some_ready := false
		var all_ready := true
		for s3 in view.get("seats", []):
			if s3["connected"]:
				some_ready = some_ready or s3["ready"]
				all_ready = all_ready and s3["ready"]
		if some_ready and not all_ready and wait >= 0.0:
			var left := int(ceil(Net.START_READY_AFTER_S - wait - (Time.get_ticks_msec() - _room_recv_ms) / 1000.0))
			if left <= 0:
				add_button(v, Loc.t("ui.online.start_ready"), "ui_play", func(): Net.lobby(int(view["leader"]), "start_ready"))
			else:
				add_button(v, Loc.t("ui.online.start_ready_in", {"n": left}), "ui_play", func(): pass, true)
				get_tree().create_timer(minf(1.0, float(left))).timeout.connect(func(): if is_inside_tree() and state == "room": _build_room())
	else:
		v.add_child(UiKit.label("%s — %s · %s" % [sel.get("level_id", ""), Loc.t("level.%s.title" % sel.get("level_id", "L01")), Loc.t("ui.diff." + str(sel.get("difficulty", "family")))], 20, UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(UiKit.label(Loc.t("ui.lobby.hint_couch"), 16, Color("#6E655B"), HORIZONTAL_ALIGNMENT_CENTER))
	if view.get("phase", "") == "countdown":
		v.add_child(UiKit.label(Loc.t("ui.lobby.starting", {"n": int(ceil(float(view.get("countdown", 3))))}), 24, UiKit.CORAL.darkened(0.3), HORIZONTAL_ALIGNMENT_CENTER))
	add_button(v, Loc.t("ui.pause.leave"), "ui_arrow_left", _back_out)
	on_back(_back_out)
	restore_focus_index(keep)

func _on_shift(info: Dictionary) -> void:
	var cfg := {"online": true, "mode": info["cfg"].get("mode", "campaign"), "layout": info["layout"], "mirror": info["mirror"],
		"systems": info["systems"], "level_def": info["level"], "level_id": info["level"].get("id", ""),
		"seat_map": _seat_map(), "modifiers": info["cfg"].get("modifiers", []), "seed": info["cfg"].get("seed", 1)}
	Session.run_online_shift(cfg)
