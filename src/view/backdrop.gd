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
	var L := Content.layout("P6" if kind != "title_small" else "P1")
	var sys := {"core": true, "thermal": true, "sound": true, "moisture": true, "festival": true}
	add_child(HotelBuilder.new().build(L, sys))
	var cos: Dictionary = Content.cosmetics[0] if not Content.cosmetics.is_empty() else {}
	var spots := [Vector3(10, 0, 9.2), Vector3(12.2, 0, 9.6), Vector3(15, 0, 9.1), Vector3(17, 0, 9.7)]
	var ids := ["pip", "pebble", "moss", "button"]
	for i in 4:
		var r := ModelActors.staff(ids[i], cos)
		r.position = spots[i]
		add_child(r)
		actors.append({"rig": r, "base": spots[i], "phase": i * 1.7, "walk": i % 2 == 0})
	var fams := SimC.FAMILIES
	var gspots := [Vector3(3, 0, 3.6), Vector3(12, 0, 3.6), Vector3(21, 0, 3.6), Vector3(3, 0, 14.4), Vector3(12, 0, 14.4), Vector3(21, 0, 14.4)]
	for i in fams.size():
		var g := ModelActors.guest(fams[i], "")
		g.position = gspots[i]
		add_child(g)
		actors.append({"rig": g, "base": gspots[i], "phase": i * 0.9, "walk": false, "guest": true})
	var nana := ModelActors.npc("nana")
	nana.position = Vector3(1.0, 0, 8.6)
	nana.face_dir = PI * 0.5
	add_child(nana)
	actors.append({"rig": nana, "base": nana.position, "phase": 0.3, "walk": false})
	var gus := ModelActors.npc("gus")
	gus.position = Vector3(5, 0, 11.2)
	add_child(gus)
	actors.append({"rig": gus, "base": gus.position, "phase": 2.0, "walk": true, "gus": true})
	stage.set_pixel_lines(Settings.pixel_lines())
	stage.set_outlines(Settings.g("outlines") and Settings.g("graphics") != "low")
	stage.set_quality(str(Settings.g("graphics")))

func _process(dt: float) -> void:
	_t += dt
	for a in actors:
		var r: ActorRig = a["rig"]
		if a.get("walk", false) and not Settings.g("reduced_motion"):
			var span := 6.0 if a.get("gus", false) else 3.0
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
