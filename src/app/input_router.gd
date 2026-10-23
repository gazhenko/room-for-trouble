extends Node
## Device → local seat routing (§6.1, §11.4). Each keyboard slot and controller
## has its own binding set; events are routed per device, never through a
## merged global action query. Produces per-seat input frames for the sim and
## per-seat menu signals for the UI.

signal seat_joined(seat: int)
signal seat_left(seat: int)
signal device_missing(seat: int)
signal device_restored(seat: int)
signal menu_nav(seat: int, dir: Vector2i)
signal menu_accept(seat: int)
signal menu_back(seat: int)
signal menu_pause(seat: int)
signal menu_alt(seat: int, action: String)
signal unjoined_press(device: String, action: String)
signal rebind_captured(seat: int, action: String, binding: Dictionary)
signal any_input

const ACTIONS := ["up", "down", "left", "right", "carry", "work", "step", "ping", "hint", "inspect", "pause"]
const BTN := {"carry": 1, "work": 2, "step": 4, "ping": 8, "hint": 16, "inspect": 32}
const PING_HOLD_S := 0.35

static func _k(code: int, loc := 0) -> Dictionary:
	return {"k": code, "loc": loc}

var DEFAULT_KB1 := {
	"up": [_k(KEY_W)], "down": [_k(KEY_S)], "left": [_k(KEY_A)], "right": [_k(KEY_D)],
	"carry": [_k(KEY_E)], "work": [_k(KEY_SPACE)], "step": [_k(KEY_SHIFT, KEY_LOCATION_LEFT)],
	"ping": [_k(KEY_Q)], "hint": [_k(KEY_R)], "inspect": [_k(KEY_TAB)], "pause": [_k(KEY_ESCAPE)],
}
var DEFAULT_KB2 := {
	"up": [_k(KEY_UP)], "down": [_k(KEY_DOWN)], "left": [_k(KEY_LEFT)], "right": [_k(KEY_RIGHT)],
	"carry": [_k(KEY_CTRL, KEY_LOCATION_RIGHT)], "work": [_k(KEY_SHIFT, KEY_LOCATION_RIGHT)],
	"step": [_k(KEY_PERIOD)], "ping": [_k(KEY_SLASH)], "hint": [_k(KEY_COMMA)],
	"inspect": [_k(KEY_BACKSLASH)], "pause": [_k(KEY_ENTER)],
}
var DEFAULT_PAD := {
	"up": [{"b": JOY_BUTTON_DPAD_UP}], "down": [{"b": JOY_BUTTON_DPAD_DOWN}],
	"left": [{"b": JOY_BUTTON_DPAD_LEFT}], "right": [{"b": JOY_BUTTON_DPAD_RIGHT}],
	"carry": [{"b": JOY_BUTTON_A}], "work": [{"b": JOY_BUTTON_X}], "step": [{"b": JOY_BUTTON_B}],
	"ping": [{"b": JOY_BUTTON_Y}], "hint": [{"b": JOY_BUTTON_LEFT_SHOULDER}],
	"inspect": [{"b": JOY_BUTTON_RIGHT_SHOULDER}], "pause": [{"b": JOY_BUTTON_START}],
}

# seat state
var seats: Array = []
var gameplay := false          # true while a shift consumes frames
var menus_open_to_all := true  # before anyone joins, any device navigates menus
var capture := {}              # rebinding capture {seat, action}
var _keys_down := {}           # "code:loc" -> true
var _pad_buttons := {}         # "joy:button" -> true
var _nav_hold := {}            # seat -> {dir, t}
var _stick_nav := {}           # device key -> last dir
var last_menu_device := "kb1"  # device that most recently used a menu

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 4:
		seats.append(_empty_seat(i))
	Input.joy_connection_changed.connect(_on_joy_changed)
	_strip_ui_actions()

func _empty_seat(i: int) -> Dictionary:
	return {"id": i, "active": false, "device": "", "joy": -1, "guid": "", "missing": false,
		"held": {}, "pending": 0, "ping_t": -1.0, "ping_pick": -1, "pending_pick": -1,
		"char": SimC.STAFF_IDS[i], "cos": "default", "ready": false, "remote": false}

