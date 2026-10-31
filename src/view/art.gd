class_name Art
extends RefCounted
## Palette (§17.1), shared materials and procedural pixel textures.

const CREAM := Color("#F7EAD6")
const WALNUT := Color("#805C49")
const CORAL := Color("#E88D79")
const SAGE := Color("#8BAE91")
const SKY := Color("#8EBBC7")
const PLUM := Color("#8C7CA8")
const INK := Color("#33434B")
const GOLD := Color("#E8BF66")
const BRASS := Color("#D9A441")
const WHITE := Color("#FFF9F0")
const LEAF := Color("#6F9B5F")
const ROSE := Color("#F2A7B5")
const STONE := Color("#A7A3A9")

# Semantic colours (always paired with shapes, §11.1).
const WARM := Color("#E88D79")
const COLD := Color("#8EBBC7")
const QUIET := Color("#8C7CA8")
const SOUND := Color("#E8BF66")
const WATER := Color("#7FB2A0")
const CLEAN := Color("#F7EAD6")

const ROOM_COLORS := {"A": Color("#E88D79"), "B": Color("#8EBBC7"), "C": Color("#E8BF66"),
	"D": Color("#8BAE91"), "E": Color("#8C7CA8"), "F": Color("#D98BB0")}
const FAMILY_COLORS := {"slime": Color("#7FCFAE"), "yeti": Color("#DDEBF2"), "dragon": Color("#E9805E"),
	"ghost": Color("#F4F1FA"), "moonwolf": Color("#9C8FC0"), "sprout": Color("#86B86A")}

const TOON := preload("res://src/view/shaders/toon.gdshader")
const HULL := preload("res://src/view/shaders/highlight_hull.gdshader")
const FX := preload("res://src/view/shaders/fx_dither.gdshader")

static var _cache: Dictionary = {}

static func toon(tint: Color = Color.WHITE) -> ShaderMaterial:
	var k := "toon_" + tint.to_html()
	if not _cache.has(k):
		var m := ShaderMaterial.new()
		m.shader = TOON
		m.set_shader_parameter("tint", tint)
		_cache[k] = m
	return _cache[k]

static func toon_unique(tint: Color = Color.WHITE) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = TOON
	m.set_shader_parameter("tint", tint)
	return m

static func toon_tex(key: String, tex: Texture2D, mode: float, scale: float, tint := Color.WHITE) -> ShaderMaterial:
	var k := "tex_" + key
	if not _cache.has(k):
		var m := ShaderMaterial.new()
		m.shader = TOON
		m.set_shader_parameter("tint", tint)
		m.set_shader_parameter("tex", tex)
		m.set_shader_parameter("use_tex", mode)
		m.set_shader_parameter("tex_scale", scale)
		_cache[k] = m
	return _cache[k]

static func hull(col: Color, width := 0.045) -> ShaderMaterial:
	var k := "hull_%s_%.3f" % [col.to_html(), width]
	if not _cache.has(k):
		var m := ShaderMaterial.new()
		m.shader = HULL
		m.set_shader_parameter("color", col)
		m.set_shader_parameter("width", width)
		_cache[k] = m
	return _cache[k]

static func fx(col: Color, alpha := 1.0, soft := false) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = FX
	m.set_shader_parameter("color", col)
	m.set_shader_parameter("alpha", alpha)
	m.set_shader_parameter("soft_edge", 1.0 if soft else 0.0)
	return m

