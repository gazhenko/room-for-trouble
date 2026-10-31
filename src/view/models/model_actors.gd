class_name ModelActors
extends RefCounted
## Procedural character models (§3.2, §3.3, §17). Characters face +z.
## Staff share one footprint; silhouette/material swaps never alter timing.

const ACTOR_SCALE := 1.8   # toy proportions: a staffer is ~1.3 m on a 1 m tile (1.45 gave a 28 px avatar at 800p)

static func _eyes(mk: MeshKit, y: float, z: float, gap: float, r: float, white := true, pupil_col := Art.INK) -> void:
	for sx in [-1.0, 1.0]:
		if white:
			mk.sphere(Vector3(sx * gap, y, z), r, Color("#FFFDF6"), 3, 6, Vector3(1, 1.1, 0.6))
			mk.sphere(Vector3(sx * gap, y - r * 0.08, z + r * 0.45), r * 0.62, pupil_col, 3, 6, Vector3(1, 1.15, 0.5))
			mk.sphere(Vector3(sx * gap + r * 0.22, y + r * 0.3, z + r * 0.75), r * 0.2, Color.WHITE, 2, 4)
		else:
			mk.sphere(Vector3(sx * gap, y, z), r, pupil_col, 3, 6, Vector3(1, 1.2, 0.5))

static func _cheeks(mk: MeshKit, y: float, z: float, gap: float, col := Color("#F2A7B5")) -> void:
	for sx in [-1.0, 1.0]:
		mk.sphere(Vector3(sx * gap, y, z), 0.045, col, 2, 5, Vector3(1.2, 0.7, 0.4))

static func _cap(rig: ActorRig, parent: Node3D, pos: Vector3, cos: Dictionary, scale_f := 1.0, tilt := -10.0) -> void:
	var mk := MeshKit.new()
	var cap_col: Color = Color(cos.get("cap", "#E88D79"))
	var trim: Color = Color(cos.get("trim", "#F7EAD6"))
	mk.cyl(Vector3(0, 0, 0), 0.15 * scale_f, 0.13 * scale_f, cap_col, 8, cap_col.lightened(0.12), 0.135 * scale_f)
	mk.cyl(Vector3(0, 0.0, 0), 0.155 * scale_f, 0.035 * scale_f, Art.GOLD, 8)
	mk.box(Vector3(0, 0.005, 0.15 * scale_f), Vector3(0.2 * scale_f, 0.02, 0.09 * scale_f), Art.INK)
	mk.sphere(Vector3(0, 0.15 * scale_f, 0), 0.03 * scale_f, trim, 2, 5)
	var n := rig.extra("cap", parent, pos)
	n.rotation_degrees = Vector3(tilt, 0, 6)
	rig.part(n, mk, Vector3.ZERO, "CapMesh")

static func _scarf(mk: MeshKit, y: float, r: float, cos: Dictionary) -> void:
	var sc: Color = Color(cos.get("scarf", "#E8BF66"))
	mk.torus(Vector3(0, y, 0), r, 0.05, sc, 10, 4)
	mk.box(Vector3(r * 0.45, y - 0.09, r * 0.85), Vector3(0.08, 0.16, 0.04), sc.darkened(0.08))

static func staff(id: String, cos: Dictionary) -> ActorRig:
	var rig := ActorRig.new()
	rig.name = "Staff_" + id
	match id:
		"pip": _pip(rig, cos)
		"pebble": _pebble(rig, cos)
		"moss": _moss(rig, cos)
		_: _button(rig, cos)
	rig.scale = Vector3.ONE * ACTOR_SCALE
	return rig

static func _limb_pair(rig: ActorRig, mk_fn: Callable, shoulder: Vector3, hip: Vector3, arm_col: Color, leg_col: Color, arm_len := 0.22, leg_len := 0.14) -> void:
	rig.arm_l.position = Vector3(shoulder.x, shoulder.y, shoulder.z)
	rig.arm_r.position = Vector3(-shoulder.x, shoulder.y, shoulder.z)
	for a in [rig.arm_l, rig.arm_r]:
		var mk := MeshKit.new()
		mk.sphere(Vector3(0, -arm_len * 0.5, 0), 0.055, arm_col, 3, 6, Vector3(1, arm_len / 0.11, 1))
		mk.sphere(Vector3(0, -arm_len, 0.0), 0.06, arm_col.lightened(0.06), 3, 6)
		rig.part(a, mk, Vector3.ZERO)
	rig.leg_l.position = Vector3(hip.x, hip.y, hip.z)
	rig.leg_r.position = Vector3(-hip.x, hip.y, hip.z)
	for l in [rig.leg_l, rig.leg_r]:
		var mk2 := MeshKit.new()
		mk2.sphere(Vector3(0, -leg_len * 0.6, 0.03), 0.075, leg_col, 3, 6, Vector3(1, 0.8, 1.35))
		rig.part(l, mk2, Vector3.ZERO)

