class_name ModelStations
extends RefCounted
## Procedural station, room-fixture and hall-fixture models (§7.3, §12, §17.3).
## Origin = centre of the station's floor tile at y=0, front toward +z (camera).
## Hall stations stay inside 0.75×0.75 m and ≤1.0 m tall (festival stand ≤1.6 m)
## and keep their stock readable from above, because the fixed high camera sees
## mostly tops and +z faces. Static geometry is one cached, shared mesh per
## variant; only animated or toggled parts are separate nodes. State arrives via
## StationNode.apply() (cheap and idempotent) and idle motion via tick().

const FAMILIES := ["slime", "yeti", "dragon", "ghost", "moonwolf", "sprout"]
const KINDS := ["reception", "pedestal", "linen_shelf", "hamper", "towel_shelf", "snack_tin",
	"welcome_kiosk", "return_shelf", "heat_pump", "tap", "tool_dock", "group_bell", "festival_stand",
	"goal_pad", "lift_pad", "bed", "plinth", "thermostat", "water_tray", "drop_pad", "curtain_rail",
	"vent_gate", "shutter"]

const WASHER := Color("#9CC6D3")
const TIN := Color("#7FB0C6")
const TERRA := Color("#C98260")
const SLATE := Color("#56616E")
const MOON_PAPER := Color("#FFEFB5")
const CLOTH := Color("#F1E4CF")
const SOIL_TOP := Color("#8A6A50")

static func kinds() -> PackedStringArray:
	return PackedStringArray(KINDS)

## Builds a station. opts: room_color (Color), side ("north"|"south"),
## palette (layout palette dict), plus per-kind extras documented below.
static func build(kind: String, opts: Dictionary = {}) -> StationNode:
	var st := StationNode.new()
	st.kind = kind
	st.opts = opts
	st.name = "Station_" + kind
	match kind:
		"reception": _reception(st)
		"pedestal": _pedestal(st)
		"linen_shelf": _linen_shelf(st)
		"hamper": _hamper(st)
		"towel_shelf": _towel_shelf(st)
		"snack_tin": _snack_tin(st)
		"welcome_kiosk": _kiosk(st)
		"counter": _counter(st)
		"counter": _counter(st)
		"return_shelf": _return_shelf(st)
		"heat_pump": _heat_pump(st)
		"tap": _tap(st)
		"tool_dock": _tool_dock(st)
		"group_bell": _group_bell(st)
		"festival_stand": _festival(st)
		"goal_pad": _goal_pad(st)
		"lift_pad": _lift_pad(st)
		"bed": _bed(st)
		"plinth": _plinth(st)
		"thermostat": _thermostat(st)
		"water_tray": _water_tray(st)
		"drop_pad": _drop_pad(st)
		"curtain_rail": _curtain_rail(st)
		"vent_gate": _vent_gate(st)
		"shutter": _shutter(st)
		_:
			push_warning("ModelStations: unknown kind '%s'" % kind)
			_mesh(st, "body", _c("st_unknown", _unknown_mesh))
	return st

# ================================================================ pass counter

const COUNTER_TOP := 0.65

## A plain wooden pass counter: anything can be set down on it and picked up
## from either side, so two players can hand items across the counter row.
static func _counter(st: StationNode) -> void:
	_mesh(st, "body", _c("st_counter", _counter_mesh))
	_pivot(st, "top", Vector3(0, COUNTER_TOP, 0))
	st.set_meta("top_y", COUNTER_TOP)

static func _counter_mesh(mk: MeshKit) -> void:
	mk.rbox(Vector3(0, 0.3, 0), Vector3(0.78, 0.6, 0.6), Art.WALNUT, 0.04, Art.WALNUT.lightened(0.1))
	mk.rbox(Vector3(0, 0.62, 0), Vector3(0.88, 0.06, 0.7), Art.CREAM.darkened(0.06), 0.02, Art.CREAM)
	mk.box(Vector3(0, 0.45, 0.305), Vector3(0.62, 0.07, 0.02), Art.CORAL)
	mk.box(Vector3(0, 0.45, -0.305), Vector3(0.62, 0.07, 0.02), Art.CORAL)
	mk.box(Vector3(0, 0.28, 0.305), Vector3(0.2, 0.1, 0.02), Art.BRASS, Art.GOLD)
	for sx in [-0.3, 0.3]:
		mk.box(Vector3(sx, 0.1, 0), Vector3(0.1, 0.2, 0.56), Art.WALNUT.darkened(0.15))

# ================================================================ helpers

static func _c(key: String, fn: Callable) -> ArrayMesh:
	return ModelItems.cached(key, fn)

static func _unknown_mesh(mk: MeshKit) -> void:
	mk.rbox(Vector3(0, 0.3, 0), Vector3(0.6, 0.6, 0.6), Art.ROSE, 0.1)

static func _mesh(st: StationNode, part: String, mesh: Mesh, parent: Node3D = null, pos := Vector3.ZERO, mat: Material = null) -> MeshInstance3D:
	var mi := Art.mesh_instance(mesh, mat if mat != null else Art.toon())
	mi.name = part.to_pascal_case()
	mi.position = pos
	(parent if parent != null else st).add_child(mi)
	st.parts[part] = mi
	return mi

static func _pivot(st: StationNode, part: String, pos: Vector3, parent: Node3D = null, rot_deg := Vector3.ZERO) -> Node3D:
	var n := Node3D.new()
	n.name = part.to_pascal_case()
	n.position = pos
	n.rotation_degrees = rot_deg
	(parent if parent != null else st).add_child(n)
	st.parts[part] = n
	return n

static func _col(v, fallback: Color) -> Color:
	if v is Color:
		return v
	if v is String and String(v) != "":
		return Color(String(v))
	return fallback

static func _pal(st: StationNode, key: String, fallback: Color) -> Color:
	var p: Dictionary = st.opts.get("palette", {})
	return _col(p.get(key), fallback)

static func _room(st: StationNode) -> Color:
	return _col(st.opts.get("room_color"), Art.CORAL)

static func _lit(on: bool) -> Material:
	return ModelItems.lit_mat() if on else ModelItems.dim_mat()

static func _blink(st: StationNode, period := 0.6) -> bool:
	return fmod(st.t, period) < period * 0.5

## Flat ring/disc slightly above the floor (decals and pads).
static func _ring(mk: MeshKit, y: float, r_out: float, r_in: float, col: Color, seg := 20) -> void:
	mk.disc(Vector3(0, y, 0), r_out, col, seg, r_in)

## Chevron lying flat, pointing toward local -x, tip at `pos`.
static func _chevron(mk: MeshKit, pos: Vector3, yaw: float, size: float, col: Color) -> void:
	mk.push_at(pos, Vector3(0, yaw, 0))
	for s in [-1.0, 1.0]:
		mk.push_at(Vector3(size * 0.38, 0, s * size * 0.3), Vector3(0, s * 40.0, 0))
		mk.box(Vector3.ZERO, Vector3(size * 0.95, 0.008, size * 0.26), col)
		mk.pop()
	mk.pop()

## Rising steam puffs (shared haze material, individually animated).
static func _steam(st: StationNode, part: String, pos: Vector3, count := 3, r := 0.06, parent: Node3D = null) -> void:
	var root := _pivot(st, part, pos, parent)
	var mesh := _c("st_puff_%.3f" % r, _puff_mesh.bind(r))
	for i in count:
		var mi := Art.mesh_instance(mesh, ModelItems.haze_mat(0.6))
		mi.name = "Puff%d" % i
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)

static func _puff_mesh(mk: MeshKit, r: float) -> void:
	mk.jitter = 0.0
	mk.sphere(Vector3.ZERO, r, Art.WHITE, 3, 7)
	mk.sphere(Vector3(r * 0.7, -r * 0.2, 0), r * 0.7, Art.WHITE, 2, 6)

static func _steam_tick(st: StationNode, part: String, rise := 0.35, speed := 0.45, drift := 0.06) -> void:
	var root: Node3D = st.parts.get(part)
	if root == null or not root.visible:
		return
	var n := root.get_child_count()
	for i in n:
		var c: Node3D = root.get_child(i)
		var k := fmod(st.t * speed + float(i) / n, 1.0)
		c.position = Vector3(sin(k * 5.0 + i) * drift, k * rise, -k * drift * 0.5)
		var s := 0.5 + k * 0.9
		if k > 0.75:
			s *= 1.0 - (k - 0.75) * 3.2
		c.scale = Vector3.ONE * maxf(0.01, s)

## Small rubbery reset switch (§9.6) with lever + lamp; parts trip_lever/trip_lamp.
static func _trip_switch(st: StationNode, pos: Vector3, parent: Node3D = null, rot_y := 0.0) -> void:
	var root := _pivot(st, "trip", pos, parent, Vector3(0, rot_y, 0))
	_mesh(st, "trip_box", _c("st_trip_box", _trip_box_mesh), root)
	var lever := _pivot(st, "trip_lever", Vector3(-0.02, 0.07, 0), root, Vector3(-20, 0, 0))
	_mesh(st, "trip_lever_mesh", _c("st_trip_lever", _trip_lever_mesh), lever)
	_mesh(st, "trip_lamp", _c("st_trip_lamp", _trip_lamp_mesh), root, Vector3.ZERO, ModelItems.dim_mat())

static func _trip_box_mesh(mk: MeshKit) -> void:
	mk.rbox(Vector3(0, 0.035, 0), Vector3(0.14, 0.07, 0.1), Art.CREAM.darkened(0.1), 0.03, Art.CREAM)
	mk.box(Vector3(-0.02, 0.071, 0), Vector3(0.05, 0.006, 0.06), SLATE)

static func _trip_lever_mesh(mk: MeshKit) -> void:
	mk.cyl(Vector3.ZERO, 0.018, 0.075, Art.CORAL.darkened(0.08), 6)
	mk.sphere(Vector3(0, 0.085, 0), 0.034, Art.CORAL, 2, 6)

static func _trip_lamp_mesh(mk: MeshKit) -> void:
	mk.sphere(Vector3(0.045, 0.085, 0.0), 0.026, Art.GOLD.lightened(0.1), 2, 6)

## Hanging "having a little nap" card shown while a fixture is tripped.
static func _trip_tag_mesh(mk: MeshKit, w: float) -> void:
	mk.box(Vector3(0, -0.07, 0), Vector3(w, 0.13, 0.02), Art.PLUM, Art.PLUM.lightened(0.15))
	for i in 2:
		var s := 0.6 + 0.4 * i
		mk.push_at(Vector3(-0.04 + i * 0.07, -0.07 + i * 0.015, 0.012), Vector3.ZERO, Vector3(s, s, 1))
		mk.box(Vector3(0, 0.025, 0), Vector3(0.05, 0.012, 0.006), Art.CREAM)
		mk.box(Vector3(0, -0.025, 0), Vector3(0.05, 0.012, 0.006), Art.CREAM)
		mk.push_at(Vector3.ZERO, Vector3(0, 0, 45))
		mk.box(Vector3.ZERO, Vector3(0.068, 0.012, 0.006), Art.CREAM)
		mk.pop()
		mk.pop()
	for s2 in [-1.0, 1.0]:
		mk.box(Vector3(s2 * w * 0.35, 0.02, 0), Vector3(0.01, 0.05, 0.01), Art.CREAM.darkened(0.2))

static func _trip_apply(st: StationNode, s: Dictionary) -> void:
	_trip_set(st, bool(s.get("tripped", false)), bool(s.get("warn", false)))

static func _trip_set(st: StationNode, tripped: bool, warn_in: bool) -> void:
	var warn := warn_in and not tripped
	var c1 := st.changed("tripped", tripped)
	var c2 := st.changed("warn", warn)
	if not (c1 or c2):
		return
	st.anim["trip"] = 2 if tripped else (1 if warn else 0)
	var lever: Node3D = st.parts["trip_lever"]
	lever.rotation_degrees = Vector3(70, 0, 0) if tripped else Vector3(-20, 0, 0)
	st.set_part_material("trip_lamp", _lit(tripped))
	st.show_part("trip_tag", tripped)

static func _trip_tick(st: StationNode) -> void:
	if int(st.anim.get("trip", 0)) != 1:
		return
	st.set_part_material("trip_lamp", _lit(_blink(st, 0.5)))
	var lever: Node3D = st.parts["trip_lever"]
	lever.rotation_degrees = Vector3(-20.0 + sin(st.t * 20.0) * 18.0, 0, 0)

# ================================================================ reception

static func _reception(st: StationNode) -> void:
	var acc := _pal(st, "accent", Art.CORAL)
	_mesh(st, "body", _c("st_reception_" + acc.to_html(), _reception_mesh.bind(acc)))
	_mesh(st, "tickets", _c("st_reception_tk_0", _ticket_stack.bind(0)), null, Vector3(0, 0.77, 0))
	st.apply_fn = _reception_apply
	st.apply({"bench": 0})

static func _reception_mesh(mk: MeshKit, acc: Color) -> void:
	var wood := Art.WALNUT
	mk.rbox(Vector3(0, 0.04, 0), Vector3(0.68, 0.08, 0.52), wood.darkened(0.25), 0.06)
	mk.rbox(Vector3(0, 0.39, 0), Vector3(0.72, 0.62, 0.56), wood, 0.07, wood.lightened(0.1))
	for sz in [1.0, -1.0]:
		mk.box(Vector3(0, 0.38, sz * 0.282), Vector3(0.54, 0.4, 0.02), acc.darkened(0.04), acc.lightened(0.15))
		mk.push_at(Vector3(0, 0.4, sz * 0.296), Vector3(0, 0 if sz > 0 else 180, 45))
		mk.box(Vector3.ZERO, Vector3(0.14, 0.14, 0.012), Art.GOLD)
		mk.pop()
		mk.box(Vector3(0, 0.68, sz * 0.3), Vector3(0.7, 0.035, 0.03), Art.BRASS)
	mk.rbox(Vector3(0, 0.735, 0), Vector3(0.8, 0.07, 0.64), Art.CREAM.darkened(0.12), 0.08, Art.CREAM)
	# Open guest book.
	var bx := -0.17
	mk.rbox(Vector3(bx, 0.782, 0.03), Vector3(0.3, 0.025, 0.23), Art.PLUM, 0.03, Art.PLUM.lightened(0.1))
	for sx in [-1.0, 1.0]:
		mk.push_at(Vector3(bx + sx * 0.068, 0.8, 0.03), Vector3(0, 0, -sx * 7.0))
		mk.box(Vector3.ZERO, Vector3(0.13, 0.016, 0.2), Art.WHITE.darkened(0.04), Art.WHITE)
		mk.pop()
	mk.box(Vector3(bx + 0.02, 0.786, 0.15), Vector3(0.03, 0.012, 0.06), Art.CORAL)
	# Brass service bell.
	var b := Vector3(0.21, 0.77, -0.07)
	mk.cyl(b, 0.09, 0.024, wood.darkened(0.15), 10, wood.lightened(0.05))
	mk.sphere(b + Vector3(0, 0.024, 0), 0.08, Art.BRASS, 4, 10, Vector3(1, 0.9, 1), Art.BRASS.darkened(0.1))
	mk.cyl(b + Vector3(0, 0.09, 0), 0.014, 0.03, Art.BRASS.darkened(0.2), 5)
	mk.sphere(b + Vector3(0, 0.125, 0), 0.026, Art.GOLD.lightened(0.1), 2, 6)

## Overflow tickets as little tent cards along the counter front (two rows of four).
static func _ticket_stack(mk: MeshKit, n: int) -> void:
	for i in mini(n, 8):
		var fam: String = FAMILIES[(i * 5 + 2) % 6]
		var x := -0.25 + (i % 4) * 0.165 + (0.04 if i >= 4 else 0.0)
		var z := 0.255 if i < 4 else 0.165
		mk.push_at(Vector3(x, 0, z), Vector3(0, float((i * 29) % 20) - 10.0, 0), Vector3(0.55, 0.55, 0.55))
		ModelItems.ticket(mk, Art.FAMILY_COLORS[fam])
		mk.pop()

