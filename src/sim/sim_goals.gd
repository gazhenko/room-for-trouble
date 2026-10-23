class_name SimGoals
extends RefCounted
## Festival trunks (two-handle kinematic sweep, §6.5), parcels, and the P5
## luggage lift pair (§12.5).

static func handle_pos(tr: Dictionary, h: int) -> Vector2i:
	var off := -SimC.TRUNK_HANDLE_OFF if h == 0 else SimC.TRUNK_HANDLE_OFF
	return Vector2i(int(tr["x"]) + off, int(tr["z"]))

static func spawn_trunk(sim: HotelSim, oid: String, pos: Array, goal: String) -> void:
	var x := sim.L.mirror_x_um(int(pos[0]) * SimC.UM)
	var z := int(pos[1]) * SimC.UM
	# Reserve an alternate parking pad if another trunk occupies the spawn.
	for tid in sim.s["trunks"]:
		var o: Dictionary = sim.s["trunks"][tid]
		if absi(o["x"] - x) < 3_200_000 and absi(o["z"] - z) < 800_000:
			for p in sim.L.trunk_parking:
				var px: int = p.x * SimC.UM
				var free := true
				for tid2 in sim.s["trunks"]:
					var o2: Dictionary = sim.s["trunks"][tid2]
					if absi(o2["x"] - px) < 3_200_000 and absi(o2["z"] - p.y * SimC.UM) < 800_000:
						free = false
				if free:
					x = px; z = p.y * SimC.UM
					break
	var tid3 := sim.alloc_id()
	sim.s["trunks"][tid3] = {"id": tid3, "oid": oid, "x": x, "z": z, "h": [-1, -1], "delivered": false,
		"goal": goal, "park": [x, z], "vx": 0, "vz": 0}
	sim.s["goals"][oid] = {"kind": "trunk", "done": false, "id": tid3}
	sim.emit("trunk_spawn", {"id": tid3, "oid": oid})

static func spawn_parcels(sim: HotelSim, oids: Array, positions: Array) -> void:
	for i in oids.size():
		var p: Array = positions[i]
		var x := sim.L.mirror_x_um(int(p[0]) * SimC.UM)
		var z := int(p[1]) * SimC.UM
		var spot := SimInteract.floor_spot(sim, x, z, 0, 0, x, z)
		if spot.x == -1:
			spot = Vector2i(x, z)
		var iid := sim.new_item("festival_parcel", {"loc": "world", "x": spot.x, "z": spot.y, "oid": oids[i]})
		sim.s["goals"][oids[i]] = {"kind": "parcel", "done": false, "id": iid}
	sim.emit("parcels_spawn", {"n": oids.size()})

static func deliver_parcel(sim: HotelSim, it: Dictionary, seat: int) -> void:
	var oid: String = it.get("oid", "")
	if oid == "" or not sim.s["goals"].has(oid):
		return
	if sim.s["goals"][oid]["done"]:
		return
	sim.s["goals"][oid]["done"] = true
	sim.emit("parcel_installed", {"oid": oid, "seat": seat})

static func grip(sim: HotelSim, st: Dictionary, tid: int, h: int) -> void:
	var tr: Dictionary = sim.s["trunks"].get(tid, {})
	if tr.is_empty() or tr["delivered"] or tr["h"][h] != -1 or st["held"] != 0:
		return
	tr["h"][h] = st["seat"]
	st["grip"] = tid
	st["grip_h"] = h
	st["work_key"] = ""
	var hp := handle_pos(tr, h)
	st["x"] = hp.x; st["z"] = hp.y; st["vx"] = 0; st["vz"] = 0
	st["fx"] = 1000 if h == 0 else -1000
	st["fz"] = 0
	sim.emit("grip", {"seat": st["seat"], "trunk": tid, "handle": h})

