extends Node
## Development screenshot tool (not shipped in normal play).
##   godot --path . res://tools/shots/shot.tscn -- --what=hotel:P6 --out=build/shots/p6.png
## what: hotel:<P1..P6> | actors | items | stations | level:<Lxx>:<seconds>

var what := "hotel:P6"
var out := "build/shots/shot.png"
var frames_wait := 8
var stage: PixelStage
var size := Vector2i(1280, 720)

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--what="): what = a.substr(7)
		elif a.begins_with("--out="): out = a.substr(6)
		elif a.begins_with("--size="):
			var p := a.substr(7).split("x")
			size = Vector2i(int(p[0]), int(p[1]))
	DisplayServer.window_set_size(size)
	stage = PixelStage.new()
	add_child(stage)
	await get_tree().process_frame
	var parts := what.split(":")
	match parts[0]:
		"hotel":
			var L: LayoutDef = Content.layout(parts[1] if parts.size() > 1 else "P6")
			var sys := {"core": true, "thermal": true, "sound": true, "moisture": true, "festival": true}
			stage.world.add_child(HotelBuilder.new().build(L, sys))
		"actors":
			_gallery_actors()
			await get_tree().process_frame
			var zoom2 := what.split(":")
			if zoom2.size() > 1 and zoom2[1] == "staff":
				stage.set_bounds(Vector3(0.5, 0, 2.6), Vector3(18.5, 1.2, 5.6))
			elif zoom2.size() > 1 and zoom2[1] == "guests":
				stage.set_bounds(Vector3(1.0, 0, 10.4), Vector3(24.0, 1.4, 13.6))
		_:
			var cb := Callable(self, "_gallery_" + parts[0])
			if cb.is_valid():
				await cb.call(parts)
	for i in frames_wait:
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://").path_join(out.get_base_dir()))
	img.save_png(ProjectSettings.globalize_path("res://").path_join(out))
	print("saved ", out, " ", img.get_size())
	get_tree().quit()

func _floor_plate(w: float, d: float) -> void:
	var mk := MeshKit.new()
	mk.flat(Vector3(13.5, 0, 9.5), Vector2(w, d), Color("#D8C3A0"))
	stage.world.add_child(Art.mesh_instance(mk.commit(), Art.toon_tex("plate", Art.planks(2), 1.0, 0.25)))

func _gallery_actors() -> void:
	_floor_plate(34, 26)
	var x := 2.0
	var cos := {"cap": "#E88D79", "scarf": "#E8BF66", "trim": "#F7EAD6"}
	for id in ["pip", "pebble", "moss", "button"]:
		var r := ModelActors.staff(id, cos)
		r.position = Vector3(x, 0, 4.0)
		stage.world.add_child(r)
		x += 2.5
	for id in ["nana", "gus", "dot"]:
		var r2 := ModelActors.npc(id)
		r2.position = Vector3(x, 0, 4.0)
		stage.world.add_child(r2)
		x += 2.5
	x = 2.0
	for fam in SimC.FAMILIES:
		var g := ModelActors.guest(fam, "")
		g.position = Vector3(x + 1.0, 0, 12.0)
		stage.world.add_child(g)
		x += 4.0
	# Close-up framing for model review.
	var zoom := what.split(":")
	if zoom.size() > 1 and zoom[1] == "staff":
		stage.set_bounds(Vector3(0.5, 0, 2.6), Vector3(18.5, 1.2, 5.6))
	elif zoom.size() > 1 and zoom[1] == "guests":
		stage.set_bounds(Vector3(1.0, 0, 10.4), Vector3(24.0, 1.4, 13.6))

# ------------------------------------------------------------ model galleries
#   --what=stations[:a|b|c|room|all]   station sheets with representative states
#   --what=stations:hotel[:P6|P5][:hall]  every fixture placed in a real template
#   --what=items                        every carryable, lying and held aloft
#   --what=props                        story props and hub decorations

func _place(n: Node3D, pos: Vector3, yaw := 0.0) -> Node3D:
	n.position = pos
	n.rotation_degrees.y = yaw
	stage.world.add_child(n)
	if n is StationNode:
		(n as StationNode).set_auto_tick(true)
	return n

func _st(kind: String, pos: Vector3, state: Dictionary = {}, opts: Dictionary = {}) -> StationNode:
	var s := ModelStations.build(kind, opts)
	_place(s, pos)
	if not state.is_empty():
		s.apply(state)
	s.tick(0.45)
	return s