func _strip_ui_actions() -> void:
	# Joypad events must not drive Godot focus directly: unjoined controllers
	# could otherwise move the menu. The router re-injects allowed navigation.
	for a in ["ui_up", "ui_down", "ui_left", "ui_right", "ui_accept", "ui_cancel", "ui_select",
			"ui_focus_next", "ui_focus_prev", "ui_page_up", "ui_page_down", "ui_home", "ui_end"]:
		if InputMap.has_action(a):
			InputMap.action_erase_events(a)

# ------------------------------------------------------------ bindings

func bindings_for(seat: int) -> Dictionary:
	var s: Dictionary = seats[seat]
	var key := "bind_pad_%d" % seat
	var defaults: Dictionary = DEFAULT_PAD
	if s["device"] == "kb1":
		key = "bind_kb1"; defaults = DEFAULT_KB1
	elif s["device"] == "kb2":
		key = "bind_kb2"; defaults = DEFAULT_KB2
	var stored = Settings.g(key)
	if stored is Dictionary and not stored.is_empty():
		var out := defaults.duplicate(true)
		for a in stored:
			out[a] = stored[a]
		return out
	# A copy: callers (rebind capture) edit the result before saving it.
	return defaults.duplicate(true)

func _kb_slot_for(code: int, loc: int) -> String:
	var b1 = Settings.g("bind_kb1")
	var kb1: Dictionary = b1 if b1 is Dictionary and not b1.is_empty() else DEFAULT_KB1
	var b2 = Settings.g("bind_kb2")
	var kb2: Dictionary = b2 if b2 is Dictionary and not b2.is_empty() else DEFAULT_KB2
	if _kb_action(kb1, code, loc) != "":
		return "kb1"
	if _kb_action(kb2, code, loc) != "":
		return "kb2"
	return ""

static func _kb_action(binds: Dictionary, code: int, loc: int) -> String:
	for a in binds:
		for b in binds[a]:
			if int(b.get("k", -1)) == code and (int(b.get("loc", 0)) == 0 or int(b.get("loc", 0)) == loc):
				return a
	return ""

static func _pad_action(binds: Dictionary, button: int) -> String:
	for a in binds:
		for b in binds[a]:
			if int(b.get("b", -1)) == button:
				return a
	return ""

func seat_of_device(dev: String, joy := -1) -> int:
	for s in seats:
		if not s["active"]:
			continue
		if dev == "pad" and s["device"] == "pad" and s["joy"] == joy:
			return s["id"]
		if dev != "pad" and s["device"] == dev:
			return s["id"]
	return -1

func active_seats() -> Array:
	var out: Array = []
	for s in seats:
		if s["active"]:
			out.append(s["id"])
	return out

func local_seat_count() -> int:
	return active_seats().size()

# ------------------------------------------------------------ join / leave

func join(dev: String, joy := -1) -> int:
	if seat_of_device(dev, joy) != -1:
		return seat_of_device(dev, joy)
	for s in seats:
		if not s["active"]:
			s["active"] = true
			s["device"] = dev
			s["joy"] = joy
			s["guid"] = Input.get_joy_guid(joy) if dev == "pad" else ""
			s["missing"] = false
			s["held"] = {}
			s["pending"] = 0
			s["ready"] = false
			menus_open_to_all = false
			seat_joined.emit(s["id"])
			return s["id"]
	return -1

func leave(seat: int) -> void:
	var s: Dictionary = seats[seat]
	if not s["active"]:
		return
	seats[seat] = _empty_seat(seat)
	seat_left.emit(seat)
	if active_seats().is_empty():
		menus_open_to_all = true

func join_last_menu_device() -> int:
	var d := last_menu_device
	if d.begins_with("pad:"):
		return join("pad", int(d.substr(4)))
	return join(d)

func reset_all() -> void:
	for i in 4:
		seats[i] = _empty_seat(i)
	menus_open_to_all = true

