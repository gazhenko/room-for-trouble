extends SceneTree
## End-to-end online client used by tests/net/run_e2e.sh (§24.1 NET01–NET03).
##   godot --headless --path . --script res://tests/net/net_client.gd -- --role=a|b --url=ws://127.0.0.1:18080 --dir=/tmp/rft_e2e
## Role a creates the room and leads; role b joins by code. Both play scripted
## inputs; b forges a frame for a's seat, disconnects and reconnects; a ends the
## shift. Each writes <dir>/<role>.json with observations.

var role := "a"
var url := "ws://127.0.0.1:18080"
var dir := "/tmp/rft_e2e"
var obs := {"role": "", "connected": false, "room": "", "seats": [], "lobby_peers": 0, "shift_started": false,
	"snapshots": 0, "hotel_s_max": 0, "my_moved_m": 0.0, "other_seat_forged_moved": false, "reconnected": false,
	"result": {}, "errors": [], "guests_seen": 0}
var net
var phase := "connect"
var t0 := 0
var start_pos := {}
var reconnect_done := false

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--role="): role = a.substr(7)
		elif a.begins_with("--url="): url = a.substr(6)
		elif a.begins_with("--dir="): dir = a.substr(6)
	obs["role"] = role
	t0 = Time.get_ticks_msec()
	DirAccess.make_dir_recursive_absolute(dir)

func _process(_dt: float) -> bool:
	if net == null:
		net = root.get_node_or_null("Net")
		if net == null:
			return false
		net.client_connected.connect(_on_connected)
		net.room_joined.connect(_on_joined)
		net.lobby_updated.connect(_on_lobby)
		net.shift_started.connect(func(_i): obs["shift_started"] = true)
		net.shift_result.connect(_on_result)
		net.client_failed.connect(func(r): obs["errors"].append("failed:" + r))
		net.connect_to(url)
		return false
	var elapsed := Time.get_ticks_msec() - t0
	if elapsed > 90_000:
		obs["errors"].append("timeout in phase " + phase)
		return _finish()
	var st: Dictionary = net.client_state()
	if not st.is_empty():
		obs["snapshots"] = int(st.get("_snap_id", 0))
		obs["hotel_s_max"] = maxi(int(obs["hotel_s_max"]), int(st.get("hotel_s", 0)))
		obs["guests_seen"] = maxi(int(obs["guests_seen"]), st.get("guests", {}).size())
		_play(st)
	if phase == "done":
		return _finish()
	return false

func _on_connected() -> void:
	obs["connected"] = true
	if role == "a":
		net.create_room(1, ["pip"])
	else:
		var code := ""
		var t := Time.get_ticks_msec()
		while code == "" and Time.get_ticks_msec() - t < 15000:
			if FileAccess.file_exists(dir.path_join("code.txt")):
				code = FileAccess.get_file_as_string(dir.path_join("code.txt")).strip_edges()
			if code == "":
				OS.delay_msec(100)
		net.join_room(code.to_lower(), 1, ["moss"])   # lowercase: codes are case-insensitive

func _on_joined(info: Dictionary) -> void:
	if info.get("reconnected", false):
		obs["reconnected"] = true
		return
	obs["room"] = info["room_code"]
	obs["seats"] = info["seat_ids"]
	if role == "a":
		var f := FileAccess.open(dir.path_join("code.txt"), FileAccess.WRITE)
		f.store_string(NetProtocol.pretty_code(info["room_code"]))
		f.close()
	phase = "lobby"

func _on_lobby(view: Dictionary) -> void:
	var peers := {}
	for s in view.get("seats", []):
		peers[int(s["peer"])] = true
	obs["lobby_peers"] = maxi(int(obs["lobby_peers"]), peers.size())
	if phase != "lobby":
		return
	if view.get("seats", []).size() >= 2:
		var mine: int = obs["seats"][0]
		if role == "a" and view["selection"].get("level_id", "") != "L01":
			net.lobby(mine, "select_level", "L01")
		var ready := false
		for s2 in view["seats"]:
			if int(s2["id"]) == mine:
				ready = s2["ready"]
		if not ready:
			net.lobby(mine, "ready")

func _play(st: Dictionary) -> void:
	if obs["seats"].is_empty() or not obs["shift_started"]:
		return
	var mine: int = obs["seats"][0]
	var me: Dictionary = {}
	var other: Dictionary = {}
	for s in st.get("staff", []):
		if int(s["seat"]) == mine: me = s
		else: other = s
	if me.is_empty():
		return
	if not start_pos.has("me"):
		start_pos["me"] = Vector2(me["x"], me["z"])
	if not other.is_empty() and not start_pos.has("other"):
		start_pos["other"] = Vector2(other["x"], other["z"])
	obs["my_moved_m"] = maxf(float(obs["my_moved_m"]), Vector2(me["x"], me["z"]).distance_to(start_pos["me"]) / 1e6)
	var frames: Array = []
	if st.get("phase", "") == "planning":
		frames.append({"seat": mine, "ax": 0, "az": 0, "held": 0, "pressed": SimC.BTN_READY if not me.get("ready", false) else 0})
	else:
		var ax := 127 if (Time.get_ticks_msec() / 1500) % 2 == 0 else -127
		frames.append({"seat": mine, "ax": ax, "az": 0, "held": 0, "pressed": 0})
	# NET01: forge a frame for the other player's seat — must be ignored.
	if role == "b" and not other.is_empty():
		frames.append({"seat": int(other["seat"]), "ax": 0, "az": 127, "held": 0, "pressed": 0})
	net.client_send_frames(frames)
	if role == "a" and not other.is_empty() and start_pos.has("other"):
		var drift = Vector2(other["x"], other["z"]) - start_pos["other"]
		if drift.y > 400_000 and absf(drift.x) < 100_000:
			obs["other_seat_forged_moved"] = true
	var hs := int(st.get("hotel_s", 0))
	# NET02: b drops its connection mid-shift and reconnects with its token.
	if role == "b" and hs >= 8 and not reconnect_done:
		reconnect_done = true
		net.peer.close()
		net._on_server_gone()
	if role == "a" and hs >= 30 and phase != "ending" and phase != "done":
		phase = "ending"
		net.lobby(mine, "leader_option", "end")

func _on_result(res: Dictionary) -> void:
	obs["result"] = {"percent": res.get("percent", -1), "result_id": res.get("result_id", ""), "scheduled": res.get("scheduled", 0)}
	phase = "done"

func _finish() -> bool:
	var f := FileAccess.open(dir.path_join(role + ".json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(obs, "\t"))
	f.close()
	print("[e2e %s] %s" % [role, JSON.stringify(obs)])
	quit(0)
	return true
