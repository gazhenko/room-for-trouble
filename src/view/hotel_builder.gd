class_name HotelBuilder
extends RefCounted
## Builds the static toy-hotel geometry for one LayoutDef: floors, cut-away
## walls (tall at the back, low toward the camera), door frames, windows,
## pipes, sound trims, exterior garden and per-template dressing (§12, §17).

var L: LayoutDef
var systems: Dictionary
var root: Node3D
var wall_mat: ShaderMaterial
var pal: Dictionary

func build(layout: LayoutDef, sys: Dictionary) -> Node3D:
	L = layout
	systems = sys
	pal = {}
	for k in L.palette:
		pal[k] = Color(L.palette[k])
	root = Node3D.new()
	root.name = "Hotel"
	_ground()
	_floors()
	_walls()
	_doors()
	_back_wall_dressing()
	_pipes()
	_sound_trims()
	_exterior()
	_template_decor()
	_inactive_rooms()
	return root

func _c(key: String, fallback: Color) -> Color:
	return pal.get(key, fallback)

func _add(mk: MeshKit, mat: Material, name: String, shadows := true) -> MeshInstance3D:
	var mi := Art.mesh_instance(mk.commit(), mat)
	mi.name = name
	if not shadows:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	return mi

## Cut-away wall heights: tall at the back, low toward the camera, derived from
## the layout's hall rows so the compact envelope reads the same way.
static func wall_height_for(L: LayoutDef, x: int, z: int) -> float:
	var hz0 := L.hall.position.y
	var hz1 := L.hall.end.y - 1
	if z == 0:
		return 1.9
	if z == L.south_wall_z():
		return 0.28
	if z < hz0 - 1:
		return 1.45
	if z == hz0 - 1:
		return 0.95
	if z <= hz1:
		return 1.15 if (x == 0 or x == L.east_wall_x()) else 0.9
	return 0.62

func _wh(x: int, z: int) -> float:
	return wall_height_for(L, x, z)

## Midpoints of the wall columns between neighbouring north rooms.
func _north_gaps() -> Array:
	var rects: Array = []
	for letter in L.rooms:
		var g: Dictionary = L.rooms[letter]
		if g["side"] == "north":
			rects.append(g["rect"])
	rects.sort_custom(func(a, b): return (a as Rect2i).position.x < (b as Rect2i).position.x)
	var out: Array = []
	for i in range(1, rects.size()):
		out.append(((rects[i - 1] as Rect2i).end.x - 1 + (rects[i] as Rect2i).position.x) * 0.5)
	return out

# ------------------------------------------------------------------ ground

func _ground() -> void:
	var mk := MeshKit.new()
	mk.jitter = 0.0
	var grass := Color(str(L.light.get("background", "#8CB27A")))
	mk.flat(Vector3(13.5, -0.06, 9.5), Vector2(52, 40), grass)
	_add(mk, Art.toon_tex("grass", Art.grass(4), 1.0, 0.25, Color(1, 1, 1)), "Ground", false)
	# Garden path to the front door.
	var mk2 := MeshKit.new()
	mk2.jitter = 0.02
	var ez := L.entrance_z()
	for i in 9:
		mk2.flat(Vector3(-1.2 - i * 0.9, -0.04, ez + sin(i * 0.9) * 0.3), Vector2(0.8, 1.6), Color("#D8C3A0"))
	_add(mk2, Art.toon(), "Path", false)

# ------------------------------------------------------------------ floors

