extends Node
## Dev: plays a shift with reference bots through the real presentation and
## saves screenshots.  godot --path . res://tools/dev/autoplay.tscn -- --level=L06 --humans=2 --secs=60 --out=build/shots/play.png [--speed=4] [--shots=3]
var level := "L06"
var humans := 2
var secs := 60.0
var out := "build/shots/play.png"
var speed := 4.0
var shots := 1
var main_like: Node
var shift: ShiftScreen
var bot: ReferenceBot
var t := 0.0
var shot_i := 0
var perf := false
var _max_fdc := 0
var _max_census := ""
var samples: Array = []
var _perf_t := 0.0
var _skip := 0

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--level="): level = a.substr(8)
		elif a.begins_with("--humans="): humans = int(a.substr(9))
		elif a.begins_with("--secs="): secs = float(a.substr(7))
		elif a.begins_with("--out="): out = a.substr(6)
		elif a.begins_with("--speed="): speed = float(a.substr(8))
		elif a.begins_with("--shots="): shots = int(a.substr(8))
		elif a == "--perf": perf = true
		elif a.begins_with("--graphics="): Settings.data["graphics"] = a.substr(11)
		elif a.begins_with("--set="):
			# --set=key=value for any Settings key (bool/float/string), e.g. --set=ui_scale=1.75
			var kv := a.substr(6).split("=", true, 1)
			var v: Variant = kv[1]
			if kv[1] in ["true", "false"]: v = kv[1] == "true"
			elif kv[1].is_valid_float(): v = float(kv[1])
			Settings.data[kv[0]] = v
		elif a.begins_with("--size="):
			var p := a.substr(7).split("x")
			DisplayServer.window_set_size(Vector2i(int(p[0]), int(p[1])))
	var l0 := CanvasLayer.new(); add_child(l0)
	var stage := PixelStage.new(); l0.add_child(stage)
	var l1 := CanvasLayer.new(); l1.layer = 1; add_child(l1)
	var ui := Control.new(); ui.theme = UiKit.theme(); l1.add_child(ui)
	# Mirror main.gd's layout: the UI root is scaled by the effective UI scale.
	var sc := Settings.effective_ui_scale()
	ui.scale = Vector2(sc, sc)
	ui.size = Vector2(DisplayServer.window_get_size()) / sc
	var l2 := CanvasLayer.new(); l2.layer = 5; add_child(l2)
	var cap := Captions.new(); l2.add_child(cap)
	InputRouter.reset_all()
	InputRouter.join("kb1")
	for i in range(1, humans):
		InputRouter.join("pad", 100 + i)
	var seats: Array = []
	for i in humans:
		seats.append({"seat": i, "char": SimC.STAFF_IDS[i], "cos": "default", "assists": {"auto_catch": true}})
	var cfg := {"mode": "campaign", "level_id": level, "humans": humans, "seats": seats, "difficulty": "family", "seed": 3,
		"modifiers": [], "gus": humans == 1, "first_visit_coaches": []}
	shift = ShiftScreen.new()
	shift.setup(stage, cap, cfg)
	ui.add_child(shift)
	bot = ReferenceBot.new(shift.sim)
	shift.frame_source = bot.frames
	Engine.time_scale = speed

