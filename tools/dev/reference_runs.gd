extends SceneTree
## Reference-run matrix (§24.2) with the transparent scripted driver.
##   godot --headless --path . --script res://tools/dev/reference_runs.gd -- [--level=L06] [--out=docs/REFERENCE_RUNS.md]
## Every level: solo Family with Gus, 2/3/4-player Family and a 2-player Busy
## run; plus one deliberately imperfect run per chapter. Records arrivals,
## admissions, abandons, service latency, work/travel time, comfort per room,
## incident overlap, resource waits, score, ribbons, finish time and recoveries.
## These are bot runs for mechanics and balance, not family playtests.

const Q := SimC.HOTEL_Q_PER_S
const RECOVERY_EVENTS := ["puddle_gone", "frost_cleared", "cloud_gone", "comfort_recovered", "ticket_home",
	"tool_home", "return_item", "room_mopped"]

var reg

func _initialize() -> void:
	var only := ""
	var out := "docs/REFERENCE_RUNS.md"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--level="): only = a.substr(8)
		elif a.begins_with("--out="): out = a.substr(6)
	reg = load("res://src/content/content_registry.gd").new()
	reg.load_all()
	var rows: Array = []
	var t0 := Time.get_ticks_msec()
	for L in reg.levels:
		if only != "" and L["id"] != only:
			continue
		for h in [1, 2, 3, 4]:
			rows.append(run(L["id"], h, "family", ""))
		rows.append(run(L["id"], 2, "busy", ""))
	var imperfect := [["L03", 2, "dropped_ticket"], ["L07", 2, "absent_teammate"], ["L11", 1, "late_start"],
		["L15", 2, "absent_teammate"], ["L19", 3, "late_start"], ["L23", 4, "two_absent"]]
	for im in imperfect:
		if only == "" or only == im[0]:
			rows.append(run(im[0], im[1], "family", im[2]))
	_write(rows, out, (Time.get_ticks_msec() - t0) / 1000.0)
	reg.free()
	quit()

func run(lid: String, humans: int, diff: String, flaw: String) -> Dictionary:
	var seats: Array = []
	for i in humans:
		seats.append({"seat": i, "char": SimC.STAFF_IDS[i % 4], "assists": {"auto_catch": true}})
	var sim := HotelSim.new(reg, {"mode": "campaign", "level_id": lid, "humans": humans, "seats": seats,
		"difficulty": diff, "seed": 1234, "modifiers": [], "gus": humans == 1})
	sim.record_inputs = false
	var bot := ReferenceBot.new(sim)
	var m := {"level": lid, "humans": humans, "difficulty": diff, "flaw": flaw, "arrivals": 0, "admitted": 0,
		"abandoned": 0, "lat_sum": 0.0, "lat_n": 0, "late": 0, "missed": 0, "incident_overlap": 0,
		"stockout_s": 0, "recoveries": 0, "recovery_kinds": {}, "wrap_s": -1, "handoffs": 0}
	var open_at := {}
	var guard := 0
	var dropped := false
	while sim.s["phase"] != "done" and guard < 30 * 60 * 12:
		var hs: int = int(sim.s["hotel_q"]) / Q
		var frames: Array = bot.frames()
		match flaw:
			"absent_teammate":
				if hs == 60 and sim.staff_by_seat(1)["present"]: sim.set_present(1, false)
				if hs == 120 and not sim.staff_by_seat(1)["present"]: sim.set_present(1, true)
			"two_absent":
				for s2 in [2, 3]:
					if hs == 70 and sim.staff_by_seat(s2)["present"]: sim.set_present(s2, false)
					if hs == 115 and not sim.staff_by_seat(s2)["present"]: sim.set_present(s2, true)
			"late_start":
				if hs >= 50 and hs < 90:
					frames = []
			"dropped_ticket":
				if not dropped and hs > 30:
					for st in sim.s["staff"]:
						if SimInteract.held_kind(sim, st) == "ticket":
							SimInteract.safe_release(sim, st)
							dropped = true
							break
		sim.step(frames)
		guard += 1
		for e in sim.events:
			var t: String = e["type"]
			match t:
				"guest_arrive": m["arrivals"] += 1
				"assign": m["admitted"] += 1
				"reservation_cancel": m["admitted"] -= 1
				"guest_cozy": m["abandoned"] += 1
				"request_open": open_at["%s:%s" % [e["guest"], e["k"]]] = int(sim.s["hotel_q"])
				"request_done":
					var k := "%s:%s" % [e["guest"], e["k"]]
					if open_at.has(k):
						m["lat_sum"] += float(int(sim.s["hotel_q"]) - int(open_at[k])) / Q
						m["lat_n"] += 1
						open_at.erase(k)
					if e.get("late", false): m["late"] += 1
				"request_missed": m["missed"] += 1
				"useful_handoff": m["handoffs"] += 1
				"wrap": m["wrap_s"] = hs
			if t in RECOVERY_EVENTS:
				m["recoveries"] += 1
				m["recovery_kinds"][t] = int(m["recovery_kinds"].get(t, 0)) + 1
		m["incident_overlap"] = maxi(m["incident_overlap"], sim.s.get("director", {}).get("active", []).size())
		if guard % 30 == 0 and sim.s["phase"] == "active":
			var stv: Dictionary = sim.s["st"]
			if int(stv["towels"]) == 0 or int(stv["snacks"]) == 0 or int(stv["linen"]) == 0:
				m["stockout_s"] += 1
	var res: Dictionary = sim.s.get("result", {})
	m["finished"] = sim.s["phase"] == "done"
	m["percent"] = int(res.get("percent", -1))
	m["stars"] = int(res.get("stars", 0))
	m["scheduled"] = int(res.get("scheduled", 0))
	m["ribbons"] = res.get("ribbons", []).filter(func(r): return r["earned"]).size()
	m["wrap_reason"] = str(sim.s.get("wrap_reason", ""))
	m["duration_s"] = int(sim.level["duration_hotel_s"])
	var comf_by_room := {}
	for g in res.get("guests", []):
		var gs: Dictionary = sim.s["guests"].get(g["id"], {})
		var room: String = gs.get("room", "")
		if room == "" or not gs.get("admitted", false):
			continue
		if not comf_by_room.has(room):
			comf_by_room[room] = []
		comf_by_room[room].append(float(g["points"]["comfort"]) / 400.0)
	var comf := {}
	for r in comf_by_room:
		var arr: Array = comf_by_room[r]
		comf[r] = int(round(arr.reduce(func(a, b): return a + b, 0.0) / arr.size()))
	m["comfort_by_room"] = comf
	var busy := float(bot.stats["busy_ticks"])
	var tot := maxf(1.0, busy + float(bot.stats["idle_ticks"]))
	m["work_pct"] = int(round(100.0 * float(bot.stats["work_ticks"]) / tot))
	m["travel_pct"] = int(round(100.0 * (busy - float(bot.stats["work_ticks"])) / tot))
	m["idle_pct"] = 100 - m["work_pct"] - m["travel_pct"]
	m["latency_s"] = snappedf(m["lat_sum"] / maxf(1.0, m["lat_n"]), 0.1)
	print("%s x%d %-6s %-16s %3d%% %d★ adm %d/%d cozy %d lat %.1fs late %d miss %d overlap %d rec %d wrap %s@%d" % [lid, humans, diff, flaw,
		m["percent"], m["stars"], m["admitted"], m["scheduled"], m["abandoned"], m["latency_s"], m["late"], m["missed"],
		m["incident_overlap"], m["recoveries"], m["wrap_reason"], m["wrap_s"]])
	return m