static func mesh_instance(mesh: Mesh, mat: Material = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat if mat != null else toon()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return mi

# ------------------------------------------------------------ pixel textures

static func _img(w: int, h: int, c: Color) -> Image:
	var im := Image.create(w, h, false, Image.FORMAT_RGBA8)
	im.fill(c)
	return im

static func _tex(im: Image) -> ImageTexture:
	return ImageTexture.create_from_image(im)

static func _hash(x: int, y: int, s: int) -> float:
	var h := (x * 374761393 + y * 668265263 + s * 2147483647) & 0x7FFFFFFF
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7FFFFFFF
	return float(h & 0xFFFF) / 65535.0

## Wood planks: 64x64 px covering 4x4 m (16 px/m), multiply-blend texture.
static func planks(seed_v := 1) -> ImageTexture:
	var k := "planks_%d" % seed_v
	if _cache.has(k):
		return _cache[k]
	var im := _img(64, 64, Color(1, 1, 1))
	for y in 64:
		var row := y / 8
		var offset := (row * 23) % 64
		for x in 64:
			var v := 0.94 + 0.06 * _hash((x + offset) / 16, row, seed_v)
			if y % 8 == 0:
				v = 0.72
			elif (x + offset) % 32 == 0:
				v = 0.78
			elif _hash(x, y, seed_v + 7) > 0.985:
				v -= 0.08
			elif y % 8 == 1:
				v += 0.05
			im.set_pixel(x, y, Color(v, v * 0.98, v * 0.96))
	var t := _tex(im)
	_cache[k] = t
	return t

## Patterned rug: a quiet 1 m diamond lattice (a busy 0.5 m pattern at full
## contrast read as noise around 7-pixel-tall characters); multiply texture.
static func rug(seed_v := 1) -> ImageTexture:
	var k := "rug_%d" % seed_v
	if _cache.has(k):
		return _cache[k]
	var im := _img(32, 32, Color(1, 1, 1))
	for y in 32:
		for x in 32:
			var cx := (x % 16) - 7.5
			var cy := (y % 16) - 7.5
			var d := absf(cx) + absf(cy)
			var v := 1.0
			if d < 1.6:
				v = 0.9
			elif d > 6.8 and d < 8.2:
				v = 0.94
			if x == 0 or y == 0:
				v = 0.9
			im.set_pixel(x, y, Color(v, v, v))
	var t := _tex(im)
	_cache[k] = t
	return t

## Wallpaper: soft stripes with a small motif every 8 px.
static func wallpaper(seed_v := 1) -> ImageTexture:
	var k := "wall_%d" % seed_v
	if _cache.has(k):
		return _cache[k]
	var im := _img(32, 32, Color(1, 1, 1))
	for y in 32:
		for x in 32:
			var v := 1.0
			if x % 8 < 2:
				v = 0.93
			if (x % 16 == 11 and y % 12 == 5) or (x % 16 == 11 and y % 12 == 6) or (x % 16 == 10 and y % 12 == 6) or (x % 16 == 12 and y % 12 == 6):
				v = 0.82
			if y >= 26:
				v = 0.8 if y == 26 else 0.88
			im.set_pixel(x, y, Color(v, v, v))
	var t := _tex(im)
	_cache[k] = t
	return t

## Soft pixel grass with sparse tufts and flowers.
static func grass(seed_v := 1) -> ImageTexture:
	var k := "grass_%d" % seed_v
	if _cache.has(k):
		return _cache[k]
	var im := _img(64, 64, Color(1, 1, 1))
	for y in 64:
		for x in 64:
			var h := _hash(x, y, seed_v)
			var v := 0.97 + 0.03 * _hash(x / 4, y / 4, seed_v + 3)
			var c := Color(v, v, v)
			if h > 0.965:
				c = Color(0.86, 0.93, 0.84)
			elif h < 0.02:
				c = Color(0.82, 0.88, 0.8)
			elif h > 0.9985:
				c = Color(1.25, 1.1, 1.15)
			im.set_pixel(x, y, c)
	var t := _tex(im)
	_cache[k] = t
	return t

## Stone tiles for the conservatory.
static func tiles(seed_v := 1) -> ImageTexture:
	var k := "tiles_%d" % seed_v
	if _cache.has(k):
		return _cache[k]
	var im := _img(32, 32, Color(1, 1, 1))
	for y in 32:
		for x in 32:
			var v := 0.95 + 0.05 * _hash(x / 8, y / 8, seed_v)
			if (x / 8 + y / 8) % 2 == 0:
				v -= 0.06
			if x % 8 == 0 or y % 8 == 0:
				v = 0.74
			im.set_pixel(x, y, Color(v, v, v))
	var t := _tex(im)
	_cache[k] = t
	return t

static func lerp_col(a: Color, b: Color, t: float) -> Color:
	return a.lerp(b, t)
