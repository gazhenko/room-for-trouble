extends SceneTree
## Content validation (§22.1): references, layouts, story staging, tutorial
## graphs, icons and localization keys used by code. Fails (exit 1) on errors.
##   godot --headless --path . --script res://tools/validate_content.gd

var errors: PackedStringArray = []
var warnings: PackedStringArray = []

func err(msg: String) -> void:
	errors.append(msg)

func _initialize() -> void:
	var C = load("res://src/content/content_registry.gd").new()
	C.load_all()
	for e in C.errors:
		if not "levels.json" in e:
			err(e)
	var loc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/localization/en.json"))
	# Guests / items / stations reference integrity.
	for fam in SimC.FAMILIES:
		if not C.guests.has(fam):
			err("guest definition missing: " + fam)
		elif not C.items.has(C.guests[fam]["welcome_item_id"]):
			err("guests/%s: welcome item %s unknown" % [fam, C.guests[fam]["welcome_item_id"]])
	for L in C.levels:
		for w in L["waves"]:
			for f in w["roster"]:
				if not C.guests.has(f):
					err("%s: unknown family %s" % [L["id"], f])
		for k in ["title", "mid", "postcard", "purpose"]:
			if not loc.has("level.%s.%s" % [L["id"], k]):
				err("missing localization level.%s.%s" % [L["id"], k])
		if not C.story.has(L["id"] + ".pre") or not C.story.has(L["id"] + ".post"):
			err("%s: missing story beats" % L["id"])
		# v2 floors may lack rooms and fixtures: overrides and events must target what exists.
		if C.templates.has(L["layout"]):
			var lay: LayoutDef = C.layout(L["layout"])
			for room in L.get("initial_rooms", {}):
				if not lay.rooms.has(room) or not lay.rooms[room]["active"]:
					err("%s: initial_rooms targets room %s, which layout %s does not have" % [L["id"], room, L["layout"]])
			for e in L.get("events", []):
				_check_target_args(L["id"], str(e.get("id", e["type"])), e.get("args", {}), lay, L["layout"])
	# Story staging: cameras, props, actors, captions.
	var props := ModelProps.kinds() if ResourceLoader.exists("res://src/view/models/model_props.gd") else PackedStringArray()
	var cams: Array = StoryStaging.CAMERAS.keys()
	var actors := ["nana", "gus", "dot", "staff", "mallow", "flurry", "cinder", "whisp", "luna", "fern"]
	for sid in C.story:
		var sc: Dictionary = C.story[sid]
		if not C.templates.has(sc.get("layout", "P1")):
			err("story %s: unknown layout" % sid)
		for p in sc.get("panels", []):
			if not p.get("camera", "") in cams:
				err("story %s: unknown camera %s" % [p.get("id", sid), p.get("camera", "")])
			if p.has("caption") and not loc.has(p["caption"]):
				err("story %s: caption key %s missing" % [p.get("id", sid), p["caption"]])
			for a in p.get("actors", []):
				var aid: String = a["id"]
				if not (aid in actors or aid.begins_with("guest:")):
					err("story %s: unknown actor %s" % [p.get("id", sid), aid])
			# Staged as the player stages it (StoryStaging): nobody stands in a
			# wall or inside a station's footprint on the floor the beat plays on.
			var slay: String = p.get("layout", sc.get("layout", "P1"))
			if C.templates.has(slay) and p.get("set", "") != "photo":
				var SL: LayoutDef = C.layout(slay)
				var staged := StoryStaging.stage(SL, p, StoryStaging.CAMERAS, ["pip"], 1.6)   # 16:10, the Deck
				for a2 in staged["actors"]:
					var m: Vector3 = a2["pos3"]
					if m.x > 0.5 and SL.is_wall_tile(LayoutDef.tile_of(int(m.x * SimC.UM)), LayoutDef.tile_of(int(m.z * SimC.UM))):
						warnings.append("story %s: actor %s stands in a wall at (%.1f, %.1f) on %s" % [p.get("id", sid), a2["id"], m.x, m.z, slay])
					var tag := _box_at(SL, m, 0.25)
					if tag != "":
						warnings.append("story %s: actor %s stands in %s at (%.1f, %.1f) on %s" % [p.get("id", sid), a2["id"], tag, m.x, m.z, slay])
			for pr in p.get("props", []):
				var pk: String = pr["kind"]
				if pk.begins_with("item:"):
					if not pk.substr(5) in ModelItems.KINDS:
						err("story %s: unknown item prop %s" % [p.get("id", sid), pk])
				elif not props.is_empty() and not pk in props:
					err("story %s: unknown prop %s" % [p.get("id", sid), pr["kind"]])
	# Tutorials.
	for tid in C.tutorials:
		var t: Dictionary = C.tutorials[tid]
		if not C.templates.has(t["layout"]):
			err("tutorial %s: unknown layout" % tid)
		else:
			var tlay: LayoutDef = C.layout(t["layout"])
			for room in t.get("assignable", []):
				if not tlay.rooms.has(room) or not tlay.rooms[room]["active"]:
					err("tutorial %s: assignable room %s is not on layout %s" % [tid, room, t["layout"]])
			for op0 in t.get("init", []):
				_check_target_args(tid, "init", op0, tlay, t["layout"])
			for st0 in t["steps"]:
				for op in st0.get("ops", []):
					_check_target_args(tid, str(st0["id"]), op, tlay, t["layout"])
		for st in t["steps"]:
			if not loc.has(st["caption"]):
				err("tutorial %s: caption %s missing" % [tid, st["caption"]])
	# Layout anchors reachable from the hall (MAP01 summary), with the staff capsule
	# against fixture boxes too (a station can seal a one-tile corridor that the
	# tile flood would pass).
	for tid in C.templates:
		var Lay: LayoutDef = C.layout(tid)
		var start0: Vector2i = Lay.fixtures["staff_starts"][0]
		var start := Vector2i(start0.x * SimC.UM, start0.y * SimC.UM)
		for letter in Lay.active_rooms:
			var d: Vector2i = Lay.rooms[letter]["door"]
			if Lay.is_wall_tile(d.x, d.y):
				err("%s: door %s is a wall" % [tid, letter])
			for closed in [false, true]:
				if closed and Lay.shutter.x < 0:
					continue
				if not Lay.capsule_reachable(start, Vector2i(d.x * SimC.UM, d.y * SimC.UM), SimC.RADIUS, closed):
					err("%s: door %s is not reachable for the staff capsule%s" % [tid, letter, " with the shutter closed" if closed else ""])
		for k in Lay.fixtures:
			if k in ["staff_starts", "pedestals", "goal_pad"]:
				continue
			var anchors: Array = Lay.fixtures[k] if Lay.fixtures[k] is Array else [Lay.fixtures[k]]
			for an in anchors:
				var ap := Vector2i(an.x * SimC.UM, an.y * SimC.UM)
				if not Lay.capsule_reachable(start, ap, SimC.RADIUS, false):
					err("%s: fixture %s at %s is not reachable for the staff capsule" % [tid, k, str(an)])
	# Localization keys used literally by code.
	var used := {}
	var rx := RegEx.new()
	rx.compile("Loc\\.t\\(\"([a-z0-9_.]+)\"")
	for path in _scripts("res://src"):
		var txt := FileAccess.get_file_as_string(path)
		for m in rx.search_all(txt):
			used[m.get_string(1)] = path
	for k in used:
		if k.ends_with(".") or k.ends_with("_"):
			continue
		if not loc.has(k):
			err("missing localization key %s (used in %s)" % [k, used[k]])
	# Icons referenced literally exist (if the icon set is present).
	if ResourceLoader.exists("res://src/ui/icons.gd"):
		var irx := RegEx.new()
		irx.compile("(?:draw_icon\\(self, |UiKit\\.icon\\(|Icons\\.tex\\(|\\.button\\([^\\n]*?, )\"([a-z][a-z0-9_]+)\"")
		var Icons_ = load("res://src/ui/icons.gd")
		var missing := {}
		for path in _scripts("res://src"):
			var txt2 := FileAccess.get_file_as_string(path)
			for m2 in irx.search_all(txt2):
				var name := m2.get_string(1)
				if name.ends_with("_"):
					continue
				if not Icons_.has(name) and not missing.has(name):
					missing[name] = path
		for n in missing:
			warnings.append("icon %s not in icon set (%s)" % [n, missing[n]])
	for w in warnings:
		print("WARN  ", w)
	for e in errors:
		print("ERROR ", e)
	print("content validation: %d errors, %d warnings (hash %s)" % [errors.size(), warnings.size(), C.content_hash])
	C.free()
	quit(1 if errors.size() > 0 else 0)