static func release_handle(sim: HotelSim, st: Dictionary) -> void:
	var tid: int = st["grip"]
	var tr: Dictionary = sim.s["trunks"].get(tid, {})
	if not tr.is_empty() and st["grip_h"] >= 0:
		tr["h"][st["grip_h"]] = -1
	st["grip"] = 0
	st["grip_h"] = -1
	if not SimMove.point_free(sim, st["x"], st["z"], SimC.RADIUS):
		var spot := SimInteract.floor_spot(sim, st["x"], st["z"], 0, 0, st["x"], st["z"])
		if spot.x != -1:
			st["x"] = spot.x; st["z"] = spot.y
	sim.emit("release", {"seat": st["seat"], "trunk": tid})

static func step_trunks(sim: HotelSim) -> void:
	for tid in sim.s["trunks"]:
		var tr: Dictionary = sim.s["trunks"][tid]
		if tr["delivered"]:
			continue
		var vecs: Array = []
		for h in 2:
			var seat: int = tr["h"][h]
			if seat == -1:
				continue
			var st := sim.staff_by_seat(seat)
			if st.is_empty() or not st["present"]:
				tr["h"][h] = -1
				continue
			var inp := SimMove.input_vec(st)
			vecs.append(Vector2i(inp.x * 1000 / 127, inp.y * 1000 / 127))
		if vecs.is_empty():
			tr["vx"] = 0; tr["vz"] = 0
			continue
		var vx := 0
		var vz := 0
		if vecs.size() == 1:
			vx = vecs[0].x * SimC.TRUNK_SPEED_ONE / 1000
			vz = vecs[0].y * SimC.TRUNK_SPEED_ONE / 1000
		else:
			var sx: int = vecs[0].x + vecs[1].x
			var sz: int = vecs[0].y + vecs[1].y
			var m := SimC.isqrt(sx * sx + sz * sz)
			if m > 0:
				var k := mini(1000, m * 1000 / 1200)
				vx = sx * SimC.TRUNK_SPEED_TWO / m * k / 1000
				vz = sz * SimC.TRUNK_SPEED_TWO / m * k / 1000
		tr["vx"] = vx; tr["vz"] = vz
		var hx := SimC.TRUNK_HANDLE_OFF + SimC.RADIUS
		var hz := SimC.TRUNK_HALF_WID
		if absi(vx) >= absi(vz):
			tr["x"] = _sweep_rect(sim, tr["x"], tr["z"], vx, true, hx, hz)
			tr["z"] = _sweep_rect(sim, tr["x"], tr["z"], vz, false, hx, hz)
		else:
			tr["z"] = _sweep_rect(sim, tr["x"], tr["z"], vz, false, hx, hz)
			tr["x"] = _sweep_rect(sim, tr["x"], tr["z"], vx, true, hx, hz)
		for h in 2:
			var seat2: int = tr["h"][h]
			if seat2 == -1:
				continue
			var st2 := sim.staff_by_seat(seat2)
			var hp := handle_pos(tr, h)
			st2["x"] = hp.x; st2["z"] = hp.y
			st2["moving"] = vx != 0 or vz != 0
		_check_goal(sim, tr)

static func _sweep_rect(sim: HotelSim, x: int, z: int, d: int, along_x: bool, hx: int, hz: int) -> int:
	if d == 0:
		return x if along_x else z
	var pos := x if along_x else z
	var target := pos + d
	var boxes: Array = []
	var tx := LayoutDef.tile_of(x)
	var tz := LayoutDef.tile_of(z)
	for j in range(tz - 2, tz + 3):
		for i in range(tx - 3, tx + 4):
			if sim.L.is_wall_tile(i, j) or (sim.L.shutter == Vector2i(i, j) and sim.s["shutter"]["state"] == "closed"):
				boxes.append([i * SimC.UM - 500_000, j * SimC.UM - 500_000, i * SimC.UM + 500_000, j * SimC.UM + 500_000])
	for b in sim.L.boxes:
		boxes.append(b)
	for b in boxes:
		var o0: int; var o1: int; var a0: int; var a1: int; var other: int
		if along_x:
			o0 = b[1] - hz; o1 = b[3] + hz; a0 = b[0] - hx; a1 = b[2] + hx; other = z
		else:
			o0 = b[0] - hx; o1 = b[2] + hx; a0 = b[1] - hz; a1 = b[3] + hz; other = x
		if other <= o0 or other >= o1:
			continue
		if d > 0 and pos <= a0 and target > a0:
			target = a0
		elif d < 0 and pos >= a1 and target < a1:
			target = a1
	return target

