extends TestBase
## DATA03, SOLO01, ROOM02, REPLAY01 and the simulation half of NET02.

func _guest_in_room(sim: HotelSim, letter: String) -> Dictionary:
	var g: Dictionary = {}
	for gid in sim.s["guests"]:
		g = sim.s["guests"][gid]
		break
	g["state"] = "staying"; g["room"] = letter; g["admitted"] = true
	sim.room(letter)["guest"] = g["id"]
	g["stay_start_q"] = sim.s["hotel_q"]
	g["checkout_q"] = g["stay_start_q"] + g["stay_len"] * SimC.HOTEL_Q_PER_S
	SimGuests._build_requests(sim, g)
	return g

func _count_kind(sim: HotelSim, kind: String) -> int:
	var n := 0
	for iid in sim.s["items"]:
		if sim.s["items"][iid]["k"] == kind:
			n += 1
	return n

func test_data03_ribbon_targets_within_upper_bounds() -> void:
	for L in content.levels:
		var lay: LayoutDef = content.layout(L["layout"])
		for h in range(1, 5):
			var sched := ArrivalPlan.schedule(L, h, lay.active_rooms.size())
			var fams := {}
			for a in sched:
				fams[a["family"]] = int(fams.get(a["family"], 0)) + 1
			var trunks := 0
			var parcels := 0
			for e in L["events"]:
				if e["type"] == "trunk_spawn": trunks += 1
				elif e["type"] == "parcels_spawn": parcels += e["args"]["object_ids"].size()
			for rb in L["ribbons"]:
				var tgt: int = int(rb["targets_1_to_4"][h - 1])
				var ub := -1
				match rb["predicate"]:
					"welcome_matches", "cozy_departures", "helpful_guests", "relocations": ub = sched.size()
					"requests": ub = sched.size() * int(L["service_count"])
					"water_care": ub = int(fams.get("sprout", 0))
					"quiet_howls": ub = int(fams.get("moonwolf", 0))
					"trunk_goal": ub = trunks
					"festival_parcels": ub = parcels
					"tidy_rooms": ub = lay.active_rooms.size()
				if ub >= 0:
					check(tgt <= ub, "%s/%d ribbon %s target %d ≤ bound %d" % [L["id"], h, rb["predicate"], tgt, ub])

func test_solo01_lessons_and_teaching_pairs_survive() -> void:
	for L in content.levels:
		var lay: LayoutDef = content.layout(L["layout"])
		var solo := ArrivalPlan.expand_waves(L, 1, lay.active_rooms.size())
		for wi in L["waves"].size():
			var w: Dictionary = L["waves"][wi]
			var need := int(w["minimum_size"])
			check(solo[wi].size() >= need, "%s wave %d keeps its minimum %d in solo" % [L["id"], wi + 1, need])
			for k in mini(need, w["roster"].size()):
				eq(solo[wi][k], w["roster"][k], "%s wave %d keeps authored guest %d first" % [L["id"], wi + 1, k + 1])
	# L06 and L10 teach pairs: Dragon/Yeti and Moonwolf/Ghost in every solo wave.
	for pair in [["L06", ["dragon", "yeti"]], ["L10", ["moonwolf", "ghost"]]]:
		var L2: Dictionary = content.level(pair[0])
		var solo2 := ArrivalPlan.expand_waves(L2, 1, content.layout(L2["layout"]).active_rooms.size())
		for w2 in solo2:
			for fam in pair[1]:
				check(fam in w2, "%s solo wave contains %s" % [pair[0], fam])

func test_solo01_one_player_moves_a_trunk() -> void:
	var sim := make_sim("L04", 1)
	activate(sim)
	for i in 16 * 30:
		sim.step([])
	check(not sim.s["trunks"].is_empty(), "L04 trunk spawned")
	var tid: int = sim.s["trunks"].keys()[0]
	var tr: Dictionary = sim.s["trunks"][tid]
	var st: Dictionary = sim.s["staff"][0]
	var x0: int = tr["x"]
	SimGoals.grip(sim, st, tid, 0)
	for i in 60:
		sim.step([frame(0, 127, 0, SimC.BTN_CARRY)])
	check(tr["x"] - x0 > 500_000, "a single handle drags the trunk (moved %.2f m)" % ((tr["x"] - x0) / 1e6))

func test_room02_relocate_after_request_and_helper() -> void:
	var sim := make_sim("L19", 2)
	activate(sim)
	var g := _guest_in_room(sim, "A")
	g["reqs"][0]["st"] = "done"
	g["helper_used"] = true
	g["welcomed"] = true
	var pts_before: Dictionary = SimScore.guest_points(sim, g)
	SimGuests.relocate(sim, g["id"], "C", 0)
	eq(SimScore.guest_points(sim, g)["service"], pts_before["service"], "service credit is neither reset nor duplicated")
	eq(SimScore.guest_points(sim, g)["welcome"], pts_before["welcome"], "welcome credit unchanged")
	eq(g["reqs"][0]["st"], "done", "fulfilled request stays fulfilled")
	g["streak"] = SimC.HELPER_STREAK_S + 10
	SimGuests._update_helper(sim, g)
	check(not g["helper_ready"], "a used helper does not recharge after moving")
	eq(int(sim.s["stats"]["relocations"]), 1, "one relocation counted")
	SimGuests.relocate(sim, g["id"], "D", 0)
	eq(int(sim.s["stats"]["relocations"]), 1, "second move refused, no extra count")

