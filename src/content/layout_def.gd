class_name LayoutDef
extends RefCounted
## One expanded floor template (§12): static collision tiles, solid fixture
## boxes, interaction anchors, room geometry and environmental graphs. Built from
## data/layouts/base.json + templates.json, optionally mirrored across x=13.5.

const W := 28
const H := 20
const NAV_RES := 500_000            # 0.5 m guest navigation cells
const NAV_W := 56
const NAV_H := 40

var id: String
var key: String
var name_key: String
var mirrored := false
var active_rooms: Array = []
var rooms: Dictionary = {}          # letter -> Dictionary of Vector2i anchors etc.
var fixtures: Dictionary = {}       # name -> Vector2i or Array[Vector2i]
var gates: Dictionary = {}          # edge -> Vector2i
var thermal_edges: Array = []
var acoustic_edges: Array = []
var systems_available: Array = []
var palette: Dictionary = {}
var decor: Array = []
var initial_humidity: Dictionary = {}
var divider: Vector2i = Vector2i(-1, -1)
var shutter: Vector2i = Vector2i(-1, -1)
var lift_pads: Array = []
var drains: Array = []
var trunk_parking: Array = []
var parcel_pads: Array = []
var entrance: Array = []
var outside: Vector2 = Vector2.ZERO
var cozy_corner: Vector2 = Vector2.ZERO
var outside_bench: Vector2 = Vector2.ZERO
var queue_offset_z := -0.32
var hall: Rect2i

var tiles := PackedByteArray()      # 1 = wall
var used: Rect2i                    # walkable tiles plus their one-tile wall ring
var boxes: Array = []               # [x0,z0,x1,z1,tag] µm solid fixture footprints
var nav_block := PackedByteArray()  # guest nav (static)
var astar_cache: Dictionary = {}     # start*cells+goal -> cell path (pure function of nav_block)

static func build(base: Dictionary, tpl: Dictionary, mirror: bool) -> LayoutDef:
	var L := LayoutDef.new()
	L.id = tpl["id"]
	L.key = tpl.get("key", "")
	L.name_key = tpl.get("name_key", "")
	L.mirrored = mirror
	L.active_rooms = tpl.get("active_rooms", []).duplicate()
	L.thermal_edges = tpl.get("thermal_edges", []).duplicate()
	L.acoustic_edges = tpl.get("acoustic_edges", []).duplicate()
	L.systems_available = tpl.get("systems_available", []).duplicate()
	L.palette = tpl.get("palette", {}).duplicate()
	L.decor = tpl.get("decor", []).duplicate()
	L.initial_humidity = tpl.get("initial_humidity", {}).duplicate()
	var hr: Array = base["hall"]
	L.hall = Rect2i(hr[0], hr[1], hr[2] - hr[0] + 1, hr[3] - hr[1] + 1)
	var overrides: Dictionary = tpl.get("room_overrides", {})
	for letter in base["rooms"]:
		var r: Dictionary = base["rooms"][letter].duplicate(true)
		if overrides.has(letter):
			for k in overrides[letter]:
				r[k] = overrides[letter][k]
		var g := {
			"letter": letter,
			"number": int(r["number"]),
			"rect": L._mrect(r["rect"]),
			"door": L._mv(r["door"]),
			"bed": L._mv(r["bed"]),
			"plinth": L._mv(r["plinth"]),
			"thermostat": L._mv(r["thermostat"]),
			"tray": L._mv(r["tray"]),
			"drop": L._mv(r["drop"]),
			"side": r["side"],
			"active": letter in L.active_rooms,
		}
		L.rooms[letter] = g
	var fx: Dictionary = base["fixtures"].duplicate(true)
	var fo: Dictionary = tpl.get("fixture_overrides", {})
	for k in fo:
		fx[k] = fo[k]
	for k in fx:
		var v = fx[k]
		if v is Array and v.size() > 0 and v[0] is Array:
			var arr: Array = []
			for p in v:
				arr.append(L._mv(p))
			L.fixtures[k] = arr
		else:
			L.fixtures[k] = L._mv(v)
	for e in base["gates"]:
		L.gates[e] = L._mv(base["gates"][e])
	if tpl.has("divider"):
		L.divider = L._mv(tpl["divider"])
	if tpl.has("shutter"):
		L.shutter = L._mv(tpl["shutter"])
	for p in tpl.get("lift_pads", []):
		L.lift_pads.append(L._mv(p))
	for p in base.get("drains", []):
		L.drains.append(L._mv(p))
	for p in base.get("trunk_parking", []):
		L.trunk_parking.append(L._mv(p))
	for p in base.get("parcel_pads", []):
		L.parcel_pads.append(L._mv(p))
	for p in base["entrance"]["tiles"]:
		L.entrance.append(L._mv(p))
	L.outside = L._mvf(base["entrance"]["outside"])
	L.cozy_corner = L._mvf(base["cozy_corner"])
	L.outside_bench = L._mvf(base["outside_bench"])
	L.queue_offset_z = float(base.get("queue_offset_z", -0.32))
	L._build_tiles()
	L._build_boxes()
	L._build_nav()
	return L

