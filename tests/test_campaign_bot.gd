extends TestBase
## Reference runs (§24.2): every level finishes and progresses at 1–4 humans
## with a transparent scripted driver; prints scores and workload.

func run_level(level_id: String, humans: int, difficulty := "family", extra := {}) -> Dictionary:
	var cfg := {"difficulty": difficulty}
	for k in extra:
		cfg[k] = extra[k]
	var sim := make_sim(level_id, humans, cfg)
	sim.record_inputs = false
	var bot := ReferenceBot.new(sim)
	var guard := 0
	while sim.s["phase"] != "done" and guard < 30 * 60 * 12:
		sim.step(bot.frames())
		guard += 1
	var res: Dictionary = sim.s.get("result", {})
	res["ticks"] = guard
	res["bot"] = bot.stats
	return res

func test_campaign_reference_runs() -> void:
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--level="):
			only = a.substr(8)
	var counts := [1, 2, 4]
	for a2 in OS.get_cmdline_user_args():
		if a2 == "--all-counts":
			counts = [1, 2, 3, 4]
	var total := 0
	var summary: Array = []
	for L in content.levels:
		if only != "" and L["id"] != only:
			continue
		for h in counts:
			var res := run_level(L["id"], h)
			check(res.has("percent"), "%s ×%d finished (%d ticks)" % [L["id"], h, res["ticks"]])
			check(res.get("scheduled", 0) > 0, "%s ×%d had guests" % [L["id"], h])
			var busy: float = float(res["bot"]["busy_ticks"]) / maxf(1.0, float(res["bot"]["busy_ticks"] + res["bot"]["idle_ticks"]))
			summary.append("%s x%d: %3d%% %d★ admitted %d/%d ribbons %d/3 busy %.0f%% (%s)" % [L["id"], h, res.get("percent", -1), res.get("stars", 0),
				res.get("admitted", 0), res.get("scheduled", 0), res.get("ribbons", []).filter(func(r): return r["earned"]).size(), busy * 100.0, res.get("wrap_reason", "")])
			total += 1
	for line in summary:
		print("   ", line)