func test_replay01_same_log_same_hashes_and_divergence_found() -> void:
	var sim := make_sim("L09", 2)
	sim.start_now()
	var r := FixedRng.new(7)
	for t in 2400:
		var fr: Array = []
		for seat in 2:
			fr.append(frame(seat, r.range_i(-127, 127), r.range_i(-127, 127), r.range_i(0, 3), r.range_i(0, 3) if r.range_i(0, 9) == 0 else 0))
		if t == 900:
			sim.set_present(1, false)
		if t == 1200:
			sim.set_present(1, true)
		sim.step(fr)
	var rec := SimReplay.capture(sim)
	var res := SimReplay.verify(content, rec)
	check(res["ok"], "replaying the record reproduces every checkpoint (diverged at %d)" % res["first_divergence_tick"])
	eq(res["checkpoints"], 2400 / 150, "one checkpoint per 5 action seconds")
	# Perturb one accepted input; the first mismatching checkpoint follows it.
	var bad: Dictionary = rec.duplicate(true)
	var at := -1
	for e in bad["inputs"]:
		if int(e[0]) >= 1500:
			e[1][0][1] = -int(e[1][0][1]) if int(e[1][0][1]) != 0 else 127
			at = int(e[0])
			break
	var sim2 := SimReplay.run(content, bad)
	var div := SimReplay.first_divergence(rec["hashes"], sim2.hashes)
	check(div > at and div <= at + 150, "divergence located in the checkpoint after tick %d (got %d)" % [at, div])

func test_net02_disconnect_releases_held_item_handle_and_work() -> void:
	var sim := make_sim("L04", 2)
	activate(sim)
	for i in 16 * 30:
		sim.step([])
	var a: Dictionary = sim.s["staff"][0]
	var b: Dictionary = sim.s["staff"][1]
	var towels := _count_kind(sim, "towel")
	var iid := sim.new_item("towel", {"loc": "held", "seat": 0})
	a["held"] = iid
	var tid: int = sim.s["trunks"].keys()[0]
	SimGoals.grip(sim, b, tid, 1)
	sim.step([])
	sim.set_present(0, false)
	sim.set_present(1, false)
	eq(a["held"], 0, "disconnected player no longer holds the towel")
	eq(sim.item(iid).get("loc", ""), "world", "towel safely placed in the world")
	eq(_count_kind(sim, "towel"), towels + 1, "exactly one towel exists")
	eq(sim.s["trunks"][tid]["h"][1], -1, "trunk handle released")
	eq(b["grip"], 0, "no grip reserved by an absent player")
	for i in 30:
		sim.step([frame(0, 127, 0, SimC.BTN_CARRY, SimC.BTN_CARRY), frame(1, 127, 0, SimC.BTN_CARRY, SimC.BTN_CARRY)])
	eq(a["held"], 0, "absent seat's inputs are ignored")
	sim.set_present(0, true)
	sim.set_present(1, true)
	var holders := 0
	for st in sim.s["staff"]:
		if st["held"] == iid:
			holders += 1
	check(holders <= 1, "after reconnect the towel has at most one holder")
	eq(_count_kind(sim, "towel"), towels + 1, "no duplicate after reconnect")

func test_net05_stale_or_flooded_input_cannot_run_away() -> void:
	var r := NetRoom.new()
	r.seats = [{"id": 0, "peer": 2, "ready": true, "char": "pip", "cos": "default", "connected": true, "token_hash": "", "missing_at": 0.0}]
	r.selection["level_id"] = "L02"
	r.start_shift(content, content.content_hash)
	r.sim.start_now()
	for i in 91:
		r.sim.step([])
	var st: Dictionary = r.sim.s["staff"][0]
	# A burst of 500 frames between ticks keeps only the latest intent.
	for i in 500:
		r.push_input(0, {"seat": 0, "ax": 127, "az": 0, "held": 0, "pressed": 0}, 1000)
	var x0: int = st["x"]
	r.step(1010)
	var one_tick: int = st["x"] - x0
	check(one_tick > 0 and one_tick <= SimC.UM / 10, "a flood moves one tick's worth (%d µm)" % one_tick)
	# Then the client goes silent (delayed TCP): motion stops once input is stale.
	for i in 30:
		r.step(1010 + NetRoom.STALE_INPUT_MS + 10 + i * 33)
	var x1: int = st["x"]
	r.step(1010 + NetRoom.STALE_INPUT_MS + 2000)
	eq(st["x"], x1, "no runaway motion after the client stops sending")
	eq(st["vx"], 0, "velocity settles to zero")

func test_save_suspended_shift_round_trips_through_profile_json() -> void:
	# Active-shift suspension (§21.4): the snapshot goes through the profile's
	# JSON file and must resume to exactly the same mechanical future.
	var a := make_sim("L14", 2)
	a.start_now()
	var r := FixedRng.new(5)
	var log: Array = []
	for t in 2400:
		var fr: Array = []
		for seat in 2:
			fr.append(frame(seat, r.range_i(-127, 127), r.range_i(-127, 127), r.range_i(0, 3), r.range_i(0, 3) if r.range_i(0, 9) == 0 else 0))
		log.append(fr)
	for t in 1200:
		a.step(log[t])
	var snap := a.snapshot()
	var txt := JSON.stringify(SaveService.normalize(snap))
	var back: Dictionary = SaveService.normalize(JSON.parse_string(txt))
	var b := make_sim("L14", 2)
	b.restore(back)
	eq(b.state_hash(), a.state_hash(), "restored state hashes identically")
	for t in range(1200, 2400):
		a.step(log[t])
		b.step(log[t])
	eq(b.state_hash(), a.state_hash(), "resumed shift continues identically")
	eq(b.s["guests"].size(), a.s["guests"].size(), "guest table intact")
