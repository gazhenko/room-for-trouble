class_name SimInteract
extends RefCounted
## Targeting, Carry/Work actions, shared work progress, handoffs and every
## atomic item transaction (§6.3–§6.6, §7). Work progress lives on the target.

const PLANNING_WORK := ["thermo", "gate", "pump"]
const RANK_SOCKET := 2
const RANK_HANDOFF := 3
const RANK_PICKUP := 4
const RANK_STATION := 5

# ============================================================ per-tick entry

static func step_all(sim: HotelSim) -> void:
	var staff: Array = sim.s["staff"]
	var n := staff.size()
	if not sim.s.has("work"):
		sim.s["work"] = {}
	for st in staff:
		if st["present"]:
			update_highlights(sim, st)
	var phase: String = sim.s["phase"]
	var can_act := phase in ["planning", "active"]
	var start: int = sim.s["tick"] % maxi(1, n)
	for k in n:
		var st: Dictionary = staff[(start + k) % n]
		if not st["present"]:
			continue
		var p: int = st["pressed_btn"]
		if (p & SimC.BTN_CARRY) != 0:
			st["last_carry_t"] = sim.s["tick"]
			if can_act:
				press_carry(sim, st)
		if (p & SimC.BTN_WORK) != 0 and can_act:
			press_work(sim, st)
		if (p & SimC.BTN_PING) != 0:
			press_ping(sim, st, (st["held_btn"] & SimC.BTN_PING_HOLD) != 0)
		if (p & SimC.BTN_HINT) != 0 and phase == "active":
			st["hint_i"] = (st["hint_i"] + 1) % 3
			st["hint_t"] = 90
		if (p & SimC.BTN_STEP) != 0 and st["grip"] != 0:
			SimGoals.release_handle(sim, st)
		if (p & SimC.BTN_STEP) != 0 and sim.s["finish_t"] > 0:
			sim.cancel_finish(st["seat"])
		if st["hint_t"] > 0:
			st["hint_t"] -= 1
	_advance_actions(sim)
	_advance_work(sim)

# ============================================================ highlights

static func update_highlights(sim: HotelSim, st: Dictionary) -> void:
	if not st["act"].is_empty() and st["act"].get("lock", false):
		return
	var c := _best(sim, st, carry_candidates(sim, st), st["hl_c"])
	st["hl_c"] = c.get("key", ""); st["hl_c_ok"] = c.get("ok", false); st["hl_c_why"] = c.get("why", "")
	var w := _best(sim, st, work_candidates(sim, st), st["hl_w"])
	st["hl_w"] = w.get("key", ""); st["hl_w_ok"] = w.get("ok", false); st["hl_w_why"] = w.get("why", "")

static func _best(sim: HotelSim, st: Dictionary, cands: Array, current: String) -> Dictionary:
	var best := {}
	var best_score := []
	for c in cands:
		var d := SimMove.dist(st["x"], st["z"], c["ax"], c["az"])
		var reach: int = c.get("reach", SimC.REACH)
		var sticky: bool = c["key"] == current
		if d > reach + (SimC.HYSTERESIS if sticky else 0):
			continue
		var dot := 1000
		var is_staff: bool = str(c["key"]).begins_with("staff:")
		if is_staff and d < 250_000:
			continue   # a teammate standing on you is never an ambiguous handoff target
		if d > 450_000 or is_staff:
			dot = (st["fx"] * (c["ax"] - st["x"]) + st["fz"] * (c["az"] - st["z"])) / maxi(1, d)
			if dot < SimC.CONE_COS_MILLI and not c.get("no_cone", false):
				continue
		if not c.get("no_los", false) and not SimMove.line_clear(sim, st["x"], st["z"], c["ax"], c["az"]):
			continue
		var rank: int = c.get("rank", RANK_STATION)
		if sticky and c["ok"]:
			rank = 0
		var score := [0 if c["ok"] else 1, rank, -dot, d, c["key"]]
		if best.is_empty() or _less(score, best_score):
			best = c
			best_score = score
	return best

static func _less(a: Array, b: Array) -> bool:
	for i in a.size():
		if a[i] == b[i]:
			continue
		return a[i] < b[i]
	return false

static func _cand(key: String, pos: Vector2i, ok: bool, why: String, rank: int, reach: int = SimC.REACH) -> Dictionary:
	return {"key": key, "ax": pos.x, "az": pos.y, "ok": ok, "why": why, "rank": rank, "reach": reach}

static func um(t: Vector2i) -> Vector2i:
	return Vector2i(t.x * SimC.UM, t.y * SimC.UM)

static func plaque_pos(sim: HotelSim, letter: String) -> Vector2i:
	var g: Dictionary = sim.L.rooms[letter]
	var d: Vector2i = g["door"]
	var off := 380_000 if g["side"] == "north" else -380_000
	return Vector2i(d.x * SimC.UM, d.y * SimC.UM + off)

static func door_pos(sim: HotelSim, letter: String) -> Vector2i:
	return um(sim.L.rooms[letter]["door"])

static func thermo_pos(sim: HotelSim, letter: String) -> Vector2i:
	var g: Dictionary = sim.L.rooms[letter]
	var p := um(g["thermostat"])
	return Vector2i(p.x, p.y + (200_000 if g["side"] == "north" else -200_000))

static func gate_pos(sim: HotelSim, edge: String) -> Vector2i:
	var p := um(sim.L.gates[edge])
	var north := p.y <= sim.L.hall.position.y * SimC.UM
	return Vector2i(p.x, p.y + (-250_000 if north else 250_000))

## What an open vent on this edge can do to a held item: "warm" when a room on
## the edge is warm, "cool" when one is cold (|heat| >= VENT_TEMPER_HEAT), else "".
static func vent_offers(sim: HotelSim, edge: String) -> String:
	if not sim.s["gates"].get(edge, false):
		return ""
	var warm := false
	var cool := false
	for letter in sim.L.edge_rooms(edge):
		var h: int = sim.room(letter)["heat"]
		if h >= SimC.VENT_TEMPER_HEAT:
			warm = true
		elif h <= -SimC.VENT_TEMPER_HEAT:
			cool = true
	if warm and not cool:
		return "warm"
	if cool and not warm:
		return "cool"
	return ""

## A howl startles staff near the room's door: half a second frozen and the
## held item set down at their feet (never lost).
static func startle_near(sim: HotelSim, x: int, z: int, radius: int) -> void:
	for st in sim.s["staff"]:
		if not st["present"] or st["grip"] != 0:
			continue
		var dx: int = st["x"] - x
		var dz: int = st["z"] - z
		if dx * dx + dz * dz > radius * radius:
			continue
		st["stun_t"] = SimC.STUN_TICKS
		st["work_key"] = ""
		var dropped := 0
		if st["held"] != 0:
			var spot := floor_spot(sim, st["x"], st["z"], st["fx"], st["fz"], st["x"], st["z"])
			if spot.x != -1:
				dropped = st["held"]
				place_world(sim, dropped, spot.x, spot.y)
				st["held"] = 0
		sim.emit("startled", {"seat": st["seat"], "dropped": dropped})

static func counter_pos(sim: HotelSim, i: int) -> Vector2i:
	return um(sim.L.fixtures["counters"][i])

## The item resting on pass counter i, or 0.
static func _counter_item(sim: HotelSim, i: int) -> int:
	var key := "counter:%d" % i
	for iid in sim.s["items"]:
		var it: Dictionary = sim.s["items"][iid]
		if it["loc"] == "sock" and it["sock"] == key:
			return int(iid)
	return 0

static func dock_pos(sim: HotelSim, dtype: String, i: int) -> Vector2i:
	match dtype:
		"mop": return um(sim.L.fixtures["mop_docks"][i])
		"can": return um(sim.L.fixtures["can_docks"][i])
		_: return um(sim.L.fixtures["breezer_dock"])

static func held_kind(sim: HotelSim, st: Dictionary) -> String:
	if st["held"] == 0:
		return ""
	return sim.item(st["held"]).get("k", "")

static func in_room(sim: HotelSim, st: Dictionary) -> String:
	var letter := sim.L.room_at_um(st["x"], st["z"])
	if letter == "":
		return ""
	if not (sim.L.rooms[letter]["rect"] as Rect2i).has_point(Vector2i(LayoutDef.tile_of(st["x"]), LayoutDef.tile_of(st["z"]))):
		return ""
	return letter

