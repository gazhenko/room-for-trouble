extends SceneTree
## Dev: triangle counts for every procedural model against the §17.4 budgets
## (actors ≤5k, stations ≤3k, props/items ≤1k). Needs a renderer (not --headless).
##   godot --path . --script res://tools/dev/mesh_budget.gd
var _done := false

func _process(_dt: float) -> bool:
	# Autoloads (Content for cosmetics) exist from the first frame on.
	if _done or root.get_node_or_null("Content") == null:
		return _done
	_done = true
	_run()
	return true

func _run() -> void:
	var rows: Array = []
	var cos: Dictionary = root.get_node("Content").cosmetics[0]
	for id in SimC.STAFF_IDS:
		rows.append(["staff", id, _tris(ModelActors.staff(id, cos)), 5000])
	for id in ["nana", "gus", "dot"]:
		rows.append(["host", id, _tris(ModelActors.npc(id)), 5000])
	for fam in SimC.FAMILIES:
		rows.append(["guest", fam, _tris(ModelActors.guest(fam, "")), 5000])
	for kind in ModelStations.KINDS:
		rows.append(["station", kind, _tris(ModelStations.build(kind, {"room_color": Art.ROOM_COLORS["A"], "side": "north"})), 3000])
	for kind in ModelItems.KINDS:
		rows.append(["item", kind, _tris(ModelItems.build(kind)), 1000])
	for kind in ModelProps.KINDS:
		rows.append(["prop", kind, _tris(ModelProps.build(kind)), 1000])
	var over := 0
	var md := "| Kind | Model | Triangles | Budget |\n|---|---|---|---|\n"
	for r in rows:
		var ok: bool = r[2] <= r[3]
		if not ok:
			over += 1
		md += "| %s | %s | %d | %d %s |\n" % [r[0], r[1], r[2], r[3], "✓" if ok else "✗ over"]
	print(md)
	print("MESHBUDGET %d models, %d over budget" % [rows.size(), over])
	quit()

func _tris(n: Node) -> int:
	var t := 0
	for c in n.find_children("*", "MeshInstance3D", true, false):
		var m: Mesh = (c as MeshInstance3D).mesh
		if m == null:
			continue
		for s in m.get_surface_count():
			var arr := m.surface_get_arrays(s)
			var idx = arr[Mesh.ARRAY_INDEX]
			if idx != null and idx.size() > 0:
				t += idx.size() / 3
			else:
				t += (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	n.free()
	return t
