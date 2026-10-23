class_name ModelItems
extends RefCounted
## Procedural carryable items (§7.2, §17.3) and the shared low-poly shape
## helpers (stars, crescents, motifs, open tubes) that ModelStations and
## ModelProps reuse. Items are in true metres with the origin at bottom centre
## and the front toward +z; each reads both lying on the floor and held aloft.
## Meshes are cached per kind/variant so every instance shares one ArrayMesh.

const KINDS := ["ticket", "move_ticket", "linen_clean", "linen_dirty", "towel", "snack",
	"welcome_slime", "welcome_yeti", "welcome_dragon", "welcome_ghost", "welcome_moonwolf",
	"welcome_sprout", "curtain_roll", "mop", "watering_can", "breezer", "festival_trunk",
	"festival_parcel"]
const FAMILIES := ["slime", "yeti", "dragon", "ghost", "moonwolf", "sprout"]

const PAPER := Color("#FBF1DF")
const DIRTY := Color("#E6D5B0")
const SLIPPER := Color("#F27FAE")
const TRUNK_BLUE := Color("#5B8CC9")
const NAVY := Color("#46558A")
const SOIL := Color("#86654B")
const GLASS := Color("#6E9FB4")
const WICKER := Color("#D1A66B")
const EYE_WHITE := Color("#FFFDF6")

static var _meshes: Dictionary = {}
static var _mats: Dictionary = {}

static func kinds() -> PackedStringArray:
	return PackedStringArray(KINDS)

# ================================================================ caches

## Builds `fn(mk)` once and shares the committed mesh under `key`.
static func cached(key: String, fn: Callable) -> ArrayMesh:
	var m: ArrayMesh = _meshes.get(key)
	if m == null:
		var mk := MeshKit.new()
		fn.call(mk)
		m = mk.commit()
		_meshes[key] = m
	return m

## Shared unshaded vertex-colour material for lit lamps, glows and pads.
static func lit_mat() -> ShaderMaterial:
	if not _mats.has("lit"):
		var m := ShaderMaterial.new()
		m.shader = Art.FX
		m.set_shader_parameter("color", Color.WHITE)
		m.set_shader_parameter("alpha", 1.0)
		_mats["lit"] = m
	return _mats["lit"]

## Shared dithered translucent vertex-colour material (steam puffs, glints).
static func haze_mat(alpha := 0.55) -> ShaderMaterial:
	var k := "haze_%.2f" % alpha
	if not _mats.has(k):
		var m := ShaderMaterial.new()
		m.shader = Art.FX
		m.set_shader_parameter("color", Color.WHITE)
		m.set_shader_parameter("alpha", alpha)
		_mats[k] = m
	return _mats[k]

## Shared darkened toon material for "off" lamps and dimmed parts.
static func dim_mat() -> ShaderMaterial:
	return Art.toon(Color(0.62, 0.6, 0.68))

static func mesh_node(mesh: Mesh, name_s: String, mat: Material = null) -> MeshInstance3D:
	var mi := Art.mesh_instance(mesh, mat if mat != null else Art.toon())
	mi.name = name_s
	return mi

# ================================================================ shapes

static func circle_pts(r: float, seg := 10, sx := 1.0, sy := 1.0) -> Array:
	var pts: Array = []
	for i in seg:
		var a := TAU * i / seg
		pts.append(Vector2(cos(a) * r * sx, sin(a) * r * sy))
	return pts

static func star_pts(n: int, r_out: float, r_in: float, rot_deg := 90.0) -> Array:
	var pts: Array = []
	for i in n * 2:
		var a := deg_to_rad(rot_deg) + PI * i / n
		var r := r_out if i % 2 == 0 else r_in
		pts.append(Vector2(cos(a) * r, sin(a) * r))
	return pts

## Drop/flame outline, point toward +y, overall height ~2.1 r.
static func teardrop_pts(r: float, seg := 8, tip := 2.0) -> Array:
	var pts: Array = []
	var g := rad_to_deg(acos(1.0 / maxf(tip, 1.05)))
	var a0 := 90.0 - g
	var span := 360.0 - 2.0 * g
	for i in seg + 1:
		var a := deg_to_rad(a0 - span * float(i) / seg)
		pts.append(Vector2(cos(a) * r, sin(a) * r))
	pts.append(Vector2(0, r * tip))
	return pts

## Lens-shaped leaf outline along +y from (0,0) to (0,len).
static func leaf_pts(length: float, w: float, seg := 4) -> Array:
	var pts: Array = []
	for i in seg + 1:
		var t := float(i) / seg
		pts.append(Vector2(sin(t * PI) * w * 0.5, t * length))
	for i in range(seg - 1, 0, -1):
		var t2 := float(i) / seg
		pts.append(Vector2(-sin(t2 * PI) * w * 0.5, t2 * length))
	return pts

## Arrow outline pointing +x, tip at x = len/2 (fan centre is returned in [1]).
static func arrow_pts(length: float, shaft: float, head_w: float, head_len: float) -> Array:
	var x0 := -length * 0.5
	var hb := length * 0.5 - head_len
	return [Vector2(x0, -shaft * 0.5), Vector2(hb, -shaft * 0.5), Vector2(hb, -head_w * 0.5),
		Vector2(length * 0.5, 0), Vector2(hb, head_w * 0.5), Vector2(hb, shaft * 0.5), Vector2(x0, shaft * 0.5)]

static func _ccw(pts: Array) -> Array:
	var area := 0.0
	var n := pts.size()
	for i in n:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[(i + 1) % n]
		area += a.x * b.y - b.x * a.y
	if area < 0.0:
		var r := pts.duplicate()
		r.reverse()
		return r
	return pts