static func _reception_apply(st: StationNode, s: Dictionary) -> void:
	var n := clampi(int(s.get("bench", 0)), 0, 8)
	if st.changed("bench", n):
		st.set_part_mesh("tickets", _c("st_reception_tk_%d" % n, _ticket_stack.bind(n)))

# ================================================================ pedestal

static func _pedestal(st: StationNode) -> void:
	_mesh(st, "body", _c("st_pedestal", _pedestal_mesh))
	var clip := _pivot(st, "clip", Vector3(0, 0.56, 0.02))
	_mesh(st, "clip_mesh", _c("st_pedestal_clip", _pedestal_clip), clip)
	_pivot(st, "top", Vector3(0, 0.58, 0))
	st.set_meta("top_y", 0.58)
	st.apply_fn = _pedestal_apply
	st.apply({"occupied": false})

static func _pedestal_mesh(mk: MeshKit) -> void:
	mk.cyl(Vector3.ZERO, 0.15, 0.04, Art.WALNUT.darkened(0.1), 10, Art.WALNUT.lightened(0.12), 0.13)
	mk.cyl(Vector3(0, 0.04, 0), 0.03, 0.5, Art.BRASS, 6)
	mk.torus(Vector3(0, 0.06, 0), 0.045, 0.014, Art.BRASS.darkened(0.15), 8, 3)
	mk.cyl(Vector3(0, 0.52, 0), 0.06, 0.04, Art.BRASS.darkened(0.1), 8, Art.GOLD)
	mk.box(Vector3(0, 0.6, -0.02), Vector3(0.12, 0.08, 0.02), Art.BRASS.darkened(0.05), Art.GOLD)

static func _pedestal_clip(mk: MeshKit) -> void:
	mk.box(Vector3(0, 0.04, 0), Vector3(0.12, 0.08, 0.02), Art.BRASS, Art.GOLD)
	mk.sphere(Vector3(0, 0.085, 0.0), 0.025, Art.CORAL, 2, 6)

static func _pedestal_apply(st: StationNode, s: Dictionary) -> void:
	var occ := bool(s.get("occupied", false))
	if st.changed("occupied", occ):
		var clip: Node3D = st.parts["clip"]
		clip.rotation.x = 0.0 if occ else 0.55

# ================================================================ linen shelf + press

static func _linen_shelf(st: StationNode) -> void:
	_mesh(st, "body", _c("st_linen", _linen_mesh))
	_mesh(st, "stock", _c("st_linen_stock_0", _linen_stock.bind(0)))
	var press := _pivot(st, "press", Vector3(0.255, 0.64, 0))
	_mesh(st, "press_mesh", _c("st_linen_iron", _linen_iron), press)
	var bar := _pivot(st, "press_bar", Vector3(0.255, 0.115, 0.258))
	_mesh(st, "press_bar_mesh", _c("st_linen_bar", _linen_bar), bar)
	_mesh(st, "press_sheet", _c("st_linen_sheet", _linen_sheet))
	_steam(st, "steam", Vector3(0.255, 0.74, 0.02), 3, 0.05)
	st.apply_fn = _linen_apply
	st.tick_fn = _linen_tick
	st.apply({"count": 0, "pressing": false, "press_progress": 0.0})

static func _linen_mesh(mk: MeshKit) -> void:
	var wood := Art.WALNUT
	var cx := -0.125
	var d := 0.56
	for x in [-0.35, 0.1]:
		mk.box(Vector3(x, 0.42, 0), Vector3(0.04, 0.84, d), wood, wood.lightened(0.12))
		for sz0 in [-1.0, 1.0]:
			mk.sphere(Vector3(x, 0.855, sz0 * 0.25), 0.036, Art.BRASS, 2, 6)
	for y in [0.06, 0.32, 0.58]:
		mk.box(Vector3(cx, y, 0), Vector3(0.43, 0.03, d - 0.02), wood.lightened(0.06), wood.lightened(0.22))
		for sz1 in [-1.0, 1.0]:
			mk.box(Vector3(cx, y, sz1 * 0.272), Vector3(0.43, 0.034, 0.014), Art.SKY)
	ModelItems.rod(mk, Vector3(-0.35, 0.8, -0.25), Vector3(0.1, 0.8, -0.25), 0.018, Art.BRASS, 6)
	for sz in [-1.0, 1.0]:
		for sx in [-0.33, 0.08]:
			mk.box(Vector3(sx, 0.022, sz * 0.24), Vector3(0.05, 0.045, 0.05), wood.darkened(0.25))
	# Emergency press attachment on +x.
	mk.rbox(Vector3(0.255, 0.26, 0), Vector3(0.22, 0.52, 0.5), Art.CORAL.darkened(0.05), 0.05, Art.CORAL)
	mk.rbox(Vector3(0.255, 0.54, 0), Vector3(0.24, 0.04, 0.52), Art.CREAM.darkened(0.08), 0.04, Art.CREAM)
	mk.box(Vector3(0.255, 0.561, 0), Vector3(0.05, 0.004, 0.5), Art.SKY.lightened(0.1))
	for sz2 in [-1.0, 1.0]:
		mk.box(Vector3(0.255, 0.26, sz2 * 0.252), Vector3(0.065, 0.31, 0.012), SLATE)
	mk.box(Vector3(0.255, 0.44, 0.255), Vector3(0.12, 0.05, 0.012), Art.GOLD)

static func _linen_stock(mk: MeshKit, n: int) -> void:
	var idx := 0
	var tops := [0.075, 0.335, 0.595]
	for tier in 3:
		for lvl in 2:
			for col in 2:
				if idx >= n:
					return
				var x := -0.125 + (float(col) - 0.5) * 0.205
				var y: float = tops[tier] + lvl * 0.105
				mk.push_at(Vector3(x + (0.006 if lvl == 1 else 0.0), y, 0))
				ModelItems.linen_stack(mk, Vector3(0.19, 0.1, 0.46), 2)
				mk.pop()
				idx += 1

static func _linen_iron(mk: MeshKit) -> void:
	mk.rbox(Vector3(0, 0.035, 0), Vector3(0.19, 0.07, 0.32), Art.BRASS.darkened(0.06), 0.06, Art.BRASS.lightened(0.1))
	mk.box(Vector3(0, 0.004, 0), Vector3(0.2, 0.008, 0.33), Art.STONE.lightened(0.2))
	for sz in [-1.0, 1.0]:
		mk.box(Vector3(0, 0.1, sz * 0.09), Vector3(0.03, 0.07, 0.03), Art.WALNUT)
	mk.rbox(Vector3(0, 0.145, 0), Vector3(0.05, 0.035, 0.24), Art.WALNUT.lightened(0.1), 0.015)
	mk.sphere(Vector3(0.06, 0.075, 0.1), 0.022, Art.CORAL, 2, 5)

static func _linen_bar(mk: MeshKit) -> void:
	mk.box(Vector3(0, 0.135, 0), Vector3(0.042, 0.27, 0.012), Art.GOLD, Art.GOLD)

static func _linen_sheet(mk: MeshKit) -> void:
	mk.box(Vector3(0.255, 0.566, 0.0), Vector3(0.2, 0.012, 0.36), Art.WHITE, Art.WHITE)
	mk.box(Vector3(0.255, 0.567, 0.0), Vector3(0.05, 0.012, 0.362), Art.SKY)

static func _linen_apply(st: StationNode, s: Dictionary) -> void:
	var n := clampi(int(s.get("count", 0)), 0, 12)
	if st.changed("count", n):
		st.set_part_mesh("stock", _c("st_linen_stock_%d" % n, _linen_stock.bind(n)))
	var pressing := bool(s.get("pressing", false))
	if st.changed("pressing", pressing):
		st.anim["pressing"] = pressing
		st.show_part("steam", pressing)
		st.show_part("press_sheet", pressing)
		if not pressing:
			var iron: Node3D = st.parts["press"]
			iron.position.y = 0.64
	var p := clampf(float(s.get("press_progress", 0.0)), 0.0, 1.0)
	if st.changed("press_progress", snappedf(p, 0.02)):
		var bar: Node3D = st.parts["press_bar"]
		bar.visible = p > 0.01
		bar.scale.y = maxf(0.04, p)

static func _linen_tick(st: StationNode, dt: float) -> void:
	if st.anim.get("pressing", false):
		var iron: Node3D = st.parts["press"]
		iron.position.y = 0.578 + absf(sin(st.t * 5.0)) * 0.05
		_steam_tick(st, "steam", 0.3, 0.7)

# ================================================================ hamper + washer

const BASKET_X := -0.17
const WASH_X := 0.195

static func _hamper(st: StationNode) -> void:
	_mesh(st, "body", _c("st_hamper", _hamper_mesh))
	_mesh(st, "bundles", _c("st_hamper_q_0", _hamper_bundles.bind(0)))
	var drum := _pivot(st, "drum", Vector3(WASH_X, 0.3, 0))
	_mesh(st, "drum_mesh", _c("st_hamper_drum", _hamper_drum), drum)
	var dial := _pivot(st, "dial", Vector3(WASH_X + 0.06, 0.62, -0.06))
	_mesh(st, "dial_mesh", _c("st_hamper_dial", _hamper_dial), dial)
	_mesh(st, "lamp_wash", _c("st_lamp_sage", _lamp_mesh.bind(Art.SAGE.lightened(0.15), 0.036)), null, Vector3(WASH_X - 0.08, 0.62, 0.13), ModelItems.dim_mat())
	_mesh(st, "lamp_full", _c("st_lamp_coral", _lamp_mesh.bind(Art.CORAL.lightened(0.1), 0.036)), null, Vector3(WASH_X + 0.06, 0.62, 0.13), ModelItems.dim_mat())
	st.apply_fn = _hamper_apply
	st.tick_fn = _hamper_tick
	st.apply({"queue": 0, "washing": false, "cycle": 0.0, "full": false})

static func _lamp_mesh(mk: MeshKit, col: Color, r: float) -> void:
	mk.cyl(Vector3(0, -0.005, 0), r * 1.25, 0.015, Art.BRASS.darkened(0.1), 8)
	mk.sphere(Vector3(0, 0.012, 0), r, col, 3, 8, Vector3(1, 0.8, 1))

static func _hamper_mesh(mk: MeshKit) -> void:
	var b := Vector3(BASKET_X, 0, 0)
	ModelItems.tube(mk, b, 0.16, 0.19, 0.48, ModelItems.WICKER, ModelItems.WICKER.darkened(0.35), 10, 0.025, 0.2, Art.WALNUT.lightened(0.15))
	for y in [0.12, 0.3]:
		mk.torus(b + Vector3(0, y, 0), 0.16 + 0.03 * y / 0.48 + 0.004, 0.016, ModelItems.WICKER.darkened(0.18), 10, 3)
	mk.torus(b + Vector3(0, 0.48, 0), 0.19, 0.026, Art.WALNUT.lightened(0.18), 10, 4)
	for sx in [-1.0, 1.0]:
		mk.push_at(b + Vector3(0, 0.44, sx * 0.19), Vector3(90, 0, 0))
		mk.torus(Vector3.ZERO, 0.05, 0.014, Art.WALNUT.lightened(0.1), 8, 3)
		mk.pop()
	# Little round-window washer.
	var w := Vector3(WASH_X, 0, 0)
	mk.box(w + Vector3(0, 0.025, 0), Vector3(0.3, 0.05, 0.44), Art.WALNUT.darkened(0.2))
	mk.rbox(w + Vector3(0, 0.33, 0), Vector3(0.34, 0.58, 0.5), WASHER, 0.07, Art.CREAM)
	for sz in [1.0, -1.0]:
		mk.push_at(w + Vector3(0, 0.3, sz * 0.252), Vector3(90, 0, 0))
		mk.torus(Vector3.ZERO, 0.118, 0.032, Art.BRASS, 12, 4)
		mk.pop()
		mk.box(w + Vector3(0.0, 0.56, sz * 0.25), Vector3(0.26, 0.05, 0.012), WASHER.darkened(0.15))
	mk.box(w + Vector3(0, 0.63, -0.17), Vector3(0.3, 0.04, 0.1), Art.CREAM.darkened(0.1), Art.CREAM)

static func _hamper_drum(mk: MeshKit) -> void:
	for back in [false, true]:
		mk.push_at(Vector3.ZERO, Vector3(0, 180.0 if back else 0.0, 0))
		mk.push_at(Vector3(0, 0, 0.252))
		ModelItems.poly_xy(mk, ModelItems.circle_pts(0.1, 12), 0.008, ModelItems.GLASS.darkened(0.1), ModelItems.GLASS)
		mk.push_at(Vector3(0.035, 0.03, 0.006))
		ModelItems.poly_xy(mk, ModelItems.circle_pts(0.045, 7, 1.2, 0.9), 0.008, ModelItems.DIRTY)
		mk.pop()
		mk.push_at(Vector3(-0.04, -0.035, 0.006))
		ModelItems.poly_xy(mk, ModelItems.circle_pts(0.035, 7, 1.3, 0.8), 0.008, Art.CORAL)
		mk.pop()
		for p in [Vector2(-0.05, 0.04), Vector2(0.05, -0.05), Vector2(0.0, 0.065)]:
			mk.push_at(Vector3(p.x, p.y, 0.008))
			ModelItems.poly_xy(mk, ModelItems.circle_pts(0.016, 6), 0.006, Art.WHITE)
			mk.pop()
		mk.pop()
		mk.pop()

static func _hamper_dial(mk: MeshKit) -> void:
	mk.cyl(Vector3.ZERO, 0.05, 0.03, Art.BRASS.darkened(0.08), 8, Art.BRASS.lightened(0.1))
	mk.box(Vector3(0, 0.034, -0.025), Vector3(0.018, 0.012, 0.05), Art.INK.lightened(0.1))

static func _hamper_bundles(mk: MeshKit, n: int) -> void:
	var spots := [Vector3(0.06, 0.25, 0.05), Vector3(-0.07, 0.25, 0.03), Vector3(0.0, 0.25, -0.08),
		Vector3(-0.01, 0.34, 0.01), Vector3(0.08, 0.37, -0.05), Vector3(-0.08, 0.39, 0.07),
		Vector3(0.03, 0.47, 0.06), Vector3(-0.04, 0.52, -0.03)]
	for i in mini(n, spots.size()):
		var p: Vector3 = spots[i]
		var c := ModelItems.DIRTY.lightened(0.05 * (i % 3)).darkened(0.03 * (i % 2))
		mk.sphere(Vector3(BASKET_X, 0, 0) + p, 0.085, c, 3, 7, Vector3(1.12, 0.78, 1.0), c.darkened(0.1))
		if i % 3 == 0:
			mk.sphere(Vector3(BASKET_X, 0, 0) + p + Vector3(0, 0.06, 0), 0.03, c.darkened(0.15), 2, 5)

static func _hamper_apply(st: StationNode, s: Dictionary) -> void:
	var q := clampi(int(s.get("queue", 0)), 0, 8)
	if st.changed("queue", q):
		st.set_part_mesh("bundles", _c("st_hamper_q_%d" % q, _hamper_bundles.bind(q)))
	var washing := bool(s.get("washing", false))
	if st.changed("washing", washing):
		st.anim["washing"] = washing
		st.set_part_material("lamp_wash", _lit(washing))
	var full := bool(s.get("full", false))
	if st.changed("full", full):
		st.anim["full"] = full
		st.set_part_material("lamp_full", _lit(full))
	var cyc := clampf(float(s.get("cycle", 0.0)), 0.0, 1.0)
	if st.changed("cycle", snappedf(cyc, 0.01)):
		var dial: Node3D = st.parts["dial"]
		dial.rotation.y = -cyc * TAU