func reassign(seat: int, dev: String, joy := -1) -> void:
	var s: Dictionary = seats[seat]
	s["device"] = dev
	s["joy"] = joy
	s["guid"] = Input.get_joy_guid(joy) if dev == "pad" else ""
	s["missing"] = false
	s["held"] = {}
	device_restored.emit(seat)

func missing_seats() -> Array:
	var out: Array = []
	for s in seats:
		if s["active"] and s["missing"]:
			out.append(s["id"])
	return out

func _on_joy_changed(device: int, connected: bool) -> void:
	if connected:
		var guid := Input.get_joy_guid(device)
		for s in seats:
			if s["active"] and s["missing"] and s["device"] == "pad" and s["guid"] == guid:
				reassign(s["id"], "pad", device)
				return
	else:
		for s in seats:
			if s["active"] and s["device"] == "pad" and s["joy"] == device:
				s["missing"] = true
				s["held"] = {}
				device_missing.emit(s["id"])

# ------------------------------------------------------------ events

func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		var ek := event as InputEventKey
		if ek.echo:
			return
		var code := ek.physical_keycode if ek.physical_keycode != 0 else ek.keycode
		var loc := int(ek.location)
		_keys_down["%d:%d" % [code, loc]] = ek.pressed
		if not capture.is_empty() and ek.pressed:
			_capture_key(code, loc)
			get_viewport().set_input_as_handled()
			return
		var slot := _kb_slot_for(code, loc)
		if slot == "":
			return
		var seat := seat_of_device(slot)
		var binds: Dictionary = bindings_for(seat) if seat >= 0 else (DEFAULT_KB1 if slot == "kb1" else DEFAULT_KB2)
		var action := _kb_action(binds, code, loc)
		_route(slot, -1, seat, action, ek.pressed)
		any_input.emit()
	elif event is InputEventJoypadButton:
		var eb := event as InputEventJoypadButton
		if not capture.is_empty() and eb.pressed:
			_capture_pad(eb.device, eb.button_index)
			return
		var seat2 := seat_of_device("pad", eb.device)
		var binds2: Dictionary = bindings_for(seat2) if seat2 >= 0 else DEFAULT_PAD
		var action2 := _pad_action(binds2, eb.button_index)
		_pad_buttons["%d:%d" % [eb.device, eb.button_index]] = eb.pressed
		# A missing seat can be reclaimed by any unassigned controller pressing Carry.
		if seat2 == -1 and eb.pressed and action2 == "carry":
			var miss := missing_seats()
			if not miss.is_empty():
				reassign(miss[0], "pad", eb.device)
				return
		_route("pad", eb.device, seat2, action2, eb.pressed)
		any_input.emit()
	elif event is InputEventJoypadMotion:
		var em := event as InputEventJoypadMotion
		if em.axis == JOY_AXIS_LEFT_X or em.axis == JOY_AXIS_LEFT_Y:
			_stick_menu(em.device)

func _route(dev: String, joy: int, seat: int, action: String, pressed: bool) -> void:
	if action == "":
		return
	if pressed:
		last_menu_device = dev if dev != "pad" else "pad:%d" % joy
	if seat == -1:
		if pressed:
			unjoined_press.emit(dev if dev != "pad" else "pad:%d" % joy, action)
			if menus_open_to_all and not gameplay:
				_menu_action(-1, action)
		return
	var s: Dictionary = seats[seat]
	if s["missing"]:
		return
	s["held"][action] = pressed
	if action == "ping" and gameplay:
		# Tap = contextual phrase; hold ≥ 0.35 s opens the radial and the
		# release chooses the phrase under the stick.
		if pressed:
			s["ping_t"] = 0.0
		elif float(s["ping_t"]) >= 0.0:
			s["pending"] = int(s["pending"]) | SimC.BTN_PING
			s["pending_pick"] = radial_pick(_seat_vec(seat)) if float(s["ping_t"]) >= PING_HOLD_S else -1
			s["ping_t"] = -1.0
	elif pressed and BTN.has(action):
		s["pending"] = int(s["pending"]) | int(BTN[action])
	if pressed and not gameplay:
		_menu_action(seat, action)
	elif pressed and action == "pause":
		menu_pause.emit(seat)

