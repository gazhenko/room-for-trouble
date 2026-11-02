extends Node
## Renders Steam library artwork for the non-Steam shortcut from the real title
## screen: the hotel backdrop at each Steam size, with the luggage-label logo.
##   godot --path . res://tools/deck/steam_art.tscn [-- --out=build/steam_art]
## Writes capsule.png (600×900), wide.png (920×430), hero.png (1920×620, no
## logo: Steam draws logo.png over it) and logo.png (transparent), plus icon.png.

const SIZES := {"capsule": Vector2i(600, 900), "wide": Vector2i(920, 430), "hero": Vector2i(1920, 620)}
# The lockup drawn at the centre of a 1280×720 canvas: the label, its drop
# shadow, the eyelet string on the left and the pennants below.
const LOGO_RECT := Rect2i(640 - int(LogoLockup.W * 0.5) - 44, 360 - int(LogoLockup.H * 0.5) - 8,
	int(LogoLockup.W) + 64, int(LogoLockup.H) + 40)
var out := "build/steam_art"

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.substr(6)
	var dir := ProjectSettings.globalize_path("res://").path_join(out)
	DirAccess.make_dir_recursive_absolute(dir)
	Settings.data["reduced_motion"] = true
	var main: Node = load("res://src/app/main.tscn").instantiate()
	add_child(main)
	get_window().min_size = Vector2i.ZERO
	await _wait(1.5)
	var logo := await _logo()
	logo.save_png(dir.path_join("logo.png"))
	Session.screen.visible = false
	for key in SIZES:
		var sz: Vector2i = SIZES[key]
		DisplayServer.window_set_size(sz)
		await _wait(0.8)
		var img := get_viewport().get_texture().get_image()
		if img.get_size() != sz:
			img.resize(sz.x, sz.y, Image.INTERPOLATE_BILINEAR)
		img.convert(Image.FORMAT_RGBA8)
		if key != "hero":
			var lw := int(sz.x * (0.92 if key == "capsule" else 0.7))
			var l := logo.duplicate() as Image
			l.resize(lw, int(lw * float(logo.get_height()) / logo.get_width()), Image.INTERPOLATE_LANCZOS)
			var y := int(sz.y * (0.14 if key == "capsule" else 0.5)) - (0 if key == "capsule" else l.get_height() / 2)
			img.blend_rect(l, Rect2i(Vector2i.ZERO, l.get_size()), Vector2i((sz.x - l.get_width()) / 2, y))
		img.save_png(dir.path_join(key + ".png"))
	var icon := Image.load_from_file(ProjectSettings.globalize_path("res://assets/export/icons/app_icon.png"))
	icon.save_png(dir.path_join("icon.png"))
	print("steam art: ", dir)
	get_tree().quit(0)

## The title's lockup, drawn at 2× into a transparent viewport and cropped.
func _logo() -> Image:
	var vp := SubViewport.new()
	vp.transparent_bg = true
	vp.size = Vector2i(2560, 1440)
	vp.size_2d_override = Vector2i(1280, 720)
	vp.size_2d_override_stretch = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var c := Control.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.draw.connect(func(): LogoLockup.draw(c, Vector2(640, 360), 1.0, 0.0, true))
	vp.add_child(c)
	await _wait(0.3)
	var img := vp.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	vp.queue_free()
	return img.get_region(Rect2i(LOGO_RECT.position * 2, LOGO_RECT.size * 2))

func _wait(secs: float) -> void:
	await get_tree().create_timer(secs).timeout
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
