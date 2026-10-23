extends Node
## Private online rooms (§20). One fixed RPC path (/root/Net) on client and
## server. The headless service multiplexes independent room simulations and
## sends each snapshot only to that room's peers. Clients request actions;
## the authoritative simulation derives every result.

signal client_connected
signal client_failed(reason_key: String)
signal room_joined(info: Dictionary)
signal lobby_updated(view: Dictionary)
signal shift_started(info: Dictionary)
signal shift_result(res: Dictionary)
signal client_disconnected(reason_key: String)
signal notice(reason_key: String)

const TICK := 1.0 / 30.0

var mode := "offline"
var online := false
var crypto := Crypto.new()

# ------------------------------------------------------------ server state
var peer: WebSocketMultiplayerPeer
var rooms: Dictionary = {}
var code_index: Dictionary = {}
var peer_info: Dictionary = {}
var rl: Dictionary = {}
var scfg := {"port": 8080, "bind": "*", "max_rooms": 16, "data_dir": "user://server", "log_level": "info",
	"joins_per_min": 10, "creates_per_min": 3, "inputs_per_s": 60, "checkpoint_ttl_h": 24, "grace_s": 10}
var _acc := 0.0
var _shutting_down := false
var _log_counts := {}

# ------------------------------------------------------------ client state
var c_url := ""
var c_room: Dictionary = {}
var c_seats: Array = []
var c_token := ""
var c_room_id := ""
var c_state: Dictionary = {}
var c_snap_id := 0
var c_events: Array = []
var c_last_snap_ms := 0
var c_snap_interval := 100.0
var c_seq := 0
var c_rtt := 0.0
var c_last_hb := 0
var c_shift: Dictionary = {}
var c_reconnecting := false
var c_reconnect_deadline := 0.0
var c_last_ack_tick := 0
var c_result_seen: Dictionary = {}
var _probe_mode := false

func is_online() -> bool:
	return online and mode == "client"

func is_server() -> bool:
	return mode == "server"

# ============================================================ server

func start_server_from_args(args: PackedStringArray) -> void:
	for i in args.size():
		var a := args[i]
		var nxt := args[i + 1] if i + 1 < args.size() else ""
		match a:
			"--port": scfg["port"] = int(nxt)
			"--bind": scfg["bind"] = nxt
			"--max-rooms": scfg["max_rooms"] = int(nxt)
			"--data-dir": scfg["data_dir"] = nxt
			"--log-level": scfg["log_level"] = nxt
	for k in ["RFT_PORT", "RFT_BIND", "RFT_MAX_ROOMS", "RFT_DATA_DIR", "RFT_LOG_LEVEL", "RFT_JOINS_PER_MIN",
			"RFT_CREATES_PER_MIN", "RFT_INPUTS_PER_S", "RFT_CHECKPOINT_TTL_H"]:
		var v := OS.get_environment(k)
		if v == "":
			continue
		var key = k.substr(4).to_lower()
		scfg[key] = int(v) if v.is_valid_int() else v
	mode = "server"
	DirAccess.make_dir_recursive_absolute(str(scfg["data_dir"]).path_join("rooms"))
	peer = WebSocketMultiplayerPeer.new()
	peer.inbound_buffer_size = 65536
	peer.outbound_buffer_size = 1 << 20
	peer.max_queued_packets = 4096
	var err := peer.create_server(int(scfg["port"]), str(scfg["bind"]))
	if err != OK:
		_log("error", "listen failed on port %d: %s" % [scfg["port"], error_string(err)])
		get_tree().quit(2)
		return
	multiplayer.multiplayer_peer = peer
	(multiplayer as SceneMultiplayer).server_relay = false
	(multiplayer as SceneMultiplayer).allow_object_decoding = false
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	_restore_checkpoints()
	_log("info", "Room for Trouble service %s listening on %s:%d (max rooms %d, content %s)" % [
		ProjectSettings.get_setting("application/config/version"), scfg["bind"], scfg["port"], scfg["max_rooms"], Content.content_hash])
	get_tree().set_auto_accept_quit(false)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and mode == "server":
		shutdown()

