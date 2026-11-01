class_name StoryStaging
extends RefCounted
## Stages a classic-authored story panel on any floor (docs/DESIGN_V2.md §9,
## DECISIONS D48). Scenes were framed on the 28x20 classic floor with actors at
## scale 1.45. On a v2 floor the panel's anchor (the camera's look point, or the
## focus of a relative preset) maps onto the compact hall; the composition
## around it keeps its authored shape scaled by the actor-size ratio, so bigger
## toys keep their spacing; and the camera rig scales about the same ground
## point, which reproduces the v1 framing exactly (similar triangles). Actors
## stay on the hall's free lane rows and the whole group slides sideways to
## stay inside the hall. The two wide presets frame the hotel, not people, so
## they map every position floor-wide instead. The postcard photo set is floor
## independent and simply scales with the toys. Pure geometry: the player and
## the content validator share it.

## Camera presets, in classic coordinates (relative ones hang off the panel's focus).
const CAMERAS := {
	"wide_hotel": {"pos": [13.5, 21.0, 34.0], "look": [13.5, 0.0, 9.0], "fov": 30},
	"lobby_group": {"pos": [6.0, 5.0, 15.5], "look": [5.0, 0.7, 9.4], "fov": 32},
	"desk_close": {"pos": [3.4, 2.5, 12.6], "look": [2.4, 0.9, 9.3], "fov": 30},
	"guest_close": {"pos": [0.0, 2.1, 4.8], "look": [0.0, 0.9, 0.0], "fov": 30, "relative": true},
	"room_door": {"pos": [0.6, 3.0, 5.2], "look": [0.6, 0.9, 0.4], "fov": 30, "relative": true},
	"fixture_close": {"pos": [0.6, 3.2, 5.4], "look": [0.6, 0.8, 0.4], "fov": 30, "relative": true},
	"high_close": {"pos": [-0.8, 6.0, 5.0], "look": [-0.6, 0.5, -0.2], "fov": 30, "relative": true},
	"festival_wide": {"pos": [17.0, 9.0, 20.0], "look": [17.0, 0.6, 9.5], "fov": 34},
	"postcard_still": {"pos": [0.0, 3.2, 6.4], "look": [0.0, 0.8, 0.0], "fov": 28, "relative": true},
}

const AUTHOR_SCALE := 1.45                   # ACTOR_SCALE the scenes were framed at
const WIDE := ["wide_hotel", "festival_wide"]
const PHOTO_ORIGIN := Vector3(200, 0, 200)
const PHOTO_POS := Vector3(0, 1.7, 9.6)
const PHOTO_LOOK := Vector3(0, 0.8, -0.2)
const PHOTO_FOV := 27.0
const LANE_MARGIN := 0.7                     # actors keep this far from the station rows (tile centres)
const PROP_SLACK := 0.2                      # props may sit this much closer to the rows
const HALL_MARGIN := 0.1                     # actor centres stay within hall tile centres ± this
const PARTY_GAP := 0.9                       # authored spacing between party members
## Rig heights before ACTOR_SCALE (ModelActors.setup), for framing checks.
const HEIGHTS := {"nana": 1.05, "gus": 0.5, "dot": 0.75, "slime": 0.7, "yeti": 1.05, "dragon": 0.95,
	"ghost": 0.9, "moonwolf": 1.05, "sprout": 0.95}
const STAFF_H := 0.8
const HEAD_PAD := 0.15                       # hats and ears above the rig height
## Safe frame for heads and faces, as fractions of the frame: inside the
## letterbox bars with air, above the caption band; the postcard keeps them
## inside its printed border.
const SAFE := Rect2(0.05, 0.09, 0.90, 0.75)
const PHOTO_SAFE := Rect2(0.15, 0.14, 0.70, 0.58)
const FIT_MAX := 1.6                         # how far a rig may pull back to fit everyone

static func ratio() -> float:
	return ModelActors.ACTOR_SCALE / AUTHOR_SCALE

