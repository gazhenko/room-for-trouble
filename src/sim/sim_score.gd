class_name SimScore
extends RefCounted
## One transparent team result (§10.4) and teamwork ribbon predicates (§10.5).
## Points are tracked in milli-points; nothing is rounded per guest.

## v2 per-order weights (docs/DESIGN_V2.md §6): every guest is an order worth
## 100 base points, plus tips for speed that can make up for a missed step.
const PTS := {"admission": 30_000, "welcome": 20_000, "service": 30_000, "comfort": 20_000}
const TIP_CHECKIN := 10_000     # ticket on a plaque with two thirds of the patience left
const TIP_WELCOME := 5_000      # matching gift installed within 15 s of entering the room
const TIP_REQUEST := 5_000      # a request served within the first third of its window
const TIP_WELCOME_WINDOW_S := 15

const PREDICATES := ["useful_handoffs", "shared_work", "cozy_departures", "welcome_matches", "laundry_cycles",
	"requests", "vent_solution", "quiet_howls", "balanced_rooms", "water_care", "helpful_guests",
	"relocations", "trunk_goal", "safe_lift_deliveries", "festival_parcels", "tidy_rooms"]

static func init_stats(sim: HotelSim) -> void:
	var st := {}
	for p in PREDICATES:
		st[p] = 0
	st["direct_deliveries"] = 0
	st["work_targets"] = 0
	st["handoff_ids"] = []
	st["lift_ids"] = []
	st["balanced_runs"] = [0, 0, 0, 0, 0, 0, 0]
	st["vent_guests"] = []
	st["water_guests"] = []
	st["handoffs_total"] = 0
	st["rescues"] = 0
	sim.s["stats"] = st

static func bump(sim: HotelSim, key: String, n: int = 1) -> void:
	sim.s["stats"][key] = int(sim.s["stats"].get(key, 0)) + n

static func note_admit(sim: HotelSim, g: Dictionary, seat: int) -> void:
	pass

static func unnote_admit(sim: HotelSim, g: Dictionary) -> void:
	pass

static func note_handoff(sim: HotelSim, it: Dictionary, from_seat: int, to_seat: int) -> void:
	bump(sim, "handoffs_total")

## Called whenever an item is consumed by a valid service, bed, gift or goal.
static func note_consumed(sim: HotelSim, it: Dictionary, seat: int, how: String) -> void:
	if it.is_empty():
		return
	var tick: int = sim.s["tick"]
	var st: Dictionary = sim.s["stats"]
	if how in ["service", "bed", "gift", "goal"]:
		if int(it.get("handoff_from", -1)) != -1 and tick - int(it.get("handoff_t", -9999)) <= SimC.HANDOFF_USE_WINDOW:
			if not it["id"] in st["handoff_ids"]:
				st["handoff_ids"].append(it["id"])
				st["useful_handoffs"] = st["handoff_ids"].size()
				sim.emit("useful_handoff", {"id": it["id"], "seat": seat})
		if how in ["service", "gift"]:
			st["direct_deliveries"] += 1
		if tick - int(it.get("lift_t", -9999)) <= SimC.LIFT_USE_WINDOW:
			if not it["id"] in st["lift_ids"]:
				st["lift_ids"].append(it["id"])
				st["safe_lift_deliveries"] = st["lift_ids"].size()

static func note_work_done(sim: HotelSim, key: String, shared: bool, seats: Array) -> void:
	var kind := key.split(":")[0]
	if kind in ["strip", "make", "mess", "puddle", "cloud", "frost", "tray", "trip", "press", "hang", "tap"]:
		bump(sim, "work_targets")
		if shared:
			bump(sim, "shared_work")
			sim.emit("shared_work", {"key": key, "seats": seats})

static func note_vent_change(sim: HotelSim, letter: String) -> void:
	var r := sim.room(letter)
	if not r.is_empty():
		r["vent_mark_s"] = sim.s["hotel_s"]

static func note_watered(sim: HotelSim, letter: String) -> void:
	var r := sim.room(letter)
	if r["guest"] != 0:
		var g := sim.guest(r["guest"])
		if g.get("fam", "") == "sprout":
			g["watered"] = true

