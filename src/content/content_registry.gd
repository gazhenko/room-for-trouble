extends Node
## ContentRegistry: resolves immutable content IDs to definitions (§19.2, §21.1).
## Loads JSON source from res://data, validates references and computes the
## gameplay content hash used by saves, replays and online compatibility checks.

const GAMEPLAY_FILES := [
	"res://data/guests/guests.json",
	"res://data/items/items.json",
	"res://data/items/stations.json",
	"res://data/layouts/base.json",
	"res://data/layouts/base_v2_small.json",
	"res://data/layouts/templates.json",
	"res://data/campaign_manifest.json",
	"res://data/tutorials/tutorials.json",
	"res://data/modifiers.json",
]

var guests: Dictionary = {}
var items: Dictionary = {}
var stations: Dictionary = {}
var templates: Dictionary = {}
var base_layout: Dictionary = {}
var base_layouts: Dictionary = {}   # name -> base envelope; templates pick one with "base"
var levels: Array = []
var levels_by_id: Dictionary = {}
var tutorials: Dictionary = {}
var modifiers: Dictionary = {}
var story: Dictionary = {}
var cosmetics: Array = []
var gags: Dictionary = {}
var content_hash := ""
var errors: PackedStringArray = []
var _layout_cache: Dictionary = {}
var loaded := false

func _ready() -> void:
	load_all()

func load_all() -> void:
	errors.clear()
	var g := _read("res://data/guests/guests.json")
	for d in g.get("guests", []):
		guests[d["id"]] = d
	var it := _read("res://data/items/items.json")
	for d in it.get("items", []):
		items[d["id"]] = d
	var st := _read("res://data/items/stations.json")
	for d in st.get("stations", []):
		stations[d["id"]] = d
	base_layout = _read("res://data/layouts/base.json")
	base_layouts = {"default": base_layout, "v2_small": _read("res://data/layouts/base_v2_small.json")}
	var tp := _read("res://data/layouts/templates.json")
	for d in tp.get("templates", []):
		templates[d["id"]] = d
	var man := _read("res://data/campaign_manifest.json")
	levels = man.get("levels", [])
	for L in levels:
		levels_by_id[L["id"]] = L
	var tu := _read("res://data/tutorials/tutorials.json")
	for d in tu.get("tutorials", []):
		tutorials[d["id"]] = d
	var md := _read("res://data/modifiers.json")
	for d in md.get("modifiers", []):
		modifiers[d["id"]] = d
	var cs := _read("res://data/cosmetics.json")
	cosmetics = cs.get("sets", [])
	for f in ["opening", "bridges", "ending", "levels"]:
		var s := _read("res://data/story/%s.json" % f)
		for p in s.get("scenes", []):
			story[p["id"]] = p
		for k in s.get("gags", {}):
			gags[k] = s["gags"][k]
	content_hash = _compute_hash()
	loaded = true

func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		errors.append("missing file: " + path)
		return {}
	var txt := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(txt)
	if parsed == null or not parsed is Dictionary:
		errors.append("invalid JSON: " + path)
		return {}
	return parsed

func _compute_hash() -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	for p in GAMEPLAY_FILES:
		if FileAccess.file_exists(p):
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(p))
			# Canonical re-serialisation so whitespace edits never change the hash.
			ctx.update(JSON.stringify(parsed, "", true).to_utf8_buffer())
	ctx.update(("protocol:%d" % SimC.PROTOCOL_VERSION).to_utf8_buffer())
	return ctx.finish().hex_encode().substr(0, 16)

func layout(template_id: String, mirror: bool = false) -> LayoutDef:
	var k := template_id + ("_m" if mirror else "")
	if not _layout_cache.has(k):
		var tpl: Dictionary = templates[template_id]
		var base: Dictionary = base_layouts.get(tpl.get("base", "default"), base_layout)
		_layout_cache[k] = LayoutDef.build(base, tpl, mirror)
	return _layout_cache[k]

func level(level_id: String) -> Dictionary:
	return levels_by_id.get(level_id, {})

func chapter_levels(chapter: int) -> Array:
	var out: Array = []
	for L in levels:
		if int(L["chapter"]) == chapter:
			out.append(L)
	return out

func guest_def(family: String) -> Dictionary:
	return guests.get(family, {})

func level_index(level_id: String) -> int:
	for i in levels.size():
		if levels[i]["id"] == level_id:
			return i
	return -1

func next_level_id(level_id: String) -> String:
	var i := level_index(level_id)
	if i >= 0 and i + 1 < levels.size():
		return levels[i + 1]["id"]
	return ""
