class_name ModelProps
extends RefCounted
## Story props (§4, §17.3) and hub decorations for the eight cosmetic sets
## (§16.3). Static, one cached mesh each, true metres, origin at bottom centre,
## front toward +z. Built from the same palette and shape helpers as the items.

const KINDS := ["invitation", "checklist", "fan", "paper_moon", "lantern", "flower_crown",
	"tiny_suitcase", "camera", "travel_hat_warm", "travel_hat_cool", "clipboard", "towel_puppet",
	"umbrella", "slipper_flowerpot",
	"welcome_pennant", "sheet_sculpture", "split_lamp", "fabric_stage", "flowerpot_trio",
	"mini_trunk", "moon_stand", "thank_you_garland"]

const MOON := Color("#FFEFB5")
const STRAW := Color("#E8CF8E")

static func kinds() -> PackedStringArray:
	return PackedStringArray(KINDS)

static func build(kind: String) -> Node3D:
	var root := Node3D.new()
	root.name = "Prop_" + kind
	var mesh := ModelItems.cached("prop_" + kind, draw.bind(kind))
	root.add_child(ModelItems.mesh_node(mesh, "Mesh"))
	if kind == "split_lamp":
		var bulb := ModelItems.mesh_node(ModelItems.cached("prop_split_lamp_bulb", _lamp_bulb), "Bulb", ModelItems.lit_mat())
		root.add_child(bulb)
	return root

static func draw(mk: MeshKit, kind: String) -> void:
	match kind:
		"invitation": _invitation(mk)
		"checklist": _checklist(mk)
		"fan": _fan(mk)
		"paper_moon": _paper_moon(mk, 0.55, true)
		"lantern": _lantern(mk, Art.CORAL)
		"flower_crown": _flower_crown(mk)
		"tiny_suitcase": ModelItems.tiny_case(mk)
		"camera": _camera(mk)
		"travel_hat_warm": _hat_warm(mk)
		"travel_hat_cool": _hat_cool(mk)
		"clipboard": _clipboard(mk)
		"towel_puppet": _towel_puppet(mk)
		"umbrella": _umbrella(mk, 0.3, 0.6)
		"slipper_flowerpot": _slipper_pot(mk)
		"welcome_pennant": _pennant(mk)
		"sheet_sculpture": _sheet_swan(mk)
		"split_lamp": _split_lamp(mk)
		"fabric_stage": _fabric_stage(mk)
		"flowerpot_trio": _pot_trio(mk)
		"mini_trunk": _mini_trunk(mk)
		"moon_stand": _moon_stand(mk)
		"thank_you_garland": _garland(mk)
		_:
			mk.box(Vector3(0, 0.15, 0), Vector3(0.3, 0.3, 0.3), Art.ROSE)

# ---------------------------------------------------------------- paper

static func _invitation(mk: MeshKit) -> void:
	var env := Art.CREAM
	mk.rbox(Vector3(0, 0.012, 0.04), Vector3(0.34, 0.024, 0.22), env.darkened(0.08), 0.02, env)
	ModelItems.poly_flat(mk, Vector3(0, 0.024, 0.04), [Vector2(-0.17, 0.11), Vector2(0.17, 0.11), Vector2(0, -0.02)], 0.006, env.darkened(0.12), env.darkened(0.05))
	mk.cyl(Vector3(0, 0.026, 0.06), 0.035, 0.012, Art.CORAL.darkened(0.1), 8, Art.CORAL)
	mk.push_at(Vector3(0, 0.0, -0.04), Vector3(-18, 0, 0))
	mk.box(Vector3(0, 0.17, 0), Vector3(0.26, 0.34, 0.014), Art.GOLD.darkened(0.05), Art.GOLD)
	mk.box(Vector3(0, 0.17, 0.008), Vector3(0.21, 0.29, 0.008), Art.WHITE)
	mk.push_at(Vector3(-0.02, 0.22, 0.014), Vector3(0, 0, 160))
	ModelItems.crescent_xy(mk, 0.06, 0.035, 0.008, Art.PLUM)
	mk.pop()
	for i in 3:
		mk.box(Vector3(0, 0.12 - i * 0.035, 0.013), Vector3(0.14 - i * 0.03, 0.012, 0.006), Art.SKY.darkened(0.2))
	for p in [[Vector3(0.07, 0.27, 0.014), Art.CORAL], [Vector3(-0.08, 0.06, 0.014), Art.SAGE], [Vector3(0.08, 0.05, 0.014), Art.SKY]]:
		var pos: Vector3 = p[0]
		mk.push_at(pos)
		ModelItems.poly_xy(mk, ModelItems.star_pts(5, 0.02, 0.009), 0.006, p[1])
		mk.pop()
	mk.pop()

