extends SceneTree
## Dev: trace the reference bot on one level.  godot --headless --path . --script res://tools/dev/bot_trace.gd -- L01 1 [seconds]
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var lid := args[0] if args.size() > 0 else "L01"
	var h := int(args[1]) if args.size() > 1 else 1
	var secs := int(args[2]) if args.size() > 2 else 120
	var reg = load("res://src/content/content_registry.gd").new()
	reg.load_all()
	var seats: Array = []
	for i in h:
		seats.append({"seat": i, "char": SimC.STAFF_IDS[i], "assists": {"auto_catch": true}})
	var sim := HotelSim.new(reg, {"mode": "campaign", "level_id": lid, "humans": h, "seats": seats, "difficulty": "family", "seed": 7, "gus": h == 1})
	var bot := ReferenceBot.new(sim)
	var last := {}
	for t in secs * 30:
		sim.step(bot.frames())
		for st in sim.s["staff"]:
			var task: Dictionary = bot.tasks.get(st["seat"], {})
			var desc := "%s/%s" % [task.get("key", "-"), task.get("action", "")]
			if t % 90 == 0 and t > 90 * 30 and t < 160 * 30:
				var it2 := sim.item(st["held"])
				print("   dbg t=%.1f pos=(%.2f,%.2f) f=(%d,%d) hl_w=%s ok=%s why=%s ch=%s trayD=%d humD=%d stand=%s act=%s" % [t / 30.0, st["x"] / 1e6, st["z"] / 1e6, st["fx"], st["fz"], st["hl_w"], st["hl_w_ok"], st["hl_w_why"], it2.get("ch", -1), sim.room("D")["tray"], sim.room("D")["hum"], task.get("stand", Vector2i.ZERO), st["act"]])
			if last.get(st["seat"], "") != desc:
				last[st["seat"]] = desc
				print("t=%5.1f s%d pos=(%.1f,%.1f) held=%s task=%s hl_c=%s hl_w=%s" % [t / 30.0, st["seat"], st["x"] / 1e6, st["z"] / 1e6, SimInteract.held_kind(sim, st), desc, st["hl_c"], st["hl_w"]])
		for e in sim.events:
			if e["type"] in ["assign", "welcome", "request_done", "request_open", "invalid", "checkout", "guest_cozy"]:
				print("      event ", e)
	reg.free()
	quit()
