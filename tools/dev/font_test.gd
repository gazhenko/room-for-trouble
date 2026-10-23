extends Node2D
func _ready() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("res://build/shots/font_test.png"))
	get_tree().quit()
func _draw() -> void:
	draw_rect(Rect2(0, 0, 1280, 720), Color("#F7EAD6"))
	var base: FontFile = load("res://assets/export/fonts/PixelifySans.ttf")
	var y := 30.0
	for aa in [0, 1]:
		var f: FontFile = base.duplicate()
		f.antialiasing = TextServer.FONT_ANTIALIASING_NONE if aa == 0 else TextServer.FONT_ANTIALIASING_GRAY
		f.hinting = TextServer.HINTING_NONE
		f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
		for sz in [13, 14, 15, 16, 18, 20, 22, 24, 26, 32]:
			draw_string(f, Vector2(20 + aa * 640, y + sz), "%d aa%d 0123456789 3/3 8/8 Room for Trouble" % [sz, aa], HORIZONTAL_ALIGNMENT_LEFT, -1, sz, Color("#2B3A42"))
			y += sz + 8
		y = 30.0