static func _checklist(mk: MeshKit) -> void:
	var n := 7
	var w := 0.19
	var h := 0.26
	var x := -0.6
	for i in n:
		var ang := 28.0 if i % 2 == 0 else -28.0
		mk.push_at(Vector3(x, 0, 0), Vector3(0, ang, 0))
		var col := Art.WHITE if i % 2 == 0 else Art.CREAM
		mk.box(Vector3(w * 0.5, h * 0.5, 0), Vector3(w, h, 0.01), col.darkened(0.05), col)
		for r in 4:
			var yy := h - 0.05 - r * 0.055
			var done := (i + r) % 3 != 0
			mk.box(Vector3(0.035, yy, 0.007), Vector3(0.028, 0.028, 0.006), Art.CORAL if done else Art.SKY.darkened(0.15))
			mk.box(Vector3(0.11, yy, 0.007), Vector3(0.1, 0.012, 0.006), Art.SKY.darkened(0.2))
		mk.pop()
		x += w * cos(deg_to_rad(ang))
	mk.push_at(Vector3(x, 0.004, 0.04), Vector3(0, 10, 0))
	mk.box(Vector3(0.16, 0, 0), Vector3(0.32, 0.008, 0.19), Art.WHITE.darkened(0.03), Art.WHITE)
	mk.pop()

static func _fan(mk: MeshKit) -> void:
	var n := 11
	var r := 0.3
	var c := Vector3(0, 0.08, 0)
	for i in n:
		var a0 := deg_to_rad(180.0 * i / n)
		var a1 := deg_to_rad(180.0 * (i + 1) / n)
		var col := Art.WHITE if i % 2 == 0 else Art.CREAM.darkened(0.06)
		var dz := 0.02 if i % 2 == 0 else -0.02
		var p0 := c + Vector3(cos(a0) * r, sin(a0) * r, dz)
		var p1 := c + Vector3(cos(a1) * r, sin(a1) * r, -dz)
		mk.tri(c, p0, p1, col)
		mk.tri(c, p1, p0, col.darkened(0.1))
		var m := (a0 + a1) * 0.5
		mk.push_at(c + Vector3(cos(m) * r * 0.7, sin(m) * r * 0.7, 0.012), Vector3(0, 0, rad_to_deg(m)))
		mk.box(Vector3.ZERO, Vector3(0.05, 0.012, 0.006), Art.SKY.darkened(0.15) if i % 3 else Art.CORAL)
		mk.pop()
	mk.push_at(c + Vector3(0, 0, 0.01))
	mk.torus(Vector3.ZERO, 0.035, 0.012, Art.CORAL, 8, 3)
	mk.pop()
	ModelItems.rod(mk, c, Vector3(0, 0.0, 0.0), 0.02, Art.CORAL.darkened(0.1), 5)
	mk.cyl(Vector3.ZERO, 0.06, 0.015, Art.WALNUT, 8)

static func _paper_moon(mk: MeshKit, r: float, base: bool) -> void:
	var cy := r + (0.2 if base else 0.0)
	if base:
		mk.rbox(Vector3(0, 0.04, 0), Vector3(0.5, 0.08, 0.3), Art.WALNUT, 0.06, Art.WALNUT.lightened(0.12))
		mk.cyl(Vector3(0, 0.08, 0), 0.03, 0.16, Art.BRASS, 6)
	mk.push_at(Vector3(r * 0.25, cy, 0), Vector3(0, 0, 15))
	ModelItems.crescent_xy(mk, r, r * 0.58, r * 0.16, MOON.darkened(0.08), MOON, 115.0, 14)
	var fx := r * 0.62
	mk.box(Vector3(fx, r * 0.18, r * 0.09), Vector3(r * 0.16, r * 0.04, 0.012), Art.INK.lightened(0.1))
	mk.push_at(Vector3(fx + r * 0.06, -r * 0.08, r * 0.085))
	ModelItems.poly_xy(mk, ModelItems.circle_pts(r * 0.07, 8, 1.2, 0.8), 0.01, Art.ROSE)
	mk.pop()
	for k in 3:
		mk.box(Vector3(fx - r * 0.06 + k * r * 0.06, -r * 0.28 - (r * 0.02 if k == 1 else 0.0), r * 0.09), Vector3(r * 0.07, r * 0.03, 0.012), Art.INK.lightened(0.1))
	mk.pop()
	# Dangling paper star.
	ModelItems.rod(mk, Vector3(-r * 0.25, cy + r * 0.62, 0), Vector3(-r * 0.25, cy + r * 0.3, 0), 0.006, Art.INK.lightened(0.2), 4)
	mk.push_at(Vector3(-r * 0.25, cy + r * 0.25, 0))
	ModelItems.poly_xy(mk, ModelItems.star_pts(5, r * 0.12, r * 0.055), 0.02, Art.GOLD.darkened(0.08), Art.GOLD)
	mk.pop()