static func _pip(rig: ActorRig, cos: Dictionary) -> void:
	rig.setup("biped", 0.72)
	var fur := Color("#6B5B95")
	var belly := Color("#A99BCF")
	var mk := MeshKit.new()
	mk.sphere(Vector3(0, 0.36, 0), 0.27, fur, 5, 9, Vector3(1, 0.95, 0.95))
	mk.sphere(Vector3(0, 0.3, 0.13), 0.17, belly, 4, 8, Vector3(1, 1.1, 0.7))
	_scarf(mk, 0.22, 0.2, cos)
	rig.part(rig.torso, mk, Vector3.ZERO, "TorsoMesh")
	rig.head.position = Vector3(0, 0.0, 0)
	var hm := MeshKit.new()
	_eyes(hm, 0.44, 0.22, 0.095, 0.075)
	_cheeks(hm, 0.36, 0.24, 0.16)
	hm.cone(Vector3(0, 0.33, 0.27), 0.03, 0.05, Color("#F2A7B5"), 4)
	rig.part(rig.head, hm, Vector3.ZERO, "Face")
	for side in [1.0, -1.0]:
		var en := rig.extra("ear_l" if side > 0 else "ear_r", rig.head, Vector3(side * 0.14, 0.55, -0.02))
		var em := MeshKit.new()
		em.cone(Vector3(0, 0, 0), 0.085, 0.24, fur, 4)
		em.cone(Vector3(0, 0.02, 0.03), 0.05, 0.16, Color("#E8A0B4"), 4)
		rig.part(en, em, Vector3.ZERO)
	_cap(rig, rig.head, Vector3(0.02, 0.6, 0.0), cos, 1.05, -14.0)
	# Wings as arms.
	rig.arm_l.position = Vector3(0.24, 0.42, 0)
	rig.arm_r.position = Vector3(-0.24, 0.42, 0)
	for a in [rig.arm_l, rig.arm_r]:
		var wm := MeshKit.new()
		var s := 1.0 if a == rig.arm_l else -1.0
		wm.tri(Vector3(0, 0, 0), Vector3(s * 0.08, -0.28, 0.0), Vector3(s * 0.2, -0.12, 0), fur.darkened(0.1))
		wm.tri(Vector3(0, 0, 0), Vector3(s * 0.2, -0.12, 0), Vector3(s * 0.08, -0.28, 0.0), fur.darkened(0.25))
		wm.sphere(Vector3(s * 0.04, -0.06, 0), 0.06, fur, 3, 6)
		rig.part(a, wm, Vector3.ZERO)
	rig.leg_l.position = Vector3(0.1, 0.1, 0.02)
	rig.leg_r.position = Vector3(-0.1, 0.1, 0.02)
	for l in [rig.leg_l, rig.leg_r]:
		var lm := MeshKit.new()
		lm.sphere(Vector3(0, -0.05, 0.03), 0.07, Color("#3E3557"), 3, 6, Vector3(1, 0.7, 1.3))
		rig.part(l, lm, Vector3.ZERO)

static func _pebble(rig: ActorRig, cos: Dictionary) -> void:
	rig.setup("biped", 0.74)
	var stone := Color("#9DA4AE")
	var top := Color("#B9C0C8")
	var mk := MeshKit.new()
	mk.rbox(Vector3(0, 0.36, 0), Vector3(0.56, 0.5, 0.46), stone, 0.12, top)
	mk.rbox(Vector3(0, 0.63, 0), Vector3(0.46, 0.08, 0.38), top, 0.1)
	for i in 2:
		mk.sphere(Vector3(0, 0.3 - i * 0.12, 0.235), 0.038, Art.GOLD, 2, 6)
	mk.box(Vector3(0.12, 0.45, 0.2), Vector3(0.1, 0.06, 0.08), stone.darkened(0.08))
	_scarf(mk, 0.13, 0.27, cos)
	rig.part(rig.torso, mk, Vector3.ZERO, "TorsoMesh")
	var hm := MeshKit.new()
	_eyes(hm, 0.47, 0.23, 0.11, 0.07)
	_cheeks(hm, 0.39, 0.235, 0.19)
	hm.box(Vector3(0, 0.38, 0.235), Vector3(0.08, 0.025, 0.02), Art.INK)
	rig.part(rig.head, hm, Vector3.ZERO, "Face")
	_cap(rig, rig.head, Vector3(-0.05, 0.69, 0), cos, 0.95, -6.0)
	_limb_pair(rig, Callable(), Vector3(0.3, 0.46, 0.02), Vector3(0.13, 0.12, 0.0), stone.darkened(0.06), stone.darkened(0.18), 0.2, 0.12)

