extends SceneTree
## Dev: tile PNG screenshots into one contact sheet for review.
##   godot --headless --path . --script res://tools/dev/contact_sheet.gd -- <dir> <out.png> [cols] [scale]
func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var dir: String = a[0]
	var out: String = a[1]
	var cols := int(a[2]) if a.size() > 2 else 4
	var sc := float(a[3]) if a.size() > 3 else 0.33
	var files: Array = []
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".png"):
			files.append(f)
	files.sort()
	var imgs: Array = []
	for f in files:
		var im := Image.load_from_file(dir.path_join(f))
		im.resize(int(im.get_width() * sc), int(im.get_height() * sc), Image.INTERPOLATE_BILINEAR)
		imgs.append(im)
	if imgs.is_empty():
		quit(1)
		return
	var w: int = imgs[0].get_width()
	var h: int = imgs[0].get_height()
	var rows := int(ceil(imgs.size() / float(cols)))
	var sheet := Image.create(w * cols, h * rows, false, Image.FORMAT_RGB8)
	for i in imgs.size():
		var im: Image = imgs[i]
		im.convert(Image.FORMAT_RGB8)
		sheet.blit_rect(im, Rect2i(0, 0, w, h), Vector2i((i % cols) * w, (i / cols) * h))
	sheet.save_png(out)
	print("sheet ", files.size(), " → ", out)
	quit()