static func _lantern(mk: MeshKit, col: Color, r := 0.12) -> void:
	var c := Vector3(0, r * 1.5, 0)
	mk.sphere(c, r, col, 4, 10, Vector3(1, 1.2, 1), col.darkened(0.1))
	for k in 3:
		mk.torus(c + Vector3(0, -r * 0.6 + k * r * 0.6, 0), r * (0.82 if k != 1 else 1.0), r * 0.07, col.lightened(0.25), 10, 3)
	mk.cyl(c + Vector3(0, r * 1.1, 0), r * 0.45, r * 0.22, Art.GOLD.darkened(0.1), 8, Art.GOLD)
	mk.cyl(c - Vector3(0, r * 1.38, 0), r * 0.45, r * 0.22, Art.GOLD.darkened(0.1), 8)
	mk.push_at(c + Vector3(0, r * 1.45, 0), Vector3(90, 0, 0))
	mk.torus(Vector3.ZERO, r * 0.4, r * 0.06, Art.INK.lightened(0.2), 8, 3)
	mk.pop()
	mk.sphere(c - Vector3(0, r * 1.5, 0), r * 0.12, Art.CORAL.darkened(0.2), 2, 5)

static func _flower(mk: MeshKit, pos: Vector3, col: Color, r := 0.035) -> void:
	for i in 5:
		var a := TAU * i / 5.0
		mk.sphere(pos + Vector3(cos(a) * r, 0, sin(a) * r), r * 0.8, col, 2, 5, Vector3(1, 0.55, 1))
	mk.sphere(pos + Vector3(0, r * 0.3, 0), r * 0.55, Art.GOLD, 2, 5)

static func _flower_crown(mk: MeshKit) -> void:
	var R := 0.13
	mk.torus(Vector3(0, 0.025, 0), R, 0.018, Art.LEAF.darkened(0.1), 14, 4)
	for i in 12:
		var a := TAU * i / 12.0
		mk.push_at(Vector3(cos(a) * R, 0.03, sin(a) * R), Vector3(0, -rad_to_deg(a), 0))
		mk.sphere(Vector3(0, 0, 0.0), 0.035, Art.LEAF.lightened(0.05 * (i % 3)), 2, 5, Vector3(0.6, 0.4, 1.5))
		mk.pop()
	var cols := [Art.ROSE, Art.GOLD.lightened(0.1), Art.CORAL, Art.SKY, Art.WHITE]
	for j in 5:
		var b := TAU * j / 5.0 + 0.3
		_flower(mk, Vector3(cos(b) * R, 0.06, sin(b) * R), cols[j], 0.032)