static func station_tripped(sim: HotelSim, fixture: String) -> bool:
	return sim.s["st"]["trips"].has(fixture) and sim.s["st"]["trips"][fixture].get("on", false)

static func planning(sim: HotelSim) -> bool:
	return sim.s["phase"] == "planning"

# ============================================================ carry candidates

static func carry_candidates(sim: HotelSim, st: Dictionary) -> Array:
	var out: Array = []
	if st["grip"] != 0 or st["step_t"] > 0:
		return out
	var hk := held_kind(sim, st)
	var plan := planning(sim)
	var why_plan := "ui.reason.after_start"
	var stv: Dictionary = sim.s["st"]
	var F: Dictionary = sim.L.fixtures
	if hk == "":
		for iid in sim.s["items"]:
			var it: Dictionary = sim.s["items"][iid]
			if it["loc"] == "world":
				out.append(_cand("pick:%d" % iid, Vector2i(it["x"], it["z"]), not plan, why_plan, RANK_PICKUP, SimC.PICKUP_REACH))
			elif it["loc"] == "sock":
				var sock: String = it["sock"]
				if sock.begins_with("ped:"):
					var pi := int(sock.substr(4))
					out.append(_cand("ped:%d" % pi, um(F["pedestals"][pi]) + Vector2i(0, 150_000), not plan, why_plan, RANK_PICKUP, SimC.PICKUP_REACH))
				elif sock.begins_with("dock:"):
					var parts := sock.split(":")
					out.append(_cand("dock:%s:%s" % [parts[1], parts[2]], dock_pos(sim, parts[1], int(parts[2])), not plan, why_plan, RANK_PICKUP))
				elif sock.begins_with("plinth:"):
					var letter := sock.substr(7)
					out.append(_cand("plinth:" + letter, um(sim.L.rooms[letter]["plinth"]), not plan, why_plan, RANK_PICKUP))
				elif sock.begins_with("curtain:") and sim.has_sys("sound"):
					var letter2 := sock.substr(8)
					out.append(_cand("curtain_off:" + letter2, door_pos(sim, letter2), not plan, why_plan, RANK_STATION))
				elif sock.begins_with("liftpad:"):
					var li := int(sock.substr(8))
					out.append(_cand("lift:%d" % li, um(sim.L.lift_pads[li]), not plan, why_plan, RANK_PICKUP))
				elif sock.begins_with("counter:"):
					var ci := int(sock.substr(8))
					out.append(_cand(sock, counter_pos(sim, ci), not plan, why_plan, RANK_PICKUP, SimC.PICKUP_REACH))
		if not sim.s["bench"].is_empty():
			out.append(_cand("bench", um(F["reception"]), not plan, why_plan, RANK_PICKUP))
		out.append(_cand("st:linen", um(F["linen_shelf"]), not plan and stv["linen"] > 0, why_plan if plan else "ui.reason.no_linen", RANK_STATION))
		out.append(_cand("st:towels", um(F["towel_shelf"]), not plan and stv["towels"] > 0, why_plan if plan else "ui.reason.restocking", RANK_STATION))
		out.append(_cand("st:snacks", um(F["snack_tin"]), not plan and stv["snacks"] > 0, why_plan if plan else "ui.reason.restocking", RANK_STATION))
		out.append(_cand("st:kiosk", um(F["welcome_kiosk"]), not plan, why_plan, RANK_STATION))
		if sim.has_sys("sound") and F.has("return_shelf"):
			out.append(_cand("st:return", um(F["return_shelf"]), not plan and stv["curtains_free"] > 0, why_plan if plan else "ui.reason.no_curtains", RANK_STATION))
		for tid in sim.s["trunks"]:
			var tr: Dictionary = sim.s["trunks"][tid]
			if tr["delivered"]:
				continue
			for h in 2:
				if tr["h"][h] == -1:
					out.append(_cand("handle:%d:%d" % [tid, h], SimGoals.handle_pos(tr, h), not plan, why_plan, RANK_PICKUP, SimC.PICKUP_REACH))
	else:
		var it: Dictionary = sim.item(st["held"])
		match hk:
			"ticket":
				for letter in sim.L.active_rooms:
					var why := sim.room_assignable(letter)
					out.append(_cand("plaque:" + letter, plaque_pos(sim, letter), why == "" and not plan, why_plan if plan else why, RANK_SOCKET))
				var home := int(it.get("home", "-1")) if str(it.get("home", "")).is_valid_int() else -1
				if home >= 0:
					out.append(_cand("retped:%d" % home, um(F["pedestals"][home]), true, "", RANK_SOCKET, SimC.PICKUP_REACH))
			"move_ticket":
				for letter in sim.L.active_rooms:
					var why2 := sim.room_assignable(letter)
					if why2 == "ui.reason.room_cap":
						why2 = ""   # relocation counts the guest once
					if letter == it["home"]:
						continue
					out.append(_cand("plaque:" + letter, plaque_pos(sim, letter), why2 == "", why2, RANK_SOCKET))
			"linen_clean":
				out.append(_cand("st:linen", um(F["linen_shelf"]), stv["linen"] < SimC.LINEN_CAP, "ui.reason.shelf_full", RANK_SOCKET))
				if F.has("return_shelf"):
					out.append(_cand("st:return", um(F["return_shelf"]), true, "", RANK_SOCKET))
			"linen_dirty":
				out.append(_cand("st:hamper", um(F["hamper"]), true, "", RANK_SOCKET))
				if F.has("return_shelf"):
					out.append(_cand("st:return", um(F["return_shelf"]), false, "ui.reason.dirty_to_hamper", RANK_SOCKET))
			"towel", "snack":
				for gid in sim.s["guests"]:
					var g: Dictionary = sim.s["guests"][gid]
					if g["state"] != "staying":
						continue
					var rq := SimGuests.open_request_for(sim, g, it)
					var any_open := SimGuests.any_open_request(sim, g)
					if rq >= 0:
						out.append(_cand("guest:%d" % gid, Vector2i(g["x"], g["z"]), true, "", RANK_SOCKET))
					elif SimGuests.open_request(sim, g, hk) >= 0:
						var need_t := SimGuests.needed_temp(sim.has_sys("thermal"), g["fam"], hk)
						out.append(_cand("guest:%d" % gid, Vector2i(g["x"], g["z"]), false, "ui.reason.needs_" + need_t, RANK_SOCKET))
					elif any_open:
						out.append(_cand("guest:%d" % gid, Vector2i(g["x"], g["z"]), false, "ui.reason.wrong_item", RANK_SOCKET))
				var stname := "st:towels" if hk == "towel" else "st:snacks"
				var stock: int = stv["towels"] if hk == "towel" else stv["snacks"]
				out.append(_cand(stname, um(F["towel_shelf" if hk == "towel" else "snack_tin"]), stock < SimC.STOCK_CAP, "ui.reason.shelf_full", RANK_SOCKET))
				if F.has("return_shelf"):
					out.append(_cand("st:return", um(F["return_shelf"]), true, "", RANK_SOCKET))
			"curtain_roll":
				if F.has("return_shelf"):
					out.append(_cand("st:return", um(F["return_shelf"]), true, "", RANK_SOCKET))
			"mop", "breezer", "watering_can":
				var dtype := "mop" if hk == "mop" else ("breezer" if hk == "breezer" else "can")
				var docks: Array
				if dtype == "breezer":
					docks = [F["breezer_dock"]]
				else:
					docks = F["mop_docks"] if dtype == "mop" else F["can_docks"]
				for i in docks.size():
					if dtype == "can" and i >= _can_count(sim):
						continue
					var key := "dock:%s:%d" % [dtype, i]
					var free := _dock_item(sim, dtype, i) == 0
					out.append(_cand(key, dock_pos(sim, dtype, i), free, "ui.reason.dock_full", RANK_SOCKET))
			"festival_parcel":
				if F.has("festival_stand"):
					out.append(_cand("st:stand", um(F["festival_stand"]), true, "", RANK_SOCKET))
		if hk.begins_with("welcome_"):
			for letter in sim.L.active_rooms:
				var r := sim.room(letter)
				out.append(_cand("plinth:" + letter, um(sim.L.rooms[letter]["plinth"]), r["gift"] == 0, "ui.reason.plinth_full", RANK_SOCKET))
			out.append(_cand("st:kiosk", um(F["welcome_kiosk"]), true, "", RANK_SOCKET))
			if F.has("return_shelf"):
				out.append(_cand("st:return", um(F["return_shelf"]), true, "", RANK_SOCKET))
		if hk != "festival_trunk":
			var counters: Array = F.get("counters", [])
			for ci in counters.size():
				var free := _counter_item(sim, ci) == 0
				out.append(_cand("counter:%d" % ci, counter_pos(sim, ci), free and not plan, why_plan if plan else "ui.reason.counter_full", RANK_SOCKET))
		if sim.has_sys("lift") and not sim.s["lifts"].is_empty() and hk != "festival_trunk":
			for li in 2:
				if _lift_pad_item(sim, li) == 0:
					out.append(_cand("lift:%d" % li, um(sim.L.lift_pads[li]), not station_tripped(sim, "lift_pair"), "ui.reason.tripped", RANK_SOCKET))
		for st2 in sim.s["staff"]:
			if st2["seat"] == st["seat"] or not st2["present"] or st2["grip"] != 0:
				continue
			var c := _cand("staff:%d" % st2["seat"], Vector2i(st2["x"], st2["z"]), not plan, why_plan, RANK_HANDOFF, SimC.HANDOFF_REACH)
			c["no_los"] = false
			out.append(c)
	if plan:
		for c in out:
			c["ok"] = false
			c["why"] = why_plan
	return out

