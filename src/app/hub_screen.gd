class_name HubScreen
extends ShiftScreen
## Walkable, non-scored hub (§16.1) using the same controls and party. Hotspots
## open the start-shift desk, wardrobe, settings bell, guest guide, postcard
## board and practice door. Every function is also in the conventional menu.

const HOTSPOTS := [
	{"id": "start", "fixture": "reception", "icon": "ui_play", "label": "ui.hub.start"},
	{"id": "wardrobe", "fixture": "welcome_kiosk", "icon": "badge_first_hello", "label": "ui.hub.wardrobe"},
	{"id": "settings", "fixture": "group_bell", "icon": "ui_settings", "label": "ui.hub.settings"},
	{"id": "guide", "fixture": "return_shelf", "icon": "ui_scrapbook", "label": "ui.hub.guide"},
	{"id": "board", "fixture": "heat_pump", "icon": "sys_postcard", "label": "ui.hub.board"},
	{"id": "practice", "room_door": "A", "icon": "sys_coach", "label": "ui.hub.practice"},
]

var overlay: HubOverlay
var towel_home := Vector2i.ZERO
var _menu_open := false

func setup_hub(p_stage: PixelStage, p_captions: Captions, p_cfg: Dictionary) -> void:
	setup(p_stage, p_captions, p_cfg)
	sim.force_active()
	var b: Vector2i = sim.L.fixtures["group_bell"]
	towel_home = Vector2i(b.x * SimC.UM + 900_000, b.y * SimC.UM)
	sim.new_item("towel", {"loc": "world", "x": towel_home.x, "z": towel_home.y, "practice": true})
	overlay = HubOverlay.new()
	overlay.hub = self
	add_child(overlay)
	hud.level = {"duration_hotel_s": 0}
	hud.show_clock = false
	Audio.play_music("title_loop")
	captions.push("nana", Loc.t("ui.hub.welcome"), "story", 4.0)
	_decorate_hub()

func _decorate_hub() -> void:
	# Unlocked cosmetic-set decorations dress the lobby.
	var spots := [Vector3(1.2, 0, 11.6), Vector3(26.0, 0, 8.3), Vector3(20.5, 0, 11.6), Vector3(6.0, 0, 11.6),
		Vector3(9.8, 0, 8.25), Vector3(16.8, 0, 8.25), Vector3(23.5, 0, 8.25), Vector3(26.0, 0, 11.6)]
	var i := 0
	for cs in Content.cosmetics:
		if cs.get("decor", "") == "" or not cs["id"] in SaveService.profile["unlocked_cosmetic_sets"]:
			continue
		if i >= spots.size():
			break
		var prop := ModelProps.build(cs["decor"])
		prop.position = spots[i]
		view.add_child(prop)
		i += 1

func hotspot_pos(h: Dictionary) -> Vector2i:
	if h.has("fixture"):
		var p: Vector2i = sim.L.fixtures[h["fixture"]]
		return Vector2i(p.x * SimC.UM, p.y * SimC.UM)
	var d: Vector2i = sim.L.rooms[h["room_door"]]["door"]
	return Vector2i(d.x * SimC.UM, d.y * SimC.UM)

func near_hotspot(st: Dictionary) -> Dictionary:
	var best := {}
	var bd := 1_400_000
	for h in HOTSPOTS:
		var p := hotspot_pos(h)
		var d := SimMove.dist(st["x"], st["z"], p.x, p.y)
		if d < bd:
			bd = d
			best = h
	return best

func _tick() -> void:
	if _menu_open:
		return
	var frames := InputRouter.build_frames(router_to_sim)
	for f in frames:
		var st := sim.staff_by_seat(int(f["seat"]))
		if st.is_empty():
			continue
		var h := near_hotspot(st)
		if not h.is_empty() and (int(f["pressed"]) & (SimC.BTN_CARRY | SimC.BTN_WORK)) != 0 and int(st["held"]) == 0:
			f["pressed"] = int(f["pressed"]) & ~(SimC.BTN_CARRY | SimC.BTN_WORK)
			_open_hotspot(h["id"])
	sim.step(frames)
	# Practice towel wanders home on its own.
	for iid in sim.s["items"]:
		var it: Dictionary = sim.s["items"][iid]
		if it.get("practice", false) and it["loc"] == "world" and int(it["idle"]) > 240:
			it["x"] = towel_home.x; it["z"] = towel_home.y; it["idle"] = 0
	view.capture_tick(sim.s)
	_decorate_state(sim.s)
	sim.s["_jobs"] = []
	hud.feed(sim.s, sim.events)
	view.on_events(sim.events)
	_feedback(sim.events)

func _open_hotspot(id: String) -> void:
	Audio.ui("ui_confirm")
	match id:
		"start": _menu(func(): Session.open_shift_select())
		"wardrobe": _menu(func(): Session.open_wardrobe())
		"settings": _menu(func(): Session.open_settings())
		"guide": _menu(func(): Session.open_scrapbook())
		"board": _menu(func(): Session.open_scrapbook())
		"practice": _menu(func(): Session.open_practice())

func _menu(open: Callable) -> void:
	_menu_open = true
	paused = true
	InputRouter.gameplay = false
	open.call()

func _process(dt: float) -> void:
	if _menu_open and Session.screen == self:
		_menu_open = false
		paused = false
		InputRouter.gameplay = true
		InputRouter.clear_edges()
	super._process(dt)

func open_pause(router_seat := 0) -> void:
	# The hub's pause button opens the conventional hub menu.
	_menu(func(): Session.push(HubMenu.new()))

func _finish() -> void:
	pass
