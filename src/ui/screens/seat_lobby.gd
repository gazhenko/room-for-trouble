class_name SeatLobby
extends Screen
## Local seat lobby (§11.4). Pressing Carry on an unused device creates a seat.
## Each seat chooses staff (left/right), outfit (up/down) and assists (Inspect)
## with its own device, then readies (Carry). All ready → 3 s countdown.

const ASSISTS := ["auto_catch", "toggle_work", "quick_step", "steady_feet"]

var mode := "couch"
var max_seats := 4
var assist_open: Dictionary = {}   # seat -> selected row
var countdown := -1.0
var _t := 0.0

func setup(p_mode: String) -> void:
	mode = p_mode
	max_seats = 1 if p_mode == "solo" else 4
	if p_mode != "online" and InputRouter.active_seats().size() > max_seats:
		for s in InputRouter.active_seats():
			if s >= max_seats:
				InputRouter.leave(s)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	InputRouter.unjoined_press.connect(_on_unjoined)
	InputRouter.menu_nav.connect(_on_nav)
	InputRouter.menu_accept.connect(_on_accept)
	InputRouter.menu_back.connect(_on_seat_back)
	InputRouter.menu_alt.connect(_on_alt)
	InputRouter.menu_pause.connect(_on_accept)
	# Seat 0 is created from the device that opened the menu if nobody joined.
	if InputRouter.active_seats().is_empty():
		InputRouter.join_last_menu_device()
	var used := {}
	for s in InputRouter.active_seats():
		used[InputRouter.seats[s]["char"]] = true

func _exit_tree() -> void:
	for sig_cb in [[InputRouter.unjoined_press, _on_unjoined], [InputRouter.menu_nav, _on_nav],
			[InputRouter.menu_accept, _on_accept], [InputRouter.menu_back, _on_seat_back],
			[InputRouter.menu_alt, _on_alt], [InputRouter.menu_pause, _on_accept]]:
		if sig_cb[0].is_connected(sig_cb[1]):
			sig_cb[0].disconnect(sig_cb[1])

func _on_unjoined(device: String, action: String) -> void:
	if action != "carry" and action != "pause":
		return
	if InputRouter.active_seats().size() >= max_seats:
		return
	var seat := -1
	if device.begins_with("pad:"):
		seat = InputRouter.join("pad", int(device.substr(4)))
	else:
		seat = InputRouter.join(device)
	if seat >= 0:
		Audio.ui("ready")
		_pick_free_char(seat)
		countdown = -1.0

func _pick_free_char(seat: int) -> void:
	var taken := {}
	for s in InputRouter.active_seats():
		if s != seat:
			taken[InputRouter.seats[s]["char"]] = true
	for c in SimC.STAFF_IDS:
		if not taken.has(c):
			InputRouter.seats[seat]["char"] = c
			return

func _on_nav(seat: int, dir: Vector2i) -> void:
	if seat < 0 or not InputRouter.seats[seat]["active"]:
		return
	var s: Dictionary = InputRouter.seats[seat]
	if assist_open.has(seat):
		if dir.y != 0:
			assist_open[seat] = (int(assist_open[seat]) + dir.y + ASSISTS.size()) % ASSISTS.size()
		elif dir.x != 0:
			_toggle_assist(seat, ASSISTS[int(assist_open[seat])])
		Audio.ui("ui_move")
		return
	if s["ready"]:
		return
	if dir.x != 0:
		var i := SimC.STAFF_IDS.find(s["char"])
		s["char"] = SimC.STAFF_IDS[(i + dir.x + 4) % 4]
		Audio.ui("ui_move")
	elif dir.y != 0:
		var sets: Array = SaveService.profile["unlocked_cosmetic_sets"]
		var j := maxi(0, sets.find(s["cos"]))
		s["cos"] = sets[(j + dir.y + sets.size()) % sets.size()]
		Audio.ui("ui_move")

func _toggle_assist(seat: int, key: String) -> void:
	var st := Settings.seat(seat)
	if key == "quick_step":
		var order := ["on", "toggle", "off"]
		Settings.set_seat(seat, key, order[(order.find(st[key]) + 1) % 3])
	else:
		Settings.set_seat(seat, key, not bool(st[key]))