## Expands the "staff" actor into the party and returns the staged panel:
##   actors:  [{id, char, pos3: Vector3, face, pose, slippers, mask, ...}]
##   props:   [{kind, pos3: Vector3, rot, scale}]
##   cam_pos, cam_look: Vector3; fov: float; photo: bool; set_scale: float
## A panel may carry a "v2" block with floor-local "actors" and/or "props"
## (tile coordinates of the v2 floor, used as given) for beats whose classic
## dressing has no counterpart on the compact hall.
static func stage(L: LayoutDef, p: Dictionary, cameras: Dictionary, party: Array, aspect := 16.0 / 9.0) -> Dictionary:
	var cam_name: String = p.get("camera", "wide_hotel")
	var preset: Dictionary = cameras.get(cam_name, cameras["wide_hotel"])
	var photo: bool = p.get("set", "") == "photo"
	var rel: bool = preset.get("relative", false)
	var wide: bool = cam_name in WIDE
	var v2: bool = L != null and L.v2
	var native: Dictionary = p.get("v2", {}) if v2 else {}
	var preset_pos := _v3(preset["pos"])
	var preset_look := _v3(preset["look"])
	var acts := _actors(native.get("actors", p.get("actors", [])), party)
	var props := _props(native.get("props", p.get("props", [])))
	var out := {"photo": photo, "fov": float(preset.get("fov", 30)), "set_scale": 1.0}
	if photo:
		var rp := ratio()
		for d in acts:
			d["pos3"] = PHOTO_ORIGIN + (d["pos3"] as Vector3) * rp
		for d in props:
			d["pos3"] = PHOTO_ORIGIN + (d["pos3"] as Vector3) * rp
		var plook := PHOTO_ORIGIN + PHOTO_LOOK * rp
		out["cam_pos"] = _fit_frame(PHOTO_ORIGIN + PHOTO_POS * rp, plook, PHOTO_FOV, aspect, _heads(acts), PHOTO_SAFE)
		out["cam_look"] = plook
		out["fov"] = PHOTO_FOV
		out["set_scale"] = rp
	elif not v2:
		# Classic floors are the authoring frame: everything as written.
		var focus := Vector3.ZERO
		if p.has("focus"):
			focus = Vector3(float(p["focus"][0]), 0.0, float(p["focus"][1]))
		var pos := preset_pos
		var look := preset_look
		if rel:
			pos += focus
			look += focus
		if p.has("cam_pos"):
			pos = _v3(p["cam_pos"])
		if p.has("cam_look"):
			look = _v3(p["cam_look"])
		out["cam_pos"] = pos
		out["cam_look"] = look
	elif wide:
		var lane := _lane(L)
		if not native.has("actors"):
			for d in acts:
				d["pos3"] = _lane_clamp(L.classic_to_local(d["pos3"]), lane, 0.0)
		if not native.has("props"):
			for d in props:
				d["pos3"] = _lane_clamp(L.classic_to_local(d["pos3"]), lane, PROP_SLACK)
		var look := L.classic_to_local(preset_look)
		var k := clampf(float(L.hall.size.x) / 26.0, 0.45, 1.0)
		var pos := look + (preset_pos - preset_look) * k
		if p.has("cam_pos"):
			pos = L.classic_to_local(_v3(p["cam_pos"]))
		if p.has("cam_look"):
			look = L.classic_to_local(_v3(p["cam_look"]))
		pos = _fit_frame(pos, look, float(out["fov"]), aspect, _heads(acts), SAFE)
		out["cam_pos"] = pos
		out["cam_look"] = look
	else:
		# Close and group shots: a similarity transform about the anchor.
		var r := ratio()
		var lane := _lane(L)
		var anchor_c := Vector2(preset_look.x, preset_look.z)
		if p.has("focus"):
			anchor_c = Vector2(float(p["focus"][0]), float(p["focus"][1]))
		elif rel:
			anchor_c = Vector2.ZERO
		var av := L.classic_to_local_xz(anchor_c.x, anchor_c.y)
		av.y = clampf(av.y, lane.x, lane.y)
		var a3c := Vector3(anchor_c.x, 0.0, anchor_c.y)
		var a3v := Vector3(av.x, 0.0, av.y)
		if not native.has("actors"):
			for d in acts:
				d["pos3"] = _lane_clamp(a3v + ((d["pos3"] as Vector3) - a3c) * r, lane, 0.0, true)
		if not native.has("props"):
			for d in props:
				d["pos3"] = _lane_clamp(a3v + ((d["pos3"] as Vector3) - a3c) * r, lane, PROP_SLACK, true)
		# Slide the composition sideways so every actor stands inside the hall.
		var lo := INF
		var hi := -INF
		for d in acts:
			lo = minf(lo, (d["pos3"] as Vector3).x)
			hi = maxf(hi, (d["pos3"] as Vector3).x)
		var hx0 := float(L.hall.position.x) - HALL_MARGIN
		var hx1 := float(L.hall.end.x - 1) + HALL_MARGIN
		var shift := 0.0
		if lo <= hi:
			if hi - lo > hx1 - hx0:
				shift = (hx0 + hx1) * 0.5 - (lo + hi) * 0.5
			elif lo < hx0:
				shift = hx0 - lo
			elif hi > hx1:
				shift = hx1 - hi
		if shift != 0.0:
			for d in acts:
				d["pos3"] = (d["pos3"] as Vector3) + Vector3(shift, 0, 0)
			if not native.has("props"):
				for d in props:
					d["pos3"] = (d["pos3"] as Vector3) + Vector3(shift, 0, 0)
			a3v.x += shift
		var pos: Vector3
		var look: Vector3
		if rel:
			pos = a3v + preset_pos * r
			look = a3v + preset_look * r
		else:
			look = Vector3(a3v.x, preset_look.y * r, a3v.z)
			pos = look + (preset_pos - preset_look) * r
		if p.has("cam_pos"):
			pos = a3v + (_v3(p["cam_pos"]) - a3c) * r
		if p.has("cam_look"):
			look = a3v + (_v3(p["cam_look"]) - a3c) * r
		pos = _fit_frame(pos, look, float(out["fov"]), aspect, _heads(acts), SAFE)
		out["cam_pos"] = pos
		out["cam_look"] = look
		out["shift"] = shift
	out["actors"] = acts
	out["props"] = props
	return out