static func _camera(mk: MeshKit) -> void:
	var top := Vector3(0, 0.5, 0)
	for k in 3:
		var a := TAU * k / 3.0 + PI * 0.5
		ModelItems.rod(mk, top, Vector3(cos(a) * 0.26, 0.0, sin(a) * 0.26), 0.022, Art.WALNUT.lightened(0.1), 5)
		mk.sphere(Vector3(cos(a) * 0.26, 0.015, sin(a) * 0.26), 0.03, Art.WALNUT.darkened(0.2), 2, 5)
	mk.cyl(top - Vector3(0, 0.02, 0), 0.07, 0.04, Art.BRASS.darkened(0.15), 8)
	var b := top + Vector3(0, 0.14, 0)
	mk.rbox(b, Vector3(0.3, 0.22, 0.22), Art.WALNUT, 0.05, Art.WALNUT.lightened(0.15))
	mk.box(b + Vector3(0, 0, 0.12), Vector3(0.2, 0.16, 0.06), Art.PLUM.lightened(0.05))
	mk.box(b + Vector3(0, 0, 0.165), Vector3(0.16, 0.13, 0.04), Art.PLUM.lightened(0.15))
	mk.push_at(b + Vector3(0, 0, 0.18), Vector3(90, 0, 0))
	mk.cyl(Vector3.ZERO, 0.06, 0.06, Art.BRASS, 10, Art.BRASS.lightened(0.1))
	mk.pop()
	mk.push_at(b + Vector3(0, 0, 0.243))
	ModelItems.poly_xy(mk, ModelItems.circle_pts(0.042, 10), 0.01, Color("#4E6A86"), Color("#6F93B5"))
	mk.pop()
	mk.sphere(b + Vector3(0.015, 0.015, 0.252), 0.012, Art.WHITE, 2, 4)
	mk.cyl(b + Vector3(-0.09, 0.11, 0.0), 0.025, 0.06, Art.BRASS.darkened(0.1), 6)
	mk.push_at(b + Vector3(-0.09, 0.2, 0.01), Vector3(-25, 0, 0))
	mk.cyl(Vector3.ZERO, 0.075, 0.03, Art.GOLD, 10, Art.WHITE, 0.09)
	mk.pop()
	mk.cyl(b + Vector3(0.09, 0.11, 0.0), 0.02, 0.03, Art.CORAL, 6)
	mk.box(b + Vector3(0, 0, -0.112), Vector3(0.18, 0.12, 0.012), Art.CREAM.darkened(0.06))

# ---------------------------------------------------------------- hats

static func _hat_warm(mk: MeshKit) -> void:
	mk.cyl(Vector3.ZERO, 0.21, 0.025, STRAW.darkened(0.08), 14, STRAW)
	mk.cyl(Vector3(0, 0.02, 0), 0.115, 0.11, STRAW.darkened(0.04), 12, STRAW.lightened(0.05), 0.1)
	mk.cyl(Vector3(0, 0.03, 0), 0.118, 0.035, Art.CORAL, 12, Art.CORAL)
	mk.push_at(Vector3(0.0, 0.05, 0.118))
	ModelItems.sun_xy(mk, 0.07, 0.01, Art.GOLD.lightened(0.1), Art.CREAM)
	mk.pop()
	mk.push_at(Vector3(-0.1, 0.06, 0.05), Vector3(0, 0, 30))
	mk.sphere(Vector3.ZERO, 0.04, Art.ROSE, 2, 5, Vector3(1, 0.4, 1))
	mk.pop()

static func _hat_cool(mk: MeshKit) -> void:
	var knit := Art.SKY
	mk.cyl(Vector3.ZERO, 0.13, 0.06, Art.CREAM.darkened(0.06), 12, Art.CREAM)
	mk.sphere(Vector3(0, 0.06, 0), 0.13, knit, 4, 12, Vector3(1, 0.95, 1), knit.darkened(0.1))
	for k in 6:
		var a := TAU * k / 6.0
		mk.box(Vector3(cos(a) * 0.131, 0.03, sin(a) * 0.131), Vector3(0.02, 0.06, 0.02), Art.CREAM.darkened(0.15))
	for s in [-1.0, 1.0]:
		mk.push_at(Vector3(s * 0.12, -0.02, 0.0), Vector3(0, 0, -s * 8.0))
		mk.rbox(Vector3.ZERO, Vector3(0.04, 0.11, 0.09), knit.darkened(0.05), 0.03)
		mk.pop()
		ModelItems.rod(mk, Vector3(s * 0.12, -0.07, 0), Vector3(s * 0.13, -0.16, 0.02), 0.01, Art.CREAM, 4)
	mk.sphere(Vector3(0, 0.2, 0), 0.05, Art.WHITE, 2, 7)
	mk.push_at(Vector3(0, 0.1, 0.12), Vector3(-20, 0, 0))
	ModelItems.snowflake_xy(mk, 0.09, 0.016, 0.01, Art.WHITE)
	mk.pop()

# ---------------------------------------------------------------- odds and ends

