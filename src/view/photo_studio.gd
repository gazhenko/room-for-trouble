class_name PhotoStudio
extends RefCounted
## Builds a small staged photo set (group photo, postcard still) inside a
## PixelStage: lobby backdrop, bunting, the actual selected staff, the shift's
## guest families, Nana and Gus, plus one harmless gag prop.

static func make_stage(size: Vector2, lines := 200) -> PixelStage:
	var ps := PixelStage.new()
	ps.set_anchors_preset(Control.PRESET_TOP_LEFT)
	ps.custom_minimum_size = size
	ps.size = size
	ps.target_lines = lines
	return ps

static func stage_photo(ps: PixelStage, staff: Array, families: Array, opts: Dictionary = {}) -> Node3D:
	var root := Node3D.new()
	root.name = "PhotoSet"
	ps.world.add_child(root)
	var mk := MeshKit.new()
	mk.jitter = 0.0
	var wall: Color = opts.get("wall", Art.CREAM)
	var floor_c: Color = opts.get("floor", Color("#B98F6E"))
	mk.flat(Vector3(0, 0, 0), Vector2(9, 6), floor_c)
	mk.box(Vector3(0, 1.4, -2.6), Vector3(9, 2.8, 0.3), wall)
	mk.box(Vector3(0, 0.06, -2.4), Vector3(9, 0.12, 0.08), Art.WALNUT)
	var cols := [Art.CORAL, Art.GOLD, Art.SKY, Art.SAGE, Art.PLUM]
	for i in 15:
		mk.cone(Vector3(-4.2 + i * 0.6, 2.4, -2.38), 0.13, -0.28, cols[i % 5], 3)
	# Window with moon and sign.
	mk.box(Vector3(2.6, 1.6, -2.42), Vector3(1.2, 1.0, 0.05), Art.WALNUT)
	mk.box(Vector3(2.6, 1.6, -2.39), Vector3(1.0, 0.82, 0.04), Color("#3E4C7A") if opts.get("night", false) else Color("#BFE0EA"))
	mk.sphere(Vector3(2.85, 1.8, -2.36), 0.15, Color("#FFF3C8"), 3, 6, Vector3(1, 1, 0.3))
	mk.box(Vector3(-2.4, 1.85, -2.42), Vector3(1.8, 0.5, 0.05), Art.GOLD)
	mk.box(Vector3(-2.4, 1.85, -2.39), Vector3(1.6, 0.36, 0.03), Art.INK)
	root.add_child(Art.mesh_instance(mk.commit()))
	var cos: Dictionary = {}
	for cs in Content.cosmetics:
		if cs["id"] == opts.get("outfit", "default"):
			cos = cs
	if cos.is_empty() and not Content.cosmetics.is_empty():
		cos = Content.cosmetics[0]
	var n := staff.size()
	for i in n:
		var r := ModelActors.staff(staff[i], cos)
		r.position = Vector3(-0.9 * (n - 1) * 0.5 + i * 0.9, 0, 0.9)
		r.set_anim(opts.get("staff_anim", "photo"))
		root.add_child(r)
		r.tick(0.5)
	var m := mini(families.size(), 6)
	for j in m:
		var g := ModelActors.guest(families[j], "")
		var x := -1.0 * (m - 1) * 0.5 + j * 1.0
		g.position = Vector3(x, 0, -0.6)
		g.set_anim("happy" if j % 2 == 0 else "wave")
		root.add_child(g)
		g.tick(0.4)
	if opts.get("npcs", true):
		var nana := ModelActors.npc("nana")
		nana.position = Vector3(-3.4, 0, -0.2)
		nana.face_dir = 0.3
		root.add_child(nana)
		nana.tick(0.3)
		var gus := ModelActors.npc("gus")
		gus.position = Vector3(3.4, 0, 0.6)
		gus.set_anim("happy")
		root.add_child(gus)
		gus.tick(0.3)
	if opts.has("prop"):
		var prop := ModelProps.build(opts["prop"])
		prop.position = Vector3(3.0, 0, -1.4)
		root.add_child(prop)
	ps.set_bounds(Vector3(-4.2, 0, -2.6), Vector3(4.2, 1.6, 1.8))
	return root

static func families_of(level_id: String) -> Array:
	var L: Dictionary = Content.level(level_id)
	var out: Array = []
	for w in L.get("waves", []):
		for f in w["roster"]:
			if not f in out:
				out.append(f)
	return out