static func _can_count(sim: HotelSim) -> int:
	return 2 if sim.s["humans"] >= 3 else 1

static func _dock_item(sim: HotelSim, dtype: String, i: int) -> int:
	var sock := "dock:%s:%d" % [dtype, i]
	for iid in sim.s["items"]:
		var it: Dictionary = sim.s["items"][iid]
		if it["loc"] == "sock" and it["sock"] == sock:
			return iid
	return 0

static func _lift_pad_item(sim: HotelSim, li: int) -> int:
	var sock := "liftpad:%d" % li
	for iid in sim.s["items"]:
		var it: Dictionary = sim.s["items"][iid]
		if it["loc"] == "sock" and it["sock"] == sock:
			return iid
	return 0

# ============================================================ work candidates

static func work_candidates(sim: HotelSim, st: Dictionary) -> Array:
	var out: Array = []
	if st["grip"] != 0 or st["step_t"] > 0:
		return out
	var hk := held_kind(sim, st)
	var plan := planning(sim)
	var F: Dictionary = sim.L.fixtures
	var wp := "ui.reason.after_start"
	var here := in_room(sim, st)
	for letter in sim.L.active_rooms:
		var r := sim.room(letter)
		var g: Dictionary = sim.L.rooms[letter]
		var bedp := um(g["bed"])
		if r["frost"]:
			var c := _cand("frost:" + letter, door_pos(sim, letter), not plan, wp, 1)
			out.append(c)
		if r["bed"] == "Dirty" and (hk == "" or hk == "linen_clean"):
			out.append(_cand("strip:" + letter, bedp, not plan, wp, RANK_STATION))
		elif r["bed"] == "Stripped":
			out.append(_cand("make:" + letter, bedp, hk == "linen_clean" and not plan, wp if plan else "ui.reason.need_linen", RANK_STATION))
		if hk == "mop" and r["mess"] > 0 and here == letter:
			var c2 := _cand("mess:" + letter, Vector2i(st["x"], st["z"]), not plan, wp, RANK_STATION)
			c2["no_cone"] = true; c2["no_los"] = true
			out.append(c2)
		if sim.has_sys("thermal"):
			var tripped := station_tripped(sim, "radiator_" + letter)
			if tripped:
				out.append(_cand("trip:radiator_" + letter, thermo_pos(sim, letter), not plan, wp, 1))
			else:
				out.append(_cand("thermo:" + letter, thermo_pos(sim, letter), true, "", RANK_STATION))
		if sim.has_sys("moisture") and hk == "watering_can":
			var it: Dictionary = sim.item(st["held"])
			var ok_tray: bool = it.get("ch", 0) > 0 and r["tray"] < 60
			var why_t := "ui.reason.can_empty" if it.get("ch", 0) <= 0 else "ui.reason.tray_full"
			out.append(_cand("tray:" + letter, um(g["tray"]), ok_tray and not plan, wp if plan else why_t, RANK_STATION))
		if hk == "" and r["guest"] != 0:
			var gg := sim.guest(r["guest"])
			if gg.get("state", "") == "staying":
				var why_m := "" if not gg["moved"] else "ui.reason.moved_once"
				out.append(_cand("move:" + letter, plaque_pos(sim, letter), why_m == "" and not plan, wp if plan else why_m, RANK_STATION))
		if hk == "" and r["reserved"] != 0:
			var gr := sim.guest(r["reserved"])
			if gr.get("state", "") == "walking" and not gr.get("relocating", false):
				out.append(_cand("cancel:" + letter, plaque_pos(sim, letter), not plan, wp, RANK_STATION))
		if hk == "curtain_roll" and sim.has_sys("sound"):
			out.append(_cand("hang:" + letter, door_pos(sim, letter), r["curtain"] == 0 and not plan, wp if plan else "ui.reason.curtain_up", RANK_SOCKET))
	if sim.has_sys("thermal"):
		for e in sim.L.thermal_edges:
			out.append(_cand("gate:" + e, gate_pos(sim, e), true, "", RANK_STATION))
			# An open vent on a warm room's edge warms a towel, on a cold room's
			# edge chills a snack: the middle step without the walk to the pump
			# (DESIGN_V2 §5.4). Its own work key: a key shared with the pump made
			# the reference bot start the work at every vent it walked past.
			if hk in ["towel", "snack"] and sim.s["gates"].get(e, false):
				var want := "warm" if hk == "towel" else "cool"
				if vent_offers(sim, e) == want:
					var it_v: Dictionary = sim.item(st["held"])
					var done_v := str(it_v.get("temp", "")) != ""
					out.append(_cand("vent:%s:%d" % [e, st["held"]], gate_pos(sim, e), not plan and not done_v,
						wp if plan else "ui.reason.already_tempered", RANK_SOCKET))
		if F.has("heat_pump"):
			if hk in ["towel", "snack"]:
				# The middle step: warm a towel / chill a snack (one second at the pump).
				var it_t: Dictionary = sim.item(st["held"])
				var tempered := str(it_t.get("temp", "")) != ""
				out.append(_cand("temper:%d" % st["held"], um(F["heat_pump"]), not plan and not tempered,
					wp if plan else "ui.reason.already_tempered", RANK_STATION))
			else:
				out.append(_cand("pump", um(F["heat_pump"]), true, "", RANK_STATION))
	if sim.has_sys("moisture") and hk == "watering_can" and F.has("tap"):
		out.append(_cand("tap", um(F["tap"]), not plan, wp, RANK_STATION))
	if hk == "":
		var busy: bool = sim.s["st"]["press_user"] != -1 and sim.s["st"]["press_user"] != st["seat"]
		out.append(_cand("press", um(F["linen_shelf"]), not plan and not busy and sim.s["st"]["linen"] < SimC.LINEN_CAP,
			wp if plan else ("ui.reason.in_use" if busy else "ui.reason.shelf_full"), RANK_STATION))
	out.append(_cand("kiosk_cycle", um(F["welcome_kiosk"]), not plan, wp, RANK_STATION))
	out.append(_cand("bell", um(F["group_bell"]), true, "", RANK_STATION))
	for fx in ["towels", "snacks"]:
		if station_tripped(sim, fx):
			out.append(_cand("trip:" + fx, um(F["towel_shelf" if fx == "towels" else "snack_tin"]), not plan, wp, 1))
	if hk == "mop":
		for pid in sim.s["puddles"]:
			var p: Dictionary = sim.s["puddles"][pid]
			out.append(_cand("puddle:%d" % pid, Vector2i(p["x"], p["z"]), not plan, wp, 1))
	if hk == "breezer":
		for cid in sim.s["clouds"]:
			var cl: Dictionary = sim.s["clouds"][cid]
			var cc := _cand("cloud:%d" % cid, Vector2i(cl["x"], cl["z"]), not plan, wp, 1, SimC.BREEZER_REACH)
			cc["no_los"] = true
			out.append(cc)
	for gid in sim.s["guests"]:
		var g2: Dictionary = sim.s["guests"][gid]
		if g2["state"] != "staying":
			continue
		var gp := Vector2i(g2["x"], g2["z"])
		if hk == "":
			if g2.get("helper_ready", false):
				var pv := SimGuests.helper_preview(sim, g2)
				out.append(_cand("helper:%d" % gid, gp, pv["useful"] and not plan, "ui.reason.ready_when_needed", 2))
			if SimGuests.goodbye_available(sim, g2):
				out.append(_cand("goodbye:%d" % gid, gp, true, "", 2))
	if sim.has_sys("lift") and not sim.s["lifts"].is_empty():
		for li in 2:
			var pad := um(sim.L.lift_pads[li])
			if station_tripped(sim, "lift_pair"):
				out.append(_cand("trip:lift_pair", pad, not plan, wp, 1))
				continue
			var on_pad := _lift_pad_item(sim, li)
			var busy2: bool = sim.s["lifts"]["busy"]
			if on_pad != 0:
				out.append(_cand("lift_send:%d" % li, pad, not busy2 and not plan and _lift_pad_item(sim, 1 - li) == 0,
					wp if plan else "ui.reason.lift_busy", RANK_STATION))
			elif hk == "" or true:
				out.append(_cand("lift_ride:%d" % li, pad, not busy2 and not plan, wp if plan else "ui.reason.lift_busy", RANK_STATION))
	if plan:
		for c in out:
			var kind: String = c["key"].split(":")[0]
			if not kind in PLANNING_WORK:
				c["ok"] = false
				c["why"] = wp
	return out