static func _clipboard(mk: MeshKit) -> void:
	mk.push_at(Vector3(0, 0.0, 0), Vector3(-75, 0, 0))
	mk.box(Vector3(0, 0.2, 0.01), Vector3(0.3, 0.4, 0.02), Art.WALNUT, Art.WALNUT)
	mk.box(Vector3(0, 0.19, 0.024), Vector3(0.25, 0.33, 0.008), Art.WHITE)
	for i in 5:
		mk.box(Vector3(0.02, 0.29 - i * 0.055, 0.03), Vector3(0.16, 0.014, 0.004), Art.SKY.darkened(0.2))
		mk.box(Vector3(-0.09, 0.29 - i * 0.055, 0.03), Vector3(0.022, 0.022, 0.004), Art.CORAL if i < 3 else Art.STONE)
	mk.box(Vector3(0, 0.38, 0.035), Vector3(0.12, 0.05, 0.03), Art.BRASS, Art.GOLD)
	mk.pop()
	ModelItems.rod(mk, Vector3(0.18, 0.015, -0.1), Vector3(0.12, 0.015, 0.16), 0.014, Art.GOLD, 6)
	mk.sphere(Vector3(0.18, 0.015, -0.1), 0.016, Art.CORAL, 2, 5)

static func _towel_puppet(mk: MeshKit) -> void:
	var c := Art.CORAL
	mk.cyl(Vector3.ZERO, 0.13, 0.22, c.darkened(0.06), 9, c, 0.1)
	mk.sphere(Vector3(0, 0.27, 0), 0.12, c, 3, 9, Vector3(1, 0.85, 0.95))
	for y in [0.04, 0.16]:
		mk.torus(Vector3(0, y, 0), 0.13 - y * 0.12, 0.012, Art.CREAM, 9, 3)
	for s in [-1.0, 1.0]:
		mk.push_at(Vector3(s * 0.08, 0.37, -0.02), Vector3(0, 0, -s * 25.0))
		mk.cyl(Vector3(0, -0.02, 0), 0.035, 0.09, c.lightened(0.06), 6, Art.CREAM)
		mk.pop()
		ModelItems.eye_xy(mk, Vector3(s * 0.045, 0.29, 0.108), 0.03)
	mk.box(Vector3(0, 0.235, 0.115), Vector3(0.05, 0.016, 0.01), Art.INK.lightened(0.1))
	mk.sphere(Vector3(0, 0.25, 0.115), 0.016, Art.ROSE, 2, 5)

static func _umbrella(mk: MeshKit, r: float, h: float) -> void:
	var apex := Vector3(0, h + 0.03, 0)
	var n := 8
	for i in n:
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		var p0 := Vector3(cos(a0) * r, h - 0.1, sin(a0) * r)
		var p1 := Vector3(cos(a1) * r, h - 0.1, sin(a1) * r)
		var m := (p0 + p1) * 0.5 + Vector3(0, 0.02, 0)
		var col := Art.CORAL if i % 2 == 0 else Art.CREAM
		mk.tri(apex, p1, m, col)
		mk.tri(apex, m, p0, col)
		mk.tri(apex, m, p1, col.darkened(0.25))
		mk.tri(apex, p0, m, col.darkened(0.25))
		mk.sphere(p0, 0.015, Art.GOLD, 1, 4)
	mk.sphere(apex + Vector3(0, 0.02, 0), 0.025, Art.GOLD, 2, 5)
	ModelItems.rod(mk, Vector3(0, 0.08, 0), apex, 0.014, Art.WALNUT.lightened(0.1), 5)
	mk.push_at(Vector3(0.04, 0.08, 0), Vector3(90, 0, 0))
	mk.torus(Vector3.ZERO, 0.04, 0.014, Art.WALNUT, 8, 3)
	mk.pop()