static func _hamper_tick(st: StationNode, dt: float) -> void:
	var drum: Node3D = st.parts["drum"]
	if st.anim.get("washing", false):
		drum.rotation.z -= dt * 7.0
		drum.position.x = WASH_X + sin(st.t * 40.0) * 0.004
	if st.anim.get("full", false):
		st.set_part_material("lamp_full", _lit(_blink(st, 0.8)))

# ================================================================ towel shelf

static func _towel_shelf(st: StationNode) -> void:
	_mesh(st, "body", _c("st_towel", _towel_mesh))
	_mesh(st, "stock", _c("st_towel_stock_0", _towel_stock.bind(0)))
	_trip_switch(st, Vector3(0.3, 0.84, 0.1))
	_mesh(st, "trip_tag", _c("st_trip_tag_0.30", _trip_tag_mesh.bind(0.3)), null, Vector3(0, 0.585, 0.25))
	st.apply_fn = _towel_apply
	st.tick_fn = _stock_tick
	st.apply({"count": 0, "tripped": false, "warn": false})

static func _towel_mesh(mk: MeshKit) -> void:
	var wood := Art.WALNUT.lightened(0.05)
	for x in [-0.3, 0.3]:
		mk.rbox(Vector3(x, 0.42, 0), Vector3(0.05, 0.84, 0.48), wood, 0.02, wood.lightened(0.14))
		for sz0 in [-1.0, 1.0]:
			mk.sphere(Vector3(x, 0.855, sz0 * 0.21), 0.036, Art.CORAL, 2, 6)
	for y in [0.06, 0.32, 0.58]:
		mk.box(Vector3(0, y, 0), Vector3(0.56, 0.03, 0.46), wood.lightened(0.06), wood.lightened(0.2))
		for sz1 in [-1.0, 1.0]:
			mk.box(Vector3(0, y, sz1 * 0.232), Vector3(0.56, 0.034, 0.014), Art.CORAL)
	ModelItems.rod(mk, Vector3(-0.3, 0.8, -0.21), Vector3(0.3, 0.8, -0.21), 0.02, Art.BRASS, 6)
	for sz in [-1.0, 1.0]:
		for sx in [-0.28, 0.28]:
			mk.box(Vector3(sx, 0.022, sz * 0.2), Vector3(0.05, 0.045, 0.05), wood.darkened(0.25))

static func _towel_stock(mk: MeshKit, n: int) -> void:
	var tops := [0.075, 0.335, 0.595]
	for i in mini(n, 6):
		var tier := i / 2
		var x := -0.135 if i % 2 == 0 else 0.135
		mk.push_at(Vector3(x, tops[tier], 0))
		ModelItems.towel_fold(mk, Vector3(0.24, 0.12, 0.4))
		mk.pop()

static func _towel_apply(st: StationNode, s: Dictionary) -> void:
	var n := clampi(int(s.get("count", 0)), 0, 6)
	if st.changed("count", n):
		st.set_part_mesh("stock", _c("st_towel_stock_%d" % n, _towel_stock.bind(n)))
	_trip_apply(st, s)

static func _stock_tick(st: StationNode, dt: float) -> void:
	_trip_tick(st)

# ================================================================ snack tin

static func _snack_tin(st: StationNode) -> void:
	_mesh(st, "body", _c("st_snack", _snack_mesh))
	_mesh(st, "stock", _c("st_snack_stock_0", _snack_stock.bind(0)))
	_trip_switch(st, Vector3(0.21, 0.27, 0.21), null, -45.0)
	_mesh(st, "trip_tag", _c("st_trip_tag_0.30", _trip_tag_mesh.bind(0.3)), null, Vector3(0, 0.31, 0.29))
	st.apply_fn = _snack_apply
	st.tick_fn = _stock_tick
	st.apply({"count": 0, "tripped": false, "warn": false})

static func _snack_mesh(mk: MeshKit) -> void:
	mk.cyl(Vector3.ZERO, 0.31, 0.045, Art.WALNUT.darkened(0.1), 12, Art.WALNUT.lightened(0.12))
	var base := Vector3(0, 0.045, 0)
	ModelItems.tube(mk, base, 0.27, 0.27, 0.3, TIN, Art.CREAM.darkened(0.15), 14, 0.022, 0.17, Art.GOLD)
	mk.torus(base + Vector3(0, 0.04, 0), 0.274, 0.02, Art.GOLD, 14, 4)
	mk.torus(base + Vector3(0, 0.29, 0), 0.276, 0.022, Art.GOLD.lightened(0.1), 14, 4)
	for k in 7:
		var a := deg_to_rad(90.0 + (k - 3) * 40.0)
		mk.push_at(base + Vector3(cos(a) * 0.272, 0.165, sin(a) * 0.272), Vector3(0, 90.0 - rad_to_deg(a), 0))
		ModelItems.poly_xy(mk, ModelItems.star_pts(5, 0.05, 0.024), 0.01, Art.CREAM, Art.WHITE)
		mk.pop()

static func _snack_stock(mk: MeshKit, n: int) -> void:
	var order := [270.0, 210.0, 330.0, 150.0, 30.0, 90.0]
	for i in mini(n, 6):
		var a := deg_to_rad(order[i])
		var p := Vector3(cos(a) * 0.14, 0.215, sin(a) * 0.14)
		for k in 4:
			ModelItems.star_cracker(mk, p + Vector3(0, k * 0.034, 0), 0.075, float((i * 23 + k * 17) % 36), 0.032)
	if n > 0:
		ModelItems.star_cracker(mk, Vector3(0, 0.215, 0), 0.075, 9.0, 0.032)

static func _snack_apply(st: StationNode, s: Dictionary) -> void:
	var n := clampi(int(s.get("count", 0)), 0, 6)
	if st.changed("count", n):
		st.set_part_mesh("stock", _c("st_snack_stock_%d" % n, _snack_stock.bind(n)))
	_trip_apply(st, s)

# ================================================================ welcome kiosk

const KIOSK_SLOPE := -40.0
const TILE_X := [-0.235, 0.0, 0.235]
const TILE_Y := [0.09, -0.09]

static func _tile_pos(i: int) -> Vector3:
	return Vector3(TILE_X[i % 3], TILE_Y[i / 3], 0)

static func _kiosk(st: StationNode) -> void:
	var acc := _pal(st, "accent", Art.CORAL)
	_mesh(st, "body", _c("st_kiosk_" + acc.to_html(), _kiosk_mesh.bind(acc)))
	var slope := _pivot(st, "slope", Vector3(0, 0.71, 0.125), null, Vector3(KIOSK_SLOPE, 0, 0))
	_mesh(st, "overlay", _c("st_kiosk_ov_63_-1", _kiosk_overlay.bind(63, -1)), slope)
	_mesh(st, "glow", _c("st_kiosk_glow", _kiosk_glow), slope, Vector3.ZERO, ModelItems.lit_mat())
	_mesh(st, "lamps", _c("st_kiosk_lamps_0", _kiosk_lamps.bind(0)), slope, Vector3.ZERO, ModelItems.lit_mat())
	st.apply_fn = _kiosk_apply
	st.tick_fn = _kiosk_tick
	st.apply({"selected": "", "families": FAMILIES.duplicate(), "needed": []})

static func _kiosk_tile(mk: MeshKit, fam: String, z: float, scale_f := 1.0, frame := Art.WALNUT.darkened(0.15)) -> void:
	var fc: Color = Art.FAMILY_COLORS[fam]
	mk.box(Vector3(0, 0, z), Vector3(0.21, 0.165, 0.014) * Vector3(scale_f, scale_f, 1), frame, frame.lightened(0.1))
	mk.box(Vector3(0, 0, z + 0.006), Vector3(0.18, 0.136, 0.012) * Vector3(scale_f, scale_f, 1), fc.darkened(0.04), fc)
	mk.push_at(Vector3(0, 0, z + 0.014), Vector3.ZERO, Vector3(scale_f, scale_f, 1))
	ModelItems.motif_xy(mk, fam, 0.115, 0.008, ModelItems.motif_color(fam))
	mk.pop()

static func _kiosk_mesh(mk: MeshKit, acc: Color) -> void:
	var wood := Art.WALNUT.lightened(0.1)
	mk.box(Vector3(0, 0.03, 0), Vector3(0.66, 0.06, 0.44), Art.WALNUT.darkened(0.25))
	mk.rbox(Vector3(0, 0.31, 0), Vector3(0.72, 0.5, 0.5), wood, 0.06, wood.lightened(0.1))
	for sz in [1.0, -1.0]:
		mk.box(Vector3(0, 0.5, sz * 0.25), Vector3(0.7, 0.05, 0.02), acc, acc.lightened(0.1))
		mk.box(Vector3(0, 0.24, sz * 0.255), Vector3(0.4, 0.15, 0.025), Art.CREAM.darkened(0.08), Art.CREAM)
		mk.box(Vector3(0, 0.24, sz * 0.27), Vector3(0.12, 0.03, 0.02), Art.BRASS)
		for sx in [-0.29, 0.29]:
			mk.push_at(Vector3(sx, 0.24, sz * 0.256), Vector3(0, 0, 45))
			mk.box(Vector3.ZERO, Vector3(0.06, 0.06, 0.012), Art.GOLD)
			mk.pop()
	# Gabled top with the six family faces on each slope.
	for back in [false, true]:
		mk.push_at(Vector3(0, 0.71, -0.125 if back else 0.125), Vector3(KIOSK_SLOPE, 180.0 if back else 0.0, 0))
		mk.box(Vector3(0, 0, -0.022), Vector3(0.76, 0.41, 0.04), Art.WALNUT, Art.WALNUT.lightened(0.1))
		for i in 6:
			mk.push_at(_tile_pos(i))
			_kiosk_tile(mk, FAMILIES[i], 0.004)
			mk.pop()
		mk.pop()
	for sx2 in [-1.0, 1.0]:
		var x: float = sx2 * 0.37
		var a := Vector3(x, 0.56, 0.25)
		var b := Vector3(x, 0.86, 0.0)
		var c := Vector3(x, 0.56, -0.25)
		if sx2 > 0:
			mk.tri(a, c, b, Art.WALNUT.lightened(0.05))
		else:
			mk.tri(a, b, c, Art.WALNUT.lightened(0.05))
	mk.box(Vector3(0, 0.875, 0), Vector3(0.8, 0.045, 0.08), Art.BRASS.darkened(0.05), Art.GOLD)
	# Gift-bow finial.
	for s in [-1.0, 1.0]:
		mk.push_at(Vector3(s * 0.045, 0.925, 0), Vector3(0, 0, -s * 25.0))
		mk.sphere(Vector3.ZERO, 0.05, acc, 2, 6, Vector3(1.1, 0.65, 0.6))
		mk.pop()
	mk.sphere(Vector3(0, 0.915, 0), 0.026, acc.darkened(0.15), 2, 5)

static func _kiosk_overlay(mk: MeshKit, enabled_mask: int, sel: int) -> void:
	for i in 6:
		var p := _tile_pos(i)
		if ((enabled_mask >> i) & 1) == 0:
			mk.box(p + Vector3(0, 0, 0.02), Vector3(0.205, 0.16, 0.02), Art.WALNUT.lightened(0.12), Art.WALNUT.lightened(0.2))
			for k in 3:
				mk.box(p + Vector3(0, -0.05 + k * 0.05, 0.031), Vector3(0.19, 0.012, 0.004), Art.WALNUT.darkened(0.1))
		elif i == sel:
			mk.push_at(p)
			_kiosk_tile(mk, FAMILIES[i], 0.035, 1.1, Art.GOLD)
			mk.box(Vector3(0, 0, 0.02), Vector3(0.2, 0.15, 0.04), Art.GOLD.darkened(0.15))
			mk.pop()

static func _kiosk_glow(mk: MeshKit) -> void:
	mk.jitter = 0.0
	var c := Art.GOLD.lightened(0.35)
	for s in [-1.0, 1.0]:
		mk.box(Vector3(0, s * 0.105, 0.045), Vector3(0.265, 0.022, 0.012), c)
		mk.box(Vector3(s * 0.128, 0, 0.045), Vector3(0.022, 0.2, 0.012), c)

static func _kiosk_lamps(mk: MeshKit, mask: int) -> void:
	mk.jitter = 0.0
	for i in 6:
		if ((mask >> i) & 1) == 1:
			var p := _tile_pos(i)
			mk.sphere(p + Vector3(0.085, 0.062, 0.04), 0.042, Art.CORAL.lightened(0.2), 2, 7)

## Bitmask of FAMILIES contained in an Array or PackedStringArray.
static func _fam_mask(arr) -> int:
	var m := 0
	for i in 6:
		if FAMILIES[i] in arr:
			m |= 1 << i
	return m

static func _kiosk_apply(st: StationNode, s: Dictionary) -> void:
	var emask := _fam_mask(s.get("families", FAMILIES))
	var sel := FAMILIES.find(String(s.get("selected", "")))
	if sel >= 0 and ((emask >> sel) & 1) == 0:
		sel = -1
	var c1 := st.changed("families", emask)
	var c2 := st.changed("selected", sel)
	if c1 or c2:
		st.set_part_mesh("overlay", _c("st_kiosk_ov_%d_%d" % [emask, sel], _kiosk_overlay.bind(emask, sel)))
		var glow: Node3D = st.parts["glow"]
		glow.visible = sel >= 0
		if sel >= 0:
			glow.position = _tile_pos(sel)
	var nmask := _fam_mask(s.get("needed", [])) & emask
	if st.changed("needed", nmask):
		st.set_part_mesh("lamps", _c("st_kiosk_lamps_%d" % nmask, _kiosk_lamps.bind(nmask)))
		st.anim["needed"] = nmask

static func _kiosk_tick(st: StationNode, dt: float) -> void:
	if int(st.anim.get("needed", 0)) != 0:
		st.show_part("lamps", fmod(st.t, 0.9) < 0.6)

# ================================================================ return shelf + curtain drawer

static func _return_shelf(st: StationNode) -> void:
	_mesh(st, "body", _c("st_return", _return_mesh))
	var on := _pivot(st, "drawer_on", Vector3.ZERO)
	_mesh(st, "drawer_on_mesh", _c("st_return_drawer", _return_drawer), on)
	_mesh(st, "rolls", _c("st_return_rolls_0", _return_rolls.bind(0)), on)
	_mesh(st, "drawer_off", _c("st_return_closed", _return_closed))
	st.apply_fn = _return_apply
	st.apply({"curtains": 0, "curtain_system": false})

static func _return_mesh(mk: MeshKit) -> void:
	var wood := Art.WALNUT
	var cx := -0.16
	for x in [-0.35, 0.03]:
		mk.box(Vector3(x, 0.26, 0), Vector3(0.04, 0.52, 0.56), wood, wood.lightened(0.12))
	for y in [0.04, 0.27]:
		mk.box(Vector3(cx, y, 0), Vector3(0.36, 0.03, 0.54), wood.lightened(0.06), wood.lightened(0.2))
	# Visible folded storage.
	mk.push_at(Vector3(cx - 0.08, 0.055, 0.0))
	ModelItems.linen_stack(mk, Vector3(0.16, 0.12, 0.3), 2)
	mk.pop()
	mk.push_at(Vector3(cx + 0.09, 0.055, 0.02))
	ModelItems.towel_fold(mk, Vector3(0.15, 0.1, 0.26), Art.CORAL)
	mk.pop()
	mk.push_at(Vector3(cx - 0.07, 0.285, 0.0))
	ModelItems.towel_fold(mk, Vector3(0.16, 0.08, 0.26), Art.SAGE)
	mk.pop()
	mk.push_at(Vector3(cx + 0.09, 0.285, 0.0))
	ModelItems.linen_stack(mk, Vector3(0.15, 0.12, 0.28), 2)
	mk.pop()
	# Return tray on top with a big sage return arrow.
	ModelItems.open_box(mk, Vector3(cx, 0.52, 0), Vector3(0.44, 0.08, 0.58), Art.CREAM.darkened(0.12), Art.CREAM.darkened(0.03), 0.03, 0.02, Art.CREAM)
	var y := 0.542
	var g := Art.SAGE.darkened(0.12)
	mk.box(Vector3(cx + 0.0, y, -0.11), Vector3(0.22, 0.012, 0.055), g)
	mk.box(Vector3(cx - 0.11, y, -0.015), Vector3(0.055, 0.012, 0.245), g)
	mk.box(Vector3(cx - 0.04, y, 0.08), Vector3(0.18, 0.012, 0.055), g)
	ModelItems.poly_flat(mk, Vector3(cx + 0.085, y - 0.006, 0.08), [Vector2(0.075, 0), Vector2(-0.035, 0.07), Vector2(-0.035, -0.07)], 0.012, g, g, 0.0)

