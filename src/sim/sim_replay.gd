class_name SimReplay
extends RefCounted
## Deterministic replay (§19.5, REPLAY01). A record is the shift setup, the
## content hash, every accepted input frame and external command, and the
## 5-second mechanical hashes. Re-running it on the same build must reproduce
## the hashes; the first mismatching checkpoint names the divergence window.

static func capture(sim: HotelSim) -> Dictionary:
	return {"version": 1, "cfg": sim.cfg, "content_hash": sim.content.content_hash,
		"engine": Engine.get_version_info()["string"], "ticks": int(sim.s["tick"]),
		"inputs": sim.input_log, "cmds": sim.cmd_log, "hashes": sim.hashes,
		"final_hash": sim.state_hash()}

static func run(content, rec: Dictionary, ticks: int = -1) -> HotelSim:
	var sim := HotelSim.new(content, rec["cfg"])
	var frames_at := {}
	for e in rec["inputs"]:
		frames_at[int(e[0])] = e[1]
	var cmds_at := {}
	for c in rec.get("cmds", []):
		var t := int(c[0])
		if not cmds_at.has(t):
			cmds_at[t] = []
		cmds_at[t].append(c)
	var n: int = int(rec["ticks"]) if ticks < 0 else ticks
	for t in n:
		for c in cmds_at.get(t, []):
			_apply(sim, str(c[1]), c[2])
		var frames: Array = []
		for f in frames_at.get(t, []):
			var d := {"seat": int(f[0]), "ax": int(f[1]), "az": int(f[2]), "held": int(f[3]), "pressed": int(f[4])}
			if f.size() > 5:
				d["pick"] = int(f[5])
			frames.append(d)
		sim.step(frames)
	return sim

static func _apply(sim: HotelSim, cmd: String, args: Array) -> void:
	match cmd:
		"start_now": sim.start_now()
		"set_present": sim.set_present(int(args[0]), bool(args[1]))
		"back_to_lobby": sim.back_to_lobby(int(args[0]))
		"find_tools": sim.find_tools()
		"leader_wrap": sim.leader_wrap()
		"enable_gus": sim.enable_gus()

## Tick of the first checkpoint whose hash differs, or -1 if all match.
static func first_divergence(a: Array, b: Array) -> int:
	var n := mini(a.size(), b.size())
	for i in n:
		if str(a[i][1]) != str(b[i][1]):
			return int(a[i][0])
	if a.size() != b.size():
		return int((a if a.size() > n else b)[n][0])
	return -1

static func verify(content, rec: Dictionary) -> Dictionary:
	var sim := run(content, rec)
	var div := first_divergence(rec["hashes"], sim.hashes)
	return {"ok": div == -1 and sim.state_hash() == rec.get("final_hash", sim.state_hash()),
		"first_divergence_tick": div, "content_match": content.content_hash == rec.get("content_hash", ""),
		"checkpoints": sim.hashes.size()}
