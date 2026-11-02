class_name ActorRig
extends Node3D
## Procedural animation rig shared by staff, guests and NPCs. Implements the
## semantic animation API (§17.4): idle, walk, carry, work, handoff, wave, happy,
## concern, quirk_warn, quirk, helper, photo. Animation never changes gameplay.

var style := "biped"       # biped | blob | float | box | pot
var body: Node3D           # squash pivot at ground
var torso: Node3D          # upper body (bob)
var head: Node3D
var arm_l: Node3D
var arm_r: Node3D
var leg_l: Node3D
var leg_r: Node3D
var hold: Node3D           # held-item anchor
var extras: Dictionary = {} # name -> Node3D (ears, tail, lid, flower…)
var height := 0.9

var anim := "idle"
var speed := 0.0           # m/s
var carrying := false
var t := 0.0
var walk_phase := 0.0
var reduced_motion := false
var face_dir := 0.0        # target yaw (radians)
var dash_t := 0.0          # seconds left of the Quick Step stretch
var _yaw := 0.0
var _anim_t := 0.0
var _prev_anim := ""
var _prev_speed := 0.0

## Quick Step: a short stretch along the body axis, dust at the feet is the view's job.
func set_dash() -> void:
	dash_t = 0.22

func setup(st: String, h: float) -> void:
	style = st
	height = h
	body = Node3D.new(); body.name = "Body"; add_child(body)
	torso = Node3D.new(); torso.name = "Torso"; body.add_child(torso)
	head = Node3D.new(); head.name = "Head"; torso.add_child(head)
	arm_l = Node3D.new(); arm_l.name = "ArmL"; torso.add_child(arm_l)
	arm_r = Node3D.new(); arm_r.name = "ArmR"; torso.add_child(arm_r)
	leg_l = Node3D.new(); leg_l.name = "LegL"; body.add_child(leg_l)
	leg_r = Node3D.new(); leg_r.name = "LegR"; body.add_child(leg_r)
	hold = Node3D.new(); hold.name = "Hold"; torso.add_child(hold)
	hold.position = Vector3(0, h * 0.92 + 0.1, 0.22)

var skinned: MeshInstance3D       # all toon parts baked into one skinned mesh
var _skel: Skeleton3D
var _bones: Array = []             # [pivot Node3D, bone index]

func _ready() -> void:
	bake()

## Bakes every part that uses the shared toon material into one skinned mesh
## whose bones follow the existing pivot nodes, so an actor costs one draw call
## (plus one shadow) instead of one per part. Animation still moves the pivots;
## _sync_bones() copies their transforms to the skeleton each tick. Parts that
## are toggled on their own (slippers, mask) stay separate nodes.
func bake() -> void:
	if _skel != null or body == null:
		return
	var toon := Art.toon()
	var separate: Array = []
	for k in ["slippers", "mask"]:
		if extras.has(k):
			separate.append(extras[k])
	var parts: Array = []
	for n in find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.material_override != toon or mi.mesh == null or mi.mesh.get_surface_count() != 1:
			continue
		var skip := false
		for sep in separate:
			if (sep as Node).is_ancestor_of(mi):
				skip = true
		if not skip:
			parts.append(mi)
	if parts.size() < 2:
		return
	_skel = Skeleton3D.new()
	_skel.name = "Skel"
	add_child(_skel)
	var bone_of := {}
	for mi in parts:
		_bone_for(mi.get_parent(), bone_of)
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	for mi in parts:
		var bi: int = bone_of[mi.get_parent()]
		var xf: Transform3D = _skel.get_bone_global_rest(bi) * mi.transform
		var arr := (mi.mesh as Mesh).surface_get_arrays(0)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var nn: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var c: PackedColorArray = arr[Mesh.ARRAY_COLOR]
		var u = arr[Mesh.ARRAY_TEX_UV]
		for i in v.size():
			verts.append(xf * v[i])
			norms.append((xf.basis * nn[i]).normalized() if i < nn.size() else Vector3.UP)
			cols.append(c[i] if i < c.size() else Color.WHITE)
			uvs.append((u as PackedVector2Array)[i] if u is PackedVector2Array and i < (u as PackedVector2Array).size() else Vector2.ZERO)
			bones.append_array([bi, 0, 0, 0])
			weights.append_array([1.0, 0.0, 0.0, 0.0])
		mi.get_parent().remove_child(mi)
		mi.queue_free()
	var a: Array = []
	a.resize(Mesh.ARRAY_MAX)
	a[Mesh.ARRAY_VERTEX] = verts
	a[Mesh.ARRAY_NORMAL] = norms
	a[Mesh.ARRAY_COLOR] = cols
	a[Mesh.ARRAY_TEX_UV] = uvs
	a[Mesh.ARRAY_BONES] = bones
	a[Mesh.ARRAY_WEIGHTS] = weights
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
	var skin := Skin.new()
	for i in _skel.get_bone_count():
		skin.add_bind(i, _skel.get_bone_global_rest(i).affine_inverse())
	skinned = MeshInstance3D.new()
	skinned.name = "SkinnedBody"
	skinned.mesh = m
	skinned.skin = skin
	skinned.material_override = toon
	_skel.add_child(skinned)
	skinned.skeleton = NodePath("..")
	_sync_bones()

