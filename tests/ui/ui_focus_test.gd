extends Node
## UI01: controller-only traversal of every menu, back navigation, and rebind.
##   godot --headless --path . res://tests/ui/ui_focus_test.tscn
## A virtual pad (device 0) joins seat 0. On each screen the test checks that
## something has focus, walks the D-pad from every reachable control, and
## fails on any visible focusable control that the D-pad can never reach, or
## on a direction that drops focus entirely. B must leave each pushed screen.

const PAD := 0
var main: Node
var failures: PackedStringArray = []
var checks := 0

func _ready() -> void:
	main = load("res://src/app/main.tscn").instantiate()
	add_child(main)
	await _frames(30)
	SaveService.load_profile("ui_focus_test")
	InputRouter.reset_all()
	InputRouter.join("pad", PAD)
	SaveService.mark_story_seen("O00")
	var screens := [
		["main_menu", func(): Session.show_main_menu(), false],
		["shift_select", func(): Session.open_shift_select(), true],
		["quick_shift", func(): Session.open_quick_shift(), true],
		["practice", func(): Session.open_practice(), true],
		["settings", func(): Session.open_settings(), true],
		["scrapbook", func(): Session.open_scrapbook(), true],
		["wardrobe", func(): Session.open_wardrobe(), true],
		["credits", func(): Session.open_credits(), true],
		["online", func(): Session.start_lobby("online"), false],
	]
	var only := OS.get_environment("UI01_ONLY")
	for sc in screens:
		if only != "" and sc[0] != only:
			continue
		Session.show_main_menu()
		await _frames(4)
		sc[1].call()
		await _frames(8)
		await _walk(sc[0])
		if sc[2]:
			var before: Control = Session.screen
			await _press(JOY_BUTTON_B)
			await _frames(4)
			_check(Session.screen != before, "%s: B (Step) leaves the screen" % sc[0])
	await _tabs("settings", func(): Session.open_settings(), "ui.settings.tab_", ["controls", "vision", "hearing", "comfort", "online"])
	await _tabs("scrapbook", func(): Session.open_scrapbook(), "ui.scrap.tab_", ["guide", "ribbons", "stories"])
	await _quick_shift_keeps_place()
	await _seat_lobby()
	await _pause_menu()
	await _rebind()
	await _keyboard()
	await _large_ui_fits()
	print("== UI01: %d checks, %d failures ==" % [checks, failures.size()])
	for f in failures:
		print("   ✗ ", f)
	get_tree().quit(1 if failures.size() > 0 else 0)

