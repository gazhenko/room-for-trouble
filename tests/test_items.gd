extends TestBase
## ITEM01–ITEM03, WORK01, ROOM01–02, GUEST01–02.

func _place(st: Dictionary, x: float, z: float, fx := 0, fz := 1000) -> void:
	st["x"] = int(x * SimC.UM); st["z"] = int(z * SimC.UM); st["fx"] = fx; st["fz"] = fz; st["vx"] = 0; st["vz"] = 0

func _count_items(sim: HotelSim, kind: String) -> int:
	var n := 0
	for iid in sim.s["items"]:
		if sim.s["items"][iid]["k"] == kind:
			n += 1
	return n

func test_item01_simultaneous_pickup_one_owner() -> void:
	var sim := make_sim("L02", 2)
	activate(sim)
	var iid := sim.new_item("towel", {"loc": "world", "x": 10_000_000, "z": 10_800_000})
	var a: Dictionary = sim.s["staff"][0]
	var b: Dictionary = sim.s["staff"][1]
	_place(a, 9.5, 10.8, 1000, 0)
	_place(b, 10.5, 10.8, -1000, 0)
	sim.step([])
	sim.step([frame(0, 0, 0, SimC.BTN_CARRY, SimC.BTN_CARRY), frame(1, 0, 0, SimC.BTN_CARRY, SimC.BTN_CARRY)])
	var holders := 0
	if a["held"] == iid: holders += 1
	if b["held"] == iid: holders += 1
	eq(holders, 1, "exactly one player holds the towel")
	eq(_count_items(sim, "towel"), 1, "no duplicate towel")

func test_item02_hamper_full_keeps_bundle() -> void:
	var sim := make_sim("L03", 1)
	activate(sim)
	sim.s["st"]["hamper_q"] = SimC.HAMPER_QUEUE_CAP
	var st: Dictionary = sim.s["staff"][0]
	var iid := sim.new_item("linen_dirty", {"loc": "held", "seat": 0})
	st["held"] = iid
	_place(st, 7.0, 9.1)
	sim.step([])
	sim.step([frame(0, 0, 0, SimC.BTN_CARRY, SimC.BTN_CARRY)])
	check(sim.s["items"].has(iid), "bundle still exists when the hamper is full")
	eq(sim.s["st"]["hamper_q"], SimC.HAMPER_QUEUE_CAP, "queue not overfilled")

func test_item03_ticket_returns_to_pedestal() -> void:
	var sim := make_sim("L01", 1)
	activate(sim)
	for i in 31 * 30:
		sim.step([])
	var g: Dictionary = {}
	for gid in sim.s["guests"]:
		if sim.s["guests"][gid]["state"] == "lobby":
			g = sim.s["guests"][gid]
			break
	check(not g.is_empty(), "a guest is waiting")
	var tid: int = g["ticket"]
	var patience: int = g["patience_q"]
	SimInteract.place_world(sim, tid, 12_000_000, 10_800_000)
	for i in SimC.TICKET_RETURN + 2:
		sim.step([])
	eq(sim.item(tid)["loc"], "sock", "unattended ticket returns to its pedestal")
	check(g["patience_q"] < patience, "patience is not reset")

func test_work01_shared_rate_and_single_commit() -> void:
	var sim := make_sim("L03", 2)
	activate(sim)
	var r := sim.room("D")
	check(r["bed"] == "Dirty", "D starts dirty")
	var a: Dictionary = sim.s["staff"][0]
	var b: Dictionary = sim.s["staff"][1]
	# Both stand on the hall side of D's bed, within reach (positions from the layout).
	var bed: Vector2i = sim.L.rooms["D"]["bed"]
	_place(a, float(bed.x), bed.y - 0.8, 0, 1000)
	_place(b, bed.x + 0.8, bed.y - 0.8, 0, 1000)
	sim.step([])
	var key := "strip:D"
	eq(a["hl_w"], key, "A targets the bed")
	eq(b["hl_w"], key, "B targets the bed")
	var ticks := 0
	var bundles := 0
	while r["bed"] == "Dirty" and ticks < 100:
		var p := SimC.BTN_WORK if ticks == 0 else 0
		sim.step([frame(0, 0, 0, SimC.BTN_WORK, p), frame(1, 0, 0, SimC.BTN_WORK, p)])
		ticks += 1
	eq(r["bed"], "Stripped", "bed stripped once")
	check(ticks <= int(ceil(SimC.T_STRIP / 1.6)) + 2, "two workers are 1.6× faster (%d ticks)" % ticks)
	eq(_count_items(sim, "linen_dirty"), 1, "exactly one dirty bundle")

func test_guest01_same_tick_delivery_counts() -> void:
	var sim := make_sim("L02", 1)
	activate(sim)
	var g := {}
	var rq := {}
	# Fast-forward a guest into a room with an open request.
	for gid in sim.s["guests"]:
		g = sim.s["guests"][gid]
		break
	g["state"] = "staying"
	g["room"] = "A"
	sim.room("A")["guest"] = g["id"]
	g["stay_start_q"] = sim.s["hotel_q"]
	g["checkout_q"] = g["stay_start_q"] + g["stay_len"] * SimC.HOTEL_Q_PER_S
	SimGuests._build_requests(sim, g)
	rq = g["reqs"][0]
	rq["st"] = "open"
	sim.s["hotel_q"] = rq["dl"]
	var iid := sim.new_item(rq["k"], {"loc": "held", "seat": 0})
	SimGuests.fulfill(sim, g, 0, 0, iid)
	eq(g["reqs"][0]["st"], "done", "delivery at the deadline counts on time")

func test_room01_move_room_preserves_history() -> void:
	var sim := make_sim("L19", 2)
	activate(sim)
	var g := {}
	for gid in sim.s["guests"]:
		g = sim.s["guests"][gid]
		break
	g["state"] = "staying"; g["room"] = "A"; g["admitted"] = true; g["welcomed"] = true; g["helper_used"] = true
	sim.room("A")["guest"] = g["id"]
	g["stay_start_q"] = sim.s["hotel_q"]; g["checkout_q"] = g["stay_start_q"] + 75 * SimC.HOTEL_Q_PER_S
	SimGuests._build_requests(sim, g)
	var reqs_before: Array = g["reqs"].duplicate(true)
	SimGuests.relocate(sim, g["id"], "C", 0)
	eq(sim.room("A")["bed"], "Dirty", "old bed becomes dirty")
	eq(sim.room("A")["mess"], 100, "old floor needs a mop")
	eq(sim.room("C")["reserved"], g["id"], "destination reserved")
	check(g["welcomed"] and g["helper_used"], "history follows the guest")
	eq(g["reqs"], reqs_before, "requests are not reset")
	SimGuests.relocate(sim, g["id"], "D", 0)
	eq(sim.room("D")["reserved"], 0, "a guest moves only once")

func test_guest02_timeout_goes_to_cozy_corner() -> void:
	var sim := make_sim("L01", 1)
	activate(sim)
	var states := {}
	for i in 140 * 30:
		sim.step([])
	for gid in sim.s["guests"]:
		states[sim.s["guests"][gid]["state"]] = true
	check(states.has("cozy") or states.has("gone"), "patience → Cozy Corner, never a failure")
	eq(sim.s["phase"], "active", "the shift continues")