func _floors() -> void:
	var hall := MeshKit.new()
	hall.jitter = 0.0
	var floor_col := _c("floor", Color("#B98F6E"))
	for z in LayoutDef.H:
		for x in LayoutDef.W:
			if L.is_wall_tile(x, z):
				continue
			var letter := L.room_at_tile(x, z)
			if letter == "" or not L.rooms[letter]["active"] or true:
				hall.flat(Vector3(x, 0.0, z), Vector2(1, 1), floor_col)
	# Door thresholds and entrance tiles.
	for e in L.entrance:
		hall.flat(Vector3(e.x, 0.0, e.y), Vector2(1, 1), floor_col.darkened(0.08))
	var tex := Art.tiles(3) if L.id == "P4" else Art.planks(L.id.hash() & 7)
	_add(hall, Art.toon_tex("floor_" + L.id, tex, 1.0, 0.25 if L.id != "P4" else 0.5), "Floor", false)
	# Rugs inside each active room (letter colour, semantic accent).
	var rugs := MeshKit.new()
	rugs.jitter = 0.0
	for letter in L.rooms:
		var g: Dictionary = L.rooms[letter]
		if not g["active"]:
			continue
		var r: Rect2i = g["rect"]
		var cx := r.position.x + (r.size.x - 1) * 0.5
		var cz := r.position.y + (r.size.y - 1) * 0.5
		var rc: Color = Art.ROOM_COLORS[letter].lerp(Art.CREAM, 0.45)
		rugs.flat(Vector3(cx, 0.012, cz), Vector2(r.size.x - 1.6, r.size.y - 1.8), rc)
	_add(rugs, Art.toon_tex("rugs", Art.rug(2), 1.0, 0.5), "Rugs", false)
	# Welcome rug in the lobby by the entrance.
	var mat := MeshKit.new()
	mat.jitter = 0.0
	var ez := L.entrance_z()
	mat.flat(Vector3(1.6, 0.012, ez), Vector2(1.6, 2.2), _c("rug", Art.CORAL))
	mat.flat(Vector3(1.6, 0.016, ez), Vector2(1.2, 1.8), Art.CREAM)
	mat.flat(Vector3(1.6, 0.02, ez), Vector2(1.0, 1.6), _c("rug", Art.CORAL).lightened(0.2))
	_add(mat, Art.toon(), "LobbyRug", false)

# ------------------------------------------------------------------ walls

func _walls() -> void:
	var mk := MeshKit.new()
	mk.jitter = 0.015
	var caps := MeshKit.new()
	caps.jitter = 0.02
	var wall_col := _c("wall", Art.CREAM)
	var trim := Color("#7D5E47")   # mid walnut: a wall top is an edge, not a dark slab
	var xe := L.east_wall_x()
	var ze := L.south_wall_z()
	var skirting := _c("trim", Art.WALNUT).darkened(0.1)
	for z in LayoutDef.H:
		for x in LayoutDef.W:
			if not L.is_wall_tile(x, z):
				continue
			var is_entrance := false
			for e in L.entrance:
				if e == Vector2i(x, z):
					is_entrance = true
			if is_entrance or not L.wall_tile_exposed(x, z):
				continue
			var h := _wh(x, z)
			var col := wall_col
			if z == 0:
				col = wall_col
			elif z >= L.hall_south_wall_z():
				col = wall_col.darkened(0.04)
			# The outer ring is drawn 0.42 m thick against its inner face (collision
			# keeps the full tile); room dividers stay a full tile so no gap shows.
			var bx := float(x)
			var bz := float(z)
			var wsx := 1.0
			var wsz := 1.0
			if z == 0:
				bz = 0.29; wsz = 0.42
			elif z == ze:
				bz = ze - 0.29; wsz = 0.42
			if x == 0:
				bx = 0.29; wsx = 0.42
			elif x == xe:
				bx = xe - 0.29; wsx = 0.42
			mk.box(Vector3(bx, h * 0.5, bz), Vector3(wsx, h, wsz), col)
			caps.box(Vector3(bx, h + 0.04, bz), Vector3(wsx + 0.04, 0.08, wsz + 0.04), trim, trim.lightened(0.12))
			# Skirting board along walkable neighbours.
			for d in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
				var nx: int = x + d.x
				var nz: int = z + d.y
				if nx < 0 or nz < 0 or nx >= LayoutDef.W or nz >= LayoutDef.H:
					continue
				if not L.is_wall_tile(nx, nz):
					var p := Vector3(x + d.x * 0.505, 0.07, z + d.y * 0.505)
					var sz := Vector3(1.0 if d.x == 0 else 0.03, 0.14, 1.0 if d.y == 0 else 0.03)
					caps.box(p, sz, skirting)
	wall_mat = Art.toon_unique(Color.WHITE)
	wall_mat.set_shader_parameter("tex", Art.wallpaper(L.id.hash() & 3))
	wall_mat.set_shader_parameter("use_tex", 5.0)
	wall_mat.set_shader_parameter("tex_scale", 0.5)
	wall_mat.set_shader_parameter("fade_walls", 1.0)
	_add(mk, wall_mat, "Walls")
	_add(caps, Art.toon(), "WallCaps")

