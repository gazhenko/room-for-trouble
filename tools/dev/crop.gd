extends SceneTree
## Dev: crops a region of a screenshot and enlarges it with nearest-neighbour
## sampling, for judging pixel-scale readability.
## godot --headless --path . --script res://tools/dev/crop.gd -- in.png x y w h scale out.png
func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() < 7:
		push_error("usage: in.png x y w h scale out.png")
		quit(1)
		return
	var root := ProjectSettings.globalize_path("res://")
	var img := Image.load_from_file(root.path_join(a[0]))
	var r := Rect2i(int(a[1]), int(a[2]), int(a[3]), int(a[4]))
	var sub := img.get_region(r)
	var k := int(a[5])
	sub.resize(r.size.x * k, r.size.y * k, Image.INTERPOLATE_NEAREST)
	sub.save_png(root.path_join(a[6]))
	print("wrote %s (%dx%d)" % [a[6], sub.get_width(), sub.get_height()])
	quit()