func _mv(p) -> Vector2i:
	var x := int(p[0])
	if mirrored:
		x = (W - 1) - x
	return Vector2i(x, int(p[1]))

func _mvf(p) -> Vector2:
	var x := float(p[0])
	if mirrored:
		x = float(W - 1) - x
	return Vector2(x, float(p[1]))

func _mrect(r) -> Rect2i:
	var x0 := int(r[0]); var x1 := int(r[2])
	if mirrored:
		var a := (W - 1) - x1
		var b := (W - 1) - x0
		x0 = a; x1 = b
	return Rect2i(x0, int(r[1]), x1 - x0 + 1, int(r[3]) - int(r[1]) + 1)

func mirror_x_um(x: int) -> int:
	return (W - 1) * SimC.UM - x if mirrored else x

func _build_tiles() -> void:
	tiles.resize(W * H)
	for z in H:
		for x in W:
			var wall := true
			if x == 0 or x == W - 1 or z == 0 or z == H - 1:
				wall = true
			elif hall.has_point(Vector2i(x, z)):
				wall = false
			else:
				for letter in rooms:
					var g: Dictionary = rooms[letter]
					if (g["rect"] as Rect2i).has_point(Vector2i(x, z)):
						wall = false
					elif g["active"] and g["door"] == Vector2i(x, z):
						wall = false
			tiles[z * W + x] = 1 if wall else 0
	if divider.x >= 0:
		tiles[divider.y * W + divider.x] = 1
	var lo := Vector2i(W, H)
	var hi := Vector2i(-1, -1)
	for z in H:
		for x in W:
			if tiles[z * W + x] == 0:
				lo = Vector2i(mini(lo.x, x), mini(lo.y, z))
				hi = Vector2i(maxi(hi.x, x), maxi(hi.y, z))
	used = Rect2i(lo - Vector2i.ONE, hi - lo + Vector2i(3, 3))

## Rows of the hall's north and south walls (the door rows).
func hall_north_wall_z() -> int:
	return hall.position.y - 1

func hall_south_wall_z() -> int:
	return hall.end.y

## Column of the east outer wall and row of the south outer wall.
func east_wall_x() -> int:
	return used.end.x - 1

func south_wall_z() -> int:
	return used.end.y - 1

## Centre z of the entrance opening (the porch, path and lobby rug line up on it).
func entrance_z() -> float:
	if entrance.is_empty():
		return float(hall.position.y) + (hall.size.y - 1) * 0.5
	var s := 0.0
	for e in entrance:
		s += float((e as Vector2i).y)
	return s / entrance.size()

