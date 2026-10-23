class_name Screen
extends Control
## Base for full-screen menus: controller-first focus, back handling via the
## InputRouter, a consistent paper-card layout and helpers for option rows.

signal back_requested

var root_box: VBoxContainer
var _first_focus: Control
var _back_cb: Callable

func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UiKit.theme()

func _enter_tree() -> void:
	if not InputRouter.menu_back.is_connected(_on_back):
		InputRouter.menu_back.connect(_on_back)

func _exit_tree() -> void:
	if InputRouter.menu_back.is_connected(_on_back):
		InputRouter.menu_back.disconnect(_on_back)

func _on_back(_seat: int) -> void:
	if not is_visible_in_tree() or not _is_top():
		return
	if _back_cb.is_valid():
		Audio.ui("ui_back")
		_back_cb.call()

func _is_top() -> bool:
	var p := get_parent()
	if p == null:
		return true
	for i in range(p.get_child_count() - 1, -1, -1):
		var c := p.get_child(i)
		if c is Screen and (c as Control).visible:
			return c == self
	return true

func on_back(cb: Callable) -> void:
	_back_cb = cb

## A centred paper card with a title and a vertical list container.
func card(title_text: String, width := 560.0, icon_name := "") -> VBoxContainer:
	var dim := ColorRect.new()
	dim.color = Color(0.13, 0.16, 0.2, 0.35)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var p := UiKit.panel("cream")
	p.custom_minimum_size = Vector2(width, 0)
	var v := UiKit.vbox(12)
	p.add_child(v)
	if title_text != "":
		var h := UiKit.hbox(12)
		h.alignment = BoxContainer.ALIGNMENT_CENTER
		if icon_name != "":
			h.add_child(UiKit.icon(icon_name, 40))
		h.add_child(UiKit.title(title_text, 34))
		v.add_child(h)
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cc.add_child(p)
	add_child(cc)
	fit_to_screen(p)
	root_box = v
	return v

## Shrinks a centred panel uniformly (never enlarges) so it fits on screen at
## any UI scale (§11.3: 125–175%); text stays as large as the screen allows.
var _fit_targets: Array = []

func fit_to_screen(panel: Control) -> void:
	_fit_targets.append(panel)
	panel.resized.connect(_refit)
	if not resized.is_connected(_refit):
		resized.connect(_refit)
	_refit.call_deferred()

func _refit() -> void:
	_fit_targets = _fit_targets.filter(func(x): return is_instance_valid(x))
	var avail := size - Vector2(24, 24)
	for p in _fit_targets:
		var need: Vector2 = (p as Control).size
		# Containers reset their children's scale, so scale the full-screen
		# CenterContainer holding the panel, about the screen centre.
		var holder := (p as Control).get_parent() as Control
		if holder == null or holder is Container and holder.get_parent() is Container:
			continue
		if need.x <= 0.0 or need.y <= 0.0 or avail.x <= 0.0:
			continue
		var f := minf(1.0, minf(avail.x / need.x, avail.y / need.y))
		# An oversized panel grows its container past the screen from the
		# top-left, so centre the scaled container explicitly.
		holder.pivot_offset = Vector2.ZERO
		holder.scale = Vector2(f, f)
		holder.position = ((size - holder.size * f) * 0.5).floor()

func add_button(box: Container, text: String, icon_name: String, cb: Callable, disabled := false, width := 0) -> Button:
	var b := UiKit.button(text, icon_name, width if width > 0 else 360)
	b.disabled = disabled
	b.pressed.connect(cb)
	box.add_child(b)
	if _first_focus == null and not disabled:
		_first_focus = b
	return b

## Position of the focused control among this screen's focusable controls, so
## a screen that redraws itself can keep the controller's place.
func focus_index() -> int:
	var fo := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	if fo == null or not is_ancestor_of(fo):
		return -1
	return _focusables(self, []).find(fo)

func restore_focus_index(idx: int) -> void:
	var list := _focusables(self, [])
	if idx >= 0 and not list.is_empty():
		(list[mini(idx, list.size() - 1)] as Control).call_deferred("grab_focus")
	else:
		focus_first()

func _focusables(n: Node, out: Array) -> Array:
	for c in n.get_children():
		if c.is_queued_for_deletion():
			continue
		if c is Control and (c as Control).focus_mode == Control.FOCUS_ALL and (c as Control).visible:
			out.append(c)
		_focusables(c, out)
	return out

func focus_first() -> void:
	if _first_focus and is_instance_valid(_first_focus):
		_first_focus.call_deferred("grab_focus")

func _ready() -> void:
	focus_first()

## Option row: label + left/right cycling value (controller friendly).
func add_cycle(box: Container, label_text: String, values: Array, labels: Array, current, cb: Callable) -> Button:
	var b := UiKit.button("", "", 460)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	var idx := maxi(0, values.find(current))
	var refresh := func():
		b.text = "%s:   ◂ %s ▸" % [label_text, labels[idx]]
	refresh.call()
	b.pressed.connect(func():
		idx = (idx + 1) % values.size()
		refresh.call()
		cb.call(values[idx]))
	b.gui_input.connect(func(ev: InputEvent):
		if ev.is_action_pressed("ui_left") or ev.is_action_pressed("ui_right"):
			var d := -1 if ev.is_action_pressed("ui_left") else 1
			idx = (idx + d + values.size()) % values.size()
			refresh.call()
			cb.call(values[idx])
			Audio.ui("ui_move")
			b.accept_event())
	box.add_child(b)
	if _first_focus == null:
		_first_focus = b
	return b

func add_slider(box: Container, label_text: String, value: float, cb: Callable, step := 0.1) -> Button:
	var vals: Array = []
	var labels: Array = []
	var n := int(round(1.0 / step))
	for i in n + 1:
		vals.append(snappedf(i * step, 0.001))
		labels.append("%d%%" % int(round(i * step * 100)))
	var cur := snappedf(value, step)
	return add_cycle(box, label_text, vals, labels, cur, cb)

func add_toggle(box: Container, label_text: String, value: bool, cb: Callable) -> Button:
	return add_cycle(box, label_text, [false, true], [Loc.t("ui.off"), Loc.t("ui.on")], value, cb)
