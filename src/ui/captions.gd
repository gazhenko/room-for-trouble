class_name Captions
extends Control
## Captions with speaker names (§11.3, §15.3). Priority: teaching > critical >
## warning > ping > story > bark. At most two lines; low-priority lines wait up
## to 3 s, then drop rather than flood the screen. Squeak/warble voices play
## through Audio.babble; captions always carry the meaning.

const PRIO := {"teaching": 6, "critical": 5, "warning": 4, "ping": 3, "story": 2, "bark": 1}

var lines: Array = []    # [{speaker, text, prio, t, life}]
var queue: Array = []
var recent: Dictionary = {}   # bark key -> time used
var _t := 0.0
var bottom_offset := 70.0

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func push(speaker: String, text: String, prio := "bark", secs := -1.0) -> void:
	if text == "":
		return
	var p: int = PRIO.get(prio, 1)
	var life := secs if secs > 0 else maxf(2.0, 0.055 * text.length() + 0.8)
	var entry := {"speaker": speaker, "text": text, "prio": p, "t": 0.0, "life": life, "queued_at": _t}
	if lines.size() < 2:
		_show(entry)
		return
	# Replace the lowest-priority visible line if this one matters more.
	var lowest := 0
	for i in lines.size():
		if lines[i]["prio"] < lines[lowest]["prio"]:
			lowest = i
	if lines[lowest]["prio"] < p:
		lines.remove_at(lowest)
		_show(entry)
	else:
		queue.append(entry)

func _show(entry: Dictionary) -> void:
	lines.append(entry)
	if Settings.g("captions") or entry["prio"] >= PRIO["warning"]:
		pass
	Audio.babble(entry["speaker"], entry["text"])

## Deterministic-ish bark selection without repeats inside 60 s.
func bark(key: String, speaker := "nana", vars := {}) -> void:
	var variants: Array = []
	for i in range(1, 6):
		var k := "%s.%d" % [key, i]
		if Loc.has(k):
			variants.append(k)
	if variants.is_empty():
		if Loc.has(key):
			variants.append(key)
		else:
			return
	var pick := ""
	for v in variants:
		if _t - float(recent.get(v, -999.0)) >= 60.0:
			pick = v
			break
	if pick == "":
		return
	recent[pick] = _t
	push(speaker, Loc.t(pick, vars), "bark")

func clear() -> void:
	lines.clear()
	queue.clear()

func _process(dt: float) -> void:
	_t += dt
	for l in lines:
		l["t"] += dt
	lines = lines.filter(func(l): return l["t"] < l["life"])
	queue = queue.filter(func(q): return _t - float(q["queued_at"]) < 3.0)
	while lines.size() < 2 and not queue.is_empty():
		queue.sort_custom(func(a, b): return a["prio"] > b["prio"])
		_show(queue.pop_front())
	queue_redraw()

func _draw() -> void:
	if lines.is_empty():
		return
	if not Settings.g("captions"):
		# Captions are optional, but warnings and teaching still show.
		var keep := lines.filter(func(l): return l["prio"] >= PRIO["warning"])
		if keep.is_empty():
			return
	var f := UiKit.font()
	var fs := 20 if not Settings.g("large_requests") else 24
	var y := size.y - bottom_offset
	for i in range(lines.size() - 1, -1, -1):
		var l: Dictionary = lines[i]
		if not Settings.g("captions") and l["prio"] < PRIO["warning"]:
			continue
		var name := Loc.t("cast." + l["speaker"]) if Settings.g("speaker_names") and l["speaker"] != "" else ""
		var text: String = l["text"]
		var full := (name + ":  " if name != "" else "") + text
		var w := minf(f.get_string_size(full, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 36, size.x - 80)
		var r := Rect2(Vector2(size.x * 0.5 - w * 0.5, y - 34), Vector2(w, 34))
		draw_style_box(UiKit.panel_style("ink"), r)
		var x := r.position.x + 18
		if name != "":
			draw_string(f, Vector2(x, y - 10), name + ":", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiKit.GOLD)
			x += f.get_string_size(name + ":  ", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(f, Vector2(x, y - 10), text, HORIZONTAL_ALIGNMENT_LEFT, r.end.x - x - 12, fs, UiKit.CREAM)
		y -= 40
