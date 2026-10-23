extends Node
## Local persistence (§21.3): versioned JSON + canonical SHA-256 checksum,
## atomic temp-file writes, three rotating backups, corruption recovery,
## schema migration and idempotent result application.

signal saved
signal recovered(message_key: String)

const SCHEMA := 1
const MAX_RECENT := 1024

var root_dir := "user://profiles"
var profile: Dictionary = {}
var profile_id := "couch"
var last_error := ""
var recovered_from := ""
var write_enabled := true
var content = null   # ContentRegistry; defaults to the Content autoload

func _c():
	return content if content != null else Content

func _ready() -> void:
	if OS.has_feature("dedicated_server") or "--server" in OS.get_cmdline_user_args():
		write_enabled = false
		profile = default_profile()
		return
	load_profile("couch")

func default_profile() -> Dictionary:
	var now := Time.get_datetime_string_from_system(true) + "Z"
	return {
		"schema_version": SCHEMA,
		"profile_id": _uuid(),
		"created_at": now,
		"updated_at": now,
		"completed_levels": [],
		"accessible_levels": ["L01"],
		"tutorial_status": {"T01": "unseen", "T02": "unseen", "T03": "unseen"},
		"seen_coaches": [],
		"seen_story_panels": [],
		"postcards": {},
		"earned_ribbons": [],
		"unlocked_cosmetic_sets": ["default"],
		"selected_staff": "pip",
		"selected_cosmetic_set": "default",
		"best_results": {},
		"recent_committed_result_ids": [],
		"settings": {},
		"suspended_shift": {},
		"discover_guests": false,
		"stats": {"shifts": 0, "guests_welcomed": 0, "handoffs": 0},
	}

func _uuid() -> String:
	var b := Crypto.new().generate_random_bytes(16)
	b[6] = (b[6] & 0x0F) | 0x40
	b[8] = (b[8] & 0x3F) | 0x80
	var h := b.hex_encode()
	return "%s-%s-%s-%s-%s" % [h.substr(0, 8), h.substr(8, 4), h.substr(12, 4), h.substr(16, 4), h.substr(20, 12)]

func path_for(id: String, suffix := "") -> String:
	return "%s/%s.json%s" % [root_dir, id, suffix]

static func checksum_of(d: Dictionary) -> String:
	var c: Dictionary = normalize(d)
	c.erase("checksum")
	return JSON.stringify(c, "", true).sha256_text()

## JSON has one number type: integral floats become ints so a saved file
## and its in-memory profile canonicalise identically.
static func normalize(v):
	if v is Dictionary:
		var out := {}
		for k in v:
			out[str(k)] = normalize(v[k])
		return out
	if v is Array:
		var arr: Array = []
		for x in v:
			arr.append(normalize(x))
		return arr
	if v is float and is_finite(v) and v == floor(v) and absf(v) < 9.0e15:
		return int(v)
	return v