static func _moss(rig: ActorRig, cos: Dictionary) -> void:
	rig.setup("biped", 0.8)
	var tunic := Color("#F2E6C9")
	var vest := Color("#8BAE91")
	var skin := Color("#E7B58F")
	var mk := MeshKit.new()
	mk.sphere(Vector3(0, 0.28, 0), 0.2, tunic, 4, 8, Vector3(1, 1.15, 0.95))
	mk.sphere(Vector3(0, 0.3, 0.02), 0.205, vest, 4, 8, Vector3(1.02, 0.9, 0.9))
	mk.box(Vector3(0, 0.3, 0.19), Vector3(0.08, 0.26, 0.02), tunic)
	_scarf(mk, 0.44, 0.15, cos)
	rig.part(rig.torso, mk, Vector3.ZERO, "TorsoMesh")
	var hm := MeshKit.new()
	hm.sphere(Vector3(0, 0.6, 0), 0.2, skin, 4, 8)
	_eyes(hm, 0.62, 0.17, 0.08, 0.06)
	_cheeks(hm, 0.55, 0.18, 0.13)
	hm.box(Vector3(0, 0.53, 0.195), Vector3(0.05, 0.02, 0.02), Art.INK)
	rig.part(rig.head, hm, Vector3.ZERO, "Head")
	var leaves := rig.extra("leaves", rig.head, Vector3(0, 0.74, -0.02))
	var lm := MeshKit.new()
	for i in 7:
		var a := TAU * i / 7.0
		lm.push_at(Vector3(cos(a) * 0.12, 0.0, sin(a) * 0.1 - 0.02), Vector3(sin(a) * 40.0, 0, -cos(a) * 40.0))
		lm.sphere(Vector3(0, 0.06, 0), 0.075, Art.LEAF.lightened(0.05 * (i % 3)), 2, 5, Vector3(0.7, 1.6, 0.35))
		lm.pop()
	rig.part(leaves, lm, Vector3.ZERO)
	_cap(rig, rig.head, Vector3(0.0, 0.79, 0.02), cos, 0.75, -8.0)
	_limb_pair(rig, Callable(), Vector3(0.21, 0.4, 0), Vector3(0.09, 0.12, 0), skin, Color("#7A5440"), 0.2, 0.12)

static func _button(rig: ActorRig, cos: Dictionary) -> void:
	rig.setup("biped", 0.76)
	var plush := Color("#9ECFDA")
	var mk := MeshKit.new()
	mk.sphere(Vector3(0, 0.27, 0), 0.22, plush, 4, 8, Vector3(1, 1.05, 0.95))
	mk.box(Vector3(0, 0.27, 0.205), Vector3(0.02, 0.32, 0.02), plush.darkened(0.3))
	for i in 3:
		mk.box(Vector3(0, 0.15 + i * 0.1, 0.212), Vector3(0.06, 0.012, 0.012), plush.darkened(0.3))
	_scarf(mk, 0.43, 0.15, cos)
	rig.part(rig.torso, mk, Vector3.ZERO, "TorsoMesh")
	var hm := MeshKit.new()
	hm.sphere(Vector3(0, 0.6, 0), 0.21, plush, 4, 8, Vector3(1.05, 0.95, 1))
	for sx in [-1.0, 1.0]:
		hm.cyl(Vector3(sx * 0.085, 0.63, 0.18), 0.055, 0.03, Art.INK, 8, Color("#4A5A63"))
		hm.push_at(Vector3(sx * 0.085, 0.63, 0.21), Vector3(90, 0, 0))
		hm.pop()
	_cheeks(hm, 0.55, 0.19, 0.14)
	hm.box(Vector3(0, 0.54, 0.205), Vector3(0.06, 0.018, 0.02), Art.INK)
	rig.part(rig.head, hm, Vector3.ZERO, "Head")
	for side in [1.0, -1.0]:
		var en := rig.extra("ears_flop_l" if side > 0 else "ears_flop_r", rig.head, Vector3(side * 0.13, 0.76, -0.02))
		var em := MeshKit.new()
		em.sphere(Vector3(side * 0.06, -0.14, 0), 0.07, plush.darkened(0.04), 3, 6, Vector3(0.75, 2.6, 0.45))
		em.sphere(Vector3(side * 0.065, -0.14, 0.02), 0.045, Color("#F6C9D3"), 3, 6, Vector3(0.6, 2.2, 0.3))
		rig.part(en, em, Vector3.ZERO)
	_cap(rig, rig.head, Vector3(0.0, 0.79, 0.0), cos, 0.82, -10.0)
	_limb_pair(rig, Callable(), Vector3(0.22, 0.38, 0), Vector3(0.1, 0.1, 0), plush, plush.darkened(0.1), 0.18, 0.1)

# ---------------------------------------------------------------- guests