static func _slipper_pot(mk: MeshKit) -> void:
	var sl := ModelItems.SLIPPER
	mk.rbox(Vector3(0, 0.045, 0), Vector3(0.15, 0.09, 0.3), sl.darkened(0.06), 0.06, sl.lightened(0.15))
	mk.sphere(Vector3(0, 0.07, 0.07), 0.08, sl.lightened(0.08), 3, 7, Vector3(0.95, 0.7, 1.15))
	mk.sphere(Vector3(0, 0.12, 0.11), 0.04, Art.WHITE, 2, 6)
	mk.box(Vector3(0, 0.092, -0.06), Vector3(0.1, 0.008, 0.13), ModelItems.SOIL)
	mk.cyl(Vector3(0, 0.09, -0.06), 0.012, 0.17, Art.LEAF, 5)
	for s in [-1.0, 1.0]:
		mk.push_at(Vector3(s * 0.01, 0.17, -0.06), Vector3(0, 0, -s * 55.0))
		mk.sphere(Vector3(0, 0.04, 0), 0.045, Art.LEAF.lightened(0.08), 2, 6, Vector3(0.6, 1.0, 0.35))
		mk.pop()
	_flower(mk, Vector3(0, 0.27, -0.06), Art.GOLD.lightened(0.15), 0.035)

# ---------------------------------------------------------------- hub decorations

static func _pennant(mk: MeshKit) -> void:
	mk.cyl(Vector3.ZERO, 0.12, 0.05, Art.WALNUT.darkened(0.1), 10, Art.WALNUT.lightened(0.1))
	mk.cyl(Vector3(0, 0.05, 0), 0.016, 0.62, Art.BRASS, 5)
	mk.sphere(Vector3(0, 0.68, 0), 0.03, Art.GOLD, 2, 6)
	mk.push_at(Vector3(0.0, 0.5, 0))
	ModelItems.poly_xy(mk, [Vector2(0.0, 0.11), Vector2(0.34, 0.0), Vector2(0.0, -0.11)], 0.016, Art.CORAL.darkened(0.06), Art.CORAL, Vector2(0.1, 0))
	mk.push_at(Vector3(0.0, 0.0, 0.01))
	ModelItems.poly_xy(mk, [Vector2(0.0, 0.11), Vector2(0.34, 0.0), Vector2(0.0, 0.085), ], 0.006, Art.CREAM, null, Vector2(0.1, 0.06))
	mk.pop()
	mk.push_at(Vector3(0.1, 0.0, 0.012))
	ModelItems.poly_xy(mk, ModelItems.star_pts(5, 0.04, 0.018), 0.008, Art.GOLD.lightened(0.1))
	mk.pop()
	mk.pop()

static func _sheet_swan(mk: MeshKit) -> void:
	mk.rbox(Vector3(0, 0.06, 0), Vector3(0.42, 0.12, 0.32), Art.WALNUT, 0.06, Art.WALNUT.lightened(0.15))
	mk.box(Vector3(0, 0.125, 0), Vector3(0.36, 0.01, 0.26), Art.SKY, Art.SKY.lightened(0.1))
	var w := Art.WHITE
	mk.sphere(Vector3(-0.02, 0.21, 0), 0.15, w, 4, 9, Vector3(1.25, 0.55, 0.85), Art.CREAM.darkened(0.06))
	for s in [-1.0, 1.0]:
		mk.push_at(Vector3(-0.03, 0.25, s * 0.08), Vector3(s * 20.0, 0, 12))
		mk.sphere(Vector3.ZERO, 0.1, Art.CREAM, 3, 7, Vector3(1.3, 0.35, 0.6))
		mk.pop()
	mk.push_at(Vector3(-0.2, 0.25, 0), Vector3(0, 0, 35))
	mk.cone(Vector3.ZERO, 0.06, 0.12, w, 5)
	mk.pop()
	var pts := [Vector3(0.12, 0.24, 0), Vector3(0.17, 0.32, 0), Vector3(0.17, 0.41, 0), Vector3(0.13, 0.47, 0)]
	for i in pts.size() - 1:
		ModelItems.rod(mk, pts[i], pts[i + 1], 0.03, w, 6)
	mk.sphere(Vector3(0.14, 0.48, 0), 0.045, w, 3, 7)
	mk.push_at(Vector3(0.17, 0.48, 0), Vector3(0, 0, -90))
	mk.cone(Vector3.ZERO, 0.018, 0.05, Art.CORAL, 5)
	mk.pop()
	mk.box(Vector3(0.15, 0.36, 0), Vector3(0.07, 0.03, 0.07), Art.SKY)

