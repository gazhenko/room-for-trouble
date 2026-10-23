extends SceneTree
## "Start with ready players" (§11.4), used by tests/net/run_ready.sh.
##   godot --headless --path . --script res://tests/net/net_ready.gd -- --role=h|j --url=ws://127.0.0.1:18082 --dir=/tmp/rft_ready
## h creates a room and readies; j joins and never readies. h tries to start
## early (must be refused), then after 20 s starts with ready players. j must
## be told it is sitting out and must not have a character in the shift.

var role := "h"
var url := "ws://127.0.0.1:18082"
var dir := "/tmp/rft_ready"
var net
var obs := {"role": "", "seats": [], "early_start_refused": false, "shift_started": false, "staff_in_shift": -1,
	"my_seat_in_shift": false, "notices": [], "result": {}, "errors": [], "started_after_s": -1.0}
var t0 := 0
var ready_at := 0
var early_sent := false
var late_sent := false
var ended := false

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
		net.shift_started.connect(func(_i):
			obs["shift_started"] = true
			obs["started_after_s"] = (Time.get_ticks_msec() - ready_at) / 1000.0)
		net.shift_result.connect(func(res): obs["result"] = {"result_id": res.get("result_id", "")})
		net.notice.connect(func(k): obs["notices"].append(k))
		net.client_failed.connect(func(r): obs["errors"].append("failed:" + r))
		net.connect_to(url)
		return false
	if Time.get_ticks_msec() - t0 > 100_000:
		obs["errors"].append("timeout")
		return _finish()
	var view: Dictionary = net.c_room
	if role == "h" and not obs["seats"].is_empty() and view.get("seats", []).size() >= 2 and not obs["shift_started"]:
		var mine: int = obs["seats"][0]
		if ready_at == 0:
			ready_at = Time.get_ticks_msec()
			net.lobby(mine, "ready")
		elif not early_sent and Time.get_ticks_msec() - ready_at > 3000:
			early_sent = true
			net.lobby(mine, "start_ready")
		elif early_sent and not obs["early_start_refused"] and Time.get_ticks_msec() - ready_at > 6000:
			obs["early_start_refused"] = view.get("phase", "") == "lobby"
		elif not late_sent and Time.get_ticks_msec() - ready_at > 21_500:
			late_sent = true
			net.lobby(mine, "start_ready")
	var st: Dictionary = net.client_state()
	if obs["shift_started"] and not st.is_empty():
		var staff: Array = st.get("staff", [])
		obs["staff_in_shift"] = staff.size()
		for s in staff:
			if int(s["seat"]) in obs["seats"]:
				obs["my_seat_in_shift"] = true
		if role == "h":
			var mine2: int = obs["seats"][0]
			if st.get("phase", "") == "planning":
				net.client_send_frames([{"seat": mine2, "ax": 0, "az": 0, "held": 0, "pressed": SimC.BTN_READY}])
			elif int(st.get("hotel_s", 0)) >= 6 and not ended:
				ended = true
				net.lobby(mine2, "leader_option", "end")
	if not obs["result"].is_empty():
		return _finish()
	return false

func _on_connected() -> void:
	if role == "h":
		net.create_room(1, ["pip"])
		return
	var code := ""
	var t := Time.get_ticks_msec()
	while code == "" and Time.get_ticks_msec() - t < 15000:
		if FileAccess.file_exists(dir.path_join("code.txt")):
			code = FileAccess.get_file_as_string(dir.path_join("code.txt")).strip_edges()
		if code == "":
			OS.delay_msec(100)
	net.join_room(code, 1, ["moss"])

func _on_joined(info: Dictionary) -> void:
	obs["seats"] = info["seat_ids"]
	if role == "h":
		var f := FileAccess.open(dir.path_join("code.txt"), FileAccess.WRITE)
		f.store_string(NetProtocol.pretty_code(info["room_code"]))
		f.close()

func _finish() -> bool:
	var f := FileAccess.open(dir.path_join(role + ".json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(obs, "\t"))
	f.close()
	print("[ready %s] %s" % [role, JSON.stringify(obs)])
	quit(0)
	return true
