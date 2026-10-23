class_name NetRoom
extends RefCounted
## One private room on the authoritative service (§20.2). Owns membership,
## readiness, the room's HotelSim, per-seat input intents, snapshot baselines,
## pause policy and checkpoints. Sends only to this room's peers.

const SEAT_RESERVE_S := 90.0
const STALE_INPUT_MS := 250
const IDLE_TTL_S := 600.0

var id := ""
var code := ""
var created := 0.0
var leader := 0
var seats: Array = []          # [{id, peer, ready, char, cos, connected, token_hash, missing_at, assists}]
var selection := {"level_id": "L01", "difficulty": "family", "modifiers": [], "seed": 1, "mode": "campaign"}
var phase := "lobby"           # lobby | countdown | shift | results
var sim: HotelSim
var shift_id := 0
var inputs: Dictionary = {}    # seat -> {frame, t_ms, pressed}
var baselines: Dictionary = {} # peer -> {section: hash}
var tick := 0
var events: Array = []
var result: Dictionary = {}
var paused := false
var pause_until := 0.0
var auto_pause_used: Dictionary = {}
var countdown := 0.0
var last_activity := 0.0
var disconnect_since: Dictionary = {}  # seat -> time
var gus_forced := false
var lobby_seq: Dictionary = {}
var ready_wait_since := 0.0    # when the first seat readied (for "Start with ready players")
var start_only_ready := false  # this countdown was started by the leader without everyone

func peers() -> Array:
	var out: Array = []
	for s in seats:
		if s["connected"] and not s["peer"] in out:
			out.append(s["peer"])
	return out

func seats_of(peer_id: int) -> Array:
	var out: Array = []
	for s in seats:
		if s["peer"] == peer_id:
			out.append(s["id"])
	return out

func seat(i: int) -> Dictionary:
	for s in seats:
		if s["id"] == i:
			return s
	return {}

func free_seats() -> int:
	return 4 - seats.size()

func add_seats(peer_id: int, n: int, chars: Array, token_hash: String) -> Array:
	var ids: Array = []
	for k in n:
		var used := {}
		for s in seats:
			used[s["id"]] = true
		var sid := 0
		while used.has(sid):
			sid += 1
		var ch: String = chars[k] if k < chars.size() and chars[k] is String and chars[k] in SimC.STAFF_IDS else SimC.STAFF_IDS[sid % 4]
		seats.append({"id": sid, "peer": peer_id, "ready": false, "char": ch, "cos": "default", "connected": true,
			"token_hash": token_hash, "missing_at": 0.0, "assists": {"auto_catch": true}})
		ids.append(sid)
	seats.sort_custom(func(a, b): return a["id"] < b["id"])
	return ids

func lobby_view() -> Dictionary:
	var ss: Array = []
	for s in seats:
		ss.append({"id": s["id"], "ready": s["ready"], "char": s["char"], "cos": s["cos"], "connected": s["connected"],
			"peer": s["peer"], "sitting_out": s.get("sitting_out", false)})
	var wait := Time.get_unix_time_from_system() - ready_wait_since if ready_wait_since > 0.0 else -1.0
	return {"room_id": id, "code": code, "leader": leader, "seats": ss, "selection": selection, "phase": phase,
		"countdown": countdown, "paused": paused, "shift_id": shift_id, "ready_wait_s": wait}

func any_ready() -> bool:
	for s in seats:
		if s["connected"] and s["ready"]:
			return true
	return false

func all_ready() -> bool:
	if seats.is_empty():
		return false
	for s in seats:
		if s["connected"] and not s["ready"]:
			return false
	return true

func start_shift(content, content_hash: String) -> void:
	shift_id += 1
	var sc: Array = []
	var humans := 0
	for s in seats:
		# "Start with ready players" never silently starts an unready character (§11.4).
		s["sitting_out"] = start_only_ready and s["connected"] and not s["ready"]
		if s["connected"] and not s["sitting_out"]:
			sc.append({"seat": s["id"], "char": s["char"], "cos": s["cos"], "assists": s.get("assists", {})})
			humans += 1
	var cfg := {"mode": selection.get("mode", "campaign"), "level_id": selection["level_id"], "humans": maxi(1, humans),
		"seats": sc, "difficulty": selection["difficulty"], "seed": int(selection.get("seed", 1)),
		"modifiers": selection.get("modifiers", []), "gus": humans == 1 or gus_forced, "first_visit_coaches": []}
	if cfg["mode"] == "playground":
		cfg["layout"] = "P6"
	sim = HotelSim.new(content, cfg)
	sim.record_inputs = true
	SimGuests.warm_paths(sim)
	phase = "shift"
	inputs.clear()
	baselines.clear()
	events.clear()
	result = {}
	auto_pause_used.clear()
	paused = false
	start_only_ready = false
	ready_wait_since = 0.0
	for s in seats:
		s["ready"] = false

