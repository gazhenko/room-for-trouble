class_name ReferenceBot
extends RefCounted
## Transparent scripted driver for mechanical reference runs (§24.2). It plays
## through the same per-seat input frames as people: stick axes plus Carry/Work
## presses, acting only when the simulation highlights the intended target.
## It never touches simulation state directly. Not a family playtest.

const CELL := 250_000
var sim: HotelSim
var tasks: Dictionary = {}      # seat -> task
var claims: Dictionary = {}     # job key -> seat
var nav_w := 0
var nav_h := 0
var blocked := PackedByteArray()
var stuck: Dictionary = {}
var use_helpers := false
var use_quick_step := false
var stats := {"tasks": 0, "repaths": 0, "work_ticks": 0, "busy_ticks": 0, "idle_ticks": 0}

func _init(p_sim: HotelSim) -> void:
	sim = p_sim
	_build_nav()

func _build_nav() -> void:
	nav_w = int(28_000_000 / CELL) + 4
	nav_h = int(20_000_000 / CELL) + 4
	blocked.resize(nav_w * nav_h)
	for j in nav_h:
		for i in nav_w:
			var p := _cell_center(i, j)
			blocked[j * nav_w + i] = 0 if SimMove.point_free(sim, p.x, p.y, SimC.RADIUS + 30_000) else 1

func _cell_center(i: int, j: int) -> Vector2i:
	return Vector2i(-500_000 + i * CELL + CELL / 2, -500_000 + j * CELL + CELL / 2)

func _cell_of(x: int, z: int) -> Vector2i:
	return Vector2i(clampi((x + 500_000) / CELL, 0, nav_w - 1), clampi((z + 500_000) / CELL, 0, nav_h - 1))

func _free(i: int, j: int) -> bool:
	if i < 0 or j < 0 or i >= nav_w or j >= nav_h:
		return false
	if blocked[j * nav_w + i] == 1:
		return false
	var sh := sim.L.shutter
	if sh.x >= 0 and sim.s["shutter"]["state"] != "open":
		var c := _cell_center(i, j)
		if absi(c.x - sh.x * SimC.UM) < 800_000 and absi(c.y - sh.y * SimC.UM) < 800_000:
			return false
	return true

func path(from: Vector2i, to: Vector2i) -> Array:
	var a := _cell_of(from.x, from.y)
	var b := _cell_of(to.x, to.y)
	if not _free(b.x, b.y):
		b = _nearest_free(b)
	if not _free(a.x, a.y):
		a = _nearest_free(a)
	var start := a.y * nav_w + a.x
	var goal := b.y * nav_w + b.x
	var came := {start: -1}
	var q: Array = [start]
	var qi := 0
	while qi < q.size():
		var c: int = q[qi]
		qi += 1
		if c == goal:
			break
		var cx := c % nav_w
		var cz := c / nav_w
		for d in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
			var nx: int = cx + d[0]
			var nz: int = cz + d[1]
			var n := nz * nav_w + nx
			if came.has(n) or not _free(nx, nz):
				continue
			came[n] = c
			q.append(n)
	if not came.has(goal):
		return [to]
	var cells: Array = []
	var at := goal
	while at != -1:
		cells.push_front(at)
		at = came[at]
	var pts: Array = []
	for c2 in cells:
		pts.append(_cell_center(c2 % nav_w, c2 / nav_w))
	# Simple string pulling.
	var out: Array = []
	var i := 0
	while i < pts.size():
		var j := mini(pts.size() - 1, i + 12)
		while j > i + 1 and not _clear(pts[i], pts[j]):
			j -= 1
		out.append(pts[j])
		i = j if j > i else i + 1
	return out

func _clear(a: Vector2i, b: Vector2i) -> bool:
	var n := maxi(1, int(Vector2(b - a).length() / 120_000))
	for k in n + 1:
		var p := a + (b - a) * k / n
		var c := _cell_of(p.x, p.y)
		if not _free(c.x, c.y):
			return false
	return true

func _nearest_free(c: Vector2i) -> Vector2i:
	for r in range(1, 10):
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if _free(c.x + dx, c.y + dz):
					return Vector2i(c.x + dx, c.y + dz)
	return c