static func note_howl(sim: HotelSim, src: String, received: Dictionary) -> void:
	var src_curt: bool = sim.room(src)["curtain"] != 0
	for dst in received:
		var r := sim.room(dst)
		if r["guest"] == 0:
			continue
		var g := sim.guest(r["guest"])
		if g.get("fam", "") != "ghost" or g.get("state", "") != "staying":
			continue
		var curtained: bool = src_curt or r["curtain"] != 0
		if curtained and r["noise"] <= 20:
			bump(sim, "quiet_howls")
			sim.emit("quiet_howl", {"src": src, "dst": dst})

static func note_departure(sim: HotelSim, g: Dictionary) -> void:
	if g["comf_s"] * 10 >= 8 * g["stay_len"] and g["stay_s"] >= g["stay_len"]:
		bump(sim, "cozy_departures")
		sim.emit("cozy_departure", {"guest": g["id"]})

static func on_guest_second(sim: HotelSim, g: Dictionary, ok: bool) -> void:
	var st: Dictionary = sim.s["stats"]
	if g["streak"] == SimC.HELPER_STREAK_S:
		var r := sim.room(g["room"])
		if int(r.get("vent_mark_s", -1)) >= 0 and not g["id"] in st["vent_guests"]:
			st["vent_guests"].append(g["id"])
			st["vent_solution"] = st["vent_guests"].size()
		if g["fam"] == "sprout" and g.get("watered", false) and not g["id"] in st["water_guests"]:
			st["water_guests"].append(g["id"])
			st["water_care"] = st["water_guests"].size()

## Per action tick: balanced-room runs are evaluated once per hotel second.
static func step(sim: HotelSim) -> void:
	var st: Dictionary = sim.s["stats"]
	var sec: int = sim.s["hotel_s"]
	if int(st.get("bal_last_s", -1)) == sec:
		return
	st["bal_last_s"] = sec
	var n := 0
	for gid in sim.s["guests"]:
		var g: Dictionary = sim.s["guests"][gid]
		if g["state"] == "staying" and not g["relocating"] and g["comfortable"]:
			n += 1
	var runs: Array = st["balanced_runs"]
	for k in range(1, 7):
		if n >= k:
			runs[k] += 1
			if runs[k] >= 10 and k > st["balanced_rooms"]:
				st["balanced_rooms"] = k
				sim.emit("balanced", {"rooms": k})
		else:
			runs[k] = 0

static func tidy_count(sim: HotelSim) -> int:
	var n := 0
	for letter in sim.L.active_rooms:
		var r := sim.room(letter)
		if r["bed"] == "Made" and r["mess"] == 0:
			n += 1
	return n

## Per-guest (per-order) point components in milli-points.
static func guest_points(sim: HotelSim, g: Dictionary) -> Dictionary:
	var adm: int = PTS["admission"] if g["admitted"] and not g["abandoned"] else 0
	var wel: int = PTS["welcome"] if g["welcomed"] else 0
	var svc := 0
	var nreq: int = maxi(1, g["reqs"].size()) if g["admitted"] else int(sim.level.get("service_count", 1))
	var per: int = PTS["service"] / nreq
	for rq in g["reqs"]:
		if rq["st"] == "done":
			svc += per
		elif rq["st"] == "late":
			svc += per / 2
	var comf := 0
	if g["admitted"] and g["stay_len"] > 0:
		comf = PTS["comfort"] * mini(g["comf_s"], g["stay_len"]) / g["stay_len"]
	var tips := int(g.get("tips", 0))
	return {"admission": adm, "welcome": wel, "service": svc, "comfort": comf, "tips": tips,
		"total": adm + wel + svc + comf + tips}

## How an order ended: served (every step on time), late (something was late or
## skipped) or missed (the guest gave up in the lobby).
static func order_outcome(g: Dictionary) -> String:
	if g["abandoned"] or not g["admitted"]:
		return "missed"
	if not g["welcomed"]:
		return "late"
	for rq in g["reqs"]:
		if rq["st"] in ["late", "missed"]:
			return "late"
	return "served"