func _wall_chunk(pos: Vector3, size: Vector3) -> void:
	var mk := MeshKit.new()
	mk.box(pos + Vector3(0, size.y * 0.5, 0), size, Art.CREAM.darkened(0.06), Color("#5E4536"))
	stage.world.add_child(Art.mesh_instance(mk.commit(), Art.toon()))

func _station_rows(page: String) -> Array:
	var all_f := ["slime", "yeti", "dragon", "ghost", "moonwolf", "sprout"]
	var a := [
		[["reception", {"bench": 0}], ["reception", {"bench": 5}], ["pedestal", {"occupied": false}],
			["pedestal", {"occupied": true}], ["linen_shelf", {"count": 12, "pressing": false, "press_progress": 0.0}],
			["linen_shelf", {"count": 5, "pressing": true, "press_progress": 0.6}],
			["hamper", {"queue": 3, "washing": true, "cycle": 0.4, "full": false}],
			["hamper", {"queue": 8, "washing": false, "cycle": 0.0, "full": true}]],
		[["towel_shelf", {"count": 6, "tripped": false, "warn": false}], ["towel_shelf", {"count": 3, "tripped": false, "warn": true}],
			["towel_shelf", {"count": 2, "tripped": true, "warn": false}], ["snack_tin", {"count": 6, "tripped": false, "warn": false}],
			["snack_tin", {"count": 2, "tripped": false, "warn": true}], ["snack_tin", {"count": 4, "tripped": true, "warn": false}],
			["welcome_kiosk", {"selected": "dragon", "families": all_f, "needed": ["yeti", "ghost"]}],
			["welcome_kiosk", {"selected": "slime", "families": ["slime", "yeti", "dragon"], "needed": []}]],
	]
	var b := [
		[["return_shelf", {"curtains": 3, "curtain_system": true}], ["return_shelf", {"curtains": 0, "curtain_system": false}],
			["heat_pump", {"enabled": true, "mode": "balanced", "hot_demand": 2, "cold_demand": 3}],
			["heat_pump", {"enabled": true, "mode": "warm", "hot_demand": 5, "cold_demand": 1}],
			["heat_pump", {"enabled": true, "mode": "cool", "hot_demand": 0, "cold_demand": 6}],
			["heat_pump", {"enabled": false, "mode": "balanced", "hot_demand": 0, "cold_demand": 0}],
			["tap", {"enabled": true}], ["tap", {"enabled": false}]],
		[["tool_dock", {"occupied": false, "enabled": true}, {"tool": "mop"}],
			["tool_dock", {"occupied": true, "enabled": true}, {"tool": "mop", "index": 1}],
			["tool_dock", {"occupied": false, "enabled": true}, {"tool": "breezer"}],
			["tool_dock", {"occupied": false, "enabled": true}, {"tool": "can"}],
			["tool_dock", {"occupied": false, "enabled": false}, {"tool": "can", "index": 1}],
			["group_bell", {"ringing": true, "finish_ready": false}], ["group_bell", {"ringing": false, "finish_ready": true}],
			["festival_stand", {"enabled": true, "parcels": 4, "trunks": 2}], ["festival_stand", {"enabled": false, "parcels": 0, "trunks": 0}]],
	]
	var c := [
		[["goal_pad", {"enabled": true, "active": true}], ["lift_pad", {"enabled": true, "busy": false, "tripped": false}, {"index": 0}],
			["lift_pad", {"enabled": true, "busy": true, "tripped": false}, {"index": 1}],
			["lift_pad", {"enabled": true, "busy": false, "tripped": true}, {"index": 0}],
			["lift_pad", {"enabled": false, "busy": false, "tripped": false}, {"index": 1}]],
		[["shutter", {"state": "open"}, {"axis": "x"}], ["shutter", {"state": "warn"}, {"axis": "x"}],
			["shutter", {"state": "closed"}, {"axis": "x"}], ["shutter", {"state": "closed"}, {"axis": "z"}]],
	]
	var room := [
		[["bed", {"bed": "Made", "occupied": true}, {"room_color": Art.ROOM_COLORS["A"]}],
			["bed", {"bed": "Dirty", "occupied": false}, {"room_color": Art.ROOM_COLORS["B"]}],
			["bed", {"bed": "Stripped", "occupied": false}, {"room_color": Art.ROOM_COLORS["E"]}],
			["plinth", {}, {"room_color": Art.ROOM_COLORS["C"]}], ["drop_pad", {}, {"room_color": Art.ROOM_COLORS["D"]}]],
		[["thermostat", {"enabled": true, "mode": "neutral", "tripped": false, "heat": 0}],
			["thermostat", {"enabled": true, "mode": "warm", "tripped": false, "heat": 45}],
			["thermostat", {"enabled": true, "mode": "cool", "tripped": false, "heat": -60}],
			["thermostat", {"enabled": true, "mode": "warm", "tripped": true, "heat": 20}],
			["thermostat", {"enabled": false, "mode": "neutral", "tripped": false, "heat": 0}],
			["water_tray", {"enabled": false, "wet": 0, "humidity": 20}], ["water_tray", {"enabled": true, "wet": 0, "humidity": 20}],
			["water_tray", {"enabled": true, "wet": 60, "humidity": 80}]],
		[["curtain_rail", {"enabled": true, "installed": true}], ["curtain_rail", {"enabled": true, "installed": false}],
			["vent_gate", {"open": true, "flow": 0.8}, {"facing": 1}], ["vent_gate", {"open": true, "flow": -0.5}, {"facing": 1}],
			["vent_gate", {"open": false, "flow": 0.0}, {"facing": 1}], ["vent_gate", {"open": true, "flow": 0.6}, {"facing": -1}],
			["vent_gate", {"open": false, "flow": 0.0}, {"facing": -1}]],
	]
	var rows: Array = a
	match page:
		"b": rows = b
		"c": rows = c
		"room": rows = room
		"all": return a + b + c + room
	# Close-up sheets: at most four models per row.
	var out: Array = []
	for row in rows:
		var i := 0
		while i < row.size():
			out.append(row.slice(i, i + 4))
			i += 4
	return out