func shutdown() -> void:
	if _shutting_down:
		return
	_shutting_down = true
	_log("info", "graceful shutdown: notifying %d rooms" % rooms.size())
	for rid in rooms:
		var r: NetRoom = rooms[rid]
		_room_send(r, {"type": "notice", "reason": "ui.online.restored"})
		_save_checkpoint(r)
	get_tree().create_timer(1.0).timeout.connect(func(): get_tree().quit(0))

func _log(level: String, msg: String) -> void:
	if level == "debug" and scfg["log_level"] != "debug":
		return
	print("%s [%s] %s" % [Time.get_datetime_string_from_system(true), level, msg])

func _on_peer_connected(pid: int) -> void:
	var ip := peer.get_peer_address(pid)
	if not _rate_ok(ip, "joins", int(scfg["joins_per_min"])):
		peer.disconnect_peer(pid)
		return
	peer_info[pid] = {"hello": false, "ip": ip, "room": "", "seq": -1, "inputs": [], "connected_ms": Time.get_ticks_msec()}

func _on_peer_disconnected(pid: int) -> void:
	var info: Dictionary = peer_info.get(pid, {})
	peer_info.erase(pid)
	var rid: String = info.get("room", "")
	if rid == "" or not rooms.has(rid):
		return
	var r: NetRoom = rooms[rid]
	var now := Time.get_unix_time_from_system()
	for s in r.seats:
		if s["peer"] == pid:
			s["connected"] = false
			s["missing_at"] = now
			if r.sim != null and r.phase == "shift":
				r.sim.set_present(s["id"], false)
	_room_send(r, {"type": "lobby", "view": r.lobby_view()})
	_log("info", "room %s: peer left (%d seats reserved)" % [_rid(r), r.seats_of(pid).size()])

func _rid(r: NetRoom) -> String:
	return r.id.substr(0, 6)

func _rate_ok(ip: String, kind: String, per_min: int) -> bool:
	var now := Time.get_ticks_msec()
	var e: Dictionary = rl.get(ip, {})
	var arr: Array = e.get(kind, [])
	arr = arr.filter(func(t): return now - int(t) < 60_000)
	if arr.size() >= per_min:
		e[kind] = arr
		rl[ip] = e
		return false
	arr.append(now)
	e[kind] = arr
	rl[ip] = e
	return true

@rpc("any_peer", "call_remote", "reliable", 0)
func _c2s(data: PackedByteArray) -> void:
	if mode != "server":
		return
	var pid := multiplayer.get_remote_sender_id()
	if not peer_info.has(pid):
		return
	var d := NetProtocol.parse_client(data)
	if d.is_empty():
		_log_count("malformed")
		return
	_handle(pid, d)

func _send(pid: int, d: Dictionary) -> void:
	if peer == null or peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	if not peer_info.has(pid):
		return
	_s2c.rpc_id(pid, NetProtocol.encode_server(d))

func _room_send(r: NetRoom, d: Dictionary) -> void:
	var bytes := NetProtocol.encode_server(d)
	for p in r.peers():
		if peer_info.has(p):
			_s2c.rpc_id(p, bytes)

func _log_count(k: String) -> void:
	_log_counts[k] = int(_log_counts.get(k, 0)) + 1