func _menu_action(seat: int, action: String) -> void:
	match action:
		"up": _nav(seat, Vector2i(0, -1))
		"down": _nav(seat, Vector2i(0, 1))
		"left": _nav(seat, Vector2i(-1, 0))
		"right": _nav(seat, Vector2i(1, 0))
		"carry":
			menu_accept.emit(seat)
			_inject("ui_accept")
		"step":
			menu_back.emit(seat)
			_inject("ui_cancel")
		"pause":
			menu_pause.emit(seat)
		_:
			menu_alt.emit(seat, action)

func _nav(seat: int, dir: Vector2i) -> void:
	menu_nav.emit(seat, dir)
	if dir.y < 0: _inject("ui_up")
	elif dir.y > 0: _inject("ui_down")
	elif dir.x < 0: _inject("ui_left")
	elif dir.x > 0: _inject("ui_right")
	_nav_hold[seat] = {"dir": dir, "t": 0.0}

func _inject(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)
	var ev2 := InputEventAction.new()
	ev2.action = action
	ev2.pressed = false
	Input.parse_input_event(ev2)

func _stick_menu(joy: int) -> void:
	if gameplay:
		return
	var seat := seat_of_device("pad", joy)
	if seat == -1 and not menus_open_to_all:
		return
	var dz := 0.5
	var x := Input.get_joy_axis(joy, JOY_AXIS_LEFT_X)
	var y := Input.get_joy_axis(joy, JOY_AXIS_LEFT_Y)
	var dir := Vector2i.ZERO
	if absf(x) > absf(y) and absf(x) > dz:
		dir = Vector2i(1 if x > 0 else -1, 0)
	elif absf(y) > dz:
		dir = Vector2i(0, 1 if y > 0 else -1)
	var key := "pad:%d" % joy
	if dir != _stick_nav.get(key, Vector2i.ZERO):
		_stick_nav[key] = dir
		if dir != Vector2i.ZERO:
			_nav(seat, dir)
		else:
			_nav_hold.erase(seat)

func _process(dt: float) -> void:
	# Menu auto-repeat for held directions.
	if not gameplay:
		for seat in _nav_hold.keys():
			var h: Dictionary = _nav_hold[seat]
			var held := false
			if seat >= 0:
				var s: Dictionary = seats[seat]
				var d: Vector2i = h["dir"]
				var a := "up" if d.y < 0 else ("down" if d.y > 0 else ("left" if d.x < 0 else "right"))
				held = s["held"].get(a, false) or (s["device"] == "pad" and _stick_nav.get("pad:%d" % s["joy"], Vector2i.ZERO) == d)
			if not held:
				_nav_hold.erase(seat)
				continue
			h["t"] += dt
			if h["t"] > 0.38:
				h["t"] = 0.26
				var dd: Vector2i = h["dir"]
				menu_nav.emit(seat, dd)
				if dd.y < 0: _inject("ui_up")
				elif dd.y > 0: _inject("ui_down")
				elif dd.x < 0: _inject("ui_left")
				else: _inject("ui_right")
	for s in seats:
		if s["active"] and float(s["ping_t"]) >= 0.0:
			s["ping_t"] = float(s["ping_t"]) + dt

# ------------------------------------------------------------ frames

## One frame per active local seat; consumes pending press edges.
func build_frames(seat_map: Dictionary = {}) -> Array:
	var out: Array = []
	for s in seats:
		if not s["active"]:
			continue
		var f := frame_for(s["id"])
		if seat_map.has(s["id"]):
			f["seat"] = seat_map[s["id"]]
		out.append(f)
	return out