# ============================================================ carry press

static func press_carry(sim: HotelSim, st: Dictionary) -> void:
	if st["grip"] != 0:
		SimGoals.release_handle(sim, st)
		return
	if not st["act"].is_empty() or st["step_t"] > 0:
		return
	var key: String = st["hl_c"]
	if key != "" and st["hl_c_ok"]:
		_do_carry(sim, st, key)
		return
	if key != "" and not st["hl_c_ok"]:
		sim.emit("invalid", {"seat": st["seat"], "key": key, "why": st["hl_c_why"]})
		if st["held"] == 0:
			return
		# A blocked socket never eats a held item; a teammate stays a valid drop.
		if not key.begins_with("staff:"):
			return
	if st["held"] != 0:
		if st["hl_w"] != "" and st["hl_w_ok"]:
			sim.emit("hint_work", {"seat": st["seat"], "key": st["hl_w"]})
			return
		var spot := floor_spot(sim, st["x"], st["z"], st["fx"], st["fz"], st["x"], st["z"])
		if spot.x == -1:
			sim.emit("invalid", {"seat": st["seat"], "key": "", "why": "ui.reason.need_room"})
			return
		var iid: int = st["held"]
		place_world(sim, iid, spot.x, spot.y)
		st["held"] = 0
		_lock(st, "place", SimC.T_TAKE)
		sim.emit("place", {"seat": st["seat"], "id": iid})

## Busy window after an action. Carry/Work presses are refused while it runs;
## pick-ups, put-downs and handoffs keep the stick live (Overcooked-style),
## longer station beats (assign, fulfil, hamper) still plant the feet.
static func _lock(st: Dictionary, kind: String, t: int) -> void:
	st["act"] = {"kind": kind, "t": t, "lock": true, "move_lock": kind not in ["take", "place", "handoff"]}

static func _channel(st: Dictionary, kind: String, key: String, t: int) -> void:
	st["act"] = {"kind": kind, "key": key, "t": t, "total": t, "lock": false, "channel": true}

static func _do_carry(sim: HotelSim, st: Dictionary, key: String) -> void:
	var parts := key.split(":")
	var kind := parts[0]
	var seat: int = st["seat"]
	var stv: Dictionary = sim.s["st"]
	match kind:
		"pick":
			var iid := int(parts[1])
			var it := sim.item(iid)
			if it.is_empty() or it["loc"] != "world":
				return
			hold(sim, st, iid)
			_lock(st, "take", SimC.T_TAKE)
			sim.emit("pickup", {"seat": seat, "id": iid, "k": it["k"]})
		"ped":
			var pi := int(parts[1])
			for iid in sim.s["items"]:
				var it2: Dictionary = sim.s["items"][iid]
				if it2["loc"] == "sock" and it2["sock"] == "ped:%d" % pi:
					hold(sim, st, iid)
					_lock(st, "take", SimC.T_TAKE)
					sim.emit("pickup", {"seat": seat, "id": iid, "k": "ticket"})
					return
		"bench":
			if sim.s["bench"].is_empty():
				return
			var gid: int = sim.s["bench"][0]
			var g := sim.guest(gid)
			var tid: int = g.get("ticket", 0)
			if tid != 0 and sim.item(tid).get("sock", "") == "bench":
				hold(sim, st, tid)
				_lock(st, "take", SimC.T_TAKE)
				sim.emit("pickup", {"seat": seat, "id": tid, "k": "ticket"})
		"retped":
			var iid3: int = st["held"]
			sock_item(sim, iid3, "ped:" + parts[1])
			st["held"] = 0
			_lock(st, "place", SimC.T_TAKE)
			sim.emit("place", {"seat": seat, "id": iid3})
		"plaque":
			var letter := parts[1]
			var iid4: int = st["held"]
			var it4 := sim.item(iid4)
			if it4["k"] == "ticket":
				if sim.room_assignable(letter) != "":
					return
				SimGuests.assign(sim, int(it4["g"]), letter, seat)
				_consume_held(sim, st, "assigned")
				_lock(st, "assign", SimC.T_ASSIGN)
			elif it4["k"] == "move_ticket":
				var why := sim.room_assignable(letter)
				if why != "" and why != "ui.reason.room_cap":
					return
				SimGuests.relocate(sim, int(it4["g"]), letter, seat)
				_consume_held(sim, st, "relocated")
				_lock(st, "assign", SimC.T_ASSIGN)
		"plinth":
			var letter2 := parts[1]
			var r := sim.room(letter2)
			if st["held"] == 0:
				if r["gift"] == 0:
					return
				var gift: int = r["gift"]
				r["gift"] = 0
				hold(sim, st, gift)
				_lock(st, "take", SimC.T_TAKE)
				sim.emit("gift_taken", {"seat": seat, "room": letter2})
			else:
				if r["gift"] != 0:
					return
				var gid2: int = st["held"]
				st["held"] = 0
				sock_item(sim, gid2, "plinth:" + letter2)
				r["gift"] = gid2
				_lock(st, "fulfill", SimC.T_FULFILL)
				SimGuests.on_gift_installed(sim, letter2, gid2, seat)
		"curtain_off":
			_channel(st, "curtain_off", key, SimC.T_CURTAIN)
		"st":
			_do_station_carry(sim, st, parts[1])
		"dock":
			var dtype := parts[1]
			var di := int(parts[2])
			if st["held"] == 0:
				var tool := _dock_item(sim, dtype, di)
				if tool == 0:
					return
				hold(sim, st, tool)
				_lock(st, "take", SimC.T_TAKE)
				sim.emit("pickup", {"seat": seat, "id": tool, "k": sim.item(tool)["k"]})
			else:
				if _dock_item(sim, dtype, di) != 0:
					return
				var tid2: int = st["held"]
				st["held"] = 0
				sock_item(sim, tid2, "dock:%s:%d" % [dtype, di])
				_lock(st, "place", SimC.T_TAKE)
				sim.emit("dock", {"seat": seat, "id": tid2})
		"counter":
			var ci := int(parts[1])
			if st["held"] == 0:
				var on_c := _counter_item(sim, ci)
				if on_c == 0:
					return
				hold(sim, st, on_c)
				_lock(st, "take", SimC.T_TAKE)
				sim.emit("pickup", {"seat": seat, "id": on_c, "k": sim.item(on_c)["k"]})
			else:
				if _counter_item(sim, ci) != 0:
					return
				var cid2: int = st["held"]
				st["held"] = 0
				sock_item(sim, cid2, "counter:%d" % ci)
				_lock(st, "place", SimC.T_TAKE)
				sim.emit("place", {"seat": seat, "id": cid2, "counter": ci})
		"lift":
			var li := int(parts[1])
			if st["held"] == 0:
				var on := _lift_pad_item(sim, li)
				if on == 0:
					return
				hold(sim, st, on)
				_lock(st, "take", SimC.T_TAKE)
			else:
				if _lift_pad_item(sim, li) != 0:
					return
				var lid: int = st["held"]
				st["held"] = 0
				sock_item(sim, lid, "liftpad:%d" % li)
				_lock(st, "place", SimC.T_TAKE)
				sim.emit("lift_load", {"seat": seat, "pad": li})
		"handle":
			SimGoals.grip(sim, st, int(parts[1]), int(parts[2]))
		"guest":
			var gid3 := int(parts[1])
			var g3 := sim.guest(gid3)
			var rq := SimGuests.open_request_for(sim, g3, sim.item(st["held"]))
			if rq < 0:
				return
			var iid5: int = st["held"]
			SimGuests.fulfill(sim, g3, rq, seat, iid5)
			_consume_held(sim, st, "request")
			_lock(st, "fulfill", SimC.T_FULFILL)
		"staff":
			_handoff(sim, st, int(parts[1]))

