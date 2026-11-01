extends SceneTree
## Dev: loads the given scripts one by one so the parser reports the real error
## line instead of "could not resolve class X because of a parser error".
##   godot --headless --path . --script res://tools/dev/parse_check.gd -- res://src/sim/sim_score.gd [...]
func _initialize() -> void:
	for p in OS.get_cmdline_user_args():
		if not p.begins_with("res://"):
			continue
		var sc = load(p)
		print("%s -> %s" % [p, "ok" if sc != null and (sc as GDScript).can_instantiate() else "FAILED (see errors above)"])
	quit()