# ------------------------------------------------------------ planning

func _um(t: Vector2i) -> Vector2i:
	return Vector2i(t.x * SimC.UM, t.y * SimC.UM)

func frames() -> Array:
	var out: Array = []
	if sim.s["phase"] == "planning":
		for st in sim.s["staff"]:
			out.append({"seat": st["seat"], "ax": 0, "az": 0, "held": 0, "pressed": SimC.BTN_READY if not st["ready"] else 0})
		return out
	for st in sim.s["staff"]:
		out.append(_drive(st))
	return out

func _drive(st: Dictionary) -> Dictionary:
	var seat: int = st["seat"]
	if not st["act"].is_empty():
		# Let quick actions and channels (dispensing) finish undisturbed.
		return {"seat": seat, "ax": 0, "az": 0, "held": 0, "pressed": 0}
	var t: Dictionary = tasks.get(seat, {})
	if t.is_empty() or not _task_valid(st, t):
		if not t.is_empty():
			claims.erase(t.get("claim", ""))
		t = _choose(st)
		tasks[seat] = t
		if not t.is_empty():
			stats["tasks"] += 1
	if t.is_empty():
		stats["idle_ticks"] += 1
		return {"seat": seat, "ax": 0, "az": 0, "held": 0, "pressed": 0}
	stats["busy_ticks"] += 1
	if st["grip"] != 0:
		return _drive_trunk(st, t)
	var goal: Vector2i = t["stand"]
	var pos := Vector2i(st["x"], st["z"])
	var d := SimMove.dist(pos.x, pos.y, goal.x, goal.y)
	var anchor: Vector2i = t["anchor"]
	var fv := Vector2(anchor - pos)
	var hl: String = st["hl_c"] if t["action"] == "carry" else st["hl_w"]
	var ok: bool = st["hl_c_ok"] if t["action"] == "carry" else st["hl_w_ok"]
	var want: String = t["key"]
	var working: bool = t["action"] == "work" and st["work_key"] == want
	if working:
		stats["work_ticks"] += 1
		return {"seat": seat, "ax": 0, "az": 0, "held": SimC.BTN_WORK, "pressed": 0}
	var ready := hl == want and ok
	if not ready and d > 300_000:
		if not t.has("path") or t.get("goal_used", Vector2i(-1, -1)) != goal or int(t.get("pi", 0)) >= t["path"].size():
			t["path"] = path(pos, goal)
			t["pi"] = 0
			t["goal_used"] = goal
			stats["repaths"] += 1
		var wp: Vector2i = t["path"][int(t["pi"])]
		if SimMove.dist(pos.x, pos.y, wp.x, wp.y) < 200_000:
			t["pi"] = int(t["pi"]) + 1
			if int(t["pi"]) >= t["path"].size():
				t["pi"] = t["path"].size() - 1
			wp = t["path"][int(t["pi"])]
		var v := Vector2(wp - pos)
		var key := str(seat)
		var prev: Vector2i = stuck.get(key + "p", pos)
		var sc: int = stuck.get(key + "n", 0)
		sc = sc + 1 if SimMove.dist(prev.x, prev.y, pos.x, pos.y) < 2_000 else 0
		stuck[key + "p"] = pos
		stuck[key + "n"] = sc
		if sc > 20:
			t.erase("path")
			stuck[key + "n"] = 0
			v = v.rotated(1.4)
		var mag := clampf(float(d) / 700_000.0, 0.35, 1.0) * 127.0
		v = v.normalized() * mag
		return {"seat": seat, "ax": int(v.x), "az": int(v.y), "held": 0, "pressed": 0}
	if not ready:
		t["wait"] = int(t.get("wait", 0)) + 1
		if int(t["wait"]) > 60:
			claims.erase(t.get("claim", ""))
			tasks.erase(seat)
		var nudge := fv.normalized() * 32.0
		return {"seat": seat, "ax": int(nudge.x), "az": int(nudge.y), "held": 0, "pressed": 0}
	if t["action"] == "carry":
		if not st["act"].is_empty():
			return {"seat": seat, "ax": 0, "az": 0, "held": 0, "pressed": 0}
		t["done"] = true
		return {"seat": seat, "ax": 0, "az": 0, "held": SimC.BTN_CARRY, "pressed": SimC.BTN_CARRY}
	stats["work_ticks"] += 1
	var press := SimC.BTN_WORK if st["work_key"] == "" else 0
	if press != 0:
		t["presses"] = int(t.get("presses", 0)) + 1
		if int(t["presses"]) > 6:
			t["done"] = true
	return {"seat": seat, "ax": 0, "az": 0, "held": SimC.BTN_WORK, "pressed": press}

