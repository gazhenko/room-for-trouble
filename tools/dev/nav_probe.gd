extends SceneTree
## Dev: checks that the reference bot can path across a floor and that the key
## hall tiles are free for its inflated capsule.
##   godot --headless --path . --script res://tools/dev/nav_probe.gd -- L17
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var lid := args[0] if args.size() > 0 else "L17"
	var reg = load("res://src/content/content_registry.gd").new()
	reg.load_all()
	var sim := HotelSim.new(reg, {"mode": "campaign", "level_id": lid, "humans": 2,
		"seats": [{"seat": 0, "char": "pip"}, {"seat": 1, "char": "pebble"}], "difficulty": "family", "seed": 3, "gus": false})
	sim.start_now()
	for i in 95:
		sim.step([])
	var L := sim.L
	print("layout %s hall %s divider %s shutter %s lifts %s shutter_state=%s" % [L.id, L.hall, L.divider, L.shutter, L.lift_pads, sim.s["shutter"]])
	var bot := ReferenceBot.new(sim)
	var hz := L.hall.position.y + 1
	for x in range(L.hall.position.x, L.hall.end.x):
		var row := ""
		for z in range(L.hall.position.y, L.hall.end.y):
			var c := Vector2i(x * SimC.UM, z * SimC.UM)
			var cell := bot._cell_of(c.x, c.y)
			row += "%s" % ("." if bot._free(cell.x, cell.y) else "#")
		print("  x=%2d  nav rows z%d..%d: %s   wall tile at lane: %s" % [x, L.hall.position.y, L.hall.end.y - 1, row, L.is_wall_tile(x, hz)])
	var a := Vector2i(L.fixtures["staff_starts"][0].x * SimC.UM, L.fixtures["staff_starts"][0].y * SimC.UM)
	for letter in L.active_rooms:
		var d: Vector2i = L.rooms[letter]["door"]
		var b := Vector2i(d.x * SimC.UM, d.y * SimC.UM)
		var pts := bot.path(a, b)
		var dist := 0.0
		var prev := a
		for p in pts:
			dist += Vector2(p - prev).length() / 1e6
			prev = p
		print("  path start -> door %s: %d waypoints, %.1f m, last=%s target=%s" % [letter, pts.size(), dist, str(pts[pts.size() - 1]), str(b)])
	reg.free()
	quit()
