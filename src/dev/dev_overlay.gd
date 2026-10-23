class_name DevOverlay
extends CanvasLayer
## Developer overlay and inspector for a running local shift (§19.5). Only
## exists when the game is launched with `-- --dev`; never in normal play.
##   F1 panel   F2 world overlay (nav grid, anchors, room climate)
##   F5 hold/resume   F6 step one action tick   F7 step one hotel second
##   F8 fire the next authored event now   F9 reset to seed

const KEYS_HELP := "F1 panel · F2 world · F5 hold · F6 tick · F7 hotel s · F8 next event · F9 reset to seed"

var shift: ShiftScreen
var panel: PanelContainer
var text: Label
var world: Node3D
var _t := 0.0

static func enabled() -> bool:
	return "--dev" in OS.get_cmdline_user_args()

func _init(p_shift: ShiftScreen) -> void:
	shift = p_shift
	layer = 60
	name = "DevOverlay"

func _ready() -> void:
	panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.09, 0.12, 0.82)
	sb.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel", sb)
	panel.position = Vector2(8, 96)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text = Label.new()
	text.add_theme_font_size_override("font_size", 12)
	text.add_theme_color_override("font_color", Color("#E8F0E0"))
	panel.add_child(text)
	add_child(panel)

func _unhandled_key_input(ev: InputEvent) -> void:
	var k := ev as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	var sim := shift.sim
	match k.keycode:
		KEY_F1: panel.visible = not panel.visible
		KEY_F2: _toggle_world()
		KEY_F5: shift.dev_hold = not shift.dev_hold
		KEY_F6:
			shift.dev_hold = true
			shift.dev_steps += 1
		KEY_F7:
			shift.dev_hold = true
			shift.dev_steps += SimC.HOTEL_Q_PER_S if sim == null else _ticks_per_hotel_second(sim)
		KEY_F8:
			if sim != null:
				_fire_next_event(sim)
		KEY_F9:
			Session._run_shift(shift.cfg.duplicate(true))
		_:
			return
	get_viewport().set_input_as_handled()

func _ticks_per_hotel_second(sim: HotelSim) -> int:
	# Hotel time advances by the pace each action tick; a hotel second is Q units.
	var pace := maxi(1, int(sim.s.get("pace", 1000)))
	return maxi(1, int(ceil(float(SimC.HOTEL_Q_PER_S) / pace)))

func _fire_next_event(sim: HotelSim) -> void:
	var evs: Array = sim.level.get("events", []).duplicate()
	evs.sort_custom(func(a, b): return int(a["at"]) < int(b["at"]))
	for ev in evs:
		if not sim.s["fired"].has(ev["id"]):
			sim.s["fired"][ev["id"]] = true
			SimDirector._fire_event(sim, ev)
			return

func _process(dt: float) -> void:
	_t += dt
	if _t < 0.2 or not panel.visible:
		return
	_t = 0.0
	text.text = _report()
	if world != null:
		_refresh_world()

