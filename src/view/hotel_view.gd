class_name HotelView
extends Node3D
## Renders a HotelSim state (local sim or online snapshot) into the pixel stage.
## Pure presentation: reads the state dictionary, never mutates it (§19.2).

const SEAT_COLORS := [Color("#F2C14E"), Color("#5FB6E8"), Color("#F07AA8"), Color("#8BD17C")]
const FIXTURE_Y := {"ped": 0.62, "plinth": 0.56, "dock": 0.0, "liftpad": 0.06}

var stage: PixelStage
var L: LayoutDef
var systems: Dictionary = {}
var cfg: Dictionary = {}
var stations: Dictionary = {}
var staff_rigs: Dictionary = {}
var guest_rigs: Dictionary = {}
var item_nodes: Dictionary = {}
var puddle_nodes: Dictionary = {}
var cloud_nodes: Dictionary = {}
var trunk_nodes: Dictionary = {}
var frost_nodes: Dictionary = {}
var mess_nodes: Dictionary = {}
var heat_tints: Dictionary = {}
var npcs: Dictionary = {}
var hotel_root: Node3D
var fx_root: Node3D
var _last: Dictionary = {}
var _this: Dictionary = {}
var _hl: Dictionary = {}          # seat -> {key, nodes}
var _bell_ring_t := 0.0
var _prebuilt: Dictionary = {}    # guest id -> hidden rig built at load
var _flow_arrows: Array = []
var _fx: Array = []               # transient effects [{node, t, life, kind, data}]
var local_seats: Array = []       # sim seats controlled on this machine (for highlights)
var reduced_motion := false
var s: Dictionary = {}            # latest state

func build(p_stage: PixelStage, layout: LayoutDef, sys: Dictionary, p_cfg: Dictionary) -> void:
	stage = p_stage
	L = layout
	systems = sys
	cfg = p_cfg
	name = "HotelView"
	stage.world.add_child(self)
	hotel_root = HotelBuilder.new().build(L, systems)
	add_child(hotel_root)
	fx_root = Node3D.new()
	fx_root.name = "FX"
	add_child(fx_root)
	_build_stations()
	_build_room_dressing()
	_merge_static_bodies()
	reduced_motion = bool(Settings.g("reduced_motion"))

## Every station's static "body" (one cached mesh per kind, never moved or
## toggled after build) is baked into a single floor mesh: one draw call and
## one shadow caster instead of ~60 of each. The original bodies stay in the
## tree, hidden, so interaction highlights can still outline them.
const _BODY_TOGGLED := ["goal_pad", "lift_pad"]
var _merged_bodies: Dictionary = {}   # MeshInstance3D -> true

