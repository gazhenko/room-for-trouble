extends SceneTree
## Dev: (re)generates the save fixtures in tests/fixtures/saves/.
##   godot --headless --path . --script res://tools/dev/make_save_fixtures.gd
func _initialize() -> void:
	var reg = load("res://src/content/content_registry.gd").new()
	reg.load_all()
	var ss = load("res://src/save/save_service.gd").new()
	ss.content = reg
	ss.root_dir = "user://fixture_gen"
	DirAccess.make_dir_recursive_absolute(ss.root_dir)
	ss.load_profile("p")
	var p: Dictionary = ss.profile
	p["profile_id"] = "00000000-0000-4000-8000-000000000001"
	p["created_at"] = "2026-10-01T10:00:00Z"
	p["completed_levels"] = ["L01", "L02", "L03", "L04", "L05"]
	p["accessible_levels"] = ["L01", "L02", "L03", "L04", "L05", "L06"]
	p["earned_ribbons"] = ["L01:A Good Fit", "L03:Fresh Sheets"]
	p["postcards"] = {"L01": {"staff": ["pip", "moss"], "outfit": "default"}}
	p["unlocked_cosmetic_sets"] = ["default", "first_hello"]
	p["best_results"] = {"L01|family|2|none|none": {"percent": 92, "stars": 3}}
	p["recent_committed_result_ids"] = ["L01-1-1", "L02-1-2"]
	p["tutorial_status"] = {"T01": "done", "T02": "unseen", "T03": "unseen"}
	ss.save()
	var valid := FileAccess.get_file_as_string(ss.path_for("p"))
	_write("v1_valid.json", valid)
	_write("v1_truncated.json", valid.substr(0, valid.length() / 2))
	var tampered: Dictionary = JSON.parse_string(valid)
	tampered["completed_levels"].append("L24")
	_write("v1_tampered.json", JSON.stringify(tampered, "\t", true))
	_write("v0_prerelease.json", JSON.stringify({"schema_version": 0, "levels_done": ["L01", "L02"],
		"ribbons": ["L01:A Good Fit"], "selected_staff": "moss"}, "\t", true))
	ss.free()
	reg.free()
	print("fixtures written")
	quit()

func _write(name: String, txt: String) -> void:
	var f := FileAccess.open("res://tests/fixtures/saves/" + name, FileAccess.WRITE)
	f.store_string(txt)
	f.close()