func frame_for(seat: int) -> Dictionary:
	var s: Dictionary = seats[seat]
	var ax := 0.0
	var az := 0.0
	var held: Dictionary = s["held"]
	if held.get("left", false): ax -= 1.0
	if held.get("right", false): ax += 1.0
	if held.get("up", false): az -= 1.0
	if held.get("down", false): az += 1.0
	var st := Settings.seat(seat)
	if s["device"] == "pad" and not s["missing"]:
		var v := Vector2(Input.get_joy_axis(s["joy"], JOY_AXIS_LEFT_X), Input.get_joy_axis(s["joy"], JOY_AXIS_LEFT_Y))
		var dz: float = float(st.get("deadzone", 0.2))
		var m := v.length()
		if m > dz:
			var k := clampf((m - dz) / (1.0 - dz), 0.0, 1.0) * float(st.get("sensitivity", 1.0))
			v = v / m * minf(1.0, k)
			ax += v.x
			az += v.y
	var vec := Vector2(ax, az)
	if vec.length() > 1.0:
		vec = vec.normalized()
	var hb := 0
	for a in BTN:
		if held.get(a, false):
			hb |= int(BTN[a])
	var pressed: int = s["pending"]
	s["pending"] = 0
	var pick: int = s["pending_pick"]
	s["pending_pick"] = -1
	if held.get("ping", false) and float(s["ping_t"]) >= PING_HOLD_S:
		vec = Vector2.ZERO   # radial open: stick selects a phrase instead of walking
		hb |= SimC.BTN_PING_HOLD
	return {"seat": seat, "ax": int(round(vec.x * 127.0)), "az": int(round(vec.y * 127.0)),
		"held": hb, "pressed": pressed, "pick": pick}

func _seat_vec(seat: int) -> Vector2:
	var s: Dictionary = seats[seat]
	var v := Vector2.ZERO
	if s["held"].get("left", false): v.x -= 1
	if s["held"].get("right", false): v.x += 1
	if s["held"].get("up", false): v.y -= 1
	if s["held"].get("down", false): v.y += 1
	if s["device"] == "pad":
		v += Vector2(Input.get_joy_axis(s["joy"], JOY_AXIS_LEFT_X), Input.get_joy_axis(s["joy"], JOY_AXIS_LEFT_Y))
	return v

static func radial_pick(v: Vector2) -> int:
	if v.length() < 0.4:
		return 0
	if absf(v.x) > absf(v.y):
		return 3 if v.x > 0 else 1
	return 2 if v.y > 0 else 0

func ping_radial_open(seat: int) -> bool:
	var s: Dictionary = seats[seat]
	return s["active"] and s["held"].get("ping", false) and float(s["ping_t"]) >= PING_HOLD_S

func clear_edges() -> void:
	for s in seats:
		s["pending"] = 0

func rumble(seat: int, weak: float, strong: float, dur: float) -> void:
	var s: Dictionary = seats[seat]
	if not s["active"] or s["device"] != "pad":
		return
	var k: float = float(Settings.seat(seat).get("vibration", 0.6))
	if k <= 0.01:
		return
	Input.start_joy_vibration(s["joy"], weak * k, strong * k, dur)

# ------------------------------------------------------------ rebinding

func begin_capture(seat: int, action: String) -> void:
	capture = {"seat": seat, "action": action}

func _capture_key(code: int, loc: int) -> void:
	var seat: int = capture["seat"]
	var s: Dictionary = seats[seat]
	if s["device"] == "pad":
		return
	var action: String = capture["action"]
	var key = "bind_" + s["device"]
	var binds := bindings_for(seat)
	binds[action] = [_k(code, loc if code in [KEY_SHIFT, KEY_CTRL, KEY_ALT] else 0)]
	Settings.set_value(key, binds)
	rebind_captured.emit(seat, action, binds[action][0])
	capture = {}

func _capture_pad(joy: int, button: int) -> void:
	var seat: int = capture["seat"]
	var s: Dictionary = seats[seat]
	if s["device"] != "pad" or s["joy"] != joy:
		return
	var action: String = capture["action"]
	var binds := bindings_for(seat)
	binds[action] = [{"b": button}]
	Settings.set_value("bind_pad_%d" % seat, binds)
	rebind_captured.emit(seat, action, binds[action][0])
	capture = {}

func reset_bindings(seat: int) -> void:
	var s: Dictionary = seats[seat]
	var key = "bind_" + s["device"] if s["device"] != "pad" else "bind_pad_%d" % seat
	Settings.set_value(key, {})

# ------------------------------------------------------------ glyphs