func _read_valid(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var txt := FileAccess.get_file_as_string(path)
	var d = JSON.parse_string(txt)
	if not d is Dictionary:
		return {}
	# Pre-release v0 profiles had no checksum; migrate() upgrades them.
	if int(d.get("schema_version", -1)) == 0 and not d.has("checksum"):
		return normalize(d)
	if str(d.get("checksum", "")) != checksum_of(d):
		return {}
	return normalize(d)

func load_profile(id: String) -> void:
	profile_id = id
	recovered_from = ""
	DirAccess.make_dir_recursive_absolute(root_dir)
	var primary := path_for(id)
	var d := _read_valid(primary)
	if d.is_empty() and FileAccess.file_exists(primary):
		for i in [1, 2, 3]:
			d = _read_valid(path_for(id, ".bak%d" % i))
			if not d.is_empty():
				recovered_from = "bak%d" % i
				break
		if not d.is_empty():
			recovered.emit("ui.save.recovered")
		else:
			recovered.emit("ui.save.reset")
	if d.is_empty():
		d = default_profile()
	profile = migrate(d)
	if recovered_from != "":
		save()

## Migrations are pure functions from older schema dictionaries (tested by
## tests/test_save.gd with fixtures in tests/fixtures/saves/).
func migrate(d: Dictionary) -> Dictionary:
	var out := d.duplicate(true)
	var v := int(out.get("schema_version", 0))
	if v < 1:
		# v0 (pre-release) stored "levels_done" and "ribbons" lists.
		out["completed_levels"] = out.get("levels_done", out.get("completed_levels", []))
		out["earned_ribbons"] = out.get("ribbons", out.get("earned_ribbons", []))
		out.erase("levels_done")
		out.erase("ribbons")
		v = 1
	var base := default_profile()
	for k in base:
		if not out.has(k):
			out[k] = base[k]
	out["schema_version"] = SCHEMA
	return out

func save() -> bool:
	if not write_enabled:
		return true
	profile["updated_at"] = Time.get_datetime_string_from_system(true) + "Z"
	profile["checksum"] = checksum_of(profile)
	var txt := JSON.stringify(profile, "\t", true)
	var primary := path_for(profile_id)
	var tmp := primary + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		last_error = "ui.save.write_failed"
		return false
	f.store_string(txt)
	f.flush()
	var ok := f.get_error() == OK
	f.close()
	if not ok:
		last_error = "ui.save.write_failed"
		DirAccess.remove_absolute(tmp)
		return false
	var verify := _read_valid(tmp)
	if verify.is_empty():
		last_error = "ui.save.verify_failed"
		DirAccess.remove_absolute(tmp)
		return false
	if FileAccess.file_exists(primary):
		for i in [3, 2]:
			var older := path_for(profile_id, ".bak%d" % i)
			var newer := path_for(profile_id, ".bak%d" % (i - 1))
			if FileAccess.file_exists(newer):
				DirAccess.copy_absolute(newer, older)
		DirAccess.copy_absolute(primary, path_for(profile_id, ".bak1"))
	var err := DirAccess.rename_absolute(tmp, primary)
	if err != OK:
		last_error = "ui.save.write_failed"
		return false
	last_error = ""
	saved.emit()
	return true

# ------------------------------------------------------------ progression

func is_accessible(level_id: String) -> bool:
	return level_id in profile["accessible_levels"]

func is_completed(level_id: String) -> bool:
	return level_id in profile["completed_levels"]

func catch_up_levels() -> Array:
	## Earlier unplayed levels remain selectable (Catch Up, §16.2).
	var out: Array = []
	var highest := -1
	for lid in profile["accessible_levels"]:
		highest = maxi(highest, _c().level_index(lid))
	for i in range(0, highest):
		var lid2: String = _c().levels[i]["id"]
		if not is_completed(lid2):
			out.append(lid2)
	return out

## Applies an authoritative shift result. Idempotent: set unions and max.
## Returns a delta describing first-time grants (for notifications).
func apply_result(res: Dictionary) -> Dictionary:
	var rid: String = res.get("result_id", "")
	var delta := {"first_completion": false, "postcard": "", "ribbons": [], "unlocks": [], "next": "",
		"best": false, "duplicate": false}
	var recent: Array = profile["recent_committed_result_ids"]
	if rid != "" and rid in recent:
		delta["duplicate"] = true
	var lid: String = res.get("level", "")
	if lid != "" and _c().level_index(lid) >= 0:
		if not lid in profile["completed_levels"]:
			profile["completed_levels"].append(lid)
			delta["first_completion"] = true
		if not lid in profile["accessible_levels"]:
			profile["accessible_levels"].append(lid)
		var nxt: String = _c().next_level_id(lid)
		if nxt != "" and not nxt in profile["accessible_levels"]:
			profile["accessible_levels"].append(nxt)
		delta["next"] = nxt
		if not profile["postcards"].has(lid):
			profile["postcards"][lid] = {"level": lid, "seed": int(res.get("seed", 0)),
				"staff": res.get("staff", []), "outfit": res.get("outfit", "default"),
				"stars": int(res.get("stars", 0)), "unlocked": true, "photo_path": ""}
			delta["postcard"] = lid
		else:
			var pc: Dictionary = profile["postcards"][lid]
			pc["stars"] = maxi(int(pc.get("stars", 0)), int(res.get("stars", 0)))
		for rb in res.get("ribbons", []):
			if rb.get("earned", false):
				var rk := "%s:%s" % [lid, rb["label"]]
				if not rk in profile["earned_ribbons"]:
					profile["earned_ribbons"].append(rk)
					delta["ribbons"].append(rb["label"])
		var key := "%s|%s|%d|%s|%s" % [lid, res.get("difficulty", "family"), int(res.get("humans", 1)),
			res.get("assist_signature", "none"), res.get("modifier_signature", "none")]
		var best: Dictionary = profile["best_results"].get(key, {})
		if best.is_empty() or int(res.get("percent", 0)) > int(best.get("percent", -1)):
			profile["best_results"][key] = {"percent": int(res.get("percent", 0)), "stars": int(res.get("stars", 0)),
				"result_id": rid, "date": Time.get_date_string_from_system()}
			delta["best"] = true
	for u in _check_unlocks():
		delta["unlocks"].append(u)
	if rid != "" and not rid in recent:
		recent.append(rid)
		while recent.size() > MAX_RECENT:
			recent.pop_front()
	profile["stats"]["shifts"] = int(profile["stats"].get("shifts", 0)) + (0 if delta["duplicate"] else 1)
	save()
	return delta

func _check_unlocks() -> Array:
	var out: Array = []
	var have: Array = profile["unlocked_cosmetic_sets"]
	for cs in _c().cosmetics:
		var id: String = cs["id"]
		if id in have:
			continue
		var u: Dictionary = cs["unlock"]
		var ok := false
		match u.get("type", ""):
			"always": ok = true
			"level": ok = u["id"] in profile["completed_levels"]
			"chapter":
				ok = true
				for L in _c().chapter_levels(int(u["chapter"])):
					if not L["id"] in profile["completed_levels"]:
						ok = false
			"ribbons": ok = profile["earned_ribbons"].size() >= int(u["count"])
		if ok:
			have.append(id)
			out.append(id)
	return out

func mark_tutorial(tid: String, status: String) -> void:
	profile["tutorial_status"][tid] = status
	save()

func mark_coach_seen(cid: String) -> void:
	if not cid in profile["seen_coaches"]:
		profile["seen_coaches"].append(cid)
		save()

func mark_story_seen(sid: String) -> void:
	if not sid in profile["seen_story_panels"]:
		profile["seen_story_panels"].append(sid)
		save()

func story_seen(sid: String) -> bool:
	return sid in profile["seen_story_panels"]
