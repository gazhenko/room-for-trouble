extends SceneTree
## Dev: tile PNG screenshots into one contact sheet for review.
##   godot --headless --path . --script res://tools/dev/contact_sheet.gd -- <dir> <out.png> [cols] [scale]
## Pair mode (A beside B for every file in A whose name starts with one of the
## comma-separated --match prefixes):
##   ... -- --a=<dirA> --b=<dirB> --match=pre_L0,pre_L1 --out=<out.png> [--cols=2] [--scale=0.33]
## Missing B files leave a dark tile, so the row order always follows A.
func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var opts := {}
	var pos: Array = []
	for arg in a:
		if arg.begins_with("--") and "=" in arg:
			var kv: PackedStringArray = arg.substr(2).split("=", true, 1)
			opts[kv[0]] = kv[1]
		else:
			pos.append(arg)
	if opts.has("a"):
		_pairs(opts)
		return
	var dir: String = pos[0]
	var out: String = pos[1]
	var cols := int(pos[2]) if pos.size() > 2 else 4
	var sc := float(pos[3]) if pos.size() > 3 else 0.33
	var files: Array = []
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".png"):
			files.append(f)
	files.sort()
	var imgs: Array = []
	for f in files:
		imgs.append(_load(dir.path_join(f), sc))
	if imgs.is_empty():
		quit(1)
		return
	_sheet(imgs, cols, out)
	print("sheet ", files.size(), " → ", out)
	quit()

func _pairs(opts: Dictionary) -> void:
	var da: String = opts["a"]
	var db: String = opts.get("b", "")
	var match_prefix: String = opts.get("match", "")
	var out: String = opts.get("out", "sheet.png")
	var cols := int(opts.get("cols", "2")) * (2 if db != "" else 1)   # no --b: a plain filtered grid
	var sc := float(opts.get("scale", "0.33"))
	var prefixes: PackedStringArray = match_prefix.split(",", false)
	var files: Array = []
	for f in DirAccess.get_files_at(da):
		if not f.ends_with(".png"):
			continue
		var hit := prefixes.is_empty()
		for pre in prefixes:
			if f.begins_with(pre):
				hit = true
		if hit:
			files.append(f)
	files.sort()
	if files.is_empty():
		print("no files in ", da, " matching ", match_prefix)
		quit(1)
		return
	var imgs: Array = []
	var names: Array = []
	for f in files:
		var ia := _load(da.path_join(f), sc)
		imgs.append(ia)
		if db != "":
			var pb := db.path_join(f)
			if FileAccess.file_exists(pb):
				imgs.append(_load(pb, sc))
			else:
				var blank := Image.create(ia.get_width(), ia.get_height(), false, Image.FORMAT_RGB8)
				blank.fill(Color(0.15, 0.15, 0.15))
				imgs.append(blank)
		names.append(f.get_basename())
	_sheet(imgs, cols, out)
	print("sheet %d pairs → %s" % [files.size(), out])
	print("order: ", ", ".join(names))
	quit()

func _load(path: String, sc: float) -> Image:
	var im := Image.load_from_file(path)
	im.resize(int(im.get_width() * sc), int(im.get_height() * sc), Image.INTERPOLATE_BILINEAR)
	im.convert(Image.FORMAT_RGB8)
	return im

func _sheet(imgs: Array, cols: int, out: String) -> void:
	var w: int = imgs[0].get_width()
	var h: int = imgs[0].get_height()
	var rows := int(ceil(imgs.size() / float(cols)))
	var sheet := Image.create(w * cols, h * rows, false, Image.FORMAT_RGB8)
	for i in imgs.size():
		var im: Image = imgs[i]
		sheet.blit_rect(im, Rect2i(0, 0, mini(w, im.get_width()), mini(h, im.get_height())), Vector2i((i % cols) * w, (i / cols) * h))
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	sheet.save_png(out)