func _drive_trunk(st: Dictionary, t: Dictionary) -> Dictionary:
	var tr: Dictionary = sim.s["trunks"].get(st["grip"], {})
	var gp: Vector2i = _um(sim.L.fixtures["goal_pad"])
	if tr.is_empty() or tr["delivered"]:
		return {"seat": st["seat"], "ax": 0, "az": 0, "held": 0, "pressed": SimC.BTN_CARRY}
	var v := Vector2(gp.x - tr["x"], gp.y - tr["z"])
	if absf(v.y) > 150_000:
		v = Vector2(0, v.y)
	v = v.normalized() * 127.0
	return {"seat": st["seat"], "ax": int(v.x), "az": int(v.y), "held": 0, "pressed": 0}

func _task_valid(st: Dictionary, t: Dictionary) -> bool:
	if t.get("done", false):
		# Carry tasks finish on press; work tasks when the key is gone.
		if t["action"] == "carry":
			return false
		if st["work_key"] == "" and int(t.get("presses", 0)) > 0:
			return false
	if t.has("check") and not (t["check"] as Callable).call():
		return false
	return true

func _stand_for(anchor: Vector2i, reach: int = 900_000) -> Vector2i:
	var best := anchor
	var bd := 1 << 62
	for k in 16:
		var ang := TAU * k / 16.0
		for r in [650_000, 800_000, 500_000, 950_000]:
			if r > reach:
				continue
			var p := anchor + Vector2i(int(cos(ang) * r), int(sin(ang) * r))
			var c := _cell_of(p.x, p.y)
			if not _free(c.x, c.y):
				continue
			if not SimMove.line_clear(sim, p.x, p.y, anchor.x, anchor.y):
				continue
			var d := absi(p.y - anchor.y) + absi(p.x - anchor.x) / 2
			if d < bd:
				bd = d
				best = p
	return best

func _task(key: String, action: String, anchor: Vector2i, claim := "", check := Callable(), reach := 900_000) -> Dictionary:
	var t := {"key": key, "action": action, "anchor": anchor, "stand": _stand_for(anchor, reach), "claim": claim}
	if check.is_valid():
		t["check"] = check
	return t

func _claimed(c: String, seat: int) -> bool:
	return claims.has(c) and claims[c] != seat

func _claim(t: Dictionary, seat: int) -> Dictionary:
	if t.is_empty():
		return t
	if t["claim"] != "":
		claims[t["claim"]] = seat
	return t

func _choose(st: Dictionary) -> Dictionary:
	var seat: int = st["seat"]
	var hk := SimInteract.held_kind(sim, st)
	if hk != "":
		return _claim(_deliver(st, hk), seat)
	for fn in [_job_finish, _job_trunk, _job_request, _job_ticket, _job_welcome, _job_thermo, _job_gate, _job_curtain,
			_job_water, _job_frost, _job_trip, _job_cloud, _job_bed, _job_mess, _job_puddle, _job_parcel, _job_helper, _job_press]:
		var t: Dictionary = fn.call(st)
		if not t.is_empty() and not _claimed(t["claim"], seat):
			return _claim(t, seat)
	return {}

func _guest_need_gift(g: Dictionary) -> bool:
	return g["state"] in ["walking", "staying"] and not g["welcomed"] and g["room"] != "" and sim.room(g["room"])["gift"] == 0

func _ideal_mode(fam: String) -> String:
	match fam:
		"yeti": return "cool"
		"dragon": return "warm"
	return "neutral"