static func guest(fam: String, variant: String) -> ActorRig:
	var rig := ActorRig.new()
	rig.name = "Guest_" + fam
	match fam:
		"slime": _slime(rig, variant)
		"yeti": _yeti(rig, variant)
		"dragon": _dragon(rig, variant)
		"ghost": _ghost(rig, variant)
		"moonwolf": _wolf(rig, variant)
		_: _sprout(rig, variant)
	rig.scale = Vector3.ONE * ACTOR_SCALE
	return rig

static func _variant_tint(base: Color, variant: String) -> Color:
	if variant != "":
		return base
	return base

static func _slime(rig: ActorRig, variant: String) -> void:
	rig.setup("blob", 0.7)
	var c := Color("#7FCFAE")
	var mk := MeshKit.new()
	mk.sphere(Vector3(0, 0.3, 0), 0.36, c, 5, 10, Vector3(1.0, 0.86, 1.0), c.darkened(0.08))
	mk.sphere(Vector3(-0.14, 0.5, 0.16), 0.07, Color("#E9FFF6"), 2, 5, Vector3(1, 0.7, 0.6))
	_eyes(mk, 0.42, 0.29, 0.11, 0.085)
	mk.sphere(Vector3(0, 0.3, 0.33), 0.06, Color("#3B6B5A"), 2, 6, Vector3(1.4, 0.55, 0.4))
	_cheeks(mk, 0.33, 0.31, 0.2)
	rig.part(rig.torso, mk, Vector3.ZERO, "Blob")
	# Slippers (shown once the welcome gift is installed).
	var sl := rig.extra("slippers", rig.body, Vector3.ZERO)
	var sm := MeshKit.new()
	for sx in [-0.14, 0.14]:
		sm.rbox(Vector3(sx, 0.04, 0.12), Vector3(0.14, 0.08, 0.26), Color("#F28CB1"), 0.05, Color("#F7B6CF"))
		sm.sphere(Vector3(sx, 0.09, 0.2), 0.035, Color.WHITE, 2, 5)
	rig.part(sl, sm, Vector3.ZERO)
	sl.visible = false
	rig.hold.position = Vector3(0, 0.72, 0.15)

static func _yeti(rig: ActorRig, variant: String) -> void:
	rig.setup("biped", 1.05)
	var fur := Color("#EAF3F8")
	var face := Color("#BCD8E6")
	var mk := MeshKit.new()
	mk.jitter = 0.06
	mk.sphere(Vector3(0, 0.42, 0), 0.36, fur, 5, 9, Vector3(1, 1.05, 0.92))
	mk.sphere(Vector3(0, 0.36, 0.16), 0.2, Color.WHITE, 3, 7, Vector3(1, 1.2, 0.6))
	rig.part(rig.torso, mk, Vector3.ZERO, "TorsoMesh")
	var hm := MeshKit.new()
	hm.jitter = 0.06
	hm.sphere(Vector3(0, 0.88, 0), 0.25, fur, 4, 8)
	hm.sphere(Vector3(0, 0.84, 0.15), 0.16, face, 3, 7, Vector3(1.1, 0.9, 0.6))
	_eyes(hm, 0.89, 0.24, 0.075, 0.055, false)
	hm.sphere(Vector3(0, 0.82, 0.27), 0.04, Color("#5C7A8C"), 2, 5)
	_cheeks(hm, 0.8, 0.25, 0.12, Color("#F4B9C6"))
	rig.part(rig.head, hm, Vector3.ZERO, "Head")
	# Tiny knitted travel hat with pompom.
	var hat := rig.extra("cap", rig.head, Vector3(0.04, 1.08, 0))
	hat.rotation_degrees = Vector3(-8, 0, 12)
	var hk := MeshKit.new()
	hk.cyl(Vector3(0, 0, 0), 0.12, 0.06, Color("#F7EAD6"), 8)
	hk.cone(Vector3(0, 0.06, 0), 0.11, 0.17, Color("#E36B6B"), 8)
	hk.sphere(Vector3(0, 0.25, 0), 0.05, Color.WHITE, 2, 5)
	rig.part(hat, hk, Vector3.ZERO)
	rig.arm_l.position = Vector3(0.36, 0.6, 0)
	rig.arm_r.position = Vector3(-0.36, 0.6, 0)
	for a in [rig.arm_l, rig.arm_r]:
		var am := MeshKit.new()
		am.jitter = 0.06
		am.sphere(Vector3(0, -0.17, 0), 0.1, fur.darkened(0.03), 3, 7, Vector3(1, 1.9, 1))
		am.sphere(Vector3(0, -0.34, 0.02), 0.075, face, 3, 6)
		rig.part(a, am, Vector3.ZERO)
	rig.leg_l.position = Vector3(0.15, 0.12, 0)
	rig.leg_r.position = Vector3(-0.15, 0.12, 0)
	for l in [rig.leg_l, rig.leg_r]:
		var lm := MeshKit.new()
		lm.sphere(Vector3(0, -0.05, 0.04), 0.1, face, 3, 6, Vector3(1, 0.65, 1.3))
		rig.part(l, lm, Vector3.ZERO)
	rig.hold.position = Vector3(0, 1.25, 0.2)