func _doors() -> void:
	var mk := MeshKit.new()
	var frame := Art.WALNUT
	for letter in L.rooms:
		var g: Dictionary = L.rooms[letter]
		var d: Vector2i = g["door"]
		var h := _wh(d.x, d.y)
		var top := h + 0.35
		if not g["active"]:
			continue
		# Rounded friendly door frame: two posts and a lintel arch.
		for sx in [-0.5, 0.5]:
			mk.box(Vector3(d.x + sx * 0.96, top * 0.5, d.y), Vector3(0.1, top, 0.36), frame)
		mk.box(Vector3(d.x, top + 0.04, d.y), Vector3(1.1, 0.12, 0.36), frame, frame.lightened(0.15))
		mk.box(Vector3(d.x, top + 0.13, d.y), Vector3(0.7, 0.07, 0.3), frame.lightened(0.1))
		# Threshold strip in the room colour.
		mk.box(Vector3(d.x, 0.015, d.y), Vector3(0.9, 0.03, 0.9), Art.ROOM_COLORS[letter].lerp(Art.CREAM, 0.3))
		# Plaque board on the hall side (the crisp letter is drawn by the HUD).
		var off := 0.47 if g["side"] == "north" else -0.47
		var px := d.x + 0.72
		mk.box(Vector3(px, h * 0.5 + 0.45, d.y + off), Vector3(0.36, 0.3, 0.05), Art.ROOM_COLORS[letter], Art.ROOM_COLORS[letter].lightened(0.2))
		mk.box(Vector3(px, h * 0.5 + 0.28, d.y + off), Vector3(0.05, 0.4, 0.05), Art.BRASS)
	_add(mk, Art.toon(), "Doors")

func _back_wall_dressing() -> void:
	var mk := MeshKit.new()
	var sky := Color("#BFE0EA")
	for letter in L.rooms:
		var g: Dictionary = L.rooms[letter]
		var r: Rect2i = g["rect"]
		if g["side"] != "north":
			continue
		# Two windows on the tall back wall of each north room.
		for wx in [r.position.x + 1.5, r.position.x + r.size.x - 2.5]:
			var z := 0.5 + 0.03
			mk.box(Vector3(wx, 1.35, z), Vector3(1.0, 0.95, 0.06), Art.WALNUT)
			mk.box(Vector3(wx, 1.35, z + 0.02), Vector3(0.84, 0.8, 0.04), sky.lightened(0.15) if L.id != "P3" else Color("#9C93C8"))
			mk.box(Vector3(wx, 1.35, z + 0.05), Vector3(0.06, 0.8, 0.03), Art.WALNUT.lightened(0.1))
			mk.box(Vector3(wx, 1.35, z + 0.05), Vector3(0.84, 0.06, 0.03), Art.WALNUT.lightened(0.1))
			mk.box(Vector3(wx, 0.85, z + 0.06), Vector3(1.1, 0.07, 0.14), Art.WALNUT.lightened(0.15))
			# Curtains either side.
			var cc := _c("accent", Art.CORAL).lerp(Art.CREAM, 0.25)
			mk.box(Vector3(wx - 0.55, 1.35, z + 0.06), Vector3(0.18, 1.05, 0.05), cc)
			mk.box(Vector3(wx + 0.55, 1.35, z + 0.06), Vector3(0.18, 1.05, 0.05), cc)
		# A small framed picture between windows.
		var pxm := r.position.x + (r.size.x - 1) * 0.5
		mk.box(Vector3(pxm, 1.5, 0.54), Vector3(0.62, 0.48, 0.05), Art.GOLD)
		mk.box(Vector3(pxm, 1.5, 0.565), Vector3(0.5, 0.36, 0.03), Art.ROOM_COLORS[letter].lerp(Art.SKY, 0.4))
	# Hotel sign over the hall on the back wall area between rooms.
	for x in _north_gaps():
		mk.box(Vector3(x, 1.8, 0.56), Vector3(0.5, 0.5, 0.05), Art.BRASS)
		mk.sphere(Vector3(x, 1.8, 0.62), 0.14, Art.GOLD.lightened(0.3), 3, 6)
	_add(mk, Art.toon(), "BackWall")