static func _do_station_carry(sim: HotelSim, st: Dictionary, which: String) -> void:
	var stv: Dictionary = sim.s["st"]
	var hk := held_kind(sim, st)
	var seat: int = st["seat"]
	match which:
		"linen":
			if hk == "":
				if stv["linen"] <= 0:
					return
				stv["linen"] -= 1
				var iid := sim.new_item("linen_clean", {"loc": "held", "seat": seat})
				st["held"] = iid
				_lock(st, "take", SimC.T_TAKE)
				sim.emit("take_stock", {"seat": seat, "what": "linen"})
			elif hk == "linen_clean" and stv["linen"] < SimC.LINEN_CAP:
				_consume_held(sim, st, "restock")
				stv["linen"] += 1
				_lock(st, "place", SimC.T_TAKE)
				sim.emit("restock", {"seat": seat, "what": "linen"})
		"towels", "snacks":
			var kind := "towel" if which == "towels" else "snack"
			if hk == "":
				if stv[which] <= 0:
					return
				_channel(st, "dispense", "st:" + which, SimC.T_DISPENSE_STOCK)
			elif hk == kind and stv[which] < SimC.STOCK_CAP:
				_consume_held(sim, st, "restock")
				stv[which] += 1
				_lock(st, "place", SimC.T_TAKE)
				sim.emit("restock", {"seat": seat, "what": which})
		"kiosk":
			if hk == "":
				_channel(st, "dispense", "st:kiosk", SimC.T_DISPENSE_GIFT)
			elif hk.begins_with("welcome_"):
				_consume_held(sim, st, "returned")
				_lock(st, "place", SimC.T_TAKE)
				sim.emit("return_item", {"seat": seat, "k": hk})
		"return":
			if hk == "":
				if stv["curtains_free"] > 0:
					_channel(st, "dispense", "st:return", SimC.T_CURTAIN)
				return
			match hk:
				"towel", "snack":
					var stock := "towels" if hk == "towel" else "snacks"
					stv[stock] = mini(SimC.STOCK_CAP, stv[stock] + 1)
				"linen_clean":
					stv["linen"] = mini(SimC.LINEN_CAP, stv["linen"] + 1)
				"curtain_roll":
					stv["curtains_free"] += 1
				"linen_dirty":
					return
			_consume_held(sim, st, "returned")
			_lock(st, "place", SimC.T_TAKE)
			sim.emit("return_item", {"seat": seat, "k": hk})
		"hamper":
			if hk != "linen_dirty":
				return
			if stv["hamper_q"] < SimC.HAMPER_QUEUE_CAP:
				var iid2: int = st["held"]
				SimScore.note_consumed(sim, sim.item(iid2), seat, "hamper")
				_consume_held(sim, st, "hamper")
				stv["hamper_q"] += 1
				_lock(st, "fulfill", SimC.T_HAMPER)
				sim.emit("hamper_in", {"seat": seat, "q": stv["hamper_q"]})
			else:
				var h := um(sim.L.fixtures["hamper"])
				var spot := floor_spot(sim, h.x, h.y + 600_000, 0, 1000, st["x"], st["z"])
				if spot.x != -1:
					var iid3: int = st["held"]
					place_world(sim, iid3, spot.x, spot.y)
					st["held"] = 0
					sim.emit("hamper_full", {"seat": seat})
		"stand":
			if hk != "festival_parcel":
				return
			var it := sim.item(st["held"])
			SimGoals.deliver_parcel(sim, it, seat)
			SimScore.note_consumed(sim, it, seat, "goal")
			_consume_held(sim, st, "goal")
			_lock(st, "fulfill", SimC.T_FULFILL)

static func _handoff(sim: HotelSim, st: Dictionary, seat2: int) -> void:
	var st2 := sim.staff_by_seat(seat2)
	if st2.is_empty() or st["held"] == 0:
		return
	var iid: int = st["held"]
	var it := sim.item(iid)
	var auto: bool = st2.get("assists", {}).get("auto_catch", true)
	var caught: bool = st2["held"] == 0 and st2["act"].is_empty() and st2["grip"] == 0 \
		and (auto or sim.s["tick"] - int(st2["last_carry_t"]) <= SimC.CATCH_WINDOW)
	st["held"] = 0
	_lock(st, "handoff", SimC.T_TAKE)
	if caught:
		it["loc"] = "held"; it["seat"] = seat2
		st2["held"] = iid
		it["handoff_t"] = sim.s["tick"]; it["handoff_from"] = st["seat"]
		_note_holder(it, seat2)
		sim.emit("handoff", {"from": st["seat"], "to": seat2, "id": iid, "k": it["k"]})
		SimScore.note_handoff(sim, it, st["seat"], seat2)
	else:
		var spot := floor_spot(sim, st2["x"], st2["z"], st2["fx"], st2["fz"], st2["x"], st2["z"])
		if spot.x == -1:
			spot = floor_spot(sim, st["x"], st["z"], st["fx"], st["fz"], st["x"], st["z"])
		if spot.x == -1:
			st["held"] = iid
			sim.emit("invalid", {"seat": st["seat"], "why": "ui.reason.need_room"})
			return
		place_world(sim, iid, spot.x, spot.y)
		sim.emit("handoff_drop", {"from": st["seat"], "to": seat2, "id": iid})

# ============================================================ work press

static func press_work(sim: HotelSim, st: Dictionary) -> void:
	if st["grip"] != 0 or not st["act"].is_empty() and st["act"].get("lock", false):
		return
	var toggle: bool = st.get("assists", {}).get("toggle_work", false)
	if toggle and st["work_key"] != "":
		st["work_key"] = ""
		st["work_toggle"] = false
		return
	var key: String = st["hl_w"]
	if key == "":
		return
	if not st["hl_w_ok"]:
		sim.emit("invalid", {"seat": st["seat"], "key": key, "why": st["hl_w_why"]})
		return
	if work_duration(sim, key) <= SimC.T_RING:
		_commit_work(sim, key, [st["seat"]])
		return
	st["work_key"] = key
	st["work_toggle"] = toggle
	sim.emit("work_start", {"seat": st["seat"], "key": key})

static func work_duration(sim: HotelSim, key: String) -> int:
	var kind := key.split(":")[0]
	match kind:
		"strip": return SimC.T_STRIP
		"make": return SimC.T_MAKE
		"mess": return SimC.T_MOP_ROOM
		"puddle": return SimC.T_MOP_PUDDLE
		"cloud": return SimC.T_BREEZER
		"frost": return SimC.T_FROST
		"temper", "vent": return SimC.T_TEMPER
		"thermo": return SimC.T_THERMO
		"tray": return SimC.T_WATER
		"gate": return SimC.T_GATE
		"pump": return SimC.T_PUMP
		"tap": return SimC.T_FILL
		"press": return SimC.T_PRESS
		"kiosk_cycle": return 0
		"bell": return 0
		"move": return SimC.T_MOVE_ROOM
		"cancel": return SimC.T_CANCEL
		"hang": return SimC.T_CURTAIN
		"helper": return SimC.T_HELPER
		"goodbye": return SimC.T_GOODBYE
		"trip": return SimC.T_RESET
		"lift_send": return SimC.T_LIFT_SEND
		"lift_ride": return SimC.T_LIFT_SEND
	return SimC.T_RING