func _check(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		failures.append(msg)

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _press(button: int) -> void:
	for pressed in [true, false]:
		var ev := InputEventJoypadButton.new()
		ev.device = PAD
		ev.button_index = button
		ev.pressed = pressed
		Input.parse_input_event(ev)
		await _frames(2)

func _focusables(root: Node, out: Array) -> void:
	for c in root.get_children():
		if c.is_queued_for_deletion():
			continue
		if c is Control:
			var cc := c as Control
			if not cc.is_visible_in_tree():
				continue
			if cc.focus_mode == Control.FOCUS_ALL:
				out.append(cc)
		_focusables(c, out)

func _label(c: Control) -> String:
	# Cycle rows change their value text; key them by the part before the colon.
	# Tree position keeps identical texts (locked postcards) apart and is stable across redraws.
	var pos := "%d.%d" % [c.get_parent().get_index(), c.get_index()]
	if c is Button and (c as Button).text != "":
		return "'%s'@%s" % [(c as Button).text.get_slice(":", 0).left(30), pos]
	return "%s@%s" % [c.get_class(), pos]

func _walk(name: String) -> void:
	var vp := get_viewport()
	var start := vp.gui_get_focus_owner()
	_check(start != null, "%s: a control has focus on open" % name)
	if start == null:
		return
	# The menu root is the focused control's top-level ancestor (screens and overlays alike).
	var screen_root: Node = start
	while screen_root.get_parent() != null and screen_root.get_parent() != main.ui_root \
			and not screen_root.get_parent() is CanvasLayer and screen_root.get_parent() != get_tree().root:
		screen_root = screen_root.get_parent()
	# Walk by label: screens that redraw recreate the same control as a new node.
	var seen := {_label(start): true}
	var queue: Array = [_label(start)]
	var dirs := [JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT]
	var guard := 0
	while not queue.is_empty() and guard < 320 and is_instance_valid(screen_root):
		var lbl: String = queue.pop_front()
		for d in dirs:
			guard += 1
			var c := _find_by_label(screen_root, lbl)
			if c == null:
				break
			c.grab_focus()
			await _frames(1)
			if OS.get_environment("UI01_TRACE") == "1":
				print("  walk %s from %s dir %d" % [name, lbl, d])
			await _press(d)
			await _frames(1)
			var now := vp.gui_get_focus_owner()
			if now == null:
				_check(false, "%s: D-pad from %s drops focus" % [name, lbl])
				continue
			if not seen.has(_label(now)):
				seen[_label(now)] = true
				queue.append(_label(now))
	var all: Array = []
	if is_instance_valid(screen_root):
		_focusables(screen_root, all)
	var missed: Array = []
	for c2 in all:
		if not seen.has(_label(c2)):
			missed.append(_label(c2))
	_check(missed.is_empty(), "%s: unreachable by D-pad: %s" % [name, ", ".join(missed)])
	print("UI01 %s: %d/%d controls reachable" % [name, all.size() - missed.size(), all.size()])

func _find_by_label(root: Node, lbl: String) -> Control:
	var list: Array = []
	_focusables(root, list)
	for c in list:
		if _label(c) == lbl:
			return c
	return null

func _tabs(name: String, open: Callable, prefix: String, tabs: Array) -> void:
	for tb in tabs:
		Session.show_main_menu()
		await _frames(4)
		open.call()
		await _frames(8)
		var want := Loc.t(prefix + tb)
		var list: Array = []
		_focusables(Session.screen, list)
		var btn: Button = null
		for c in list:
			if c is Button and (c as Button).text == want:
				btn = c
		_check(btn != null, "%s: tab %s exists" % [name, tb])
		if btn == null:
			continue
		btn.grab_focus()
		await _frames(1)
		await _press(JOY_BUTTON_A)
		await _frames(6)
		await _walk("%s/%s" % [name, tb])

func _quick_shift_keeps_place() -> void:
	Session.show_main_menu()
	await _frames(4)
	Session.open_quick_shift()
	await _frames(8)
	var b := Session.screen.find_child("mod_extra_towels", true, false) as Control
	_check(b != null, "quick_shift: modifier buttons exist")
	if b == null:
		return
	b.grab_focus()
	await _frames(1)
	await _press(JOY_BUTTON_A)
	await _frames(3)
	var fo := get_viewport().gui_get_focus_owner()
	_check(fo != null and fo.name == "mod_extra_towels", "quick_shift: toggling a modifier keeps focus on it (got %s)" % (fo.name if fo else "none"))
	await _press(JOY_BUTTON_A)
	print("UI01 quick_shift: focus kept across redraw")

func _seat_lobby() -> void:
	# Seat lobby is per-device rather than focus-driven (§11.4): each pad
	# changes its own staff/outfit and readies with Carry.
	Session.show_main_menu()
	await _frames(4)
	Session.start_lobby("couch")
	await _frames(8)
	var s0: Dictionary = InputRouter.seats[0]
	var c0: String = s0["char"]
	await _press(JOY_BUTTON_DPAD_RIGHT)
	_check(s0["char"] != c0, "seat_lobby: D-pad right changes staff")
	await _press(JOY_BUTTON_A)
	_check(s0["ready"], "seat_lobby: A readies the seat")
	await _press(JOY_BUTTON_B)
	_check(not s0["ready"], "seat_lobby: B un-readies")
	var ev := InputEventJoypadButton.new()
	ev.device = 1; ev.button_index = JOY_BUTTON_A; ev.pressed = true
	Input.parse_input_event(ev)
	await _frames(2)
	ev = ev.duplicate(); ev.pressed = false
	Input.parse_input_event(ev)
	await _frames(2)
	_check(InputRouter.seat_of_device("pad", 1) >= 0, "seat_lobby: a second pad joins with A")
	InputRouter.leave(InputRouter.seat_of_device("pad", 1))
	await _press(JOY_BUTTON_B)
	await _frames(4)
	_check(Session.screen is MainMenuScreen, "seat_lobby: B with one seat returns to the main menu")
	print("UI01 seat_lobby: checked")

func _pause_menu() -> void:
	Session._run_shift(Session._base_cfg({"mode": "campaign", "level_id": "L01", "seed": 3}))
	await _frames(20)
	await _press(JOY_BUTTON_START)
	await _frames(6)
	var fo := get_viewport().gui_get_focus_owner()
	_check(fo != null, "pause: menu takes controller focus")
	if fo != null:
		await _walk("pause")
	await _press(JOY_BUTTON_B)
	await _frames(6)
	_check(InputRouter.gameplay, "pause: B resumes play")
	var sh: ShiftScreen = Session.screen as ShiftScreen
	if sh != null:
		sh.notification(NOTIFICATION_APPLICATION_FOCUS_IN)
		sh.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
		await _frames(6)
		_check(sh.paused and get_viewport().gui_get_focus_owner() != null, "pause: losing window focus pauses a local shift")
		await _press(JOY_BUTTON_B)
		await _frames(6)
		_check(not sh.paused and InputRouter.gameplay, "pause: B resumes after a focus pause")
		sh._wall -= 30.0   # as if the machine slept for 30 s
		await _frames(6)
		_check(sh.paused, "pause: waking from sleep pauses a local shift")
		await _press(JOY_BUTTON_B)
		await _frames(6)
	Session.leave_shift()
	await _frames(10)

func _rebind() -> void:
	InputRouter.begin_capture(0, "work")
	await _press(JOY_BUTTON_Y)
	await _frames(2)
	var b: Array = InputRouter.bindings_for(0).get("work", [])
	var has_y := false
	for e in b:
		if int(e.get("b", -1)) == JOY_BUTTON_Y:
			has_y = true
	_check(has_y, "rebind: Work captured on the Y button")
	InputRouter.reset_bindings(0)
	var b2: Array = InputRouter.bindings_for(0).get("work", [])
	_check(not b2.is_empty() and int(b2[0].get("b", -1)) == JOY_BUTTON_X, "rebind: reset restores X")

func _key(code: int, loc := KEY_LOCATION_UNSPECIFIED) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.physical_keycode = code
		ev.keycode = code
		ev.location = loc
		ev.pressed = pressed
		Input.parse_input_event(ev)
		await _frames(2)

func _keyboard() -> void:
	# Keyboard slot 1 alone can drive the menus: S moves, E accepts, Left Shift backs out.
	InputRouter.reset_all()
	InputRouter.join("kb1")
	Session.show_main_menu()
	await _frames(6)
	var first := get_viewport().gui_get_focus_owner()
	await _key(KEY_S)
	var second := get_viewport().gui_get_focus_owner()
	_check(first != null and second != null and first != second, "keyboard: S moves menu focus")
	var target: Button = null
	var list: Array = []
	_focusables(Session.screen, list)
	for c in list:
		if c is Button and (c as Button).text == Loc.t("ui.menu.settings"):
			target = c
	if target == null:
		_check(false, "keyboard: settings button exists")
		return
	target.grab_focus()
	await _frames(1)
	await _key(KEY_E)
	await _frames(4)
	_check(Session.screen is SettingsScreen, "keyboard: E opens Settings")
	await _key(KEY_SHIFT, KEY_LOCATION_LEFT)
	await _frames(4)
	_check(Session.screen is MainMenuScreen, "keyboard: Left Shift backs out")
	print("UI01 keyboard: checked")

func _large_ui_fits() -> void:
	# §11.3 UI scale 175%: every menu card must stay fully on screen.
	Settings.data["ui_scale"] = 1.75
	main._layout_ui()
	var vr := get_viewport().get_visible_rect().grow(1.0)
	var openers := [["main_menu", func(): Session.show_main_menu()], ["settings", func(): Session.open_settings()],
		["shift_select", func(): Session.open_shift_select()], ["scrapbook", func(): Session.open_scrapbook()],
		["wardrobe", func(): Session.open_wardrobe()], ["quick_shift", func(): Session.open_quick_shift()],
		["credits", func(): Session.open_credits()], ["practice", func(): Session.open_practice()]]
	for o in openers:
		Session.show_main_menu()
		await _frames(3)
		o[1].call()
		await _frames(8)
		var panels: Array = Session.screen.find_children("*", "PanelContainer", true, false)
		var p: Control = panels[0] if not panels.is_empty() else null
		if p == null:
			_check(false, "175%%: %s has a panel" % o[0])
			continue
		var r: Rect2 = p.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, p.size)
		_check(vr.encloses(r), "175%%: %s card fits on screen (%s in %s)" % [o[0], r, vr])
	Settings.data["ui_scale"] = 1.0
	main._layout_ui()
	print("UI01 ui_scale 175%: checked")
