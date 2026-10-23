extends TestBase
## Tutorials (§13): each step can always be finished — by players or, after
## 60 s without progress, by Nana's "Try it for me" — and nothing soft-locks.

func _run_tutorial(tid: String, humans: int) -> Dictionary:
	var seats: Array = []
	for i in humans:
		seats.append({"seat": i, "char": SimC.STAFF_IDS[i], "assists": {"auto_catch": true}})
	var sim := HotelSim.new(content, {"mode": "tutorial", "tutorial_id": tid, "humans": humans, "seats": seats, "difficulty": "family", "seed": 5, "gus": true})
	var steps_seen: Array = []
	var guard := 0
	while not sim.tutorial.done and guard < 30 * 60 * 15:
		var f: Array = []
		for i in humans:
			var p := SimC.BTN_HINT if sim.tutorial.hint_level() >= 3 else 0
			f.append(frame(i, 0, 0, 0, p))
		sim.step(f)
		for e in sim.events:
			if e["type"] == "tutorial_step":
				steps_seen.append(e["id"])
		guard += 1
	return {"done": sim.tutorial.done, "steps": steps_seen, "ticks": guard, "sim": sim}

func test_tutorials_complete_with_assist() -> void:
	for tid in ["T01", "T02", "T03"]:
		for h in [1, 2]:
			var r := _run_tutorial(tid, h)
			check(r["done"], "%s x%d completes (steps %s)" % [tid, h, ",".join(r["steps"])])
			eq(r["steps"].size(), content.tutorials[tid]["steps"].size(), "%s x%d visits every step" % [tid, h])

func test_t01_circles_by_walking() -> void:
	var sim := HotelSim.new(content, {"mode": "tutorial", "tutorial_id": "T01", "humans": 1, "seats": [{"seat": 0, "char": "pip"}], "seed": 1})
	var st: Dictionary = sim.s["staff"][0]
	# Walk west to the first circle, then east to the second.
	for i in 30 * 4:
		sim.step([frame(0, -127, 0)])
	for i in 30 * 6:
		sim.step([frame(0, 127, 0)])
	check(sim.tutorial.step_i >= 1, "walking through both circles advances T01.1 (step %d)" % sim.tutorial.step_i)
