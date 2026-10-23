class_name Toast
extends Control
## Small non-blocking notification card (unlocks, saves, recoveries).

var text := ""
var icon_name := ""
var t := 0.0
const LIFE := 3.2

func setup(p_text: String, p_icon: String) -> void:
	text = p_text
	icon_name = p_icon
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(dt: float) -> void:
	t += dt
	if t > LIFE:
		queue_free()
	queue_redraw()

func _draw() -> void:
	var f := UiKit.font()
	var idx := 0
	for c in get_parent().get_children():
		if c == self:
			break
		if c is Toast:
			idx += 1
	var tw := minf(f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x, 520.0)
	var slide := clampf(t / 0.25, 0.0, 1.0) * clampf((LIFE - t) / 0.25, 0.0, 1.0)
	var w := tw + 70
	var r := Rect2(Vector2(size.x - w - 20 + (1.0 - slide) * (w + 30), size.y - 140 - idx * 58), Vector2(w, 48))
	draw_rect(Rect2(r.position + Vector2(0, 4), r.size), UiKit.SHADOW)
	draw_style_box(UiKit._box(UiKit.PAPER, UiKit.GOLD.darkened(0.3), 3, 10, 0), r)
	UiKit.draw_icon(self, icon_name, r.position + Vector2(26, 24), 28)
	draw_string(f, r.position + Vector2(48, 31), text, HORIZONTAL_ALIGNMENT_LEFT, tw + 4, 20, UiKit.INK)