static func _dragon(rig: ActorRig, variant: String) -> void:
	rig.setup("biped", 0.95)
	var scale_c := Color("#E9805E")
	var belly := Color("#F6D7A7")
	var mk := MeshKit.new()
	mk.sphere(Vector3(0, 0.36, 0), 0.29, scale_c, 4, 9, Vector3(1, 1.05, 0.95))
	mk.sphere(Vector3(0, 0.32, 0.14), 0.19, belly, 3, 7, Vector3(1, 1.25, 0.6))
	rig.part(rig.torso, mk, Vector3.ZERO, "TorsoMesh")
	var hm := MeshKit.new()
	hm.sphere(Vector3(0, 0.78, 0), 0.21, scale_c, 4, 8)
	# Kettle-shaped snout with a tiny spout.
	hm.push_at(Vector3(0, 0.73, 0.18), Vector3(90, 0, 0))
	hm.cyl(Vector3(0, 0, 0), 0.11, 0.13, scale_c.lightened(0.08), 8, belly, 0.09)
	hm.pop()
	hm.cyl(Vector3(0.0, 0.79, 0.27), 0.025, 0.09, scale_c.darkened(0.1), 5)
	for sx in [-1.0, 1.0]:
		hm.sphere(Vector3(sx * 0.04, 0.72, 0.32), 0.018, Art.INK, 2, 4)
		hm.cone(Vector3(sx * 0.1, 0.95, -0.03), 0.04, 0.11, belly, 5)
	_eyes(hm, 0.84, 0.15, 0.085, 0.06)
	rig.part(rig.head, hm, Vector3.ZERO, "Head")
	for side in [1.0, -1.0]:
		var wn := rig.extra("wing_l" if side > 0 else "wing_r", rig.torso, Vector3(side * 0.16, 0.5, -0.18))
		var wm := MeshKit.new()
		wm.tri(Vector3(0, 0, 0), Vector3(side * 0.28, 0.16, -0.05), Vector3(side * 0.22, -0.1, -0.05), Color("#B76AA5"))
		wm.tri(Vector3(0, 0, 0), Vector3(side * 0.22, -0.1, -0.05), Vector3(side * 0.28, 0.16, -0.05), Color("#8F4E85"))
		rig.part(wn, wm, Vector3.ZERO)
	var tail := rig.extra("tail", rig.torso, Vector3(0, 0.2, -0.24))
	var tm := MeshKit.new()
	tm.push_at(Vector3(0, 0, 0), Vector3(-70, 0, 0))
	tm.cone(Vector3(0, 0, 0), 0.1, 0.36, scale_c.darkened(0.06), 6)
	tm.pop()
	rig.part(tail, tm, Vector3.ZERO)
	_limb_pair(rig, Callable(), Vector3(0.27, 0.48, 0.04), Vector3(0.13, 0.12, 0), scale_c.darkened(0.04), scale_c.darkened(0.15), 0.17, 0.12)
	rig.hold.position = Vector3(0, 1.1, 0.2)

static func _ghost(rig: ActorRig, variant: String) -> void:
	rig.setup("float", 0.9)
	var sheet := Color("#F4F1FA")
	var mk := MeshKit.new()
	mk.sphere(Vector3(0, 0.62, 0), 0.27, sheet, 4, 9, Vector3(1, 1.0, 0.95))
	mk.cyl(Vector3(0, 0.12, 0), 0.31, 0.5, sheet.darkened(0.04), 9, null, 0.27)
	for i in 9:
		var a := TAU * (i + 0.5) / 9.0
		mk.sphere(Vector3(cos(a) * 0.27, 0.12, sin(a) * 0.27), 0.07, sheet.darkened(0.06), 2, 5)
	for sx in [-1.0, 1.0]:
		mk.sphere(Vector3(sx * 0.09, 0.66, 0.24), 0.055, Art.INK, 3, 6, Vector3(0.8, 1.3, 0.4))
	_cheeks(mk, 0.58, 0.25, 0.16, Color("#F6B8C8"))
	mk.sphere(Vector3(0, 0.55, 0.26), 0.035, Art.INK, 2, 5, Vector3(1, 1.3, 0.4))
	rig.part(rig.torso, mk, Vector3.ZERO, "Sheet")
	rig.arm_l.position = Vector3(0.28, 0.45, 0)
	rig.arm_r.position = Vector3(-0.28, 0.45, 0)
	for a in [rig.arm_l, rig.arm_r]:
		var am := MeshKit.new()
		am.sphere(Vector3(0, -0.08, 0), 0.06, sheet, 3, 5, Vector3(1, 1.6, 1))
		rig.part(a, am, Vector3.ZERO)
	var mask := rig.extra("mask", rig.head, Vector3(0, 0.76, 0.22))
	var mm := MeshKit.new()
	mm.box(Vector3(0, 0, 0), Vector3(0.36, 0.08, 0.06), Color("#3E4C7A"))
	mm.sphere(Vector3(0.09, 0.0, 0.035), 0.025, Art.GOLD, 2, 4)
	rig.part(mask, mm, Vector3.ZERO)
	mask.visible = false
	rig.hold.position = Vector3(0, 1.05, 0.2)