func _on_accept(seat: int) -> void:
	if seat < 0 or not InputRouter.seats[seat]["active"]:
		return
	if assist_open.has(seat):
		_toggle_assist(seat, ASSISTS[int(assist_open[seat])])
		return
	var s: Dictionary = InputRouter.seats[seat]
	s["ready"] = not s["ready"]
	Audio.ui("ready" if s["ready"] else "unready")
	if not s["ready"]:
		countdown = -1.0

func _on_seat_back(seat: int) -> void:
	if seat < 0:
		return
	if assist_open.has(seat):
		assist_open.erase(seat)
		return
	var s: Dictionary = InputRouter.seats[seat]
	if s["ready"]:
		s["ready"] = false
		countdown = -1.0
		Audio.ui("unready")
		return
	if InputRouter.active_seats().size() <= 1:
		Session.show_main_menu()
		return
	InputRouter.leave(seat)
	Audio.ui("ui_back")

func _on_alt(seat: int, action: String) -> void:
	if seat < 0 or not InputRouter.seats[seat]["active"]:
		return
	if action == "inspect" or action == "work":
		if assist_open.has(seat):
			assist_open.erase(seat)
		else:
			assist_open[seat] = 0
		Audio.ui("ui_move")

func _process(dt: float) -> void:
	_t += dt
	var seats := InputRouter.active_seats()
	var all_ready := not seats.is_empty()
	for s in seats:
		if not InputRouter.seats[s]["ready"]:
			all_ready = false
	if all_ready:
		if countdown < 0.0:
			countdown = 3.0
			Audio.ui("photo_timer")
		countdown -= dt
		if countdown <= 0.0:
			countdown = -1.0
			for s2 in seats:
				InputRouter.seats[s2]["ready"] = false
			SaveService.profile["selected_staff"] = InputRouter.seats[seats[0]]["char"]
			Session.after_lobby()
			return
	else:
		countdown = -1.0
	queue_redraw()

