class_name UiKit
extends RefCounted
## Shared UI building blocks: theme, fonts, panels, focusable buttons, glyph
## badges and icon helpers. Text uses a high-contrast ink/cream pair (§17.1).

const INK := Color("#2B3A42")
const CREAM := Color("#F7EAD6")
const PAPER := Color("#FFF8EC")
const WALNUT := Color("#805C49")
const CORAL := Color("#E88D79")
const GOLD := Color("#E8BF66")
const SAGE := Color("#8BAE91")
const SKY := Color("#8EBBC7")
const PLUM := Color("#8C7CA8")
const SHADOW := Color(0.13, 0.16, 0.2, 0.55)

static var _font: FontFile
static var _font_readable: FontFile
static var _theme: Theme
static var _theme_key := ""

static func font() -> Font:
	if Settings.g("readable_font"):
		return readable_font()
	if _font == null:
		_font = FontFile.new()
		_font.load_dynamic_font("res://assets/export/fonts/PixelifySans.ttf")
		_font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
		_font.hinting = TextServer.HINTING_NONE
		_font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
		_font.fallbacks = [readable_font()]
	return _font

static func readable_font() -> Font:
	if _font_readable == null:
		_font_readable = FontFile.new()
		_font_readable.load_dynamic_font("res://assets/export/fonts/Nunito.ttf")
		_font_readable.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	return _font_readable

static func _box(bg: Color, border: Color, bw := 3, radius := 6, pad := 10) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(radius)
	sb.anti_aliasing = false
	sb.content_margin_left = pad
	sb.content_margin_right = pad
	sb.content_margin_top = pad * 0.6
	sb.content_margin_bottom = pad * 0.6
	sb.shadow_color = SHADOW
	sb.shadow_size = 0
	sb.shadow_offset = Vector2(0, 4)
	return sb

static func theme() -> Theme:
	var key := "%s_%s" % [Settings.g("readable_font"), Settings.g("high_contrast")]
	if _theme != null and _theme_key == key:
		return _theme
	_theme_key = key
	var t := Theme.new()
	var hc: bool = Settings.g("high_contrast")
	var f := font()
	t.default_font = f
	t.default_font_size = 22
	var ink := Color.BLACK if hc else INK
	var btn := _box(PAPER, WALNUT, 3, 7, 14)
	btn.shadow_size = 1
	var btn_focus := _box(Color("#FFF1C9"), GOLD.darkened(0.25) if not hc else Color.BLACK, 4, 7, 14)
	btn_focus.shadow_size = 2
	var btn_press := _box(Color("#F3DDB6"), WALNUT, 3, 7, 14)
	var btn_dis := _box(Color("#E9E1D3"), Color("#B9AA98"), 3, 7, 14)
	for cls in ["Button", "OptionButton", "CheckBox", "CheckButton"]:
		t.set_stylebox("normal", cls, btn)
		t.set_stylebox("hover", cls, btn_focus)
		t.set_stylebox("focus", cls, btn_focus)
		t.set_stylebox("pressed", cls, btn_press)
		t.set_stylebox("hover_pressed", cls, btn_focus)
		t.set_stylebox("disabled", cls, btn_dis)
		t.set_color("font_color", cls, ink)
		t.set_color("font_hover_color", cls, ink)
		t.set_color("font_focus_color", cls, ink)
		t.set_color("font_pressed_color", cls, ink)
		t.set_color("font_disabled_color", cls, Color("#8D8378"))
		t.set_font_size("font_size", cls, 22)
	t.set_stylebox("panel", "PanelContainer", _box(CREAM, WALNUT, 4, 10, 16))
	t.set_stylebox("panel", "Panel", _box(CREAM, WALNUT, 4, 10, 16))
	t.set_color("font_color", "Label", ink)
	t.set_font_size("font_size", "Label", 22)
	t.set_color("font_outline_color", "Label", CREAM)
	t.set_stylebox("normal", "LineEdit", _box(PAPER, WALNUT, 3, 5, 10))
	t.set_stylebox("focus", "LineEdit", _box(Color("#FFF1C9"), GOLD.darkened(0.25), 4, 5, 10))
	t.set_color("font_color", "LineEdit", ink)
	t.set_stylebox("slider", "HSlider", _box(Color("#E2D2BA"), WALNUT, 2, 4, 4))
	t.set_stylebox("grabber_area", "HSlider", _box(CORAL, WALNUT, 2, 4, 4))
	t.set_stylebox("grabber_area_highlight", "HSlider", _box(GOLD, WALNUT, 2, 4, 4))
	t.set_stylebox("panel", "TooltipPanel", _box(INK, CREAM, 2, 4, 8))
	t.set_color("font_color", "TooltipLabel", CREAM)
	t.set_stylebox("scroll", "VScrollBar", _box(Color("#E2D2BA"), Color("#E2D2BA"), 0, 4, 2))
	t.set_stylebox("grabber", "VScrollBar", _box(WALNUT, WALNUT, 0, 4, 2))
	t.set_stylebox("grabber_highlight", "VScrollBar", _box(CORAL, CORAL, 0, 4, 2))
	_theme = t
	return t