## Extruded polygon in the local XY plane with its face toward +z. The outline
## must be star-shaped around `center` (default: the vertex average).
static func poly_xy(mk: MeshKit, pts_in: Array, depth: float, col: Color, front_col = null, center = null) -> void:
	var pts := _ccw(pts_in)
	var n := pts.size()
	var c := Vector2.ZERO
	if center == null:
		for p in pts:
			c += p
		c /= float(n)
	else:
		c = center
	var fc: Color = col if front_col == null else front_col
	var zf := depth * 0.5
	var zb := -depth * 0.5
	for i in n:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[(i + 1) % n]
		mk.tri(Vector3(c.x, c.y, zf), Vector3(a.x, a.y, zf), Vector3(b.x, b.y, zf), fc)
		mk.tri(Vector3(c.x, c.y, zb), Vector3(b.x, b.y, zb), Vector3(a.x, a.y, zb), col.darkened(0.15))
		mk.quad(Vector3(a.x, a.y, zb), Vector3(b.x, b.y, zb), Vector3(b.x, b.y, zf), Vector3(a.x, a.y, zf), col)

## Same outline lying flat on XZ (face up, outline "up" toward -z), bottom at pos.y.
static func poly_flat(mk: MeshKit, pos: Vector3, pts: Array, depth: float, col: Color, front_col = null, rot_y := 0.0, center = null) -> void:
	mk.push_at(pos + Vector3(0, depth * 0.5, 0), Vector3(-90, rot_y, 0))
	poly_xy(mk, pts, depth, col, front_col, center)
	mk.pop()

## Crescent in local XY bulging toward +x, face toward +z.
static func crescent_xy(mk: MeshKit, r: float, w: float, depth: float, col: Color, front_col = null, span_deg := 115.0, seg := 10) -> void:
	var fc: Color = col if front_col == null else front_col
	var zf := depth * 0.5
	var zb := -depth * 0.5
	var outer: Array = []
	var inner: Array = []
	for i in seg + 1:
		var th := deg_to_rad(-span_deg + 2.0 * span_deg * float(i) / seg)
		var k := cos(PI * 0.5 * (th / deg_to_rad(span_deg)))
		outer.append(Vector2(cos(th), sin(th)) * r)
		inner.append(Vector2(cos(th), sin(th)) * (r - w * k) + Vector2(-w * 0.15 * k, 0))
	for i in seg:
		var o0: Vector2 = outer[i]
		var o1: Vector2 = outer[i + 1]
		var i0: Vector2 = inner[i]
		var i1: Vector2 = inner[i + 1]
		mk.quad(Vector3(i0.x, i0.y, zf), Vector3(o0.x, o0.y, zf), Vector3(o1.x, o1.y, zf), Vector3(i1.x, i1.y, zf), fc)
		mk.quad(Vector3(i1.x, i1.y, zb), Vector3(o1.x, o1.y, zb), Vector3(o0.x, o0.y, zb), Vector3(i0.x, i0.y, zb), col.darkened(0.15))
		mk.quad(Vector3(o0.x, o0.y, zb), Vector3(o1.x, o1.y, zb), Vector3(o1.x, o1.y, zf), Vector3(o0.x, o0.y, zf), col)
		mk.quad(Vector3(i1.x, i1.y, zb), Vector3(i0.x, i0.y, zb), Vector3(i0.x, i0.y, zf), Vector3(i1.x, i1.y, zf), col)

## Six-armed snowflake in local XY (three bars plus tip nubs), face toward +z.
static func snowflake_xy(mk: MeshKit, size: float, thick: float, depth: float, col: Color) -> void:
	for k in 3:
		mk.push_at(Vector3.ZERO, Vector3(0, 0, 30.0 + 60.0 * k))
		mk.box(Vector3.ZERO, Vector3(size, thick, depth), col)
		for s in [-1.0, 1.0]:
			mk.box(Vector3(s * size * 0.32, 0, 0), Vector3(thick * 0.9, thick * 2.4, depth), col)
		mk.pop()

## Eighth-note in local XY, face toward +z.
static func note_xy(mk: MeshKit, size: float, depth: float, col: Color) -> void:
	mk.push_at(Vector3(-size * 0.12, -size * 0.28, 0), Vector3(0, 0, 20))
	poly_xy(mk, circle_pts(size * 0.17, 8, 1.25, 0.95), depth, col)
	mk.pop()
	mk.box(Vector3(size * 0.06, size * 0.06, 0), Vector3(size * 0.1, size * 0.66, depth), col)
	mk.push_at(Vector3(size * 0.17, size * 0.3, 0), Vector3(0, 0, -35))
	mk.box(Vector3.ZERO, Vector3(size * 0.28, size * 0.1, depth), col)
	mk.pop()

## Round sun (eight soft rays) in local XY, face toward +z.
static func sun_xy(mk: MeshKit, size: float, depth: float, col: Color, core: Color) -> void:
	poly_xy(mk, star_pts(8, size * 0.5, size * 0.33, 0.0), depth, col)
	mk.push_at(Vector3(0, 0, depth * 0.5))
	poly_xy(mk, circle_pts(size * 0.26, 10), depth, core)
	mk.pop()

## Family motif (§1.4 shapes) centred in local XY, face toward +z.
static func motif_xy(mk: MeshKit, family: String, size: float, depth: float, col: Color) -> void:
	match family:
		"slime":
			mk.push_at(Vector3(0, -size * 0.22, 0))
			poly_xy(mk, teardrop_pts(size * 0.27, 8, 2.1), depth, col)
			mk.pop()
			mk.push_at(Vector3(-size * 0.09, -size * 0.2, depth * 0.5))
			poly_xy(mk, circle_pts(size * 0.06, 6), depth, Color("#E9FFF6"))
			mk.pop()
		"yeti":
			snowflake_xy(mk, size * 0.92, size * 0.14, depth, col)
		"dragon":
			mk.push_at(Vector3(0, -size * 0.24, 0))
			poly_xy(mk, teardrop_pts(size * 0.27, 8, 2.2), depth, col)
			mk.push_at(Vector3(0, size * 0.0, depth * 0.5))
			poly_xy(mk, teardrop_pts(size * 0.13, 6, 2.0), depth, Art.GOLD)
			mk.pop()
			mk.pop()
		"ghost":
			mk.push_at(Vector3(-size * 0.06, 0, 0), Vector3(0, 0, 160))
			crescent_xy(mk, size * 0.4, size * 0.24, depth, col)
			mk.pop()
		"moonwolf":
			note_xy(mk, size, depth, col)
		_:
			mk.box(Vector3(0, -size * 0.22, 0), Vector3(size * 0.09, size * 0.34, depth), col)
			for s in [-1.0, 1.0]:
				mk.push_at(Vector3(0, -size * 0.1, 0), Vector3(0, 0, -s * 42.0))
				poly_xy(mk, leaf_pts(size * 0.46, size * 0.24), depth, col)
				mk.pop()