static func _split_lamp(mk: MeshKit) -> void:
	mk.cyl(Vector3.ZERO, 0.14, 0.04, Art.WALNUT.darkened(0.1), 10, Art.WALNUT.lightened(0.1))
	mk.cyl(Vector3(0, 0.04, 0), 0.025, 0.42, Art.BRASS, 6)
	var y0 := 0.38
	var y1 := 0.6
	var n := 12
	for i in n:
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		var warm := cos((a0 + a1) * 0.5) < 0.0
		var col := Art.CORAL if warm else Art.SKY
		var p0 := Vector3(cos(a0) * 0.22, y0, sin(a0) * 0.22)
		var p1 := Vector3(cos(a1) * 0.22, y0, sin(a1) * 0.22)
		var q0 := Vector3(cos(a0) * 0.12, y1, sin(a0) * 0.12)
		var q1 := Vector3(cos(a1) * 0.12, y1, sin(a1) * 0.12)
		mk.quad(p1, p0, q0, q1, col)
		mk.quad(q1, q0, p0, p1, col.lightened(0.3))
	mk.torus(Vector3(0, y0, 0), 0.22, 0.012, Art.GOLD, 12, 3)
	mk.torus(Vector3(0, y1, 0), 0.12, 0.012, Art.GOLD, 12, 3)
	mk.push_at(Vector3(-0.11, 0.49, 0.15), Vector3(-15, -35, 0))
	ModelItems.sun_xy(mk, 0.08, 0.01, Art.GOLD.lightened(0.1), Art.CREAM)
	mk.pop()
	mk.push_at(Vector3(0.11, 0.49, 0.15), Vector3(-15, 35, 0))
	ModelItems.snowflake_xy(mk, 0.08, 0.014, 0.01, Art.WHITE)
	mk.pop()

static func _lamp_bulb(mk: MeshKit) -> void:
	mk.jitter = 0.0
	mk.sphere(Vector3(0, 0.44, 0), 0.06, Color("#FFF3C8"), 3, 7)

static func _fabric_stage(mk: MeshKit) -> void:
	mk.rbox(Vector3(0, 0.08, 0), Vector3(0.8, 0.16, 0.5), Art.WALNUT, 0.06, Art.WALNUT.lightened(0.15))
	mk.box(Vector3(0, 0.162, 0.02), Vector3(0.62, 0.008, 0.4), Art.PLUM.lightened(0.25))
	for s in [-1.0, 1.0]:
		mk.cyl(Vector3(s * 0.38, 0.16, -0.2), 0.025, 0.62, Art.BRASS, 6)
		for k in 3:
			mk.cyl(Vector3(s * (0.33 - k * 0.05), 0.16, -0.19 + (k % 2) * 0.03), 0.04, 0.58, Art.PLUM.darkened(0.05 * k), 6, Art.PLUM, 0.03)
		mk.torus(Vector3(s * 0.28, 0.42, -0.17), 0.06, 0.012, Art.GOLD, 8, 3)
	mk.box(Vector3(0, 0.8, -0.2), Vector3(0.84, 0.1, 0.06), Art.GOLD.darkened(0.08), Art.GOLD)
	for i in 5:
		mk.push_at(Vector3(-0.32 + i * 0.16, 0.73, -0.17))
		ModelItems.poly_xy(mk, [Vector2(-0.07, 0.02), Vector2(0.07, 0.02), Vector2(0, -0.05)], 0.01, Art.PLUM.lightened(0.1))
		mk.pop()
	mk.push_at(Vector3(0.0, 0.9, -0.2))
	ModelItems.poly_xy(mk, ModelItems.star_pts(5, 0.06, 0.028), 0.02, Art.GOLD.lightened(0.1))
	mk.pop()
	mk.push_at(Vector3(0.03, 0.42, -0.21), Vector3(0, 0, 160))
	ModelItems.crescent_xy(mk, 0.12, 0.07, 0.02, MOON.darkened(0.05), MOON)
	mk.pop()