static func _work_still_valid(sim: HotelSim, st: Dictionary, key: String) -> bool:
	for c in work_candidates(sim, st):
		if c["key"] == key:
			if not c["ok"]:
				return false
			var d := SimMove.dist(st["x"], st["z"], c["ax"], c["az"])
			return d <= int(c.get("reach", SimC.REACH)) + SimC.HYSTERESIS
	return false

static func _advance_work(sim: HotelSim) -> void:
	var workers := {}   # key -> [seat...]
	for st in sim.s["staff"]:
		if st["work_key"] == "" or not st["present"]:
			continue
		var held_work: bool = (st["held_btn"] & SimC.BTN_WORK) != 0 or st["work_toggle"]
		if not held_work or not _work_still_valid(sim, st, st["work_key"]):
			st["work_key"] = ""
			st["work_toggle"] = false
			if st["seat"] == sim.s["st"]["press_user"]:
				sim.s["st"]["press_user"] = -1
			continue
		if st["work_key"] == "press":
			if sim.s["st"]["press_user"] == -1:
				sim.s["st"]["press_user"] = st["seat"]
			elif sim.s["st"]["press_user"] != st["seat"]:
				st["work_key"] = ""
				continue
		if not workers.has(st["work_key"]):
			workers[st["work_key"]] = []
		workers[st["work_key"]].append(st["seat"])
	var W: Dictionary = sim.s["work"]
	for key in workers:
		var seats: Array = workers[key]
		var n := mini(2, seats.size())
		var units := SimC.WORK_ONE if n == 1 else SimC.WORK_TWO
		if not W.has(key):
			W[key] = {"p": 0, "c": {}}
		var w: Dictionary = W[key]
		for i in n:
			var sk := str(seats[i])
			w["c"][sk] = int(w["c"].get(sk, 0)) + 1
		if key.begins_with("mess:"):
			var r := sim.room(key.substr(5))
			r["mess_milli"] = int(r.get("mess_milli", r["mess"] * 1000)) - units * 100 / SimC.T_MOP_ROOM
			r["mess"] = maxi(0, int(ceil(r["mess_milli"] / 1000.0)))
			if r["mess"] <= 0:
				r["mess_milli"] = 0
				_commit_work(sim, key, seats.slice(0, n))
			continue
		w["p"] = int(w["p"]) + units
		if w["p"] >= work_duration(sim, key) * 1000:
			_commit_work(sim, key, seats.slice(0, n))

static func _commit_work(sim: HotelSim, key: String, seats: Array) -> void:
	var W: Dictionary = sim.s["work"]
	var contrib: Dictionary = W.get(key, {}).get("c", {})
	W.erase(key)
	var shared := 0
	for sk in contrib:
		if int(contrib[sk]) >= SimC.SHARED_MIN_TICKS:
			shared += 1
	for st in sim.s["staff"]:
		if st["work_key"] == key:
			st["work_key"] = ""
			st["work_toggle"] = false
	var seat: int = seats[0] if not seats.is_empty() else -1
	var st0 := sim.staff_by_seat(seat)
	var parts := key.split(":")
	var kind := parts[0]
	var ok := true
	match kind:
		"strip":
			var r := sim.room(parts[1])
			r["bed"] = "Stripped"
			var bedp := um(sim.L.rooms[parts[1]]["bed"])
			if not st0.is_empty() and st0["held"] == 0:
				var iid := sim.new_item("linen_dirty", {"loc": "held", "seat": seat})
				st0["held"] = iid
			else:
				var spot := floor_spot(sim, bedp.x, bedp.y + 700_000, 0, 1000, bedp.x, bedp.y + 700_000)
				if spot.x == -1:
					spot = Vector2i(bedp.x, bedp.y + 700_000)
				sim.new_item("linen_dirty", {"loc": "world", "x": spot.x, "z": spot.y})
			sim.emit("bed_stripped", {"room": parts[1], "seat": seat})
		"make":
			var r2 := sim.room(parts[1])
			if st0.is_empty() or held_kind(sim, st0) != "linen_clean":
				ok = false
			else:
				SimScore.note_consumed(sim, sim.item(st0["held"]), seat, "bed")
				_consume_held(sim, st0, "bed")
				r2["bed"] = "Made"
				sim.emit("bed_made", {"room": parts[1], "seat": seat})
		"mess":
			sim.emit("room_mopped", {"room": parts[1], "seat": seat})
		"puddle":
			var pid := int(parts[1])
			if sim.s["puddles"].has(pid):
				sim.s["puddles"].erase(pid)
				sim.emit("puddle_gone", {"id": pid, "seat": seat})
		"cloud":
			var cid := int(parts[1])
			if sim.s["clouds"].has(cid):
				sim.s["clouds"].erase(cid)
				sim.emit("cloud_gone", {"id": cid, "seat": seat})
		"frost":
			var r3 := sim.room(parts[1])
			r3["frost"] = false
			r3["frost_cd"] = 20
			sim.emit("frost_cleared", {"room": parts[1], "seat": seat})
		"temper":
			var it_t := sim.item(int(parts[1]))
			if it_t.is_empty() or not it_t["k"] in ["towel", "snack"]:
				ok = false
			else:
				it_t["temp"] = "warm" if it_t["k"] == "towel" else "cool"
				sim.emit("tempered", {"seat": seat, "id": int(parts[1]), "temp": it_t["temp"]})
		"vent":
			# vent:<edge>:<item>: the same middle step at an open vent (D51).
			var it_x := sim.item(int(parts[2]))
			var want_x := "warm" if it_x.get("k", "") == "towel" else "cool"
			if it_x.is_empty() or not it_x["k"] in ["towel", "snack"] or vent_offers(sim, parts[1]) != want_x:
				ok = false
			else:
				it_x["temp"] = want_x
				sim.emit("tempered", {"seat": seat, "id": int(parts[2]), "temp": want_x, "vent": parts[1]})
		"thermo":
			var r4 := sim.room(parts[1])
			var order := ["neutral", "warm", "cool"]
			r4["thermo"] = order[(order.find(r4["thermo"]) + 1) % 3]
			SimScore.note_vent_change(sim, parts[1])
			sim.emit("thermostat", {"room": parts[1], "mode": r4["thermo"], "seat": seat})
		"tray":
			var r5 := sim.room(parts[1])
			var can := sim.item(st0["held"]) if not st0.is_empty() else {}
			if can.is_empty() or can["ch"] <= 0:
				ok = false
			elif r5["tray"] >= 60:
				sim.emit("tray_full", {"room": parts[1]})
				ok = false
			else:
				can["ch"] -= 1
				r5["tray"] = mini(60, r5["tray"] + 30)
				r5["hum"] = mini(100, r5["hum"] + 20)
				SimScore.note_watered(sim, parts[1])
				sim.emit("watered", {"room": parts[1], "seat": seat})
				# A sprout's "water" step on its card is this watering (DESIGN_V2 §5.4).
				var wg := sim.guest(int(r5.get("guest", 0))) if int(r5.get("guest", 0)) != 0 else {}
				if not wg.is_empty() and wg["state"] == "staying":
					var wi := SimGuests.open_request(sim, wg, "water")
					if wi >= 0:
						SimGuests.fulfill(sim, wg, wi, seat, 0)
		"gate":
			var e := parts[1]
			sim.s["gates"][e] = not sim.s["gates"][e]
			for letter in sim.L.edge_rooms(e):
				SimScore.note_vent_change(sim, letter)
			sim.emit("gate", {"edge": e, "open": sim.s["gates"][e], "seat": seat})
		"pump":
			var order2 := ["balanced", "warm", "cool"]
			sim.s["st"]["pump"] = order2[(order2.find(sim.s["st"]["pump"]) + 1) % 3]
			sim.emit("pump", {"mode": sim.s["st"]["pump"], "seat": seat})
		"tap":
			if not st0.is_empty():
				sim.item(st0["held"])["ch"] = 3
				sim.emit("can_filled", {"seat": seat})
		"press":
			sim.s["st"]["press_user"] = -1
			if sim.s["st"]["linen"] < SimC.LINEN_CAP:
				sim.s["st"]["linen"] += 1
				sim.emit("pressed_linen", {"seat": seat})
		"kiosk_cycle":
			var fams := introduced_families(sim)
			var cur: int = sim.s["st"]["kiosk_sel"]
			var idx := fams.find(SimC.FAMILIES[cur])
			var nf: String = fams[(idx + 1) % fams.size()]
			sim.s["st"]["kiosk_sel"] = SimC.FAMILIES.find(nf)
			sim.emit("kiosk_cycle", {"family": nf, "seat": seat})
		"bell":
			_ring_bell(sim, seat)
		"move":
			var r6 := sim.room(parts[1])
			var g := sim.guest(r6["guest"])
			if g.is_empty() or g["moved"] or st0.is_empty() or st0["held"] != 0:
				ok = false
			else:
				var mt := sim.new_item("move_ticket", {"loc": "held", "seat": seat, "g": g["id"], "home": parts[1]})
				st0["held"] = mt
				g["move_ticket"] = mt
				sim.emit("move_ticket", {"room": parts[1], "seat": seat, "guest": g["id"]})
		"cancel":
			SimGuests.cancel_reservation(sim, parts[1], seat)
		"hang":
			var r7 := sim.room(parts[1])
			if st0.is_empty() or held_kind(sim, st0) != "curtain_roll" or r7["curtain"] != 0:
				ok = false
			else:
				var cid2: int = st0["held"]
				st0["held"] = 0
				sock_item(sim, cid2, "curtain:" + parts[1])
				r7["curtain"] = cid2
				sim.emit("curtain_hung", {"room": parts[1], "seat": seat})
		"helper":
			SimGuests.invoke_helper(sim, int(parts[1]), seat)
		"goodbye":
			SimGuests.wave_goodbye(sim, int(parts[1]), seat)
		"trip":
			SimEnv.reset_trip(sim, parts[1], seat)
		"lift_send":
			SimGoals.lift_send(sim, int(parts[1]), seat)
		"lift_ride":
			SimGoals.lift_ride(sim, int(parts[1]), st0)
	if ok:
		SimScore.note_work_done(sim, key, shared >= 2, seats)
		sim.emit("work_done", {"key": key, "seats": seats, "shared": shared >= 2})

