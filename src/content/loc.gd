extends Node
## Localization (§21.5). English source lives in data/localization/en.json as
## flat keys (ui.*, guest.*, story.*, level.Lxx.*, item.*, ribbon.*). Supports
## {var} substitution, plural forms ({"one": "...", "other": "..."}) and a
## pseudo-localization mode (+40% length, accents) for layout testing.

var strings: Dictionary = {}
var locale := "en"
var pseudo := false
var missing: Dictionary = {}

func _ready() -> void:
	load_locale("en")

func load_locale(code: String) -> void:
	locale = code
	strings.clear()
	var path := "res://data/localization/%s.json" % code
	if not FileAccess.file_exists(path):
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	if d is Dictionary:
		_flatten("", d, strings)

func _flatten(prefix: String, d: Dictionary, out: Dictionary) -> void:
	for k in d:
		var key: String = k if prefix == "" else prefix + "." + k
		var v = d[k]
		if v is Dictionary and not (v.has("one") or v.has("other")):
			_flatten(key, v, out)
		else:
			out[key] = v

func has(key: String) -> bool:
	return strings.has(key)

func t(key: String, vars: Dictionary = {}) -> String:
	var v = strings.get(key, null)
	if v == null:
		missing[key] = true
		return key if OS.is_debug_build() else key.get_slice(".", key.get_slice_count(".") - 1).capitalize()
	var s: String
	if v is Dictionary:
		var n := int(vars.get("n", vars.get("count", 0)))
		s = v.get("one", v.get("other", "")) if n == 1 else v.get("other", v.get("one", ""))
	else:
		s = str(v)
	for k in vars:
		s = s.replace("{" + str(k) + "}", str(vars[k]))
	if pseudo:
		s = _pseudo(s)
	return s

func _pseudo(s: String) -> String:
	var map := {"a": "á", "e": "é", "i": "í", "o": "ö", "u": "ü", "A": "Å", "E": "É", "O": "Ø", "c": "ç", "n": "ñ"}
	var out := ""
	var in_brace := false
	for ch in s:
		if ch == "{": in_brace = true
		if ch == "}": in_brace = false
		out += ch if in_brace else map.get(ch, ch)
	var pad := int(ceil(s.length() * 0.4))
	return "⟦" + out + " " + "~".repeat(maxi(1, pad - 3)) + "⟧"

func missing_keys() -> PackedStringArray:
	return PackedStringArray(missing.keys())
