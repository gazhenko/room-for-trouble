extends TestBase
## SCORE01–02: one transparent team result.

func _perfect_guest(sim: HotelSim, g: Dictionary) -> void:
	g["admitted"] = true
	g["welcomed"] = true
	g["comf_s"] = g["stay_len"]
	g["reqs"] = []
	for i in int(sim.level["service_count"]):
		g["reqs"].append({"k": "towel", "st": "done", "at": 0, "dl": 0, "late": 0, "i": i})

func test_score01_all_perfect_is_100() -> void:
	var sim := make_sim("L06", 2)
	for gid in sim.s["guests"]:
		_perfect_guest(sim, sim.s["guests"][gid])
	var r := SimScore.team_result(sim)
	eq(r["percent"], 100, "perfect stays score 100%")
	eq(r["stars"], 3, "three stars")

func test_score01_star_boundaries() -> void:
	var sim := make_sim("L01", 2)
	var gs: Array = sim.s["guests"].values()
	for g in gs:
		_perfect_guest(sim, g)
		g["comf_s"] = 0     # 60 points each
	var r := SimScore.team_result(sim)
	eq(r["percent"], 60, "60% without comfort")
	eq(r["stars"], 1, "55 ≤ 60 < 75 → one star")
	for g in gs:
		g["comf_s"] = int(g["stay_len"] * 3 / 4)   # +30 → 90
	r = SimScore.team_result(sim)
	check(r["percent"] >= 89 and r["percent"] <= 90, "≈90%")

func test_score02_late_half_and_abandoned_zero() -> void:
	var sim := make_sim("L02", 1)
	var gs: Array = sim.s["guests"].values()
	var g: Dictionary = gs[0]
	_perfect_guest(sim, g)
	g["reqs"][0]["st"] = "late"
	var p := SimScore.guest_points(sim, g)
	eq(p["service"], 15_000, "two requests: one on time (10) + one late (5)")
	var g2: Dictionary = gs[1]
	g2["abandoned"] = true
	var p2 := SimScore.guest_points(sim, g2)
	eq(p2["total"], 0, "an abandoned guest earns only already-earned components (none)")
	check(p2["total"] >= 0, "no negative points")

func test_score_denominator_stable() -> void:
	var sim := make_sim("L04", 2)
	var r := SimScore.team_result(sim)
	eq(r["scheduled"], sim.schedule.size(), "denominator = scheduled guests; trunks never change it")