static func panel_style(kind := "cream") -> StyleBoxFlat:
	match kind:
		"ink": return _box(Color("#2E3A44EE"), CREAM, 3, 8, 12)
		"card": return _box(PAPER, WALNUT, 3, 8, 10)
		"warn": return _box(Color("#FFF1C9"), CORAL, 3, 8, 10)
		"clear": return _box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0, 0)
	return _box(CREAM, WALNUT, 4, 10, 16)

static func label(text: String, size := 22, color := INK, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	# Wrap only paragraphs; short labels inside rows must keep their width.
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if text.length() > 48 else TextServer.AUTOWRAP_OFF
	return l

static func title(text: String, size := 40) -> Label:
	var l := label(text, size, INK, HORIZONTAL_ALIGNMENT_CENTER)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.add_theme_color_override("font_outline_color", CREAM)
	l.add_theme_constant_override("outline_size", 8)
	return l

static func button(text: String, icon_name := "", min_w := 320) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_w, 52)
	b.focus_mode = Control.FOCUS_ALL
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT if icon_name != "" else HORIZONTAL_ALIGNMENT_CENTER
	if icon_name != "" and Icons.has(icon_name):
		b.icon = Icons.tex(icon_name)
		b.expand_icon = false
		b.add_theme_constant_override("icon_max_width", 32)
		b.add_theme_constant_override("h_separation", 14)
	b.focus_entered.connect(func(): Audio.ui("ui_move"))
	b.pressed.connect(func(): Audio.ui("ui_confirm"))
	return b

static func icon(name: String, px := 32) -> TextureRect:
	var tr := TextureRect.new()
	tr.texture = Icons.tex(name)
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.custom_minimum_size = Vector2(px, px)
	return tr

static func vbox(sep := 10) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v

static func hbox(sep := 10) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h

static func panel(kind := "cream") -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", panel_style(kind))
	return p

static func center(c: Control) -> CenterContainer:
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cc.add_child(c)
	return cc

## Draws a controller/keyboard glyph badge (shape + label; never colour only).
static func draw_glyph(ci: CanvasItem, pos: Vector2, g: Dictionary, h := 26.0) -> float:
	var txt: String = g.get("text", "?")
	var f := font()
	var fs := int(h * 0.62)
	var tw := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var w := maxf(h, tw + h * 0.5)
	var shape: String = g.get("shape", "key")
	var col: Color = g.get("color", PAPER)
	var r := Rect2(pos - Vector2(w * 0.5, h * 0.5), Vector2(w, h))
	if shape == "round" and w <= h + 1:
		ci.draw_circle(pos + Vector2(0, 2), h * 0.5, SHADOW)
		ci.draw_circle(pos, h * 0.5, INK)
		ci.draw_circle(pos, h * 0.5 - 2.0, col)
	else:
		var sb := _box(col if shape != "key" else PAPER, INK, 2, 4 if shape == "key" else int(h * 0.5), 0)
		ci.draw_style_box(sb, r)
	var tc := INK
	ci.draw_string(f, Vector2(pos.x - tw * 0.5, pos.y + fs * 0.36), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, tc)
	return w

static func glyph_width(g: Dictionary, h := 26.0) -> float:
	var f := font()
	var tw := f.get_string_size(g.get("text", "?"), HORIZONTAL_ALIGNMENT_LEFT, -1, int(h * 0.62)).x
	return maxf(h, tw + h * 0.5)

static func draw_text_outlined(ci: CanvasItem, pos: Vector2, text: String, size: int, col := INK, outline := CREAM, align := HORIZONTAL_ALIGNMENT_CENTER, width := -1.0) -> void:
	var f := font()
	var p := pos
	if align == HORIZONTAL_ALIGNMENT_CENTER and width < 0:
		p.x -= f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x * 0.5
	ci.draw_string_outline(f, p, text, align if width > 0 else HORIZONTAL_ALIGNMENT_LEFT, width, size, 6, outline)
	ci.draw_string(f, p, text, align if width > 0 else HORIZONTAL_ALIGNMENT_LEFT, width, size, col)

static func draw_icon(ci: CanvasItem, name: String, center_pos: Vector2, px: float, modulate := Color.WHITE) -> void:
	var tex := Icons.tex(name)
	if tex == null:
		return
	ci.draw_texture_rect(tex, Rect2(center_pos - Vector2(px, px) * 0.5, Vector2(px, px)), false, modulate)

static func draw_ring(ci: CanvasItem, c: Vector2, r: float, frac: float, col: Color, w := 4.0, bg := Color(0.17, 0.22, 0.26, 0.55)) -> void:
	ci.draw_arc(c, r, 0, TAU, 28, bg, w + 2.0)
	if frac > 0.0:
		ci.draw_arc(c, r, -PI * 0.5, -PI * 0.5 + TAU * clampf(frac, 0.0, 1.0), 28, col, w)

static func draw_bubble(ci: CanvasItem, c: Vector2, r: float, fill := PAPER, border := INK) -> void:
	ci.draw_circle(c + Vector2(0, 2), r + 2, SHADOW)
	ci.draw_circle(c, r + 2, border)
	ci.draw_circle(c, r, fill)