func _report() -> String:
	var lines: PackedStringArray = [KEYS_HELP]
	if shift.online:
		var st := Net.client_state()
		lines.append("ONLINE  rtt %.0f ms  snapshot age %d ms  snap #%d  interval %.0f ms" % [Net.c_rtt,
			Time.get_ticks_msec() - Net.c_last_snap_ms, int(st.get("_snap_id", 0)), Net.c_snap_interval])
		lines.append("phase %s  hotel %ss" % [st.get("phase", "?"), st.get("hotel_s", "?")])
		return "\n".join(lines)
	var sim := shift.sim
	var s: Dictionary = sim.s
	lines.append("%s  seed %d  %s  hash %s  content %s" % [sim.level.get("id", "?"), int(sim.cfg.get("seed", 0)),
		sim.cfg.get("difficulty", ""), sim.state_hash().substr(0, 8), Content.content_hash.substr(0, 8)])
	lines.append("tick %d  hotel %.1fs / %ds  phase %s%s" % [s["tick"], float(s["hotel_q"]) / SimC.HOTEL_Q_PER_S,
		int(sim.level.get("duration_hotel_s", 0)), s["phase"], "  [HOLD]" if shift.dev_hold else ""])
	# Arrivals still to come.
	var next: PackedStringArray = []
	for gid in s["guests"]:
		var g: Dictionary = s["guests"][gid]
		if g["state"] == "announced" and next.size() < 6:
			next.append("%s@%ds" % [g["fam"], int(g["arrive_q"]) / SimC.HOTEL_Q_PER_S])
	lines.append("arrivals: " + (", ".join(next) if not next.is_empty() else "—"))
	var d: Dictionary = s.get("director", {})
	var act: PackedStringArray = []
	for inc in d.get("active", []):
		act.append("%s:%s→%ds" % [inc.get("kind", "?"), inc.get("room", ""), int(inc.get("until_s", 0))])
	lines.append("incidents %d active [%s]  %d pending" % [act.size(), ", ".join(act), d.get("pending", []).size()])
	var fired: PackedStringArray = []
	for ev in sim.level.get("events", []):
		fired.append("%s%s@%d" % ["✓" if s["fired"].has(ev["id"]) else "·", ev["type"], int(ev["at"])])
	lines.append("events " + " ".join(fired))
	for letter in s["rooms"]:
		var r: Dictionary = s["rooms"][letter]
		if not sim.L.rooms.get(letter, {}).get("active", false):
			continue
		var g2: Dictionary = s["guests"].get(r["guest"], {})
		lines.append("%s heat %3d noise %3d hum %3d  bed %-8s mess %3d  %s%s" % [letter, int(r.get("heat", 0)), int(r.get("noise", 0)),
			int(r.get("hum", 0)), r["bed"], int(r.get("mess", 0)), g2.get("fam", "") if not g2.is_empty() else ("res" if r.get("reserved", 0) != 0 else "—"),
			(" comf %ds %s" % [int(g2.get("comf_s", 0)), "✓" if g2.get("comfortable", false) else "✗"]) if not g2.is_empty() else ""])
	for st in s["staff"]:
		var it := sim.item(st["held"])
		lines.append("seat %d %-6s held %s#%d  work %s  grip %d  %s" % [st["seat"], st["char"], it.get("k", "—"), int(st["held"]),
			st.get("work_key", ""), int(st.get("grip", 0)), "" if st["present"] else "ABSENT"])
	var work: PackedStringArray = []
	for k in s.get("work", {}):
		work.append("%s p=%d" % [k, int(s["work"][k].get("p", 0))])
	lines.append("pending work: " + (", ".join(work) if not work.is_empty() else "—"))
	var goals: PackedStringArray = []
	for gk in s.get("goals", {}):
		goals.append("%s %s" % [gk, "✓" if s["goals"][gk].get("done", false) else "·"])
	if not goals.is_empty():
		lines.append("goals: " + ", ".join(goals))
	var stv: Dictionary = s["st"]
	lines.append("stock towels %d snacks %d linen %d hamper %d" % [int(stv["towels"]), int(stv["snacks"]), int(stv["linen"]), int(stv["hamper_q"])])
	return "\n".join(lines)

# ------------------------------------------------------------ world overlay

func _toggle_world() -> void:
	if world != null:
		world.queue_free()
		world = null
		return
	if shift.sim == null:
		return
	world = Node3D.new()
	world.name = "DevWorld"
	shift.stage.world.add_child(world)
	var L: LayoutDef = shift.sim.L
	var mk := MeshKit.new()
	mk.jitter = 0.0
	# Nav grid: walkable tiles as small green squares; blocked as red.
	for x in range(0, 28):
		for z in range(0, 20):
			var free := SimMove.point_free(shift.sim, x * SimC.UM, z * SimC.UM, SimC.RADIUS)
			mk.flat(Vector3(x, 0.03, z), Vector2(0.18, 0.18), Color("#6CE07A") if free else Color("#E0605A"))
	var grid := MeshInstance3D.new()
	grid.mesh = mk.commit()
	grid.material_override = Art.fx(Color(1, 1, 1), 0.55)
	grid.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(grid)
	# Interaction anchors: yellow posts at every room fixture.
	var mk2 := MeshKit.new()
	mk2.jitter = 0.0
	for letter in L.rooms:
		var g: Dictionary = L.rooms[letter]
		for key in ["door", "bed", "plinth", "thermostat", "tray", "drop"]:
			if g.has(key):
				var p: Vector2i = g[key]
				mk2.box(Vector3(p.x, 0.5, p.y), Vector3(0.06, 1.0, 0.06), Color("#FFD24A"))
	var anchors := MeshInstance3D.new()
	anchors.mesh = mk2.commit()
	anchors.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(anchors)
	for letter in L.rooms:
		if not L.rooms[letter]["active"]:
			continue
		var lab := Label3D.new()
		lab.name = "env_" + letter
		lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lab.pixel_size = 0.008
		lab.font_size = 28
		lab.outline_size = 6
		var r: Rect2i = L.rooms[letter]["rect"]
		lab.position = Vector3(r.position.x + r.size.x * 0.5, 1.6, r.position.y + r.size.y * 0.5)
		world.add_child(lab)

func _refresh_world() -> void:
	for c in world.get_children():
		if c is Label3D:
			var letter := String(c.name).substr(4)
			var r: Dictionary = shift.sim.s["rooms"].get(letter, {})
			(c as Label3D).text = "%s  heat %d  noise %d  hum %d" % [letter, int(r.get("heat", 0)), int(r.get("noise", 0)), int(r.get("hum", 0))]