func push_input(seat_id: int, f: Dictionary, now_ms: int) -> void:
	var cur: Dictionary = inputs.get(seat_id, {"pressed": 0})
	var pressed := int(cur.get("pressed", 0)) | int(f.get("pressed", 0))
	inputs[seat_id] = {"frame": f, "t_ms": now_ms, "pressed": pressed, "pick": int(f.get("pick", -1)) if int(f.get("pick", -1)) >= 0 else int(cur.get("pick", -1))}

func step(now_ms: int) -> void:
	var frames: Array = []
	for s in seats:
		var inp: Dictionary = inputs.get(s["id"], {})
		var f: Dictionary = inp.get("frame", {})
		var stale: bool = now_ms - int(inp.get("t_ms", 0)) > STALE_INPUT_MS
		frames.append({"seat": s["id"], "ax": 0 if stale else int(f.get("ax", 0)), "az": 0 if stale else int(f.get("az", 0)),
			"held": 0 if stale else int(f.get("held", 0)), "pressed": int(inp.get("pressed", 0)), "pick": int(inp.get("pick", -1))})
		if inputs.has(s["id"]):
			inputs[s["id"]]["pressed"] = 0
			inputs[s["id"]]["pick"] = -1
	sim.step(frames)
	tick += 1
	for e in sim.events:
		if events.size() < 400:
			events.append(e)

## Section-level delta snapshot (§20.4). Full state on join/reconnect/every 2 s.
func snapshot_for(peer_id: int, full: bool) -> Dictionary:
	var s: Dictionary = sim.s
	var base: Dictionary = baselines.get(peer_id, {})
	var out := {}
	var hashes := {}
	for k in s:
		var h := hash(var_to_bytes(s[k]))
		hashes[k] = h
		if full or base.get(k, -1) != h:
			out[k] = s[k]
	baselines[peer_id] = hashes
	return {"type": "state_snapshot", "room_id": id, "shift_id": shift_id, "tick": tick, "hotel_q": s["hotel_q"],
		"full": full, "s": out, "layout": sim.L.id, "mirror": sim.L.mirrored, "systems": sim.systems.keys(),
		"level": sim.level, "checksum": sim.state_hash() if full else ""}

func checkpoint() -> Dictionary:
	var ss: Array = []
	for s in seats:
		ss.append(s.duplicate(true))
	var d := {"schema": 1, "id": id, "code": code, "created": created, "leader": leader, "seats": ss,
		"selection": selection, "phase": phase, "shift_id": shift_id, "tick": tick}
	if sim != null and phase == "shift":
		d["sim_cfg"] = sim.cfg
		d["sim"] = Marshalls.raw_to_base64(var_to_bytes(sim.snapshot()))
	return d

static func from_checkpoint(d: Dictionary, content) -> NetRoom:
	var r := NetRoom.new()
	r.id = d["id"]; r.code = d["code"]; r.created = float(d.get("created", 0)); r.leader = int(d.get("leader", 0))
	r.seats = d.get("seats", [])
	for s in r.seats:
		s["id"] = int(s["id"]); s["peer"] = 0; s["connected"] = false; s["ready"] = false
		s["missing_at"] = Time.get_unix_time_from_system()
	r.selection = d.get("selection", r.selection)
	r.phase = d.get("phase", "lobby")
	r.shift_id = int(d.get("shift_id", 0))
	r.tick = int(d.get("tick", 0))
	if d.has("sim") and r.phase == "shift":
		var cfg: Dictionary = d["sim_cfg"]
		r.sim = HotelSim.new(content, cfg)
		var snap = bytes_to_var(Marshalls.base64_to_raw(d["sim"]))
		if snap is Dictionary:
			r.sim.restore(snap)
			r.paused = true
			for st in r.sim.s["staff"]:
				st["present"] = false
	else:
		r.phase = "lobby"
	return r
