extends SceneTree
## Four-seat / abuse online test used by tests/net/run_quad.sh (§24.1 NET03, NET05).
##   godot --headless --path . --script res://tests/net/net_quad.gd -- --role=h|j1|j2|j3|x --url=ws://127.0.0.1:18081 --dir=/tmp/rft_quad
## h creates a room with two local seats; j1 and j2 join with one seat each
## (2+1+1); j3 tries to join the full room and must be refused. x runs its own
## room and sends garbage, forged seats, wrong-shift frames, an input flood and
## an oversized message; it must never see the other room's data, and the main
## shift must finish for everyone.

var role := "h"
var url := "ws://127.0.0.1:18081"
var dir := "/tmp/rft_quad"
var net
var obs := {"role": "", "seats": [], "room_id": "", "max_lobby_seats": 0, "max_lobby_peers": 0, "rejected": "",
	"shift_started": false, "snapshots": 0, "foreign_room_data": false, "result": {}, "errors": [],
	"moved_m": 0.0, "hb_after_flood": false, "attacks": 0, "seats_seen_in_shift": 0}
var t0 := 0
var done := false
var ready_sent := {}
var start_xy := {}
var attack_phase := 0
var flood_ms := 0

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--role="): role = a.substr(7)
		elif a.begins_with("--url="): url = a.substr(6)
		elif a.begins_with("--dir="): dir = a.substr(6)
	obs["role"] = role
	t0 = Time.get_ticks_msec()
	DirAccess.make_dir_recursive_absolute(dir)

func _flag(name: String) -> bool:
	return FileAccess.file_exists(dir.path_join(name))

func _set_flag(name: String, text := "1") -> void:
	var f := FileAccess.open(dir.path_join(name), FileAccess.WRITE)
	f.store_string(text)
	f.close()

func _process(_dt: float) -> bool:
	if net == null:
		net = root.get_node_or_null("Net")
		if net == null:
			return false
		net.client_connected.connect(_on_connected)
		net.room_joined.connect(_on_joined)
		net.lobby_updated.connect(_on_lobby)
		net.shift_started.connect(func(_i):
			obs["shift_started"] = true
			if role == "h":
				_set_flag("main_shift"))
		net.shift_result.connect(func(res): obs["result"] = {"result_id": res.get("result_id", ""), "percent": res.get("percent", -1)})
		net.client_failed.connect(_on_failed)
		if role == "j3":
			return false
		net.connect_to(url)
		return false
	if Time.get_ticks_msec() - t0 > 120_000:
		obs["errors"].append("timeout")
		return _finish()
	if role == "j3" and not net.is_online() and net.mode == "offline" and _flag("full") and obs["rejected"] == "":
		net.connect_to(url)
	if role in ["h", "j1", "j2"] and not obs["shift_started"]:
		_maybe_ready(net.c_room)
	var st: Dictionary = net.client_state()
	if not st.is_empty():
		obs["snapshots"] = int(st.get("_snap_id", 0))
		obs["seats_seen_in_shift"] = maxi(int(obs["seats_seen_in_shift"]), st.get("staff", []).size())
		_play(st)
	if role in ["h", "j1", "j2"] and not obs["result"].is_empty():
		return _finish()
	if role == "x" and attack_phase >= 9:
		return _finish()
	if role == "j3" and obs["rejected"] != "":
		_set_flag("j3_done")
		return _finish()
	if done:
		return _finish()
	return false

func _on_failed(reason: String) -> void:
	if role == "j3":
		obs["rejected"] = reason
	else:
		obs["errors"].append("failed:" + reason)

func _on_connected() -> void:
	match role:
		"h": net.create_room(2, ["pip", "moss"])
		"x": net.create_room(1, ["bram"])
		_:
			var code := ""
			var t := Time.get_ticks_msec()
			while code == "" and Time.get_ticks_msec() - t < 20_000:
				if _flag("code.txt"):
					code = FileAccess.get_file_as_string(dir.path_join("code.txt")).strip_edges()
				if code == "":
					OS.delay_msec(100)
			net.join_room(code, 1, ["juniper"])

func _on_joined(info: Dictionary) -> void:
	obs["seats"] = info["seat_ids"]
	obs["room_id"] = info["room_id"]
	if role == "h":
		_set_flag("code.txt", NetProtocol.pretty_code(info["room_code"]))

func _on_lobby(view: Dictionary) -> void:
	var peers := {}
	for s in view.get("seats", []):
		peers[int(s["peer"])] = true
	obs["max_lobby_seats"] = maxi(int(obs["max_lobby_seats"]), view.get("seats", []).size())
	obs["max_lobby_peers"] = maxi(int(obs["max_lobby_peers"]), peers.size())
	if role == "x" and view.get("seats", []).size() > 1:
		obs["foreign_room_data"] = true
	if role == "h" and view.get("seats", []).size() >= 4:
		_set_flag("full")
	_maybe_ready(view)