static func _pot_trio(mk: MeshKit) -> void:
	var pots := [[Vector3(-0.2, 0, 0.02), Art.CORAL, 0.1, 0.16, Art.ROSE], [Vector3(0.0, 0, -0.06), Art.GOLD, 0.12, 0.22, Art.SKY],
		[Vector3(0.2, 0, 0.04), Art.SAGE, 0.09, 0.13, Art.WHITE]]
	for p in pots:
		var pos: Vector3 = p[0]
		var col: Color = p[1]
		var r: float = p[2]
		var h: float = p[3]
		var fc: Color = p[4]
		ModelItems.tube(mk, pos, r * 0.8, r, h, col.darkened(0.05), ModelItems.SOIL, 8, 0.015, h - 0.03, col.lightened(0.15))
		var stem := h * 1.2
		mk.cyl(pos + Vector3(0, h - 0.03, 0), 0.012, stem, Art.LEAF, 5)
		for s in [-1.0, 1.0]:
			mk.push_at(pos + Vector3(s * 0.01, h + stem * 0.4, 0), Vector3(0, 0, -s * 55.0))
			mk.sphere(Vector3(0, 0.04, 0), 0.045, Art.LEAF.lightened(0.06), 2, 6, Vector3(0.6, 1.0, 0.35))
			mk.pop()
		_flower(mk, pos + Vector3(0, h - 0.03 + stem, 0), fc, 0.04)

static func _mini_trunk(mk: MeshKit) -> void:
	mk.rbox(Vector3(0, 0.03, 0), Vector3(0.72, 0.06, 0.3), Art.WALNUT, 0.06, Art.WALNUT.lightened(0.15))
	mk.push_at(Vector3(0, 0.06, 0), Vector3.ZERO, Vector3(0.36, 0.36, 0.36))
	ModelItems.trunk(mk, false)
	mk.pop()
	var stickers := [[Vector3(-0.2, 0.15, 0.093), Art.CORAL], [Vector3(0.22, 0.13, 0.093), Art.GOLD], [Vector3(0.17, 0.2, 0.093), Art.SAGE]]
	for s in stickers:
		var sp: Vector3 = s[0]
		mk.push_at(sp, Vector3(0, 0, 12))
		ModelItems.poly_xy(mk, ModelItems.circle_pts(0.03, 8), 0.006, s[1])
		mk.pop()

static func _moon_stand(mk: MeshKit) -> void:
	mk.cyl(Vector3.ZERO, 0.17, 0.05, Art.WALNUT.darkened(0.1), 10, Art.WALNUT.lightened(0.12))
	mk.cyl(Vector3(0, 0.05, 0), 0.025, 0.3, Art.BRASS, 6)
	mk.push_at(Vector3(0, 0.2, 0))
	_paper_moon(mk, 0.3, false)
	mk.pop()
	mk.push_at(Vector3(0, 0.5, -0.02), Vector3(90, 0, 0))
	mk.torus(Vector3.ZERO, 0.36, 0.02, Art.GOLD, 16, 3)
	mk.pop()

static func _garland(mk: MeshKit) -> void:
	var cols := [Art.CORAL, Art.GOLD, Art.SKY, Art.SAGE, Art.PLUM.lightened(0.1), Art.ROSE]
	for s in [-1.0, 1.0]:
		mk.cyl(Vector3(s * 0.55, 0, 0), 0.08, 0.04, Art.WALNUT.darkened(0.1), 8, Art.WALNUT.lightened(0.1))
		mk.cyl(Vector3(s * 0.55, 0.04, 0), 0.02, 0.72, Art.WALNUT.lightened(0.05), 5)
		mk.sphere(Vector3(s * 0.55, 0.77, 0), 0.035, Art.GOLD, 2, 6)
	var n := 9
	var prev := Vector3(-0.55, 0.72, 0)
	for i in n:
		var t := float(i + 1) / (n + 1)
		var p := Vector3(-0.55 + 1.1 * t, 0.72 - sin(t * PI) * 0.16, 0)
		ModelItems.rod(mk, prev, p, 0.006, Art.INK.lightened(0.25), 4)
		prev = p
		mk.push_at(p)
		if i == n / 2:
			ModelItems.poly_xy(mk, _heart_pts(0.07), 0.016, Art.CORAL.darkened(0.06), Art.CORAL, Vector2(0, -0.01))
		else:
			ModelItems.poly_xy(mk, [Vector2(-0.045, 0), Vector2(0.045, 0), Vector2(0, -0.09)], 0.008, cols[i % cols.size()])
		mk.pop()
	ModelItems.rod(mk, prev, Vector3(0.55, 0.72, 0), 0.006, Art.INK.lightened(0.25), 4)

static func _heart_pts(s: float) -> Array:
	var pts: Array = []
	for i in 16:
		var t := TAU * i / 16.0
		var x := 16.0 * pow(sin(t), 3)
		var y := 13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t)
		pts.append(Vector2(x, y) * s / 17.0)
	return pts
