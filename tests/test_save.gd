extends TestBase
## SAVE01–SAVE02: corruption recovery, migration, idempotent results.

func _service(dir: String):
	var ss = load("res://src/save/save_service.gd").new()
	ss.root_dir = dir
	ss.content = content
	DirAccess.make_dir_recursive_absolute(dir)
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	return ss

func test_save01_atomic_write_and_backup_recovery() -> void:
	var dir := "user://test_saves_a"
	var ss = _service(dir)
	ss.load_profile("t")
	ss.profile["completed_levels"] = ["L01"]
	check(ss.save(), "first save")
	ss.profile["completed_levels"] = ["L01", "L02"]
	check(ss.save(), "second save (creates .bak1)")
	check(FileAccess.file_exists(ss.path_for("t", ".bak1")), "backup kept")
	# Corrupt the primary file (power cut mid-write simulation).
	var f := FileAccess.open(ss.path_for("t"), FileAccess.WRITE)
	f.store_string("{\"schema_version\": 1, \"completed_levels\": [\"L0")
	f.close()
	var ss2 = _service_keep(dir)
	ss2.load_profile("t")
	eq(ss2.recovered_from, "bak1", "recovered from the most recent valid backup")
	check("L01" in ss2.profile["completed_levels"], "durable stamps survive")
	ss2.free()
	ss.free()

func _service_keep(dir: String):
	var ss = load("res://src/save/save_service.gd").new()
	ss.root_dir = dir
	ss.content = content
	return ss

func test_save01_migration_v0_fixture() -> void:
	var ss = _service("user://test_saves_b")
	var v0 := {"schema_version": 0, "levels_done": ["L01", "L02"], "ribbons": ["L01:A Good Fit"], "selected_staff": "moss"}
	var m: Dictionary = ss.migrate(v0)
	eq(m["schema_version"], 1, "migrated to schema 1")
	eq(m["completed_levels"], ["L01", "L02"], "levels carried over")
	eq(m["earned_ribbons"], ["L01:A Good Fit"], "ribbons carried over")
	eq(m["selected_staff"], "moss", "unknown-to-v0 fields kept")
	check(m.has("postcards") and m.has("best_results"), "new fields defaulted")
	ss.free()

func test_save02_idempotent_results() -> void:
	var ss = _service("user://test_saves_c")
	ss.load_profile("t")
	var res := {"result_id": "L01-1-1", "level": "L01", "percent": 92, "stars": 3, "humans": 2, "difficulty": "family",
		"ribbons": [{"label": "A Good Fit", "earned": true}], "staff": ["pip"], "seed": 1}
	var d1: Dictionary = ss.apply_result(res)
	var d2: Dictionary = ss.apply_result(res)
	check(d1["first_completion"], "first completion granted")
	check(not d2["first_completion"], "no duplicate completion")
	check(d2["duplicate"], "duplicate result detected")
	eq(ss.profile["completed_levels"].count("L01"), 1, "stamp is a set")
	eq(ss.profile["earned_ribbons"].size(), 1, "ribbon not duplicated")
	check("L02" in ss.profile["accessible_levels"], "next shift unlocked")
	check("first_hello" in ss.profile["unlocked_cosmetic_sets"], "first cosmetic set unlocked")
	var worse := res.duplicate(true)
	worse["result_id"] = "L01-1-2"
	worse["percent"] = 40
	ss.apply_result(worse)
	var key := "L01|family|2|none|none"
	eq(ss.profile["best_results"][key]["percent"], 92, "best result keeps the max")
	ss.free()

