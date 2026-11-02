class_name Backdrop
extends Node3D
## Living 3D backdrop for menus: the hotel floor with staff, guests, Nana and
## Gus idling or strolling (cosmetic only, no simulation).

var stage: PixelStage
var actors: Array = []
var _t := 0.0

func build(p_stage: PixelStage, kind: String) -> void:
	stage = p_stage
	name = "Backdrop"
	stage.world.add_child(self)
	# The v2 hotel (D31): the six-room festival floor behind the menus, the
	# four-room chapter-1 floor behind the title. Everyone stands where the
	# layout says there is floor: staff on the lane, guests by their beds.
	var L := Content.layout("P6v2" if kind != "title_small" else "P1v2")
	var sys := {"core": true, "thermal": true, "sound": true, "moisture": true, "festival": true}
	add_child(HotelBuilder.new().build(L, sys))
	# Frame this floor (the stage's default bounds are the classic envelope).
	var u := L.used
	stage.set_bounds(Vector3(u.position.x - 0.6, 0.0, u.position.y - 0.6), Vector3(u.end.x - 1 + 0.6, 0.6, u.end.y - 1 + 0.7))
	var cos: Dictionary = Content.cosmetics[0] if not Content.cosmetics.is_empty() else {}
	var hx0 := float(L.hall.position.x)
	var hw := float(L.hall.size.x - 1)
	var lane := float(L.hall.position.y) + 1.0
	var ids := ["pip", "pebble", "moss", "button"]
	for i in 4:
		var r := ModelActors.staff(ids[i], cos)
		var spot := Vector3(hx0 + hw * (0.2 + 0.2 * i), 0, lane + (0.25 if i % 2 == 0 else -0.15))
		r.position = spot
		add_child(r)
		actors.append({"rig": r, "base": spot, "phase": i * 1.7, "walk": i % 2 == 0, "span": hw * 0.08})
	var fams := SimC.FAMILIES
	var letters: Array = L.active_rooms.duplicate()
	for i in mini(fams.size(), letters.size()):
		var g := ModelActors.guest(fams[i], "")
		var room: Dictionary = L.rooms[letters[i]]
		var bed: Vector2i = room["bed"]
		var gpos := Vector3(bed.x + 0.9, 0, bed.y + (0.6 if room["side"] == "north" else -0.6))
		g.position = gpos
		g.face_dir = 0.0 if room["side"] == "north" else PI
		add_child(g)
		actors.append({"rig": g, "base": gpos, "phase": i * 0.9, "walk": false, "guest": true})
	var nana := ModelActors.npc("nana")
	var rp: Vector2i = L.fixtures["reception"]
	nana.position = Vector3(rp.x + 1.0, 0, rp.y + 0.1)
	nana.face_dir = PI * 0.5
	add_child(nana)
	actors.append({"rig": nana, "base": nana.position, "phase": 0.3, "walk": false})
	var gus := ModelActors.npc("gus")
	gus.position = Vector3(hx0 + hw * 0.5, 0, lane - 0.35)
	add_child(gus)
	actors.append({"rig": gus, "base": gus.position, "phase": 2.0, "walk": true, "gus": true, "span": hw * 0.3})
	stage.set_pixel_lines(Settings.pixel_lines())
	stage.set_outlines(Settings.g("outlines") and Settings.g("graphics") != "low")
	stage.set_quality(str(Settings.g("graphics")))

func _process(dt: float) -> void:
	_t += dt
	for a in actors:
		var r: ActorRig = a["rig"]
		if a.get("walk", false) and not Settings.g("reduced_motion"):
			var span: float = a.get("span", 3.0)
			var k: float = sin(_t * 0.35 + a["phase"])
			var base: Vector3 = a["base"]
			var x := base.x + k * span
			var dx := cos(_t * 0.35 + a["phase"])
			r.position = Vector3(x, 0, base.z)
			r.speed = absf(dx) * 1.2
			r.face_dir = PI * 0.5 if dx > 0 else -PI * 0.5
		else:
			r.speed = 0.0
			if int(_t / 3.0 + a["phase"]) % 5 == 0:
				r.set_anim("wave" if not a.get("guest", false) else "happy")
			else:
				r.set_anim("idle")
		r.tick(dt)
