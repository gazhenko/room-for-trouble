extends SceneTree
## Headless test entry point:
##   godot --headless --path . --script res://tests/run_all.gd [-- --only=name]

const SUITES := [
	"res://tests/test_sim_core.gd",
	"res://tests/test_content.gd",
	"res://tests/test_env.gd",
	"res://tests/test_items.gd",
	"res://tests/test_score.gd",
	"res://tests/test_campaign_bot.gd",
	"res://tests/test_save.gd",
	"res://tests/test_net.gd",
]

func _initialize() -> void:
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.substr(7)
	var reg = load("res://src/content/content_registry.gd").new()
	reg.load_all()
	var total_fail := 0
	var total_checks := 0
	var t0 := Time.get_ticks_msec()
	var suites: Array = []
	for f in DirAccess.get_files_at("res://tests"):
		if f.begins_with("test_") and f.ends_with(".gd") and f != "test_base.gd":
			suites.append("res://tests/" + f)
	suites.sort()
	# The long reference-run suite goes last.
	suites.erase("res://tests/test_campaign_bot.gd")
	suites.append("res://tests/test_campaign_bot.gd")
	for path in suites:
		if not ResourceLoader.exists(path):
			continue
		var script: GDScript = load(path)
		var suite = script.new()
		suite.content = reg
		for m in suite.get_method_list():
			var name: String = m["name"]
			if not name.begins_with("test_"):
				continue
			if only != "" and not (only in name or only in path):
				continue
			suite.current = name
			var before: int = suite.failures.size()
			var ts := Time.get_ticks_msec()
			suite.call(name)
			var ok: bool = suite.failures.size() == before
			print("%s %s :: %s (%d ms)" % ["PASS" if ok else "FAIL", path.get_file(), name, Time.get_ticks_msec() - ts])
		for f in suite.failures:
			print("   ✗ ", f)
		total_fail += suite.failures.size()
		total_checks += suite.checks
	print("== %d checks, %d failures, %.1f s ==" % [total_checks, total_fail, (Time.get_ticks_msec() - t0) / 1000.0])
	reg.free()
	quit(1 if total_fail > 0 else 0)