func _pick_room(fam: String) -> String:
	var best := ""
	var best_score := -999
	for letter in sim.L.active_rooms:
		if sim.room_assignable(letter) != "":
			continue
		var r := sim.room(letter)
		var score := 0
		if sim.has_sys("thermal"):
			score += 10 if r["thermo"] == _ideal_mode(fam) else 0
			var c: Dictionary = sim.content.guest_def(fam).get("comfort", {})
			if c.has("heat_min") and r["heat"] >= int(c["heat_min"]) and r["heat"] <= int(c["heat_max"]):
				score += 5
		if fam == "ghost" and sim.has_sys("sound"):
			score += 8 if not _wolf_neighbor(letter) else -6
			score += 4 if r["curtain"] != 0 else 0
		if fam == "moonwolf" and sim.has_sys("sound"):
			score += 6 if not _ghost_neighbor(letter) else -6
		if fam == "sprout":
			score += r["hum"] / 10
		score -= _room_distance(letter) / 4_000_000
		if score > best_score:
			best_score = score
			best = letter
	return best

func _room_distance(letter: String) -> int:
	var d: Vector2i = sim.L.rooms[letter]["door"]
	var p: Vector2i = sim.L.fixtures["pedestals"][0]
	return absi(d.x - p.x) * SimC.UM + absi(d.y - p.y) * SimC.UM

func _neighbors(letter: String) -> Array:
	var out: Array = []
	for e in sim.L.acoustic_edges:
		if e.substr(0, 1) == letter: out.append(e.substr(1, 1))
		elif e.substr(1, 1) == letter: out.append(e.substr(0, 1))
	return out

func _wolf_neighbor(letter: String) -> bool:
	for n in _neighbors(letter):
		var g := sim.guest(sim.room(n)["guest"] if sim.room(n)["guest"] != 0 else sim.room(n)["reserved"])
		if g.get("fam", "") == "moonwolf":
			return true
	return false

func _ghost_neighbor(letter: String) -> bool:
	for n in _neighbors(letter):
		var g := sim.guest(sim.room(n)["guest"] if sim.room(n)["guest"] != 0 else sim.room(n)["reserved"])
		if g.get("fam", "") == "ghost":
			return true
	return false

