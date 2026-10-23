extends Node
## Audio direction (§18): buses Master/Music/Effects/Voices/UI, a master
## limiter, four synchronized chapter stems crossfaded on bar boundaries by
## task intensity (minimum dwell 16 s), ducking under captions, chatter and
## warning voice limits, and captioned squeak/warble "speech".

const MANIFEST := "res://assets/export/audio/audio_manifest.json"
const BPM := 108.0
const BAR_S := 60.0 / BPM * 4.0
const STEMS := ["calm", "move", "busy", "celeb"]
const SPEAKER_PITCH := {"nana": 0.82, "gus": 1.55, "dot": 1.35, "pip": 1.3, "pebble": 0.9, "moss": 1.15,
	"button": 1.2, "mallow": 1.1, "flurry": 0.8, "cinder": 1.25, "whisp": 1.4, "luna": 1.0, "fern": 1.3,
	"slime": 1.1, "yeti": 0.8, "dragon": 1.25, "ghost": 1.4, "moonwolf": 1.0, "sprout": 1.3}

var cues: Dictionary = {}
var _streams: Dictionary = {}
var _pool: Array = []
var _stems: Array = []          # AudioStreamPlayer x4
var _stem_target: Array = [1.0, 0.0, 0.0, 0.0]
var _music_player: AudioStreamPlayer
var _chapter := 0
var _intensity := 0
var _intensity_since := 0.0
var _pending_intensity := -1
var _duck := 0.0
var _duck_target := 0.0
var _chatter: Array = []
var _warning: AudioStreamPlayer
var _music_mode := ""
var enabled := true
var _lowpass: AudioEffectLowPassFilter
var _time := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if DisplayServer.get_name() == "headless":
		enabled = false
		return
	_setup_buses()
	_load_manifest()
	for i in 14:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool.append(p)
	for i in 4:
		var sp := AudioStreamPlayer.new()
		sp.bus = "Music"
		sp.volume_db = -80.0
		add_child(sp)
		_stems.append(sp)
	_music_player = AudioStreamPlayer.new()
	_music_player.bus = "Music"
	add_child(_music_player)
	_warning = AudioStreamPlayer.new()
	_warning.bus = "Effects"
	add_child(_warning)
	Settings.apply_runtime()

func _setup_buses() -> void:
	for name in ["Music", "Effects", "Voices", "UI"]:
		if AudioServer.get_bus_index(name) == -1:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, name)
			AudioServer.set_bus_send(idx, "Master")
	var music := AudioServer.get_bus_index("Music")
	_lowpass = AudioEffectLowPassFilter.new()
	_lowpass.cutoff_hz = 900.0
	AudioServer.add_bus_effect(music, _lowpass)
	AudioServer.set_bus_effect_enabled(music, 0, false)
	var master := AudioServer.get_bus_index("Master")
	var lim := AudioEffectHardLimiter.new()
	lim.ceiling_db = -1.0
	AudioServer.add_bus_effect(master, lim)
	var mono := AudioEffectStereoEnhance.new()
	mono.pan_pullout = 0.0
	AudioServer.add_bus_effect(master, mono)
	AudioServer.set_bus_effect_enabled(master, 1, false)

func set_mono(on: bool) -> void:
	if not enabled:
		return
	AudioServer.set_bus_effect_enabled(AudioServer.get_bus_index("Master"), 1, on)

func _load_manifest() -> void:
	if not FileAccess.file_exists(MANIFEST):
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	if d is Dictionary:
		var list = d.get("cues", d.get("files", []))
		if list is Array:
			for c in list:
				cues[c["id"]] = c
		elif list is Dictionary:
			for k in list:
				var c2: Dictionary = list[k]
				c2["id"] = k
				cues[k] = c2

func _stream(id: String) -> AudioStream:
	if _streams.has(id):
		return _streams[id]
	var c: Dictionary = cues.get(id, {})
	var path: String = c.get("path", "")
	if path == "":
		for prefix in ["res://assets/export/audio/sfx/", "res://assets/export/audio/music/", "res://assets/export/audio/voice/"]:
			if ResourceLoader.exists(prefix + id + ".ogg"):
				path = prefix + id + ".ogg"
				break
	var st: AudioStream = null
	if path != "" and ResourceLoader.exists(path):
		st = load(path)
		if st is AudioStreamOggVorbis:
			(st as AudioStreamOggVorbis).loop = bool(c.get("loop", false))
	_streams[id] = st
	return st

func has_cue(id: String) -> bool:
	return cues.has(id) or _stream(id) != null

## Plays a one-shot. Variants id_1/id_2 are chosen cosmetically.
func sfx(id: String, volume_db := 0.0, pitch := 1.0, bus := "") -> void:
	if not enabled:
		return
	var use := id
	if not cues.has(id) and cues.has(id + "_1"):
		use = id + ("_1" if randf() < 0.5 or not cues.has(id + "_2") else "_2")
	var st := _stream(use)
	if st == null:
		return
	var b: String = bus if bus != "" else cues.get(use, {}).get("bus", "Effects")
	if b.begins_with("guest") or use.begins_with("guest_"):
		if Settings.g("mute_chatter") and ("idle" in use):
			return
		_chatter = _chatter.filter(func(p): return is_instance_valid(p) and p.playing)
		if _chatter.size() >= 2 and "idle" in use:
			return
	var p := _free_player()
	p.stream = st
	p.bus = b
	p.volume_db = volume_db + (-4.0 if Settings.g("gentle_sound") and b == "Effects" else 0.0)
	p.pitch_scale = pitch
	p.play()
	if use.begins_with("guest_"):
		_chatter.append(p)

