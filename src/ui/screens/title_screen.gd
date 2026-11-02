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
	var c := Vector2(size.x * 0.5, size.y * 0.34)
	var f := UiKit.font()
	# The lockup (LogoLockup): label, two wordmark bands, bunting, bell, edition.
	var sc := clampf(minf(size.x / 1280.0, size.y / 720.0), 0.6, 1.25)
	LogoLockup.draw(self, c, sc, _t)
	var sub := Loc.t("ui.title.tagline")
	var sw := f.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
	var sr := Rect2(Vector2(c.x - sw * 0.5 - 18, c.y + 128 * sc), Vector2(sw + 36, 40))
	draw_style_box(UiKit._box(Color(UiKit.PAPER, 0.92), UiKit.WALNUT, 2, 10, 0), sr)
	draw_string(f, Vector2(c.x - sw * 0.5, sr.position.y + 28), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, UiKit.CORAL.darkened(0.35))
	var blink := 1.0 if Settings.g("reduced_motion") else (0.55 + 0.45 * absf(sin(_t * 2.0)))
	var press := Loc.t("ui.title.press")
	var pw := f.get_string_size(press, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
	var pr := Rect2(Vector2(size.x * 0.5 - pw * 0.5 - 24, size.y * 0.72 - 24), Vector2(pw + 48, 44))
	draw_style_box(UiKit._box(Color(UiKit.PAPER, blink), UiKit.WALNUT, 3, 12, 0), pr)
	draw_string(f, Vector2(size.x * 0.5 - pw * 0.5, size.y * 0.72 + 8), press, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, UiKit.INK)
	var ver := "v%s" % ProjectSettings.get_setting("application/config/version")
	draw_string(f, Vector2(16, size.y - 14), ver, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UiKit.CREAM)