func test_net01_protocol_rejects_bad_input() -> void:
	var good := NetProtocol.encode_client({"type": "heartbeat", "sequence": 1, "t": 5})
	check(not NetProtocol.parse_client(good).is_empty(), "valid heartbeat accepted")
	check(NetProtocol.parse_client("not json".to_utf8_buffer()).is_empty(), "garbage rejected")
	check(NetProtocol.parse_client(NetProtocol.encode_client({"type": "rm_rf", "x": 1})).is_empty(), "unknown type rejected")
	check(NetProtocol.parse_client(NetProtocol.encode_client({"type": "heartbeat", "sequence": 1, "t": 5, "evil": true})).is_empty(), "unexpected field rejected")
	check(NetProtocol.parse_client(NetProtocol.encode_client({"type": "heartbeat", "sequence": "1", "t": 5})).is_empty(), "wrong type rejected")
	var big := {"type": "join_room", "room_code": "A".repeat(3000), "local_seat_count": 1}
	check(NetProtocol.parse_client(NetProtocol.encode_client(big)).is_empty(), "oversized payload rejected")
	check(NetProtocol.clean_frame({"seat": 0, "ax": 999, "az": 0, "held": 0, "pressed": 0}).is_empty(), "impossible axis rejected")
	check(NetProtocol.clean_frame({"seat": 0, "ax": 0, "az": 0, "held": 0, "pressed": 0, "hack": 1}).is_empty(), "extra frame field rejected")
	check(not NetProtocol.clean_frame({"seat": 1, "ax": -127, "az": 127, "held": 3, "pressed": 1}).is_empty(), "valid frame accepted")
	eq(NetProtocol.normalize_code("abcd-oil1"), "ABCD0111", "O→0 and I/L→1, case-insensitive")
	var payload := {"type": "state_snapshot", "s": {"x": [1, 2, 3]}}
	eq(NetProtocol.decode_server(NetProtocol.encode_server(payload)), payload, "server payload round-trips")

## Fixture files in tests/fixtures/saves/ (regenerate: tools/dev/make_save_fixtures.gd).
func _install(dir: String, files: Dictionary):
	var ss = _service(dir)
	for name in files:
		var src := FileAccess.get_file_as_string("res://tests/fixtures/saves/" + files[name])
		var f := FileAccess.open(dir.path_join(name), FileAccess.WRITE)
		f.store_string(src)
		f.close()
	return ss

func test_save01_fixture_valid_v1_loads() -> void:
	var ss = _install("user://test_saves_f1", {"p.json": "v1_valid.json"})
	ss.load_profile("p")
	eq(ss.recovered_from, "", "valid file needs no recovery")
	eq(ss.profile["completed_levels"].size(), 5, "five completed shifts")
	check("L06" in ss.profile["accessible_levels"], "next shift accessible")
	check("first_hello" in ss.profile["unlocked_cosmetic_sets"], "cosmetic unlock kept")
	ss.free()

func test_save01_fixture_truncated_primary_recovers_backup() -> void:
	var ss = _install("user://test_saves_f2", {"p.json": "v1_truncated.json", "p.json.bak1": "v1_valid.json"})
	ss.load_profile("p")
	eq(ss.recovered_from, "bak1", "power-cut primary falls back to the backup")
	eq(ss.profile["completed_levels"].size(), 5, "durable stamps survive")
	ss.free()

func test_save01_fixture_tampered_is_not_trusted() -> void:
	var ss = _install("user://test_saves_f3", {"p.json": "v1_tampered.json", "p.json.bak2": "v1_valid.json"})
	ss.load_profile("p")
	eq(ss.recovered_from, "bak2", "checksum mismatch → older valid backup")
	check(not "L24" in ss.profile["completed_levels"], "edited progress not accepted")
	ss.free()

func test_save01_fixture_v0_file_migrates_on_load() -> void:
	var ss = _install("user://test_saves_f4", {"p.json": "v0_prerelease.json"})
	ss.load_profile("p")
	eq(ss.profile["schema_version"], 1, "migrated to schema 1")
	eq(ss.profile["completed_levels"], ["L01", "L02"], "v0 levels carried over")
	eq(ss.profile["selected_staff"], "moss", "v0 fields kept")
	ss.free()

func test_save01_disk_write_failure_keeps_previous_save() -> void:
	var dir := "user://test_saves_f5"
	var ss = _install(dir, {"p.json": "v1_valid.json"})
	ss.load_profile("p")
	ss.root_dir = dir.path_join("missing/deeper")   # unwritable target: open() fails
	ss.profile["completed_levels"].append("L06")
	check(not ss.save(), "save reports failure")
	eq(ss.last_error, "ui.save.write_failed", "clear recoverable message key")
	ss.root_dir = dir
	var ss2 = _service_keep(dir)
	ss2.load_profile("p")
	eq(ss2.profile["completed_levels"].size(), 5, "previous good save intact")
	ss2.free()
	ss.free()
