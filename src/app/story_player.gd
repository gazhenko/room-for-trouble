class_name StoryPlayer
extends Control
## Data-driven story panels (§4.1): in-engine staging on the hotel set with
## camera presets, posed actors and props; captions with speaker names; gentle
## camera drift (cuts in reduced motion); confirm advances after the minimum
## read time max(2.0, 0.045 × chars); skip asks once, and is immediate for
## scenes everyone has already seen. Story pauses hotel and action clocks.

## Camera presets live in StoryStaging.CAMERAS (shared with the content validator).

signal done

var stage: PixelStage
var captions: Captions
var scene: Dictionary
var panels: Array = []
var idx := -1
var t := 0.0
var min_t := 2.0
var dur := 6.0
var then: Callable
var set_root: Node3D
var actors: Dictionary = {}
var cam_from: Transform3D
var cam_to: Transform3D
var skip_prompt := false
var seen_before := false
var _postcard := false
var _layout := ""
var _L: LayoutDef = null
var _caption := ""
var _speaker := ""
var _credits := false
var _finished := false
var _view: HotelView = null
var _staged: Dictionary = {}
var _culled: Array = []            # hotel stations hidden for this panel (sightline to a face)
var _fov := 30.0

func setup(p_stage: PixelStage, p_captions: Captions, p_scene: Dictionary, p_then: Callable) -> void:
	stage = p_stage
	captions = p_captions
	scene = p_scene
	panels = scene.get("panels", [])
	then = p_then
	seen_before = SaveService.story_seen(scene.get("id", ""))
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

func _ready() -> void:
	InputRouter.gameplay = false
	InputRouter.menu_accept.connect(_on_accept)
	InputRouter.menu_back.connect(_on_skip)
	InputRouter.menu_pause.connect(_on_skip)
	if scene.has("music"):
		Audio.play_music(scene["music"])
	_next()

func _exit_tree() -> void:
	# The next scene may already own the captions: drop only this scene's line.
	if not _finished and _caption != "":
		captions.drop(_caption)
	for pair in [[InputRouter.menu_accept, _on_accept], [InputRouter.menu_back, _on_skip], [InputRouter.menu_pause, _on_skip]]:
		if pair[0].is_connected(pair[1]):
			pair[0].disconnect(pair[1])
	stage.dynamic_offset = Vector3.ZERO
	stage.fit_camera()

func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed:
		_on_accept(0)

func _on_accept(_seat: int) -> void:
	if skip_prompt:
		_finish()
		return
	if _credits:
		return
	if t >= min_t:
		_next()

func _on_skip(_seat: int) -> void:
	if seen_before:
		_finish()
		return
	if skip_prompt:
		skip_prompt = false
		return
	skip_prompt = true

func _next() -> void:
	idx += 1
	if idx >= panels.size():
		_finish()
		return
	var p: Dictionary = panels[idx]
	t = 0.0
	_caption = Loc.t(p.get("caption", "")) if p.get("caption", "") != "" else ""
	_speaker = p.get("speaker", "")
	if _speaker == "staff":
		_speaker = _party_chars()[0]
	dur = float(p.get("duration", 6.0))
	min_t = maxf(2.0, 0.045 * _caption.length())
	_postcard = p.get("camera", "") == "postcard_still"
	_credits = p.get("credits", false)
	_stage(p)
	captions.clear()
	if _caption != "":
		captions.push(_speaker, _caption, "story", maxf(dur, min_t) + 0.5)
	if p.has("sound"):
		Audio.sfx(p["sound"])
	if p.has("sting"):
		Audio.sting(p["sting"])
	SaveService.mark_story_seen(p.get("id", ""))
	if Settings.g("read_aloud") and _caption != "" and DisplayServer.get_name() != "headless":
		var voices := DisplayServer.tts_get_voices_for_language("en")
		if not voices.is_empty():
			DisplayServer.tts_stop()
			DisplayServer.tts_speak(_caption, voices[0])

