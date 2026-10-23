class_name Icons
extends RefCounted
## Original pixel-art icon set (§11.1, §17.3) built at runtime from the
## hand-editable text sources in data/art/icons/*.txt. The format is documented
## at the top of data/art/icons/palette.txt; tools/icons/icontext.py is the
## matching Python parser used by the contact-sheet preview.
##
##   Icons.tex("sys_warm")                    -> Texture2D, default palette
##   Icons.tinted("sys_warm", "tritanopia")   -> colour-vision variant
##   Icons.has("sys_warm"), Icons.names()
##   Icons.style_box("panel_cream")           -> 9-slice StyleBoxTexture
##
## Textures are cached ImageTextures with a transparent background and no
## mipmaps. Draw them at integer scale with nearest filtering (the project's
## default canvas texture filter). Unknown names return a visible
## question-mark tile; nothing here ever errors or returns null.
##
## Exported builds: the .txt sources are not Godot resources, so the export
## preset must list "data/art/icons/*.txt" in its non-resource include filter.

const DIR := "res://data/art/icons/"
const PALETTE_FILE := "palette.txt"
## Used when the directory cannot be listed (e.g. an unusual export layout).
const SOURCE_FILES: PackedStringArray = [
	"palette.txt", "families.txt", "guests.txt", "staff.txt", "items.txt",
	"systems.txt", "actions.txt", "ui.txt", "badges.txt",
]
const VARIANTS: PackedStringArray = [
	"default", "deuteranopia", "protanopia", "tritanopia", "high_contrast",
]

## 9-slice margins in source pixels (same on all four sides). Every corner and
## border pixel lies inside this margin, so StyleBoxTexture / NinePatchRect can
## stretch the centre and edges freely. Scale the box with integer
## expand margins or a CanvasItem scale; never filter.
const NINE_SLICE := {
	"panel_cream": 8,   # rounded cream panel, walnut 2-px border, inner highlight
	"panel_ink": 8,     # dark ink panel, cream border
	"panel_card": 8,    # white card with coral top band (band sits in top margin)
	"button_idle": 8,   # cream button, ink outline, walnut lip at the bottom
	"button_focus": 8,  # same body with a 2-px gold focus glow
	"bubble": 8,        # speech-bubble body, corners 8 (tail drawn separately)
}

## Alternate ids found in data files and the §7.2 item ids -> canonical names.
const ALIASES := {
	"sys_note": "sys_noise",
	"towel": "item_towel",
	"move_room": "item_move_ticket",
	"lantern": "sys_festival",
	"festival": "sys_festival",
	"ticket": "item_ticket",
	"move_ticket": "item_move_ticket",
	"linen_clean": "item_linen_clean",
	"linen_dirty": "item_linen_dirty",
	"snack": "item_snack",
	"welcome_slime": "gift_slime",
	"welcome_yeti": "gift_yeti",
	"welcome_dragon": "gift_dragon",
	"welcome_ghost": "gift_ghost",
	"welcome_moonwolf": "gift_moonwolf",
	"welcome_sprout": "gift_sprout",
	"curtain_roll": "item_curtain",
	"mop": "tool_mop",
	"watering_can": "tool_can",
	"breezer": "tool_breezer",
	"festival_trunk": "item_trunk",
	"festival_parcel": "item_parcel",
	"staff_assist": "sys_assist",
	"gus": "npc_gus",
	"nana": "npc_nana",
	"dot": "npc_dot",
}

# Built-in question-mark tile, independent of the source files.
const _FALLBACK_ROWS: PackedStringArray = [
	"................",
	"..kkkkkkkkkkkk..",
	".kcccccccccccck.",
	".kcccckkkkcccck.",
	".kccckkcckkccck.",
	".kccccccckkccck.",
	".kcccccckkcccck.",
	".kccccckkccccck.",
	".kccccckkccccck.",
	".kcccccccccccck.",
	".kccccckkccccck.",
	".kccccckkccccck.",
	".kcccccccccccck.",
	".kcccccccccccck.",
	"..kkkkkkkkkkkk..",
	"................",
]
const _FALLBACK_KEYS := {"k": "#33434B", "c": "#F7EAD6"}

static var _loaded := false
static var _palette: Dictionary = {}    # key char -> "#RRGGBB" ("" = transparent)
static var _icons: Dictionary = {}      # name -> {w, h, rows, keys, file}
static var _variants: Dictionary = {}   # variant -> {"#RRGGBB": Color}
static var _tex_cache: Dictionary = {}  # "variant/name" -> Texture2D
static var _errors: PackedStringArray = []