static func _return_drawer(mk: MeshKit) -> void:
	var x := 0.22
	mk.rbox(Vector3(x, 0.27, 0), Vector3(0.3, 0.5, 0.56), Art.PLUM.darkened(0.05), 0.04, Art.PLUM.lightened(0.1))
	ModelItems.open_box(mk, Vector3(x, 0.52, 0), Vector3(0.3, 0.12, 0.56), Art.PLUM, Art.PLUM.darkened(0.3), 0.03, 0.02, Art.PLUM.lightened(0.15))
	for sz in [1.0, -1.0]:
		mk.box(Vector3(x, 0.25, sz * 0.282), Vector3(0.24, 0.36, 0.012), Art.PLUM.lightened(0.08))
		mk.box(Vector3(x, 0.4, sz * 0.295), Vector3(0.12, 0.028, 0.025), Art.BRASS)
		mk.push_at(Vector3(x + 0.01, 0.22, sz * 0.292), Vector3(0, 0 if sz > 0 else 180, 160))
		ModelItems.crescent_xy(mk, 0.085, 0.05, 0.012, Art.GOLD)
		mk.pop()

static func _return_rolls(mk: MeshKit, n: int) -> void:
	for i in mini(n, 6):
		var layer := i / 2
		var x := 0.22 + (-0.065 if i % 2 == 0 else 0.065)
		mk.push_at(Vector3(x + (0.0 if layer % 2 == 0 else 0.008), 0.54 + layer * 0.13, 0), Vector3(0, 90, 0))
		ModelItems.curtain_roll(mk, 0.48, 0.062)
		mk.pop()

static func _return_closed(mk: MeshKit) -> void:
	var x := 0.22
	mk.rbox(Vector3(x, 0.3, 0), Vector3(0.3, 0.6, 0.56), Art.WALNUT.lightened(0.04), 0.04, Art.WALNUT.lightened(0.15))
	for sz in [1.0, -1.0]:
		mk.box(Vector3(x, 0.3, sz * 0.282), Vector3(0.24, 0.44, 0.012), Art.WALNUT.lightened(0.1))
		mk.box(Vector3(x, 0.44, sz * 0.295), Vector3(0.1, 0.025, 0.02), Art.BRASS)
	mk.box(Vector3(x, 0.612, 0), Vector3(0.32, 0.025, 0.5), CLOTH.darkened(0.05), CLOTH)

static func _return_apply(st: StationNode, s: Dictionary) -> void:
	var on := bool(s.get("curtain_system", false))
	if st.changed("curtain_system", on):
		st.show_part("drawer_on", on)
		st.show_part("drawer_off", not on)
	var n := clampi(int(s.get("curtains", 0)), 0, 6)
	if st.changed("curtains", n):
		st.set_part_mesh("rolls", _c("st_return_rolls_%d" % n, _return_rolls.bind(n)))

# ================================================================ heat pump

static func _heat_pump(st: StationNode) -> void:
	var on := _pivot(st, "on", Vector3.ZERO)
	_mesh(st, "body", _c("st_heat_pump", _hp_mesh), on)
	var panel := _pivot(st, "panel", Vector3(0, 0.36, 0.25), on, Vector3(-16, 0, 0))
	_mesh(st, "panel_mesh", _c("st_hp_panel", _hp_panel), panel)
	_mesh(st, "lamp_hot", _c("st_hp_lamp_hot", _hp_lamp.bind(true)), panel, Vector3(-0.125, -0.005, 0.04), ModelItems.dim_mat())
	_mesh(st, "lamp_cold", _c("st_hp_lamp_cold", _hp_lamp.bind(false)), panel, Vector3(0.125, -0.005, 0.04), ModelItems.dim_mat())
	for side in ["hot", "cold"]:
		var nd := _pivot(st, "needle_" + side, Vector3(-0.125 if side == "hot" else 0.125, -0.06, 0.075), panel)
		_mesh(st, "needle_%s_mesh" % side, _c("st_hp_needle", _hp_needle), nd)
	var lever := _pivot(st, "priority", Vector3(0, -0.1, 0.045), panel)
	_mesh(st, "priority_mesh", _c("st_hp_lever_balanced", _hp_lever.bind(Art.CREAM)), lever)
	_steam(st, "steam", Vector3(0, 0.83, -0.04), 3, 0.06, on)
	_mesh(st, "sheet", _c("st_hp_sheet", _hp_sheet))
	st.apply_fn = _hp_apply
	st.tick_fn = _hp_tick
	st.apply({"enabled": true, "mode": "balanced", "hot_demand": 0, "cold_demand": 0})

static func _hp_mesh(mk: MeshKit) -> void:
	mk.rbox(Vector3(0, 0.04, 0), Vector3(0.66, 0.08, 0.54), Art.WALNUT.darkened(0.15), 0.06, Art.WALNUT.lightened(0.05))
	mk.cyl(Vector3(0, 0.08, 0), 0.25, 0.46, Art.BRASS, 12, Art.BRASS.lightened(0.1))
	for y in [0.15, 0.5]:
		mk.torus(Vector3(0, y, 0), 0.255, 0.022, Art.BRASS.darkened(0.2), 12, 4)
	mk.sphere(Vector3(0, 0.54, 0), 0.25, Art.BRASS.lightened(0.06), 4, 12, Vector3(1, 0.52, 1))
	mk.cyl(Vector3(0, 0.6, -0.04), 0.045, 0.2, Art.BRASS.darkened(0.12), 7)
	mk.cyl(Vector3(0, 0.79, -0.04), 0.065, 0.035, Art.BRASS.darkened(0.2), 7, Art.INK.lightened(0.2))
	# Painted warm/cool side pipes into the floor.
	for s in [-1.0, 1.0]:
		var pc := Art.CORAL if s < 0 else Art.SKY
		ModelItems.rod(mk, Vector3(s * 0.23, 0.32, 0.0), Vector3(s * 0.33, 0.32, 0.0), 0.04, Art.BRASS.darkened(0.1), 6)
		ModelItems.rod(mk, Vector3(s * 0.33, 0.34, 0.0), Vector3(s * 0.33, 0.0, 0.0), 0.04, pc, 6)
		mk.sphere(Vector3(s * 0.33, 0.33, 0), 0.05, Art.BRASS.darkened(0.1), 2, 6)
	# Static twin of the dial panel on the back so the z=9 side also reads as a front.
	mk.push_at(Vector3(0, 0.36, -0.25), Vector3(-16, 180, 0))
	_hp_panel(mk)
	for s2 in [-1.0, 1.0]:
		mk.push_at(Vector3(s2 * 0.125, -0.005, 0.04))
		_hp_lamp(mk, s2 < 0)
		mk.pop()
	mk.pop()

static func _hp_panel(mk: MeshKit) -> void:
	mk.rbox(Vector3(0, 0.0, 0), Vector3(0.54, 0.3, 0.06), Art.WALNUT, 0.04, Art.WALNUT.lightened(0.12))
	mk.box(Vector3(0, -0.005, 0.026), Vector3(0.49, 0.25, 0.02), Art.CREAM.darkened(0.05), Art.CREAM)
	for s in [-1.0, 1.0]:
		mk.push_at(Vector3(s * 0.125, -0.005, 0.04), Vector3(90, 0, 0))
		mk.torus(Vector3.ZERO, 0.1, 0.018, Art.BRASS, 12, 4)
		mk.pop()
	mk.box(Vector3(0, -0.115, 0.04), Vector3(0.05, 0.03, 0.012), SLATE)

## Dial face that doubles as the side's lamp (lit when that side has priority).
static func _hp_lamp(mk: MeshKit, hot: bool) -> void:
	var c := Art.CORAL if hot else Art.SKY
	ModelItems.poly_xy(mk, ModelItems.circle_pts(0.092, 14), 0.02, c.darkened(0.05), c)
	mk.push_at(Vector3(0, 0.02, 0.014))
	if hot:
		ModelItems.sun_xy(mk, 0.1, 0.008, Art.GOLD.lightened(0.15), Art.CREAM)
	else:
		ModelItems.snowflake_xy(mk, 0.1, 0.018, 0.008, Art.WHITE)
	mk.pop()

static func _hp_needle(mk: MeshKit) -> void:
	mk.box(Vector3(0, 0.04, 0.004), Vector3(0.016, 0.08, 0.006), Art.INK)
	mk.sphere(Vector3(0, 0, 0.006), 0.018, Art.BRASS.darkened(0.15), 2, 6)

static func _hp_lever(mk: MeshKit, knob: Color) -> void:
	mk.cyl(Vector3.ZERO, 0.012, 0.11, Art.BRASS.darkened(0.15), 5)
	mk.sphere(Vector3(0, 0.12, 0), 0.034, knob, 2, 7)

static func _hp_sheet(mk: MeshKit) -> void:
	var c := CLOTH
	mk.cyl(Vector3.ZERO, 0.34, 0.6, c.darkened(0.06), 9, c, 0.27)
	mk.sphere(Vector3(0, 0.6, 0), 0.27, c, 3, 9, Vector3(1, 0.5, 1))
	mk.sphere(Vector3(0.0, 0.74, -0.04), 0.075, c, 2, 6, Vector3(1, 1.2, 1))
	for i in 9:
		var a := TAU * (i + 0.5) / 9.0
		mk.sphere(Vector3(cos(a) * 0.33, 0.03, sin(a) * 0.33), 0.06, c.darkened(0.08), 2, 5, Vector3(1, 0.7, 1))
	mk.torus(Vector3(0, 0.46, 0), 0.29, 0.02, Art.CORAL, 10, 3)
	mk.push_at(Vector3(0.16, 0.38, 0.27), Vector3(0, 20, -8))
	mk.box(Vector3.ZERO, Vector3(0.1, 0.07, 0.012), Art.GOLD, Art.GOLD)
	mk.pop()

static func _hp_apply(st: StationNode, s: Dictionary) -> void:
	var en := bool(s.get("enabled", true))
	if st.changed("enabled", en):
		st.show_part("on", en)
		st.show_part("sheet", not en)
	var mode := String(s.get("mode", "balanced"))
	if st.changed("mode", mode):
		var lever: Node3D = st.parts["priority"]
		var knob := Art.CREAM
		match mode:
			"warm":
				lever.rotation.z = 0.65
				knob = Art.CORAL
			"cool":
				lever.rotation.z = -0.65
				knob = Art.SKY
			_:
				lever.rotation.z = 0.0
		st.set_part_mesh("priority_mesh", _c("st_hp_lever_" + mode, _hp_lever.bind(knob)))
		st.set_part_material("lamp_hot", _lit(mode != "cool"))
		st.set_part_material("lamp_cold", _lit(mode != "warm"))
	var dh := clampi(int(s.get("hot_demand", 0)), 0, 6)
	if st.changed("hot", dh):
		(st.parts["needle_hot"] as Node3D).rotation.z = deg_to_rad(70.0 - dh * (140.0 / 6.0))
	var dc := clampi(int(s.get("cold_demand", 0)), 0, 6)
	if st.changed("cold", dc):
		(st.parts["needle_cold"] as Node3D).rotation.z = deg_to_rad(70.0 - dc * (140.0 / 6.0))

static func _hp_tick(st: StationNode, dt: float) -> void:
	if st.last("enabled", true):
		_steam_tick(st, "steam", 0.4, 0.35, 0.05)

# ================================================================ tap

static func _tap(st: StationNode) -> void:
	_mesh(st, "body", _c("st_tap", _tap_mesh))
	var on := _pivot(st, "on", Vector3.ZERO)
	_mesh(st, "faucet", _c("st_tap_faucet", _tap_faucet), on)
	var drip := _pivot(st, "drip", Vector3(0, 0.7, -0.03), on)
	_mesh(st, "drip_mesh", _c("st_tap_drip", _tap_drip), drip)
	_mesh(st, "covered", _c("st_tap_cover", _tap_cover))
	st.apply_fn = _tap_apply
	st.tick_fn = _tap_tick
	st.apply({"enabled": true})

static func _tap_mesh(mk: MeshKit) -> void:
	var wood := Art.WALNUT.lightened(0.08)
	mk.rbox(Vector3(0, 0.25, 0), Vector3(0.56, 0.5, 0.46), wood, 0.05, wood.lightened(0.1))
	for sz in [1.0, -1.0]:
		for sx in [-0.13, 0.13]:
			mk.box(Vector3(sx, 0.25, sz * 0.232), Vector3(0.22, 0.34, 0.016), wood.lightened(0.08))
			mk.sphere(Vector3(sx * 0.3, 0.3, sz * 0.245), 0.022, Art.BRASS, 2, 5)
	mk.rbox(Vector3(0, 0.525, 0), Vector3(0.64, 0.05, 0.52), Art.SKY.lightened(0.25).darkened(0.08), 0.05, Art.SKY.lightened(0.35))
	ModelItems.tube(mk, Vector3(0, 0.55, 0.04), 0.13, 0.2, 0.12, Art.WHITE.darkened(0.06), Color("#DCE9EC"), 12, 0.022, 0.03, Art.WHITE)

static func _tap_faucet(mk: MeshKit) -> void:
	mk.cyl(Vector3(0, 0.55, -0.19), 0.045, 0.03, Art.BRASS.darkened(0.15), 8)
	mk.cyl(Vector3(0, 0.55, -0.19), 0.03, 0.25, Art.BRASS, 7)
	ModelItems.rod(mk, Vector3(0, 0.78, -0.19), Vector3(0, 0.78, -0.03), 0.026, Art.BRASS.lightened(0.05), 7)
	mk.sphere(Vector3(0, 0.78, -0.19), 0.035, Art.BRASS, 2, 7)
	ModelItems.rod(mk, Vector3(0, 0.79, -0.03), Vector3(0, 0.72, -0.03), 0.03, Art.BRASS.darkened(0.05), 7)
	for s in [-1.0, 1.0]:
		ModelItems.rod(mk, Vector3(0, 0.68, -0.19), Vector3(s * 0.09, 0.68, -0.19), 0.016, Art.BRASS.darkened(0.1), 5)
		mk.sphere(Vector3(s * 0.1, 0.69, -0.19), 0.04, Art.CORAL if s < 0 else Art.SKY, 2, 7, Vector3(1, 0.8, 1))
	mk.disc(Vector3(0, 0.645, 0.04), 0.17, Art.WATER.lightened(0.15), 12)
	mk.disc(Vector3(0.05, 0.647, 0.08), 0.03, Art.WHITE, 6)

static func _tap_drip(mk: MeshKit) -> void:
	mk.sphere(Vector3.ZERO, 0.022, Color("#8FD0E8"), 2, 6, Vector3(1, 1.3, 1))

