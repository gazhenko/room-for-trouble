class_name TitleScreen
extends Screen
## Title: ROOM FOR TROUBLE luggage-label logo over the living hotel backdrop.
## Any device may continue; the first press opens the main menu.

var _t := 0.0
var _armed := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	InputRouter.menu_accept.connect(_go)
	InputRouter.menu_pause.connect(_go)
	get_tree().create_timer(0.4).timeout.connect(func(): _armed = true)

func _exit_tree() -> void:
	super._exit_tree()
	if InputRouter.menu_accept.is_connected(_go):
		InputRouter.menu_accept.disconnect(_go)
	if InputRouter.menu_pause.is_connected(_go):
		InputRouter.menu_pause.disconnect(_go)

func _go(_seat := -1) -> void:
	if not _armed:
		return
	_armed = false
	Audio.sfx("bell_ring")
	Session.show_main_menu()

func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed:
		_go()

func _process(dt: float) -> void:
	_t += dt
	queue_redraw()

func _draw() -> void:
	var c := Vector2(size.x * 0.5, size.y * 0.36)
	var f := UiKit.font()
	# Luggage-label logo.
	var w := 620.0
	var h := 170.0
	var tilt := 0.0 if Settings.g("reduced_motion") else sin(_t * 0.8) * 0.012
	draw_set_transform(c, tilt, Vector2.ONE)
	var r := Rect2(Vector2(-w * 0.5, -h * 0.5), Vector2(w, h))
	draw_rect(Rect2(r.position + Vector2(6, 10), r.size), UiKit.SHADOW)
	draw_style_box(UiKit._box(UiKit.PAPER, UiKit.WALNUT, 5, 18, 0), r)
	draw_style_box(UiKit._box(Color(0, 0, 0, 0), UiKit.CORAL, 3, 12, 0), r.grow(-12))
	draw_circle(Vector2(-w * 0.5 + 34, 0), 13, UiKit.WALNUT)
	draw_circle(Vector2(-w * 0.5 + 34, 0), 8, UiKit.CREAM)
	var title := Loc.t("ui.title.name")
	var tw := f.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 64).x
	draw_string_outline(f, Vector2(-tw * 0.5 + 16, 18), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 64, 10, UiKit.CREAM)
	draw_string(f, Vector2(-tw * 0.5 + 16, 18), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 64, UiKit.INK)
	var sub := Loc.t("ui.title.tagline")
	var sw := f.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
	draw_string(f, Vector2(-sw * 0.5 + 16, 62), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, UiKit.CORAL.darkened(0.35))
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	var blink := 1.0 if Settings.g("reduced_motion") else (0.55 + 0.45 * absf(sin(_t * 2.0)))
	var press := Loc.t("ui.title.press")
	var pw := f.get_string_size(press, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
	var pr := Rect2(Vector2(size.x * 0.5 - pw * 0.5 - 24, size.y * 0.72 - 24), Vector2(pw + 48, 44))
	draw_style_box(UiKit._box(Color(UiKit.PAPER, blink), UiKit.WALNUT, 3, 12, 0), pr)
	draw_string(f, Vector2(size.x * 0.5 - pw * 0.5, size.y * 0.72 + 8), press, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, UiKit.INK)
	var ver := "v%s" % ProjectSettings.get_setting("application/config/version")
	draw_string(f, Vector2(16, size.y - 14), ver, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UiKit.CREAM)
