extends Node
## Global and per-seat settings (§11.3). Stored inside the couch profile.
## Individual settings follow the local seat; shared UI scale uses the largest
## requested size. Reducing effects never removes mechanical information.

signal changed(key: String)

const DEFAULTS := {
	"master": 0.9, "music": 0.7, "effects": 0.85, "voices": 0.8, "ui": 0.8,
	"mono": false, "gentle_sound": false, "mute_chatter": false,
	"fullscreen": false, "vsync": true, "pixel_size": "classic", "outlines": true,
	"ui_scale": 1.0, "high_contrast": false, "palette": "default", "reduced_motion": false,
	"reduced_transparency": false, "flashes": false, "camera_shake": false, "vibration": 0.6,
	"large_requests": false, "persistent_silhouettes": true, "readable_font": false,
	"captions": true, "speaker_names": true, "sound_visuals": true, "reading_auto_advance": false,
	"hints": true, "read_aloud": false, "difficulty": "family", "pace_milli": 1000,
	"gus_assist": false, "endpoint": "wss://play.example.invalid/game", "language": "en",
	"pseudo_loc": false, "shared_keyboard_ok": false,
}

const SEAT_DEFAULTS := {
	"auto_catch": true, "toggle_work": false, "quick_step": "on", "steady_feet": false,
	"deadzone": 0.2, "sensitivity": 1.0, "auto_pickup": false, "vibration": 0.6,
	"ui_scale": 1.0,
}

const PIXEL_LINES := {"chunky": 270, "classic": 360, "fine": 540, "off": 0}

var data: Dictionary = {}
var seats: Array = []

func _ready() -> void:
	_load()
	apply_runtime()

func _load() -> void:
	var stored: Dictionary = SaveService.profile.get("settings", {})
	data = DEFAULTS.duplicate(true)
	for k in stored:
		if k != "seats":
			data[k] = stored[k]
	# Operators can ship a default endpoint beside the executable (endpoint.txt)
	# or set RFT_ENDPOINT per launch; a player's own choice otherwise persists.
	var env_ep := OS.get_environment("RFT_ENDPOINT")
	var file_ep := ""
	var ep_file := OS.get_executable_path().get_base_dir().path_join("endpoint.txt")
	if FileAccess.file_exists(ep_file):
		file_ep = FileAccess.get_file_as_string(ep_file).strip_edges()
	if env_ep != "":
		data["endpoint"] = env_ep
	elif file_ep != "" and data["endpoint"] == DEFAULTS["endpoint"]:
		data["endpoint"] = file_ep
	seats = []
	var ss: Array = stored.get("seats", [])
	for i in 4:
		var s: Dictionary = SEAT_DEFAULTS.duplicate(true)
		if i < ss.size() and ss[i] is Dictionary:
			for k in ss[i]:
				s[k] = ss[i][k]
		seats.append(s)

func g(key: String):
	return data.get(key, DEFAULTS.get(key))

func set_value(key: String, v) -> void:
	data[key] = v
	_persist()
	apply_runtime()
	changed.emit(key)

func seat(i: int) -> Dictionary:
	return seats[clampi(i, 0, 3)]

func set_seat(i: int, key: String, v) -> void:
	seats[clampi(i, 0, 3)][key] = v
	_persist()
	changed.emit("seat.%d.%s" % [i, key])

func _persist() -> void:
	var out := data.duplicate(true)
	out["seats"] = seats.duplicate(true)
	SaveService.profile["settings"] = out
	SaveService.save()

func seat_assists(i: int) -> Dictionary:
	var s := seat(i)
	return {"auto_catch": s["auto_catch"], "toggle_work": s["toggle_work"],
		"no_step": s["quick_step"] == "off", "steady_feet": s["steady_feet"]}

func assist_signature(seat_ids: Array) -> String:
	var parts: Array = []
	if g("gus_assist"):
		parts.append("gus")
	for i in seat_ids:
		var s := seat(i)
		if s["steady_feet"]: parts.append("feet%d" % i)
		if s["toggle_work"]: parts.append("tw%d" % i)
	return "none" if parts.is_empty() else "+".join(parts)

func effective_ui_scale() -> float:
	var sc: float = float(g("ui_scale"))
	for s in seats:
		sc = maxf(sc, float(s.get("ui_scale", 1.0)))
	return sc

func pixel_lines() -> int:
	return PIXEL_LINES.get(g("pixel_size"), 360)

func apply_runtime() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var fs: bool = g("fullscreen")
	var mode := DisplayServer.window_get_mode()
	if fs and mode != DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	elif not fs and mode == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if g("vsync") else DisplayServer.VSYNC_DISABLED)
	Loc.pseudo = bool(g("pseudo_loc"))
	for bus in ["Master", "Music", "Effects", "Voices", "UI"]:
		var idx := AudioServer.get_bus_index(bus)
		if idx >= 0:
			var v: float = float(g(bus.to_lower()))
			AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(0.0001, v)))
			AudioServer.set_bus_mute(idx, v <= 0.001)