## Motif colour that reads on the family's own panel colour.
static func motif_color(family: String) -> Color:
	match family:
		"slime": return Color("#2F7563")
		"yeti": return Color("#5C8FA5")
		"dragon": return Art.CREAM
		"ghost": return Color("#5A4E86")
		"moonwolf": return Art.CREAM
		_: return Art.CREAM

## Open-topped tube (basket, tin, pot, sink) with an inner wall and raised floor.
static func tube(mk: MeshKit, base: Vector3, r_bot: float, r_top: float, h: float, col: Color, inner_col: Color, seg := 10, wall := 0.02, floor_h := 0.02, rim_col = null) -> void:
	var rc: Color = col.lightened(0.12) if rim_col == null else rim_col
	var top := Vector3(0, h, 0)
	var fl := Vector3(0, floor_h, 0)
	for i in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		var c0 := Vector3(cos(a0), 0, sin(a0))
		var c1 := Vector3(cos(a1), 0, sin(a1))
		var p0 := base + c0 * r_bot
		var p1 := base + c1 * r_bot
		var q0 := base + c0 * r_top + top
		var q1 := base + c1 * r_top + top
		mk.quad(p1, p0, q0, q1, col)
		var rib := r_bot - wall
		var rit := r_top - wall
		var pi0 := base + c0 * (rib + (rit - rib) * floor_h / h) + fl
		var pi1 := base + c1 * (rib + (rit - rib) * floor_h / h) + fl
		var qi0 := base + c0 * rit + top
		var qi1 := base + c1 * rit + top
		mk.quad(qi1, qi0, pi0, pi1, inner_col)
		mk.quad(qi0, qi1, q1, q0, rc)
		mk.tri(base + fl, pi1, pi0, inner_col.darkened(0.12))
		mk.tri(base, p0, p1, col.darkened(0.2))

## Open box (bin, drawer, tray) standing on `base` with walls of `wall`.
static func open_box(mk: MeshKit, base: Vector3, size: Vector3, col: Color, inner_col: Color, wall := 0.03, floor_h := 0.03, top_col = null) -> void:
	var tc: Color = col.lightened(0.12) if top_col == null else top_col
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	var cy := base.y + size.y * 0.5
	mk.box(Vector3(base.x, base.y + floor_h * 0.5, base.z), Vector3(size.x, floor_h, size.z), col, inner_col)
	for s in [-1.0, 1.0]:
		mk.box(Vector3(base.x, cy, base.z + s * (hz - wall * 0.5)), Vector3(size.x, size.y, wall), col, tc)
		mk.box(Vector3(base.x + s * (hx - wall * 0.5), cy, base.z), Vector3(wall, size.y, size.z - wall * 2.0), col, tc)

## Flat painted eye (white, ink pupil, highlight) in local XY facing +z.
static func eye_xy(mk: MeshKit, pos: Vector3, r: float, look := Vector2.ZERO) -> void:
	mk.push_at(pos)
	poly_xy(mk, circle_pts(r, 10, 0.86, 1.0), 0.012, EYE_WHITE)
	mk.push_at(Vector3(look.x * r * 0.3, -r * 0.12 + look.y * r * 0.3, 0.008))
	poly_xy(mk, circle_pts(r * 0.58, 8, 0.9, 1.0), 0.01, Art.INK)
	mk.push_at(Vector3(r * 0.18, r * 0.2, 0.007))
	poly_xy(mk, circle_pts(r * 0.2, 6), 0.006, Color.WHITE)
	mk.pop()
	mk.pop()
	mk.pop()

## Line segment as a thin box (rails, handles, strings).
static func rod(mk: MeshKit, a: Vector3, b: Vector3, r: float, col: Color, seg := 5) -> void:
	var d := b - a
	var l := d.length()
	if l < 1e-5:
		return
	var y := d / l
	var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	var z := x.cross(y)
	mk.push(Transform3D(Basis(x, y, z), a))
	mk.cyl(Vector3.ZERO, r, l, col, seg)
	mk.pop()

# ================================================================ build

## Builds one carryable. Stateful items (watering_can, festival_trunk, breezer)
## return a StationNode whose apply() takes {"charges"}, {"open","look"}, {"active"}.
static func build(kind: String, extra: Dictionary = {}) -> Node3D:
	match kind:
		"watering_can":
			return _can_node(extra)
		"festival_trunk":
			return _trunk_node(extra)
		"breezer":
			return _breezer_node(extra)
	var root := Node3D.new()
	root.name = "Item_" + kind
	var key := "item_" + kind
	if kind == "ticket":
		key += "_" + String(extra.get("family", ""))
	elif kind == "festival_parcel":
		key += "_%d" % posmod(int(extra.get("index", 0)), 6)
	root.add_child(mesh_node(cached(key, draw.bind(kind, extra)), "Mesh"))
	return root

## Appends the static geometry of `kind` to `mk` at its current transform
## (used for stocked items on shelves and for the gallery).
static func draw(mk: MeshKit, kind: String, extra: Dictionary = {}) -> void:
	match kind:
		"ticket":
			var fam := String(extra.get("family", ""))
			ticket(mk, Art.FAMILY_COLORS.get(fam, Art.CORAL))
		"move_ticket": _move_ticket(mk)
		"linen_clean": linen_stack(mk, Vector3(0.32, 0.15, 0.25), 3)
		"linen_dirty": dirty_bundle(mk, 1.0)
		"towel": towel_fold(mk, Vector3(0.3, 0.11, 0.23))
		"snack": _snack(mk)
		"welcome_slime": _slippers(mk)
		"welcome_yeti": _yeti_pillow(mk)
		"welcome_dragon": _dragon_cushion(mk)
		"welcome_ghost": _ghost_mask(mk)
		"welcome_moonwolf": _moon_blanket(mk)
		"welcome_sprout": _sprout_pot(mk)
		"curtain_roll": curtain_roll(mk, 0.38)
		"mop": _mop(mk)
		"watering_can":
			_can_body(mk)
			_can_water(mk)
			_can_drops(mk, 3)
		"breezer":
			_breezer_base(mk)
			_breezer_blades(mk)
		"festival_trunk":
			trunk(mk, false)
		"festival_parcel": parcel(mk, int(extra.get("index", 0)))
		_:
			mk.box(Vector3(0, 0.1, 0), Vector3(0.2, 0.2, 0.2), Art.ROSE)