func _station_width(kind: String) -> float:
	match kind:
		"bed": return 1.9
		"goal_pad": return 2.2
		"shutter", "curtain_rail", "vent_gate": return 1.25
	return 1.05

func _gallery_stations(parts: Array) -> void:
	var page := String(parts[1]) if parts.size() > 1 else "a"
	if page == "hotel":
		await _stations_hotel(String(parts[2]) if parts.size() > 2 else "P6", parts.size() > 3 and parts[3] == "hall")
		return
	_floor_plate(40, 30)
	var z := 3.6
	var max_x := 0.0
	var rows := _station_rows(page)
	if parts.size() > 2 and String(parts[2]).is_valid_int():
		# --what=stations:<page>:<n> frames rows n and n+1 only (closer review).
		var first := int(parts[2])
		rows = rows.slice(first, first + 2)
	for row in rows:
		var x := 1.6
		var depth := 1.5
		for e in row:
			var kind: String = e[0]
			var w := _station_width(kind)
			var opts: Dictionary = e[2] if e.size() > 2 else {}
			var pos := Vector3(x + w * 0.5, 0, z)
			if kind == "vent_gate":
				var f := float(opts.get("facing", 1))
				_wall_chunk(pos + Vector3(0, 0, -1.0 * f), Vector3(1.0, 0.95 if f > 0 else 0.62, 1.0))
			if kind == "curtain_rail":
				for s in [-1.0, 1.0]:
					_wall_chunk(pos + Vector3(s * 0.98, 0, 0), Vector3(0.96, 0.95, 1.0))
			var sn := _st(kind, pos, e[1], opts)
			if kind == "pedestal" and e[1].get("occupied", false):
				_place(ModelItems.build("ticket", {"family": "dragon"}), pos + Vector3(0, sn.get_meta("top_y"), 0))
			if kind == "plinth":
				_place(ModelItems.build("welcome_yeti"), pos + Vector3(0, sn.get_meta("top_y"), 0))
			if kind == "tool_dock" and e[1].get("occupied", false):
				_place(ModelItems.build("mop"), pos)
			if kind == "bed" or kind == "goal_pad":
				depth = 2.2
			x += w + 0.25
		max_x = maxf(max_x, x)
		z += depth
	await get_tree().process_frame
	stage.set_bounds(Vector3(1.3, 0, 2.6), Vector3(max_x, 1.2, z - 0.9))

func _v(p: Vector2i) -> Vector3:
	return Vector3(p.x, 0, p.y)