static func _wolf(rig: ActorRig, variant: String) -> void:
	rig.setup("biped", 1.05)
	var fur := Color("#9C8FC0")
	var chest := Color("#E9E2F5")
	var mk := MeshKit.new()
	mk.sphere(Vector3(0, 0.42, 0), 0.29, fur, 4, 9, Vector3(1, 1.15, 0.9))
	mk.sphere(Vector3(0, 0.5, 0.14), 0.18, chest, 3, 7, Vector3(1, 1.2, 0.6))
	rig.part(rig.torso, mk, Vector3.ZERO, "TorsoMesh")
	var hm := MeshKit.new()
	hm.sphere(Vector3(0, 0.9, 0), 0.22, fur, 4, 8)
	hm.sphere(Vector3(0, 0.84, 0.17), 0.11, chest, 3, 7, Vector3(1, 0.8, 1.2))
	hm.sphere(Vector3(0, 0.86, 0.29), 0.035, Art.INK, 2, 5)
	for sx in [-1.0, 1.0]:
		hm.cone(Vector3(sx * 0.12, 1.04, -0.02), 0.07, 0.18, fur.darkened(0.08), 4)
	_eyes(hm, 0.95, 0.17, 0.08, 0.058)
	# Crescent moon mark.
	hm.sphere(Vector3(0.0, 1.06, 0.18), 0.045, Art.GOLD, 2, 6, Vector3(1.2, 1, 0.3))
	hm.sphere(Vector3(0.02, 1.07, 0.2), 0.04, fur, 2, 6, Vector3(1.1, 1, 0.3))
	rig.part(rig.head, hm, Vector3.ZERO, "Head")
	var tail := rig.extra("tail", rig.torso, Vector3(0, 0.25, -0.26))
	var tm := MeshKit.new()
	tm.sphere(Vector3(0, 0.08, -0.12), 0.11, fur.lightened(0.05), 3, 6, Vector3(0.9, 0.9, 1.9))
	tm.sphere(Vector3(0, 0.12, -0.3), 0.07, chest, 2, 5)
	rig.part(tail, tm, Vector3.ZERO)
	_limb_pair(rig, Callable(), Vector3(0.27, 0.6, 0.03), Vector3(0.12, 0.14, 0), fur.darkened(0.05), fur.darkened(0.18), 0.22, 0.14)
	rig.hold.position = Vector3(0, 1.25, 0.2)

static func _sprout(rig: ActorRig, variant: String) -> void:
	rig.setup("biped", 0.95)
	var pot := Color("#D9825B")
	var green := Color("#86B86A")
	var mk := MeshKit.new()
	mk.cyl(Vector3(0, 0.0, 0), 0.22, 0.32, pot, 8, pot.lightened(0.1), 0.28)
	mk.cyl(Vector3(0, 0.3, 0), 0.31, 0.07, pot.lightened(0.08), 8)
	mk.sphere(Vector3(0, 0.52, 0), 0.24, green, 4, 8, Vector3(1, 0.95, 0.95))
	_eyes(mk, 0.56, 0.2, 0.08, 0.06)
	_cheeks(mk, 0.48, 0.21, 0.14)
	mk.box(Vector3(0, 0.45, 0.225), Vector3(0.06, 0.02, 0.02), Art.INK)
	rig.part(rig.torso, mk, Vector3.ZERO, "TorsoMesh")
	var leaves := rig.extra("leaves", rig.head, Vector3(0, 0.74, 0))
	var lm := MeshKit.new()
	for i in 5:
		var a := TAU * i / 5.0 + 0.3
		lm.push_at(Vector3(cos(a) * 0.06, 0, sin(a) * 0.06), Vector3(sin(a) * 50.0, 0, -cos(a) * 50.0))
		lm.sphere(Vector3(0, 0.12, 0), 0.09, Art.LEAF.lightened(0.04 * (i % 2)), 2, 5, Vector3(0.65, 1.7, 0.3))
		lm.pop()
	rig.part(leaves, lm, Vector3.ZERO)
	var flower := rig.extra("flower", rig.head, Vector3(0.03, 0.88, 0.02))
	var fm := MeshKit.new()
	for i in 5:
		var a2 := TAU * i / 5.0
		fm.sphere(Vector3(cos(a2) * 0.07, 0.0, sin(a2) * 0.07), 0.05, Color("#F49AB8"), 2, 5, Vector3(1, 0.5, 1))
	fm.sphere(Vector3(0, 0.02, 0), 0.04, Art.GOLD, 2, 5)
	rig.part(flower, fm, Vector3.ZERO)
	flower.scale = Vector3.ONE * 0.55
	rig.arm_l.position = Vector3(0.23, 0.55, 0)
	rig.arm_r.position = Vector3(-0.23, 0.55, 0)
	for a3 in [rig.arm_l, rig.arm_r]:
		var am := MeshKit.new()
		am.sphere(Vector3(0, -0.1, 0), 0.06, Art.LEAF, 2, 5, Vector3(0.7, 2.0, 0.4))
		rig.part(a3, am, Vector3.ZERO)
	rig.leg_l.position = Vector3(0.1, 0.04, 0)
	rig.leg_r.position = Vector3(-0.1, 0.04, 0)
	for l in [rig.leg_l, rig.leg_r]:
		var rm := MeshKit.new()
		rm.sphere(Vector3(0, -0.02, 0.06), 0.06, Color("#A8724E"), 2, 5, Vector3(1, 0.5, 1.4))
		rig.part(l, rm, Vector3.ZERO)
	rig.hold.position = Vector3(0, 1.05, 0.2)