func _write(rows: Array, out: String, secs: float) -> void:
	var md := "# Reference runs\n\n"
	md += "Generated by `godot --headless --path . --script res://tools/dev/reference_runs.gd` (%d runs, %.0f s) on %s with build content hash `%s`.\n\n" % [rows.size(), secs, Time.get_date_string_from_system(), reg.content_hash]
	md += "These are runs of the transparent scripted driver (`src/dev/reference_bot.gd`), seed 1234. They check mechanics, pacing and solvability. **They are not family playtests**; see `docs/PLAYTEST_REPORT.md`.\n\n"
	md += "The bot plays without Quick Step or guest helpers and never uses co-carry, so its scores are a floor rather than a target. Solo runs have Gus on.\n\n"
	md += "Columns: score % and stars; admitted/scheduled guests; Cozy Corner abandons; mean request latency (hotel s, open→delivered); late and missed requests; bot time split work/travel/idle; peak simultaneous incidents; seconds with an empty towel, snack or linen stock; recoveries (puddles dried, frost cleared, steam gone, comfort recovered, tickets/tools returned, rooms mopped); ribbons earned; how the shift ended.\n\n"
	md += "| Level | Players | Pace | Variation | Score | Admitted | Cozy | Latency | Late/Missed | Work/Travel/Idle | Overlap | Stock-out s | Recoveries | Ribbons | Ended | Comfort by room |\n"
	md += "|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|\n"
	for m in rows:
		var comf: Array = []
		var keys: Array = m["comfort_by_room"].keys()
		keys.sort()
		for r in keys:
			comf.append("%s %d" % [r, m["comfort_by_room"][r]])
		var ended: String = ("timer" if m["wrap_reason"] == "timer" else "early @%ds" % m["wrap_s"]) if m["finished"] else "DID NOT FINISH"
		md += "| %s | %d%s | %s | %s | %d%% %s | %d/%d | %d | %.1f s | %d/%d | %d/%d/%d%% | %d | %d | %d | %d/3 | %s | %s |\n" % [m["level"], m["humans"], " +Gus" if m["humans"] == 1 else "",
			m["difficulty"], m["flaw"].replace("_", " ") if m["flaw"] != "" else "—", m["percent"], "★".repeat(m["stars"]),
			m["admitted"], m["scheduled"], m["abandoned"], m["latency_s"], m["late"], m["missed"], m["work_pct"], m["travel_pct"], m["idle_pct"],
			m["incident_overlap"], m["stockout_s"], m["recoveries"], m["ribbons"], ended, ", ".join(comf)]
	var unfinished := rows.filter(func(r): return not r["finished"]).size()
	md += "\n**Summary:** %d runs, %d did not finish. " % [rows.size(), unfinished]
	var solo := rows.filter(func(r): return r["humans"] == 1 and r["flaw"] == "" and r["difficulty"] == "family")
	var avg := 0.0
	for r in solo:
		avg += r["percent"]
	md += "Mean solo Family score %.0f%%.\n" % (avg / maxf(1.0, solo.size()))
	var f := FileAccess.open("res://" + out, FileAccess.WRITE)
	f.store_string(md)
	f.close()
	var jf := FileAccess.open("res://build/reference_runs.json", FileAccess.WRITE)
	jf.store_string(JSON.stringify(rows, "\t"))
	jf.close()
	print("wrote ", out)
