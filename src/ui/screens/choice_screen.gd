class_name ChoiceScreen
extends Screen
## A titled card with a short message and equal-weight choices.

func setup(title_text: String, body: String, choices: Array, icon_name := "") -> void:
	var v := card(title_text, 600, icon_name)
	if body != "":
		var l := UiKit.label(body, 22, UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER)
		l.custom_minimum_size = Vector2(540, 0)
		v.add_child(l)
	for c in choices:
		add_button(v, c[0], c[1], c[2])
	if choices.size() > 0:
		on_back(choices[choices.size() - 1][2])
