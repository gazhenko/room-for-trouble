class_name SimGus
extends RefCounted
## Gus, the suitcase mimic (§7.4). Every 12 action seconds he picks one small
## laundry/tool chore. He never fulfils requests, assigns rooms, changes
## controls, touches beds, takes a held/reserved item or moves a trunk.

const TASK_TICKS := 75

static func step(sim: HotelSim) -> void:
	var gus: Dictionary = sim.s["gus"]
	if not gus.has("x"):
		var home: Vector2i = sim.L.fixtures["linen_shelf"]
		gus["x"] = home.x * SimC.UM
		gus["z"] = (home.y + 1) * SimC.UM - 350_000
		gus["home"] = [gus["x"], gus["z"]]
	var task: Dictionary = gus["task"]
	if not task.is_empty():
		task["t"] -= 1
		if task.has("item"):
			var it := sim.item(task["item"])
			if it.is_empty() or it["loc"] != "world":
				sim.emit("gus_cancel", {})
				gus["task"] = {}
				return
		if task["t"] <= 0:
			_complete(sim, task)
			gus["task"] = {}
		return
	gus["t"] += 1
	if gus["t"] < SimC.GUS_INTERVAL:
		return
	gus["t"] = 0
	# (1) oldest resting dirty bundle
	var best := 0
	var best_born := 1 << 62
	for iid in sim.s["items"]:
		var it: Dictionary = sim.s["items"][iid]
		if it["k"] == "linen_dirty" and it["loc"] == "world" and it["idle"] >= SimC.GUS_BUNDLE_REST and it["claim"] == -1:
			if it["born"] < best_born:
				best_born = it["born"]; best = iid
	if best != 0:
		var it2 := sim.item(best)
		gus["task"] = {"kind": "bundle", "item": best, "t": TASK_TICKS, "tx": it2["x"], "tz": it2["z"]}
		sim.emit("gus_start", {"kind": "bundle"})
		return
	# (2) low linen
	if sim.s["st"]["linen"] < 2:
		gus["task"] = {"kind": "fold", "t": TASK_TICKS, "tx": gus["home"][0], "tz": gus["home"][1]}
		sim.emit("gus_start", {"kind": "fold"})
		return
	# (3) idle unique tool
	best = 0
	var best_idle := -1
	for iid in sim.s["items"]:
		var it3: Dictionary = sim.s["items"][iid]
		if it3["k"] in ["mop", "breezer", "watering_can"] and it3["loc"] == "world" and it3["idle"] >= SimC.GUS_TOOL_IDLE:
			if it3["idle"] > best_idle:
				best_idle = it3["idle"]; best = iid
	if best != 0:
		var it4 := sim.item(best)
		gus["task"] = {"kind": "tool", "item": best, "t": TASK_TICKS, "tx": it4["x"], "tz": it4["z"]}
		sim.emit("gus_start", {"kind": "tool"})

static func _complete(sim: HotelSim, task: Dictionary) -> void:
	var stv: Dictionary = sim.s["st"]
	match task["kind"]:
		"bundle":
			var it := sim.item(task["item"])
			if it.is_empty() or it["loc"] != "world":
				return
			if stv["hamper_q"] < SimC.HAMPER_QUEUE_CAP:
				sim.consume_item(task["item"], "gus_hamper")
				stv["hamper_q"] += 1
				sim.emit("gus_done", {"kind": "bundle"})
		"fold":
			if stv["linen"] < SimC.LINEN_CAP:
				stv["linen"] += 1
				sim.emit("gus_done", {"kind": "fold"})
		"tool":
			var it2 := sim.item(task["item"])
			if it2.is_empty() or it2["loc"] != "world":
				return
			SimInteract._return_tool(sim, task["item"])
			sim.emit("gus_done", {"kind": "tool"})
