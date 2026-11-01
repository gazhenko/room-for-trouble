extends TestBase
## Core loop smoke tests: phases, arrivals, timeouts, wrap, determinism.

func test_planning_to_active() -> void:
	var sim := make_sim("L01", 1)
	eq(sim.s["phase"], "planning", "starts in planning")
	run_ticks(sim, 30)
	eq(sim.s["hotel_q"], 0, "hotel clock frozen during planning")
	sim.step([frame(0, 0, 0, 0, SimC.BTN_READY)])
	eq(sim.s["phase"], "countdown", "ready starts the 3-note countdown")
	run_ticks(sim, 91)
	eq(sim.s["phase"], "active", "active after countdown")

func test_idle_shift_soft_wrap() -> void:
	var sim := make_sim("L01", 1)
	activate(sim)
	var seen_cozy := 0
	for i in 270 * 30 + 200:
		sim.step([])
		for e in sim.events:
			if e["type"] == "guest_cozy":
				seen_cozy += 1
		if sim.s["phase"] == "done":
			break
	eq(sim.s["phase"], "done", "timed wrap reached")
	eq(seen_cozy, sim.s["scheduled_count"], "every unassigned guest rests in the Cozy Corner")
	var res: Dictionary = sim.s["result"]
	eq(res["percent"], 0, "no points without play")
	check(res["practice"], "results call it a practice welcome")

func test_schedule_l01_solo() -> void:
	var sim := make_sim("L01", 1)
	eq(sim.schedule.size(), 3, "solo L01 has 3 guests (0.65 scale)")
	var sim2 := make_sim("L01", 2)
	eq(sim2.schedule.size(), 4, "duo L01 matches the manifest baseline")
	var last := 0
	for a in sim2.schedule:
		last = maxi(last, a["arrive_s"])
	var lvl: Dictionary = sim2.level
	check(last <= int(lvl["duration_hotel_s"]) - ArrivalPlan.reserve_for(lvl), "final arrival preserves the level's reserve")
	eq(sim2.schedule[0]["arrive_s"], 4, "v2 pacing: the first guest arrives at 4 s")

func test_determinism_same_inputs() -> void:
	var a := make_sim("L06", 2)
	var b := make_sim("L06", 2)
	a.start_now(); b.start_now()
	var r := FixedRng.new(99)
	for i in 3000:
		var fr: Array = []
		for seat in 2:
			fr.append(frame(seat, r.range_i(-127, 127), r.range_i(-127, 127), r.range_i(0, 3), r.range_i(0, 3) if r.range_i(0, 9) == 0 else 0))
		a.step(fr)
		b.step(fr)
	eq(a.state_hash(), b.state_hash(), "identical command logs give identical hashes")

func test_walk_and_collide() -> void:
	var sim := make_sim("L01", 1)
	activate(sim)
	var st: Dictionary = sim.s["staff"][0]
	# Walk north into the hall's north wall from the tile beside room A's door
	# (positions come from the layout; chapter 1 plays on the v2 floor).
	var door: Vector2i = sim.L.rooms["A"]["door"]
	st["x"] = (door.x + 1) * SimC.UM
	st["z"] = int((sim.L.hall.position.y + 1) * SimC.UM)
	for i in 120:
		sim.step([frame(0, 0, -127)])
	var wall_face := int((sim.L.hall.position.y - 0.5) * SimC.UM)
	check(st["z"] >= wall_face + SimC.RADIUS - 1, "wall stops the avatar (z=%d)" % st["z"])
	# Top speed sanity: walk east 1 second.
	var x0: int = st["x"]
	for i in 30:
		sim.step([frame(0, 127, 0)])
	check(st["x"] - x0 > 2_800_000 and st["x"] - x0 < 3_700_000, "about 3.6 m/s (moved %d)" % (st["x"] - x0))

func test_take_linen_and_place() -> void:
	var sim := make_sim("L01", 1)
	activate(sim)
	var st: Dictionary = sim.s["staff"][0]
	# Stand 0.9 m on the lane side of the linen shelf, facing it.
	var ls: Vector2i = sim.L.fixtures["linen_shelf"]
	var hall_mid := float(sim.L.hall.position.y) + (sim.L.hall.size.y - 1) * 0.5
	var toward := -1 if float(ls.y) > hall_mid else 1
	st["x"] = ls.x * SimC.UM; st["z"] = int((ls.y + toward * 0.9) * SimC.UM); st["fx"] = 0; st["fz"] = -toward * 1000
	sim.step([])
	eq(st["hl_c"], "st:linen", "linen shelf highlighted from the lane")
	var before: int = sim.s["st"]["linen"]
	sim.step([frame(0, 0, 0, SimC.BTN_CARRY, SimC.BTN_CARRY)])
	check(st["held"] != 0, "holding a bundle")
	eq(sim.s["st"]["linen"], before - 1, "stock decremented once")
	run_ticks(sim, 6)
	st["fx"] = 0; st["fz"] = toward * 1000
	sim.step([])
	sim.step([frame(0, 0, 0, SimC.BTN_CARRY, SimC.BTN_CARRY)])
	run_ticks(sim, 6)
	eq(st["held"], 0, "placed on the floor (hl=%s)" % st["hl_c"])