## True when a wall tile touches a walkable tile (filler inside a thick wall mass
## never needs geometry).
func wall_tile_exposed(x: int, z: int) -> bool:
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var nx := x + dx
			var nz := z + dz
			if nx < 0 or nz < 0 or nx >= W or nz >= H:
				continue
			if tiles[nz * W + nx] == 0:
				return true
	return false

func is_wall_tile(x: int, z: int) -> bool:
	if x < 0 or z < 0 or x >= W or z >= H:
		return true
	return tiles[z * W + x] == 1

func room_at_tile(x: int, z: int) -> String:
	for letter in rooms:
		var g: Dictionary = rooms[letter]
		if (g["rect"] as Rect2i).has_point(Vector2i(x, z)):
			return letter
	return ""

func room_at_um(x: int, z: int) -> String:
	return room_at_tile(tile_of(x), tile_of(z))

static func tile_of(v_um: int) -> int:
	# Tile index whose centre is nearest (tile centre at integer metres).
	return int(floor((float(v_um) + 500_000.0) / 1_000_000.0))

func _add_box(c: Vector2i, w_m: float, h_m: float, tag: String) -> void:
	var cx := c.x * SimC.UM
	var cz := c.y * SimC.UM
	var hw := int(w_m * 500_000.0)
	var hh := int(h_m * 500_000.0)
	boxes.append([cx - hw, cz - hh, cx + hw, cz + hh, tag])

func _build_boxes() -> void:
	boxes.clear()
	var solid := ["reception", "linen_shelf", "hamper", "towel_shelf", "snack_tin", "welcome_kiosk",
		"return_shelf", "heat_pump", "tap", "festival_stand"]
	for k in solid:
		if fixtures.has(k):
			_add_box(fixtures[k], 0.75, 0.75, k)
	for k in ["mop_docks", "can_docks"]:
		for p in fixtures.get(k, []):
			_add_box(p, 0.75, 0.75, k)
	if fixtures.has("breezer_dock"):
		_add_box(fixtures["breezer_dock"], 0.75, 0.75, "breezer_dock")
	for letter in rooms:
		var g: Dictionary = rooms[letter]
		_add_box(g["bed"], 1.6, 0.8, "bed_" + letter)
		_add_box(g["plinth"], 0.5, 0.5, "plinth_" + letter)

func _build_nav() -> void:
	nav_block.resize(NAV_W * NAV_H)
	var gr := 180_000
	for j in NAV_H:
		for i in NAV_W:
			var c := nav_cell_center(i, j)
			var blocked := is_wall_tile(tile_of(c.x), tile_of(c.y))
			if blocked:
				for e in entrance:
					if Vector2i(tile_of(c.x), tile_of(c.y)) == e:
						blocked = false
			if not blocked:
				for b in boxes:
					if c.x > b[0] - gr and c.x < b[2] + gr and c.y > b[1] - gr and c.y < b[3] + gr:
						blocked = true
						break
			nav_block[j * NAV_W + i] = 1 if blocked else 0

static func nav_cell_center(i: int, j: int) -> Vector2i:
	return Vector2i(-250_000 + i * NAV_RES, -250_000 + j * NAV_RES)

static func nav_cell_of(x: int, z: int) -> Vector2i:
	return Vector2i(int(floor((x + 500_000) / float(NAV_RES))), int(floor((z + 500_000) / float(NAV_RES))))

func nav_blocked(i: int, j: int) -> bool:
	if i < 0 or j < 0 or i >= NAV_W or j >= NAV_H:
		return true
	return nav_block[j * NAV_W + i] == 1

func tile_center_um(t: Vector2i) -> Vector2i:
	return Vector2i(t.x * SimC.UM, t.y * SimC.UM)

func edge_rooms(edge: String) -> Array:
	return [edge.substr(0, 1), edge.substr(1, 1)]

func pedestal_positions() -> Array:
	return fixtures.get("pedestals", [])

func describe() -> Dictionary:
	return {"id": id, "mirrored": mirrored, "active_rooms": active_rooms,
		"thermal_edges": thermal_edges, "acoustic_edges": acoustic_edges}