func _finish() -> void:
	if not is_inside_tree():
		return
	_finished = true
	captions.clear()
	SaveService.mark_story_seen(scene.get("id", ""))
	if then.is_valid():
		var cb := then
		then = Callable()
		cb.call()
	done.emit()
	queue_free()

var _photo_set: Node3D

func _ensure_photo_set() -> void:
	if _photo_set != null and is_instance_valid(_photo_set):
		return
	_photo_set = Node3D.new()
	_photo_set.position = StoryStaging.PHOTO_ORIGIN
	var mk := MeshKit.new()
	mk.jitter = 0.0
	var night: bool = scene.get("id", "") in ["E00"]
	mk.flat(Vector3(0, 0, 0.5), Vector2(10, 7), Color("#B98F6E"))
	mk.box(Vector3(0, 1.5, -2.4), Vector3(10, 3.0, 0.3), Art.CREAM)
	mk.box(Vector3(0, 0.06, -2.22), Vector3(10, 0.12, 0.08), Art.WALNUT)
	var cols := [Art.CORAL, Art.GOLD, Art.SKY, Art.SAGE, Art.PLUM]
	for i in 17:
		mk.cone(Vector3(-4.8 + i * 0.6, 2.55, -2.2), 0.14, -0.3, cols[i % 5], 3)
	mk.box(Vector3(3.0, 1.7, -2.22), Vector3(1.3, 1.0, 0.05), Art.WALNUT)
	mk.box(Vector3(3.0, 1.7, -2.19), Vector3(1.1, 0.82, 0.04), Color("#3E4C7A") if night else Color("#BFE0EA"))
	mk.sphere(Vector3(3.25, 1.9, -2.16), 0.16, Color("#FFF3C8"), 3, 6, Vector3(1, 1, 0.3))
	mk.box(Vector3(-2.8, 1.95, -2.22), Vector3(2.0, 0.55, 0.05), Art.GOLD)
	mk.box(Vector3(-2.8, 1.95, -2.19), Vector3(1.8, 0.4, 0.03), Art.INK)
	mk.flat(Vector3(0, 0.01, 0.2), Vector2(6.0, 2.6), Art.CORAL.lerp(Art.CREAM, 0.4))
	# A low riser for the back row of guests (group-photo staging).
	mk.box(Vector3(0, 0.2, -0.85), Vector3(6.0, 0.4, 0.95), Art.WALNUT, Art.WALNUT.lightened(0.25))
	_photo_set.add_child(Art.mesh_instance(mk.commit()))
	set_root.add_child(_photo_set)

func _stage(p: Dictionary) -> void:
	var layout: String = p.get("layout", scene.get("layout", "P1"))
	if layout != _layout or set_root == null:
		for c in stage.world.get_children():
			c.queue_free()
		set_root = Node3D.new()
		stage.world.add_child(set_root)
		var L := Content.layout(layout)
		_L = L
		var fam := layout.substr(0, 2)   # P1..P6, classic or v2
		var sys := {"core": true, "thermal": fam != "P1", "sound": fam in ["P3", "P4", "P5", "P6"],
			"moisture": fam in ["P4", "P5", "P6"], "festival": fam in ["P1", "P6"],
			"shutter": fam == "P5", "lift": fam == "P5"}
		# The real hotel set: shell, stations and made-up rooms, without mess.
		var view := HotelView.new()
		# Story keeps station bodies unmerged so one in a sightline can be hidden.
		view.build(stage, L, sys, {"story": true})
		view.reparent(set_root)
		for letter in view.mess_nodes:
			(view.mess_nodes[letter] as Node3D).visible = false
			view._apply("bed:" + letter, {"bed": "Made", "occupied": false})
		_view = view
		_culled.clear()
		_layout = layout
		actors.clear()
	# Positions, props and the camera come from the shared staging (StoryStaging):
	# classic authoring mapped onto this floor, scaled with the toys.
	var aspect := size.x / size.y if size.y > 1.0 else 16.0 / 9.0
	var staged := StoryStaging.stage(_L, p, StoryStaging.CAMERAS, _party_chars(), aspect)
	_staged = staged
	# Actors persist across panels by id; reposition/pose per panel.
	var wanted := {}
	for a in staged["actors"]:
		_place_actor(a)
		wanted[a["id"]] = true
	for k in actors.keys():
		if not wanted.has(k):
			(actors[k] as Node3D).queue_free()
			actors.erase(k)
	for c in set_root.get_children():
		if c.has_meta("prop"):
			c.queue_free()
	for pr in staged["props"]:
		var kind: String = pr["kind"]
		var node := ModelItems.build(kind.substr(5)) if kind.begins_with("item:") else ModelProps.build(kind)
		node.position = pr["pos3"]
		node.rotation_degrees.y = float(pr.get("rot", 0))
		if pr.has("scale"):
			node.scale = Vector3.ONE * float(pr["scale"])
		node.set_meta("prop", true)
		set_root.add_child(node)
	if staged["photo"]:
		_ensure_photo_set()
		_photo_set.scale = Vector3.ONE * float(staged["set_scale"])
	var pos: Vector3 = staged["cam_pos"]
	var look: Vector3 = staged["cam_look"]
	_fov = float(staged["fov"])
	stage.camera.fov = _fov
	cam_to = Transform3D(Basis(), pos).looking_at(look, Vector3.UP)
	var drift := Vector3(-0.35, 0.12, -0.25) if not Settings.g("reduced_motion") else Vector3.ZERO
	cam_from = Transform3D(cam_to.basis, cam_to.origin - drift)
	_cull_occluders(pos)