func _draw() -> void:
	var f := UiKit.font()
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.13, 0.16, 0.2, 0.35))
	var title := Loc.t("ui.lobby.title_" + mode)
	UiKit.draw_text_outlined(self, Vector2(size.x * 0.5, 64), title, 38)
	var n := max_seats
	var w := 270.0
	var gap := 18.0
	var total := n * w + (n - 1) * gap
	var x0 := size.x * 0.5 - total * 0.5
	var y0 := 110.0
	var h := minf(470.0, size.y - 220.0)
	for i in n:
		var s: Dictionary = InputRouter.seats[i]
		var r := Rect2(Vector2(x0 + i * (w + gap), y0), Vector2(w, h))
		var col: Color = HotelView.SEAT_COLORS[i]
		draw_rect(Rect2(r.position + Vector2(0, 6), r.size), UiKit.SHADOW)
		draw_style_box(UiKit._box(UiKit.PAPER if s["active"] else Color("#EDE3D3"), col.darkened(0.35), 4, 14, 0), r)
		draw_style_box(UiKit._box(col, col.darkened(0.35), 0, 10, 0), Rect2(r.position + Vector2(4, 4), Vector2(w - 8, 36)))
		UiKit.draw_text_outlined(self, Vector2(r.position.x + w * 0.5, r.position.y + 30), "P%d" % (i + 1), 24, UiKit.INK, Color(0, 0, 0, 0))
		if not s["active"]:
			var join := Loc.t("ui.lobby.join")
			draw_multiline_string(f, Vector2(r.position.x + 20, r.position.y + h * 0.45), join, HORIZONTAL_ALIGNMENT_CENTER, w - 40, 20, 4, Color("#6E655B"))
			UiKit.draw_icon(self, "sys_controller", Vector2(r.position.x + w * 0.5 - 22, r.position.y + h * 0.33), 34)
			UiKit.draw_icon(self, "sys_keyboard", Vector2(r.position.x + w * 0.5 + 22, r.position.y + h * 0.33), 34)
			continue
		UiKit.draw_icon(self, "staff_" + s["char"], Vector2(r.position.x + w * 0.5, r.position.y + 130), 144)
		UiKit.draw_text_outlined(self, Vector2(r.position.x + w * 0.5, r.position.y + 228), Loc.t("cast." + s["char"]), 26)
		UiKit.draw_text_outlined(self, Vector2(r.position.x + w * 0.5, r.position.y + 256), "◂  " + Loc.t("ui.lobby.staff") + "  ▸", 16, Color("#6E655B"), Color(0, 0, 0, 0))
		var cs := Loc.t("cos.%s.name" % s["cos"])
		UiKit.draw_text_outlined(self, Vector2(r.position.x + w * 0.5, r.position.y + 290), "▴ " + cs + " ▾", 18, UiKit.INK, Color(0, 0, 0, 0))
		var dev := InputRouter.glyph(i, "carry")
		var dname := Loc.t("ui.lobby.device_" + ("pad" if s["device"] == "pad" else s["device"]))
		draw_string(f, Vector2(r.position.x + 16, r.position.y + h - 70), dname, HORIZONTAL_ALIGNMENT_LEFT, w - 32, 16, Color("#6E655B"))
		if assist_open.has(i):
			var ar := Rect2(r.position + Vector2(10, 150), Vector2(w - 20, 170))
			draw_style_box(UiKit._box(UiKit.CREAM, UiKit.PLUM, 3, 10, 0), ar)
			var st := Settings.seat(i)
			for k in ASSISTS.size():
				var key: String = ASSISTS[k]
				var val = st[key]
				var on = (val == true) or (val is String and val != "off")
				var txt := "%s: %s" % [Loc.t("ui.assist." + key), Loc.t("ui.assist.qs_" + str(val)) if key == "quick_step" else (Loc.t("ui.on") if on else Loc.t("ui.off"))]
				var yy := ar.position.y + 30 + k * 34
				if int(assist_open[i]) == k:
					draw_rect(Rect2(Vector2(ar.position.x + 6, yy - 20), Vector2(ar.size.x - 12, 28)), Color("#FFF1C9"))
				draw_string(f, Vector2(ar.position.x + 14, yy), txt, HORIZONTAL_ALIGNMENT_LEFT, ar.size.x - 24, 16, UiKit.INK)
		# Controls hint row.
		var gx := r.position.x + 18
		var gy := r.position.y + h - 36
		var g1 := InputRouter.glyph(i, "carry")
		gx += UiKit.draw_glyph(self, Vector2(gx + 12, gy), g1, 24) + 4
		draw_string(f, Vector2(gx, gy + 6), Loc.t("ui.lobby.ready") if not s["ready"] else Loc.t("ui.lobby.unready"), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UiKit.INK)
		var g2 := InputRouter.glyph(i, "inspect")
		var gx2 := r.position.x + w * 0.55
		gx2 += UiKit.draw_glyph(self, Vector2(gx2 + 12, gy), g2, 24) + 4
		draw_string(f, Vector2(gx2, gy + 6), Loc.t("ui.lobby.assists"), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UiKit.INK)
		if s["ready"]:
			var rr := Rect2(r.position + Vector2(w * 0.5 - 70, 320), Vector2(140, 40))
			draw_style_box(UiKit._box(Color("#D7F0C8"), Color("#5E8F4E"), 3, 10, 0), rr)
			UiKit.draw_text_outlined(self, rr.get_center() + Vector2(0, 8), Loc.t("ui.lobby.is_ready"), 22, Color("#2F5A25"), Color(0, 0, 0, 0))
	if countdown > 0.0:
		UiKit.draw_text_outlined(self, Vector2(size.x * 0.5, size.y - 50), Loc.t("ui.lobby.starting", {"n": int(ceil(countdown))}), 28)
	else:
		UiKit.draw_text_outlined(self, Vector2(size.x * 0.5, size.y - 50), Loc.t("ui.lobby.hint_" + ("solo" if mode == "solo" else "couch")), 20, UiKit.INK)
