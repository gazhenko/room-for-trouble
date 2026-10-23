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
var _yaw := 0.0
var _anim_t := 0.0
var _prev_anim := ""

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
			bob = absf(sw) * 0.035 if moving else 0.012 * sin(t * 2.0)
	if moving:
		leg_a = sw * 0.55
		arm_lr = -sw * 0.5
		arm_rr = sw * 0.5
		torso_lean = 0.08
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