func _party_chars() -> Array:
	var out: Array = []
	for s in InputRouter.active_seats():
		out.append(InputRouter.seats[s]["char"])
	if out.is_empty():
		out = ["pip"]
	return out

func _place_actor(a: Dictionary) -> void:
	var aid: String = a["id"]
	var staff_char: String = a.get("char", "")
	var rig: ActorRig = actors.get(aid, null)
	if rig == null:
		if staff_char != "":
			var cos := {}
			for cs in Content.cosmetics:
				if cs["id"] == SaveService.profile.get("selected_cosmetic_set", "default"):
					cos = cs
			rig = ModelActors.staff(staff_char, cos if not cos.is_empty() else Content.cosmetics[0])
		elif aid in ["nana", "gus", "dot"]:
			rig = ModelActors.npc(aid)
		else:
			var fam := _family_of(aid)
			rig = ModelActors.guest(fam, aid)
		set_root.add_child(rig)
		actors[aid] = rig
	rig.position = a["pos3"]
	rig.face_dir = deg_to_rad(float(a.get("face", 0)))
	rig.set_anim(a.get("pose", "idle"))
	rig.speed = 0.0
	if rig.extras.has("slippers"):
		(rig.extras["slippers"] as Node3D).visible = a.get("slippers", false)
	if rig.extras.has("mask"):
		(rig.extras["mask"] as Node3D).visible = a.get("mask", false)
	rig.reduced_motion = bool(Settings.g("reduced_motion"))

## Hotel stations standing between the camera and a face are hidden for the
## panel (the compact halls put a station row a metre in front of the lane, so
## any shot from the south would otherwise look through the bell stand or the
## linen shelf). Story props and actors are never hidden: they are authored.
func _cull_occluders(cam_pos: Vector3) -> void:
	for n in _culled:
		if is_instance_valid(n):
			(n as Node3D).visible = true
	_culled.clear()
	if _view == null or _staged.get("photo", false):
		return
	var targets: Array = []
	for aid in actors:
		var rig: ActorRig = actors[aid]
		var h := rig.height * ModelActors.ACTOR_SCALE
		targets.append(rig.position + Vector3(0, h * 0.78, 0))
		targets.append(rig.position + Vector3(0, h + 0.25, 0))
	for key in _view.stations:
		var st: Node3D = _view.stations[key]
		if not is_instance_valid(st) or not st.visible:
			continue
		var box := _world_aabb(st)
		if box.size == Vector3.ZERO:
			continue
		box = box.grow(0.25)
		for t in targets:
			if box.intersects_segment(cam_pos, t) != null:
				st.visible = false
				_culled.append(st)
				break