func _deliver(st: Dictionary, hk: String) -> Dictionary:
	var it := sim.item(st["held"])
	var F: Dictionary = sim.L.fixtures
	match hk:
		"ticket":
			var g := sim.guest(it["g"])
			var room := _pick_room(g.get("fam", "slime"))
			if room == "":
				return {}
			return _task("plaque:" + room, "carry", SimInteract.plaque_pos(sim, room), "room:" + room)
		"linen_clean":
			for letter in sim.L.active_rooms:
				var r := sim.room(letter)
				if r["guest"] == 0 and r["reserved"] == 0 and r["bed"] == "Stripped":
					return _task("make:" + letter, "work", _um(sim.L.rooms[letter]["bed"]), "bed:" + letter, func(): return sim.room(letter)["bed"] == "Stripped")
				if r["guest"] == 0 and r["reserved"] == 0 and r["bed"] == "Dirty":
					return _task("strip:" + letter, "work", _um(sim.L.rooms[letter]["bed"]), "bed:" + letter, func(): return sim.room(letter)["bed"] == "Dirty")
			return _task("st:linen", "carry", _um(F["linen_shelf"]))
		"linen_dirty":
			return _task("st:hamper", "carry", _um(F["hamper"]))
		"towel", "snack":
			for gid in sim.s["guests"]:
				var g2: Dictionary = sim.s["guests"][gid]
				if g2["state"] == "staying" and SimGuests.open_request(sim, g2, hk) >= 0:
					return _task("guest:%d" % gid, "carry", Vector2i(g2["x"], g2["z"]), "", func(): return SimGuests.open_request(sim, sim.guest(gid), hk) >= 0)
			return _task("st:return", "carry", _um(F["return_shelf"]))
		"mop":
			var t := _mop_target(st)
			if not t.is_empty():
				return t
			return _dock_task("mop")
		"breezer":
			for cid in sim.s["clouds"]:
				var c: Dictionary = sim.s["clouds"][cid]
				return _task("cloud:%d" % cid, "work", Vector2i(c["x"], c["z"]), "", func(): return sim.s["clouds"].has(cid), 1_200_000)
			return _dock_task("breezer")
		"watering_can":
			if int(it.get("ch", 0)) <= 0:
				return _task("tap", "work", _um(F["tap"]), "", func(): return int(sim.item(st["held"]).get("ch", 0)) < 3)
			var room2 := _dry_sprout_room()
			if room2 != "":
				return _task("tray:" + room2, "work", _um(sim.L.rooms[room2]["tray"]), "tray:" + room2, func(): return sim.room(room2)["tray"] < 30)
			return _dock_task("can")
		"curtain_roll":
			var target := _curtain_room()
			if target != "":
				return _task("hang:" + target, "work", SimInteract.door_pos(sim, target), "curtain:" + target, func(): return sim.room(target)["curtain"] == 0)
			return _task("st:return", "carry", _um(F["return_shelf"]))
		"festival_parcel":
			return _task("st:stand", "carry", _um(F["festival_stand"]))
		"move_ticket":
			for letter in sim.L.active_rooms:
				if sim.room_assignable(letter) == "" and letter != it["home"]:
					return _task("plaque:" + letter, "carry", SimInteract.plaque_pos(sim, letter), "room:" + letter)
	if hk.begins_with("welcome_"):
		var fam := hk.substr(8)
		for gid in sim.s["guests"]:
			var g3: Dictionary = sim.s["guests"][gid]
			if g3["fam"] == fam and _guest_need_gift(g3):
				var letter2: String = g3["room"]
				return _task("plinth:" + letter2, "carry", _um(sim.L.rooms[letter2]["plinth"]), "", func(): return sim.room(letter2)["gift"] == 0)
		return _task("st:kiosk", "carry", _um(F["welcome_kiosk"]))
	return {}

func _dock_task(dtype: String) -> Dictionary:
	var n := 2 if dtype in ["mop"] else (1 if dtype == "breezer" else SimInteract._can_count(sim))
	for i in n:
		if SimInteract._dock_item(sim, dtype, i) == 0:
			return _task("dock:%s:%d" % [dtype, i], "carry", SimInteract.dock_pos(sim, dtype, i))
	return {}

func _mop_target(st: Dictionary) -> Dictionary:
	for letter in sim.L.active_rooms:
		var r := sim.room(letter)
		if r["mess"] > 0 and r["guest"] == 0 and r["reserved"] == 0 and r["bed"] == "Made":
			var g: Dictionary = sim.L.rooms[letter]
			var rect: Rect2i = g["rect"]
			var c := Vector2i((rect.position.x + rect.size.x / 2) * SimC.UM, (rect.position.y + rect.size.y / 2) * SimC.UM)
			var t := _task("mess:" + letter, "work", c, "mess:" + letter, func(): return sim.room(letter)["mess"] > 0)
			t["stand"] = Vector2i(_um(g["bed"]).x, _um(g["bed"]).y + (900_000 if g["side"] == "north" else -900_000))
			return t
	for pid in sim.s["puddles"]:
		var p: Dictionary = sim.s["puddles"][pid]
		return _task("puddle:%d" % pid, "work", Vector2i(p["x"], p["z"]), "puddle:%d" % pid, func(): return sim.s["puddles"].has(pid))
	return {}

func _dry_sprout_room() -> String:
	for gid in sim.s["guests"]:
		var g: Dictionary = sim.s["guests"][gid]
		if g["fam"] == "sprout" and g["state"] in ["staying", "walking"] and g["room"] != "":
			var r := sim.room(g["room"])
			if r["hum"] < 62 and r["tray"] < 30:
				return g["room"]
	return ""

