extends TestBase
## DATA01–DATA02, MAP01–MAP02, STORY01 references, localization coverage.

func test_data01_manifest() -> void:
	eq(content.levels.size(), 24, "24 levels")
	var by_ch := {}
	for L in content.levels:
		by_ch[int(L["chapter"])] = by_ch.get(int(L["chapter"]), 0) + 1
		eq(L["waves"].size(), 3, L["id"] + " has 3 waves")
		check(content.templates.has(L["layout"]), L["id"] + " layout exists")
	for ch in range(1, 7):
		eq(by_ch.get(ch, 0), 4, "chapter %d has 4 levels" % ch)
	eq(content.errors.size(), 0, "content loaded without errors: %s" % ", ".join(content.errors))

func test_data02_expansion_all_counts() -> void:
	for L in content.levels:
		var lay: LayoutDef = content.layout(L["layout"])
		for h in range(1, 5):
			var sched := ArrivalPlan.schedule(L, h, lay.active_rooms.size())
			var last := 0
			for a in sched:
				check(int(a["arrive_s"]) >= 0, "%s/%d nonnegative arrivals" % [L["id"], h])
				last = maxi(last, int(a["arrive_s"]))
			check(int(L["duration_hotel_s"]) - last >= 148, "%s/%d final reserve" % [L["id"], h])
		var solo := ArrivalPlan.expand_waves(L, 1, lay.active_rooms.size())
		var fams := {}
		for w in solo:
			for f in w:
				fams[f] = true
		if L["id"] in ["L16", "L24"]:
			eq(fams.size(), 6, L["id"] + " solo covers all six families")

func test_map01_routes_reachable() -> void:
	for tid in content.templates:
		for mirror in [false, true]:
			var L: LayoutDef = content.layout(tid, mirror)
			var start: Vector2i = L.fixtures["staff_starts"][0]
			var seen := _flood(L, start, false)
			for letter in L.active_rooms:
				var d: Vector2i = L.rooms[letter]["door"]
				check(seen.has(d), "%s%s door %s reachable" % [tid, "m" if mirror else "", letter])
				var b: Vector2i = L.rooms[letter]["plinth"]
				check(seen.has(b + Vector2i(0, 1)) or seen.has(b + Vector2i(0, -1)) or seen.has(b + Vector2i(1, 0)) or seen.has(b + Vector2i(-1, 0)), "%s plinth %s reachable" % [tid, letter])
			if L.shutter.x >= 0:
				var seen2 := _flood(L, start, true)
				for letter in L.active_rooms:
					check(seen2.has(L.rooms[letter]["door"]), "%s room %s reachable with shutter closed" % [tid, letter])

func _flood(L: LayoutDef, start: Vector2i, shutter_closed: bool) -> Dictionary:
	var seen := {start: true}
	var q: Array = [start]
	while not q.is_empty():
		var c: Vector2i = q.pop_front()
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if seen.has(n) or L.is_wall_tile(n.x, n.y):
				continue
			if shutter_closed and n == L.shutter:
				continue
			seen[n] = true
			q.append(n)
	return seen

func test_map02_fixtures_have_access() -> void:
	for tid in content.templates:
		var L: LayoutDef = content.layout(tid)
		for k in ["reception", "linen_shelf", "hamper", "towel_shelf", "snack_tin", "welcome_kiosk", "return_shelf", "tap"]:
			var p: Vector2i = L.fixtures[k]
			var open := 0
			for d in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
				if not L.is_wall_tile(p.x + d.x, p.y + d.y):
					open += 1
			check(open >= 2, "%s %s has at least two sides open" % [tid, k])

func test_story_refs_and_loc() -> void:
	var loc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/localization/en.json"))
	for sid in content.story:
		var sc: Dictionary = content.story[sid]
		for p in sc.get("panels", []):
			if p.has("caption"):
				check(loc.has(p["caption"]), "caption key %s exists" % p["caption"])
	for L in content.levels:
		for k in ["title", "mid", "postcard", "purpose", "blurb"]:
			check(loc.has("level.%s.%s" % [L["id"], k]), "level.%s.%s exists" % [L["id"], k])
		check(content.story.has(L["id"] + ".pre"), L["id"] + " has a pre-shift beat")
		check(content.story.has(L["id"] + ".post"), L["id"] + " has a postcard")
		check(content.gags.has(L["id"]), L["id"] + " has a live gag")
	for b in ["O00", "B01", "B02", "B03", "B04", "B05", "E00"]:
		check(content.story.has(b), b + " exists")
	for t in ["T01", "T02", "T03"]:
		for st in content.tutorials[t]["steps"]:
			check(loc.has(st["caption"]), "tutorial caption %s" % st["caption"])

func test_mod01_mirror_transforms() -> void:
	var a: LayoutDef = content.layout("P5")
	var b: LayoutDef = content.layout("P5", true)
	for letter in a.rooms:
		var da: Vector2i = a.rooms[letter]["door"]
		var db: Vector2i = b.rooms[letter]["door"]
		eq(db.x, 27 - da.x, "door %s mirrored" % letter)
		eq(db.y, da.y, "door %s keeps z" % letter)
	eq(b.lift_pads[0].x, 27 - a.lift_pads[0].x, "lift pads mirrored")
	eq(b.shutter.x, 27 - a.shutter.x, "shutter mirrored")