func _maybe_ready(view: Dictionary) -> void:
	if view.is_empty() or view.get("phase", "lobby") != "lobby":
		return
	# Main room readies only once j3 has been refused, so the refusal is "full", not "underway".
	var go: bool = (role == "x") or (_flag("j3_done") and view.get("seats", []).size() >= 4)
	if not go or not obs["result"].is_empty():
		return
	for sid in obs["seats"]:
		if not ready_sent.get(sid, false):
			ready_sent[sid] = true
			net.lobby(int(sid), "ready")

func _play(st: Dictionary) -> void:
	if not obs["shift_started"] or obs["seats"].is_empty():
		return
	if role == "x" and st.get("staff", []).size() > 1:
		obs["foreign_room_data"] = true
	var frames: Array = []
	for sid in obs["seats"]:
		var me: Dictionary = {}
		for s in st.get("staff", []):
			if int(s["seat"]) == int(sid):
				me = s
		if me.is_empty():
			continue
		if not start_xy.has(sid):
			start_xy[sid] = Vector2(me["x"], me["z"])
		obs["moved_m"] = maxf(float(obs["moved_m"]), Vector2(me["x"], me["z"]).distance_to(start_xy[sid]) / 1e6)
		var ax := 127 if (Time.get_ticks_msec() / 1200) % 2 == 0 else -127
		if st.get("phase", "") == "planning":
			frames.append({"seat": int(sid), "ax": 0, "az": 0, "held": 0, "pressed": SimC.BTN_READY if not me.get("ready", false) else 0})
		else:
			frames.append({"seat": int(sid), "ax": ax, "az": 0, "held": 0, "pressed": 0})
	if role == "x":
		if st.get("phase", "") == "planning":
			net.client_send_frames(frames)
			return
		_attack(st)
		return
	net.client_send_frames(frames)
	if role == "h" and int(st.get("hotel_s", 0)) >= 25 and not done and not st.get("phase", "") in ["wrap", "done"]:
		if not ready_sent.get("end", false):
			ready_sent["end"] = true
			net.lobby(int(obs["seats"][0]), "leader_option", "end")

func _attack(st: Dictionary) -> void:
	if not _flag("main_shift") and attack_phase == 0:
		return
	var mine: int = int(obs["seats"][0])
	match attack_phase:
		0:
			# Garbage, truncated JSON and unknown types.
			for i in 50:
				net._c2s.rpc_id(1, Crypto.new().generate_random_bytes(200 + i))
			net._c2s.rpc_id(1, "{\"type\":\"input_frame\",\"shift_id\":".to_utf8_buffer())
			net._csend({"type": "drop_tables"})
			obs["attacks"] += 52
		1:
			# Forged seats and duplicate/out-of-order lobby sequences.
			for sid in [mine + 1, mine + 2, 7, -1]:
				net.lobby(sid, "unready")
			net.c_seq = 0
			net.lobby(mine, "leader_option", "end")
			obs["attacks"] += 5
		2:
			# Wrong shift id and impossible frames.
			net._csend({"type": "input_frame", "shift_id": 999, "frames": [{"seat": mine, "ax": 127, "az": 0, "held": 0, "pressed": 0, "pick": -1}]})
			net._csend({"type": "input_frame", "shift_id": int(net.c_shift.get("shift_id", 0)), "frames": [{"seat": mine, "ax": 9999, "az": 0, "held": 0, "pressed": 0, "pick": -1}]})
			obs["attacks"] += 2
		3:
			# Input flood: 1500 frames in one burst (rate limited, latest-frame only).
			for i in 1500:
				net.client_send_frames([{"seat": mine, "ax": 127, "az": 0, "held": 0, "pressed": 0}])
			obs["attacks"] += 1500
			flood_ms = Time.get_ticks_msec()
			net.c_rtt = -1.0
		4, 5, 6:
			if Time.get_ticks_msec() - flood_ms > 600 * (attack_phase - 3):
				net._csend({"type": "heartbeat", "sequence": 100 + attack_phase, "t": Time.get_ticks_msec()})
			else:
				return
		7:
			if net.c_rtt >= 0.0:
				obs["hb_after_flood"] = true
			else:
				return
		8:
			# Oversized message (beyond the 64 KiB inbound buffer): the server may drop us, nothing else.
			net._c2s.rpc_id(1, "x".repeat(200_000).to_utf8_buffer())
			obs["attacks"] += 1
			_set_flag("x_oversize_sent")
	attack_phase += 1

func _finish() -> bool:
	if role == "x":
		# Give the server a moment, then leave.
		OS.delay_msec(300)
	var f := FileAccess.open(dir.path_join(role + ".json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(obs, "\t"))
	f.close()
	print("[quad %s] %s" % [role, JSON.stringify(obs)])
	quit(0)
	return true