static func _tap_cover(mk: MeshKit) -> void:
	mk.rbox(Vector3(0, 0.675, 0.04), Vector3(0.44, 0.03, 0.44), Art.WALNUT.lightened(0.2), 0.08, Art.WALNUT.lightened(0.3))
	mk.cyl(Vector3(0, 0.55, -0.19), 0.08, 0.26, CLOTH.darkened(0.05), 7, CLOTH, 0.04)
	mk.sphere(Vector3(0, 0.82, -0.17), 0.06, CLOTH, 2, 6)
	mk.torus(Vector3(0, 0.72, -0.19), 0.055, 0.014, Art.CORAL, 7, 3)
	mk.cyl(Vector3(0.1, 0.69, 0.1), 0.065, 0.09, TERRA, 7, SOIL_TOP, 0.075)
	for k in 4:
		var a := TAU * k / 4.0 + 0.4
		mk.push_at(Vector3(0.1 + cos(a) * 0.03, 0.8, 0.1 + sin(a) * 0.03), Vector3(cos(a) * 35.0, 0, -sin(a) * 35.0))
		mk.sphere(Vector3(0, 0.05, 0), 0.06, Art.LEAF.lightened(0.04 * k), 2, 5, Vector3(0.6, 1.4, 0.5))
		mk.pop()

static func _tap_apply(st: StationNode, s: Dictionary) -> void:
	var en := bool(s.get("enabled", true))
	if st.changed("enabled", en):
		st.show_part("on", en)
		st.show_part("covered", not en)

static func _tap_tick(st: StationNode, dt: float) -> void:
	var d: Node3D = st.parts["drip"]
	if not d.visible:
		return
	var k := fmod(st.t, 1.6) / 1.6
	d.position.y = 0.7 - maxf(0.0, k - 0.6) * 0.15
	d.scale = Vector3.ONE * (minf(1.0, k * 2.5) if k < 0.97 else 0.01)

# ================================================================ tool dock

static func _dock_color(tool: String) -> Color:
	match tool:
		"breezer": return Art.PLUM.lerp(Art.CREAM, 0.3)
		"can": return Art.SAGE.lerp(Art.CREAM, 0.25)
		_: return Art.SKY.lerp(Art.CREAM, 0.25)

static func _tool_dock(st: StationNode) -> void:
	var tool := String(st.opts.get("tool", "mop"))
	var idx := clampi(int(st.opts.get("index", 0)), 0, 2)
	var col := _dock_color(tool)
	_mesh(st, "body", _c("st_dock_" + tool, _dock_mesh.bind(col)))
	_mesh(st, "sign", _c("st_dock_sign_%s_%d" % [tool, idx], _dock_sign.bind(col, idx)))
	_mesh(st, "silhouette", _c("st_dock_sil_" + tool, _dock_sil.bind(tool, col)))
	_mesh(st, "cover", _c("st_dock_cover", _dock_cover))
	st.apply_fn = _dock_apply
	st.apply({"occupied": false, "enabled": true})

static func _dock_mesh(mk: MeshKit, col: Color) -> void:
	mk.rbox(Vector3(0, 0.014, 0), Vector3(0.68, 0.028, 0.68), col.darkened(0.25), 0.14, col.darkened(0.05))
	ModelItems.rod(mk, Vector3(-0.29, 0.0, -0.29), Vector3(-0.29, 0.44, -0.29), 0.032, Art.WALNUT, 6)
	mk.cyl(Vector3(-0.29, 0.0, -0.29), 0.06, 0.035, Art.WALNUT.darkened(0.15), 6)

static func _dock_sign(mk: MeshKit, col: Color, idx: int) -> void:
	mk.push_at(Vector3(-0.29, 0.5, -0.255), Vector3(-20, 0, 0))
	ModelItems.poly_xy(mk, ModelItems.circle_pts(0.095, 12), 0.03, Art.CREAM.darkened(0.06), Art.CREAM)
	mk.push_at(Vector3(0, 0, 0.016))
	ModelItems.poly_xy(mk, ModelItems.circle_pts(0.075, 12), 0.01, col)
	mk.pop()
	for i in idx + 1:
		mk.push_at(Vector3((i - idx * 0.5) * 0.045, 0, 0.024))
		ModelItems.poly_xy(mk, ModelItems.circle_pts(0.017, 6), 0.008, Art.CREAM)
		mk.pop()
	mk.pop()

static func _dock_sil(mk: MeshKit, tool: String, col: Color) -> void:
	mk.jitter = 0.0
	var y := 0.029
	for pass_i in 2:
		var grow := 0.022 if pass_i == 0 else 0.0
		var c := col.darkened(0.35) if pass_i == 0 else Art.CREAM
		var yy := y + 0.002 * pass_i
		match tool:
			"mop":
				mk.push_at(Vector3(0, yy, 0), Vector3(0, -45, 0))
				mk.box(Vector3(-0.1, 0.002, 0), Vector3(0.78 + grow, 0.004, 0.055 + grow), c)
				ModelItems.poly_flat(mk, Vector3(0.42, 0, 0), ModelItems.circle_pts(0.12 + grow * 0.5, 12, 0.9, 1.15), 0.004, c, c)
				mk.pop()
			"breezer":
				ModelItems.poly_flat(mk, Vector3(0, yy, -0.06), ModelItems.circle_pts(0.145 + grow * 0.5, 14), 0.004, c, c)
				mk.box(Vector3(0, yy + 0.002, 0.15), Vector3(0.06 + grow, 0.004, 0.2 + grow), c)
			_:
				ModelItems.poly_flat(mk, Vector3(-0.02, yy, 0), ModelItems.circle_pts(0.12 + grow * 0.5, 12), 0.004, c, c)
				mk.push_at(Vector3(0.14, yy + 0.002, 0), Vector3(0, 0, 0))
				mk.box(Vector3.ZERO, Vector3(0.2 + grow, 0.004, 0.05 + grow), c)
				mk.pop()
				ModelItems.poly_flat(mk, Vector3(0.26, yy, 0), ModelItems.circle_pts(0.045 + grow * 0.5, 8), 0.004, c, c)
				mk.box(Vector3(-0.17, yy + 0.002, 0), Vector3(0.07 + grow, 0.004, 0.14 + grow), c)

static func _dock_cover(mk: MeshKit) -> void:
	mk.rbox(Vector3(0, 0.045, 0), Vector3(0.76, 0.05, 0.76), CLOTH.darkened(0.06), 0.16, CLOTH)
	for i in 6:
		var a := TAU * (i + 0.5) / 6.0
		mk.sphere(Vector3(cos(a) * 0.2, 0.07, sin(a) * 0.2), 0.08, CLOTH.darkened(0.03 * (i % 2)), 2, 6, Vector3(1.4, 0.35, 1.0))
	mk.cyl(Vector3(-0.29, 0.03, -0.29), 0.09, 0.52, CLOTH.darkened(0.04), 7, CLOTH, 0.04)
	mk.torus(Vector3(-0.29, 0.4, -0.29), 0.055, 0.014, Art.CORAL, 7, 3)

static func _dock_apply(st: StationNode, s: Dictionary) -> void:
	var en := bool(s.get("enabled", true))
	var occ := bool(s.get("occupied", false))
	var c1 := st.changed("enabled", en)
	var c2 := st.changed("occupied", occ)
	if c1 or c2:
		st.show_part("silhouette", en and not occ)
		st.show_part("sign", en)
		st.show_part("cover", not en)

# ================================================================ group bell

static func _group_bell(st: StationNode) -> void:
	_mesh(st, "body", _c("st_bell", _bell_stand))
	var bell := _pivot(st, "bell", Vector3(0, 0.915, 0))
	_mesh(st, "bell_mesh", _c("st_bell_bell", _bell_bell), bell)
	_mesh(st, "glow", _c("st_bell_glow", _bell_glow), null, Vector3.ZERO, ModelItems.lit_mat())
	st.apply_fn = _bell_apply
	st.tick_fn = _bell_tick
	st.apply({"ringing": false, "finish_ready": false})

static func _bell_stand(mk: MeshKit) -> void:
	mk.cyl(Vector3.ZERO, 0.25, 0.05, Art.WALNUT.darkened(0.1), 12, Art.WALNUT.lightened(0.12), 0.23)
	mk.torus(Vector3(0, 0.05, 0), 0.2, 0.015, Art.BRASS, 12, 3)
	for s in [-1.0, 1.0]:
		mk.cyl(Vector3(s * 0.19, 0.05, 0), 0.03, 0.88, Art.WALNUT, 6)
		mk.sphere(Vector3(s * 0.19, 0.06, 0), 0.05, Art.WALNUT.darkened(0.1), 2, 6, Vector3(1, 0.6, 1))
	mk.rbox(Vector3(0, 0.95, 0), Vector3(0.5, 0.06, 0.09), Art.WALNUT.lightened(0.05), 0.03, Art.WALNUT.lightened(0.18))
	for s2 in [-1.0, 1.0]:
		mk.push_at(Vector3(s2 * 0.045, 0.985, 0), Vector3(0, 0, -s2 * 25.0))
		mk.sphere(Vector3.ZERO, 0.04, Art.CORAL, 2, 6, Vector3(1.1, 0.6, 0.6))
		mk.pop()

static func _bell_bell(mk: MeshKit) -> void:
	mk.box(Vector3(0, -0.015, 0), Vector3(0.05, 0.05, 0.05), Art.BRASS.darkened(0.25))
	mk.sphere(Vector3(0, -0.1, 0), 0.1, Art.BRASS.lightened(0.12), 3, 10, Vector3(1, 0.8, 1))
	mk.cyl(Vector3(0, -0.3, 0), 0.16, 0.2, Art.BRASS, 12, null, 0.1)
	mk.torus(Vector3(0, -0.3, 0), 0.16, 0.025, Art.GOLD.lightened(0.05), 12, 4)
	mk.torus(Vector3(0, -0.2, 0), 0.135, 0.012, Art.BRASS.darkened(0.15), 12, 3)
	mk.sphere(Vector3(0, -0.33, 0), 0.035, Art.BRASS.darkened(0.3), 2, 6)

static func _bell_glow(mk: MeshKit) -> void:
	mk.jitter = 0.0
	_ring(mk, 0.014, 0.37, 0.29, Art.GOLD.lightened(0.3), 20)
	for i in 8:
		var a := TAU * i / 8.0
		ModelItems.poly_flat(mk, Vector3(cos(a) * 0.43, 0.012, sin(a) * 0.43), ModelItems.star_pts(4, 0.05, 0.018), 0.006, Art.GOLD.lightened(0.4), Art.GOLD.lightened(0.4), rad_to_deg(a))

static func _bell_apply(st: StationNode, s: Dictionary) -> void:
	var ring := bool(s.get("ringing", false))
	if st.changed("ringing", ring):
		st.anim["ringing"] = ring
		if ring:
			st.anim["sway"] = 1.0
			st.anim["ring_t"] = st.t
	var fin := bool(s.get("finish_ready", false))
	if st.changed("finish_ready", fin):
		st.show_part("glow", fin)

static func _bell_tick(st: StationNode, dt: float) -> void:
	var sway := float(st.anim.get("sway", 0.0))
	if st.anim.get("ringing", false):
		sway = maxf(sway, 0.6)
	else:
		sway = maxf(0.0, sway - dt * 0.9)
	st.anim["sway"] = sway
	var bell: Node3D = st.parts["bell"]
	bell.rotation.z = sin((st.t - float(st.anim.get("ring_t", 0.0))) * 12.0) * 0.42 * sway
	var glow: Node3D = st.parts["glow"]
	if glow.visible:
		glow.scale = Vector3.ONE * (1.0 + 0.06 * sin(st.t * 4.0))

# ================================================================ festival stand

const LANTERN_ANGLES := [215.0, 325.0, 180.0, 0.0, 250.0, 290.0]

static func _festival(st: StationNode) -> void:
	_mesh(st, "body", _c("st_fest_base", _fest_base))
	var on := _pivot(st, "on", Vector3.ZERO)
	_mesh(st, "frame", _c("st_fest_frame", _fest_frame), on)
	_mesh(st, "lanterns", _c("st_fest_lanterns_0", _fest_lanterns.bind(0)), on)
	_mesh(st, "trunks", _c("st_fest_trunks_0", _fest_trunks.bind(0)), on)
	_mesh(st, "off", _c("st_fest_drape", _fest_drape))
	st.apply_fn = _fest_apply
	st.tick_fn = _fest_tick
	st.apply({"enabled": true, "parcels": 0, "trunks": 0})

static func _fest_base(mk: MeshKit) -> void:
	mk.rbox(Vector3(0, 0.09, 0), Vector3(0.74, 0.18, 0.74), Art.WALNUT, 0.08, Art.WALNUT.lightened(0.15))
	for sz in [-1.0, 1.0]:
		mk.box(Vector3(0, 0.15, sz * 0.372), Vector3(0.6, 0.03, 0.012), Art.GOLD)
	for sx in [-1.0, 1.0]:
		mk.box(Vector3(sx * 0.372, 0.15, 0), Vector3(0.012, 0.03, 0.6), Art.GOLD)

static func _fest_frame(mk: MeshKit) -> void:
	mk.box(Vector3(0, 0.186, 0.02), Vector3(0.62, 0.012, 0.6), Art.PLUM, Art.PLUM.lightened(0.12))
	var z := -0.26
	var cy := 0.98
	for s in [-1.0, 1.0]:
		mk.cyl(Vector3(s * 0.34, 0.18, z), 0.035, 1.14, Art.WALNUT.lightened(0.05), 6)
		for k in 5:
			mk.torus(Vector3(s * 0.34, 0.36 + k * 0.2, z), 0.04, 0.013, Art.CORAL if k % 2 == 0 else Art.GOLD, 6, 3)
		mk.sphere(Vector3(s * 0.34, 1.34, z), 0.05, Art.GOLD, 2, 6)
	mk.push_at(Vector3(0, cy, z), Vector3(90, 0, 0))
	mk.torus(Vector3.ZERO, 0.33, 0.028, Art.BRASS, 18, 4)
	mk.pop()
	# Paper moon with a sleepy smile.
	mk.push_at(Vector3(0.04, cy, z))
	ModelItems.crescent_xy(mk, 0.27, 0.17, 0.05, MOON_PAPER.darkened(0.08), MOON_PAPER, 112.0, 12)
	mk.box(Vector3(0.17, 0.05, 0.03), Vector3(0.055, 0.014, 0.01), Art.INK.lightened(0.1))
	mk.push_at(Vector3(0.19, -0.03, 0.028))
	ModelItems.poly_xy(mk, ModelItems.circle_pts(0.026, 8, 1.2, 0.8), 0.008, Art.ROSE)
	mk.pop()
	mk.pop()
	mk.push_at(Vector3(0, 1.37, z))
	ModelItems.poly_xy(mk, ModelItems.star_pts(5, 0.075, 0.035), 0.03, Art.GOLD.darkened(0.1), Art.GOLD.lightened(0.15))
	mk.pop()
	# Little bunting on the moon ring.
	var cols := [Art.CORAL, Art.SKY, Art.GOLD, Art.SAGE, Art.ROSE]
	for i in 5:
		var a := deg_to_rad(60.0 + i * 15.0)
		mk.push_at(Vector3(cos(a) * 0.33, cy + sin(a) * 0.33 - 0.04, z + 0.03), Vector3(0, 0, rad_to_deg(a) - 90.0))
		ModelItems.poly_xy(mk, [Vector2(-0.035, 0.02), Vector2(0.035, 0.02), Vector2(0, -0.05)], 0.008, cols[i])
		mk.pop()

static func _lantern(mk: MeshKit, pos: Vector3, col: Color, r := 0.065) -> void:
	mk.sphere(pos, r, col, 4, 8, Vector3(1, 1.2, 1), col.darkened(0.1))
	mk.cyl(pos + Vector3(0, r * 1.05, 0), r * 0.45, r * 0.3, Art.GOLD.darkened(0.1), 6)
	mk.cyl(pos - Vector3(0, r * 1.35, 0), r * 0.45, r * 0.3, Art.GOLD.darkened(0.1), 6)
	for k in 2:
		mk.torus(pos + Vector3(0, -r * 0.35 + k * r * 0.7, 0), r * 0.93, r * 0.12, col.lightened(0.25), 8, 3)