# ------------------------------------------------------------------ public API

## Texture for `name` in the default palette (fallback tile if unknown).
static func tex(name: String) -> Texture2D:
	return tinted(name, "default")


## Texture for `name` with a colour-vision palette variant applied:
## "default", "deuteranopia", "protanopia", "tritanopia" or "high_contrast".
## Unknown variants fall back to "default"; unknown names to the fallback tile.
static func tinted(name: String, palette_variant: String) -> Texture2D:
	_ensure_loaded()
	var v := palette_variant if _variants.has(palette_variant) else "default"
	var id := _resolve(name)
	var key := v + "/" + (id if id != "" else "__fallback__")
	if _tex_cache.has(key):
		return _tex_cache[key]
	var t := ImageTexture.create_from_image(image(id, v) if id != "" else _fallback_image())
	_tex_cache[key] = t
	return t


## True when `name` (or one of its aliases) is a defined icon.
static func has(name: String) -> bool:
	_ensure_loaded()
	return _resolve(name) != ""


## Every canonical icon name, sorted.
static func names() -> PackedStringArray:
	_ensure_loaded()
	var out := PackedStringArray(_icons.keys())
	out.sort()
	return out


## Pixel size of an icon (16x16 for unknown names, matching the fallback).
static func size_of(name: String) -> Vector2i:
	_ensure_loaded()
	var id := _resolve(name)
	if id == "":
		return Vector2i(16, 16)
	var d: Dictionary = _icons[id]
	return Vector2i(int(d["w"]), int(d["h"]))


## A fresh RGBA8 Image of the icon (fallback tile if unknown). Useful for atlases.
static func image(name: String, palette_variant: String = "default") -> Image:
	_ensure_loaded()
	var id := _resolve(name)
	if id == "":
		return _fallback_image()
	var d: Dictionary = _icons[id]
	var w := int(d["w"])
	var h := int(d["h"])
	var rows: PackedStringArray = d["rows"]
	var table := _colour_table(d, palette_variant)
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in h:
		var row: String = rows[y]
		for x in w:
			var ch := row[x]
			if ch == ".":
				continue
			if table.has(ch):
				img.set_pixel(x, y, table[ch])
	return img


## 9-slice StyleBoxTexture for a panel source listed in NINE_SLICE.
static func style_box(name: String, palette_variant: String = "default") -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = tinted(name, palette_variant)
	var m := float(NINE_SLICE.get(name, 8))
	sb.texture_margin_left = m
	sb.texture_margin_top = m
	sb.texture_margin_right = m
	sb.texture_margin_bottom = m
	sb.content_margin_left = m
	sb.content_margin_top = m
	sb.content_margin_right = m
	sb.content_margin_bottom = m
	return sb


## Parse problems found while loading (empty when the sources are clean).
static func errors() -> PackedStringArray:
	_ensure_loaded()
	return _errors


## Drop every cache and re-read the sources (editor hot-reload, tests).
static func reload() -> void:
	_loaded = false
	_palette.clear()
	_icons.clear()
	_variants.clear()
	_tex_cache.clear()
	_errors.clear()
	_ensure_loaded()


# ------------------------------------------------------------------ internals

static func _resolve(name: String) -> String:
	if _icons.has(name):
		return name
	if ALIASES.has(name) and _icons.has(String(ALIASES[name])):
		return String(ALIASES[name])
	return ""


static func _colour_table(d: Dictionary, palette_variant: String) -> Dictionary:
	var remap: Dictionary = _variants.get(palette_variant, {})
	var table := {}
	var keys: Dictionary = d["keys"]
	for src in [_palette, keys]:
		var dict: Dictionary = src
		for k in dict:
			var hex: String = dict[k]
			if hex == "":
				table[k] = Color(0, 0, 0, 0)
				continue
			var c := Color.html(hex)
			var base := hex.substr(0, 7).to_upper()
			if remap.has(base):
				var m: Color = remap[base]
				c = Color(m.r, m.g, m.b, c.a)
			table[k] = c
	return table


