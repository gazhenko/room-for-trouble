class_name HubOverlay
extends Control
## Labels hub hotspots in the world and shows the menu hint.

var hub: HubScreen
var _t := 0.0

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(dt: float) -> void:
	_t += dt
	queue_redraw()

func _draw() -> void:
	if hub == null or hub.sim == null:
		return
	var f := UiKit.font()
	var near := {}
	for st in hub.sim.s["staff"]:
		var h := hub.near_hotspot(st)
		if not h.is_empty():
			near[h["id"]] = st["seat"]
	for h in HubScreen.HOTSPOTS:
		var p := hub.hotspot_pos(h)
		var sp := hub.view.stage.world_to_screen(Vector3(float(p.x) / 1e6, 1.7, float(p.y) / 1e6)) / hub.hud.ui_scale
		var on := near.has(h["id"])
		var bob := 0.0 if Settings.g("reduced_motion") else sin(_t * 2.4 + p.x) * 3.0
		var txt := Loc.t(h["label"])
		var tw := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		var r := Rect2(sp + Vector2(-tw * 0.5 - 22, -16 + bob), Vector2(tw + 44, 30))
		draw_style_box(UiKit._box(Color("#FFF1C9") if on else UiKit.PAPER, UiKit.GOLD.darkened(0.3) if on else UiKit.WALNUT, 2, 8, 0), r)
		UiKit.draw_icon(self, h["icon"], r.position + Vector2(14, 15), 18)
		draw_string(f, r.position + Vector2(26, 21), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UiKit.INK)
		if on:
			var rs: int = hub.sim_to_router.get(near[h["id"]], 0)
			UiKit.draw_glyph(self, r.position + Vector2(r.size.x + 16, 15), InputRouter.glyph(rs, "carry"), 22)
	var seat0: int = InputRouter.active_seats()[0] if not InputRouter.active_seats().is_empty() else 0
	var hint := Loc.t("ui.hub.menu_hint")
	var g := InputRouter.glyph(seat0, "pause")
	var w := f.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x + 60
	var hr := Rect2(Vector2(16, 16), Vector2(w, 34))
	draw_style_box(UiKit._box(UiKit.PAPER, UiKit.WALNUT, 2, 8, 0), hr)
	UiKit.draw_glyph(self, hr.position + Vector2(20, 17), g, 24)
	draw_string(f, hr.position + Vector2(40, 24), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, UiKit.INK)