static func _world_aabb(n: Node3D) -> AABB:
	var box := AABB()
	var first := true
	var list: Array = n.find_children("*", "VisualInstance3D", true, false)
	if n is VisualInstance3D:
		list.append(n)
	for vi in list:
		if not (vi as Node3D).visible:
			continue
		var b: AABB = (vi as VisualInstance3D).global_transform * (vi as VisualInstance3D).get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box

## Dev report for the UI tour (tools/dev/ui_tour.gd --only=...): where every
## actor's head and face land in the frame at the camera's rest position, and
## what stands between the camera and the speaker's face. Fractions of the
## frame; the pass bar is the letterbox, the caption band and the postcard frame.
func frame_report() -> Dictionary:
	var cam := stage.camera
	var keep := cam.transform
	cam.transform = cam_to
	var vs := Vector2(stage.viewport.size)
	var hgt := maxf(1.0, size.y)
	var top_lim := 34.0 / hgt + 0.004
	var bottom_lim := 1.0
	var caption_top := (hgt - 70.0 - 34.0) / hgt
	if _postcard:
		top_lim = 0.1 + 14.0 / hgt + 0.004
		bottom_lim = 0.76 - 14.0 / hgt
	var spk_id := _speaker_actor()
	var p: Dictionary = panels[idx]
	var rep := {"beat": p.get("id", ""), "camera": p.get("camera", ""), "layout": _layout, "speaker": _speaker,
		"speaker_actor": spk_id, "photo": _postcard, "culled": _culled.size(), "shift": snappedf(float(_staged.get("shift", 0.0)), 0.01),
		"heads": [], "heads_ok": true, "speaker_ok": true, "occluders": []}
	for aid in actors:
		var rig: ActorRig = actors[aid]
		var h := rig.height * ModelActors.ACTOR_SCALE
		var top := rig.position + Vector3(0, h + StoryStaging.HEAD_PAD, 0)
		var face := rig.position + Vector3(0, h * 0.78, 0)
		if cam.is_position_behind(face):
			rep["heads"].append({"id": aid, "behind": true})
			rep["heads_ok"] = false
			continue
		var pt := cam.unproject_position(top) / vs
		var pf := cam.unproject_position(face) / vs
		var pb := cam.unproject_position(rig.position) / vs
		var ok := pt.y >= top_lim and pt.x >= 0.02 and pt.x <= 0.98 and pb.y <= bottom_lim
		rep["heads"].append({"id": aid, "top": [snappedf(pt.x, 0.001), snappedf(pt.y, 0.001)], "face_y": snappedf(pf.y, 0.001), "feet_y": snappedf(pb.y, 0.001), "ok": ok})
		if not ok:
			rep["heads_ok"] = false
		if aid == spk_id:
			if not ok or pf.y > caption_top:
				rep["speaker_ok"] = false
			for other in actors:
				if other == aid:
					continue
				var orig: ActorRig = actors[other]
				var oh := orig.height * ModelActors.ACTOR_SCALE
				var ob := AABB(orig.position - Vector3(oh * 0.25, 0, oh * 0.25), Vector3(oh * 0.5, oh, oh * 0.5))
				if ob.intersects_segment(cam_to.origin, face) != null:
					rep["occluders"].append("actor:" + other)
			for c in set_root.get_children():
				if c.has_meta("prop") and c is Node3D:
					var pbx := _world_aabb(c)
					if pbx.size != Vector3.ZERO and pbx.intersects_segment(cam_to.origin, face) != null:
						rep["occluders"].append("prop:" + String(c.name))
			if _view != null:
				for key in _view.stations:
					var st: Node3D = _view.stations[key]
					if not is_instance_valid(st) or not st.visible:
						continue
					var sbx := _world_aabb(st)
					if sbx.size != Vector3.ZERO and sbx.intersects_segment(cam_to.origin, face) != null:
						rep["occluders"].append("station:" + str(key))
			if not rep["occluders"].is_empty():
				rep["speaker_ok"] = false
	cam.transform = keep
	return rep