static func _check_goal(sim: HotelSim, tr: Dictionary) -> void:
	var gp: Vector2i = sim.L.fixtures["goal_pad"]
	var gx := gp.x * SimC.UM
	var gz := gp.y * SimC.UM
	if SimMove.dist(tr["x"], tr["z"], gx, gz) <= 1_000_000:
		tr["delivered"] = true
		for h in 2:
			var seat: int = tr["h"][h]
			if seat != -1:
				var st := sim.staff_by_seat(seat)
				release_handle(sim, st)
		tr["h"] = [-1, -1]
		if sim.s["goals"].has(tr["oid"]):
			sim.s["goals"][tr["oid"]]["done"] = true
		sim.emit("trunk_delivered", {"id": tr["id"], "oid": tr["oid"]})

static func park_unfinished(sim: HotelSim) -> void:
	for k in sim.s["goals"]:
		if not sim.s["goals"][k]["done"]:
			sim.emit("nana_parks", {"oid": k})

# ------------------------------------------------------------- lifts

static func lift_send(sim: HotelSim, pad: int, seat: int) -> void:
	var lf: Dictionary = sim.s["lifts"]
	if lf.is_empty() or lf["busy"]:
		return
	var iid := SimInteract._lift_pad_item(sim, pad)
	if iid == 0 or SimInteract._lift_pad_item(sim, 1 - pad) != 0:
		return
	var it := sim.item(iid)
	it["loc"] = "lift"; it["sock"] = ""
	lf["busy"] = true; lf["t"] = SimC.T_LIFT_TRANSIT; lf["item"] = iid; lf["rider"] = -1; lf["to"] = 1 - pad
	sim.emit("lift_depart", {"pad": pad, "id": iid, "seat": seat})

static func lift_ride(sim: HotelSim, pad: int, st: Dictionary) -> void:
	var lf: Dictionary = sim.s["lifts"]
	if lf.is_empty() or lf["busy"] or st.is_empty():
		return
	lf["busy"] = true; lf["t"] = SimC.T_LIFT_TRANSIT; lf["item"] = st["held"]; lf["rider"] = st["seat"]; lf["to"] = 1 - pad
	st["act"] = {"kind": "ride", "t": SimC.T_LIFT_TRANSIT + 1, "lock": true}
	st["riding"] = true
	sim.emit("lift_ride", {"pad": pad, "seat": st["seat"]})

static func step_lifts(sim: HotelSim) -> void:
	var lf: Dictionary = sim.s["lifts"]
	if lf.is_empty() or not lf["busy"]:
		return
	if SimInteract.station_tripped(sim, "lift_pair"):
		return
	lf["t"] -= 1
	if lf["t"] > 0:
		return
	var to: int = lf["to"]
	var pad: Vector2i = sim.L.lift_pads[to]
	var px := pad.x * SimC.UM
	var pz := pad.y * SimC.UM
	if lf["rider"] != -1:
		var st := sim.staff_by_seat(lf["rider"])
		if not st.is_empty():
			var spot := SimInteract.floor_spot(sim, px, pz, 0, 0, px, pz)
			if spot.x == -1:
				spot = Vector2i(px, pz)
			st["x"] = spot.x; st["z"] = spot.y
			st["riding"] = false
			st["act"] = {}
			if st["held"] != 0:
				sim.item(st["held"])["lift_t"] = sim.s["tick"]
		sim.emit("lift_arrive", {"pad": to, "rider": lf["rider"]})
	elif lf["item"] != 0:
		var it := sim.item(lf["item"])
		if not it.is_empty():
			SimInteract.sock_item(sim, lf["item"], "liftpad:%d" % to)
			it["lift_t"] = sim.s["tick"]
		sim.emit("lift_arrive", {"pad": to, "id": lf["item"]})
	lf["busy"] = false; lf["item"] = 0; lf["rider"] = -1