func _handle(pid: int, d: Dictionary) -> void:
	var info: Dictionary = peer_info[pid]
	var t: String = d["type"]
	if t == "hello":
		var ok: bool = int(d["protocol"]) == NetProtocol.VERSION and d["content_hash"] == Content.content_hash
		if d.get("probe", false):
			_send(pid, {"type": "hello_ok", "status": "ready" if not _shutting_down else "draining", "rooms": rooms.size(),
				"protocol": NetProtocol.VERSION, "content_hash": Content.content_hash})
			get_tree().create_timer(0.3).timeout.connect(func(): if peer_info.has(pid): peer.disconnect_peer(pid))
			return
		if not ok:
			_send(pid, {"type": "hello_reject", "reason": "ui.online.version"})
			return
		info["hello"] = true
		_send(pid, {"type": "hello_ok", "protocol": NetProtocol.VERSION})
		return
	if not info["hello"]:
		return
	match t:
		"heartbeat":
			_send(pid, {"type": "heartbeat", "sequence": d["sequence"], "t": d["t"]})
		"create_room":
			if _shutting_down:
				_send(pid, {"type": "join_reject", "reason": "ui.online.failed"})
				return
			if not _rate_ok(info["ip"], "creates", int(scfg["creates_per_min"])) or rooms.size() >= int(scfg["max_rooms"]):
				_send(pid, {"type": "join_reject", "reason": "ui.online.full"})
				return
			var n := clampi(int(d["local_seat_count"]), 1, 4)
			var r := NetRoom.new()
			r.id = crypto.generate_random_bytes(12).hex_encode()
			var code := NetProtocol.new_code(crypto)
			while code_index.has(code):
				code = NetProtocol.new_code(crypto)
			r.code = code
			r.created = Time.get_unix_time_from_system()
			r.last_activity = r.created
			rooms[r.id] = r
			code_index[code] = r.id
			_admit(pid, r, n, d.get("chars", []))
			_log("info", "room %s created (%d rooms)" % [_rid(r), rooms.size()])
		"join_room":
			var code2 := NetProtocol.normalize_code(d["room_code"])
			if not code_index.has(code2):
				_send(pid, {"type": "join_reject", "reason": "ui.online.no_room"})
				return
			var r2: NetRoom = rooms[code_index[code2]]
			var n2 := clampi(int(d["local_seat_count"]), 1, 4)
			if r2.phase == "shift":
				_send(pid, {"type": "join_reject", "reason": "ui.online.underway"})
				return
			if n2 > r2.free_seats() or r2.peers().size() >= 4:
				_send(pid, {"type": "join_reject", "reason": "ui.online.full"})
				return
			_admit(pid, r2, n2, d.get("chars", []))
		"reconnect":
			_reconnect(pid, d)
		"leave_room":
			_leave(pid)
		"lobby_command":
			_lobby(pid, d)
		"input_frame":
			_inputs(pid, d)
		"result_ack":
			pass

func _admit(pid: int, r: NetRoom, n: int, chars: Array) -> void:
	var token := crypto.generate_random_bytes(32).hex_encode()
	var th := token.sha256_text()
	var ids := r.add_seats(pid, n, chars, th)
	if r.seats.size() == ids.size():
		r.leader = ids[0]
	peer_info[pid]["room"] = r.id
	_send(pid, {"type": "room_joined", "room_id": r.id, "room_code": r.code, "seat_ids": ids, "reconnect_token": token,
		"leader": r.leader, "lobby": r.lobby_view()})
	_room_send(r, {"type": "lobby", "view": r.lobby_view()})

func _reconnect(pid: int, d: Dictionary) -> void:
	var r: NetRoom = rooms.get(d["room_id"], null)
	if r == null:
		_send(pid, {"type": "reconnect_reject", "reason": "ui.online.no_room"})
		return
	var th: String = str(d["reconnect_token"]).sha256_text()
	var ids: Array = []
	for s in r.seats:
		if s["token_hash"] == th and not s["connected"]:
			s["peer"] = pid
			s["connected"] = true
			ids.append(s["id"])
			if r.sim != null and r.phase == "shift":
				r.sim.set_present(s["id"], true)
	if ids.is_empty():
		_send(pid, {"type": "reconnect_reject", "reason": "ui.online.no_room"})
		return
	peer_info[pid]["room"] = r.id
	_send(pid, {"type": "room_joined", "room_id": r.id, "room_code": r.code, "seat_ids": ids, "reconnect_token": d["reconnect_token"],
		"leader": r.leader, "lobby": r.lobby_view(), "reconnected": true})
	if r.phase == "shift" and r.sim != null:
		_send(pid, _shift_info(r))
		r.baselines.erase(pid)
		_send(pid, r.snapshot_for(pid, true))
		if r.paused and r.pause_until == 0.0:
			r.paused = false
	_room_send(r, {"type": "lobby", "view": r.lobby_view()})