func _curtain_room() -> String:
	for gid in sim.s["guests"]:
		var g: Dictionary = sim.s["guests"][gid]
		if g["fam"] == "ghost" and g["state"] in ["staying", "walking"] and g["room"] != "":
			if sim.room(g["room"])["curtain"] == 0 and _wolf_neighbor(g["room"]):
				return g["room"]
	for gid in sim.s["guests"]:
		var g2: Dictionary = sim.s["guests"][gid]
		if g2["fam"] == "moonwolf" and g2["state"] in ["staying", "walking"] and g2["room"] != "":
			if sim.room(g2["room"])["curtain"] == 0 and _ghost_neighbor(g2["room"]):
				return g2["room"]
	return ""

# ------------------------------------------------------------ jobs (empty hands)

func _job_ticket(st: Dictionary) -> Dictionary:
	var best := {}
	var bp := 1 << 62
	for gid in sim.s["guests"]:
		var g: Dictionary = sim.s["guests"][gid]
		if g["state"] != "lobby" or g["slot"] < 0:
			continue
		if _pick_room(g["fam"]) == "":
			continue
		if g["patience_q"] < bp and not _claimed("ticket:%d" % gid, st["seat"]):
			bp = g["patience_q"]
			var slot: int = g["slot"]
			var p: Vector2i = sim.L.fixtures["pedestals"][slot]
			best = _task("ped:%d" % slot, "carry", _um(p) + Vector2i(0, 150_000), "ticket:%d" % gid, func(): return sim.guest(gid).get("state", "") == "lobby", 800_000)
	return best

## What teammates already carry or are fetching: {"towel": n, "snack": n, "gift_<fam>": n}.
func _intent(st: Dictionary) -> Dictionary:
	var out := {}
	for o in sim.s["staff"]:
		if o["seat"] == st["seat"]:
			continue
		var k := SimInteract.held_kind(sim, o)
		if k == "towel" or k == "snack":
			out[k] = int(out.get(k, 0)) + 1
		elif k.begins_with("welcome_"):
			out["gift_" + k.substr(8)] = int(out.get("gift_" + k.substr(8), 0)) + 1
		var t: Dictionary = tasks.get(o["seat"], {})
		match t.get("key", ""):
			"st:towels": out["towel"] = int(out.get("towel", 0)) + 1
			"st:snacks": out["snack"] = int(out.get("snack", 0)) + 1
			"st:kiosk", "kiosk_cycle":
				var f: String = t.get("fam", "")
				if f != "":
					out["gift_" + f] = int(out.get("gift_" + f, 0)) + 1
	return out

func _job_request(st: Dictionary) -> Dictionary:
	var intent := _intent(st)
	var open := {"towel": 0, "snack": 0}
	for gid0 in sim.s["guests"]:
		var g0: Dictionary = sim.s["guests"][gid0]
		if g0["state"] == "staying":
			for rq0 in g0["reqs"]:
				if rq0["st"] == "open":
					open[rq0["k"]] += 1
	for gid in sim.s["guests"]:
		var g: Dictionary = sim.s["guests"][gid]
		if g["state"] != "staying":
			continue
		for rq in g["reqs"]:
			if rq["st"] != "open":
				continue
			var c := "req:%d:%s" % [gid, rq["k"]]
			if _claimed(c, st["seat"]) or int(open[rq["k"]]) <= int(intent.get(rq["k"], 0)):
				continue
			var which := "towels" if rq["k"] == "towel" else "snacks"
			if sim.s["st"][which] <= 0:
				continue
			var F: Dictionary = sim.L.fixtures
			return _task("st:" + which, "carry", _um(F["towel_shelf" if which == "towels" else "snack_tin"]), c)
	return {}

func _job_welcome(st: Dictionary) -> Dictionary:
	var intent := _intent(st)
	var need := {}
	for gid0 in sim.s["guests"]:
		var g0: Dictionary = sim.s["guests"][gid0]
		if _guest_need_gift(g0):
			need[g0["fam"]] = int(need.get(g0["fam"], 0)) + 1
	for gid in sim.s["guests"]:
		var g: Dictionary = sim.s["guests"][gid]
		if not _guest_need_gift(g):
			continue
		if int(need.get(g["fam"], 0)) <= int(intent.get("gift_" + g["fam"], 0)):
			continue
		var c := "gift:%d" % gid
		if _claimed(c, st["seat"]):
			continue
		var sel: String = SimC.FAMILIES[sim.s["st"]["kiosk_sel"]]
		var kp := _um(sim.L.fixtures["welcome_kiosk"])
		var t: Dictionary
		if sel != g["fam"]:
			t = _task("kiosk_cycle", "work", kp, "kiosk", func(): return SimC.FAMILIES[sim.s["st"]["kiosk_sel"]] != g["fam"])
		else:
			t = _task("st:kiosk", "carry", kp, c)
		t["fam"] = g["fam"]
		return t
	return {}

