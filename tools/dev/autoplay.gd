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
		elif a.begins_with("--size="):
			var p := a.substr(7).split("x")
			DisplayServer.window_set_size(Vector2i(int(p[0]), int(p[1])))
	var l0 := CanvasLayer.new(); add_child(l0)
	var stage := PixelStage.new(); l0.add_child(stage)
	var l1 := CanvasLayer.new(); l1.layer = 1; add_child(l1)
	var ui := Control.new(); ui.theme = UiKit.theme(); l1.add_child(ui)
	ui.size = Vector2(1280, 720)
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
		samples.append({"frame_ms": dt * 1000.0 / maxf(0.01, Engine.time_scale), "hotel_s": int(shift.sim.s["hotel_q"]) / SimC.HOTEL_Q_PER_S,
			"process_ms": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
			"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			"objects": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
			"primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
			"mem_mb": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
			"vram_mb": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0})
	var due := secs * float(shot_i + 1) / float(shots)
	var hotel_t := float(shift.sim.s["hotel_q"]) / SimC.HOTEL_Q_PER_S
	if not has_meta("p"):
		set_meta("p", true)
		print("sizes ui=%s shift=%s hud=%s" % [shift.get_parent().size, shift.size, shift.hud.size])
	if hotel_t >= due or t > 600.0:
		Engine.time_scale = 1.0
		await get_tree().process_frame
		await get_tree().process_frame
		var img := get_viewport().get_texture().get_image()
		var path := out if shots == 1 else out.replace(".png", "_%d.png" % shot_i)
		img.save_png(ProjectSettings.globalize_path("res://").path_join(path))
		print("saved %s at hotel %.0fs phase %s" % [path, hotel_t, shift.sim.s["phase"]])
		shot_i += 1
		_skip = 3
		Engine.time_scale = speed
		if shot_i >= shots:
			if perf:
				_report_perf()
			get_tree().quit()

func _report_perf() -> void:
	var fr: Array = []
	var keys := ["process_ms", "draw_calls", "objects", "primitives", "mem_mb", "vram_mb"]
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
	print("PERF level=%s humans=%d size=%s renderer=%s adapter=%s frames=%d avg_ms=%.2f p95_ms=%.2f max_ms=%.2f sim_tick_ms=%.3f max=%s" % [level, humans, DisplayServer.window_get_size(), RenderingServer.get_current_rendering_method(), RenderingServer.get_video_adapter_name(), n, avg, fr[int(n * 0.95)], fr[n - 1], sim_ms, JSON.stringify(mx)])