static func _ring_bell(sim: HotelSim, seat: int) -> void:
	if sim.s["bell_cd"] > 0 and sim.s["tick"] < sim.s["bell_cd"]:
		return
	sim.s["bell_cd"] = sim.s["tick"] + SimC.BELL_COOLDOWN
	sim.emit("bell", {"seat": seat})
	if sim.tutorial != null:
		sim.tutorial.on_bell(sim, seat)
	if sim.can_finish_early():
		sim.request_finish(seat)

static func introduced_families(sim: HotelSim) -> Array:
	if sim.cfg.get("mode") in ["playground", "hub"]:
		return SimC.FAMILIES.duplicate()
	var seen := {}
	var ch := int(sim.level.get("chapter", 1))
	for L2 in sim.content.levels:
		if int(L2["chapter"]) > ch:
			continue
		if int(L2["chapter"]) == ch and L2["id"] > sim.level.get("id", "L00") and sim.cfg.get("mode") != "quick":
			continue
		for w in L2["waves"]:
			for f in w["roster"]:
				seen[f] = true
	for gid in sim.s["guests"]:
		seen[sim.s["guests"][gid]["fam"]] = true
	var out: Array = []
	for f in SimC.FAMILIES:
		if seen.has(f):
			out.append(f)
	if out.is_empty():
		out.append("slime")
	return out

# ============================================================ actions/channels

static func _advance_actions(sim: HotelSim) -> void:
	for st in sim.s["staff"]:
		var a: Dictionary = st["act"]
		if a.is_empty():
			continue
		if a.get("channel", false):
			var inp := SimMove.input_vec(st)
			if inp != Vector2i.ZERO or not st["present"]:
				st["act"] = {}
				sim.emit("channel_cancel", {"seat": st["seat"]})
				continue
		a["t"] = int(a["t"]) - 1
		if a["t"] <= 0:
			st["act"] = {}
			if a.get("channel", false):
				_finish_channel(sim, st, a)

static func _finish_channel(sim: HotelSim, st: Dictionary, a: Dictionary) -> void:
	var seat: int = st["seat"]
	var key: String = a["key"]
	var stv: Dictionary = sim.s["st"]
	if st["held"] != 0:
		return
	match key:
		"st:towels", "st:snacks":
			var which := key.substr(3)
			if stv[which] <= 0:
				return
			stv[which] -= 1
			var iid := sim.new_item("towel" if which == "towels" else "snack", {"loc": "held", "seat": seat})
			st["held"] = iid
			sim.emit("take_stock", {"seat": seat, "what": which})
		"st:kiosk":
			var fam: String = SimC.FAMILIES[stv["kiosk_sel"]]
			var iid2 := sim.new_item("welcome_" + fam, {"loc": "held", "seat": seat})
			st["held"] = iid2
			sim.emit("take_gift", {"seat": seat, "family": fam})
		"st:return":
			if stv["curtains_free"] <= 0:
				return
			stv["curtains_free"] -= 1
			var iid3 := sim.new_item("curtain_roll", {"loc": "held", "seat": seat})
			st["held"] = iid3
			sim.emit("take_curtain", {"seat": seat})
		_:
			if key.begins_with("curtain_off:"):
				var letter := key.substr(12)
				var r := sim.room(letter)
				if r["curtain"] == 0:
					return
				var cid: int = r["curtain"]
				r["curtain"] = 0
				hold(sim, st, cid)
				sim.emit("curtain_removed", {"room": letter, "seat": seat})
	var held: int = st["held"]
	if held != 0:
		_note_holder(sim.item(held), seat)

# ============================================================ item helpers

static func hold(sim: HotelSim, st: Dictionary, iid: int) -> void:
	var it := sim.item(iid)
	it["loc"] = "held"; it["seat"] = st["seat"]; it["sock"] = ""; it["idle"] = 0
	st["held"] = iid
	_note_holder(it, st["seat"])

static func _note_holder(it: Dictionary, seat: int) -> void:
	if it.is_empty():
		return
	it["last_holder"] = seat

static func place_world(sim: HotelSim, iid: int, x: int, z: int) -> void:
	var it := sim.item(iid)
	it["loc"] = "world"; it["seat"] = -1; it["sock"] = ""; it["x"] = x; it["z"] = z; it["idle"] = 0

static func sock_item(sim: HotelSim, iid: int, sock: String) -> void:
	var it := sim.item(iid)
	it["loc"] = "sock"; it["seat"] = -1; it["sock"] = sock; it["idle"] = 0

static func _consume_held(sim: HotelSim, st: Dictionary, why: String) -> void:
	var iid: int = st["held"]
	st["held"] = 0
	sim.consume_item(iid, why)

## Nearest valid floor spot within 0.8 m of (ox,oz) on a 0.25 m lattice,
## preferring the point in front of the facing vector.
static func floor_spot(sim: HotelSim, ox: int, oz: int, fx: int, fz: int, from_x: int, from_z: int) -> Vector2i:
	var px := ox + fx * 450
	var pz := oz + fz * 450
	var best := Vector2i(-1, -1)
	var best_d := 1 << 62
	var lat := SimC.FLOOR_LATTICE
	var gx0 := int(floor(float(ox - SimC.FLOOR_PLACE_RADIUS) / lat))
	var gz0 := int(floor(float(oz - SimC.FLOOR_PLACE_RADIUS) / lat))
	var steps := 2 * SimC.FLOOR_PLACE_RADIUS / lat + 2
	for j in steps:
		for i in steps:
			var x := (gx0 + i) * lat
			var z := (gz0 + j) * lat
			if SimMove.dist(x, z, ox, oz) > SimC.FLOOR_PLACE_RADIUS:
				continue
			if not _spot_valid(sim, x, z, from_x, from_z):
				continue
			var d := (x - px) * (x - px) + (z - pz) * (z - pz)
			if d < best_d or (d == best_d and (x < best.x or (x == best.x and z < best.y))):
				best_d = d
				best = Vector2i(x, z)
	return best