func _pipes() -> void:
	if not systems.has("thermal"):
		return
	var mk := MeshKit.new()
	for e in L.thermal_edges:
		var ab := L.edge_rooms(e)
		var ga: Dictionary = L.rooms[ab[0]]
		var gb: Dictionary = L.rooms[ab[1]]
		var north: bool = ga["side"] == "north"
		var z := float(L.hall_north_wall_z() if north else L.hall_south_wall_z())
		var y := _wh(0, int(z)) + 0.12
		var xa: float = float(ga["rect"].position.x + ga["rect"].size.x - 1)
		var xb: float = float(gb["rect"].position.x)
		if xa > xb:
			var t := xa; xa = xb; xb = t
		var len := xb - xa + 1.0
		var cx := (xa + xb) * 0.5
		mk.push_at(Vector3(cx, y, z), Vector3(0, 0, 90))
		mk.cyl(Vector3(0, -len * 0.5, 0), 0.07, len, Art.BRASS, 6)
		mk.pop()
		for px in [xa - 0.2, xb + 0.2]:
			mk.box(Vector3(px, y, z), Vector3(0.16, 0.2, 0.16), Art.BRASS.darkened(0.15))
	_add(mk, Art.toon(), "Pipes")

func _sound_trims() -> void:
	if not systems.has("sound"):
		return
	var mk := MeshKit.new()
	mk.jitter = 0.0
	for e in L.acoustic_edges:
		var a: Dictionary = L.rooms[e.substr(0, 1)]
		var x: int = a["door"].x
		var b: Dictionary = L.rooms[e.substr(1, 1)]
		var xb: int = b["door"].x
		var xm := (x + xb) * 0.5
		for z in range(L.hall.position.y, L.hall.end.y):
			mk.flat(Vector3(xm + 0.55, 0.01, z), Vector2(0.12, 0.9), Art.SOUND)
			# Little note shapes along the trim.
			mk.disc(Vector3(xm + 0.55, 0.012, z + 0.2), 0.11, Art.SOUND.darkened(0.15), 6)
	_add(mk, Art.toon(), "SoundTrims", false)

func _exterior() -> void:
	var mk := MeshKit.new()
	# Porch and front door (west entrance).
	var ent: Vector2i = L.entrance[0]
	var ex := float(ent.x)
	var ez := L.entrance_z()
	var xe := float(L.east_wall_x())
	var ze := float(L.south_wall_z())
	mk.box(Vector3(ex - 0.9, 0.05, ez), Vector3(1.6, 0.1, 2.6), Art.WALNUT.lightened(0.15))
	for sz in [-1.25, 1.25]:
		mk.box(Vector3(ex, 0.8, ez + sz), Vector3(0.3, 1.6, 0.3), Art.WALNUT)
	mk.box(Vector3(ex, 1.7, ez), Vector3(0.4, 0.2, 2.9), Art.CORAL, Art.CORAL.lightened(0.15))
	# Hanging sign "Hearth & Hiccup" (crooked final letter in the story).
	mk.box(Vector3(ex - 0.55, 2.05, ez), Vector3(0.06, 0.5, 1.8), Art.GOLD)
	mk.box(Vector3(ex - 0.58, 2.05, ez), Vector3(0.04, 0.38, 1.6), Art.INK)
	# Lamp posts.
	for lz in [ez - 1.9, ez + 1.9]:
		mk.cyl(Vector3(ex - 1.6, 0, lz), 0.05, 1.4, Art.INK, 6)
		mk.sphere(Vector3(ex - 1.6, 1.5, lz), 0.14, Art.GOLD.lightened(0.35), 3, 6)
	# Outside bench and cozy corner bench.
	for p in [L.outside_bench, L.cozy_corner]:
		mk.box(Vector3(p.x, 0.32, p.y), Vector3(0.55, 0.08, 1.4), Art.WALNUT)
		mk.box(Vector3(p.x - 0.22, 0.6, p.y), Vector3(0.08, 0.5, 1.4), Art.WALNUT.darkened(0.1))
		for sz2 in [-0.55, 0.55]:
			mk.box(Vector3(p.x, 0.15, p.y + sz2), Vector3(0.45, 0.3, 0.08), Art.WALNUT.darkened(0.2))
	# Cozy corner tea table.
	var cc := L.cozy_corner
	mk.cyl(Vector3(cc.x - 0.7, 0, cc.y + 0.9), 0.22, 0.4, Art.CREAM, 8, Art.CORAL)
	mk.cyl(Vector3(cc.x - 0.7, 0.4, cc.y + 0.9), 0.06, 0.08, Art.WHITE, 6)
	# Hedges and trees around the hotel.
	var hedge := Color("#6E9E64")
	for i in int(xe / 2.0):
		var tx := 1.0 + i * 2.0
		mk.sphere(Vector3(tx, 0.35, -1.1), 0.55, hedge.lightened(0.05 * (i % 3)), 3, 7, Vector3(1.2, 0.8, 1))
		mk.sphere(Vector3(tx + 0.5, 0.3, ze + 1.3), 0.5, hedge.darkened(0.05 * (i % 2)), 3, 7, Vector3(1.2, 0.7, 1))
	# Trees shrink with the floor so a four-room hotel is not dwarfed by its garden.
	var ts := 1.0 if xe >= 20.0 else 0.72
	for tz in [1.5, 4.5, ze - 4.0, ze - 1.0]:
		mk.cyl(Vector3(-1.4, 0, tz), 0.12 * ts, 0.8 * ts, Art.WALNUT, 6)
		mk.sphere(Vector3(-1.4, 1.25 * ts, tz), 0.65 * ts, Color("#7BAA6B"), 3, 7)
		mk.cyl(Vector3(xe + 1.4, 0, tz), 0.12 * ts, 0.8 * ts, Art.WALNUT, 6)
		mk.sphere(Vector3(xe + 1.4, 1.25 * ts, tz), 0.65 * ts, Color("#7BAA6B").darkened(0.06), 3, 7)
	# Flowers along the front.
	for i in int(xe / 1.5):
		var fx := 0.5 + i * 1.5
		var fc: Color = [Art.CORAL, Art.GOLD, Art.ROSE, Art.SKY][i % 4]
		mk.cyl(Vector3(fx, 0, ze + 0.85), 0.02, 0.22, Art.LEAF, 4)
		mk.sphere(Vector3(fx, 0.26, ze + 0.85), 0.07, fc, 2, 5)
	_add(mk, Art.toon(), "Exterior")