static func _fallback_image() -> Image:
	var img := Image.create_empty(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in 16:
		var row: String = _FALLBACK_ROWS[y]
		for x in 16:
			var ch := row[x]
			if _FALLBACK_KEYS.has(ch):
				img.set_pixel(x, y, Color.html(String(_FALLBACK_KEYS[ch])))
	return img


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_variants["default"] = {}
	var files := _source_files()
	for f in files:
		var path := DIR + f
		if FileAccess.file_exists(path):
			_parse(f, FileAccess.get_file_as_string(path))
	for id in _icons:
		var d: Dictionary = _icons[id]
		var keys: Dictionary = d["keys"]
		for row in (d["rows"] as PackedStringArray):
			for i in row.length():
				var ch := row[i]
				if ch != "." and not keys.has(ch) and not _palette.has(ch):
					_errors.append("%s: unknown key '%s'" % [id, ch])
					keys[ch] = ""


static func _source_files() -> PackedStringArray:
	var found := PackedStringArray()
	for f in DirAccess.get_files_at(DIR):
		if f.ends_with(".txt") and f != PALETTE_FILE:
			found.append(f)
	if found.is_empty():
		for f in SOURCE_FILES:
			if f != PALETTE_FILE:
				found.append(f)
	found.sort()
	found.insert(0, PALETTE_FILE)
	return found


static func _is_colour(tok: String) -> bool:
	if tok == "transparent":
		return true
	if not tok.begins_with("#") or (tok.length() != 7 and tok.length() != 9):
		return false
	return tok.substr(1).is_valid_hex_number(false)


static func _norm(tok: String) -> String:
	return "" if tok == "transparent" else tok.to_upper()


static func _parse(file: String, text: String) -> void:
	var mode := ""
	var cur := {}
	var vmap := {}
	var ln := 0
	for raw in text.split("\n"):
		ln += 1
		var line := raw.replace("\t", " ").strip_edges()
		if line == "" or line == "#" or line.begins_with("# "):
			continue
		var toks := line.split(" ", false)
		if mode == "":
			if toks[0] == "palette":
				mode = "palette"
			elif toks[0] == "variant" and toks.size() >= 2:
				mode = "variant"
				if not _variants.has(toks[1]):
					_variants[toks[1]] = {}
				vmap = _variants[toks[1]]
			elif toks[0] == "icon" and toks.size() >= 3:
				var dims := toks[2].to_lower().split("x")
				var w := dims[0].to_int()
				var h := dims[1].to_int() if dims.size() > 1 else w
				cur = {"name": toks[1], "w": w, "h": h, "rows": PackedStringArray(),
					"keys": {}, "file": file, "line": ln}
				mode = "icon"
			else:
				_errors.append("%s:%d: unexpected line" % [file, ln])
			continue
		if toks[0] == "end" and toks.size() == 1:
			if mode == "icon":
				_finish_icon(cur)
			mode = ""
			continue
		match mode:
			"palette":
				if toks.size() >= 2 and toks[0].length() == 1 and _is_colour(toks[1]):
					_palette[toks[0]] = _norm(toks[1])
				else:
					_errors.append("%s:%d: bad palette entry" % [file, ln])
			"variant":
				if toks.size() >= 2 and _is_colour(toks[0]) and _is_colour(toks[1]):
					vmap[toks[0].substr(0, 7).to_upper()] = Color.html(toks[1])
				else:
					_errors.append("%s:%d: bad variant entry" % [file, ln])
			"icon":
				var rows: PackedStringArray = cur["rows"]
				if rows.is_empty() and toks.size() >= 2 and toks[0].length() == 1 and _is_colour(toks[1]):
					var keys: Dictionary = cur["keys"]
					keys[toks[0]] = _norm(toks[1])
				else:
					rows.append(line)
					cur["rows"] = rows
	if mode != "":
		_errors.append("%s: missing 'end' for final %s block" % [file, mode])


static func _finish_icon(d: Dictionary) -> void:
	var id: String = d["name"]
	var w := int(d["w"])
	var h := int(d["h"])
	var rows: PackedStringArray = d["rows"]
	var where := "%s:%d" % [d["file"], d["line"]]
	if w <= 0 or rows.size() != h:
		_errors.append("%s: %s has %d rows, expected %d" % [where, id, rows.size(), h])
		return
	for r in rows:
		if r.length() != w:
			_errors.append("%s: %s has a row of %d columns, expected %d" % [where, id, r.length(), w])
			return
	if _icons.has(id):
		_errors.append("%s: duplicate icon %s" % [where, id])
		return
	_icons[id] = d
