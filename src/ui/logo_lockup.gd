class_name LogoLockup
extends RefCounted
## The title lockup (§2 front end): a luggage label on a brass eyelet, the
## wordmark in two bands (ROOM FOR on a walnut strip, TROUBLE big in coral with
## a pixel shadow), six family pennants as the bunting along its bottom edge,
## the bell, and an edition tag. Everything is drawn with the UI kit, so it
## matches the pixel font, the icon palette variants and high contrast. One
## call draws it at any scale: the title at 1.0, the menu cards at about 0.5.

const W := 640.0
const H := 190.0
const FAMS := ["slime", "yeti", "dragon", "ghost", "moonwolf", "sprout"]

static func draw(ci: CanvasItem, center: Vector2, scale: float, t: float, edition := true) -> void:
	var f := UiKit.font()
	var hc: bool = Settings.g("high_contrast")
	var ink := Color.BLACK if hc else UiKit.INK
	var tilt := 0.0 if Settings.g("reduced_motion") else sin(t * 0.8) * 0.012
	ci.draw_set_transform(center, tilt, Vector2(scale, scale))
	var r := Rect2(Vector2(-W * 0.5, -H * 0.5), Vector2(W, H))
	# Label body: pixel shadow, cream card, coral inner frame.
	ci.draw_rect(Rect2(r.position + Vector2(8, 12), r.size), UiKit.SHADOW)
	ci.draw_style_box(UiKit._box(UiKit.PAPER, ink if hc else UiKit.WALNUT, 6, 20, 0), r)
	ci.draw_style_box(UiKit._box(Color(0, 0, 0, 0), UiKit.CORAL, 3, 14, 0), r.grow(-12))
	# Brass eyelet with its string loop.
	var ex := -W * 0.5 + 42
	ci.draw_circle(Vector2(ex, 0), 17, UiKit.WALNUT)
	ci.draw_circle(Vector2(ex, 0), 11, Art.BRASS)
	ci.draw_circle(Vector2(ex, 0), 5, UiKit.CREAM)
	ci.draw_arc(Vector2(ex - 28, -10), 24, PI * 0.15, PI * 1.55, 18, UiKit.WALNUT, 3.0)
	# Band one: ROOM FOR, cream on walnut.
	var band := Rect2(Vector2(-W * 0.5 + 86, -H * 0.5 + 24), Vector2(W - 124, 40))
	ci.draw_style_box(UiKit._box(UiKit.WALNUT, UiKit.WALNUT.darkened(0.35), 2, 6, 0), band)
	var top := Loc.t("ui.title.top")
	var tw := f.get_string_size(top, HORIZONTAL_ALIGNMENT_LEFT, -1, 28).x
	ci.draw_string(f, Vector2(band.get_center().x - tw * 0.5, band.position.y + 30), top, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, UiKit.CREAM)
	# Band two: TROUBLE, coral with a pixel drop shadow and an ink outline.
	var main := Loc.t("ui.title.main")
	var mw := f.get_string_size(main, HORIZONTAL_ALIGNMENT_LEFT, -1, 86).x
	var mp := Vector2(band.get_center().x - mw * 0.5, 64)
	ci.draw_string(f, mp + Vector2(6, 6), main, HORIZONTAL_ALIGNMENT_LEFT, -1, 86, UiKit.WALNUT.darkened(0.25))
	ci.draw_string_outline(f, mp, main, HORIZONTAL_ALIGNMENT_LEFT, -1, 86, 8, ink)
	ci.draw_string(f, mp, main, HORIZONTAL_ALIGNMENT_LEFT, -1, 86, UiKit.CORAL.darkened(0.45) if hc else UiKit.CORAL)
	# Bunting along the bottom edge: one pennant per guest family.
	for i in FAMS.size():
		var px := band.position.x + 34 + i * ((band.size.x - 68) / float(FAMS.size() - 1))
		var col: Color = Art.FAMILY_COLORS[FAMS[i]]
		var tri := PackedVector2Array([Vector2(px - 13, H * 0.5 - 3), Vector2(px + 13, H * 0.5 - 3), Vector2(px, H * 0.5 + 17)])
		ci.draw_colored_polygon(tri, col)
		ci.draw_polyline(PackedVector2Array([tri[0], tri[2], tri[1]]), ink, 2.0)
	UiKit.draw_icon(ci, "sys_bell", Vector2(W * 0.5 - 54, -H * 0.5 + 46), 36)
	if edition:
		var ed := Loc.t("ui.title.edition")
		var ew := f.get_string_size(ed, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
		var er := Rect2(Vector2(W * 0.5 - ew - 48, H * 0.5 - 44), Vector2(ew + 26, 30))
		ci.draw_style_box(UiKit._box(Art.GOLD, ink if hc else UiKit.WALNUT, 2, 6, 0), er)
		ci.draw_string(f, er.position + Vector2(13, 21), ed, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, ink)
	ci.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

## A header control for menu cards: the lockup at `scale`, sized to fit.
static func header(scale := 0.5) -> Control:
	var h := Header.new()
	h.s = scale
	h.custom_minimum_size = Vector2(W * scale + 24, (H + 30) * scale + 8)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return h

class Header extends Control:
	var s := 0.5
	var t := 0.0
	func _process(dt: float) -> void:
		if not Settings.g("reduced_motion"):
			t += dt
			queue_redraw()
	func _draw() -> void:
		LogoLockup.draw(self, Vector2(size.x * 0.5, size.y * 0.5 - 6 * s), s, t, false)