static func _fest_lanterns(mk: MeshKit, n: int) -> void:
	var cols := [Art.CORAL, Art.SKY, Art.GOLD, Art.PLUM.lightened(0.1), Art.SAGE, Art.ROSE]
	for i in mini(n, LANTERN_ANGLES.size()):
		var a := deg_to_rad(LANTERN_ANGLES[i])
		var hang := Vector3(cos(a) * 0.33, 0.98 + sin(a) * 0.33, -0.2)
		var pos := hang + Vector3(0, -0.12, 0.02)
		ModelItems.rod(mk, hang, pos + Vector3(0, 0.07, 0), 0.008, Art.INK.lightened(0.2), 4)
		_lantern(mk, pos, cols[i % cols.size()])

static func _fest_trunks(mk: MeshKit, n: int) -> void:
	for i in mini(n, 3):
		mk.push_at(Vector3(0.0, 0.192 + i * 0.1, 0.17 - i * 0.02), Vector3(0, (i - 1) * 6.0, 0), Vector3(0.22, 0.2, 0.22))
		ModelItems.trunk(mk, false)
		mk.pop()

static func _fest_drape(mk: MeshKit) -> void:
	mk.rbox(Vector3(0, 0.1, 0), Vector3(0.8, 0.2, 0.8), CLOTH.darkened(0.06), 0.1, CLOTH)
	for i in 12:
		var a := TAU * (i + 0.5) / 12.0
		mk.sphere(Vector3(cos(a) * 0.4, 0.04, sin(a) * 0.4), 0.06, CLOTH.darkened(0.08), 2, 5, Vector3(1, 0.7, 1))
	mk.sphere(Vector3(-0.08, 0.24, -0.05), 0.2, CLOTH, 3, 7, Vector3(1.3, 0.45, 1.0))
	mk.torus(Vector3(0, 0.15, 0), 0.4, 0.016, Art.GOLD.darkened(0.1), 12, 3)

static func _fest_apply(st: StationNode, s: Dictionary) -> void:
	var en := bool(s.get("enabled", true))
	if st.changed("enabled", en):
		st.show_part("on", en)
		st.show_part("off", not en)
	var p := clampi(int(s.get("parcels", 0)), 0, 6)
	if st.changed("parcels", p):
		st.set_part_mesh("lanterns", _c("st_fest_lanterns_%d" % p, _fest_lanterns.bind(p)))
	var t := clampi(int(s.get("trunks", 0)), 0, 3)
	if st.changed("trunks", t):
		st.set_part_mesh("trunks", _c("st_fest_trunks_%d" % t, _fest_trunks.bind(t)))

static func _fest_tick(st: StationNode, dt: float) -> void:
	var l: Node3D = st.parts["lanterns"]
	l.rotation.z = sin(st.t * 1.3) * 0.015

# ================================================================ goal pad

static func _goal_pad(st: StationNode) -> void:
	var r := float(st.opts.get("radius", 1.0))
	_mesh(st, "body", _c("st_goal_%.2f" % r, _goal_mesh.bind(r)))
	var arrows := _pivot(st, "arrows", Vector3.ZERO)
	_mesh(st, "arrows_mesh", _c("st_goal_arrows_%.2f" % r, _goal_arrows.bind(r)), arrows)
	_mesh(st, "glow", _c("st_goal_glow_%.2f" % r, _goal_glow.bind(r)), null, Vector3.ZERO, ModelItems.lit_mat())
	_no_shadow(st)
	st.apply_fn = _goal_apply
	st.tick_fn = _goal_tick
	st.apply({"enabled": true, "active": false})