func _leave(pid: int) -> void:
	var info: Dictionary = peer_info.get(pid, {})
	var r: NetRoom = rooms.get(info.get("room", ""), null)
	if r == null:
		return
	for sid in r.seats_of(pid):
		if r.sim != null and r.phase == "shift":
			r.sim.set_present(sid, false)
	r.seats = r.seats.filter(func(s): return s["peer"] != pid)
	info["room"] = ""
	if r.seats.is_empty():
		_close_room(r)
	else:
		if r.seat(r.leader).is_empty():
			r.leader = r.seats[0]["id"]
		_room_send(r, {"type": "lobby", "view": r.lobby_view()})

func _close_room(r: NetRoom) -> void:
	code_index.erase(r.code)
	rooms.erase(r.id)
	var path := str(scfg["data_dir"]).path_join("rooms/%s.json" % r.id)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	_log("info", "room %s closed (%d rooms)" % [_rid(r), rooms.size()])

func _owns(pid: int, r: NetRoom, seat_id: int) -> bool:
	var s := r.seat(seat_id)
	return not s.is_empty() and s["peer"] == pid and s["connected"]

func _lobby(pid: int, d: Dictionary) -> void:
	var info: Dictionary = peer_info[pid]
	var r: NetRoom = rooms.get(info.get("room", ""), null)
	if r == null:
		return
	var seq := int(d["sequence"])
	if seq <= int(info.get("seq", -1)):
		return
	info["seq"] = seq
	var sid := int(d["seat"])
	if not _owns(pid, r, sid):
		_log_count("forged_seat")
		return
	var action: String = d["action"]
	if not action in NetProtocol.LOBBY_ACTIONS:
		return
	var v = d.get("value", null)
	var s := r.seat(sid)
	var is_leader := sid == r.leader
	r.last_activity = Time.get_unix_time_from_system()
	match action:
		"ready": s["ready"] = true
		"unready":
			s["ready"] = false
			r.countdown = 0.0
			if r.phase == "countdown":
				r.phase = "lobby"
		"char":
			if v is String and v in SimC.STAFF_IDS:
				s["char"] = v
		"cos":
			if v is String and v.length() < 32:
				s["cos"] = v
		"assists":
			if v is Dictionary:
				var a := {}
				for k in ["auto_catch", "toggle_work", "steady_feet", "no_step"]:
					a[k] = bool(v.get(k, false))
				s["assists"] = a
		"select_level":
			if is_leader and v is String and Content.level_index(v) >= 0:
				r.selection["level_id"] = v
		"difficulty":
			if is_leader and v is String and v in ["cozy", "family", "busy"]:
				r.selection["difficulty"] = v
		"modifiers":
			if is_leader and v is Array and v.size() <= 2:
				var ms: Array = []
				for m in v:
					if m is String and Content.modifiers.has(m):
						ms.append(m)
				r.selection["modifiers"] = ms
		"mode":
			if is_leader and v is String and v in ["campaign", "quick", "playground"]:
				r.selection["mode"] = v
		"seed":
			if is_leader and (v is float or v is int):
				r.selection["seed"] = int(v)
		"start":
			if r.phase == "lobby" and r.all_ready():
				r.phase = "countdown"
				r.countdown = 3.0
		"start_ready":
			if is_leader and r.phase == "lobby":
				for s2 in r.seats:
					if not s2["ready"]:
						s2["connected"] = s2["connected"]
				r.phase = "countdown"
				r.countdown = 3.0
		"pause":
			if r.phase == "shift" and not r.paused:
				if not r.auto_pause_used.get(sid, false):
					r.auto_pause_used[sid] = true
					r.paused = true
					r.pause_until = Time.get_unix_time_from_system() + 20.0
				elif is_leader:
					r.paused = true
					r.pause_until = 0.0
				_room_send(r, {"type": "pause_state", "paused": r.paused, "reason": str(v) if v is String else "break",
					"remaining": maxf(0.0, r.pause_until - Time.get_unix_time_from_system()) if r.pause_until > 0 else -1.0})
		"resume":
			if r.paused and (is_leader or r.pause_until > 0.0):
				r.paused = false
				r.pause_until = 0.0
				_room_send(r, {"type": "pause_state", "paused": false, "reason": "", "remaining": 0.0})
		"leader_option":
			if is_leader and r.sim != null:
				match str(v):
					"gus":
						r.sim.s["gus"]["on"] = true
						r.gus_forced = true
					"end":
						r.sim.begin_wrap("leader")
					_:
						pass
	if r.phase == "lobby" and r.all_ready() and action == "ready":
		r.phase = "countdown"
		r.countdown = 3.0
	_room_send(r, {"type": "lobby", "view": r.lobby_view()})