func _template_decor() -> void:
	var mk := MeshKit.new()
	var deco: Array = L.decor
	var xe := float(L.east_wall_x())
	var ze := float(L.south_wall_z())
	var hz0 := float(L.hall.position.y)
	var hz1 := float(L.hall.end.y - 1)
	if "boxes" in deco:
		for p in [Vector3(xe - 1.4, 0, hz0 + 0.2), Vector3(xe - 1.0, 0, hz0 + 0.5), Vector3(1.2, 0, hz1 + 0.6)]:
			mk.box(p + Vector3(0, 0.18, 0), Vector3(0.38, 0.36, 0.38), Color("#C9A27E"), Color("#D8B48E"))
	if "potted_fern" in deco or "planters" in deco:
		for p in [Vector3(1.1, 0, hz0 + 0.2), Vector3(xe - 1.0, 0, hz1 + 0.6), Vector3(xe * 0.44, 0, hz1 + 0.65)]:
			mk.cyl(p, 0.2, 0.32, Art.CORAL.darkened(0.15), 7, Art.WALNUT)
			for k in 5:
				var a := TAU * k / 5.0
				mk.push_at(p + Vector3(cos(a) * 0.08, 0.35, sin(a) * 0.08), Vector3(cos(a) * 35, 0, sin(a) * 35))
				mk.sphere(Vector3(0, 0.12, 0), 0.12, Art.LEAF, 2, 5, Vector3(0.6, 1.6, 0.6))
				mk.pop()
	if "lanterns" in deco or "garlands" in deco:
		var cols := [Art.CORAL, Art.GOLD, Art.SKY, Art.PLUM, Art.SAGE]
		# Lanterns glow (the festival night is lit by them, DESIGN_V2 §9).
		var glow := MeshKit.new()
		for i in int((xe - 1.0) / 2.15):
			var x := 1.6 + i * 2.15
			glow.sphere(Vector3(x, 1.55, hz0 - 0.45), 0.14, cols[i % 5], 3, 6, Vector3(1, 1.25, 1))
			mk.cyl(Vector3(x, 1.68, hz0 - 0.45), 0.04, 0.12, Art.INK, 4)
		var glow_mat := Art.toon_unique()
		glow_mat.set_shader_parameter("emission", Color(1.0, 0.86, 0.55, 0.55))
		_add(glow, glow_mat, "Lanterns", false)
		for i in int(xe) - 1:
			mk.cone(Vector3(1.0 + i * 1.0, 1.38, hz0 - 0.5), 0.09, -0.18, cols[i % 5], 3)
	if "paper_moon" in deco:
		mk.sphere(Vector3(xe - 2.0, 2.2, 0.8), 0.6, Color("#FFF3C8"), 4, 10, Vector3(1, 1, 0.3))
	if "glass_roof" in deco:
		for i in int(xe / 4.6) + 1:
			mk.box(Vector3(2 + i * 4.6, 2.32, 0.5), Vector3(0.08, 0.06, 1.0), Art.BRASS)
	if "travel_stickers" in deco and L.divider.x >= 0:
		var d := L.divider
		var sc := [Art.CORAL, Art.SKY, Art.GOLD, Art.SAGE]
		for i in 4:
			mk.box(Vector3(d.x - 0.3 + 0.2 * i, 0.5 + 0.1 * (i % 2), d.y + 0.51), Vector3(0.16, 0.12, 0.02), sc[i])
	if "radiators" in deco or "brass_pipes" in deco:
		for letter in L.rooms:
			var g: Dictionary = L.rooms[letter]
			if not g["active"]:
				continue
			var r: Rect2i = g["rect"]
			var side_z := 0.62 if g["side"] == "north" else ze - 0.62
			var rx := r.position.x + r.size.x - 1.6
			for k in 5:
				mk.box(Vector3(rx + k * 0.12, 0.35, side_z), Vector3(0.08, 0.5, 0.12), Art.CREAM.darkened(0.12))
	if "moon_lamps" in deco:
		for x in [xe * 0.11, xe * 0.44, xe * 0.78]:
			mk.sphere(Vector3(x + 2.0, 1.95, 0.6), 0.16, Color("#FFF3C8"), 3, 6)
	if not mk.is_empty():
		_add(mk, Art.toon(), "Decor")