# ---------------------------------------------------------------- paper

## Tent-card ticket: two leaning cards with a family band along the ridge.
static func ticket(mk: MeshKit, band: Color, paper := PAPER, w := 0.27, h := 0.2, foot := 0.075) -> void:
	var lean := rad_to_deg(atan2(foot, h))
	var plen := sqrt(h * h + foot * foot)
	var edge := band.darkened(0.35) if band.get_luminance() > 0.75 else band.darkened(0.18)
	for back in [false, true]:
		mk.push_at(Vector3(0, h, 0), Vector3(-lean, 180.0 if back else 0.0, 0))
		mk.box(Vector3(0, -plen * 0.5, 0), Vector3(w, plen, 0.014), paper.darkened(0.04), paper)
		var bh := plen * 0.42
		mk.box(Vector3(0, -bh * 0.5 - 0.004, 0.006), Vector3(w * 0.96, bh, 0.008), edge)
		mk.box(Vector3(0, -bh * 0.5 - 0.004, 0.009), Vector3(w * 0.86, bh - 0.03, 0.008), band, band)
		mk.pop()
	mk.box(Vector3(0, h + 0.004, 0), Vector3(w * 0.98, 0.014, 0.03), edge)

static func _move_ticket(mk: MeshKit) -> void:
	var paper := Color("#F3D373")
	var w := 0.27
	var h := 0.2
	var foot := 0.075
	var lean := rad_to_deg(atan2(foot, h))
	var plen := sqrt(h * h + foot * foot)
	for back in [false, true]:
		mk.push_at(Vector3(0, h, 0), Vector3(-lean, 180.0 if back else 0.0, 0))
		mk.box(Vector3(0, -plen * 0.5, 0), Vector3(w, plen, 0.014), paper.darkened(0.06), paper)
		mk.push_at(Vector3(0, -plen * 0.5, 0.012))
		var ap := arrow_pts(0.19, 0.05, 0.12, 0.07)
		poly_xy(mk, ap, 0.01, Art.CORAL.darkened(0.1), Art.CORAL, Vector2(0.03, 0))
		mk.pop()
		mk.pop()
	mk.box(Vector3(0, h + 0.004, 0), Vector3(w * 0.98, 0.014, 0.03), paper.darkened(0.2))
	# Tiny "Do Not Disturb" door hanger leaning on the side.
	mk.push_at(Vector3(0.19, 0.0, 0.02), Vector3(-12, -20, 0))
	mk.box(Vector3(0, 0.075, 0), Vector3(0.09, 0.15, 0.014), Art.PLUM, Art.PLUM.lightened(0.15))
	mk.push_at(Vector3(0, 0.17, 0), Vector3(90, 0, 0))
	mk.torus(Vector3.ZERO, 0.03, 0.009, Art.PLUM.darkened(0.1), 8, 3)
	mk.pop()
	mk.push_at(Vector3(0.0, 0.07, 0.009), Vector3(0, 0, 200))
	crescent_xy(mk, 0.03, 0.017, 0.006, Art.GOLD)
	mk.pop()
	mk.pop()

# ---------------------------------------------------------------- linen

## Folded clean linen: cream/white layers with a sky band over the top.
static func linen_stack(mk: MeshKit, size: Vector3, layers := 3) -> void:
	var lh := size.y / layers
	for i in layers:
		var off := 0.006 if i % 2 == 0 else -0.006
		var col := Art.WHITE if i % 2 == 0 else Art.CREAM
		mk.rbox(Vector3(off, lh * (i + 0.5), 0), Vector3(size.x, lh * 0.97, size.z), col.darkened(0.05), 0.03, Art.WHITE)
	mk.box(Vector3(0, size.y * 0.5 + 0.002, 0), Vector3(size.x * 0.27, size.y + 0.008, size.z + 0.014), Art.SKY, Art.SKY.lightened(0.15))

## Lumpy dirty bundle tied with a knot (and a friendly sock poking out).
static func dirty_bundle(mk: MeshKit, s := 1.0, sock := true) -> void:
	mk.sphere(Vector3(0, 0.1, 0) * s, 0.15 * s, DIRTY, 4, 8, Vector3(1.15, 0.7, 0.95), DIRTY.darkened(0.08))
	mk.sphere(Vector3(0.08, 0.14, 0.05) * s, 0.085 * s, DIRTY.lightened(0.06), 3, 7)
	mk.sphere(Vector3(-0.09, 0.13, -0.03) * s, 0.08 * s, DIRTY.darkened(0.04), 3, 7)
	mk.sphere(Vector3(0, 0.2, 0) * s, 0.04 * s, Art.CORAL.darkened(0.1), 2, 6)
	for e in [-1.0, 1.0]:
		mk.push_at(Vector3(e * 0.03, 0.21, 0) * s, Vector3(0, 0, -e * 50.0))
		mk.cone(Vector3.ZERO, 0.035 * s, 0.085 * s, DIRTY.darkened(0.22), 5)
		mk.pop()
	mk.torus(Vector3(0, 0.17, 0) * s, 0.045 * s, 0.014 * s, Art.CORAL.darkened(0.1), 8, 3)
	if sock:
		mk.push_at(Vector3(0.15, 0.06, 0.07) * s, Vector3(0, -25, -25))
		mk.rbox(Vector3(0.03, 0, 0) * s, Vector3(0.1, 0.05, 0.055) * s, Art.SKY, 0.02)
		mk.box(Vector3(0.075, 0, 0) * s, Vector3(0.02, 0.052, 0.057) * s, Art.WHITE)
		mk.pop()