func _merge_static_bodies() -> void:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
	var toon := Art.toon()
	var inv := global_transform.affine_inverse() if is_inside_tree() else Transform3D.IDENTITY
	for key in stations:
		var st = stations[key]
		if not st is StationNode or (st as StationNode).kind in _BODY_TOGGLED:
			continue
		var body: MeshInstance3D = st.parts.get("body")
		if body == null or body.mesh == null or body.material_override != toon or body.mesh.get_surface_count() != 1:
			continue
		var xf: Transform3D = (inv * body.global_transform) if body.is_inside_tree() else (st.transform * body.transform)
		var arr := body.mesh.surface_get_arrays(0)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var c: PackedColorArray = arr[Mesh.ARRAY_COLOR]
		var u = arr[Mesh.ARRAY_TEX_UV]
		if arr[Mesh.ARRAY_INDEX] != null or c.size() != v.size() or n.size() != v.size():
			continue
		var basis := xf.basis
		for i in v.size():
			verts.append(xf * v[i])
			norms.append((basis * n[i]).normalized())
		cols.append_array(c)
		if u is PackedVector2Array and (u as PackedVector2Array).size() == v.size():
			uvs.append_array(u)
		else:
			var pad := PackedVector2Array()
			pad.resize(v.size())
			uvs.append_array(pad)
		body.visible = false
		_merged_bodies[body] = true
		# The merged body carries the station's shadow; small moving parts don't need their own.
		for part in (st as Node).find_children("*", "MeshInstance3D", true, false):
			if part != body:
				(part as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if verts.is_empty():
		return
	var a: Array = []
	a.resize(Mesh.ARRAY_MAX)
	a[Mesh.ARRAY_VERTEX] = verts
	a[Mesh.ARRAY_NORMAL] = norms
	a[Mesh.ARRAY_COLOR] = cols
	a[Mesh.ARRAY_TEX_UV] = uvs
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
	var mi := Art.mesh_instance(m, toon)
	mi.name = "MergedStationBodies"
	add_child(mi)

func wall_material() -> ShaderMaterial:
	for c in hotel_root.get_children():
		if c.name == "Walls":
			return (c as MeshInstance3D).material_override
	return null

func _place(key: String, node: Node3D, pos: Vector3, rot_y := 0.0) -> void:
	node.position = pos
	node.rotation.y = rot_y
	add_child(node)
	stations[key] = node

func _v(t: Vector2i, y := 0.0) -> Vector3:
	return Vector3(t.x, y, t.y)

func _build_stations() -> void:
	var F: Dictionary = L.fixtures
	var pal := L.palette
	_place("reception", ModelStations.build("reception", {"palette": pal}), _v(F["reception"]))
	var peds: Array = F["pedestals"]
	for i in peds.size():
		_place("ped:%d" % i, ModelStations.build("pedestal", {}), _v(peds[i]))
	_place("linen", ModelStations.build("linen_shelf", {}), _v(F["linen_shelf"]))
	_place("hamper", ModelStations.build("hamper", {}), _v(F["hamper"]))
	_place("towels", ModelStations.build("towel_shelf", {}), _v(F["towel_shelf"]))
	_place("snacks", ModelStations.build("snack_tin", {}), _v(F["snack_tin"]))
	_place("kiosk", ModelStations.build("welcome_kiosk", {}), _v(F["welcome_kiosk"]))
	var ctrs: Array = F.get("counters", [])
	for i in ctrs.size():
		_place("counter:%d" % i, ModelStations.build("counter", {}), _v(ctrs[i]))
	# Fixtures a floor never uses may be absent (the v2 chapter-1 floor has no
	# heat pump, tap, breezer, cans or return shelf).
	if F.has("return_shelf"):
		_place("return", ModelStations.build("return_shelf", {}), _v(F["return_shelf"]))
	if F.has("heat_pump"):
		_place("pump", ModelStations.build("heat_pump", {}), _v(F["heat_pump"]))
	if F.has("tap"):
		_place("tap", ModelStations.build("tap", {}), _v(F["tap"]))
	var mops: Array = F["mop_docks"]
	for i in mops.size():
		_place("dock:mop:%d" % i, ModelStations.build("tool_dock", {"tool": "mop"}), _v(mops[i]))
	if F.has("breezer_dock"):
		_place("dock:breezer:0", ModelStations.build("tool_dock", {"tool": "breezer"}), _v(F["breezer_dock"]))
	var cans: Array = F.get("can_docks", [])
	for i in cans.size():
		_place("dock:can:%d" % i, ModelStations.build("tool_dock", {"tool": "can"}), _v(cans[i]))
	_place("bell", ModelStations.build("group_bell", {}), _v(F["group_bell"]))
	if F.has("festival_stand"):
		_place("stand", ModelStations.build("festival_stand", {}), _v(F["festival_stand"]))
	_place("goal_pad", ModelStations.build("goal_pad", {}), _v(F["goal_pad"], 0.01))
	_no_shadows(stations["goal_pad"])
	for i in L.lift_pads.size():
		_place("lift:%d" % i, ModelStations.build("lift_pad", {"index": i}), _v(L.lift_pads[i], 0.01))
	if L.shutter.x >= 0:
		_place("shutter", ModelStations.build("shutter", {}), _v(L.shutter))
	for e in L.thermal_edges:
		var gp: Vector2i = L.gates[e]
		var north := gp.y <= L.hall.position.y
		var pos := Vector3(gp.x, 0.0, gp.y + (-0.46 if north else 0.46))
		_place("gate:" + e, ModelStations.build("vent_gate", {"facing": 1 if north else -1}), pos)

func _build_room_dressing() -> void:
	for letter in L.rooms:
		var g: Dictionary = L.rooms[letter]
		if not g["active"]:
			continue
		var rc: Color = Art.ROOM_COLORS[letter]
		var opts := {"room_color": rc, "side": g["side"]}
		var flip := 0.0 if g["side"] == "north" else PI
		_place("bed:" + letter, ModelStations.build("bed", opts), _v(g["bed"]))
		_place("plinth:" + letter, ModelStations.build("plinth", opts), _v(g["plinth"]))
		var tp: Vector2i = g["thermostat"]
		_place("thermo:" + letter, ModelStations.build("thermostat", opts), Vector3(tp.x, 0, tp.y + (0.2 if g["side"] == "north" else -0.2)), flip)
		_place("tray:" + letter, ModelStations.build("water_tray", opts), _v(g["tray"]))
		_place("drop:" + letter, ModelStations.build("drop_pad", opts), _v(g["drop"], 0.01))
		_no_shadows(stations["drop:" + letter])
		_no_shadows(stations["tray:" + letter])
		_place("rail:" + letter, ModelStations.build("curtain_rail", opts), _v(g["door"]), flip)
		# Mess decals and heat tint overlay.
		var mess := Node3D.new()
		var mk := MeshKit.new()
		var r: Rect2i = g["rect"]
		var rng := RandomNumberGenerator.new()
		rng.seed = letter.hash()
		for i in 9:
			var px := r.position.x + 0.6 + rng.randf() * (r.size.x - 1.6)
			var pz := r.position.y + 0.6 + rng.randf() * (r.size.y - 1.6)
			mk.disc(Vector3(px, 0.02, pz), 0.12 + rng.randf() * 0.1, Color("#B9A58C"), 6)
			mk.sphere(Vector3(px + 0.15, 0.04, pz), 0.05, Color("#D8CBB5"), 2, 4)
		mess.add_child(Art.mesh_instance(mk.commit()))
		_no_shadows(mess)
		add_child(mess)
		mess_nodes[letter] = mess
		var tint := MeshInstance3D.new()
		var tm := MeshKit.new()
		tm.jitter = 0.0
		tm.flat(Vector3(r.position.x + (r.size.x - 1) * 0.5, 0.025, r.position.y + (r.size.y - 1) * 0.5), Vector2(r.size.x, r.size.y), Color.WHITE)
		tint.mesh = tm.commit()
		var fm := Art.fx(Color(1, 0.6, 0.5), 0.0)
		tint.material_override = fm
		tint.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(tint)
		heat_tints[letter] = tint

## Builds every scheduled guest's rig and every item mesh up front, so an
## arrival never stalls a frame on procedural mesh construction.
func prewarm(state: Dictionary) -> void:
	for gid in state.get("guests", {}):
		var key := int(gid)
		if guest_rigs.has(key) or _prebuilt.has(key):
			continue
		var g: Dictionary = state["guests"][gid]
		var rig := ModelActors.guest(g["fam"], g.get("var", ""))
		rig.visible = false
		add_child(rig)
		_prebuilt[key] = rig
	for kind in ModelItems.KINDS:
		ModelItems.build(kind).free()
	for fam in ModelItems.FAMILIES:
		ModelItems.build("ticket", {"family": fam}).free()

# ------------------------------------------------------------ interpolation

func capture_tick(state: Dictionary) -> void:
	s = state
	_last = _this
	_this = {}
	for st in state.get("staff", []):
		_this["s%d" % st["seat"]] = Vector2(st["x"], st["z"]) / 1_000_000.0
	for gid in state.get("guests", {}):
		var g: Dictionary = state["guests"][gid]
		_this["g%d" % int(gid)] = Vector2(g["x"], g["z"]) / 1_000_000.0
	for iid in state.get("items", {}):
		var it: Dictionary = state["items"][iid]
		if it["loc"] == "world":
			_this["i%d" % int(iid)] = Vector2(it["x"], it["z"]) / 1_000_000.0
	for tid in state.get("trunks", {}):
		var tr: Dictionary = state["trunks"][tid]
		_this["t%d" % int(tid)] = Vector2(tr["x"], tr["z"]) / 1_000_000.0
	var gus: Dictionary = state.get("gus", {})
	if gus.has("x"):
		var task: Dictionary = gus.get("task", {})
		var tx: float = float(task.get("tx", gus["x"])) / 1_000_000.0
		var tz: float = float(task.get("tz", gus["z"])) / 1_000_000.0
		_this["gus"] = Vector2(tx, tz)

func _ip(key: String, alpha: float) -> Vector2:
	var b: Vector2 = _this.get(key, Vector2.ZERO)
	var a: Vector2 = _last.get(key, b)
	if a.distance_to(b) > 2.0:
		return b
	return a.lerp(b, alpha)

# ------------------------------------------------------------ per frame

func sync(alpha: float, dt: float) -> void:
	if s.is_empty():
		return
	_sync_stations(dt)
	_sync_staff(alpha, dt)
	_sync_guests(alpha, dt)
	_sync_items(alpha)
	_sync_entities(alpha, dt)
	_sync_npcs(dt)
	_sync_flow(dt)
	_tick_fx(dt)
	var wm := wall_material()
	if wm:
		var pts: Array = []
		for st in s.get("staff", []):
			var p := _ip("s%d" % st["seat"], alpha)
			pts.append(Vector4(p.x, 0.5, p.y, 1.0))
		while pts.size() < 4:
			pts.append(Vector4(0, 0, 0, 0))
		wm.set_shader_parameter("fade_points", pts)

func _sync_stations(dt: float) -> void:
	for k in stations:
		var sn = stations[k]
		if sn.has_method("tick"):
			sn.tick(dt)
	var stv: Dictionary = s.get("st", {})
	var trips: Dictionary = stv.get("trips", {})
	var thermal := systems.has("thermal")
	var sound := systems.has("sound")
	var moist := systems.has("moisture")
	var work: Dictionary = s.get("work", {})
	_apply("reception", {"bench": s.get("bench", []).size()})
	var peds: Array = s.get("pedestals", [])
	for i in peds.size():
		_apply("ped:%d" % i, {"occupied": int(peds[i]) != 0})
	var press_p := 0.0
	if work.has("press"):
		press_p = float(work["press"]["p"]) / float(SimC.T_PRESS * 1000)
	_apply("linen", {"count": int(stv.get("linen", 0)), "pressing": work.has("press"), "press_progress": press_p})
	var hq := int(stv.get("hamper_q", 0))
	_apply("hamper", {"queue": hq, "washing": hq > 0, "cycle": float(stv.get("hamper_t", 0)) / SimC.HAMPER_CYCLE, "full": hq >= SimC.HAMPER_QUEUE_CAP})
	_apply("towels", {"count": int(stv.get("towels", 0)), "tripped": trips.has("towels"), "warn": _warned("towels")})
	_apply("snacks", {"count": int(stv.get("snacks", 0)), "tripped": trips.has("snacks"), "warn": _warned("snacks")})
	var fams: Array = s.get("_families", SimC.FAMILIES)
	var needed: Array = []
	for gid in s.get("guests", {}):
		var g: Dictionary = s["guests"][gid]
		if g["state"] in ["walking", "staying", "lobby"] and not g["welcomed"] and not g["fam"] in needed:
			needed.append(g["fam"])
	_apply("kiosk", {"selected": SimC.FAMILIES[int(stv.get("kiosk_sel", 0))], "families": fams, "needed": needed})
	_apply("return", {"curtains": int(stv.get("curtains_free", 0)), "curtain_system": sound})
	_apply("pump", {"enabled": thermal, "mode": stv.get("pump", "balanced"), "hot_demand": int(stv.get("hot_demand", 0)), "cold_demand": int(stv.get("cold_demand", 0))})
	_apply("tap", {"enabled": moist})
	for k in stations:
		if k.begins_with("dock:"):
			var parts: PackedStringArray = k.split(":")
			var enabled := true
			if parts[1] == "breezer": enabled = thermal or cfg.get("mode", "") == "playground"
			elif parts[1] == "can": enabled = moist and (int(parts[2]) == 0 or int(s.get("humans", 1)) >= 3)
			_apply(k, {"occupied": _docked(k) != 0, "enabled": enabled})
	if _bell_ring_t > 0.0:
		_bell_ring_t -= dt
	_apply("bell", {"ringing": _bell_ring_t > 0.0, "finish_ready": bool(s.get("_can_finish", false))})
	var parcels := 0
	var trunks := 0
	for k in s.get("goals", {}):
		var gl: Dictionary = s["goals"][k]
		if gl.get("done", false):
			if gl.get("kind", "") == "parcel": parcels += 1
			else: trunks += 1
	var fest := systems.has("festival")
	_apply("stand", {"enabled": fest, "parcels": parcels, "trunks": trunks})
	_apply("goal_pad", {"enabled": fest, "active": not s.get("trunks", {}).is_empty()})
	var lf: Dictionary = s.get("lifts", {})
	for i in L.lift_pads.size():
		_apply("lift:%d" % i, {"enabled": systems.has("lift"), "busy": bool(lf.get("busy", false)), "tripped": trips.has("lift_pair")})
	if stations.has("shutter"):
		_apply("shutter", {"state": s.get("shutter", {}).get("state", "open")})
	for e in L.thermal_edges:
		var open: bool = s.get("gates", {}).get(e, false)
		var ab := L.edge_rooms(e)
		var ra: Dictionary = s["rooms"].get(ab[0], {})
		var rb: Dictionary = s["rooms"].get(ab[1], {})
		var flow := 0.0
		if open and not ra.is_empty():
			flow = clampf((float(rb["heat"]) - float(ra["heat"])) / 60.0, -1.0, 1.0)
		_apply("gate:" + e, {"open": open, "flow": flow})
	for letter in L.rooms:
		if not L.rooms[letter]["active"]:
			continue
		var r: Dictionary = s["rooms"][letter]
		_apply("bed:" + letter, {"bed": r["bed"], "occupied": int(r["guest"]) != 0})
		_apply("plinth:" + letter, {})
		_apply("thermo:" + letter, {"enabled": thermal, "mode": r["thermo"], "tripped": trips.has("radiator_" + letter), "heat": int(r["heat"])})
		_apply("tray:" + letter, {"enabled": moist, "wet": int(r["tray"]), "humidity": int(r["hum"])})
		_apply("drop:" + letter, {})
		_apply("rail:" + letter, {"enabled": sound, "installed": int(r["curtain"]) != 0})
		var mn: Node3D = mess_nodes[letter]
		mn.visible = int(r["mess"]) > 0
		if mn.visible:
			var k2 := 0.5 + 0.5 * float(r["mess"]) / 100.0
			mn.scale = Vector3(1.0, 1.0, 1.0) * 1.0
			for c in mn.get_children():
				(c as Node3D).scale = Vector3(k2, 1.0, k2)
		var tint: MeshInstance3D = heat_tints[letter]
		var h := float(r["heat"])
		var mat: ShaderMaterial = tint.material_override
		if thermal and absf(h) > 12.0:
			var col := Art.WARM if h > 0 else Art.COLD
			mat.set_shader_parameter("color", col)
			mat.set_shader_parameter("alpha", clampf((absf(h) - 12.0) / 150.0, 0.0, 0.28))
		else:
			mat.set_shader_parameter("alpha", 0.0)

func _warned(fixture: String) -> bool:
	return s.get("_warn_fixtures", {}).has(fixture)

func _apply(key: String, st: Dictionary) -> void:
	var n = stations.get(key, null)
	if n != null and n.has_method("apply"):
		n.apply(st)

func _docked(key: String) -> int:
	var sock := key
	for iid in s.get("items", {}):
		var it: Dictionary = s["items"][iid]
		if it["loc"] == "sock" and it["sock"] == sock:
			return int(iid)
	return 0

func _sync_staff(alpha: float, dt: float) -> void:
	for st in s.get("staff", []):
		var seat: int = st["seat"]
		if not staff_rigs.has(seat):
			var cos := _cosmetic(st.get("cos", "default"))
			var rig := ModelActors.staff(st["char"], cos)
			add_child(rig)
			staff_rigs[seat] = rig
			rig.reduced_motion = reduced_motion
			_add_seat_marker(rig, seat)
		var rig2: ActorRig = staff_rigs[seat]
		var p := _ip("s%d" % seat, alpha)
		rig2.position = Vector3(p.x, 0.0, p.y)
		rig2.visible = not st.get("riding", false)
		var spd := Vector2(st["vx"], st["vz"]).length() / 1_000_000.0 * SimC.TICK_HZ
		if st["grip"] != 0 and st.get("moving", false):
			spd = 1.4
		rig2.speed = spd
		if st["fx"] != 0 or st["fz"] != 0:
			rig2.face_dir = atan2(float(st["fx"]), float(st["fz"]))
		rig2.carrying = int(st["held"]) != 0 or int(st["grip"]) != 0
		var a := "idle"
		var act: Dictionary = st.get("act", {})
		if st["work_key"] != "":
			a = "mop" if str(st["work_key"]).begins_with("mess:") or str(st["work_key"]).begins_with("puddle:") else "work"
		elif not act.is_empty():
			match act.get("kind", ""):
				"handoff": a = "handoff"
				"dispense", "curtain_off": a = "work"
				"assign", "fulfill": a = "handoff"
		elif s.get("phase", "") == "wrap" or s.get("phase", "") == "done":
			a = "happy"
		if not st["present"]:
			a = "concern"
		rig2.set_anim(a)
		rig2.tick(dt)
		var transp: bool = int(st.get("transp_t", 0)) > 0 or not st["present"]
		_set_dither(rig2, 0.55 if transp else 1.0)

func _add_seat_marker(rig: ActorRig, seat: int) -> void:
	var mk := MeshKit.new()
	mk.jitter = 0.0
	mk.disc(Vector3(0, 0.02, 0), 0.36, SEAT_COLORS[seat % 4], 10, 0.27)
	var mi := MeshInstance3D.new()
	mi.mesh = mk.commit()
	mi.material_override = Art.fx(Color.WHITE, 0.9)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.name = "SeatRing"
	rig.add_child(mi)
	mi.scale = Vector3.ONE / ModelActors.ACTOR_SCALE

func _set_dither(rig: Node3D, a: float) -> void:
	if rig.get_meta("dither", 1.0) == a:
		return
	rig.set_meta("dither", a)
	for mi in _meshes(rig):
		if mi.name == "SeatRing":
			continue
		if a >= 0.999:
			mi.material_override = Art.toon()
		else:
			var m := Art.toon_unique()
			m.set_shader_parameter("dither_alpha", a)
			mi.material_override = m

## Small props skip the shadow pass (halves their draw calls; §19.6 budget).
func _no_shadows(n: Node) -> void:
	for mi in _meshes(n):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _meshes(n: Node) -> Array:
	var out: Array = []
	for c in n.get_children():
		if c is MeshInstance3D:
			out.append(c)
		out.append_array(_meshes(c))
	return out

func _cosmetic(id: String) -> Dictionary:
	for cs in Content.cosmetics:
		if cs["id"] == id:
			return cs
	return Content.cosmetics[0] if not Content.cosmetics.is_empty() else {}

func _sync_guests(alpha: float, dt: float) -> void:
	var seen := {}
	for gid in s.get("guests", {}):
		var g: Dictionary = s["guests"][gid]
		var visible: bool = g["state"] in ["lobby", "walking", "staying", "departing", "cozy"]
		if not visible:
			continue
		var key := int(gid)
		seen[key] = true
		if not guest_rigs.has(key):
			var rig: ActorRig = _prebuilt.get(key, null)
			if rig != null:
				_prebuilt.erase(key)
				rig.visible = true
			else:
				rig = ModelActors.guest(g["fam"], g.get("var", ""))
				add_child(rig)
			rig.reduced_motion = reduced_motion
			guest_rigs[key] = rig
			if g["fam"] == "ghost":
				_set_dither(rig, 0.88)
			_spawn_fx("sparkle", Vector3(float(g["x"]) / 1e6, 0.6, float(g["z"]) / 1e6), Art.GOLD)
		var r: ActorRig = guest_rigs[key]
		var p := _ip("g%d" % key, alpha)
		var pos := Vector3(p.x, 0.0, p.y)
		r.position = pos
		var moving: bool = g.get("anim", "idle") == "walk" and g["state"] in ["walking", "departing", "cozy", "lobby"] and int(g.get("pi", 0)) < g.get("path", []).size()
		if g["state"] == "staying" and g.get("relocating", false):
			moving = true
		r.speed = 1.8 if moving else 0.0
		if moving:
			var prev: Vector2 = _last.get("g%d" % key, p)
			var d := p - prev
			if d.length() > 0.001:
				r.face_dir = atan2(d.x, d.y)
		else:
			r.face_dir = 0.0
		var a := "idle"
		match g["state"]:
			"staying":
				if not moving:
					a = "idle"
					if g.get("mood", "") == "delighted": a = "happy" if int(Time.get_ticks_msec() / 2600 + key) % 4 == 0 else "idle"
					elif g.get("mood", "") == "inconvenienced": a = "concern"
					if g.get("helper_ready", false): a = "helper" if int(Time.get_ticks_msec() / 1800 + key) % 3 == 0 else a
			"departing":
				a = "wave" if not moving else "idle"
			"cozy":
				a = "sit" if not moving else "idle"
			"lobby":
				a = "wave" if int(Time.get_ticks_msec() / 3000 + key) % 5 == 0 and not moving else "idle"
		var q: String = r.get_meta("quirk_anim", "")
		if q != "" and float(r.get_meta("quirk_until", 0.0)) > Time.get_ticks_msec() / 1000.0:
			a = q
		if s.get("phase", "") == "wrap":
			a = "wave"
		r.set_anim(a)
		if r.extras.has("slippers"):
			(r.extras["slippers"] as Node3D).visible = g.get("slippers_on", false)
		if r.extras.has("mask"):
			(r.extras["mask"] as Node3D).visible = g.get("welcomed", false)
		r.tick(dt)
	for key in guest_rigs.keys():
		if not seen.has(key):
			var rr: ActorRig = guest_rigs[key]
			_spawn_fx("sparkle", rr.position + Vector3(0, 0.6, 0), Art.CREAM)
			rr.queue_free()
			guest_rigs.erase(key)

func guest_rig(gid: int) -> ActorRig:
	return guest_rigs.get(gid, null)

func _sync_items(alpha: float) -> void:
	var seen := {}
	var bench_n := 0
	for iid in s.get("items", {}):
		var it: Dictionary = s["items"][iid]
		var key := int(iid)
		seen[key] = true
		if not item_nodes.has(key):
			var extra := {}
			if it["k"] == "ticket":
				var g: Dictionary = s.get("guests", {}).get(int(it.get("g", 0)), {})
				extra["family"] = g.get("fam", "slime")
			if it["k"] == "festival_parcel":
				extra["index"] = key % 3
			var node := ModelItems.build(it["k"], extra)
			_no_shadows(node)
			add_child(node)
			item_nodes[key] = node
		var n: Node3D = item_nodes[key]
		if n.has_method("apply") and it["k"] == "watering_can":
			n.apply({"charges": int(it.get("ch", 0))})
		if n.has_method("apply") and it["k"] == "breezer":
			var holder: Dictionary = {}
			for stf in s.get("staff", []):
				if int(stf["held"]) == key:
					holder = stf
			n.apply({"active": not holder.is_empty() and str(holder.get("work_key", "")).begins_with("cloud:")})
		if n.has_method("tick"):
			n.tick(get_process_delta_time())
		var loc: String = it["loc"]
		n.visible = true
		match loc:
			"held":
				var seat := int(it["seat"])
				var rig: ActorRig = staff_rigs.get(seat, null)
				if rig != null:
					var hp := rig.hold.global_position
					n.global_position = hp
					n.rotation = Vector3(0, rig.rotation.y, 0)
					n.visible = rig.visible
			"world":
				var p := _ip("i%d" % key, alpha)
				n.position = Vector3(p.x, 0.0, p.y)
				n.rotation = Vector3(0, float((key * 37) % 360) * 0.0174, 0)
			"sock":
				var sock: String = it["sock"]
				n.rotation = Vector3.ZERO
				if sock.begins_with("ped:"):
					var pi := int(sock.substr(4))
					var pp: Vector2i = L.fixtures["pedestals"][pi]
					n.position = Vector3(pp.x, FIXTURE_Y["ped"], pp.y + 0.05)
				elif sock == "bench":
					var rp: Vector2i = L.fixtures["reception"]
					n.position = Vector3(rp.x - 0.15 + bench_n * 0.08, 0.92 + bench_n * 0.02, rp.y)
					bench_n += 1
				elif sock.begins_with("dock:"):
					var dn: Node3D = stations.get(sock, null)
					if dn != null:
						n.position = dn.position + Vector3(0, 0.02, 0.1)
				elif sock.begins_with("plinth:"):
					var pn: Node3D = stations.get(sock, null)
					if pn != null:
						n.position = pn.position + Vector3(0, float(pn.get_meta("top_y", FIXTURE_Y["plinth"])), 0)
				elif sock.begins_with("liftpad:"):
					var ln: Node3D = stations.get("lift:" + sock.substr(8), null)
					if ln != null:
						n.position = ln.position + Vector3(0, FIXTURE_Y["liftpad"], 0)
				elif sock.begins_with("counter:"):
					var cn: Node3D = stations.get(sock, null)
					if cn != null:
						n.position = cn.position + Vector3(0, float(cn.get_meta("top_y", 0.65)), 0)
				elif sock.begins_with("counter:"):
					var cn: Node3D = stations.get(sock, null)
					if cn != null:
						n.position = cn.position + Vector3(0, float(cn.get_meta("top_y", 0.65)), 0)
				elif sock.begins_with("curtain:"):
					n.visible = false
				else:
					n.visible = false
			_:
				n.visible = false
	for key in item_nodes.keys():
		if not seen.has(key):
			(item_nodes[key] as Node3D).queue_free()
			item_nodes.erase(key)

func _sync_entities(alpha: float, dt: float) -> void:
	# Puddles
	var seen := {}
	for pid in s.get("puddles", {}):
		var p: Dictionary = s["puddles"][pid]
		var key := int(pid)
		seen[key] = true
		if not puddle_nodes.has(key):
			var n := _make_puddle()
			add_child(n)
			puddle_nodes[key] = n
			n.scale = Vector3(0.2, 1, 0.2)
		var pn: Node3D = puddle_nodes[key]
		pn.position = Vector3(float(p["x"]) / 1e6, 0.0, float(p["z"]) / 1e6)
		pn.scale = pn.scale.lerp(Vector3.ONE, minf(1.0, dt * 8.0))
	for key in puddle_nodes.keys():
		if not seen.has(key):
			_spawn_fx("sparkle", (puddle_nodes[key] as Node3D).position + Vector3(0, 0.2, 0), Art.WATER)
			(puddle_nodes[key] as Node3D).queue_free()
			puddle_nodes.erase(key)
	# Steam clouds
	seen = {}
	for cid in s.get("clouds", {}):
		var c: Dictionary = s["clouds"][cid]
		var key2 := int(cid)
		seen[key2] = true
		if not cloud_nodes.has(key2):
			var n2 := _make_cloud(key2)
			add_child(n2)
			cloud_nodes[key2] = n2
		var cn: Node3D = cloud_nodes[key2]
		var life := float(c.get("life", 18)) / float(SimC.STEAM_LIFE_S)
		cn.position = Vector3(float(c["x"]) / 1e6, 0.7 + 0.05 * sin(Time.get_ticks_msec() / 500.0 + key2), float(c["z"]) / 1e6)
		# Big enough to read as a warning at 360 lines (§17.6), shrinking as it fades.
		var sc := clampf(0.9 + life * 0.6, 0.9, 1.5)
		cn.scale = cn.scale.lerp(Vector3(sc, sc, sc), minf(1.0, dt * 4.0))
		cn.rotation.y += dt * 0.3
	for key2 in cloud_nodes.keys():
		if not seen.has(key2):
			(cloud_nodes[key2] as Node3D).queue_free()
			cloud_nodes.erase(key2)
	# Frost at doors
	for letter in L.rooms:
		if not L.rooms[letter]["active"]:
			continue
		var frozen: bool = s["rooms"][letter].get("frost", false)
		if frozen and not frost_nodes.has(letter):
			var fnode := _make_frost(letter)
			add_child(fnode)
			frost_nodes[letter] = fnode
		elif not frozen and frost_nodes.has(letter):
			_spawn_fx("sparkle", (frost_nodes[letter] as Node3D).position + Vector3(0, 0.4, 0), Art.COLD)
			(frost_nodes[letter] as Node3D).queue_free()
			frost_nodes.erase(letter)
	# Trunks
	for tid in s.get("trunks", {}):
		var tr: Dictionary = s["trunks"][tid]
		var key3 := int(tid)
		if not trunk_nodes.has(key3):
			var tn := ModelItems.build("festival_trunk", {})
			add_child(tn)
			trunk_nodes[key3] = tn
		var tnode: Node3D = trunk_nodes[key3]
		var tp := _ip("t%d" % key3, alpha)
		tnode.position = Vector3(tp.x, 0.0, tp.y)
		if tnode.has_method("apply"):
			tnode.apply({"open": tr.get("delivered", false)})

func _make_puddle() -> Node3D:
	var root := Node3D.new()
	var mk := MeshKit.new()
	mk.jitter = 0.0
	mk.push_at(Vector3.ZERO, Vector3.ZERO, Vector3(1.0, 1.0, 0.75))
	mk.disc(Vector3(0, 0.015, 0), 0.42, Color("#8FCBE0"), 12)
	mk.disc(Vector3(0.08, 0.02, -0.06), 0.18, Color("#CDEFF8"), 8)
	mk.disc(Vector3(-0.2, 0.018, 0.12), 0.07, Color("#CDEFF8"), 6)
	mk.pop()
	var mi := Art.mesh_instance(mk.commit())
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	return root

func _make_cloud(seed_v: int) -> Node3D:
	var root := Node3D.new()
	var mk := MeshKit.new()
	mk.jitter = 0.05
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	# A puffy cloud that (comically) resembles a sock.
	var pts := [Vector3(-0.35, 0.0, 0), Vector3(-0.1, 0.05, 0.05), Vector3(0.15, 0.0, 0), Vector3(0.35, -0.12, 0.05), Vector3(0.45, -0.38, 0), Vector3(0.28, -0.45, 0.06)]
	for p in pts:
		mk.sphere(p, 0.26 + rng.randf() * 0.08, Color("#F4F6FA"), 3, 7)
	var mi := MeshInstance3D.new()
	mi.mesh = mk.commit()
	var mat := Art.toon_unique()
	mat.set_shader_parameter("dither_alpha", 0.72 if not Settings.g("reduced_transparency") else 0.9)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	return root

func _make_frost(letter: String) -> Node3D:
	var g: Dictionary = L.rooms[letter]
	var d: Vector2i = g["door"]
	var root := Node3D.new()
	root.position = Vector3(d.x, 0.0, d.y)
	var mk := MeshKit.new()
	mk.disc(Vector3(0, 0.02, 0), 0.6, Color("#D7F0FA"), 10)
	for i in 6:
		var a := TAU * i / 6.0
		mk.cone(Vector3(cos(a) * 0.35, 0.02, sin(a) * 0.35), 0.06, 0.18, Color("#BFE6F5"), 4)
	# Frozen bell ornament on the frame ("ting…k").
	mk.sphere(Vector3(0.0, 1.2, 0.0), 0.12, Color("#E6F7FD"), 3, 6)
	mk.cone(Vector3(0.0, 1.05, 0.0), 0.05, -0.18, Color("#BFE6F5"), 4)
	root.add_child(Art.mesh_instance(mk.commit()))
	return root

func _sync_npcs(dt: float) -> void:
	var gus: Dictionary = s.get("gus", {})
	if gus.get("on", false):
		if not npcs.has("gus"):
			var r := ModelActors.npc("gus")
			add_child(r)
			npcs["gus"] = r
			var hp: Vector2i = L.fixtures["linen_shelf"]
			r.position = Vector3(hp.x, 0, hp.y + 0.65)
		var gr: ActorRig = npcs["gus"]
		var target: Vector2 = _this.get("gus", Vector2(gr.position.x, gr.position.z))
		var cur := Vector2(gr.position.x, gr.position.z)
		var d := target - cur
		var task: Dictionary = gus.get("task", {})
		if d.length() > 0.08:
			var stepv := minf(d.length(), dt * 2.4)
			cur += d.normalized() * stepv
			gr.speed = 2.0
			gr.face_dir = atan2(d.x, d.y)
		else:
			gr.speed = 0.0
		gr.position = Vector3(cur.x, 0, cur.y)
		gr.set_anim("work" if not task.is_empty() and d.length() <= 0.08 else "idle")
		gr.tick(dt)
	elif npcs.has("gus"):
		(npcs["gus"] as Node3D).queue_free()
		npcs.erase("gus")
	if not npcs.has("nana"):
		var n := ModelActors.npc("nana")
		add_child(n)
		npcs["nana"] = n
		var rp: Vector2i = L.fixtures["reception"]
		n.position = Vector3(rp.x - 1.05, 0, rp.y - 0.15)
		n.face_dir = PI * 0.5
	var nana: ActorRig = npcs["nana"]
	if nana.get_meta("anim_until", 0.0) < Time.get_ticks_msec() / 1000.0:
		nana.set_anim("idle")
	nana.tick(dt)

func nana_react(anim: String, secs := 1.4) -> void:
	if npcs.has("nana"):
		var n: ActorRig = npcs["nana"]
		n.set_anim(anim)
		n.set_meta("anim_until", Time.get_ticks_msec() / 1000.0 + secs)

# ------------------------------------------------------------ thermal flow

func _sync_flow(dt: float) -> void:
	if not systems.has("thermal"):
		return
	if _flow_arrows.is_empty():
		for e in L.thermal_edges:
			for k in 3:
				var mk := MeshKit.new()
				mk.jitter = 0.0
				mk.cone(Vector3(0, 0, 0), 0.07, 0.2, Color.WHITE, 4)
				var mi := MeshInstance3D.new()
				mi.mesh = mk.commit()
				mi.rotation_degrees = Vector3(0, 0, -90)
				mi.material_override = Art.fx(Color.WHITE, 1.0)
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				add_child(mi)
				_flow_arrows.append({"edge": e, "k": k, "node": mi})
	var t := Time.get_ticks_msec() / 1000.0
	for fa in _flow_arrows:
		var e: String = fa["edge"]
		var mi2: MeshInstance3D = fa["node"]
		var open: bool = s.get("gates", {}).get(e, false)
		var ab := L.edge_rooms(e)
		var ha := float(s["rooms"][ab[0]]["heat"])
		var hb := float(s["rooms"][ab[1]]["heat"])
		var diff := hb - ha
		if not open or absf(diff) < 6.0 or reduced_motion:
			mi2.visible = false
			continue
		mi2.visible = true
		var ga: Dictionary = L.rooms[ab[0]]
		var gb: Dictionary = L.rooms[ab[1]]
		var north: bool = ga["side"] == "north"
		var z := float(L.hall_north_wall_z() if north else L.hall_south_wall_z())
		var y := HotelBuilder.wall_height_for(L, 0, int(z)) + 0.3
		var xa := float(ga["rect"].position.x + ga["rect"].size.x - 1)
		var xb := float(gb["rect"].position.x)
		var from := xb if diff > 0 else xa
		var to := xa if diff > 0 else xb
		var f := fmod(t * 0.6 + fa["k"] / 3.0, 1.0)
		mi2.position = Vector3(lerpf(from, to, f), y, z)
		mi2.rotation_degrees = Vector3(0, 0, -90 if to > from else 90)
		(mi2.material_override as ShaderMaterial).set_shader_parameter("color", Art.WARM if (hb > ha) == (diff > 0) and maxf(ha, hb) > 0 else Art.COLD)

# ------------------------------------------------------------ highlights

func set_highlight(seat: int, key: String, ok: bool) -> void:
	var cur: Dictionary = _hl.get(seat, {})
	if cur.get("key", "") == key and cur.get("ok", true) == ok:
		return
	for mi in cur.get("nodes", []):
		if is_instance_valid(mi):
			(mi as MeshInstance3D).material_overlay = null
			if _merged_bodies.has(mi) and not _highlighted_elsewhere(mi, seat):
				(mi as MeshInstance3D).visible = false
	var nodes: Array = []
	var target := node_for_key(key)
	if target != null:
		var col: Color = SEAT_COLORS[seat % 4] if ok else Color("#B9B2C8")
		for mi in _meshes(target):
			if mi.name == "SeatRing":
				continue
			mi.material_overlay = Art.hull(col, 0.035)
			if _merged_bodies.has(mi):
				mi.visible = true   # draw the hidden body only while it is outlined
			nodes.append(mi)
	_hl[seat] = {"key": key, "ok": ok, "nodes": nodes}

func _highlighted_elsewhere(mi: MeshInstance3D, except_seat: int) -> bool:
	for s in _hl:
		if s != except_seat and mi in _hl[s].get("nodes", []):
			return true
	return false

func node_for_key(key: String) -> Node3D:
	if key == "":
		return null
	var p := key.split(":")
	var kind := p[0]
	match kind:
		"pick":
			return item_nodes.get(int(p[1]), null)
		"ped":
			for iid in s.get("items", {}):
				var it: Dictionary = s["items"][iid]
				if it["loc"] == "sock" and it["sock"] == "ped:" + p[1]:
					return item_nodes.get(int(iid), null)
			return stations.get("ped:" + p[1], null)
		"bench": return stations.get("reception", null)
		"counter":
			for iid in s.get("items", {}):
				var it: Dictionary = s["items"][iid]
				if it["loc"] == "sock" and it["sock"] == key:
					return item_nodes.get(int(iid), null)
			return stations.get(key, null)
		"counter":
			for iid in s.get("items", {}):
				var it: Dictionary = s["items"][iid]
				if it["loc"] == "sock" and it["sock"] == key:
					return item_nodes.get(int(iid), null)
			return stations.get(key, null)
		"st":
			var map := {"linen": "linen", "towels": "towels", "snacks": "snacks", "kiosk": "kiosk", "return": "return", "hamper": "hamper", "stand": "stand"}
			return stations.get(map.get(p[1], p[1]), null)
		"dock":
			var tool := _docked(key)
			return item_nodes.get(tool, stations.get(key, null)) if tool != 0 else stations.get(key, null)
		"plinth", "thermo", "tray":
			if kind == "plinth" and int(s["rooms"][p[1]].get("gift", 0)) != 0:
				return item_nodes.get(int(s["rooms"][p[1]]["gift"]), stations.get(key, null))
			return stations.get(kind + ":" + p[1], null)
		"strip", "make": return stations.get("bed:" + p[1], null)
		"mess": return mess_nodes.get(p[1], null)
		"hang", "curtain_off": return stations.get("rail:" + p[1], null)
		"gate": return stations.get(key, null)
		"pump": return stations.get("pump", null)
		"tap": return stations.get("tap", null)
		"press": return stations.get("linen", null)
		"kiosk_cycle": return stations.get("kiosk", null)
		"bell": return stations.get("bell", null)
		"guest", "helper", "goodbye": return guest_rigs.get(int(p[1]), null)
		"staff": return staff_rigs.get(int(p[1]), null)
		"puddle": return puddle_nodes.get(int(p[1]), null)
		"cloud": return cloud_nodes.get(int(p[1]), null)
		"frost": return frost_nodes.get(p[1], null)
		"handle": return trunk_nodes.get(int(p[1]), null)
		"lift", "lift_send", "lift_ride": return stations.get("lift:" + p[1], null)
		"trip":
			var fx: String = p[1]
			if fx.begins_with("radiator_"): return stations.get("thermo:" + fx.substr(9), null)
			if fx == "towels": return stations.get("towels", null)
			if fx == "snacks": return stations.get("snacks", null)
			return stations.get("lift:0", null)
	return null

## World anchor for a target key (for HUD prompts and progress rings).
func anchor_for_key(key: String) -> Vector3:
	var n := node_for_key(key)
	if n != null:
		return n.global_position + Vector3(0, 1.0, 0)
	var p := key.split(":")
	if p.size() > 1 and L.rooms.has(p[1]):
		var d: Vector2i = L.rooms[p[1]]["door"]
		return Vector3(d.x, 1.0, d.y)
	return Vector3.ZERO

# ------------------------------------------------------------ events → FX

func on_events(events: Array) -> void:
	for e in events:
		match e["type"]:
			"bell":
				_bell_ring_t = 1.0
			"sound_pulse":
				_sound_fx(e)
			"handoff":
				var a: ActorRig = staff_rigs.get(int(e["from"]), null)
				var b: ActorRig = staff_rigs.get(int(e["to"]), null)
				if a and b:
					_spawn_fx("ribbon", a.position + Vector3(0, 1.0, 0), Art.CORAL, {"to": b.position + Vector3(0, 1.0, 0)})
			"welcome":
				var gr: ActorRig = guest_rigs.get(int(e["guest"]), null)
				if gr:
					_spawn_fx("confetti", gr.position + Vector3(0, 1.0, 0), Art.GOLD)
					_quirk_anim(gr, "happy", 1.4)
				nana_react("happy")
			"request_done":
				var gr2: ActorRig = guest_rigs.get(int(e["guest"]), null)
				if gr2:
					_spawn_fx("heart", gr2.position + Vector3(0, 1.4, 0), Art.CORAL)
					_quirk_anim(gr2, "happy", 1.0)
			"shared_work":
				var k: String = e.get("key", "")
				_spawn_fx("heart", anchor_for_key(k), Art.ROSE)
			"incident_warn":
				var gr3: ActorRig = guest_rigs.get(int(e.get("guest", 0)), null)
				if gr3:
					_quirk_anim(gr3, "quirk_warn", 4.0)
			"incident":
				var gr4: ActorRig = guest_rigs.get(int(e.get("guest", 0)), null)
				if gr4:
					_quirk_anim(gr4, "quirk", 0.9)
				if e.get("kind", "") in ["sneeze", "hiccup"]:
					var room: String = e.get("room", "")
					if L.rooms.has(room):
						var bp: Vector2i = L.rooms[room]["bed"]
						_spawn_fx("puff", Vector3(bp.x, 1.0, bp.y + 0.6), Art.COLD if e["kind"] == "sneeze" else Art.WARM)
			"quirk_cosmetic":
				var gr5: ActorRig = guest_rigs.get(int(e.get("guest", 0)), null)
				if gr5:
					_quirk_anim(gr5, "quirk", 1.0)
					_spawn_fx("sparkle", gr5.position + Vector3(0, 1.2, 0), Art.CREAM)
			"helper":
				var gr6: ActorRig = guest_rigs.get(int(e.get("guest", 0)), null)
				if gr6:
					_quirk_anim(gr6, "helper", 1.5)
					_spawn_fx("heart", gr6.position + Vector3(0, 1.5, 0), Art.GOLD)
			"guest_sparkle":
				var gr7: ActorRig = guest_rigs.get(int(e.get("id", 0)), null)
				if gr7:
					_spawn_fx("sparkle", gr7.position + Vector3(0, 0.6, 0), Art.GOLD)
			"trunk_delivered", "parcel_installed":
				var st_node: Node3D = stations.get("stand", null)
				if st_node:
					_spawn_fx("confetti", st_node.position + Vector3(0, 1.4, 0), Art.GOLD)
			"cozy_departure", "balanced":
				pass
			"assign":
				nana_react("wave", 1.0)

func _quirk_anim(r: ActorRig, a: String, secs: float) -> void:
	r.set_meta("quirk_anim", a)
	r.set_meta("quirk_until", Time.get_ticks_msec() / 1000.0 + secs)

func _sound_fx(e: Dictionary) -> void:
	var src: String = e["room"]
	if not L.rooms.has(src):
		return
	var g: Dictionary = L.rooms[src]
	var bp: Vector2i = g["bed"]
	var amp := float(e.get("own", e.get("amp", 60)))
	_spawn_fx("note", Vector3(bp.x, 1.3, bp.y), Art.SOUND, {"scale": clampf(amp / 60.0, 0.3, 1.4)})
	var recv: Dictionary = e.get("recv", {})
	for dst in recv:
		var gd: Dictionary = L.rooms[dst]
		var dp: Vector2i = gd["bed"]
		var amt := float(recv[dst])
		_spawn_fx("note_travel", Vector3(g["door"].x, 1.2, g["door"].y), Art.SOUND,
			{"to": Vector3(gd["door"].x, 1.2, gd["door"].y), "scale": clampf(amp / 60.0, 0.4, 1.3), "end_scale": clampf(amt / 60.0, 0.15, 1.2)})

func _note_mesh(col: Color) -> Mesh:
	var mk := MeshKit.new()
	mk.jitter = 0.0
	mk.sphere(Vector3(0, 0, 0), 0.14, col, 3, 6, Vector3(1.2, 0.9, 0.6))
	mk.box(Vector3(0.13, 0.26, 0), Vector3(0.04, 0.5, 0.04), col.darkened(0.2))
	mk.box(Vector3(0.22, 0.45, 0), Vector3(0.18, 0.06, 0.04), col.darkened(0.2))
	return mk.commit()

func _spawn_fx(kind: String, pos: Vector3, col: Color, data := {}) -> void:
	if reduced_motion and kind in ["confetti"]:
		kind = "sparkle"
	var node := Node3D.new()
	node.position = pos
	var life := 1.0
	match kind:
		"sparkle", "confetti":
			var n := 6 if kind == "sparkle" else 12
			for i in n:
				var mk := MeshKit.new()
				mk.jitter = 0.0
				var c: Color = col if kind == "sparkle" else [Art.CORAL, Art.GOLD, Art.SKY, Art.SAGE, Art.PLUM][i % 5]
				mk.box(Vector3.ZERO, Vector3(0.08, 0.08, 0.02), c)
				var mi := MeshInstance3D.new()
				mi.mesh = mk.commit()
				mi.material_override = Art.fx(Color.WHITE, 1.0)
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				var a := TAU * i / n
				mi.set_meta("v", Vector3(cos(a) * 1.2, 1.6 + 0.4 * (i % 3), sin(a) * 1.2) * (0.6 if kind == "sparkle" else 1.0))
				node.add_child(mi)
			life = 0.8 if kind == "sparkle" else 1.2
		"heart", "puff", "note":
			var mk2 := MeshKit.new()
			mk2.jitter = 0.0
			if kind == "heart":
				mk2.sphere(Vector3(-0.07, 0, 0), 0.1, col, 3, 6)
				mk2.sphere(Vector3(0.07, 0, 0), 0.1, col, 3, 6)
				mk2.cone(Vector3(0, -0.02, 0), 0.15, -0.18, col, 6)
			elif kind == "puff":
				for i2 in 4:
					mk2.sphere(Vector3(cos(i2 * 1.6) * 0.15, 0, sin(i2 * 1.6) * 0.15), 0.16, col.lightened(0.3), 3, 6)
			var mi2 := MeshInstance3D.new()
			mi2.mesh = mk2.commit() if kind != "note" else _note_mesh(col)
			mi2.material_override = Art.fx(Color.WHITE, 1.0)
			mi2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			node.add_child(mi2)
			node.scale = Vector3.ONE * float(data.get("scale", 1.0))
			life = 1.2
		"note_travel":
			var mi3 := MeshInstance3D.new()
			mi3.mesh = _note_mesh(col)
			mi3.material_override = Art.fx(Color.WHITE, 1.0)
			mi3.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			node.add_child(mi3)
			node.scale = Vector3.ONE * float(data.get("scale", 1.0))
			life = 1.4
		"ribbon":
			for i3 in 5:
				var mk3 := MeshKit.new()
				mk3.jitter = 0.0
				mk3.box(Vector3.ZERO, Vector3(0.12, 0.05, 0.03), col.lightened(i3 * 0.08))
				var mi4 := MeshInstance3D.new()
				mi4.mesh = mk3.commit()
				mi4.material_override = Art.fx(Color.WHITE, 1.0)
				node.add_child(mi4)
			life = 0.6
	fx_root.add_child(node)
	_fx.append({"node": node, "t": 0.0, "life": life, "kind": kind, "data": data, "origin": pos})

func _tick_fx(dt: float) -> void:
	var keep: Array = []
	for f in _fx:
		f["t"] += dt
		var n: Node3D = f["node"]
		var k: float = f["t"] / f["life"]
		if k >= 1.0:
			n.queue_free()
			continue
		match f["kind"]:
			"sparkle", "confetti":
				for c in n.get_children():
					var v: Vector3 = c.get_meta("v")
					c.position = v * f["t"] + Vector3(0, -2.5 * f["t"] * f["t"], 0)
					c.rotation.z += dt * 8.0
			"heart", "note":
				n.position = f["origin"] + Vector3(0, k * 0.6, 0)
				var sc := (1.0 - k * 0.4) * float(f["data"].get("scale", 1.0))
				n.scale = Vector3.ONE * sc
			"puff":
				n.scale = Vector3.ONE * (0.6 + k)
			"note_travel":
				var to: Vector3 = f["data"]["to"]
				n.position = f["origin"].lerp(to, k) + Vector3(0, sin(k * PI) * 0.6, 0)
				n.scale = Vector3.ONE * lerpf(float(f["data"].get("scale", 1.0)), float(f["data"].get("end_scale", 0.5)), k)
			"ribbon":
				var to2: Vector3 = f["data"]["to"]
				var i := 0
				for c2 in n.get_children():
					var kk := clampf(k * 1.4 - i * 0.08, 0.0, 1.0)
					c2.position = (f["origin"].lerp(to2, kk) + Vector3(0, sin(kk * PI) * 0.5, 0)) - n.position
					i += 1
		keep.append(f)
	_fx = keep