func _inactive_rooms() -> void:
	var mk := MeshKit.new()
	for letter in L.rooms:
		var g: Dictionary = L.rooms[letter]
		if g["active"]:
			continue
		var r: Rect2i = g["rect"]
		var d: Vector2i = g["door"]
		# Closed decorative door and a friendly renovation fence.
		var off := 0.3 if g["side"] == "north" else -0.3
		mk.box(Vector3(d.x, 0.5, d.y + off), Vector3(0.9, 1.0, 0.08), Art.WALNUT.lightened(0.1))
		for k in 5:
			mk.box(Vector3(d.x - 1.2 + k * 0.6, 0.35, d.y + off * 2.6), Vector3(0.06, 0.7, 0.06), Art.GOLD)
		mk.box(Vector3(d.x, 0.55, d.y + off * 2.6), Vector3(2.6, 0.08, 0.04), Art.CORAL)
		mk.box(Vector3(d.x, 0.3, d.y + off * 2.6), Vector3(2.6, 0.08, 0.04), Art.CREAM)
		# Boxes, a ladder and dust sheets inside.
		var cx := r.position.x + 2.0
		var cz := r.position.y + 2.0
		var sx := minf(cx + 2.5, r.end.x - 1.9)   # dust sheet stays inside a 5-tile room
		var lx := minf(cx + 4.0, r.end.x - 1.3)   # ladder too
		mk.box(Vector3(cx, 0.25, cz), Vector3(0.6, 0.5, 0.6), Color("#C9A27E"), Color("#D8B48E"))
		mk.box(Vector3(cx + 0.7, 0.18, cz + 0.3), Vector3(0.45, 0.36, 0.45), Color("#C9A27E"))
		mk.box(Vector3(sx, 0.4, cz + 0.8), Vector3(1.6, 0.8, 0.8), Art.WHITE.darkened(0.08))
		for k in 4:
			mk.box(Vector3(lx, 0.2 + k * 0.32, cz + 0.6), Vector3(0.5, 0.05, 0.08), Art.WALNUT)
		mk.box(Vector3(lx - 0.22, 0.6, cz + 0.6), Vector3(0.05, 1.2, 0.05), Art.WALNUT)
		mk.box(Vector3(lx + 0.22, 0.6, cz + 0.6), Vector3(0.05, 1.2, 0.05), Art.WALNUT)
	if not mk.is_empty():
		_add(mk, Art.toon(), "Renovation")