static func towel_fold(mk: MeshKit, size: Vector3, col := Art.CORAL) -> void:
	var half := size.y * 0.5
	mk.rbox(Vector3(0, half * 0.5, 0), Vector3(size.x, half, size.z), col.darkened(0.06), 0.03, col)
	mk.rbox(Vector3(0.006, half * 1.5, -0.006), Vector3(size.x - 0.01, half, size.z - 0.014), col, 0.03, col.lightened(0.12))
	mk.push_at(Vector3(0, half, size.z * 0.5 - half * 0.6), Vector3(0, 0, 90))
	mk.cyl(Vector3(0, -size.x * 0.5, 0), half, size.x, col.lightened(0.04), 6)
	mk.pop()
	for s in [-1.0, 1.0]:
		mk.box(Vector3(s * size.x * 0.33, half, 0.003), Vector3(0.03, size.y + 0.006, size.z + 0.01), Art.CREAM)

static func star_cracker(mk: MeshKit, pos: Vector3, r: float, rot := 0.0, thick := 0.03) -> void:
	poly_flat(mk, pos, star_pts(5, r, r * 0.5), thick, Art.GOLD.darkened(0.12), Art.GOLD.lightened(0.18), rot)

static func _snack(mk: MeshKit) -> void:
	mk.cyl(Vector3.ZERO, 0.14, 0.025, Art.WHITE.darkened(0.06), 12, Art.WHITE, 0.175)
	mk.torus(Vector3(0, 0.025, 0), 0.165, 0.012, Art.SKY, 12, 4)
	star_cracker(mk, Vector3(-0.06, 0.025, 0.035), 0.075, 12.0)
	star_cracker(mk, Vector3(0.065, 0.025, 0.03), 0.075, -18.0)
	star_cracker(mk, Vector3(0.0, 0.025, -0.065), 0.075, 33.0)
	star_cracker(mk, Vector3(0.005, 0.055, 0.005), 0.075, 4.0)

# ---------------------------------------------------------------- gifts

static func _slippers(mk: MeshKit) -> void:
	for sx in [-1.0, 1.0]:
		mk.push_at(Vector3(sx * 0.08, 0, 0), Vector3(0, -sx * 9.0, 0))
		mk.rbox(Vector3(0, 0.035, 0), Vector3(0.12, 0.07, 0.25), SLIPPER.darkened(0.06), 0.05, SLIPPER.lightened(0.18))
		mk.sphere(Vector3(0, 0.06, 0.055), 0.065, SLIPPER.lightened(0.08), 3, 7, Vector3(0.95, 0.65, 1.15))
		mk.box(Vector3(0, 0.072, -0.055), Vector3(0.075, 0.006, 0.1), SLIPPER.darkened(0.35))
		mk.sphere(Vector3(0, 0.1, 0.085), 0.038, Art.WHITE, 2, 6)
		mk.pop()

static func _yeti_pillow(mk: MeshKit) -> void:
	var pc := Color("#9FC8DB")
	mk.rbox(Vector3(0, 0.04, 0), Vector3(0.32, 0.08, 0.25), pc.darkened(0.08), 0.08, pc)
	mk.sphere(Vector3(0, 0.08, 0), 0.155, pc.lightened(0.04), 3, 8, Vector3(1.0, 0.4, 0.78))
	mk.push_at(Vector3(0, 0.142, 0), Vector3(-90, 0, 0))
	snowflake_xy(mk, 0.2, 0.03, 0.014, Art.WHITE)
	mk.pop()

static func _dragon_cushion(mk: MeshKit) -> void:
	var oc := Color("#EE874D")
	mk.rbox(Vector3(0, 0.045, 0), Vector3(0.3, 0.09, 0.27), oc.darkened(0.06), 0.07, oc)
	mk.sphere(Vector3(0, 0.09, 0), 0.145, oc.lightened(0.04), 3, 8, Vector3(1.0, 0.24, 0.88))
	var embers := [[Vector3(-0.06, 0.122, -0.03), Art.GOLD], [Vector3(0.05, 0.122, 0.04), Art.GOLD],
		[Vector3(0.0, 0.124, -0.005), Color("#C9483A")], [Vector3(0.075, 0.118, -0.05), Color("#C9483A")],
		[Vector3(-0.07, 0.118, 0.055), Color("#C9483A")]]
	for e in embers:
		var p: Vector3 = e[0]
		var c: Color = e[1]
		poly_flat(mk, p, [Vector2(0.026, 0), Vector2(0, 0.034), Vector2(-0.026, 0), Vector2(0, -0.034)], 0.01, c, c.lightened(0.15), 20.0)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			mk.sphere(Vector3(sx * 0.125, 0.05, sz * 0.11), 0.022, Art.GOLD, 2, 5)

static func _ghost_mask(mk: MeshKit) -> void:
	mk.torus(Vector3(0, 0.02, -0.01), 0.14, 0.011, Color("#B9AED6"), 12, 3)
	for sx in [-1.0, 1.0]:
		mk.sphere(Vector3(sx * 0.075, 0.032, 0), 0.088, NAVY, 3, 8, Vector3(1.1, 0.36, 0.8))
		mk.push_at(Vector3(sx * 0.075, 0.064, 0.0), Vector3(-90, 0, 0))
		mk.push_at(Vector3.ZERO, Vector3(0, 0, 150))
		crescent_xy(mk, 0.042, 0.024, 0.01, Art.GOLD)
		mk.pop()
		mk.pop()
	mk.box(Vector3(0, 0.035, 0.012), Vector3(0.06, 0.04, 0.07), NAVY)