# ---------------------------------------------------------------- NPCs

static func npc(id: String) -> ActorRig:
	var rig := ActorRig.new()
	rig.name = "Npc_" + id
	match id:
		"nana": _nana(rig)
		"gus": _gus(rig)
		_: _dot(rig)
	rig.scale = Vector3.ONE * ACTOR_SCALE
	return rig

static func _nana(rig: ActorRig) -> void:
	rig.setup("biped", 1.05)
	var stone := Color("#A79DB0")
	var shawl := Color("#E88D79")
	var mk := MeshKit.new()
	mk.sphere(Vector3(0, 0.4, 0), 0.33, stone, 4, 9, Vector3(1, 1.05, 0.95))
	mk.cone(Vector3(0, 0.45, 0), 0.36, 0.3, shawl, 9)
	mk.sphere(Vector3(0, 0.55, 0.2), 0.05, Art.GOLD, 2, 5)
	rig.part(rig.torso, mk, Vector3.ZERO, "TorsoMesh")
	var hm := MeshKit.new()
	hm.sphere(Vector3(0, 0.88, 0), 0.25, stone.lightened(0.06), 4, 8)
	for sx in [-1.0, 1.0]:
		hm.cone(Vector3(sx * 0.14, 1.05, -0.04), 0.05, 0.12, stone.darkened(0.15), 4)
		hm.torus(Vector3(sx * 0.09, 0.91, 0.22), 0.06, 0.012, Art.GOLD, 8, 3)
	_eyes(hm, 0.91, 0.22, 0.09, 0.045, false)
	_cheeks(hm, 0.82, 0.23, 0.15)
	hm.box(Vector3(0, 0.8, 0.245), Vector3(0.09, 0.02, 0.02), Art.INK)
	hm.sphere(Vector3(0, 1.1, -0.06), 0.1, Color("#DDD6E3"), 2, 6, Vector3(1.3, 0.7, 1.0))
	rig.part(rig.head, hm, Vector3.ZERO, "Head")
	for side in [1.0, -1.0]:
		var wn := rig.extra("wing_l" if side > 0 else "wing_r", rig.torso, Vector3(side * 0.18, 0.62, -0.22))
		var wm := MeshKit.new()
		wm.tri(Vector3(0, 0, 0), Vector3(side * 0.3, 0.2, -0.04), Vector3(side * 0.25, -0.12, -0.04), stone.darkened(0.1))
		wm.tri(Vector3(0, 0, 0), Vector3(side * 0.25, -0.12, -0.04), Vector3(side * 0.3, 0.2, -0.04), stone.darkened(0.25))
		rig.part(wn, wm, Vector3.ZERO)
	_limb_pair(rig, Callable(), Vector3(0.3, 0.55, 0.03), Vector3(0.13, 0.12, 0), stone, stone.darkened(0.2), 0.2, 0.12)

