extends SceneTree
## Dev: samples the reference bot's position, task, stand target and path
## progress every 2 s so a bot that never arrives can be diagnosed.
##   godot --headless --path . --script res://tools/dev/bot_stuck_probe.gd -- L17 2 60
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var lid := args[0] if args.size() > 0 else "L17"
	var h := int(args[1]) if args.size() > 1 else 2
	var secs := int(args[2]) if args.size() > 2 else 60
	var reg = load("res://src/content/content_registry.gd").new()
	reg.load_all()
	var seats: Array = []
	for i in h:
		seats.append({"seat": i, "char": SimC.STAFF_IDS[i], "assists": {"auto_catch": true}})
	var sim := HotelSim.new(reg, {"mode": "campaign", "level_id": lid, "humans": h, "seats": seats, "difficulty": "family", "seed": 7, "gus": false})
	var bot := ReferenceBot.new(sim)
	for t in secs * 30:
		sim.step(bot.frames())
		if t % 60 == 0 and t >= 600:
			for st in sim.s["staff"]:
				var task: Dictionary = bot.tasks.get(st["seat"], {})
				var stand = task.get("stand", Vector2i.ZERO)
				var path: Array = task.get("path", [])
				print("t=%3d s%d pos=(%.2f,%.2f) v=(%d,%d) held=%s task=%s/%s stand=(%.2f,%.2f) path=%d/%d wait=%d stuck=%s hl_c=%s hl_w=%s act=%s stun=%d slide=%d" % [
					t / 30, st["seat"], st["x"] / 1e6, st["z"] / 1e6, st["vx"], st["vz"], SimInteract.held_kind(sim, st),
					task.get("key", "-"), task.get("action", ""), stand.x / 1e6, stand.y / 1e6, int(task.get("pi", 0)), path.size(),
					int(task.get("wait", 0)), str(bot.stuck.get(str(st["seat"]) + "n", 0)), st["hl_c"], st["hl_w"], str(st["act"]), int(st.get("stun_t", 0)), int(st["slide_t"])])
	reg.free()
	quit()