func _stations_hotel(tpl: String, hall: bool) -> void:
	var L: LayoutDef = Content.layout(tpl)
	var sys := {"core": true, "thermal": true, "sound": true, "moisture": true, "festival": true}
	stage.world.add_child(HotelBuilder.new().build(L, sys))
	var pal := L.palette
	var f := L.fixtures
	var all_f := ["slime", "yeti", "dragon", "ghost", "moonwolf", "sprout"]
	_st("reception", _v(f["reception"]), {"bench": 3}, {"palette": pal})
	var peds: Array = f["pedestals"]
	for i in peds.size():
		var pn := _st("pedestal", _v(peds[i]), {"occupied": i < 3})
		if i < 3:
			_place(ModelItems.build("ticket", {"family": all_f[i * 2]}), _v(peds[i]) + Vector3(0, pn.get_meta("top_y"), 0))
	_st("linen_shelf", _v(f["linen_shelf"]), {"count": 8, "pressing": true, "press_progress": 0.5})
	_st("hamper", _v(f["hamper"]), {"queue": 4, "washing": true, "cycle": 0.3, "full": false})
	_st("towel_shelf", _v(f["towel_shelf"]), {"count": 4, "tripped": false, "warn": false})
	_st("snack_tin", _v(f["snack_tin"]), {"count": 4, "tripped": false, "warn": true})
	_st("welcome_kiosk", _v(f["welcome_kiosk"]), {"selected": "ghost", "families": all_f, "needed": ["sprout"]}, {"palette": pal})
	_st("return_shelf", _v(f["return_shelf"]), {"curtains": 2, "curtain_system": true})
	_st("heat_pump", _v(f["heat_pump"]), {"enabled": true, "mode": "warm", "hot_demand": 3, "cold_demand": 1})
	_st("tap", _v(f["tap"]), {"enabled": true})
	var docks: Array = []
	for p in f.get("mop_docks", []):
		docks.append([p, "mop"])
	docks.append([f["breezer_dock"], "breezer"])
	for p2 in f.get("can_docks", []):
		docks.append([p2, "can"])
	for i in docks.size():
		var d: Array = docks[i]
		var occ := i == 0 or i == 2
		_st("tool_dock", _v(d[0]), {"occupied": occ, "enabled": i < 4}, {"tool": d[1], "index": i % 2})
		if occ:
			var tool_kind := "mop" if d[1] == "mop" else ("breezer" if d[1] == "breezer" else "watering_can")
			_place(ModelItems.build(tool_kind), _v(d[0]))
	_st("group_bell", _v(f["group_bell"]), {"ringing": true, "finish_ready": true})
	if tpl == "P6":
		_st("festival_stand", _v(f["festival_stand"]), {"enabled": true, "parcels": 3, "trunks": 1})
		_st("goal_pad", _v(f["goal_pad"]), {"enabled": true, "active": true})
		var tk := ModelItems.build("festival_trunk")
		_place(tk, Vector3(6.0, 0, 11.0))
	if L.shutter.x >= 0:
		_st("shutter", _v(L.shutter), {"state": "closed"}, {"axis": "z"})
	for i in L.lift_pads.size():
		_st("lift_pad", _v(L.lift_pads[i]), {"enabled": true, "busy": i == 0, "tripped": false}, {"index": i})
	var bed_states := ["Made", "Dirty", "Stripped"]
	var k := 0
	for letter in L.rooms:
		var g: Dictionary = L.rooms[letter]
		if not g["active"]:
			continue
		var rc: Color = Art.ROOM_COLORS[letter]
		var o := {"room_color": rc, "side": g["side"], "palette": pal}
		_st("bed", _v(g["bed"]), {"bed": bed_states[k % 3], "occupied": k % 3 == 0}, o)
		var pl := _st("plinth", _v(g["plinth"]), {}, o)
		_place(ModelItems.build("welcome_" + all_f[k % 6]), _v(g["plinth"]) + Vector3(0, pl.get_meta("top_y"), 0))
		_st("thermostat", _v(g["thermostat"]), {"enabled": true, "mode": ["neutral", "warm", "cool"][k % 3], "tripped": k == 4, "heat": (k - 2) * 30}, o)
		_st("water_tray", _v(g["tray"]), {"enabled": true, "wet": (k * 20) % 70, "humidity": 40}, o)
		_st("drop_pad", _v(g["drop"]), {}, o)
		_st("curtain_rail", _v(g["door"]), {"enabled": true, "installed": k % 2 == 0}, o)
		k += 1
	for e in L.thermal_edges:
		var gp: Vector2i = L.gates[e]
		_st("vent_gate", _v(gp), {"open": e != "BC", "flow": 0.6 if e != "EF" else -0.6}, {"facing": 1 if gp.y <= 9 else -1})
	# Scale references: staff holding items, guests, loose items.
	var cos_d := {"cap": "#E88D79", "scarf": "#E8BF66", "trim": "#F7EAD6"}
	var held := ["linen_clean", "towel", "welcome_dragon", "watering_can"]
	var starts: Array = f["staff_starts"]
	for i in starts.size():
		var r := ModelActors.staff(["pip", "pebble", "moss", "button"][i], cos_d)
		_place(r, _v(starts[i]) + Vector3(0, 0, 0.3))
		r.carrying = true
		r.tick(0.1)
		var it := ModelItems.build(held[i])
		it.scale = Vector3.ONE / ModelActors.ACTOR_SCALE
		r.hold.add_child(it)
	_place(ModelItems.build("linen_dirty"), Vector3(9.6, 0, 8.6))
	_place(ModelItems.build("snack"), Vector3(12.4, 0, 10.9))
	if hall:
		await get_tree().process_frame
		stage.set_bounds(Vector3(0.6, 0, 7.0), Vector3(27.0, 1.0, 12.4))