func _inputs(pid: int, d: Dictionary) -> void:
	var info: Dictionary = peer_info[pid]
	var r: NetRoom = rooms.get(info.get("room", ""), null)
	if r == null or r.phase != "shift" or int(d["shift_id"]) != r.shift_id:
		return
	var now := Time.get_ticks_msec()
	var arr: Array = info["inputs"]
	arr = arr.filter(func(t): return now - int(t) < 1000)
	if arr.size() > int(scfg["inputs_per_s"]) * maxi(1, r.seats_of(pid).size()):
		info["inputs"] = arr
		_log_count("input_rate")
		return
	arr.append(now)
	info["inputs"] = arr
	var frames: Array = d["frames"]
	if frames.size() > 4:
		return
	for f in frames:
		var cf := NetProtocol.clean_frame(f)
		if cf.is_empty() or not _owns(pid, r, cf["seat"]):
			_log_count("bad_frame")
			continue
		r.push_input(cf["seat"], cf, now)

func _shift_info(r: NetRoom) -> Dictionary:
	return {"type": "shift_started", "shift_id": r.shift_id, "layout": r.sim.L.id, "mirror": r.sim.L.mirrored,
		"systems": r.sim.systems.keys(), "level": r.sim.level, "cfg": r.sim.cfg}

func _server_process(dt: float) -> void:
	_acc += minf(dt, 0.25)
	var now := Time.get_unix_time_from_system()
	var now_ms := Time.get_ticks_msec()
	var steps := 0
	while _acc >= TICK and steps < 6:
		_acc -= TICK
		steps += 1
		for rid in rooms.keys():
			var r: NetRoom = rooms[rid]
			if r.phase == "countdown":
				r.countdown -= TICK
				if r.countdown <= 0.0:
					r.start_shift(Content, Content.content_hash)
					_room_send(r, _shift_info(r))
					_log("info", "room %s shift %d started (%s)" % [_rid(r), r.shift_id, r.selection["level_id"]])
				continue
			if r.phase != "shift" or r.sim == null:
				continue
			if r.paused:
				if r.pause_until > 0.0 and now >= r.pause_until:
					r.paused = false
					r.pause_until = 0.0
					_room_send(r, {"type": "pause_state", "paused": false, "reason": "", "remaining": 0.0})
				continue
			r.step(now_ms)
			if r.tick % 3 == 0:
				var full := r.tick % 60 == 0
				for p in r.peers():
					var snap := r.snapshot_for(p, full or not r.baselines.has(p))
					snap["events"] = r.events
					_send(p, snap)
				r.events = []
			if r.tick % 150 == 0:
				_save_checkpoint(r)
			if r.sim.s["phase"] == "done":
				var res: Dictionary = r.sim.s.get("result", {}).duplicate(true)
				res["result_id"] = "%s-%d" % [r.id.substr(0, 8), r.shift_id]
				res["seed"] = r.selection.get("seed", 1)
				res["staff"] = []
				for st in r.sim.s["staff"]:
					res["staff"].append(st["char"])
				res["mode"] = r.selection.get("mode", "campaign")
				_room_send(r, {"type": "shift_result", "result": res, "manifest_hash": Content.content_hash})
				r.phase = "lobby"
				r.result = res
				r.sim = null
				_save_checkpoint(r)
				_room_send(r, {"type": "lobby", "view": r.lobby_view()})
	# Membership housekeeping once per frame.
	for rid in rooms.keys():
		var r2: NetRoom = rooms[rid]
		var connected := 0
		for s in r2.seats:
			if s["connected"]:
				connected += 1
			elif now - float(s["missing_at"]) > NetRoom.SEAT_RESERVE_S:
				s["token_hash"] = ""
		if r2.seat(r2.leader).get("connected", false) == false:
			for s2 in r2.seats:
				if s2["connected"] and now - float(r2.seat(r2.leader).get("missing_at", now)) > 10.0:
					r2.leader = s2["id"]
					_room_send(r2, {"type": "lobby", "view": r2.lobby_view()})
					break
		if connected == 0:
			var oldest := now
			for s3 in r2.seats:
				oldest = minf(oldest, float(s3.get("missing_at", now)))
			if r2.phase == "shift" and not r2.paused:
				r2.paused = true
			if now - oldest > NetRoom.SEAT_RESERVE_S:
				_save_checkpoint(r2)
				code_index.erase(r2.code)
				rooms.erase(rid)
				_log("info", "room %s suspended to checkpoint" % _rid(r2))
		elif r2.phase == "lobby" and now - r2.last_activity > NetRoom.IDLE_TTL_S:
			_close_room(r2)

