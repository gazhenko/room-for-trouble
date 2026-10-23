extends SceneTree
## Dev: re-run a recorded shift and report the first divergent checkpoint.
##   godot --headless --path . --script res://tools/dev/replay.gd -- [path]
## Default path is the last local shift (user://replays/last_shift.json).
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var path := args[0] if args.size() > 0 else "user://replays/last_shift.json"
	var reg = load("res://src/content/content_registry.gd").new()
	reg.load_all()
	var rec = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not rec is Dictionary:
		printerr("cannot read replay ", path)
		reg.free()
		quit(2)
		return
	var res := SimReplay.verify(reg, rec)
	print("replay %s: %s  checkpoints=%d  first_divergence_tick=%d  content_match=%s" % [path,
		"MATCH" if res["ok"] else "DIVERGED", res["checkpoints"], res["first_divergence_tick"], res["content_match"]])
	reg.free()
	quit(0 if res["ok"] else 1)