func _gallery_items(parts: Array) -> void:
	_floor_plate(40, 30)
	var kinds := ModelItems.kinds()
	var x := 2.0
	var z := 3.6
	var col := 0
	for kind in kinds:
		var extra := {}
		if kind == "ticket":
			extra = {"family": "moonwolf"}
		var n := ModelItems.build(kind, extra)
		var w := 2.2 if kind == "festival_trunk" else (1.3 if kind == "mop" else 0.85)
		_place(n, Vector3(x + w * 0.5, 0, z))
		x += w
		col += 1
		if col % 8 == 0:
			x = 2.0
			z += 1.0
	# Variants: open trunk, tickets per family, can charges, parcels.
	z += 1.1
	x = 2.0
	var tr := ModelItems.build("festival_trunk") as StationNode
	tr.apply({"open": true})
	_place(tr, Vector3(x + 1.0, 0, z))
	x += 2.3
	for fam in ["slime", "yeti", "dragon", "ghost", "moonwolf", "sprout"]:
		_place(ModelItems.build("ticket", {"family": fam}), Vector3(x, 0, z))
		x += 0.55
	for c in 4:
		_place(ModelItems.build("watering_can", {"charges": c}), Vector3(x + 0.1, 0, z))
		x += 0.6
	z += 0.9
	x = 2.0
	for i in 6:
		_place(ModelItems.build("festival_parcel", {"index": i}), Vector3(x + 0.3, 0, z))
		x += 0.6
	# Held aloft by staff.
	var cos_d := {"cap": "#E88D79", "scarf": "#E8BF66", "trim": "#F7EAD6"}
	var held := ["ticket", "linen_clean", "linen_dirty", "towel", "snack", "welcome_slime", "welcome_ghost", "curtain_roll", "breezer", "festival_parcel"]
	x += 0.4
	for i in held.size():
		var r := ModelActors.staff(["pip", "pebble", "moss", "button"][i % 4], cos_d)
		_place(r, Vector3(x, 0, z + 0.2))
		r.carrying = true
		r.tick(0.2)
		var it := ModelItems.build(held[i], {"family": "dragon"})
		it.scale = Vector3.ONE / ModelActors.ACTOR_SCALE
		r.hold.add_child(it)
		x += 0.8
	await get_tree().process_frame
	stage.set_bounds(Vector3(1.6, 0, 2.9), Vector3(maxf(x, 15.5), 1.2, z + 0.6))

func _gallery_props(parts: Array) -> void:
	_floor_plate(40, 30)
	var x := 2.0
	var z := 3.8
	var col := 0
	for kind in ModelProps.kinds():
		var w := 1.0
		if kind in ["checklist", "paper_moon", "thank_you_garland"]:
			w = 1.5
		_place(ModelProps.build(kind), Vector3(x + w * 0.5, 0, z))
		x += w
		col += 1
		if col % 8 == 0:
			x = 2.0
			z += 1.4
	await get_tree().process_frame
	stage.set_bounds(Vector3(1.6, 0, 3.0), Vector3(11.2, 1.3, z + 0.7))