static func _gus(rig: ActorRig) -> void:
	rig.setup("box", 0.5)
	var leather := Color("#A0704B")
	var mk := MeshKit.new()
	mk.rbox(Vector3(0, 0.2, 0), Vector3(0.56, 0.22, 0.32), leather, 0.05, leather.lightened(0.1))
	for sx in [-0.18, 0.18]:
		mk.box(Vector3(sx, 0.2, 0.0), Vector3(0.05, 0.23, 0.33), leather.darkened(0.25))
	for cx in [-0.26, 0.26]:
		mk.box(Vector3(cx, 0.1, 0.15), Vector3(0.05, 0.05, 0.04), Art.BRASS)
	rig.part(rig.torso, mk, Vector3.ZERO, "Case")
	var lid := rig.extra("lid", rig.torso, Vector3(0, 0.31, -0.16))
	var lm := MeshKit.new()
	lm.rbox(Vector3(0, 0.07, 0.16), Vector3(0.56, 0.14, 0.32), leather.lightened(0.04), 0.05, leather.lightened(0.14))
	lm.box(Vector3(0, -0.005, 0.16), Vector3(0.5, 0.02, 0.26), Color("#E07A8C"))
	_eyes(lm, 0.08, 0.33, 0.12, 0.06)
	lm.box(Vector3(0, 0.15, 0.16), Vector3(0.2, 0.04, 0.05), Art.INK)
	lm.box(Vector3(0, 0.05, 0.33), Vector3(0.06, 0.05, 0.02), Art.BRASS)
	lm.box(Vector3(0.18, 0.1, 0.32), Vector3(0.1, 0.08, 0.01), Art.SKY)
	rig.part(lid, lm, Vector3.ZERO)
	rig.leg_l.position = Vector3(0.18, 0.08, 0.06)
	rig.leg_r.position = Vector3(-0.18, 0.08, 0.06)
	for l in [rig.leg_l, rig.leg_r]:
		var fm := MeshKit.new()
		fm.cyl(Vector3(0, -0.08, 0), 0.025, 0.08, Art.INK, 5)
		fm.sphere(Vector3(0, -0.08, 0.03), 0.04, Art.INK.lightened(0.1), 2, 5, Vector3(1, 0.6, 1.4))
		rig.part(l, fm, Vector3.ZERO)
	rig.hold.position = Vector3(0, 0.55, 0.0)

static func _dot(rig: ActorRig) -> void:
	rig.setup("float", 0.75)
	var fuzz := Color("#F3E7CF")
	var mk := MeshKit.new()
	mk.jitter = 0.06
	mk.sphere(Vector3(0, 0.36, 0), 0.2, fuzz, 4, 8, Vector3(1, 1.2, 0.95))
	mk.sphere(Vector3(0, 0.62, 0), 0.17, fuzz.lightened(0.05), 4, 8)
	_eyes(mk, 0.64, 0.14, 0.07, 0.05)
	for sx in [-1.0, 1.0]:
		mk.torus(Vector3(sx * 0.07, 0.64, 0.17), 0.045, 0.01, Art.INK, 8, 3)
	rig.part(rig.torso, mk, Vector3.ZERO, "TorsoMesh")
	for side in [1.0, -1.0]:
		var wn := rig.extra("wing_l" if side > 0 else "wing_r", rig.torso, Vector3(side * 0.12, 0.45, -0.12))
		var wm := MeshKit.new()
		wm.sphere(Vector3(side * 0.2, 0.08, -0.02), 0.16, Color("#D9CDEB"), 2, 6, Vector3(1.4, 1.2, 0.15))
		wm.sphere(Vector3(side * 0.24, 0.1, 0.0), 0.05, Art.PLUM, 2, 5, Vector3(1, 1, 0.2))
		rig.part(wn, wm, Vector3.ZERO)
	var ant := rig.extra("antenna", rig.torso, Vector3(0, 0.76, 0.02))
	var am := MeshKit.new()
	for sx2 in [-1.0, 1.0]:
		am.push_at(Vector3(sx2 * 0.05, 0, 0), Vector3(-15, 0, -sx2 * 25))
		am.cone(Vector3(0, 0, 0), 0.04, 0.2, Color("#C9B48C"), 4)
		am.pop()
	rig.part(ant, am, Vector3.ZERO)
	# The clipboard bigger than she is.
	var clip := rig.extra("clipboard", rig.torso, Vector3(0, 0.42, 0.24))
	var cm := MeshKit.new()
	cm.box(Vector3(0, 0, 0), Vector3(0.4, 0.5, 0.03), Art.WALNUT)
	cm.box(Vector3(0, -0.02, 0.02), Vector3(0.34, 0.42, 0.01), Art.WHITE)
	for i in 4:
		cm.box(Vector3(0.0, 0.12 - i * 0.08, 0.03), Vector3(0.24, 0.015, 0.005), Art.SKY.darkened(0.2))
	cm.box(Vector3(0, 0.24, 0.025), Vector3(0.12, 0.05, 0.02), Art.BRASS)
	rig.part(clip, cm, Vector3.ZERO)
	rig.arm_l.position = Vector3(0.18, 0.45, 0.05)
	rig.arm_r.position = Vector3(-0.18, 0.45, 0.05)