static func _moon_blanket(mk: MeshKit) -> void:
	mk.rbox(Vector3(0, 0.035, 0), Vector3(0.33, 0.07, 0.25), Art.CREAM.darkened(0.06), 0.04, Art.CREAM)
	mk.rbox(Vector3(0.006, 0.1, -0.004), Vector3(0.32, 0.06, 0.24), Art.PLUM.darkened(0.04), 0.04, Art.PLUM)
	var lav := Color("#B9AED6")
	for ix in 3:
		for iz in 2:
			var c: Color = [Art.PLUM.lightened(0.05), Art.CREAM, lav][(ix + iz * 2) % 3]
			mk.box(Vector3(-0.1 + ix * 0.1, 0.132, -0.055 + iz * 0.11), Vector3(0.094, 0.006, 0.104), c)
	mk.push_at(Vector3(0.0, 0.14, 0.0), Vector3(-90, 0, 0))
	mk.push_at(Vector3.ZERO, Vector3(0, 0, 160))
	crescent_xy(mk, 0.06, 0.034, 0.012, Art.GOLD)
	mk.pop()
	mk.pop()
	mk.push_at(Vector3(0, 0.065, 0.12), Vector3(0, 0, 90))
	mk.cyl(Vector3(0, -0.165, 0), 0.035, 0.33, Art.PLUM.lightened(0.08), 6)
	mk.pop()

static func _sprout_pot(mk: MeshKit) -> void:
	tube(mk, Vector3.ZERO, 0.075, 0.098, 0.14, Art.CREAM.darkened(0.04), SOIL, 8, 0.016, 0.11, Art.CREAM)
	mk.torus(Vector3(0, 0.085, 0), 0.09, 0.013, Art.SAGE, 8, 3)
	mk.cyl(Vector3(0, 0.1, 0), 0.013, 0.1, Art.LEAF, 5)
	for s in [-1.0, 1.0]:
		mk.push_at(Vector3(s * 0.012, 0.185, 0), Vector3(0, 0, -s * 58.0))
		mk.sphere(Vector3(0, 0.05, 0), 0.055, Art.LEAF.lightened(0.08), 2, 6, Vector3(0.62, 1.0, 0.32))
		mk.pop()
	mk.sphere(Vector3(0, 0.205, 0), 0.022, Art.LEAF.lightened(0.15), 2, 5)

## Cream acoustic curtain roll lying along x with plum end caps.
static func curtain_roll(mk: MeshKit, length: float, r := 0.075) -> void:
	mk.push_at(Vector3(0, r, 0), Vector3(0, 0, 90))
	mk.cyl(Vector3(0, -length * 0.5, 0), r, length, Art.CREAM, 8, Art.WHITE)
	for s in [-1.0, 1.0]:
		mk.cyl(Vector3(0, s * length * 0.5 - 0.015, 0), r + 0.014, 0.03, Art.PLUM, 8, Art.PLUM.lightened(0.15))
	mk.cyl(Vector3(0, -0.018, 0), r + 0.007, 0.036, Art.PLUM.lightened(0.05), 8)
	mk.pop()
	mk.box(Vector3(length * 0.25, r * 1.4, r * 0.9), Vector3(0.05, 0.03, 0.03), Art.CREAM.darkened(0.08))

# ---------------------------------------------------------------- tools

static func _mop(mk: MeshKit) -> void:
	mk.push_at(Vector3.ZERO, Vector3(0, -45, 0))
	mop_local(mk)
	mk.pop()

## Mop lying along +x (head at +x), centred on the origin.
static func mop_local(mk: MeshKit) -> void:
	var handle := Color("#C79562")
	rod(mk, Vector3(-0.5, 0.035, 0), Vector3(0.3, 0.035, 0), 0.03, handle, 6)
	mk.sphere(Vector3(-0.5, 0.035, 0), 0.04, Art.CORAL, 2, 6)
	rod(mk, Vector3(0.28, 0.035, 0), Vector3(0.34, 0.04, 0), 0.045, Art.BRASS, 6)
	var head := Color("#E4EEF0")
	mk.sphere(Vector3(0.43, 0.075, 0), 0.1, head, 3, 8, Vector3(0.9, 0.75, 1.15), head.darkened(0.08))
	for i in 6:
		var a := TAU * i / 6.0
		mk.sphere(Vector3(0.43 + cos(a) * 0.075, 0.05, sin(a) * 0.09), 0.055, head.darkened(0.04 * (i % 2)), 2, 6)
	mk.torus(Vector3(0.37, 0.07, 0), 0.07, 0.015, Art.SKY, 8, 3)

static func _can_body(mk: MeshKit) -> void:
	tube(mk, Vector3.ZERO, 0.115, 0.1, 0.18, Art.SAGE, Art.SAGE.darkened(0.35), 10, 0.016, 0.03, Art.SAGE.lightened(0.18))
	mk.torus(Vector3(0, 0.18, 0), 0.1, 0.014, Art.BRASS, 10, 3)
	mk.torus(Vector3(0, 0.02, 0), 0.115, 0.012, Art.SAGE.darkened(0.15), 10, 3)
	rod(mk, Vector3(0.08, 0.05, 0), Vector3(0.25, 0.2, 0), 0.024, Art.SAGE.darkened(0.06), 6)
	rod(mk, Vector3(0.24, 0.19, 0), Vector3(0.28, 0.23, 0), 0.042, Art.BRASS, 7)
	mk.push_at(Vector3(-0.1, 0.12, 0), Vector3(90, 0, 0))
	mk.torus(Vector3.ZERO, 0.075, 0.017, Art.SAGE.darkened(0.08), 10, 4)
	mk.pop()

static func _can_water(mk: MeshKit) -> void:
	mk.disc(Vector3.ZERO, 0.088, Art.WATER.lightened(0.1), 10)
	mk.disc(Vector3(0.02, 0.002, -0.02), 0.02, Art.WHITE, 5)

static func _can_drops(mk: MeshKit, n: int) -> void:
	for i in 3:
		var full := i < n
		var c := Color("#5FB3D9") if full else Art.SAGE.darkened(0.2)
		mk.push_at(Vector3(-0.055 + i * 0.055, 0.075, 0.108 - absf(i - 1) * 0.008), Vector3(0, (i - 1) * -28.0, 0))
		poly_xy(mk, teardrop_pts(0.02, 6, 1.9), 0.012, c, c.lightened(0.2) if full else c)
		mk.pop()