func ui(id: String) -> void:
	sfx(id, 0.0, 1.0, "UI")

## Only one prioritized incident warning sound at a time (§18.3).
func warning(id: String) -> void:
	if not enabled:
		return
	if _warning.playing:
		return
	var st := _stream(id)
	if st == null:
		return
	_warning.stream = st
	_warning.volume_db = -3.0 if Settings.g("gentle_sound") else 0.0
	_warning.play()
	duck(0.6)

func _free_player() -> AudioStreamPlayer:
	for p in _pool:
		if not p.playing:
			return p
	return _pool[0]

## Captioned squeak/warble speech: a few syllables pitched per speaker.
func babble(speaker: String, text: String) -> void:
	if not enabled:
		return
	var n := clampi(text.length() / 9, 2, 7)
	var pitch: float = SPEAKER_PITCH.get(speaker, 1.0)
	duck(0.4 + n * 0.12)
	for i in n:
		var syl := "syl_%02d" % (1 + (text.hash() + i * 7) % 16)
		var t := get_tree().create_timer(i * 0.11, true, false, true)
		t.timeout.connect(func(): sfx(syl, -3.0, pitch * (0.94 + 0.12 * ((i * 37) % 5) / 4.0), "Voices"))

func duck(seconds: float) -> void:
	_duck_target = 1.0
	var t := get_tree().create_timer(seconds, true, false, true)
	t.timeout.connect(func(): _duck_target = 0.0)

# ------------------------------------------------------------ music

func play_music(id: String) -> void:
	if not enabled:
		return
	if _music_mode == id:
		return
	_stop_stems()
	_music_mode = id
	var st := _stream(id)
	if st == null:
		_music_player.stop()
		return
	if st is AudioStreamOggVorbis:
		(st as AudioStreamOggVorbis).loop = true
	_music_player.stream = st
	_music_player.volume_db = 0.0
	_music_player.play()

func stop_music() -> void:
	_music_mode = ""
	if not enabled:
		return
	_music_player.stop()
	_stop_stems()

func sting(id: String) -> void:
	sfx(id, 0.0, 1.0, "Music")

## Loads a chapter's four music stems ahead of time (no hitch at shift start).
func preload_chapter(chapter: int) -> void:
	if not enabled:
		return
	for stem in STEMS:
		_stream("ch%d_%s" % [chapter, stem])

func start_chapter(chapter: int) -> void:
	if not enabled:
		return
	_music_player.stop()
	_music_mode = "chapter%d" % chapter
	_chapter = chapter
	for i in 4:
		var st := _stream("ch%d_%s" % [chapter, STEMS[i]])
		var p: AudioStreamPlayer = _stems[i]
		p.stop()
		if st is AudioStreamOggVorbis:
			(st as AudioStreamOggVorbis).loop = true
		p.stream = st
	_stem_target = [1.0, 0.0, 0.0, 0.0]
	_intensity = 0
	_intensity_since = _time
	for i in 4:
		var p2: AudioStreamPlayer = _stems[i]
		p2.volume_db = 0.0 if i == 0 else -60.0
		if p2.stream != null:
			p2.play(0.0)

func _stop_stems() -> void:
	for p in _stems:
		p.stop()

## 0 calm → 3 celebration. Changes apply on the next bar boundary after a
## 16-second minimum dwell (§18.2).
func set_intensity(level: int) -> void:
	level = clampi(level, 0, 3)
	if level == _intensity:
		_pending_intensity = -1
		return
	_pending_intensity = level

func set_paused_filter(on: bool) -> void:
	if not enabled:
		return
	AudioServer.set_bus_effect_enabled(AudioServer.get_bus_index("Music"), 0, on)

func _process(dt: float) -> void:
	if not enabled:
		return
	_time += dt
	_duck = move_toward(_duck, _duck_target, dt / (0.2 if _duck_target > _duck else 0.5))
	var duck_db := -3.0 * _duck
	if _pending_intensity != -1 and _time - _intensity_since >= 16.0:
		var p0: AudioStreamPlayer = _stems[0]
		var pos := p0.get_playback_position() if p0.playing else 0.0
		var into_bar := fmod(pos, BAR_S)
		if into_bar < dt * 1.5 or BAR_S - into_bar < dt:
			_intensity = _pending_intensity
			_pending_intensity = -1
			_intensity_since = _time
			_stem_target = [1.0, 1.0 if _intensity >= 1 else 0.0, 1.0 if _intensity >= 2 else 0.0, 1.0 if _intensity >= 3 else 0.0]
	for i in 4:
		var p: AudioStreamPlayer = _stems[i]
		if p.stream == null:
			continue
		var cur := db_to_linear(p.volume_db - duck_db) if p.volume_db > -59.0 else 0.0
		var tgt: float = _stem_target[i]
		if Settings.g("difficulty") == "cozy" and i == 2:
			tgt *= 0.5
		cur = move_toward(cur, tgt, dt / 1.5)
		p.volume_db = (linear_to_db(maxf(cur, 0.0001)) if cur > 0.001 else -60.0) + duck_db
	if _music_player.playing:
		_music_player.volume_db = duck_db