static func _no_shadow(st: StationNode) -> void:
	for p in st.parts.values():
		if p is GeometryInstance3D:
			(p as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

static func _goal_mesh(mk: MeshKit, r: float) -> void:
	mk.jitter = 0.0
	_ring(mk, 0.018, r, r - 0.11, Art.GOLD.darkened(0.08), 32)
	_ring(mk, 0.02, r - 0.16, r - 0.2, Art.CREAM, 32)
	ModelItems.poly_flat(mk, Vector3(0, 0.016, 0), ModelItems.star_pts(5, 0.2, 0.09), 0.006, Art.GOLD, Art.GOLD.lightened(0.1))

static func _goal_arrows(mk: MeshKit, r: float) -> void:
	mk.jitter = 0.0
	var ap := ModelItems.arrow_pts(0.3, 0.08, 0.2, 0.12)
	for k in 4:
		var a := deg_to_rad(45.0 + 90.0 * k)
		var p := Vector3(cos(a), 0, sin(a)) * (r * 0.58)
		ModelItems.poly_flat(mk, p + Vector3(0, 0.018, 0), ap, 0.006, Art.GOLD.darkened(0.12), Art.GOLD.darkened(0.04), 180.0 - rad_to_deg(a), Vector2(0.04, 0))

static func _goal_glow(mk: MeshKit, r: float) -> void:
	mk.jitter = 0.0
	_ring(mk, 0.024, r + 0.02, r - 0.08, Art.GOLD.lightened(0.35), 32)

static func _goal_apply(st: StationNode, s: Dictionary) -> void:
	var en := bool(s.get("enabled", true))
	var act := bool(s.get("active", false)) and en
	var c1 := st.changed("enabled", en)
	var c2 := st.changed("active", act)
	if c1 or c2:
		st.show_part("body", en)
		st.show_part("arrows", en)
		st.show_part("glow", act)
		st.anim["active"] = act

static func _goal_tick(st: StationNode, dt: float) -> void:
	if st.anim.get("active", false):
		var a: Node3D = st.parts["arrows"]
		var k := 0.92 + 0.08 * sin(st.t * 5.0)
		a.scale = Vector3(k, 1, k)

# ================================================================ lift pad

static func _lift_pad(st: StationNode) -> void:
	var idx := clampi(int(st.opts.get("index", 0)), 0, 1)
	var rc := _col(st.opts.get("pair_color"), Art.PLUM)
	_mesh(st, "body", _c("st_lift_%d" % idx, _lift_mesh.bind(idx)))
	_mesh(st, "ring", _c("st_lift_ring_" + rc.to_html(), _lift_ring.bind(rc)))
	var arrows := _pivot(st, "arrows", Vector3.ZERO)
	_mesh(st, "arrows_mesh", _c("st_lift_arrows_" + rc.to_html(), _lift_arrows.bind(rc)), arrows, Vector3.ZERO, ModelItems.lit_mat())
	_trip_switch(st, Vector3(0.0, 0.0, -0.4))
	_mesh(st, "cover", _c("st_lift_cover", _lift_cover))
	# The car: a dumbwaiter cage that sinks at the sending pad and rises at the
	# other (the view drives car / car_y from the lift state, DESIGN_V2 §7).
	var car := _pivot(st, "car", Vector3.ZERO)
	_mesh(st, "car_mesh", _c("st_lift_car", _lift_car), car)
	st.apply_fn = _lift_apply
	st.tick_fn = _lift_tick
	st.apply({"enabled": true, "busy": false, "tripped": false, "car": false, "car_y": 0.0})

static func _lift_car(mk: MeshKit) -> void:
	mk.rbox(Vector3(0, 0.035, 0), Vector3(0.62, 0.03, 0.62), Art.WALNUT.lightened(0.1), 0.04, Art.WALNUT.lightened(0.25))
	for sx in [-0.28, 0.28]:
		for sz in [-0.28, 0.28]:
			mk.cyl(Vector3(sx, 0.05, sz), 0.018, 0.96, Art.BRASS, 5)
	for sz2 in [-0.28, 0.28]:
		mk.box(Vector3(0, 1.02, sz2), Vector3(0.6, 0.03, 0.03), Art.BRASS)
	for sx2 in [-0.28, 0.28]:
		mk.box(Vector3(sx2, 1.02, 0), Vector3(0.03, 0.03, 0.6), Art.BRASS)
	mk.box(Vector3(0, 1.08, 0), Vector3(0.34, 0.08, 0.34), Art.CORAL, Art.CORAL.lightened(0.15))
	mk.sphere(Vector3(0, 1.16, 0), 0.05, Art.GOLD, 2, 6)

static func _lift_mesh(mk: MeshKit, idx: int) -> void:
	mk.cyl(Vector3.ZERO, 0.44, 0.04, Art.STONE.lightened(0.1), 16, Art.CREAM.darkened(0.1), 0.42)
	mk.torus(Vector3(0, 0.04, 0), 0.425, 0.022, Art.BRASS, 16, 3)
	# Suitcase symbol.
	var y := 0.042
	var case_c := Art.WALNUT.lightened(0.1)
	mk.rbox(Vector3(0, y + 0.006, 0.02), Vector3(0.32, 0.012, 0.22), case_c.darkened(0.1), 0.05, case_c)
	for sx in [-0.09, 0.09]:
		mk.box(Vector3(sx, y + 0.014, 0.02), Vector3(0.03, 0.006, 0.222), Art.GOLD)
	mk.box(Vector3(0, y + 0.012, -0.11), Vector3(0.12, 0.012, 0.025), case_c.darkened(0.1))
	for sx2 in [-0.06, 0.06]:
		mk.box(Vector3(sx2, y + 0.012, -0.1), Vector3(0.025, 0.012, 0.04), case_c.darkened(0.1))
	for i in idx + 1:
		mk.sphere(Vector3((i - idx * 0.5) * 0.08, 0.05, 0.36), 0.026, Art.CREAM, 2, 6, Vector3(1, 0.5, 1))

static func _lift_ring(mk: MeshKit, rc: Color) -> void:
	mk.jitter = 0.0
	_ring(mk, 0.043, 0.38, 0.29, rc, 20)

static func _lift_arrows(mk: MeshKit, rc: Color) -> void:
	mk.jitter = 0.0
	for k in 3:
		var a := TAU * k / 3.0
		ModelItems.poly_flat(mk, Vector3(cos(a) * 0.335, 0.047, sin(a) * 0.335), [Vector2(0.05, 0), Vector2(-0.03, 0.04), Vector2(-0.03, -0.04)], 0.006, rc.lightened(0.45), rc.lightened(0.45), -rad_to_deg(a) - 90.0)

static func _lift_cover(mk: MeshKit) -> void:
	mk.cyl(Vector3.ZERO, 0.45, 0.06, Art.STONE.darkened(0.05), 16, Art.STONE.lightened(0.15))
	for s in [-1.0, 1.0]:
		mk.push_at(Vector3(0, 0.062, 0), Vector3(0, s * 45.0, 0))
		mk.box(Vector3.ZERO, Vector3(0.8, 0.006, 0.07), Art.CREAM.darkened(0.05))
		mk.pop()

static func _lift_apply(st: StationNode, s: Dictionary) -> void:
	var en := bool(s.get("enabled", true))
	var busy := bool(s.get("busy", false)) and en
	var trip := bool(s.get("tripped", false)) and en
	var c1 := st.changed("enabled", en)
	var c2 := st.changed("busy", busy)
	var c3 := st.changed("trip_state", trip)
	if c1 or c2 or c3:
		st.show_part("body", en)
		st.show_part("ring", en)
		st.show_part("trip", en)
		st.show_part("cover", not en)
		st.show_part("arrows", busy and not trip)
		st.set_part_material("ring", ModelItems.dim_mat() if trip else (ModelItems.lit_mat() if busy else Art.toon()))
		st.anim["busy"] = busy and not trip
	var car_on := bool(s.get("car", false)) and en
	st.show_part("car", car_on)
	if car_on:
		(st.parts["car"] as Node3D).position.y = float(s.get("car_y", 0.0))
	_trip_set(st, trip, false)

static func _lift_tick(st: StationNode, dt: float) -> void:
	if st.anim.get("busy", false):
		var a: Node3D = st.parts["arrows"]
		a.rotation.y -= dt * 2.4

# ================================================================ bed

static func _bed(st: StationNode) -> void:
	var rc := _room(st)
	var k := rc.to_html()
	_mesh(st, "body", _c("st_bed_frame_" + k, _bed_frame.bind(rc)))
	_mesh(st, "made", _c("st_bed_made_" + k, _bed_made.bind(rc)))
	_mesh(st, "dirty", _c("st_bed_dirty_" + k, _bed_dirty.bind(rc)))
	_mesh(st, "stripped", _c("st_bed_stripped", _bed_stripped))
	_mesh(st, "dnd", _c("st_bed_dnd", _bed_dnd))
	st.apply_fn = _bed_apply
	st.apply({"bed": "Made", "occupied": false})

static func _bed_frame(mk: MeshKit, rc: Color) -> void:
	var wood := Art.WALNUT
	for sx in [-0.72, 0.72]:
		for sz in [-0.34, 0.34]:
			mk.box(Vector3(sx, 0.05, sz), Vector3(0.08, 0.1, 0.08), wood.darkened(0.2))
	mk.rbox(Vector3(0, 0.165, 0), Vector3(1.56, 0.15, 0.8), wood, 0.05, wood.lightened(0.1))
	mk.rbox(Vector3(0.02, 0.315, 0), Vector3(1.44, 0.15, 0.74), Art.CREAM.darkened(0.08), 0.08, Art.CREAM)
	for sz2 in [-0.2, 0.0, 0.2]:
		mk.box(Vector3(0.02, 0.392, sz2), Vector3(1.36, 0.004, 0.07), Art.SKY.lightened(0.22))
	# Rounded headboard on -x with room-colour finials.
	mk.rbox(Vector3(-0.76, 0.32, 0), Vector3(0.08, 0.64, 0.84), wood, 0.03, wood.lightened(0.12))
	mk.push_at(Vector3(-0.76, 0.6, 0), Vector3(0, 0, 90), Vector3(1, 0.5, 1))
	mk.cyl(Vector3(0, -0.04, 0), 0.42, 0.08, wood, 14, wood.lightened(0.12))
	mk.pop()
	mk.push_at(Vector3(-0.715, 0.6, 0), Vector3(0, 90, 0))
	ModelItems.poly_xy(mk, ModelItems.circle_pts(0.1, 10, 1.2, 0.8), 0.012, rc.darkened(0.05), rc)
	mk.pop()
	for sz3 in [-0.42, 0.42]:
		mk.sphere(Vector3(-0.76, 0.66, sz3), 0.055, rc, 2, 7)
		mk.sphere(Vector3(0.77, 0.52, sz3), 0.048, rc, 2, 7)
	# Footboard on +x.
	mk.rbox(Vector3(0.77, 0.25, 0), Vector3(0.07, 0.5, 0.84), wood, 0.03, wood.lightened(0.12))
	mk.box(Vector3(0.77, 0.4, 0), Vector3(0.075, 0.04, 0.7), Art.BRASS)

static func _bed_made(mk: MeshKit, rc: Color) -> void:
	var x0 := -0.36
	var x1 := 0.73
	var cx := (x0 + x1) * 0.5
	var L := x1 - x0
	mk.rbox(Vector3(cx, 0.415, 0), Vector3(L, 0.07, 0.8), rc.darkened(0.06), 0.03, rc)
	for sz in [-1.0, 1.0]:
		mk.box(Vector3(cx, 0.32, sz * 0.405), Vector3(L, 0.18, 0.025), rc.darkened(0.12))
	for px in [0.42, 0.56]:
		mk.box(Vector3(px, 0.416, 0), Vector3(0.06, 0.072, 0.81), rc.lightened(0.38), rc.lightened(0.38))
		mk.box(Vector3(px, 0.32, 0.41), Vector3(0.06, 0.18, 0.03), rc.lightened(0.3))
	mk.rbox(Vector3(x0 + 0.06, 0.422, 0), Vector3(0.15, 0.08, 0.82), Art.WHITE.darkened(0.05), 0.03, Art.WHITE)
	mk.sphere(Vector3(-0.56, 0.44, 0), 0.15, Art.WHITE, 3, 8, Vector3(0.85, 0.42, 1.6), Art.CREAM.darkened(0.06))

static func _bed_dirty(mk: MeshKit, rc: Color) -> void:
	var c := rc.darkened(0.04)
	mk.sphere(Vector3(0.32, 0.41, 0.04), 0.24, c, 3, 9, Vector3(1.5, 0.3, 1.3), c.darkened(0.1))
	mk.sphere(Vector3(0.02, 0.43, -0.13), 0.17, rc.darkened(0.12), 3, 8, Vector3(1.2, 0.38, 1.1))
	mk.sphere(Vector3(0.56, 0.42, 0.2), 0.15, rc.lightened(0.06), 3, 8, Vector3(1.1, 0.34, 1.2))
	mk.push_at(Vector3(0.36, 0.3, 0.41), Vector3(0, 0, -12))
	mk.box(Vector3.ZERO, Vector3(0.42, 0.2, 0.03), rc.darkened(0.12))
	mk.pop()
	mk.push_at(Vector3(-0.47, 0.45, 0.13), Vector3(10, 32, 8))
	mk.sphere(Vector3.ZERO, 0.15, Art.WHITE.darkened(0.04), 3, 8, Vector3(0.85, 0.42, 1.5), Art.CREAM.darkened(0.08))
	mk.pop()
	var crumbs := [Vector3(-0.24, 0.395, -0.2), Vector3(-0.16, 0.395, -0.25), Vector3(-0.2, 0.395, 0.24), Vector3(-0.3, 0.395, 0.27)]
	for p in crumbs:
		ModelItems.star_cracker(mk, p, 0.035, float(int(p.x * 100.0) % 40), 0.012)
	for f in [[Vector3(-0.08, 0.4, 0.26), 30.0], [Vector3(-0.34, 0.4, -0.12), -50.0], [Vector3(0.12, 0.48, -0.2), 75.0]]:
		var fp: Vector3 = f[0]
		var fr: float = f[1]
		mk.push_at(fp, Vector3(0, fr, 10))
		mk.sphere(Vector3.ZERO, 0.045, Art.WHITE, 2, 6, Vector3(2.0, 0.3, 0.7))
		mk.pop()

static func _bed_stripped(mk: MeshKit) -> void:
	for x in [-0.45, -0.1, 0.25, 0.6]:
		for sz in [-0.18, 0.18]:
			mk.sphere(Vector3(x, 0.392, sz), 0.022, Art.SKY.darkened(0.05), 2, 5, Vector3(1, 0.4, 1))
	mk.box(Vector3(0.68, 0.39, 0.33), Vector3(0.06, 0.006, 0.05), Art.CORAL)

static func _bed_dnd(mk: MeshKit) -> void:
	mk.push_at(Vector3(0.74, 0.47, 0.44), Vector3(-10, 0, 0))
	mk.push_at(Vector3(0, 0.07, 0), Vector3(90, 0, 0))
	mk.torus(Vector3.ZERO, 0.04, 0.01, Art.PLUM.darkened(0.1), 8, 3)
	mk.pop()
	mk.box(Vector3(0, -0.06, 0), Vector3(0.15, 0.2, 0.016), Art.PLUM, Art.PLUM.lightened(0.15))
	mk.push_at(Vector3(0.0, -0.06, 0.011), Vector3(0, 0, 200))
	ModelItems.crescent_xy(mk, 0.05, 0.028, 0.008, Art.GOLD)
	mk.pop()
	mk.pop()

static func _bed_apply(st: StationNode, s: Dictionary) -> void:
	var b := String(s.get("bed", "Made"))
	if st.changed("bed", b):
		st.show_part("made", b == "Made")
		st.show_part("dirty", b == "Dirty")
		st.show_part("stripped", b == "Stripped")
	var occ := bool(s.get("occupied", false))
	if st.changed("occupied", occ):
		st.show_part("dnd", occ)

# ================================================================ plinth

const PLINTH_TOP := 0.55

static func _plinth(st: StationNode) -> void:
	var rc := _room(st)
	_mesh(st, "body", _c("st_plinth_" + rc.to_html(), _plinth_mesh.bind(rc)))
	_pivot(st, "top", Vector3(0, PLINTH_TOP, 0))
	st.set_meta("top_y", PLINTH_TOP)

static func _plinth_mesh(mk: MeshKit, rc: Color) -> void:
	mk.cyl(Vector3.ZERO, 0.17, 0.05, Art.WALNUT.darkened(0.1), 10, Art.WALNUT.lightened(0.1), 0.15)
	mk.cyl(Vector3(0, 0.05, 0), 0.05, 0.43, Art.WALNUT.lightened(0.08), 8, null, 0.045)
	mk.torus(Vector3(0, 0.25, 0), 0.055, 0.016, Art.BRASS, 8, 3)
	mk.cyl(Vector3(0, 0.48, 0), 0.22, 0.06, Art.WALNUT, 12, Art.WALNUT.lightened(0.15), 0.23)
	mk.disc(Vector3(0, PLINTH_TOP - 0.008, 0), 0.2, rc, 12)
	mk.disc(Vector3(0, PLINTH_TOP - 0.004, 0), 0.14, Art.CREAM, 12)
	for i in 8:
		var a := TAU * (i + 0.5) / 8.0
		mk.sphere(Vector3(cos(a) * 0.205, 0.52, sin(a) * 0.205), 0.03, rc.darkened(0.05), 2, 5, Vector3(1, 0.8, 1))

# ================================================================ thermostat

static func _thermostat(st: StationNode) -> void:
	var south := String(st.opts.get("side", "north")) == "south"
	_mesh(st, "body", _c("st_thermo_post", _thermo_post))
	var head := _pivot(st, "head", Vector3(0, 0.84, 0), null, Vector3(-32.0 if south else 32.0, 0, 0))
	# Housing and face are one mesh per mode (four cached variants): one draw
	# call per thermostat instead of two, six per floor.
	_mesh(st, "face", _c("st_thermo_head_neutral", _thermo_head.bind("neutral")), head)
	var needle := _pivot(st, "needle", Vector3(0, 0.035, 0), head)
	_mesh(st, "needle_mesh", _c("st_thermo_needle", _thermo_needle), needle)
	var sw := _pivot(st, "switch", Vector3(0.17, 0.0, 0.0), head)
	_mesh(st, "switch_mesh", _c("st_thermo_switch", _thermo_switch), sw)
	_mesh(st, "cover", _c("st_thermo_cover", _thermo_cover))
	st.apply_fn = _thermo_apply
	st.apply({"enabled": true, "mode": "neutral", "tripped": false, "heat": 0})

static func _thermo_post(mk: MeshKit) -> void:
	mk.cyl(Vector3.ZERO, 0.13, 0.045, Art.WALNUT.darkened(0.1), 10, Art.WALNUT.lightened(0.1), 0.11)
	mk.cyl(Vector3(0, 0.045, 0), 0.032, 0.75, Art.BRASS, 6)
	mk.torus(Vector3(0, 0.07, 0), 0.045, 0.014, Art.BRASS.darkened(0.15), 8, 3)
	mk.sphere(Vector3(0, 0.79, 0), 0.05, Art.BRASS.darkened(0.1), 2, 6)

static func _thermo_housing(mk: MeshKit) -> void:
	mk.cyl(Vector3(0, -0.05, 0), 0.17, 0.07, Art.BRASS.darkened(0.08), 14, Art.BRASS)
	mk.torus(Vector3(0, 0.022, 0), 0.165, 0.02, Art.BRASS.lightened(0.12), 14, 4)
	for k in 2:
		for s in [-1.0, 1.0]:
			var a := deg_to_rad(90.0 + s * (55.0 + k * 30.0))
			mk.box(Vector3(cos(a) * 0.135, 0.03, -sin(a) * 0.135), Vector3(0.03, 0.01, 0.03), Art.SKY.darkened(0.1) if s > 0 else Art.CORAL.darkened(0.05))

static func _thermo_face(mk: MeshKit, mode: String) -> void:
	var bg := Art.CREAM
	match mode:
		"warm": bg = Art.CORAL
		"cool": bg = Art.SKY
		"tripped": bg = SLATE
	ModelItems.poly_flat(mk, Vector3(0, 0.018, 0), ModelItems.circle_pts(0.145, 14), 0.008, bg.darkened(0.1), bg)
	match mode:
		"warm":
			mk.push_at(Vector3(0, 0.03, 0.045), Vector3(-90, 0, 0))
			ModelItems.sun_xy(mk, 0.13, 0.008, Art.GOLD.lightened(0.15), Art.CREAM)
			mk.pop()
		"cool":
			mk.push_at(Vector3(0, 0.03, 0.045), Vector3(-90, 0, 0))
			ModelItems.snowflake_xy(mk, 0.13, 0.022, 0.008, Art.WHITE)
			mk.pop()
		"tripped":
			mk.push_at(Vector3(0, 0.03, 0.05), Vector3(-90, 0, 0))
			ModelItems.crescent_xy(mk, 0.045, 0.025, 0.008, Art.STONE)
			mk.pop()
		_:
			ModelItems.poly_flat(mk, Vector3(0, 0.026, 0.05), ModelItems.circle_pts(0.03, 8), 0.006, Art.SAGE, Art.SAGE)

## Housing plus the face for one mode, as a single mesh.
static func _thermo_head(mk: MeshKit, mode: String) -> void:
	_thermo_housing(mk)
	_thermo_face(mk, mode)

static func _thermo_needle(mk: MeshKit) -> void:
	mk.box(Vector3(0, 0, -0.055), Vector3(0.022, 0.01, 0.11), Art.INK)
	mk.sphere(Vector3.ZERO, 0.026, Art.BRASS.darkened(0.15), 2, 6, Vector3(1, 0.6, 1))

static func _thermo_switch(mk: MeshKit) -> void:
	mk.box(Vector3(0.0, -0.01, 0), Vector3(0.05, 0.05, 0.06), Art.CREAM.darkened(0.08))
	mk.cyl(Vector3(0.0, 0.0, 0), 0.016, 0.07, Art.CORAL.darkened(0.08), 6)
	mk.sphere(Vector3(0.0, 0.08, 0), 0.03, Art.CORAL, 2, 6)

static func _thermo_cover(mk: MeshKit) -> void:
	mk.sphere(Vector3(0, 0.86, 0), 0.19, CLOTH, 3, 8, Vector3(1, 0.85, 1), CLOTH.darkened(0.06))
	mk.cyl(Vector3(0, 0.62, 0), 0.08, 0.14, CLOTH.darkened(0.06), 7, null, 0.15)
	mk.torus(Vector3(0, 0.72, 0), 0.07, 0.016, Art.CORAL, 8, 3)

static func _thermo_apply(st: StationNode, s: Dictionary) -> void:
	var en := bool(s.get("enabled", true))
	if st.changed("enabled", en):
		st.show_part("head", en)
		st.show_part("cover", not en)
	var trip := bool(s.get("tripped", false))
	var mode := String(s.get("mode", "neutral"))
	var face := "tripped" if trip else mode
	if face != "warm" and face != "cool" and face != "tripped":
		face = "neutral"
	if st.changed("face", face):
		st.set_part_mesh("face", _c("st_thermo_head_" + face, _thermo_head.bind(face)))
		var sw: Node3D = st.parts["switch"]
		sw.rotation.z = -1.7 if trip else 0.0
		st.show_part("needle", not trip)
	var h := clampi(int(s.get("heat", 0)), -100, 100)
	if st.changed("heat", h):
		var nd: Node3D = st.parts["needle"]
		nd.rotation.y = -float(h) / 100.0 * deg_to_rad(120.0)

# ================================================================ water tray

static func _water_tray(st: StationNode) -> void:
	_mesh(st, "body", _c("st_tray", _tray_mesh))
	var plants := _pivot(st, "plants", Vector3.ZERO)
	_mesh(st, "plants_mesh", _c("st_tray_plants", _tray_plants), plants)
	_mesh(st, "water", _c("st_tray_water", _tray_water))
	_mesh(st, "cover", _c("st_tray_cover", _tray_cover))
	st.apply_fn = _tray_apply
	st.apply({"enabled": true, "wet": 0, "humidity": 20})

static func _tray_mesh(mk: MeshKit) -> void:
	mk.box(Vector3(0, 0.02, 0), Vector3(0.6, 0.04, 0.34), Art.WALNUT.darkened(0.15))
	ModelItems.open_box(mk, Vector3(0, 0.0, 0), Vector3(0.66, 0.18, 0.4), TERRA, TERRA.darkened(0.25), 0.04, 0.03, TERRA.lightened(0.15))
	mk.box(Vector3(0, 0.09, 0), Vector3(0.58, 0.07, 0.32), ModelItems.SOIL, SOIL_TOP)
	for k in 3:
		mk.push_at(Vector3(-0.2 + k * 0.2, 0.08, 0.203))
		ModelItems.poly_xy(mk, ModelItems.teardrop_pts(0.024, 6, 2.0), 0.008, Art.WATER.lightened(0.2))
		mk.pop()

static func _tray_plants(mk: MeshKit) -> void:
	for k in 3:
		var x := -0.19 + k * 0.19
		var h := 0.1 if k != 1 else 0.14
		mk.cyl(Vector3(x, 0.12, 0), 0.014, h, Art.LEAF.darkened(0.05), 5)
		for s in [-1.0, 1.0]:
			mk.push_at(Vector3(x + s * 0.01, 0.12 + h * 0.75, 0), Vector3(0, k * 40.0, -s * 55.0))
			mk.sphere(Vector3(0, 0.045, 0), 0.05, Art.LEAF.lightened(0.06 * k), 2, 6, Vector3(0.6, 1.0, 0.35))
			mk.pop()
		if k == 1:
			for i in 5:
				var a := TAU * i / 5.0
				mk.sphere(Vector3(x + cos(a) * 0.028, 0.12 + h + 0.01, sin(a) * 0.028), 0.026, Art.ROSE, 2, 5, Vector3(1, 0.6, 1))
			mk.sphere(Vector3(x, 0.12 + h + 0.02, 0), 0.02, Art.GOLD, 2, 5)

static func _tray_water(mk: MeshKit) -> void:
	mk.box(Vector3(0, 0.0, 0), Vector3(0.58, 0.012, 0.32), Art.WATER, Art.WATER.lightened(0.18))
	for p in [Vector3(-0.15, 0.007, 0.06), Vector3(0.12, 0.007, -0.08), Vector3(0.22, 0.007, 0.09)]:
		mk.box(p, Vector3(0.07, 0.004, 0.02), Art.WHITE)

static func _tray_cover(mk: MeshKit) -> void:
	mk.rbox(Vector3(0, 0.19, 0), Vector3(0.7, 0.05, 0.44), CLOTH.darkened(0.04), 0.06, CLOTH)
	for sz in [-1.0, 1.0]:
		mk.box(Vector3(0, 0.11, sz * 0.215), Vector3(0.66, 0.14, 0.02), CLOTH.darkened(0.08))
	mk.sphere(Vector3(0.05, 0.23, 0.0), 0.16, CLOTH, 2, 7, Vector3(1.6, 0.3, 0.9))
	mk.torus(Vector3(-0.2, 0.2, 0), 0.04, 0.012, Art.CORAL, 6, 3)

static func _tray_apply(st: StationNode, s: Dictionary) -> void:
	var en := bool(s.get("enabled", true))
	if st.changed("enabled", en):
		st.show_part("cover", not en)
		st.show_part("plants", en)
	var wet := clampi(int(s.get("wet", 0)), 0, 60)
	var lvl := snappedf(float(wet) / 60.0, 0.05)
	var c1 := st.changed("wet", lvl)
	var c2 := st.changed("en_w", en)
	if c1 or c2:
		var w: Node3D = st.parts["water"]
		w.visible = en and wet > 0
		w.position.y = 0.128 + 0.035 * lvl
	var hum := clampi(int(s.get("humidity", 20)), 0, 100)
	var hk := snappedf(float(hum) / 100.0, 0.1)
	if st.changed("humidity", hk):
		var p: Node3D = st.parts["plants"]
		var sc := 0.85 + 0.3 * clampf(hk, 0.0, 0.8)
		p.scale = Vector3(1.0, sc, 1.0)

# ================================================================ drop pad

static func _drop_pad(st: StationNode) -> void:
	var rc := _room(st)
	var mi := _mesh(st, "body", _c("st_drop_" + rc.to_html(), _drop_mesh.bind(rc)))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

static func _drop_mesh(mk: MeshKit, rc: Color) -> void:
	mk.jitter = 0.0
	var y := 0.016
	mk.flat(Vector3(0, y, 0), Vector2(0.6, 0.6), rc.lerp(Art.CREAM, 0.55))
	for s in [-1.0, 1.0]:
		mk.flat(Vector3(0, y + 0.002, s * 0.27), Vector2(0.62, 0.07), rc)
		mk.flat(Vector3(s * 0.27, y + 0.002, 0), Vector2(0.07, 0.62), rc)
	_chevron(mk, Vector3(0, y + 0.003, 0.08), 90.0, 0.2, rc.darkened(0.15))
	_chevron(mk, Vector3(0, y + 0.003, -0.04), 90.0, 0.2, rc.darkened(0.15))

# ================================================================ curtain rail

static func _curtain_rail(st: StationNode) -> void:
	var ry := float(st.opts.get("rail_y", 0.92))
	_mesh(st, "rail", _c("st_rail_%.2f" % ry, _rail_mesh.bind(ry)))
	for s in [-1.0, 1.0]:
		var part := "curtain_l" if s < 0 else "curtain_r"
		var cp := _pivot(st, part, Vector3(s * 0.36, ry - 0.02, 0))
		_mesh(st, part + "_mesh", _c("st_curtain_%.2f_%d" % [ry, int(s)], _curtain_panel.bind(ry - 0.04, s)), cp)
	st.apply_fn = _rail_apply
	st.tick_fn = _rail_tick
	st.apply({"enabled": true, "installed": false})

static func _rail_mesh(mk: MeshKit, ry: float) -> void:
	var prev := Vector3(-0.47, ry - 0.03, 0)
	for i in range(1, 9):
		var x := -0.47 + 0.94 * i / 8.0
		var p := Vector3(x, ry - 0.03 + 0.07 * sin(PI * i / 8.0), 0)
		ModelItems.rod(mk, prev, p, 0.022, Art.BRASS, 6)
		prev = p
	for s in [-1.0, 1.0]:
		mk.sphere(Vector3(s * 0.48, ry - 0.03, 0), 0.04, Art.GOLD, 2, 6)
		mk.box(Vector3(s * 0.47, ry - 0.07, 0), Vector3(0.04, 0.06, 0.06), Art.BRASS.darkened(0.15))
	mk.sphere(Vector3(0, ry + 0.06, 0), 0.035, Art.GOLD, 2, 6)

## Tied-back acoustic curtain hanging from the rail (pivot at the rail).
static func _curtain_panel(mk: MeshKit, h: float, side: float) -> void:
	var cream := Color("#FCF2DF")
	var tie := -h * 0.52
	mk.push_at(Vector3.ZERO, Vector3.ZERO, Vector3(1, 1, 0.6))
	mk.cyl(Vector3(0, tie, 0), 0.06, -tie, cream.darkened(0.03), 8, cream, 0.12)
	mk.cyl(Vector3(0, -h + 0.05, 0), 0.115, h + tie - 0.05, cream.darkened(0.06), 8, cream, 0.06)
	mk.cyl(Vector3(0, -h, 0), 0.12, 0.05, Art.PLUM, 8, Art.PLUM.lightened(0.15), 0.117)
	mk.torus(Vector3(0, tie, 0), 0.068, 0.02, Art.PLUM.lightened(0.05), 8, 3)
	mk.pop()
	mk.sphere(Vector3(-side * 0.05, tie, 0.05), 0.028, Art.GOLD, 2, 5)
	for k in 3:
		mk.torus(Vector3((-0.08 + k * 0.08), 0.0, 0), 0.026, 0.009, Art.BRASS.darkened(0.1), 6, 3)

static func _rail_apply(st: StationNode, s: Dictionary) -> void:
	var en := bool(s.get("enabled", true))
	var inst := bool(s.get("installed", false)) and en
	var c1 := st.changed("enabled", en)
	var c2 := st.changed("installed", inst)
	if c1 or c2:
		st.show_part("rail", en)
		st.show_part("curtain_l", inst)
		st.show_part("curtain_r", inst)

static func _rail_tick(st: StationNode, dt: float) -> void:
	if not st.last("installed", false):
		return
	var l: Node3D = st.parts["curtain_l"]
	var r: Node3D = st.parts["curtain_r"]
	l.rotation.x = sin(st.t * 1.7) * 0.035
	r.rotation.x = sin(st.t * 1.7 + 1.3) * 0.035

# ================================================================ vent gate

static func _vent_gate(st: StationNode) -> void:
	var f := -1.0 if float(st.opts.get("facing", 1.0)) < 0.0 else 1.0
	var pipe_y := float(st.opts.get("pipe_y", 1.07 if f > 0 else 0.74))
	var mount := _pivot(st, "mount", Vector3.ZERO, null, Vector3(0, 0 if f > 0 else 180, 0))
	_mesh(st, "body", _c("st_vent_%.2f" % pipe_y, _vent_mesh.bind(pipe_y)), mount)
	var flap := _pivot(st, "flap", Vector3(0, 0.49, -0.326), mount)
	_mesh(st, "flap_mesh", _c("st_vent_flap", _vent_flap), flap)
	var ind := _pivot(st, "indicator", Vector3(-0.1 * f, pipe_y + 0.06, -0.45 * f))
	_mesh(st, "lamp", _c("st_vent_lamp_open", _vent_lamp.bind("open")), ind, Vector3.ZERO, ModelItems.lit_mat())
	st.apply_fn = _vent_apply
	st.tick_fn = _vent_tick
	st.apply({"open": true, "flow": 0.0})

static func _vent_mesh(mk: MeshKit, pipe_y: float) -> void:
	var z0 := -0.5
	mk.rbox(Vector3(0, 0.38, z0 + 0.085), Vector3(0.4, 0.32, 0.17), Art.BRASS.darkened(0.04), 0.05, Art.BRASS.lightened(0.12))
	mk.box(Vector3(0, 0.37, z0 + 0.172), Vector3(0.3, 0.2, 0.01), SLATE.lightened(0.1))
	for k in 3:
		mk.box(Vector3(0, 0.31 + k * 0.06, z0 + 0.178), Vector3(0.3, 0.018, 0.012), Art.BRASS.darkened(0.15))
	for s in [-1.0, 1.0]:
		ModelItems.rod(mk, Vector3(s * 0.2, 0.37, z0 + 0.08), Vector3(s * 0.27, 0.37, z0 + 0.08), 0.045, Art.BRASS.darkened(0.1), 6)
		mk.box(Vector3(s * 0.275, 0.37, z0 + 0.08), Vector3(0.025, 0.12, 0.12), Art.BRASS.darkened(0.2))
	# Riser to the wall-top pipe.
	ModelItems.rod(mk, Vector3(-0.1, 0.54, z0 + 0.05), Vector3(-0.1, pipe_y, z0 + 0.05), 0.035, Art.BRASS, 6)
	ModelItems.rod(mk, Vector3(-0.1, pipe_y, z0 + 0.05), Vector3(-0.1, pipe_y, z0 - 0.5), 0.035, Art.BRASS, 6)
	mk.sphere(Vector3(-0.1, pipe_y, z0 + 0.05), 0.045, Art.BRASS.darkened(0.1), 2, 6)
	mk.cyl(Vector3(-0.1, pipe_y + 0.02, z0 + 0.05), 0.075, 0.035, Art.BRASS.darkened(0.2), 10, Art.BRASS.darkened(0.05))

static func _vent_flap(mk: MeshKit) -> void:
	mk.box(Vector3(0, -0.1, 0.012), Vector3(0.32, 0.2, 0.024), Art.CORAL.darkened(0.04), Art.CORAL.lightened(0.1))
	mk.box(Vector3(0, -0.1, 0.026), Vector3(0.2, 0.04, 0.008), Art.CREAM)
	ModelItems.rod(mk, Vector3(-0.165, 0, 0.0), Vector3(0.165, 0, 0.0), 0.018, Art.BRASS.darkened(0.15), 6)

static func _vent_lamp(mk: MeshKit, kind: String) -> void:
	mk.jitter = 0.0
	match kind:
		"open":
			ModelItems.poly_flat(mk, Vector3.ZERO, ModelItems.circle_pts(0.075, 12), 0.016, Art.SAGE.darkened(0.1), Art.SAGE.lightened(0.15))
			ModelItems.poly_flat(mk, Vector3(0, 0.016, 0), ModelItems.circle_pts(0.025, 8), 0.004, Art.WHITE, Art.WHITE)
		"flow":
			ModelItems.poly_flat(mk, Vector3.ZERO, ModelItems.circle_pts(0.075, 12), 0.016, Art.SAGE.darkened(0.1), Art.SAGE.lightened(0.15))
			var ap := ModelItems.arrow_pts(0.12, 0.034, 0.09, 0.05)
			ModelItems.poly_flat(mk, Vector3(0, 0.016, 0), ap, 0.004, Art.WHITE, Art.WHITE, 0.0, Vector2(0.02, 0))
		_:
			ModelItems.poly_flat(mk, Vector3.ZERO, ModelItems.circle_pts(0.075, 12), 0.016, Art.CORAL.darkened(0.1), Art.CORAL.lightened(0.1))
			mk.box(Vector3(0, 0.02, 0), Vector3(0.1, 0.006, 0.03), Art.WHITE)

static func _vent_apply(st: StationNode, s: Dictionary) -> void:
	var open := bool(s.get("open", true))
	var flow := clampf(float(s.get("flow", 0.0)), -1.0, 1.0)
	var dir := 0
	if open and flow > 0.05:
		dir = 1
	elif open and flow < -0.05:
		dir = -1
	var c1 := st.changed("open", open)
	var c2 := st.changed("dir", dir)
	if c1 or c2:
		var flap: Node3D = st.parts["flap"]
		flap.rotation.x = -1.35 if open else 0.0
		var kind := "closed"
		if open:
			kind = "flow" if dir != 0 else "open"
		st.set_part_mesh("lamp", _c("st_vent_lamp_" + kind, _vent_lamp.bind(kind)))
		var ind: Node3D = st.parts["indicator"]
		ind.rotation.y = PI if dir < 0 else 0.0
		st.anim["dir"] = dir
	st.anim["flow"] = absf(flow)

static func _vent_tick(st: StationNode, dt: float) -> void:
	if int(st.anim.get("dir", 0)) != 0:
		var ind: Node3D = st.parts["indicator"]
		var k := 1.0 + 0.15 * sin(st.t * (4.0 + 6.0 * float(st.anim.get("flow", 0.0))))
		ind.scale = Vector3(k, 1, k)

# ================================================================ shutter

const SHUTTER_TOP := 0.98
const SHUTTER_DROP := 0.95

static func _shutter(st: StationNode) -> void:
	var axis_z := String(st.opts.get("axis", "z")) == "z"
	var root := _pivot(st, "frame", Vector3.ZERO, null, Vector3(0, 90 if axis_z else 0, 0))
	_mesh(st, "body", _c("st_shutter", _shutter_mesh), root)
	_mesh(st, "warn_lit", _c("st_shutter_warn", _shutter_warn), root, Vector3.ZERO, ModelItems.lit_mat())
	var slats := _pivot(st, "slats", Vector3(0, SHUTTER_TOP, 0), root)
	_mesh(st, "slats_mesh", _c("st_shutter_slats", _shutter_slats), slats)
	var bar := _pivot(st, "bar", Vector3(0, SHUTTER_TOP, 0), root)
	_mesh(st, "bar_mesh", _c("st_shutter_bar", _shutter_bar), bar)
	_mesh(st, "floor_marks", _c("st_shutter_marks", _shutter_marks), root)
	st.anim["k"] = 0.04
	st.anim["target"] = 0.04
	st.apply_fn = _shutter_apply
	st.tick_fn = _shutter_tick
	st.apply({"state": "open"})
	_shutter_pose(st, 0.04)

static func _shutter_mesh(mk: MeshKit) -> void:
	for s in [-1.0, 1.0]:
		mk.box(Vector3(s * 0.47, 0.5, 0), Vector3(0.07, 1.0, 0.16), Art.WALNUT, Art.WALNUT.lightened(0.15))
		mk.box(Vector3(s * 0.47, 0.03, 0), Vector3(0.1, 0.06, 0.2), Art.WALNUT.darkened(0.2))
	mk.rbox(Vector3(0, 1.08, 0), Vector3(1.04, 0.2, 0.24), Art.CREAM.darkened(0.08), 0.06, Art.CREAM)
	for i in 7:
		var x := -0.42 + i * 0.14
		var c := Art.GOLD if i % 2 == 0 else Art.CORAL
		mk.box(Vector3(x, 1.08, 0), Vector3(0.09, 0.205, 0.245), c.darkened(0.08), c)

static func _shutter_warn(mk: MeshKit) -> void:
	mk.jitter = 0.0
	for i in 7:
		var c := Color("#FFF4B8") if i % 2 == 0 else Color("#FFB7A3")
		mk.box(Vector3(-0.42 + i * 0.14, 1.08, 0), Vector3(0.1, 0.212, 0.252), c)

static func _shutter_slats(mk: MeshKit) -> void:
	var n := 8
	var h := SHUTTER_DROP / n
	for i in n:
		var c := Art.SKY.lightened(0.12) if i % 2 == 0 else Art.CREAM.darkened(0.04)
		mk.box(Vector3(0, -h * (i + 0.5), 0), Vector3(0.88, h * 0.94, 0.07), c, c.lightened(0.1))
		mk.box(Vector3(0, -h * (i + 1.0), 0), Vector3(0.88, 0.014, 0.09), c.darkened(0.15))

static func _shutter_bar(mk: MeshKit) -> void:
	mk.box(Vector3(0, -0.03, 0), Vector3(0.9, 0.06, 0.13), Art.BRASS, Art.BRASS.lightened(0.12))
	mk.sphere(Vector3(0, -0.07, 0.07), 0.03, Art.CORAL, 2, 6)

static func _shutter_marks(mk: MeshKit) -> void:
	mk.jitter = 0.0
	for s in [-1.0, 1.0]:
		for i in 4:
			var x := -0.33 + i * 0.22
			_chevron(mk, Vector3(x, 0.014, s * 0.3), 90.0 if s > 0 else -90.0, 0.16, Art.CORAL if i % 2 == 0 else Art.GOLD)

static func _shutter_apply(st: StationNode, s: Dictionary) -> void:
	var state := String(s.get("state", "open"))
	if not st.changed("state", state):
		return
	match state:
		"closed": st.anim["target"] = 1.0
		"warn": st.anim["target"] = 0.14
		_: st.anim["target"] = 0.04
	st.anim["warn"] = state == "warn"
	st.show_part("warn_lit", false)
	st.show_part("floor_marks", state != "open")

static func _shutter_pose(st: StationNode, k: float) -> void:
	var slats: Node3D = st.parts["slats"]
	slats.scale = Vector3(1, maxf(0.02, k), 1)
	var bar: Node3D = st.parts["bar"]
	bar.position.y = SHUTTER_TOP - SHUTTER_DROP * k

static func _shutter_tick(st: StationNode, dt: float) -> void:
	var k := float(st.anim.get("k", 0.04))
	var target := float(st.anim.get("target", 0.04))
	if absf(k - target) > 0.001:
		k = move_toward(k, target, dt * (1.6 if target > k else 1.1))
		st.anim["k"] = k
		_shutter_pose(st, k)
	if st.anim.get("warn", false):
		var on := _blink(st, 0.5)
		st.show_part("warn_lit", on)
		st.show_part("floor_marks", on)