func _job_thermo(st: Dictionary) -> Dictionary:
	if not sim.has_sys("thermal"):
		return {}
	for letter in sim.L.active_rooms:
		var r := sim.room(letter)
		var gid: int = r["guest"] if r["guest"] != 0 else r["reserved"]
		if gid == 0:
			continue
		var want := _ideal_mode(sim.guest(gid)["fam"])
		if r["thermo"] != want and not SimInteract.station_tripped(sim, "radiator_" + letter):
			return _task("thermo:" + letter, "work", SimInteract.thermo_pos(sim, letter), "thermo:" + letter, func(): return sim.room(letter)["thermo"] != want)
	return {}

func _job_gate(st: Dictionary) -> Dictionary:
	if not sim.has_sys("thermal"):
		return {}
	for e in sim.L.thermal_edges:
		if not sim.s["gates"].get(e, false):
			continue
		var ab := sim.L.edge_rooms(e)
		var ma: String = sim.room(ab[0])["thermo"]
		var mb: String = sim.room(ab[1])["thermo"]
		var conflict = (ma == "warm" and mb == "cool") or (ma == "cool" and mb == "warm") or ((ma == "neutral") != (mb == "neutral") and (sim.room(ab[0])["guest"] != 0 and sim.room(ab[1])["guest"] != 0))
		if conflict:
			return _task("gate:" + e, "work", SimInteract.gate_pos(sim, e), "gate:" + e, func(): return sim.s["gates"].get(e, false))
	return {}

func _job_curtain(st: Dictionary) -> Dictionary:
	if not sim.has_sys("sound") or sim.s["st"]["curtains_free"] <= 0:
		return {}
	if _curtain_room() == "":
		return {}
	return _task("st:return", "carry", _um(sim.L.fixtures["return_shelf"]), "curtain_fetch")

func _job_water(st: Dictionary) -> Dictionary:
	if not sim.has_sys("moisture") or _dry_sprout_room() == "":
		return {}
	for i in SimInteract._can_count(sim):
		var can := SimInteract._dock_item(sim, "can", i)
		if can != 0:
			return _task("dock:can:%d" % i, "carry", SimInteract.dock_pos(sim, "can", i), "can")
	return {}

func _job_frost(st: Dictionary) -> Dictionary:
	for letter in sim.L.active_rooms:
		if sim.room(letter)["frost"]:
			return _task("frost:" + letter, "work", SimInteract.door_pos(sim, letter), "frost:" + letter, func(): return sim.room(letter)["frost"])
	return {}

func _job_trip(st: Dictionary) -> Dictionary:
	for fx in sim.s["st"]["trips"]:
		var a := Vector2i.ZERO
		if fx.begins_with("radiator_"):
			a = SimInteract.thermo_pos(sim, fx.substr(9))
		elif fx == "towels":
			a = _um(sim.L.fixtures["towel_shelf"])
		elif fx == "snacks":
			a = _um(sim.L.fixtures["snack_tin"])
		else:
			a = _um(sim.L.lift_pads[0])
		return _task("trip:" + fx, "work", a, "trip:" + fx, func(): return SimInteract.station_tripped(sim, fx))
	return {}

func _job_cloud(st: Dictionary) -> Dictionary:
	if sim.s["clouds"].is_empty():
		return {}
	var b := SimInteract._dock_item(sim, "breezer", 0)
	if b == 0:
		return {}
	return _task("dock:breezer:0", "carry", SimInteract.dock_pos(sim, "breezer", 0), "breezer")