func _save_checkpoint(r: NetRoom) -> void:
	var dir := str(scfg["data_dir"]).path_join("rooms")
	var path := dir.path_join("%s.json" % r.id)
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"saved": Time.get_unix_time_from_system(), "content_hash": Content.content_hash, "room": r.checkpoint()}))
	f.close()
	if FileAccess.file_exists(path):
		DirAccess.copy_absolute(path, path + ".prev")
	DirAccess.rename_absolute(tmp, path)

func _restore_checkpoints() -> void:
	var dir := str(scfg["data_dir"]).path_join("rooms")
	var da := DirAccess.open(dir)
	if da == null:
		return
	var now := Time.get_unix_time_from_system()
	for fn in da.get_files():
		if not fn.ends_with(".json"):
			continue
		var d = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join(fn)))
		if not d is Dictionary:
			continue
		if now - float(d.get("saved", 0)) > float(scfg["checkpoint_ttl_h"]) * 3600.0 or d.get("content_hash", "") != Content.content_hash:
			DirAccess.remove_absolute(dir.path_join(fn))
			continue
		var r := NetRoom.from_checkpoint(d["room"], Content)
		rooms[r.id] = r
		code_index[r.code] = r.id
		_log("info", "restored room %s from checkpoint" % _rid(r))

# ============================================================ health probe

func run_probe(args: PackedStringArray) -> void:
	var url := "ws://127.0.0.1:8080"
	for i in args.size():
		if args[i] in ["--probe", "--healthcheck"] and i + 1 < args.size() and not args[i + 1].begins_with("--"):
			url = args[i + 1]
	_probe_mode = true
	mode = "client"
	var ok := await _probe(url)
	print("probe %s: %s" % [url, "ok" if ok else "FAILED"])
	get_tree().quit(0 if ok else 1)

func _probe(url: String) -> bool:
	var p := WebSocketMultiplayerPeer.new()
	if p.create_client(url, TLSOptions.client_unsafe() if url.begins_with("wss://") and OS.get_environment("RFT_PROBE_INSECURE") == "1" else TLSOptions.client()) != OK:
		return false
	multiplayer.multiplayer_peer = p
	var t0 := Time.get_ticks_msec()
	while p.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTING and Time.get_ticks_msec() - t0 < 5000:
		await get_tree().process_frame
	if p.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return false
	_probe_reply = {}
	_c2s.rpc_id(1, NetProtocol.encode_client({"type": "hello", "protocol": NetProtocol.VERSION, "build_tag": _build_tag(), "content_hash": Content.content_hash, "probe": true}))
	while _probe_reply.is_empty() and Time.get_ticks_msec() - t0 < 6000:
		await get_tree().process_frame
	multiplayer.multiplayer_peer = null
	if _probe_reply.get("type", "") == "hello_ok" and _probe_reply.get("status", "") == "ready":
		print("rooms=%d protocol=%d content=%s" % [_probe_reply.get("rooms", 0), _probe_reply.get("protocol", 0), _probe_reply.get("content_hash", "")])
		return true
	return false