func _speaker_actor() -> String:
	if _speaker == "":
		return ""
	if actors.has(_speaker):
		return _speaker
	var party := _party_chars()
	var i := party.find(_speaker)
	if i >= 0 and actors.has("staff%d" % i):
		return "staff%d" % i
	return ""

static func _family_of(aid: String) -> String:
	return StoryStaging.family_of(aid)

func _process(dt: float) -> void:
	t += dt
	var k := clampf(t / maxf(0.1, dur), 0.0, 1.0)
	var e := k * k * (3.0 - 2.0 * k)
	# The story owns the camera: a stage re-fit (resize, bounds) must not put
	# the gameplay FOV back under a framed shot.
	stage.camera.fov = _fov
	stage.camera.transform = cam_from.interpolate_with(cam_to, e) if not Settings.g("reduced_motion") else cam_to
	for aid in actors:
		(actors[aid] as ActorRig).tick(dt)
	if not _credits and t >= maxf(dur, min_t) and (Settings.g("reading_auto_advance") or t >= maxf(dur, min_t) + 6.0):
		_next()
	queue_redraw()

func _draw() -> void:
	var f := UiKit.font()
	# Letterbox bars give story a distinct, calm frame.
	draw_rect(Rect2(0, 0, size.x, 34), Color(0.12, 0.14, 0.17, 0.85))
	draw_rect(Rect2(0, size.y - 34, size.x, 34), Color(0.12, 0.14, 0.17, 0.85))
	if _postcard:
		var r := Rect2(Vector2(size.x * 0.12, size.y * 0.1), Vector2(size.x * 0.76, size.y * 0.66))
		draw_style_box(UiKit._box(Color(0, 0, 0, 0), UiKit.PAPER, 14, 6, 0), r)
		draw_style_box(UiKit._box(Color(0, 0, 0, 0), UiKit.CORAL, 3, 4, 0), r.grow(-14))
	if scene.get("title_card", "") != "" and idx == panels.size() - 1 and scene.get("id", "") == "O00":
		pass
	var hint := Loc.t("ui.story.continue") if t >= min_t else ""
	var seat0: int = InputRouter.active_seats()[0] if not InputRouter.active_seats().is_empty() else 0
	if hint != "":
		var g := InputRouter.glyph(seat0, "carry")
		UiKit.draw_glyph(self, Vector2(size.x - 160 - UiKit.glyph_width(g, 22) * 0.5, size.y - 17), g, 22)
		draw_string(f, Vector2(size.x - 150, size.y - 11), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UiKit.CREAM)
	var g2 := InputRouter.glyph(seat0, "step")
	var gw := UiKit.glyph_width(g2, 22)
	UiKit.draw_glyph(self, Vector2(16 + gw * 0.5, size.y - 17), g2, 22)
	draw_string(f, Vector2(24 + gw, size.y - 11), Loc.t("ui.story.skip"), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UiKit.CREAM)
	if skip_prompt:
		var c := Vector2(size.x * 0.5, size.y * 0.5)
		var r2 := Rect2(c - Vector2(200, 46), Vector2(400, 92))
		draw_style_box(UiKit._box(UiKit.PAPER, UiKit.WALNUT, 3, 12, 0), r2)
		UiKit.draw_text_outlined(self, c + Vector2(0, -8), Loc.t("ui.story.skip_q"), 26, UiKit.INK, Color(0, 0, 0, 0))
		UiKit.draw_text_outlined(self, c + Vector2(0, 26), Loc.t("ui.story.skip_how"), 16, Color("#6E655B"), Color(0, 0, 0, 0))
	if _credits:
		_draw_credits_overlay()

func _draw_credits_overlay() -> void:
	var f := UiKit.font()
	var lines := [Loc.t("ui.title.name"), Loc.t("story.E00.thanks"), "", Loc.t("ui.story.ending_options")]
	var y := 90.0
	for l in lines:
		UiKit.draw_text_outlined(self, Vector2(size.x * 0.5, y), l, 30 if y < 100 else 20)
		y += 40