## Free lane rows of a v2 hall as [lo, hi] z (tile centres minus the margin):
## the one middle row on three-row halls, the two middle rows on the split lobby.
static func _lane(L: LayoutDef) -> Vector2:
	return Vector2(float(L.hall.position.y) + LANE_MARGIN, float(L.hall.end.y - 1) - LANE_MARGIN)

## Keeps a point on the hall's rows out of the station rows. Close and group
## shots clamp always (their cast is in the hall by authoring); wide shots only
## clamp points that land on the hall, leaving the porch and the rooms alone.
static func _lane_clamp(q: Vector3, lane: Vector2, slack: float, force := false) -> Vector3:
	if force or (q.z > lane.x - LANE_MARGIN - 0.5 and q.z < lane.y + LANE_MARGIN + 0.5):
		q.z = clampf(q.z, lane.x - slack, lane.y + slack)
	return q

static func _actors(list: Array, party: Array) -> Array:
	var acts: Array = []
	for a in list:
		if a["id"] == "staff":
			var base: Array = a.get("pos", [5, 9.6])
			var n := maxi(1, party.size())
			for i in n:
				var sub: Dictionary = a.duplicate()
				sub["id"] = "staff%d" % i
				sub["char"] = party[i] if i < party.size() else "pip"
				sub["pos3"] = Vector3(float(base[0]) + i * PARTY_GAP - (n - 1) * PARTY_GAP * 0.5, float(a.get("y", 0.0)), float(base[1]))
				acts.append(sub)
			continue
		var d: Dictionary = a.duplicate()
		var pos: Array = a.get("pos", [5, 9.5])
		d["char"] = ""
		d["pos3"] = Vector3(float(pos[0]), float(a.get("y", 0.0)), float(pos[1]))
		acts.append(d)
	return acts

static func _props(list: Array) -> Array:
	var props: Array = []
	for pr in list:
		var d: Dictionary = pr.duplicate()
		var pp: Array = pr.get("pos", [0, 0, 0])
		d["pos3"] = Vector3(float(pp[0]), float(pp[1]), float(pp[2]))
		props.append(d)
	return props

static func _v3(a: Array) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))

## Guest family of a story actor id ("mallow" -> "slime", "guest:yeti" -> "yeti").
static func family_of(aid: String) -> String:
	match aid:
		"mallow": return "slime"
		"flurry": return "yeti"
		"cinder": return "dragon"
		"whisp": return "ghost"
		"luna": return "moonwolf"
		"fern": return "sprout"
	if aid.begins_with("guest:"):
		return aid.split(":")[1]
	return "slime"

## Rig height (before ACTOR_SCALE) of a staged actor.
static func actor_height(a: Dictionary) -> float:
	if a.get("char", "") != "":
		return STAFF_H
	var aid: String = a["id"]
	if HEIGHTS.has(aid):
		return HEIGHTS[aid]
	return float(HEIGHTS.get(family_of(aid), 0.9))

## Head tops and faces of the staged actors, the points a shot must keep in frame.
static func _heads(acts: Array) -> Array:
	var pts: Array = []
	for a in acts:
		var h := actor_height(a) * ModelActors.ACTOR_SCALE
		var base: Vector3 = a["pos3"]
		pts.append(base + Vector3(0, h + HEAD_PAD, 0))
		pts.append(base + Vector3(0, h * 0.78, 0))
	return pts

## Pulls the camera back along its own axis (never closer, at most FIT_MAX
## times the authored distance) until every point projects inside `safe`.
static func _fit_frame(pos: Vector3, look: Vector3, fov: float, aspect: float, pts: Array, safe: Rect2) -> Vector3:
	if pts.is_empty():
		return pos
	var off := pos - look
	var f := 1.0
	while f < FIT_MAX and not _inside(look + off * f, look, fov, aspect, pts, safe):
		f += 0.05
	return look + off * f

static func _inside(pos: Vector3, look: Vector3, fov: float, aspect: float, pts: Array, safe: Rect2) -> bool:
	var inv := Transform3D(Basis(), pos).looking_at(look, Vector3.UP).affine_inverse()
	var t := tan(deg_to_rad(fov) * 0.5)
	for p in pts:
		var c: Vector3 = inv * (p as Vector3)       # camera space, -z forward
		if c.z >= -0.05:
			return false
		var fx := (c.x / (-c.z * t * aspect) + 1.0) * 0.5
		var fy := (1.0 - c.y / (-c.z * t)) * 0.5
		if fx < safe.position.x or fx > safe.end.x or fy < safe.position.y or fy > safe.end.y:
			return false
	return true