static func _spot_valid(sim: HotelSim, x: int, z: int, from_x: int, from_z: int) -> bool:
	if not SimMove.point_free(sim, x, z, SimC.ITEM_RADIUS):
		return false
	var tx := LayoutDef.tile_of(x)
	var tz := LayoutDef.tile_of(z)
	if sim.L.is_wall_tile(tx, tz):
		return false
	for iid in sim.s["items"]:
		var it: Dictionary = sim.s["items"][iid]
		if it["loc"] == "world" and absi(it["x"] - x) < SimC.ITEM_SPACING and absi(it["z"] - z) < SimC.ITEM_SPACING:
			return false
	for p in sim.L.fixtures["pedestals"]:
		if absi(p.x * SimC.UM - x) < 350_000 and absi(p.y * SimC.UM - z) < 350_000:
			return false
	var bell: Vector2i = sim.L.fixtures["group_bell"]
	if absi(bell.x * SimC.UM - x) < 400_000 and absi(bell.y * SimC.UM - z) < 400_000:
		return false
	for lp in sim.L.lift_pads:
		if absi(lp.x * SimC.UM - x) < 450_000 and absi(lp.y * SimC.UM - z) < 450_000:
			return false
	return SimMove.line_clear(sim, from_x, from_z, x, z)

# ============================================================ timers (§7.3, §6.6)

static func step_timers(sim: HotelSim) -> void:
	var stv: Dictionary = sim.s["st"]
	# Laundry
	if stv["hamper_q"] > 0:
		if stv["linen"] < SimC.LINEN_CAP:
			stv["hamper_t"] += 1
			if stv["hamper_t"] >= SimC.HAMPER_CYCLE:
				stv["hamper_t"] = 0
				stv["hamper_q"] -= 1
				stv["linen"] += 1
				SimScore.bump(sim, "laundry_cycles")
				sim.emit("laundry_done", {"q": stv["hamper_q"]})
		elif stv["hamper_t"] >= SimC.HAMPER_CYCLE - 1:
			stv["laundry_hold"] = 1
	for which in ["towels", "snacks"]:
		if stv[which] < SimC.STOCK_CAP and not station_tripped(sim, which):
			var tk := "towel_t" if which == "towels" else "snack_t"
			stv[tk] += 1
			if stv[tk] >= SimC.STOCK_REGEN:
				stv[tk] = 0
				stv[which] += 1
				sim.emit("stock_refill", {"what": which})
	# Items: idle recovery
	var to_return: Array = []
	for iid in sim.s["items"]:
		var it: Dictionary = sim.s["items"][iid]
		# A ticket forgotten on a pass counter goes home like one left on the floor.
		var parked: bool = it["loc"] == "sock" and str(it["sock"]).begins_with("counter:") and it["k"] in ["ticket", "move_ticket"]
		if it["loc"] != "world" and not parked:
			continue
		it["idle"] = int(it["idle"]) + 1
		var k: String = it["k"]
		if k == "ticket" and it["idle"] >= SimC.TICKET_RETURN:
			to_return.append(iid)
		elif k == "move_ticket" and it["idle"] >= SimC.TICKET_RETURN:
			to_return.append(iid)
		elif k in ["mop", "breezer", "watering_can", "curtain_roll"] and not _in_bounds(sim, it) and it["idle"] >= SimC.TOOL_OOB_RETURN:
			to_return.append(iid)
	for iid in to_return:
		_recover(sim, iid)
	# Pings
	var dead: Array = []
	for seat in sim.s["pings"]:
		var p: Dictionary = sim.s["pings"][seat]
		p["t"] -= 1
		if p["t"] <= 0:
			dead.append(seat)
	for seat in dead:
		sim.s["pings"].erase(seat)
	for st in sim.s["staff"]:
		if st["ping_cd"] > 0:
			st["ping_cd"] -= 1
	SimGoals.step_lifts(sim)

static func _in_bounds(sim: HotelSim, it: Dictionary) -> bool:
	var tx := LayoutDef.tile_of(it["x"])
	var tz := LayoutDef.tile_of(it["z"])
	return not sim.L.is_wall_tile(tx, tz)

static func _recover(sim: HotelSim, iid: int) -> void:
	var it := sim.item(iid)
	match it["k"]:
		"ticket":
			var g := sim.guest(it["g"])
			if g.is_empty() or g["state"] != "lobby":
				sim.consume_item(iid, "stale")
				return
			if g["slot"] >= 0:
				sock_item(sim, iid, "ped:%d" % g["slot"])
			else:
				sock_item(sim, iid, "bench")
			sim.emit("ticket_home", {"id": iid})
		"move_ticket":
			var g2 := sim.guest(it["g"])
			if not g2.is_empty():
				g2["move_ticket"] = 0
			sim.consume_item(iid, "move_cancel")
			sim.emit("move_cancelled", {"guest": it["g"]})
		_:
			_return_tool(sim, iid)

static func _return_tool(sim: HotelSim, iid: int) -> void:
	var it := sim.item(iid)
	if it["k"] == "curtain_roll":
		sim.s["st"]["curtains_free"] += 1
		sim.consume_item(iid, "curtain_home")
		return
	var home: String = it.get("home", "")
	if home == "":
		return
	var parts := home.split(":")
	if _dock_item(sim, parts[1], int(parts[2])) != 0:
		# Find any free dock of the same type.
		var n := 1
		if parts[1] == "mop": n = sim.L.fixtures["mop_docks"].size()
		elif parts[1] == "can": n = _can_count(sim)
		for i in n:
			if _dock_item(sim, parts[1], i) == 0:
				home = "dock:%s:%d" % [parts[1], i]
				break
	sock_item(sim, iid, home)
	sim.emit("tool_home", {"id": iid, "k": it["k"]})

static func find_tools(sim: HotelSim) -> void:
	var ids: Array = []
	for iid in sim.s["items"]:
		var it: Dictionary = sim.s["items"][iid]
		if it["loc"] == "world" and it["k"] in ["mop", "breezer", "watering_can"]:
			ids.append(iid)
	for iid in ids:
		_return_tool(sim, iid)
	sim.emit("find_tools", {"count": ids.size()})

static func safe_release(sim: HotelSim, st: Dictionary) -> void:
	if st["grip"] != 0:
		SimGoals.release_handle(sim, st)
	st["work_key"] = ""
	st["work_toggle"] = false
	st["act"] = {}
	if st["held"] != 0:
		var iid: int = st["held"]
		var spot := floor_spot(sim, st["x"], st["z"], st["fx"], st["fz"], st["x"], st["z"])
		if spot.x == -1:
			spot = Vector2i(st["x"], st["z"])
		place_world(sim, iid, spot.x, spot.y)
		st["held"] = 0
		sim.emit("place", {"seat": st["seat"], "id": iid})

static func release_all(sim: HotelSim) -> void:
	for st in sim.s["staff"]:
		if st["grip"] != 0:
			SimGoals.release_handle(sim, st)
		st["work_key"] = ""
		st["act"] = {}

# ============================================================ pings (§11.2)

static func press_ping(sim: HotelSim, st: Dictionary, radial: bool) -> void:
	if st["ping_cd"] > 0:
		return
	var key: String = st["hl_c"] if st["hl_c"] != "" else st["hl_w"]
	var x: int = st["x"]; var z: int = st["z"]
	var phrase := "help_here"
	if key != "":
		for c in carry_candidates(sim, st) + work_candidates(sim, st):
			if c["key"] == key:
				x = c["ax"]; z = c["az"]
				break
	if st["held"] != 0:
		phrase = "bringing_it"
		var it := sim.item(st["held"])
		it["claim"] = st["seat"]; it["claim_t"] = sim.s["tick"]
	elif key.begins_with("plaque:") and sim.room_assignable(key.substr(7)) == "":
		phrase = "room_ready"
	var radial_pick: int = int(st.get("ping_pick", -1))
	if radial_pick >= 0:
		phrase = ["help_here", "bringing_it", "room_ready", "thank_you"][radial_pick % 4]
	sim.s["pings"][st["seat"]] = {"seat": st["seat"], "x": x, "z": z, "phrase": phrase, "key": key, "t": SimC.PING_TICKS}
	st["ping_cd"] = SimC.PING_COOLDOWN
	sim.emit("ping", {"seat": st["seat"], "phrase": phrase, "key": key})
	if sim.tutorial != null:
		sim.tutorial.on_ping(sim, st["seat"], phrase)