## Rooms, radiator fixtures, lift pairs and hall positions named by an event or
## tutorial op must exist on the floor it runs on.
## Tag of the solid fixture footprint (grown by `grow` metres) that contains the
## point, or "" when the point is on open floor.
func _box_at(lay: LayoutDef, m: Vector3, grow: float) -> String:
	var g := int(grow * SimC.UM)
	var px := int(m.x * SimC.UM)
	var pz := int(m.z * SimC.UM)
	for b in lay.boxes:
		if px >= int(b[0]) - g and px <= int(b[2]) + g and pz >= int(b[1]) - g and pz <= int(b[3]) + g:
			return str(b[4])
	return ""

func _check_target_args(owner: String, what: String, a: Dictionary, lay: LayoutDef, layout_id: String) -> void:
	if a.has("room"):
		var room := str(a["room"])
		if not lay.rooms.has(room) or not lay.rooms[room]["active"]:
			err("%s: %s targets room %s, which layout %s does not have" % [owner, what, room, layout_id])
	var fx := str(a.get("fixture", ""))
	if fx.begins_with("radiator_") and not lay.rooms.has(fx.substr(9)):
		err("%s: %s trips %s, which layout %s does not have" % [owner, what, fx, layout_id])
	if fx == "lift_pair" and lay.lift_pads.size() != 2:
		err("%s: %s trips the lift pair but layout %s has no lift" % [owner, what, layout_id])
	var pts: Array = []
	if a.has("position"):
		pts.append(a["position"])
	for p in a.get("positions", []):
		pts.append(p)
	for p in pts:
		if lay.is_wall_tile(int(p[0]), int(p[1])):
			err("%s: %s position %s is a wall on layout %s" % [owner, what, str(p), layout_id])

func _scripts(dir: String) -> Array:
	var out: Array = []
	var da := DirAccess.open(dir)
	if da == null:
		return out
	for f in da.get_files():
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for d in da.get_directories():
		out.append_array(_scripts(dir.path_join(d)))
	return out
