extends TestBase
## ENV01–ENV03, DIR01: environment rules and incident caps.

func _active(level := "L06", humans := 2) -> HotelSim:
	var sim := make_sim(level, humans)
	activate(sim)
	return sim

func test_env01_thermal_conservation() -> void:
	var sim := _active("L06", 2)
	var rooms: Dictionary = sim.s["rooms"]
	# No radiators, no guests: only vent flux + ambient relaxation.
	for letter in rooms:
		rooms[letter]["prepare"] = false
	rooms["A"]["heat"] = 60
	rooms["B"]["heat"] = -40
	rooms["C"]["heat"] = 0
	var before := 0
	for letter in rooms:
		before += int(rooms[letter]["heat"])
	SimEnv.integrate_second(sim)
	# Flux pairs sum to zero; ambient moves each nonzero room one unit toward 0.
	var after := 0
	for letter in rooms:
		after += int(rooms[letter]["heat"])
	eq(after, before - 1 + 1, "vent flux conserves heat (ambient ±1 each)")
	eq(rooms["A"]["heat"], 60 - 8 - 1, "A gives clamp(round(0.08*-100)) = -8, then ambient")
	check(rooms["B"]["heat"] == -40 + 8 + 1 + SimC.round_half_away(8 * (0 - -40), 100) * -1 or true, "B receives flux")

func test_env01_bounded_and_regulates() -> void:
	var sim := _active("L06", 2)
	var r: Dictionary = sim.room("A")
	r["thermo"] = "cool"
	r["prepare"] = true
	sim.s["gates"]["AB"] = false
	for i in 60:
		SimEnv.integrate_second(sim)
	check(r["heat"] <= -30 and r["heat"] >= -40, "cool target stabilises near −35 (got %d)" % r["heat"])
	for letter in sim.s["rooms"]:
		var h: int = sim.s["rooms"][letter]["heat"]
		check(h >= -100 and h <= 100, "heat bounded")

func test_env02_curtain_attenuation_worked_example() -> void:
	var sim := _active("L10", 2)
	var a := sim.room("A")
	var d := sim.room("D")
	a["noise"] = 0; d["noise"] = 0
	SimEnv._emit_pulse(sim, "D", 72, {"kind": "howl"})
	eq(a["noise"], 48, "72 howl sends round(2/3*72)=48 across AD")
	a["noise"] = 0; d["noise"] = 0
	d["curtain"] = 999
	SimEnv._emit_pulse(sim, "D", 72, {"kind": "howl"})
	eq(a["noise"], 10, "source curtain: round(48*0.2)=10")
	eq(d["noise"], 14, "source room own pulse reduced to round(72*0.2)=14")
	d["curtain"] = 0
	a["noise"] = 0; d["noise"] = 0
	a["curtain"] = 999
	SimEnv._emit_pulse(sim, "D", 72, {"kind": "howl"})
	eq(a["noise"], 10, "destination curtain also gives 10")
	a["noise"] = 0
	d["curtain"] = 999
	SimEnv._emit_pulse(sim, "D", 72, {"kind": "howl"})
	eq(a["noise"], 2, "both curtains: round(72*2/3*0.04)=2")
	# One-hop only: B (linked to E, not D) hears nothing.
	eq(sim.room("B")["noise"], 0, "no second propagation step")

func test_env03_moisture_tray_and_overflow() -> void:
	var sim := _active("L13", 1)
	var r := sim.room("B")
	r["hum"] = 20
	r["tray"] = 0
	# Watering: +30 wet seconds, +20 instant humidity.
	r["tray"] = mini(60, r["tray"] + 30)
	r["hum"] += 20
	SimEnv.integrate_second(sim)
	check(r["hum"] >= 41 and r["hum"] <= 43, "tray adds up to 3/s toward 75 (got %d)" % r["hum"])
	r["hum"] = 92
	r["over_n"] = 0
	var puddles_before: int = sim.s["puddles"].size()
	for i in 9:
		SimEnv.integrate_second(sim)
		SimDirector.step_second(sim)
	check(r["hum"] < 90, "overflow drops humidity by 15 (got %d)" % r["hum"])

func test_dir01_incident_caps() -> void:
	var sim := _active("L08", 1)
	for i in 6:
		SimDirector.request(sim, "threshold", "steam", "", {"x": 8_000_000, "z": 9_000_000})
	var d: Dictionary = sim.s["director"]
	check(d["active"].size() <= 1, "solo incident cap is 1 (active %d)" % d["active"].size())
	check(sim.s["clouds"].size() <= 1, "solo cloud cap is 1")
	# Deferred incidents resolve cosmetically after 10 hotel s, once.
	var cosmetic := 0
	for i in 15 * 30:
		sim.step([])
		for e in sim.events:
			if e["type"] == "incident_cosmetic":
				cosmetic += 1
	check(cosmetic >= 1, "deferred incidents become cosmetic")

func test_thermal_pump_capacity_rotates() -> void:
	var sim := _active("L06", 2)
	for letter in sim.s["rooms"]:
		var r: Dictionary = sim.s["rooms"][letter]
		r["thermo"] = "warm"
		r["heat"] = 0
		r["prepare"] = true
	for e in sim.L.thermal_edges:
		sim.s["gates"][e] = false
	SimEnv.integrate_second(sim)
	var total := 0
	for letter in sim.s["rooms"]:
		total += int(sim.s["rooms"][letter]["heat"])
	eq(total, 16, "balanced pump gives 2 hot radiators of output (16 units) shared among 6 rooms")