func _process(dt: float) -> void:
	t += dt / maxf(0.01, Engine.time_scale)
	# Frames right after a screenshot (synchronous PNG save) are not game frames.
	if _skip > 0:
		_skip -= 1
	elif perf and t > 3.0:
		if dt * 1000.0 / maxf(0.01, Engine.time_scale) > 25.0:
			var kinds: Array = []
			for e in shift.sim.events:
				kinds.append(e["type"])
			print("SPIKE %.1fms hotel %ds events %s" % [dt * 1000.0, int(shift.sim.s["hotel_q"]) / SimC.HOTEL_Q_PER_S, kinds])
		var fdc := _floor_draw_calls()
		if "--census" in OS.get_cmdline_user_args() and fdc > _max_fdc:
			# Name what is on screen at the busiest frame so far (the §17.4 budget moment).
			_max_fdc = fdc
			_max_census = "CENSUS at floor draw calls %d (hotel %ds)\n%s" % [fdc, int(shift.sim.s["hotel_q"]) / SimC.HOTEL_Q_PER_S, _census_text()]
		samples.append({"frame_ms": dt * 1000.0 / maxf(0.01, Engine.time_scale), "hotel_s": int(shift.sim.s["hotel_q"]) / SimC.HOTEL_Q_PER_S,
			"process_ms": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
			"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			"floor_draw_calls": fdc,
			"objects": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
			"primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
			"mem_mb": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
			"vram_mb": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0})
	var due := secs * float(shot_i + 1) / float(shots)
	var hotel_t := float(shift.sim.s["hotel_q"]) / SimC.HOTEL_Q_PER_S
	# --lift-demo: at hotel 3 s put the first loose item on lift pad 0 and send it,
	# so frames around 3.6 / 4.8 / 6.0 s show the car sinking, rising and arrived.
	if "--lift-demo" in OS.get_cmdline_user_args() and not has_meta("lift_demo") and hotel_t >= 3.0:
		set_meta("lift_demo", true)
		for iid in shift.sim.s["items"]:
			var it: Dictionary = shift.sim.s["items"][iid]
			if it["loc"] in ["world", "sock"]:
				SimInteract.sock_item(shift.sim, int(iid), "liftpad:0")
				SimGoals.lift_send(shift.sim, 0, 0)
				print("lift demo: sent item %d (%s)" % [int(iid), it["k"]])
				break
	if not has_meta("p"):
		set_meta("p", true)
		print("sizes ui=%s shift=%s hud=%s" % [shift.get_parent().size, shift.size, shift.hud.size])
	if hotel_t >= due or t > 600.0:
		Engine.time_scale = 1.0
		# --a11y-demo: fire the v2 sound events at the shot so the frame shows
		# their captions and sound marks (evidence for §11.2, not gameplay).
		if "--a11y-demo" in OS.get_cmdline_user_args():
			var seat0: int = shift.sim.s["staff"][0]["seat"] if not shift.sim.s["staff"].is_empty() else 0
			var room0: String = shift.sim.L.active_rooms[0]
			var demo := [{"type": "slip", "seat": seat0, "kind": "frost", "room": room0},
				{"type": "tempered", "seat": seat0, "id": 0, "temp": "cool", "vent": "AB"},
				{"type": "watered", "room": room0, "seat": seat0}]
			shift.hud.feed(shift.sim.s, demo)
			shift._feedback(demo)
			# And the three lane hazards side by side on the lane, for palette frames.
			var lane_z: int = (shift.sim.L.hall.position.y + 1) * SimC.UM
			var hx0: int = (shift.sim.L.hall.position.x + 2) * SimC.UM
			SimEnv.add_puddle(shift.sim, hx0, lane_z, "demo")
			SimEnv.add_cloud(shift.sim, hx0 + 3 * SimC.UM, lane_z, "demo")
			shift.sim.room(room0)["frost"] = true
		await get_tree().process_frame
		await get_tree().process_frame
		var img := get_viewport().get_texture().get_image()
		var path := out if shots == 1 else out.replace(".png", "_%d.png" % shot_i)
		img.save_png(ProjectSettings.globalize_path("res://").path_join(path))
		print("saved %s at hotel %.0fs phase %s" % [path, hotel_t, shift.sim.s["phase"]])
		print("done_cards at shot: %s" % JSON.stringify(shift.hud.done_cards))
		shot_i += 1
		_skip = 3
		Engine.time_scale = speed
		if shot_i >= shots:
			if perf:
				_report_perf()
			get_tree().quit()

## Draw calls of the 3D floor viewport (colour + shadow passes), i.e. the
## §17.4 "busy floor" budget, separate from UI and offscreen photo viewports.
func _floor_draw_calls() -> int:
	var vp := shift.stage.viewport.get_viewport_rid()
	return RenderingServer.viewport_get_render_info(vp, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME) \
		+ RenderingServer.viewport_get_render_info(vp, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)

## Visible MeshInstance3D count per top-level group under the stage world,
## and how many cast shadows (each caster adds a shadow-pass draw).
func _census() -> void:
	print(_census_text())