static func _can_node(extra: Dictionary) -> StationNode:
	var st := StationNode.new()
	st.kind = "watering_can"
	st.name = "Item_watering_can"
	st.add_child(mesh_node(cached("item_can_body", _can_body), "Body"))
	var water := mesh_node(cached("item_can_water", _can_water), "Water")
	st.add_child(water)
	st.parts["water"] = water
	var drops := mesh_node(cached("item_can_drops_3", _can_drops.bind(3)), "Drops")
	st.add_child(drops)
	st.parts["drops"] = drops
	st.apply_fn = _can_apply
	st.apply({"charges": int(extra.get("charges", 3))})
	return st

static func _can_apply(st: StationNode, s: Dictionary) -> void:
	if not s.has("charges"):
		return
	var n := clampi(int(s["charges"]), 0, 3)
	if not st.changed("charges", n):
		return
	var w: Node3D = st.parts["water"]
	w.visible = n > 0
	w.position.y = [0.03, 0.08, 0.12, 0.16][n]
	st.set_part_mesh("drops", cached("item_can_drops_%d" % n, _can_drops.bind(n)))

static func _breezer_base(mk: MeshKit) -> void:
	rod(mk, Vector3(0, 0.03, 0.05), Vector3(0, 0.03, 0.24), 0.028, Art.WALNUT.lightened(0.15), 6)
	mk.sphere(Vector3(0, 0.03, 0.25), 0.035, Art.CORAL, 2, 6)
	mk.sphere(Vector3(0, 0.04, -0.06), 0.06, Art.CORAL, 3, 7, Vector3(1, 0.7, 1))
	mk.torus(Vector3(0, 0.05, -0.06), 0.13, 0.016, Art.BRASS, 14, 4)
	for k in 2:
		mk.push_at(Vector3(0, 0.05, -0.06), Vector3(0, 45.0 + 90.0 * k, 0))
		mk.box(Vector3.ZERO, Vector3(0.25, 0.012, 0.012), Art.BRASS.darkened(0.1))
		mk.pop()

static func _breezer_blades(mk: MeshKit) -> void:
	for k in 4:
		var c := Art.SKY.lightened(0.1) if k % 2 == 0 else Art.CREAM
		mk.push_at(Vector3(0, 0.07, -0.06), Vector3(0, 90.0 * k, 0))
		mk.push_at(Vector3(0.06, 0, 0), Vector3(-18, 0, 0))
		mk.sphere(Vector3.ZERO, 0.055, c, 2, 6, Vector3(1.0, 0.18, 0.62))
		mk.pop()
		mk.pop()
	mk.sphere(Vector3(0, 0.08, -0.06), 0.025, Art.GOLD, 2, 6)

static func _breezer_node(extra: Dictionary) -> StationNode:
	var st := StationNode.new()
	st.kind = "breezer"
	st.name = "Item_breezer"
	st.add_child(mesh_node(cached("item_breezer_base", _breezer_base), "Body"))
	var hub := Node3D.new()
	hub.name = "Blades"
	hub.position = Vector3(0, 0, -0.06)
	st.add_child(hub)
	var bl := mesh_node(cached("item_breezer_blades", _breezer_blades), "BladeMesh")
	bl.position = Vector3(0, 0, 0.06)
	hub.add_child(bl)
	st.parts["blades"] = hub
	st.anim["active"] = bool(extra.get("active", false))
	st.apply_fn = func(n: StationNode, s: Dictionary) -> void:
		if s.has("active"):
			n.anim["active"] = bool(s["active"])
	st.tick_fn = func(n: StationNode, dt: float) -> void:
		var hb: Node3D = n.parts["blades"]
		hb.rotation.y += dt * (16.0 if n.anim.get("active", false) else 0.6)
	return st

# ---------------------------------------------------------------- festival

## Long painted festival trunk (1.8 x 0.5 x 0.5). `with_lid` adds the closed lid.
static func trunk(mk: MeshKit, open_body: bool, with_lid := true, look := Vector2.ZERO) -> void:
	var blue := TRUNK_BLUE
	var L := 1.8
	var D := 0.5
	var H := 0.36
	if open_body:
		open_box(mk, Vector3(0, 0.0, 0), Vector3(L, H, D), blue, Color("#E9A7B4"), 0.045, 0.06, blue.lightened(0.12))
	else:
		mk.rbox(Vector3(0, H * 0.5, 0), Vector3(L, H, D), blue, 0.05, blue.lightened(0.12))
	mk.box(Vector3(0, 0.025, 0), Vector3(L + 0.02, 0.05, D + 0.02), blue.darkened(0.25))
	for x in [-0.86, -0.56, 0.56, 0.86]:
		for sz in [-1.0, 1.0]:
			mk.box(Vector3(x, H * 0.5 + 0.005, sz * (D * 0.5 + 0.004)), Vector3(0.06, H + 0.01, 0.014), Art.GOLD, Art.GOLD.lightened(0.15))
		mk.box(Vector3(x, H - 0.004, 0), Vector3(0.06, 0.012, D + 0.02), Art.GOLD.lightened(0.1))
	for s in [-1.0, 1.0]:
		mk.push_at(Vector3(s * 0.92, 0.24, 0), Vector3(0, 0, 90))
		mk.torus(Vector3.ZERO, 0.08, 0.02, Art.BRASS, 8, 4)
		mk.pop()
		mk.box(Vector3(s * 0.905, 0.24, 0), Vector3(0.03, 0.06, 0.2), Art.BRASS.darkened(0.15))
	# Friendly painted face on the long front.
	for s in [-1.0, 1.0]:
		eye_xy(mk, Vector3(s * 0.15, 0.22, D * 0.5 + 0.004), 0.065, look)
		mk.push_at(Vector3(s * 0.27, 0.15, D * 0.5 + 0.004))
		poly_xy(mk, circle_pts(0.04, 8, 1.3, 0.8), 0.008, Art.ROSE)
		mk.pop()
	for i in 3:
		mk.box(Vector3(-0.04 + i * 0.04, 0.13 - (0.012 if i == 1 else 0.0), D * 0.5 + 0.006), Vector3(0.045, 0.018, 0.01), Art.INK.lightened(0.1))
	if with_lid:
		trunk_lid(mk, Vector3(0, H, -D * 0.5))

