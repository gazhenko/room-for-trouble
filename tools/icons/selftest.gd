extends SceneTree
## Headless check for the runtime icon loader (src/ui/icons.gd).
##   godot --headless --path . --script res://tools/icons/selftest.gd
## Verifies the sources parse cleanly, every icon builds in every palette
## variant with a sane size, 9-slice sources exist, aliases resolve, and a
## missing name yields the visible fallback tile instead of failing.


func _init() -> void:
	var fails := PackedStringArray()
	var names := Icons.names()
	if names.is_empty():
		fails.append("no icons loaded")
	for e in Icons.errors():
		fails.append("parse: " + e)
	for n in names:
		var sz := Icons.size_of(n)
		if sz.x < 8 or sz.y < 8 or sz.x > 64 or sz.y > 64:
			fails.append("%s: odd size %s" % [n, sz])
		for v in Icons.VARIANTS:
			var t := Icons.tinted(n, v)
			if t == null or t.get_width() != sz.x or t.get_height() != sz.y:
				fails.append("%s/%s: bad texture" % [n, v])
	for p in Icons.NINE_SLICE:
		if not Icons.has(String(p)):
			fails.append("nine-slice source missing: " + String(p))
	for a in Icons.ALIASES:
		if not Icons.has(String(a)):
			fails.append("alias target missing: %s -> %s" % [a, Icons.ALIASES[a]])
	var fb := Icons.tex("__definitely_missing__")
	if fb == null or fb.get_width() != 16:
		fails.append("fallback tile missing")
	if Icons.has("__definitely_missing__"):
		fails.append("has() true for a missing icon")
	var unknown_variant := Icons.tinted("sys_warm", "no_such_variant")
	if unknown_variant == null:
		fails.append("unknown variant returned null")
	if Icons.has("sys_warm") and Icons.has("sys_cold"):
		var a := Icons.image("sys_warm", "default")
		var b := Icons.image("sys_warm", "deuteranopia")
		if a.get_data() == b.get_data():
			fails.append("deuteranopia variant did not remap sys_warm")
	var sb := Icons.style_box("panel_cream")
	if sb.texture_margin_left != 8.0:
		fails.append("style_box margin")
	print("Icons selftest: %d icons, %d variants" % [names.size(), Icons.VARIANTS.size()])
	for f in fails:
		printerr("FAIL ", f)
	print("OK" if fails.is_empty() else "%d failure(s)" % fails.size())
	quit(0 if fails.is_empty() else 1)