func _job_bed(st: Dictionary) -> Dictionary:
	for letter in sim.L.active_rooms:
		var r := sim.room(letter)
		if r["guest"] != 0 or r["reserved"] != 0:
			continue
		if r["bed"] == "Dirty":
			return _task("strip:" + letter, "work", _um(sim.L.rooms[letter]["bed"]), "bed:" + letter, func(): return sim.room(letter)["bed"] == "Dirty")
		if r["bed"] == "Stripped" and not _claimed("bed:" + letter, st["seat"]):
			if sim.s["st"]["linen"] > 0:
				return _task("st:linen", "carry", _um(sim.L.fixtures["linen_shelf"]), "bed:" + letter)
			return _task("press", "work", _um(sim.L.fixtures["linen_shelf"]), "press", func(): return sim.s["st"]["linen"] == 0)
	# Pick up dirty bundles lying around.
	for iid in sim.s["items"]:
		var it: Dictionary = sim.s["items"][iid]
		if it["k"] == "linen_dirty" and it["loc"] == "world":
			return _task("pick:%d" % iid, "carry", Vector2i(it["x"], it["z"]), "pick:%d" % iid, func(): return sim.item(iid).get("loc", "") == "world", 700_000)
	return {}

func _job_mess(st: Dictionary) -> Dictionary:
	if _mop_target(st).is_empty():
		return {}
	for i in 2:
		if SimInteract._dock_item(sim, "mop", i) != 0:
			return _task("dock:mop:%d" % i, "carry", SimInteract.dock_pos(sim, "mop", i), "mop%d" % i)
	return {}

func _job_puddle(st: Dictionary) -> Dictionary:
	return {}

func _job_parcel(st: Dictionary) -> Dictionary:
	for iid in sim.s["items"]:
		var it: Dictionary = sim.s["items"][iid]
		if it["k"] == "festival_parcel" and it["loc"] == "world":
			return _task("pick:%d" % iid, "carry", Vector2i(it["x"], it["z"]), "parcel:%d" % iid, func(): return sim.item(iid).get("loc", "") == "world", 700_000)
	return {}

func _job_trunk(st: Dictionary) -> Dictionary:
	for tid in sim.s["trunks"]:
		var tr: Dictionary = sim.s["trunks"][tid]
		if tr["delivered"]:
			continue
		for h in [1, 0]:
			if tr["h"][h] == -1 and not _claimed("trunk:%d:%d" % [tid, h], st["seat"]):
				var hp := SimGoals.handle_pos(tr, h)
				var spot := hp + Vector2i(-450_000 if h == 0 else 450_000, 0)
				var sc := _cell_of(spot.x, spot.y)
				if not _free(sc.x, sc.y):
					spot = hp
					sc = _cell_of(spot.x, spot.y)
					if not _free(sc.x, sc.y):
						continue
				var t := _task("handle:%d:%d" % [tid, h], "carry", hp, "trunk:%d:%d" % [tid, h], func(): return not sim.s["trunks"][tid]["delivered"], 700_000)
				t["stand"] = spot
				return t
	return {}

func _job_helper(st: Dictionary) -> Dictionary:
	if not use_helpers:
		return {}
	for gid in sim.s["guests"]:
		var g: Dictionary = sim.s["guests"][gid]
		if g["state"] == "staying" and g.get("helper_ready", false) and SimGuests.helper_preview(sim, g)["useful"]:
			return _task("helper:%d" % gid, "work", Vector2i(g["x"], g["z"]), "helper:%d" % gid, func(): return sim.guest(gid).get("helper_ready", false))
	return {}

func _job_finish(st: Dictionary) -> Dictionary:
	if sim.can_finish_early() and sim.s["finish_t"] == 0:
		return _task("bell", "work", _um(sim.L.fixtures["group_bell"]), "bell", func(): return sim.s["finish_t"] == 0 and sim.s["phase"] == "active")
	return {}

func _job_press(st: Dictionary) -> Dictionary:
	if sim.s["st"]["linen"] < 2:
		return _task("press", "work", _um(sim.L.fixtures["linen_shelf"]), "press", func(): return sim.s["st"]["linen"] < 3)
	return {}