## Lid geometry relative to its back hinge at `hinge`.
static func trunk_lid(mk: MeshKit, hinge: Vector3) -> void:
	var blue := TRUNK_BLUE.lightened(0.05)
	var L := 1.8
	var D := 0.5
	mk.push_at(hinge)
	mk.rbox(Vector3(0, 0.04, D * 0.5), Vector3(L, 0.08, D), blue, 0.05, blue.lightened(0.14))
	mk.push_at(Vector3(0, 0.075, D * 0.5), Vector3(0, 0, 90), Vector3(1, 0.26, 1))
	mk.cyl(Vector3(0, -L * 0.5 + 0.03, 0), D * 0.49, L - 0.06, blue.lightened(0.06), 10, blue.lightened(0.12))
	mk.pop()
	for x in [-0.86, -0.56, 0.56, 0.86]:
		mk.box(Vector3(x, 0.072, D * 0.5), Vector3(0.062, 0.15, D + 0.02), Art.GOLD, Art.GOLD.lightened(0.18))
	mk.box(Vector3(0, 0.02, D + 0.012), Vector3(0.1, 0.09, 0.03), Art.BRASS)
	mk.pop()

static func tiny_case(mk: MeshKit) -> void:
	var case_c := Color("#B5764D")
	mk.rbox(Vector3(0, 0.1, 0), Vector3(0.34, 0.2, 0.18), case_c, 0.04, case_c.lightened(0.14))
	mk.box(Vector3(0, 0.21, 0), Vector3(0.1, 0.04, 0.03), Art.INK.lightened(0.15))
	for s in [-1.0, 1.0]:
		mk.box(Vector3(s * 0.1, 0.1, 0.0), Vector3(0.035, 0.205, 0.185), case_c.darkened(0.25))
		eye_xy(mk, Vector3(s * 0.045, 0.13, 0.095), 0.03)
	# Bow tie.
	for s in [-1.0, 1.0]:
		mk.push_at(Vector3(s * 0.035, 0.06, 0.1))
		poly_xy(mk, [Vector2(0, 0), Vector2(s * 0.045, -0.025), Vector2(s * 0.045, 0.025)], 0.02, Art.CORAL, Art.CORAL.lightened(0.1), Vector2(s * 0.028, 0))
		mk.pop()
	mk.sphere(Vector3(0, 0.06, 0.105), 0.015, Art.CORAL.darkened(0.15), 2, 5)

static func _trunk_node(extra: Dictionary) -> StationNode:
	var st := StationNode.new()
	st.kind = "festival_trunk"
	st.name = "Item_festival_trunk"
	var body := mesh_node(cached("item_trunk_body", trunk.bind(true, false, Vector2.ZERO)), "Body")
	st.add_child(body)
	var lid := Node3D.new()
	lid.name = "Lid"
	lid.position = Vector3(0, 0.36, -0.25)
	st.add_child(lid)
	lid.add_child(mesh_node(cached("item_trunk_lid", trunk_lid.bind(Vector3.ZERO)), "LidMesh"))
	st.parts["lid"] = lid
	var inside := Node3D.new()
	inside.name = "Suitcase"
	inside.position = Vector3(0.0, 0.06, 0.0)
	st.add_child(inside)
	inside.add_child(mesh_node(cached("itemtiny_case", tiny_case), "CaseMesh"))
	st.parts["suitcase"] = inside
	for s in [-1.0, 1.0]:
		var h := Node3D.new()
		h.name = "HandleL" if s < 0 else "HandleR"
		h.position = Vector3(s * 0.98, 0.24, 0)
		st.add_child(h)
		st.parts["handle_l" if s < 0 else "handle_r"] = h
	st.apply_fn = _trunk_apply
	st.tick_fn = _trunk_tick
	st.apply({"open": bool(extra.get("open", false))})
	return st

static func _trunk_apply(st: StationNode, s: Dictionary) -> void:
	if s.has("open") and st.changed("open", bool(s["open"])):
		var open := bool(s["open"])
		var lid: Node3D = st.parts["lid"]
		lid.rotation.x = -1.95 if open else 0.0
		st.show_part("suitcase", open)

static func _trunk_tick(st: StationNode, dt: float) -> void:
	var sc: Node3D = st.parts["suitcase"]
	if sc.visible:
		sc.position.y = 0.06 + absf(sin(st.t * 4.0)) * 0.03
		sc.rotation.z = sin(st.t * 4.0) * 0.08

## Wrapped parcel; `index` picks the wrapping/ribbon pair.
static func parcel(mk: MeshKit, index: int) -> void:
	var wraps := [Art.CORAL, Art.SKY, Art.PLUM, Art.SAGE, Art.ROSE, Art.GOLD]
	var ribbons := [Art.GOLD, Art.CREAM, Art.GOLD, Art.CREAM, Art.PLUM, Art.CORAL]
	var i := posmod(index, wraps.size())
	var w: Color = wraps[i]
	var rb: Color = ribbons[i]
	mk.rbox(Vector3(0, 0.12, 0), Vector3(0.3, 0.24, 0.28), w, 0.04, w.lightened(0.14))
	mk.box(Vector3(0, 0.122, 0), Vector3(0.065, 0.248, 0.29), rb, rb.lightened(0.1))
	mk.box(Vector3(0, 0.122, 0), Vector3(0.31, 0.248, 0.065), rb, rb.lightened(0.1))
	for s in [-1.0, 1.0]:
		mk.push_at(Vector3(s * 0.045, 0.265, 0), Vector3(0, 0, -s * 28.0))
		mk.sphere(Vector3.ZERO, 0.05, rb.lightened(0.05), 2, 6, Vector3(1.1, 0.6, 0.55))
		mk.pop()
	mk.sphere(Vector3(0, 0.255, 0), 0.025, rb.darkened(0.1), 2, 5)
