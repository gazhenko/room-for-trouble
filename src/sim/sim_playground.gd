class_name SimPlayground
extends RefCounted
## Playground board operations (§16.5): untimed, unscored practice. Operations
## respect ownership and navigation exactly like normal play.

const MAX_GUESTS := 6

static func guest_count(sim: HotelSim) -> int:
	var n := 0
	for gid in sim.s["guests"]:
		if sim.s["guests"][gid]["state"] in ["lobby", "walking", "staying"]:
			n += 1
	return n

static func spawn_guest(sim: HotelSim, fam: String) -> bool:
	if guest_count(sim) >= MAX_GUESTS:
		return false
	var gid := sim.alloc_id()
	var g := SimGuests.make_guest(sim, gid, fam, "", {"arrive_s": 0, "announce_s": 0, "arrival_index": gid})
	g["play"] = true
	g["arrive_q"] = sim.s["hotel_q"]
	g["announce_q"] = sim.s["hotel_q"]
	g["announced"] = true
	sim.s["guests"][gid] = g
	SimGuests._arrive(sim, g)
	sim.emit("playground", {"op": "spawn", "fam": fam})
	return true

static func clear_guests(sim: HotelSim) -> void:
	for gid in sim.s["guests"].keys():
		var g: Dictionary = sim.s["guests"][gid]
		if g["ticket"] != 0:
			var t := sim.item(g["ticket"])
			if t.get("loc", "") == "held":
				var st := sim.staff_by_seat(t["seat"])
				if not st.is_empty():
					st["held"] = 0
			sim.consume_item(g["ticket"], "playground")
		if g["state"] == "lobby":
			SimGuests._release_pedestal(sim, g)
		g["state"] = "gone"
	for letter in sim.s["rooms"]:
		var r: Dictionary = sim.s["rooms"][letter]
		r["guest"] = 0
		r["reserved"] = 0
	sim.s["guests"].clear()
	sim.s["pedestals"] = [0, 0, 0, 0, 0, 0]
	sim.s["bench"] = []
	sim.emit("playground", {"op": "clear"})

static func set_rooms_dirty(sim: HotelSim, dirty: bool) -> void:
	for letter in sim.L.active_rooms:
		var r := sim.room(letter)
		if r["guest"] != 0 or r["reserved"] != 0:
			continue
		r["bed"] = "Dirty" if dirty else "Made"
		r["mess"] = 100 if dirty else 0
		r["mess_milli"] = r["mess"] * 1000

static func set_env(sim: HotelSim, what: String, value: int) -> void:
	for letter in sim.L.active_rooms:
		var r := sim.room(letter)
		match what:
			"heat": r["heat"] = clampi(value, -100, 100)
			"hum": r["hum"] = clampi(value, 0, 100)
			"noise": r["noise"] = clampi(value, 0, 100)

static func demo_quirk(sim: HotelSim) -> void:
	for gid in sim.s["guests"]:
		var g: Dictionary = sim.s["guests"][gid]
		if g["state"] == "staying" and g["quirk"] == "pending":
			g["quirk_q"] = sim.s["hotel_q"]
			return
		if g["state"] == "staying":
			g["quirk"] = "pending"
			g["quirk_q"] = sim.s["hotel_q"]
			return

static func demo_helper(sim: HotelSim) -> void:
	for gid in sim.s["guests"]:
		var g: Dictionary = sim.s["guests"][gid]
		if g["state"] == "staying" and not g["helper_used"]:
			var r := sim.room(g["room"])
			if r["gift"] == 0:
				r["gift"] = sim.new_item("welcome_" + g["fam"], {"loc": "sock", "sock": "plinth:" + g["room"]})
			g["welcomed"] = true
			g["streak"] = SimC.HELPER_STREAK_S
			g["helper_ready"] = true
			return

## Documented six-family arrangement (§16.5): A Yeti/Cool; B Dragon/Warm with
## AB and BC closed; C Ghost + curtain; D Moonwolf + curtain; E Sprout watered;
## F Slime/Neutral; DE/EF closed if their heat would interfere.
static func good_arrangement(sim: HotelSim) -> void:
	clear_guests(sim)
	set_rooms_dirty(sim, false)
	var plan := {"A": ["yeti", "cool"], "B": ["dragon", "warm"], "C": ["ghost", "neutral"],
		"D": ["moonwolf", "neutral"], "E": ["sprout", "neutral"], "F": ["slime", "neutral"]}
	for letter in plan:
		var fam: String = plan[letter][0]
		var r := sim.room(letter)
		r["thermo"] = plan[letter][1]
		r["heat"] = SimC.TARGET_COOL if plan[letter][1] == "cool" else (SimC.TARGET_WARM if plan[letter][1] == "warm" else 0)
		var gid := sim.alloc_id()
		var g := SimGuests.make_guest(sim, gid, fam, "", {"arrive_s": 0, "announce_s": 0, "arrival_index": gid})
		g["play"] = true
		g["announced"] = true
		g["state"] = "staying"
		g["admitted"] = true
		g["room"] = letter
		var b := SimGuests.bedside(sim, letter)
		g["x"] = b.x; g["z"] = b.y
		g["stay_start_q"] = sim.s["hotel_q"]
		g["checkout_q"] = sim.s["hotel_q"] + g["stay_len"] * SimC.HOTEL_Q_PER_S
		g["quirk_q"] = sim.s["hotel_q"] + SimC.QUIRK_AT_S * SimC.HOTEL_Q_PER_S
		g["reqs"] = []
		sim.s["guests"][gid] = g
		r["guest"] = gid
		r["gift"] = sim.new_item("welcome_" + fam, {"loc": "sock", "sock": "plinth:" + letter})
		g["welcomed"] = true
	for e in ["AB", "BC"]:
		sim.s["gates"][e] = false
	for e in ["DE", "EF"]:
		sim.s["gates"][e] = false
	for letter in ["C", "D"]:
		var r2 := sim.room(letter)
		if r2["curtain"] == 0:
			r2["curtain"] = sim.new_item("curtain_roll", {"loc": "sock", "sock": "curtain:" + letter})
			sim.s["st"]["curtains_free"] = maxi(0, sim.s["st"]["curtains_free"] - 1)
	var e_room := sim.room("E")
	e_room["tray"] = 60
	e_room["hum"] = 70
	sim.emit("playground", {"op": "arrangement"})