var _probe_reply: Dictionary = {}

# ============================================================ client

func _build_tag() -> String:
	return "%s-%s" % [ProjectSettings.get_setting("application/config/version"), Engine.get_version_info()["string"]]

func connect_to(url: String) -> void:
	disconnect_client()
	c_url = url
	mode = "client"
	peer = WebSocketMultiplayerPeer.new()
	peer.inbound_buffer_size = 1 << 20
	peer.outbound_buffer_size = 65536
	var tls: TLSOptions = null
	if url.begins_with("wss://"):
		tls = TLSOptions.client_unsafe() if Settings.g("allow_insecure_tls") == true else TLSOptions.client()
	var err := peer.create_client(url, tls)
	if err != OK:
		client_failed.emit("ui.online.failed")
		mode = "offline"
		return
	multiplayer.multiplayer_peer = peer
	(multiplayer as SceneMultiplayer).allow_object_decoding = false
	if not multiplayer.connected_to_server.is_connected(_on_connected):
		multiplayer.connected_to_server.connect(_on_connected)
		multiplayer.connection_failed.connect(_on_failed)
		multiplayer.server_disconnected.connect(_on_server_gone)

func disconnect_client() -> void:
	if mode == "client" and multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	online = false
	if mode == "client":
		mode = "offline"

func _on_connected() -> void:
	_csend({"type": "hello", "protocol": NetProtocol.VERSION, "build_tag": _build_tag(), "content_hash": Content.content_hash})

func _on_failed() -> void:
	if c_reconnecting:
		return
	client_failed.emit("ui.online.failed")
	mode = "offline"

func _on_server_gone() -> void:
	if c_room_id != "" and c_token != "" and not c_reconnecting:
		c_reconnecting = true
		c_reconnect_deadline = Time.get_unix_time_from_system() + 90.0
		notice.emit("ui.online.disconnected")
		_try_reconnect()
		return
	online = false
	client_disconnected.emit("ui.online.disconnected")

func _try_reconnect() -> void:
	if not c_reconnecting:
		return
	if Time.get_unix_time_from_system() > c_reconnect_deadline:
		c_reconnecting = false
		online = false
		client_disconnected.emit("ui.online.disconnected")
		return
	var url := c_url
	var room := c_room_id
	var tok := c_token
	disconnect_client()
	c_room_id = room
	c_token = tok
	connect_to(url)
	get_tree().create_timer(3.0).timeout.connect(func():
		if c_reconnecting and (peer == null or peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED):
			_try_reconnect())

func _csend(d: Dictionary) -> void:
	if peer == null or peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	_c2s.rpc_id(1, NetProtocol.encode_client(d))

@rpc("authority", "call_remote", "reliable", 0)
func _s2c(data: PackedByteArray) -> void:
	if mode != "client":
		return
	var d := NetProtocol.decode_server(data)
	if d.is_empty():
		return
	if _probe_mode:
		_probe_reply = d
		return
	_client_handle(d)