func _bone_for(n: Node, bone_of: Dictionary) -> int:
	if bone_of.has(n):
		return bone_of[n]
	var parent_idx := -1
	var rest := Transform3D.IDENTITY
	if n != self:
		parent_idx = _bone_for(n.get_parent(), bone_of)
		rest = (n as Node3D).transform
	var idx := _skel.get_bone_count()
	_skel.add_bone("b%d_%s" % [idx, n.name])
	if parent_idx >= 0:
		_skel.set_bone_parent(idx, parent_idx)
	_skel.set_bone_rest(idx, rest)
	bone_of[n] = idx
	if n != self:
		_bones.append([n, idx])
	return idx

func _sync_bones() -> void:
	for e in _bones:
		var n: Node3D = e[0]
		var i: int = e[1]
		_skel.set_bone_pose_position(i, n.position)
		_skel.set_bone_pose_rotation(i, n.quaternion)
		_skel.set_bone_pose_scale(i, n.scale)

func part(parent: Node3D, mk: MeshKit, pos: Vector3, name_s := "") -> MeshInstance3D:
	var mi := Art.mesh_instance(mk.commit(), Art.toon())
	mi.position = pos
	if name_s != "":
		mi.name = name_s
	parent.add_child(mi)
	return mi

func extra(name_s: String, parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.name = name_s
	n.position = pos
	parent.add_child(n)
	extras[name_s] = n
	return n

func set_anim(a: String) -> void:
	if a != anim:
		_prev_anim = anim
		anim = a
		_anim_t = 0.0

func tick(dt: float) -> void:
	t += dt
	_anim_t += dt
	var rm := 0.35 if reduced_motion else 1.0
	# Smooth facing.
	var dy := wrapf(face_dir - _yaw, -PI, PI)
	_yaw += dy * minf(1.0, dt * 14.0)
	rotation.y = _yaw
	var moving := speed > 0.15
	var dv := speed - _prev_speed
	_prev_speed = speed
	dash_t = maxf(0.0, dash_t - dt)
	if moving:
		walk_phase += dt * (6.0 + speed * 2.2)
	var sw := sin(walk_phase)
	var bob := 0.0
	var sq := Vector3.ONE
	var arm_lr := 0.0
	var arm_rr := 0.0
	var arm_lz := 0.0
	var arm_rz := 0.0
	var leg_a := 0.0
	var head_tilt := 0.0
	var head_turn := 0.0
	var torso_lean := 0.0
	var hop := 0.0
	match style:
		"blob":
			var s := 1.0 + (0.08 * sin(walk_phase * 2.0) if moving else 0.035 * sin(t * 2.4))
			sq = Vector3(1.0 / sqrt(s), s, 1.0 / sqrt(s))
		"float":
			bob = 0.08 * sin(t * 1.8) + 0.12
		"box":
			bob = absf(sw) * 0.04 if moving else 0.0
		_:
			bob = absf(sw) * 0.05 if moving else 0.012 * sin(t * 2.0)
	if moving:
		leg_a = sw * 0.55
		arm_lr = -sw * 0.5
		arm_rr = sw * 0.5
		# Lean into the run: more at speed, a nod forward when accelerating.
		torso_lean = 0.06 + 0.16 * clampf(speed / 3.6, 0.0, 1.0) + clampf(dv * 0.12, -0.1, 0.2) * rm
	if dash_t > 0.0:
		# Quick Step stretch; under reduced motion only a small lean, no stretch.
		var k := dash_t / 0.22
		if not reduced_motion:
			sq = sq * Vector3(1.0 - 0.16 * k, 1.0 + 0.22 * k, 1.0 - 0.16 * k)
		torso_lean = 0.4 * k * rm
	elif dv < -1.6 and not reduced_motion:
		# Hard stop: a quick squash the scale lerp below recovers from.
		body.scale = Vector3(1.16, 0.86, 1.16)
	else:
		arm_lz = 0.04 * sin(t * 2.0)
		arm_rz = -0.04 * sin(t * 2.0)
	match anim:
		"carry":
			arm_lr = -1.25; arm_rr = -1.25
			arm_lz = 0.15; arm_rz = -0.15
		"work":
			var w := sin(_anim_t * 16.0)
			arm_lr = -0.9 + w * 0.35; arm_rr = -0.9 - w * 0.35
			torso_lean = 0.18
			head_tilt = 0.12
			bob += absf(w) * 0.015
		"mop":
			var w2 := sin(_anim_t * 7.0)
			arm_lr = -0.7; arm_rr = -0.7
			torso_lean = 0.12 + w2 * 0.08
			head_turn = w2 * 0.2
		"handoff":
			arm_lr = -1.5; arm_rr = -1.5
			torso_lean = 0.2
		"wave":
			arm_rz = -2.4
			arm_rr = sin(_anim_t * 12.0) * 0.5
			head_tilt = -0.1
		"happy":
			hop = maxf(0.0, sin(_anim_t * 9.0)) * 0.12 * rm
			arm_lz = 1.2; arm_rz = -1.2
		"concern":
			head_tilt = 0.18 * sin(t * 3.0)
			torso_lean = -0.05
			arm_lz = 0.3; arm_rz = -0.3
			sq = sq * Vector3(1.0, 0.97, 1.0)
		"quirk_warn":
			var k := clampf(_anim_t / 4.0, 0.0, 1.0)
			sq = Vector3(1.0 + 0.12 * k, 1.0 + 0.1 * k, 1.0 + 0.12 * k)
			head_tilt = -0.25 * k
			bob += 0.01 * sin(t * 30.0) * k * rm
		"quirk":
			var k2 := clampf(1.0 - _anim_t / 0.8, 0.0, 1.0)
			torso_lean = 0.35 * k2
			head_tilt = 0.3 * k2
			sq = Vector3(1.0 - 0.1 * k2, 1.0 + 0.15 * k2, 1.0 - 0.1 * k2)
		"helper":
			hop = absf(sin(_anim_t * 6.0)) * 0.08 * rm
			arm_lz = 0.9; arm_rz = -0.9
			arm_lr = -0.6; arm_rr = -0.6
		"photo":
			arm_lz = 0.8; arm_rz = -0.8
			head_tilt = -0.08
		"sleep":
			head_tilt = 0.35
			sq = Vector3(1.0 + 0.02 * sin(t * 1.4), 1.0 - 0.02 * sin(t * 1.4), 1.0)
		"sit":
			bob -= 0.12
	if carrying and anim in ["idle", "walk"]:
		arm_lr = -1.25; arm_rr = -1.25
		arm_lz = 0.15; arm_rz = -0.15
	body.position.y = bob + hop
	body.scale = body.scale.lerp(sq, minf(1.0, dt * 12.0))
	torso.rotation.x = lerpf(torso.rotation.x, torso_lean, minf(1.0, dt * 10.0))
	head.rotation.x = lerpf(head.rotation.x, head_tilt, minf(1.0, dt * 10.0))
	head.rotation.y = lerpf(head.rotation.y, head_turn, minf(1.0, dt * 10.0))
	arm_l.rotation = arm_l.rotation.lerp(Vector3(arm_lr, 0, arm_lz), minf(1.0, dt * 16.0))
	arm_r.rotation = arm_r.rotation.lerp(Vector3(arm_rr, 0, arm_rz), minf(1.0, dt * 16.0))
	leg_l.rotation.x = lerpf(leg_l.rotation.x, leg_a, minf(1.0, dt * 16.0))
	leg_r.rotation.x = lerpf(leg_r.rotation.x, -leg_a, minf(1.0, dt * 16.0))
	_animate_extras(dt, moving)
	if _skel != null:
		_sync_bones()

func _animate_extras(dt: float, moving: bool) -> void:
	for k in extras:
		var n: Node3D = extras[k]
		match k:
			"ear_l", "ear_r":
				var s := 1.0 if k == "ear_l" else -1.0
				n.rotation.z = s * (0.25 + (0.25 * absf(sin(walk_phase)) if moving else 0.06 * sin(t * 1.7)))
			"ears_flop_l", "ears_flop_r":
				var s2 := 1.0 if k == "ears_flop_l" else -1.0
				n.rotation.x = 0.15 * sin(walk_phase * (1.0 if moving else 0.0) + t * 0.8) + (0.3 if anim == "work" else 0.0)
				n.rotation.z = s2 * (0.12 + 0.08 * sin(t * 1.3))
			"tail":
				n.rotation.y = 0.35 * sin(t * (5.0 if anim == "happy" else 2.0))
			"wing_l", "wing_r":
				var s3 := 1.0 if k == "wing_l" else -1.0
				n.rotation.z = s3 * (0.2 + 0.35 * maxf(0.0, sin(t * (14.0 if anim in ["happy", "helper"] else 3.0))))
			"lid":
				var open := 0.0
				if anim in ["happy", "helper", "work", "photo"]:
					open = 0.7 + 0.15 * sin(t * 8.0)
				elif anim == "wave":
					open = 0.4
				n.rotation.x = lerpf(n.rotation.x, -open, minf(1.0, dt * 10.0))
			"flower":
				var target := 1.0 if anim in ["happy", "helper"] else 0.55
				var sc: float = lerpf(n.scale.x, target, minf(1.0, dt * 4.0))
				n.scale = Vector3(sc, sc, sc)
			"leaves":
				n.rotation.z = 0.08 * sin(t * 2.3)
			"antenna":
				n.rotation.x = 0.1 * sin(t * 3.1)
			"cap":
				pass