func pad_family(seat: int) -> String:
	var s: Dictionary = seats[seat]
	if s["device"] != "pad":
		return "keyboard"
	var n := Input.get_joy_name(s["joy"]).to_lower()
	if "ps" in n or "dualsense" in n or "dualshock" in n or "sony" in n or "playstation" in n:
		return "playstation"
	if "nintendo" in n or "pro controller" in n or "joy-con" in n or "switch" in n:
		return "nintendo"
	if "steam" in n or "deck" in n:
		return "steamdeck"
	return "xbox"

## Short label for an action on this seat's device ("A", "E", "Space", "✕").
func glyph(seat: int, action: String) -> Dictionary:
	if seat < 0 or not seats[seat]["active"]:
		return {"text": action.substr(0, 1).to_upper(), "shape": "key"}
	var s: Dictionary = seats[seat]
	var binds := bindings_for(seat)
	var arr: Array = binds.get(action, [])
	if arr.is_empty():
		return {"text": "?", "shape": "key"}
	var b: Dictionary = arr[0]
	if s["device"] != "pad":
		var code := int(b.get("k", 0))
		var name := OS.get_keycode_string(DisplayServer.keyboard_get_keycode_from_physical(code) if code < KEY_SPECIAL else code)
		if code == KEY_SHIFT: name = "LShift" if int(b.get("loc", 0)) == KEY_LOCATION_LEFT else "RShift"
		if code == KEY_CTRL: name = "RCtrl" if int(b.get("loc", 0)) == KEY_LOCATION_RIGHT else "Ctrl"
		if code == KEY_SPACE: name = "Space"
		var short := {KEY_BACKSLASH: "\\", KEY_SLASH: "/", KEY_PERIOD: ".", KEY_COMMA: ",", KEY_TAB: "Tab",
			KEY_UP: "↑", KEY_DOWN: "↓", KEY_LEFT: "←", KEY_RIGHT: "→", KEY_SEMICOLON: ";", KEY_APOSTROPHE: "'"}
		if short.has(code): name = short[code]
		if code == KEY_ESCAPE: name = "Esc"
		if code == KEY_ENTER: name = "Enter"
		return {"text": name, "shape": "key"}
	var btn := int(b.get("b", 0))
	var fam := pad_family(seat)
	var xbox := {JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
		JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB", JOY_BUTTON_START: "≡", JOY_BUTTON_BACK: "⧉",
		JOY_BUTTON_DPAD_UP: "↑", JOY_BUTTON_DPAD_DOWN: "↓", JOY_BUTTON_DPAD_LEFT: "←", JOY_BUTTON_DPAD_RIGHT: "→"}
	var ps := {JOY_BUTTON_A: "✕", JOY_BUTTON_B: "○", JOY_BUTTON_X: "□", JOY_BUTTON_Y: "△",
		JOY_BUTTON_LEFT_SHOULDER: "L1", JOY_BUTTON_RIGHT_SHOULDER: "R1", JOY_BUTTON_START: "Opt"}
	var nin := {JOY_BUTTON_A: "B", JOY_BUTTON_B: "A", JOY_BUTTON_X: "Y", JOY_BUTTON_Y: "X",
		JOY_BUTTON_LEFT_SHOULDER: "L", JOY_BUTTON_RIGHT_SHOULDER: "R", JOY_BUTTON_START: "+"}
	var table: Dictionary = xbox
	if fam == "playstation": table = ps
	elif fam == "nintendo": table = nin
	var txt: String = table.get(btn, xbox.get(btn, "B%d" % btn))
	var shape := "round"
	if btn in [JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER, JOY_BUTTON_START, JOY_BUTTON_BACK]:
		shape = "pill"
	var face_col := {JOY_BUTTON_A: Color("#7BC67E"), JOY_BUTTON_B: Color("#E8796F"), JOY_BUTTON_X: Color("#79A7E3"), JOY_BUTTON_Y: Color("#E8C462")}
	return {"text": txt, "shape": shape, "color": face_col.get(btn, Color("#C9CDD2")) if fam == "xbox" or fam == "steamdeck" else Color("#C9CDD2")}