func _client_handle(d: Dictionary) -> void:
	match d.get("type", ""):
		"hello_ok":
			if c_reconnecting and c_room_id != "":
				_csend({"type": "reconnect", "room_id": c_room_id, "reconnect_token": c_token, "last_ack": c_last_ack_tick})
			else:
				online = true
				client_connected.emit()
		"hello_reject":
			client_failed.emit(d.get("reason", "ui.online.version"))
		"join_reject", "reconnect_reject":
			if c_reconnecting:
				c_reconnecting = false
				online = false
				client_disconnected.emit(d.get("reason", "ui.online.disconnected"))
			else:
				client_failed.emit(d.get("reason", "ui.online.failed"))
		"room_joined":
			online = true
			c_room_id = d["room_id"]
			c_token = d["reconnect_token"]
			c_seats = d["seat_ids"]
			c_room = d["lobby"]
			if d.get("reconnected", false):
				c_reconnecting = false
				notice.emit("ui.online.restored")
			room_joined.emit(d)
		"lobby":
			c_room = d["view"]
			lobby_updated.emit(c_room)
		"shift_started":
			c_shift = d
			c_state = {}
			c_snap_id = 0
			c_events.clear()
			shift_started.emit(d)
		"state_snapshot":
			if d["full"]:
				c_state = d["s"]
			else:
				for k in d["s"]:
					c_state[k] = d["s"][k]
			c_last_ack_tick = int(d["tick"])
			var now := Time.get_ticks_msec()
			if c_last_snap_ms > 0:
				c_snap_interval = lerpf(c_snap_interval, float(now - c_last_snap_ms), 0.2)
			c_last_snap_ms = now
			c_snap_id += 1
			c_state["_snap_id"] = c_snap_id
			for e in d.get("events", []):
				c_events.append(e)
		"shift_result":
			var res: Dictionary = d["result"]
			if not c_result_seen.has(res.get("result_id", "")):
				c_result_seen[res.get("result_id", "")] = true
				c_state["phase"] = "done"
				c_state["result"] = res
				shift_result.emit(res)
				_csend({"type": "result_ack", "result_id": res.get("result_id", "")})
		"pause_state":
			notice.emit("ui.pause.title" if d.get("paused", false) else "")
		"heartbeat":
			c_rtt = float(Time.get_ticks_msec() - int(d["t"]))
		"notice":
			notice.emit(d.get("reason", ""))

func create_room(local_seats: int, chars: Array) -> void:
	_csend({"type": "create_room", "local_seat_count": local_seats, "chars": chars})

func join_room(code: String, local_seats: int, chars: Array) -> void:
	_csend({"type": "join_room", "room_code": code, "local_seat_count": local_seats, "chars": chars})

func lobby(seat: int, action: String, value = null) -> void:
	c_seq += 1
	var d := {"type": "lobby_command", "sequence": c_seq, "seat": seat, "action": action}
	if value != null:
		d["value"] = value
	_csend(d)

func leave_room() -> void:
	_csend({"type": "leave_room"})
	c_room_id = ""
	c_token = ""
	c_room = {}

func client_send_frames(frames: Array) -> void:
	if c_shift.is_empty():
		return
	var out: Array = []
	for f in frames:
		out.append({"seat": int(f["seat"]), "ax": int(f["ax"]), "az": int(f["az"]), "held": int(f["held"]),
			"pressed": int(f["pressed"]), "pick": int(f.get("pick", -1))})
	_csend({"type": "input_frame", "shift_id": int(c_shift.get("shift_id", 0)), "frames": out})

func client_state() -> Dictionary:
	return c_state

func client_take_events() -> Array:
	var e := c_events
	c_events = []
	return e

func client_alpha() -> float:
	return clampf(float(Time.get_ticks_msec() - c_last_snap_ms) / maxf(30.0, c_snap_interval), 0.0, 1.0)

func client_connection_map() -> Dictionary:
	var out := {}
	var q := "good" if c_rtt < 150.0 and Time.get_ticks_msec() - c_last_snap_ms < 500 else "poor"
	if c_reconnecting:
		q = "lost"
	for s in c_room.get("seats", []):
		out[int(s["id"])] = q if s.get("connected", true) else "lost"
	return out

func client_report_result(_res: Dictionary) -> void:
	pass

func _process(dt: float) -> void:
	if mode == "server":
		_server_process(dt)
	elif mode == "client" and online and not _probe_mode:
		var now := Time.get_ticks_msec()
		if now - c_last_hb > 1000:
			c_last_hb = now
			_csend({"type": "heartbeat", "sequence": c_seq, "t": now})