static func team_result(sim: HotelSim) -> Dictionary:
	var total := 0
	var comp := {"admission": 0, "welcome": 0, "service": 0, "comfort": 0, "tips": 0}
	var orders := {"served": 0, "late": 0, "missed": 0}
	var per_guest: Array = []
	var count := 0
	for gid in sim.s["guests"]:
		var g: Dictionary = sim.s["guests"][gid]
		var p := guest_points(sim, g)
		var outcome := order_outcome(g)
		if g["state"] in ["announced", "lobby", "walking", "staying"] and not g["abandoned"]:
			outcome = "late" if g["admitted"] else "missed"   # still open at the timer
		orders[outcome] = int(orders[outcome]) + 1
		per_guest.append({"id": gid, "fam": g["fam"], "var": g["var"], "points": p, "abandoned": g["abandoned"], "outcome": outcome})
		total += p["total"]
		for k in comp:
			comp[k] += p[k]
		count += 1
	var percent := 0
	if count > 0:
		percent = clampi((total + count * 500) / (count * 1000), 0, 100)
	var stars := 0
	if percent >= 90: stars = 3
	elif percent >= 75: stars = 2
	elif percent >= 55: stars = 1
	var admitted := 0
	for gid in sim.s["guests"]:
		if sim.s["guests"][gid]["admitted"]:
			admitted += 1
	# The roster this party size was dealt, before the schedule dropped guests
	# that could not have been housed before the reserve (ArrivalPlan.schedule).
	var roster := 0
	for wave in ArrivalPlan.expand_waves(sim.level, int(sim.s.get("humans", 1)), sim.L.active_rooms.size()):
		roster += (wave as Array).size()
	return {"percent": percent, "stars": stars, "total_milli": total, "components": comp, "guests": per_guest,
		"scheduled": count, "admitted": admitted, "orders": orders, "roster": roster, "trimmed": maxi(0, roster - count)}

## Records a speed tip on a guest's order and tells the presentation.
static func tip(sim: HotelSim, g: Dictionary, amount_milli: int, seat: int, why: String) -> void:
	g["tips"] = int(g.get("tips", 0)) + amount_milli
	var x: int = g["x"]
	var z: int = g["z"]
	var st := sim.staff_by_seat(seat) if seat >= 0 else {}
	if not st.is_empty():
		x = st["x"]; z = st["z"]
	bump(sim, "tips", amount_milli / 1000)
	sim.emit("tip", {"guest": g["id"], "amount": amount_milli / 1000, "seat": seat, "why": why, "x": x, "z": z})

static func ribbon_value(sim: HotelSim, predicate: String) -> int:
	var st: Dictionary = sim.s["stats"]
	var solo: bool = sim.s["humans"] == 1
	match predicate:
		"useful_handoffs":
			return st["direct_deliveries"] if solo else st["useful_handoffs"]
		"shared_work":
			return st["work_targets"] if solo else st["shared_work"]
		"tidy_rooms":
			return tidy_count(sim)
		"trunk_goal", "festival_parcels":
			var n := 0
			for k in sim.s["goals"]:
				var gl: Dictionary = sim.s["goals"][k]
				if gl.get("done", false) and gl.get("kind", "") == ("trunk" if predicate == "trunk_goal" else "parcel"):
					n += 1
			return n
	return int(st.get(predicate, 0))

static func ribbons(sim: HotelSim) -> Array:
	var out: Array = []
	var h: int = sim.s["humans"]
	for rb in sim.level.get("ribbons", []):
		var target: int = rb["targets_1_to_4"][h - 1]
		var v := ribbon_value(sim, rb["predicate"])
		out.append({"label": rb["label"], "predicate": rb["predicate"], "target": target, "value": v, "earned": v >= target})
	return out

static func finalize(sim: HotelSim) -> void:
	var res := team_result(sim)
	res["ribbons"] = ribbons(sim)
	res["tidy"] = tidy_count(sim)
	res["level"] = sim.level.get("id", "")
	res["humans"] = sim.s["humans"]
	res["difficulty"] = sim.s["difficulty"]
	res["wrap_reason"] = sim.s["wrap_reason"]
	res["practice"] = res["admitted"] == 0
	sim.s["result"] = res
