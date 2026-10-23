extends Node
## Boot: dedicated server, headless tools, or the client with its persistent
## layers (3D pixel stage, scaled UI root, captions and fade overlay).

var stage: PixelStage
var ui_root: Control
var captions: Captions
var fade: ColorRect
var toast_layer: Control

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if "--server" in args or OS.has_feature("dedicated_server"):
		Net.start_server_from_args(args)
		return
	if "--probe" in args or "--healthcheck" in args:
		Net.run_probe(args)
		return
	get_window().title = "Room for Trouble"
	get_window().min_size = Vector2i(960, 540)
	var l0 := CanvasLayer.new()
	l0.layer = 0
	add_child(l0)
	stage = PixelStage.new()
	l0.add_child(stage)
	var l1 := CanvasLayer.new()
	l1.layer = 1
	add_child(l1)
	ui_root = Control.new()
	ui_root.name = "UiRoot"
	ui_root.theme = UiKit.theme()
	ui_root.mouse_filter = Control.MOUSE_FILTER_PASS
	l1.add_child(ui_root)
	var l2 := CanvasLayer.new()
	l2.layer = 5
	add_child(l2)
	captions = Captions.new()
	l2.add_child(captions)
	toast_layer = Control.new()
	toast_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	toast_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l2.add_child(toast_layer)
	fade = ColorRect.new()
	fade.color = Color(0.2, 0.26, 0.29, 0.0)
	fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l2.add_child(fade)
	get_viewport().size_changed.connect(_layout_ui)
	Settings.changed.connect(func(_k): _layout_ui())
	_layout_ui()
	Session.boot(self)

func _layout_ui() -> void:
	var sc := Settings.effective_ui_scale()
	var vs := get_viewport().get_visible_rect().size
	ui_root.scale = Vector2(sc, sc)
	ui_root.position = Vector2.ZERO
	ui_root.size = vs / sc
	captions.scale = Vector2(sc, sc)
	captions.size = vs / sc
	toast_layer.scale = Vector2(sc, sc)
	toast_layer.size = vs / sc

func fade_to(a: float, secs := 0.25) -> void:
	if Settings.g("reduced_motion"):
		secs = 0.08
	var tw := create_tween()
	tw.tween_property(fade, "color:a", a, secs)
	await tw.finished