## Visible meshes per group; groups that are not stations also list their
## mesh paths, so an unexpected draw call can be named.
func _census_text() -> String:
	var groups := {}
	var names := {}
	for top in shift.stage.world.get_children():
		_census_walk(top, str(top.name), groups, names, 0)
	var keys := groups.keys()
	keys.sort_custom(func(a, b): return groups[a][0] > groups[b][0])
	var tm := 0
	var tc := 0
	var lines: Array = []
	for k in keys:
		tm += groups[k][0]
		tc += groups[k][1]
		lines.append("CENSUS %-28s meshes %4d casters %4d" % [k, groups[k][0], groups[k][1]])
		if not str(k).begins_with("st:") and names.has(k):
			lines.append("CENSUS   %s: %s" % [k, ", ".join((names[k] as Array).slice(0, 16))])
	lines.append("CENSUS TOTAL meshes %d casters %d" % [tm, tc])
	return "\n".join(lines)

func _census_walk(n: Node, label: String, groups: Dictionary, names: Dictionary, depth: int) -> void:
	if n is Node3D and not (n as Node3D).visible:
		return
	var lab := label
	if depth == 1:
		var nm := String(n.name)
		lab = nm.get_slice("_", 0) if not nm.begins_with("@") else "anon:" + (String(n.get_child(0).name).get_slice("_", 0) if n.get_child_count() > 0 else "?")
		if n is StationNode:
			lab = "st:" + (n as StationNode).kind
	if n is MeshInstance3D:
		var e: Array = groups.get(lab, [0, 0])
		e[0] += 1
		if (n as MeshInstance3D).cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			e[1] += 1
		groups[lab] = e
		var nl: Array = names.get(lab, [])
		var mi := n as MeshInstance3D
		nl.append("%s/%s(%d)" % [String(n.get_parent().name), String(n.name), mi.mesh.get_surface_count() if mi.mesh != null else 0])
		names[lab] = nl
	for c in n.get_children():
		_census_walk(c, lab, groups, names, depth + 1)

func _report_perf() -> void:
	if "--census" in OS.get_cmdline_user_args():
		_census()
		# Split draw calls between the 3D stage viewport and the 2D UI.
		var vp_rid := shift.stage.viewport.get_viewport_rid()
		print("CENSUS stage-viewport draw calls %d objects %d" % [RenderingServer.viewport_get_render_info(vp_rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME),
			RenderingServer.viewport_get_render_info(vp_rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_OBJECTS_IN_FRAME)])
		print("CENSUS stage-viewport shadow draw calls %d" % RenderingServer.viewport_get_render_info(vp_rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME))
		var root_rid := get_viewport().get_viewport_rid()
		print("CENSUS root-viewport canvas (UI) draw calls %d; stage canvas %d" % [
			RenderingServer.viewport_get_render_info(root_rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_CANVAS, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME),
			RenderingServer.viewport_get_render_info(vp_rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_CANVAS, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)])
	var fr: Array = []
	var keys := ["process_ms", "draw_calls", "floor_draw_calls", "objects", "primitives", "mem_mb", "vram_mb"]
	var mx := {}
	for smp in samples:
		fr.append(smp["frame_ms"])
		for k in keys:
			mx[k] = maxf(float(mx.get(k, 0.0)), float(smp[k]))
	fr.sort()
	var n := fr.size()
	if n == 0:
		return
	var avg := 0.0
	for v in fr:
		avg += v
	avg /= n
	var sim_ms := 0.0
	# Simulation cost per tick measured directly.
	var tt := Time.get_ticks_usec()
	for i in 60:
		shift.sim.step(bot.frames())
	sim_ms = (Time.get_ticks_usec() - tt) / 60000.0
	var by_time := samples.duplicate()
	by_time.sort_custom(func(a, b): return a["frame_ms"] > b["frame_ms"])
	var spikes: Array = []
	for smp2 in by_time.slice(0, 5):
		spikes.append("%.1fms@%ds" % [smp2["frame_ms"], smp2["hotel_s"]])
	print("PERF spikes ", ", ".join(spikes))
	if _max_census != "":
		print(_max_census)
	print("PERF level=%s humans=%d size=%s renderer=%s adapter=%s frames=%d avg_ms=%.2f p95_ms=%.2f max_ms=%.2f sim_tick_ms=%.3f max=%s" % [level, humans, DisplayServer.window_get_size(), RenderingServer.get_current_rendering_method(), RenderingServer.get_video_adapter_name(), n, avg, fr[int(n * 0.95)], fr[n - 1], sim_ms, JSON.stringify(mx)])
