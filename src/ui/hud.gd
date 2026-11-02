class_name Hud
extends Control
## In-shift HUD (§11.1). Immediate-mode drawing over the pixel stage:
## world-anchored plaques, tickets, guest needs, prompts and rings; top clock,
## incoming cards, ribbon objective and warnings; bottom staff portraits.

const SEAT_COLORS := HotelView.SEAT_COLORS
const VERBS_CARRY := {"pick": "pick", "ped": "take_ticket", "bench": "take_ticket", "retped": "put_back",
	"curtain_off": "take_curtain", "dock": "tool", "lift": "lift_load", "handle": "grab", "guest": "deliver",
	"staff": "hand_over"}
const ITEM_ICON := {"ticket": "item_ticket", "move_ticket": "item_move_ticket", "linen_clean": "item_linen_clean",
	"linen_dirty": "item_linen_dirty", "towel": "item_towel", "snack": "item_snack", "welcome_slime": "gift_slime",
	"welcome_yeti": "gift_yeti", "welcome_dragon": "gift_dragon", "welcome_ghost": "gift_ghost",
	"welcome_moonwolf": "gift_moonwolf", "welcome_sprout": "gift_sprout", "curtain_roll": "item_curtain",
	"mop": "tool_mop", "watering_can": "tool_can", "breezer": "tool_breezer", "festival_trunk": "item_trunk",
	"festival_parcel": "item_parcel", "water": "tool_can"}

var view: HotelView
var s: Dictionary = {}
var level: Dictionary = {}
var local_seats: Array = []          # sim seat ids controlled here
var seat_device: Dictionary = {}     # sim seat -> router seat (for glyphs)
var ui_scale := 1.0
var bubbles: Array = []              # transient text bubbles [{seat, text, icon, t}]
var floats: Array = []               # rising "+N" tip texts [{text, pos, t, col}]
var done_cards: Array = []           # order cards sliding out [{gid, outcome, t}]
var notices: Array = []              # top-right notices [{icon, text, t, prio}]
var banner := {}                     # {text, sub, t, icon}
var coach := {}
var tutorial := {}
var hint_level := 0
var connection := {}                 # sim seat -> "good"/"poor"/"lost"
var families: Array = []
var _t := 0.0
var _font: Font
var palette := "default"
var show_clock := true

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = UiKit.font()
	palette = Settings.g("palette")

func feed(state: Dictionary, events: Array) -> void:
	s = state
	for e in events:
		_on_event(e)

func _process(dt: float) -> void:
	_t += dt
	for b in bubbles:
		b["t"] -= dt
	bubbles = bubbles.filter(func(b): return b["t"] > 0.0)
	for n in notices:
		n["t"] -= dt
	notices = notices.filter(func(n): return n["t"] > 0.0)
	for f in floats:
		f["t"] -= dt
	floats = floats.filter(func(f): return f["t"] > 0.0)
	for c in done_cards:
		c["t"] -= dt
	done_cards = done_cards.filter(func(c): return c["t"] > 0.0)
	if banner.has("t") and float(banner["t"]) < 900.0:
		banner["t"] = float(banner["t"]) - dt
		if banner["t"] <= 0.0:
			banner = {}
	queue_redraw()

func _w2s(p: Vector3) -> Vector2:
	return view.stage.world_to_screen(p) / ui_scale

func _ic(name: String) -> String:
	return name

func say(seat: int, text: String, icon := "", secs := 1.6) -> void:
	for b in bubbles:
		if b["seat"] == seat:
			b["text"] = text; b["icon"] = icon; b["t"] = secs
			return
	bubbles.append({"seat": seat, "text": text, "icon": icon, "t": secs})

func notice(icon: String, text: String, secs := 4.0, prio := 1) -> void:
	notices.append({"icon": icon, "text": text, "t": secs, "prio": prio})
	notices.sort_custom(func(a, b): return a["prio"] > b["prio"])
	while notices.size() > 2:
		notices.pop_back()

func show_banner(text: String, sub := "", secs := 2.5, icon := "") -> void:
	banner = {"text": text, "sub": sub, "t": secs, "icon": icon}

func _on_event(e: Dictionary) -> void:
	match e["type"]:
		"invalid":
			var why: String = e.get("why", "")
			if why != "" and local_seats.has(int(e.get("seat", -1))):
				say(int(e["seat"]), Loc.t(why), _reason_icon(why))
		"hint_work":
			if local_seats.has(int(e.get("seat", -1))):
				say(int(e["seat"]), Loc.t("ui.hint.use_work"), "sys_arrow", 1.2)
		"event_warning":
			var et: String = e.get("etype", "")
			notice(_event_icon(et, e.get("args", {})), Loc.t("ui.warn." + et, _warn_vars(e.get("args", {}))), 5.5, 2)
		"incident_warn":
			var k: String = e.get("kind", "")
			notice(_incident_icon(k), Loc.t("ui.warn.quirk_" + k, {"room": e.get("room", "")}), 4.5, 2)
		"incident_deferred":
			pass
		"request_missed":
			notice("sys_help", Loc.t("bark.missed_request"), 3.0, 0)
		"helper_ready":
			pass
		"announce":
			notice(e.get("icon", "sys_festival") if Icons.has(e.get("icon", "")) else "sys_festival", Loc.t(e.get("text_key", "")), 5.0, 1)
		"trip":
			notice("sys_trip", Loc.t("ui.warn.tripped", {"what": Loc.t("fixture." + str(e.get("fixture", "")))}), 4.0, 2)
		"finish_prompt":
			show_banner(Loc.t("ui.finish.prompt"), Loc.t("ui.finish.cancel_hint"), 3.0, "sys_bell")
		"finish_cancel":
			banner = {}
		"coach":
			coach = {"id": e.get("id", ""), "t": 0.0}
		"coach_done":
			coach = {}
		"wrap":
			show_banner(Loc.t("bark.timer_wraps"), "", 3.0, "sys_bell")
		"countdown":
			pass
		"tip":
			var p := _w2s(Vector3(float(e.get("x", 0)) / 1e6, 1.6, float(e.get("z", 0)) / 1e6))
			floats.append({"text": "+%d" % int(e.get("amount", 0)), "pos": p, "t": 1.1, "col": Art.GOLD.darkened(0.15), "gid": int(e.get("guest", 0))})
		"checkout", "guest_cozy":
			var gid := int(e.get("guest", e.get("id", 0)))
			var g: Dictionary = s.get("guests", {}).get(gid, {})
			if not g.is_empty():
				done_cards.append({"gid": gid, "outcome": "missed" if e["type"] == "guest_cozy" else SimScore.order_outcome(g), "t": DONE_CARD_S, "fam": g["fam"]})

func _warn_vars(args: Dictionary) -> Dictionary:
	var v := {}
	for k in args:
		v[k] = str(args[k])
	if args.has("fixture"):
		v["what"] = Loc.t("fixture." + str(args["fixture"]))
	return v

static func _reason_icon(why: String) -> String:
	match why:
		"ui.reason.room_not_ready": return "sys_bed_dirty"
		"ui.reason.room_cap": return "sys_room_cap"
		"ui.reason.need_room": return "sys_need_room"
		"ui.reason.wrong_item": return "sys_soft_no"
		"ui.reason.need_linen": return "item_linen_clean"
		"ui.reason.after_start": return "sys_clock"
		"ui.reason.tripped": return "sys_trip"
	return "sys_soft_no"

static func _event_icon(et: String, args: Dictionary) -> String:
	match et:
		"thermal_pulse": return "sys_warm" if int(args.get("delta", 0)) > 0 else "sys_cold"
		"humidity_pulse": return "sys_humid"
		"steam_cloud": return "sys_steam"
		"frost_patch": return "sys_frost"
		"concert_pulse": return "sys_music"
		"fixture_trip": return "sys_trip"
		"puddle_patch": return "sys_puddle"
		"shutter_cycle": return "sys_shutter"
	return "sys_help"

static func _incident_icon(k: String) -> String:
	match k:
		"sneeze": return "sys_cold"
		"hiccup": return "sys_warm"
		"howl": return "sys_noise"
		"bloom_puddle", "overflow": return "sys_puddle"
		"steam": return "sys_steam"
		"frost": return "sys_frost"
	return "sys_help"

# ============================================================ drawing

func _draw() -> void:
	if s.is_empty() or view == null:
		return
	_draw_room_plaques()
	_draw_tickets()
	_draw_guests()
	_draw_work_rings()
	_draw_incidents()
	_draw_pings()
	if _any_inspect():
		_draw_inspect()
	_draw_prompts()
	_draw_floats()
	_draw_top()
	_draw_bottom()
	_draw_center()

func _any_inspect() -> bool:
	for st in s.get("staff", []):
		if st.get("inspect", false) and local_seats.has(st["seat"]):
			return true
	return false

func _room_screen(letter: String, y := 1.75) -> Vector2:
	var g: Dictionary = view.L.rooms[letter]
	var d: Vector2i = g["door"]
	var off := 0.55 if g["side"] == "north" else -0.55
	return _w2s(Vector3(d.x + 0.72, y, d.y + off))

func _draw_room_plaques() -> void:
	var lg: bool = Settings.g("large_requests")
	for letter in view.L.rooms:
		var g: Dictionary = view.L.rooms[letter]
		if not g["active"]:
			continue
		var r: Dictionary = s["rooms"][letter]
		var p := _room_screen(letter)
		var col: Color = Art.ROOM_COLORS[letter]
		var w := 58.0
		var rect := Rect2(p - Vector2(w * 0.5, 14), Vector2(w, 26))
		draw_rect(Rect2(rect.position + Vector2(0, 3), rect.size), UiKit.SHADOW)
		draw_style_box(UiKit._box(col.lerp(Color.WHITE, 0.15), UiKit.INK, 2, 5, 0), rect)
		var txt := "%s %d" % [letter, int(g["number"])]
		UiKit.draw_text_outlined(self, p + Vector2(0, 7), txt, 18, UiKit.INK, Color(1, 1, 1, 0))
		# A frozen door keeps a visible marker until someone clears it.
		if r.get("frost", false):
			var fp := p + Vector2(w * 0.5 + 16, -1)
			var fpulse := 1.0 + (0.0 if Settings.g("reduced_motion") else 0.1 * sin(_t * 6.0))
			UiKit.draw_bubble(self, fp, 14 * fpulse, Color("#E9F6FF"), Color("#5F9CC9"))
			UiKit.draw_icon(self, "sys_frost", fp, 20)
		# Status chip under the plaque: guest family, request, comfort, readiness.
		var chip := p + Vector2(0, 26)
		var gid: int = int(r["guest"]) if int(r["guest"]) != 0 else int(r["reserved"])
		if gid != 0:
			var gg: Dictionary = s["guests"].get(gid, {})
			if not gg.is_empty():
				UiKit.draw_bubble(self, chip + Vector2(-16, 0), 14)
				UiKit.draw_icon(self, "fam_" + gg["fam"], chip + Vector2(-16, 0), 22)
				var cf := 1.0 if gg.get("comfortable", true) else 0.0
				UiKit.draw_ring(self, chip + Vector2(-16, 0), 16, 1.0, Color("#8BD17C") if cf > 0.5 else Art.CORAL, 3.0)
				var rq := _open_req(gg)
				if not rq.is_empty():
					var ic: String = ITEM_ICON.get(rq["k"], "sys_help")
					var sz := 30.0 if lg else 24.0
					UiKit.draw_bubble(self, chip + Vector2(18, 0), sz * 0.6)
					UiKit.draw_icon(self, ic, chip + Vector2(18, 0), sz)
					UiKit.draw_ring(self, chip + Vector2(18, 0), sz * 0.6 + 3, _req_frac(rq), Art.GOLD, 3.0)
		else:
			var ready: bool = r["bed"] == "Made" and int(r["mess"]) == 0
			if not ready:
				UiKit.draw_bubble(self, chip, 12, Color("#F3E6D2"))
				UiKit.draw_icon(self, "sys_bed_dirty" if r["bed"] != "Made" else "sys_mess", chip, 20)
			elif s.get("phase", "") == "active":
				UiKit.draw_icon(self, "sys_check", chip, 18, Color(1, 1, 1, 0.85))
		if r.get("frost", false):
			UiKit.draw_icon(self, "sys_frost", p + Vector2(w * 0.5 + 12, 0), 22)

func _open_req(g: Dictionary) -> Dictionary:
	for rq in g.get("reqs", []):
		if rq["st"] == "open":
			return rq
	return {}

func _req_frac(rq: Dictionary) -> float:
	if rq.is_empty():
		return 0.0
	var hq := float(s.get("hotel_q", 0))
	if s.get("cozy", false):
		return 1.0
	var at := float(rq["at"])
	var dl := float(rq["dl"])
	if hq <= dl:
		return clampf(1.0 - (hq - at) / maxf(1.0, dl - at), 0.0, 1.0)
	return 0.05

func _draw_tickets() -> void:
	var peds: Array = s.get("pedestals", [])
	for i in peds.size():
		var gid := int(peds[i])
		if gid == 0:
			continue
		var g: Dictionary = s["guests"].get(gid, {})
		if g.is_empty() or g["state"] != "lobby":
			continue
		var pp: Vector2i = view.L.fixtures["pedestals"][i]
		var sp := _w2s(Vector3(pp.x, 1.05, pp.y))
		var frac := float(g["patience_q"]) / float(int(level.get("patience_s", SimC.PATIENCE_S)) * SimC.HOTEL_Q_PER_S)
		UiKit.draw_bubble(self, sp, 14)
		UiKit.draw_icon(self, "fam_" + g["fam"], sp, 22)
		if not s.get("cozy", false):
			var c := Color("#8BD17C") if frac > 0.5 else (Art.GOLD if frac > 0.25 else Art.CORAL)
			UiKit.draw_ring(self, sp, 17, frac, c, 4.0)
	var bench: Array = s.get("bench", [])
	if not bench.is_empty():
		var rp: Vector2i = view.L.fixtures["reception"]
		var bp := _w2s(Vector3(rp.x, 1.4, rp.y))
		UiKit.draw_bubble(self, bp, 14)
		UiKit.draw_icon(self, "item_ticket", bp, 20)
		UiKit.draw_text_outlined(self, bp + Vector2(18, -8), "×%d" % bench.size(), 16)

func _draw_guests() -> void:
	for gid in s.get("guests", {}):
		var g: Dictionary = s["guests"][gid]
		if g["state"] != "staying" or g.get("relocating", false):
			continue
		var rig: ActorRig = view.guest_rig(int(gid))
		if rig == null:
			continue
		var top := _w2s(rig.position + Vector3(0, rig.height * ModelActors.ACTOR_SCALE + 0.45, 0))
		var need: String = g.get("need", "")
		var icon := ""
		match need:
			"service":
				if _open_req(g).is_empty():
					continue
				icon = ITEM_ICON.get(_open_req(g).get("k", ""), "sys_help")
			"comfort":
				icon = _comfort_icon(g)
			"welcome":
				icon = "gift_" + g["fam"]
			"helper":
				icon = "sys_heart"
		if icon == "":
			continue
		var bob := 0.0 if Settings.g("reduced_motion") else sin(_t * 3.0 + int(gid)) * 2.0
		var c := top + Vector2(0, bob)
		var sz := 30.0 if Settings.g("large_requests") else 24.0
		UiKit.draw_bubble(self, c, sz * 0.62, UiKit.PAPER if need != "helper" else Color("#FFE9EC"))
		UiKit.draw_icon(self, icon, c, sz)
		if need == "service":
			UiKit.draw_ring(self, c, sz * 0.62 + 3, _req_frac(_open_req(g)), Art.GOLD, 3.0)
			var tp := str(_open_req(g).get("temp", ""))
			if tp != "":
				UiKit.draw_icon(self, "sys_warm" if tp == "warm" else "sys_cold", c + Vector2(-sz * 0.45, -sz * 0.45), 13)

func _comfort_icon(g: Dictionary) -> String:
	var r: Dictionary = s["rooms"].get(g["room"], {})
	if r.is_empty():
		return "sys_help"
	match g["fam"]:
		"ghost": return "sys_quiet"
		"sprout":
			if int(r["hum"]) < 55: return "sys_water"
	var c: Dictionary = Content.guest_def(g["fam"]).get("comfort", {})
	if c.has("heat_min"):
		if int(r["heat"]) < int(c["heat_min"]): return "sys_warm"
		if int(r["heat"]) > int(c["heat_max"]): return "sys_cold"
	return "sys_cozy"

func _draw_work_rings() -> void:
	var W: Dictionary = s.get("work", {})
	for key in W:
		var w: Dictionary = W[key]
		var dur := SimInteract.work_duration(null, key) if not key.begins_with("mess:") else SimC.T_MOP_ROOM
		var frac := float(w["p"]) / float(maxi(1, dur * 1000))
		if key.begins_with("mess:"):
			var letter: String = key.substr(5)
			frac = 1.0 - float(s["rooms"][letter]["mess"]) / 100.0
		var a := view.anchor_for_key(key)
		if a == Vector3.ZERO:
			continue
		var p := _w2s(a + Vector3(0, 0.3, 0))
		UiKit.draw_bubble(self, p, 10, UiKit.PAPER)
		UiKit.draw_ring(self, p, 12, frac, Color("#8BD17C"), 5.0)
	for st in s.get("staff", []):
		var act: Dictionary = st.get("act", {})
		if act.get("channel", false):
			var rig: ActorRig = view.staff_rigs.get(st["seat"], null)
			if rig:
				var p2 := _w2s(rig.position + Vector3(0, 1.75, 0))
				var frac2 := 1.0 - float(act["t"]) / float(maxi(1, int(act.get("total", 1))))
				UiKit.draw_ring(self, p2, 11, frac2, Art.GOLD, 4.0)

func _draw_incidents() -> void:
	var d: Dictionary = s.get("director", {})
	for inc in d.get("active", []):
		if inc.get("fired", false):
			continue
		var room: String = inc.get("room", "")
		if room == "" or not view.L.rooms.has(room):
			continue
		var bp: Vector2i = view.L.rooms[room]["bed"]
		var p := _w2s(Vector3(bp.x, 2.1, bp.y))
		var left := float(inc["fire_s"]) - float(s.get("hotel_s", 0))
		var total := maxf(1.0, float(inc["fire_s"]) - float(inc["start_s"]))
		var pulse := 1.0 + (0.0 if Settings.g("reduced_motion") else 0.12 * sin(_t * 8.0))
		UiKit.draw_bubble(self, p, 16 * pulse, Color("#FFF1C9"), Art.CORAL)
		UiKit.draw_icon(self, _incident_icon(inc["kind"]), p, 24)
		UiKit.draw_ring(self, p, 20, clampf(left / total, 0, 1), Art.CORAL, 3.0)
	# Hall hazards have no room plaque, so they get their own markers: a pulsing
	# steam bubble over each cloud and a small drop over each puddle.
	var pulse2 := 1.0 + (0.0 if Settings.g("reduced_motion") else 0.1 * sin(_t * 6.0))
	for cid in s.get("clouds", {}):
		var c: Dictionary = s["clouds"][cid]
		var cp := _w2s(Vector3(float(c["x"]) / 1e6, 1.9, float(c["z"]) / 1e6))
		UiKit.draw_bubble(self, cp, 15 * pulse2, Color("#FFF1C9"), Art.CORAL)
		UiKit.draw_icon(self, "sys_steam", cp, 22)
	for pid in s.get("puddles", {}):
		var pd: Dictionary = s["puddles"][pid]
		var pp := _w2s(Vector3(float(pd["x"]) / 1e6, 0.55, float(pd["z"]) / 1e6))
		UiKit.draw_icon(self, "sys_puddle", pp, 16)
	for p2 in d.get("pending", []):
		var room2: String = p2.get("room", "")
		if room2 != "" and view.L.rooms.has(room2):
			var bp2: Vector2i = view.L.rooms[room2]["bed"]
			var q := _w2s(Vector3(bp2.x, 2.1, bp2.y))
			UiKit.draw_icon(self, "sys_wait", q, 20)

func _draw_pings() -> void:
	for seat in s.get("pings", {}):
		var p: Dictionary = s["pings"][seat]
		var sp := _w2s(Vector3(float(p["x"]) / 1e6, 1.9, float(p["z"]) / 1e6))
		var col: Color = SEAT_COLORS[int(seat) % 4]
		var ph: String = p["phrase"]
		UiKit.draw_bubble(self, sp, 16, UiKit.PAPER, col.darkened(0.3))
		UiKit.draw_icon(self, "ping_" + ph.replace("help_here", "help").replace("bringing_it", "bringing").replace("room_ready", "ready").replace("thank_you", "thanks"), sp, 24)
		UiKit.draw_text_outlined(self, sp + Vector2(0, -22), Loc.t("ui.ping." + ph), 15, col.darkened(0.45))
		draw_line(sp + Vector2(0, 16), sp + Vector2(0, 30), col, 3.0)

func _draw_floats() -> void:
	for f in floats:
		var k: float = 1.0 - float(f["t"]) / 1.1
		var p: Vector2 = f["pos"] + Vector2(0, -36.0 * k)
		var a := clampf(2.5 - k * 2.5, 0.0, 1.0)
		var col: Color = f["col"]
		col.a = a
		UiKit.draw_text_outlined(self, p, f["text"], 22, col, Color(1, 1, 1, a * 0.9))

func _draw_prompts() -> void:
	# Seat tags (P1..P4) sit at the feet, beside the seat ring, so they never
	# cover a face or a prompt (§11.1 asked for tags; the head was the wrong place).
	for st0 in s.get("staff", []):
		var rig0: ActorRig = view.staff_rigs.get(int(st0["seat"]), null)
		if rig0 == null or not rig0.visible:
			continue
		var feet0 := _w2s(rig0.position)
		var col0: Color = SEAT_COLORS[int(st0["seat"]) % 4]
		var tr := Rect2(feet0 + Vector2(10, 2), Vector2(24, 16))
		draw_style_box(UiKit._box(col0, UiKit.INK, 1, 3, 0), tr)
		UiKit.draw_text_outlined(self, tr.get_center() + Vector2(0, 5), "P%d" % (int(st0["seat"]) + 1), 12, UiKit.INK, Color(0, 0, 0, 0))
	# With four players the prompts pile up around one spot, so: a target that two
	# players highlight is prompted only for the nearer one, and every prompt box
	# is pushed up until it overlaps no box drawn before it.
	var nearest_for_key := {}
	for st1 in s.get("staff", []):
		if not local_seats.has(int(st1["seat"])):
			continue
		var rig1: ActorRig = view.staff_rigs.get(int(st1["seat"]), null)
		if rig1 == null:
			continue
		for key1 in [st1["hl_c"], st1["hl_w"]]:
			if key1 == "":
				continue
			var anchor1 := view.anchor_for_key(key1)
			var d1 := rig1.position.distance_to(anchor1) if anchor1 != Vector3.ZERO else 0.0
			if not nearest_for_key.has(key1) or d1 < float(nearest_for_key[key1][1]):
				nearest_for_key[key1] = [int(st1["seat"]), d1]
	var placed: Array = []
	for st in s.get("staff", []):
		var seat: int = st["seat"]
		var rig: ActorRig = view.staff_rigs.get(seat, null)
		if rig == null or not rig.visible:
			continue
		var head := _w2s(rig.position + Vector3(0, rig.height * ModelActors.ACTOR_SCALE + 0.35, 0))
		var col: Color = SEAT_COLORS[seat % 4]
		if not local_seats.has(seat):
			continue
		var router_seat: int = seat_device.get(seat, seat)
		var y := head.y - 30.0
		var lines: Array = []
		if st["hl_c"] != "" and int(nearest_for_key.get(st["hl_c"], [seat])[0]) == seat:
			lines.append(["carry", st["hl_c"], st["hl_c_ok"], st["hl_c_why"]])
		if st["hl_w"] != "" and st["hl_w"] != st["hl_c"] and int(nearest_for_key.get(st["hl_w"], [seat])[0]) == seat:
			lines.append(["work", st["hl_w"], st["hl_w_ok"], st["hl_w_why"]])
		if st["grip"] != 0:
			lines = [["carry", "release", true, ""]]
		for ln in lines:
			var g := InputRouter.glyph(router_seat, ln[0])
			var verb := _verb(ln[0], ln[1], st)
			var ok: bool = ln[2]
			var fs := 16
			var tw := _font.get_string_size(verb, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var gw := UiKit.glyph_width(g, 24)
			var total := gw + 6 + tw + 12
			var r := Rect2(Vector2(head.x - total * 0.5, y - 13), Vector2(total, 26))
			for _bump in 4:
				var hit := false
				for pr in placed:
					if (pr as Rect2).grow(3).intersects(r):
						hit = true
						break
				if not hit:
					break
				y -= 30.0
				r.position.y = y - 13
			placed.append(r)
			draw_style_box(UiKit._box(UiKit.PAPER if ok else Color("#ECE5DA"), col.darkened(0.35) if ok else Color("#A79E91"), 2, 6, 0), r)
			UiKit.draw_glyph(self, Vector2(r.position.x + gw * 0.5 + 3, y), g, 22)
			draw_string(_font, Vector2(r.position.x + gw + 9, y + 6), verb, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiKit.INK if ok else Color("#7A7268"))
			if not ok and ln[3] != "":
				UiKit.draw_icon(self, _reason_icon(ln[3]), Vector2(r.end.x + 12, y), 18)
			y -= 30.0
		# Ping radial
		if InputRouter.ping_radial_open(router_seat):
			var c := head + Vector2(0, -70)
			var labels := ["help_here", "bringing_it", "room_ready", "thank_you"]
			var offs := [Vector2(0, -38), Vector2(-46, 0), Vector2(0, 38), Vector2(46, 0)]
			for i in 4:
				UiKit.draw_bubble(self, c + offs[i], 16)
				UiKit.draw_icon(self, ["ping_help", "ping_bringing", "ping_ready", "ping_thanks"][i], c + offs[i], 22)
		for b in bubbles:
			if b["seat"] == seat:
				var bp := head + Vector2(0, -34.0 - 30.0 * lines.size())
				var text: String = b["text"]
				var tw2 := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
				var br := Rect2(bp - Vector2(tw2 * 0.5 + 22, 14), Vector2(tw2 + 44, 28))
				draw_style_box(UiKit._box(Color("#FFF6E3"), Art.CORAL.darkened(0.2), 2, 8, 0), br)
				if b["icon"] != "":
					UiKit.draw_icon(self, b["icon"], Vector2(br.position.x + 14, bp.y), 18)
				draw_string(_font, Vector2(br.position.x + 28, bp.y + 6), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UiKit.INK)
		# Held item icon chip by the hands (persistent silhouettes help find it).
		if int(st["held"]) != 0:
			var it: Dictionary = s["items"].get(int(st["held"]), {})
			if not it.is_empty():
				var hp := _w2s(rig.position + Vector3(0.45, 0.9, 0))
				UiKit.draw_icon(self, ITEM_ICON.get(it["k"], "sys_help"), hp, 18, Color(1, 1, 1, 0.9))
				var htp := str(it.get("temp", ""))
				if htp != "":
					UiKit.draw_icon(self, "sys_warm" if htp == "warm" else "sys_cold", hp + Vector2(9, -9), 11)

func _verb(kind: String, key: String, st: Dictionary) -> String:
	var k := key.split(":")[0]
	var held := ""
	if int(st["held"]) != 0:
		held = s["items"].get(int(st["held"]), {}).get("k", "")
	if key == "release":
		return Loc.t("ui.verb.release")
	match k:
		"plaque":
			return Loc.t("ui.verb.move_here" if held == "move_ticket" else "ui.verb.assign", {"room": key.substr(7)})
		"plinth":
			return Loc.t("ui.verb.place_gift" if held != "" else "ui.verb.take_gift")
		"st":
			var which := key.substr(3)
			if held == "":
				return Loc.t("ui.verb.take_" + which)
			return Loc.t("ui.verb.return" if which in ["return", "linen", "towels", "snacks", "kiosk"] else "ui.verb.put_" + which)
		"dock":
			return Loc.t("ui.verb.take_tool" if held == "" else "ui.verb.dock_tool")
		"counter":
			return Loc.t("ui.verb.counter_take" if held == "" else "ui.verb.counter_put")
		"temper", "vent":
			return Loc.t("ui.verb.temper_warm" if held == "towel" else "ui.verb.temper_cool")
		"lift":
			return Loc.t("ui.verb.lift_load" if held != "" else "ui.verb.take")
		"thermo":
			var r: Dictionary = s["rooms"][key.substr(7)]
			var nxt := {"neutral": "warm", "warm": "cool", "cool": "neutral"}
			return Loc.t("ui.verb.thermo_" + nxt.get(r["thermo"], "warm"))
		"gate":
			return Loc.t("ui.verb.gate_close" if s.get("gates", {}).get(key.substr(5), false) else "ui.verb.gate_open")
		"bell":
			return Loc.t("ui.verb.finish" if s.get("_can_finish", false) else "ui.verb.ring")
	if kind == "carry":
		return Loc.t("ui.verb." + VERBS_CARRY.get(k, k))
	return Loc.t("ui.verb." + k)

func _draw_inspect() -> void:
	var rooms: Dictionary = s["rooms"]
	var L := view.L
	# Thermal edges: lines between rooms with flow arrows and gate state.
	for e in L.thermal_edges:
		var ab := L.edge_rooms(e)
		var pa := _room_center(ab[0])
		var pb := _room_center(ab[1])
		var open: bool = s.get("gates", {}).get(e, false)
		var col := Art.WARM if int(rooms[ab[1]]["heat"]) + int(rooms[ab[0]]["heat"]) > 0 else Art.COLD
		if not open:
			col = Color(0.5, 0.5, 0.55, 0.8)
		draw_line(pa, pb, Color(0.15, 0.18, 0.22, 0.6), 7.0)
		draw_line(pa, pb, col, 4.0)
		var mid := (pa + pb) * 0.5
		UiKit.draw_bubble(self, mid, 13)
		UiKit.draw_icon(self, "sys_gate" if open else "sys_gate_closed", mid, 20)
	for e2 in L.acoustic_edges:
		var ab2 := L.edge_rooms(e2)
		var pa2 := _room_center(ab2[0])
		var pb2 := _room_center(ab2[1])
		var n := 10
		for i in n:
			if i % 2 == 0:
				draw_line(pa2.lerp(pb2, float(i) / n), pa2.lerp(pb2, float(i + 1) / n), Art.SOUND, 3.0)
		UiKit.draw_icon(self, "sys_note_small", (pa2 + pb2) * 0.5 + Vector2(18, 0), 18)
	for letter in L.rooms:
		if not L.rooms[letter]["active"]:
			continue
		var r: Dictionary = rooms[letter]
		var c := _room_center(letter)
		var w := 92.0
		var rect := Rect2(c - Vector2(w * 0.5, 34), Vector2(w, 68))
		draw_style_box(UiKit._box(Color("#2E3A44DD"), UiKit.CREAM, 2, 6, 0), rect)
		var y := rect.position.y + 14
		var rows: Array = []
		if view.systems.has("thermal"):
			rows.append(["sys_warm" if int(r["heat"]) >= 0 else "sys_cold", "%+d" % int(r["heat"]), Loc.t("ui.inspect.mode_" + r["thermo"])])
		if view.systems.has("sound"):
			rows.append(["sys_noise", str(int(r["noise"])), "" if int(r["curtain"]) == 0 else Loc.t("ui.inspect.curtain")])
		if view.systems.has("moisture"):
			rows.append(["sys_water", str(int(r["hum"])), ""])
		if rows.is_empty():
			rows.append(["sys_bed", Loc.t("ui.bed." + r["bed"]), ""])
		for row in rows:
			UiKit.draw_icon(self, row[0], Vector2(rect.position.x + 14, y), 16)
			draw_string(_font, Vector2(rect.position.x + 26, y + 6), row[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UiKit.CREAM)
			if row[2] != "":
				draw_string(_font, Vector2(rect.position.x + 54, y + 6), row[2], HORIZONTAL_ALIGNMENT_LEFT, 40, 12, Color("#D9D2C5"))
			y += 18

func _room_center(letter: String) -> Vector2:
	var r: Rect2i = view.L.rooms[letter]["rect"]
	return _w2s(Vector3(r.position.x + (r.size.x - 1) * 0.5, 0.6, r.position.y + (r.size.y - 1) * 0.5))

# ------------------------------------------------------------ top/bottom

func _draw_top() -> void:
	var W := size.x
	# Clock (top centre).
	var phase: String = s.get("phase", "")
	if not show_clock:
		return
	var cx := W * 0.5
	var dur := int(level.get("duration_hotel_s", 0))
	var hs := float(s.get("hotel_q", 0)) / SimC.HOTEL_Q_PER_S
	var r := Rect2(Vector2(cx - 92, 10), Vector2(184, 54))
	draw_style_box(UiKit._box(UiKit.CREAM, UiKit.WALNUT, 3, 10, 0), r)
	if dur > 0:
		var frac := clampf(hs / float(dur), 0.0, 1.0)
		if s.get("cozy", false):
			UiKit.draw_icon(self, "sys_sun_moon", Vector2(r.position.x + 26, r.position.y + 27), 30)
			UiKit.draw_text_outlined(self, Vector2(cx + 18, r.position.y + 25), Loc.t("ui.hud.take_your_time"), 16, UiKit.INK, Color(0, 0, 0, 0))
		else:
			UiKit.draw_icon(self, "sys_clock", Vector2(r.position.x + 26, r.position.y + 27), 30)
			var left := maxi(0, dur - int(hs))
			UiKit.draw_text_outlined(self, Vector2(cx + 14, r.position.y + 30), "%d:%02d" % [left / 60, left % 60], 30, UiKit.INK, Color(0, 0, 0, 0))
		# Wave pips and progress bar.
		var bar := Rect2(r.position + Vector2(12, 44), Vector2(r.size.x - 24, 5))
		draw_rect(bar, Color("#D9C7AE"))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * frac, bar.size.y)), Art.CORAL)
		var anchors: Array = s.get("wave_marks", ArrivalPlan.anchors(dur))
		for i in anchors.size():
			var ax := bar.position.x + bar.size.x * clampf(float(anchors[i]) / dur, 0, 1)
			draw_circle(Vector2(ax, bar.position.y + 2), 5, UiKit.INK)
			draw_circle(Vector2(ax, bar.position.y + 2), 3, Art.GOLD if hs >= anchors[i] else UiKit.CREAM)
	else:
		UiKit.draw_text_outlined(self, Vector2(cx, r.position.y + 34), Loc.t("ui.hud.practice"), 20, UiKit.INK, Color(0, 0, 0, 0))
	_draw_orders()
	_draw_objectives()

## The order rail (docs/DESIGN_V2.md §4): one card per guest from the moment
## they are announced until they leave. Each card shows the steps in order
## (key, gift, each request) with the current one lit, and a timer bar: lobby
## patience, then the open request's window, then the stay.
const CARD_W := 112.0
const CARD_H := 70.0
const DONE_CARD_S := 1.4             # a finished order's card stays this long below the rail
const DONE_FADE_S := 0.3             # and fades only in its last moment

func _order_cards() -> Array:
	var cards: Array = []
	for gid in s.get("guests", {}):
		var g: Dictionary = s["guests"][gid]
		if g["state"] == "announced" and not g.get("announced", false):
			continue
		if g["state"] in ["announced", "lobby", "walking", "staying"]:
			cards.append(g)
	cards.sort_custom(func(a, b): return int(a["ai"]) < int(b["ai"]))
	return cards

## Festival trunks still on the floor are jobs on the rail too (DESIGN_V2 §5.6):
## a card with the two handles, who holds each, and the way left to the stand.
func _trunk_cards() -> Array:
	var out: Array = []
	for tid in s.get("trunks", {}):
		var tr: Dictionary = s["trunks"][tid]
		if not tr.get("delivered", false):
			out.append(tr)
	out.sort_custom(func(a, b): return int(a["id"]) < int(b["id"]))
	return out

func _draw_orders() -> void:
	var cards := _order_cards()
	var trunks := _trunk_cards()
	var x := 14.0
	var y := 10.0
	var hq := float(s.get("hotel_q", 0))
	var limit_x := size.x * 0.5 - 92.0 - 10.0 if show_clock else size.x * 0.6
	var fit := clampi(int((limit_x - x - 50.0) / (CARD_W + 8.0)), 1, 5)
	# Trunk jobs take the rightmost slots; guests keep arrival order on the left.
	var trunk_slots := mini(trunks.size(), maxi(0, fit - 1))
	var shown := mini(fit - trunk_slots, cards.size())
	var pat_q := float(int(level.get("patience_s", SimC.PATIENCE_S)) * SimC.HOTEL_Q_PER_S)
	for i in shown:
		var g: Dictionary = cards[i]
		var r := Rect2(Vector2(x, y), Vector2(CARD_W, CARD_H))
		var fam_col: Color = Art.FAMILY_COLORS[g["fam"]].darkened(0.35)
		var urgent := false
		var frac := 1.0
		var bar_col := Art.GOLD
		var sub := ""
		match g["state"]:
			"announced":
				var secs := maxi(0, int(ceil((float(g["arrive_q"]) - hq) / SimC.HOTEL_Q_PER_S)))
				sub = Loc.t("ui.order.arrives", {"n": secs})
				bar_col = Color("#C9BFB0")
			"lobby":
				frac = clampf(float(g["patience_q"]) / pat_q, 0.0, 1.0)
				urgent = frac < 0.3
				bar_col = Color("#8BD17C") if frac > 0.5 else (Art.GOLD if frac > 0.25 else Art.CORAL)
			"walking":
				bar_col = UiKit.SKY
			"staying":
				var rq := _open_req(g)
				if not rq.is_empty():
					frac = _req_frac(rq)
					urgent = frac < 0.3
					bar_col = Art.GOLD if frac > 0.25 else Art.CORAL
				else:
					var sl := maxf(1.0, float(g["stay_len"]))
					frac = 1.0 - clampf(float(g["stay_s"]) / sl, 0.0, 1.0)
					bar_col = UiKit.SAGE
		var pulse := 1.0 if (not urgent or Settings.g("reduced_motion")) else 0.85 + 0.15 * absf(sin(_t * 8.0))
		var bgc := UiKit.PAPER if g["state"] != "announced" else Color("#EFE6D8")
		if urgent:
			bgc = bgc.lerp(Art.CORAL, 0.25 * pulse)
		draw_rect(Rect2(r.position + Vector2(0, 3), r.size), UiKit.SHADOW)
		draw_style_box(UiKit._box(bgc, fam_col, 3, 8, 0), r)
		UiKit.draw_icon(self, "fam_" + g["fam"], r.position + Vector2(20, 24), 30)
		# Steps: key, gift, then each planned request.
		var steps: Array = [["item_ticket", g["admitted"]], ["gift_" + g["fam"], g["welcomed"]]]
		var reqs: Array = g.get("reqs", [])
		var plan: Array = g.get("plan", [])
		for j in plan.size():
			var k: String = plan[j]
			var done: bool = j < reqs.size() and reqs[j]["st"] in ["done", "late"]
			var missed: bool = j < reqs.size() and reqs[j]["st"] == "missed"
			var need_t := SimGuests.needed_temp(view.systems.has("thermal"), g["fam"], k)
			steps.append([ITEM_ICON.get(k, "sys_help"), done, missed, "" if need_t == "" else ("sys_warm" if need_t == "warm" else "sys_cold")])
		var cur := -1
		for j in steps.size():
			if not steps[j][1] and (steps[j].size() < 3 or not steps[j][2]):
				cur = j
				break
		var sx := r.position.x + 44.0
		for j in steps.size():
			var c := Vector2(sx + j * 22.0, r.position.y + 20.0)
			var done2: bool = steps[j][1]
			var missed2: bool = steps[j].size() >= 3 and steps[j][2]
			if j == cur:
				UiKit.draw_bubble(self, c, 11, Color("#FFF1C9"), fam_col)
			UiKit.draw_icon(self, steps[j][0], c, 18, Color(1, 1, 1, 0.45 if (done2 or missed2) else 1.0))
			if steps[j].size() >= 4 and str(steps[j][3]) != "":
				UiKit.draw_icon(self, str(steps[j][3]), c + Vector2(-8, -8), 11)
			if done2:
				UiKit.draw_icon(self, "sys_check", c + Vector2(5, 5), 12)
			elif missed2:
				UiKit.draw_icon(self, "sys_soft_no", c + Vector2(5, 5), 12)
		if sub != "":
			draw_string(_font, r.position + Vector2(44, 50), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UiKit.INK)
		var bar := Rect2(r.position + Vector2(8, CARD_H - 11), Vector2(CARD_W - 16, 6))
		draw_rect(bar, Color("#D9C7AE"))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * frac, bar.size.y)), bar_col)
		if int(g.get("tips", 0)) > 0:
			UiKit.draw_text_outlined(self, r.position + Vector2(CARD_W - 16, 50), "+%d" % (int(g["tips"]) / 1000), 13, Art.GOLD.darkened(0.3), Color(1, 1, 1, 0.9))
		x += CARD_W + 8.0
	for ti in trunk_slots:
		_draw_trunk_card(Rect2(Vector2(x, y), Vector2(CARD_W, CARD_H)), trunks[ti])
		x += CARD_W + 8.0
	var hidden := (cards.size() - shown) + (trunks.size() - trunk_slots)
	if hidden > 0:
		var r2 := Rect2(Vector2(x, y + 10), Vector2(44, 48))
		draw_style_box(UiKit._box(Color("#EFE6D8"), UiKit.WALNUT, 2, 8, 0), r2)
		draw_string(_font, r2.position + Vector2(8, 32), "+%d" % hidden, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, UiKit.INK)
	# Finished orders slide out below the rail: readable at full strength for a
	# beat, then gone in a quick fade. A slow linear fade left a translucent grey
	# slab under the rail for most of the card's life (very visible on the night
	# floors), and the card is as wide as its label so the text never overruns.
	var dx := 14.0
	for c in done_cards:
		var tl: float = c["t"]
		var a := clampf(tl / DONE_FADE_S, 0.0, 1.0)
		a = a * a * (3.0 - 2.0 * a)
		if a < 0.03:
			continue
		var k2: float = 1.0 - tl / DONE_CARD_S
		var t := Loc.t("ui.order." + str(c["outcome"]))
		var cw := maxf(CARD_W, _font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 38.0)
		var cr := Rect2(Vector2(dx, y + CARD_H + 6.0 + k2 * 10.0), Vector2(cw, 26))
		var oc: Color = Color("#8BD17C") if c["outcome"] == "served" else (Art.GOLD if c["outcome"] == "late" else Art.CORAL)
		oc.a = a
		var bg := UiKit.PAPER
		bg.a = a
		draw_style_box(UiKit._box(bg, oc, 2, 6, 0), cr)
		UiKit.draw_icon(self, "fam_" + str(c["fam"]), cr.position + Vector2(14, 13), 18, Color(1, 1, 1, a))
		var tc := UiKit.INK
		tc.a = a
		draw_string(_font, cr.position + Vector2(28, 18), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, tc)
		dx += cw + 8.0

var _trunk_d0: Dictionary = {}       # trunk id -> distance to the stand when first seen

## A festival trunk as a job card: the trunk, its two handles (who holds which),
## a one-line cue and the way left to the stand. Two carriers move it twice as
## fast, so a half-held trunk says so.
func _draw_trunk_card(r: Rect2, tr: Dictionary) -> void:
	var tid := int(tr["id"])
	var grips := 0
	for h in 2:
		if int(tr["h"][h]) != -1:
			grips += 1
	draw_rect(Rect2(r.position + Vector2(0, 3), r.size), UiKit.SHADOW)
	draw_style_box(UiKit._box(UiKit.PAPER, UiKit.WALNUT, 3, 8, 0), r)
	UiKit.draw_icon(self, "item_trunk", r.position + Vector2(20, 24), 30)
	for h in 2:
		var c := r.position + Vector2(58 + h * 26, 20)
		var seat := int(tr["h"][h])
		if seat == -1:
			UiKit.draw_bubble(self, c, 10, Color("#EFE6D8"), UiKit.WALNUT)
			UiKit.draw_icon(self, "sys_assist", c, 14, Color(1, 1, 1, 0.5))
		else:
			UiKit.draw_bubble(self, c, 11, Color("#FFF1C9"), SEAT_COLORS[seat % 4])
			UiKit.draw_icon(self, "staff_" + _char_of_seat(seat), c, 20)
	var cue := "ui.order.trunk_grab" if grips == 0 else ("ui.order.trunk_two" if grips == 1 else "ui.order.trunk_go")
	draw_string(_font, r.position + Vector2(44, 50), Loc.t(cue), HORIZONTAL_ALIGNMENT_LEFT, CARD_W - 48, 11, UiKit.INK)
	var frac := 0.0
	var gp = view.L.fixtures.get("goal_pad", null)
	if gp is Vector2i:
		var d := Vector2(float(tr["x"]) / 1e6 - float(gp.x), float(tr["z"]) / 1e6 - float(gp.y)).length()
		var d0: float = float(_trunk_d0.get(tid, 0.0))
		if d0 <= 0.0 or d > d0:
			d0 = maxf(d, 0.01)
			_trunk_d0[tid] = d0
		frac = clampf(1.0 - d / d0, 0.0, 1.0)
	var bar := Rect2(r.position + Vector2(8, CARD_H - 11), Vector2(CARD_W - 16, 6))
	draw_rect(bar, Color("#D9C7AE"))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * frac, bar.size.y)), Art.GOLD if grips == 2 else UiKit.WALNUT)

func _char_of_seat(seat: int) -> String:
	for st in s.get("staff", []):
		if int(st["seat"]) == seat:
			return str(st.get("char", "pip"))
	return "pip"

static func _family_need_icon(fam: String) -> String:
	match fam:
		"yeti": return "sys_cold"
		"dragon": return "sys_warm"
		"ghost": return "sys_quiet"
		"moonwolf": return "sys_noise"
		"sprout": return "sys_water"
	return "sys_cozy"

func _draw_objectives() -> void:
	var W := size.x
	var x := W - 14.0
	var y := 12.0
	var rbs: Array = s.get("_ribbons", [])
	for rb in rbs:
		if rb.get("earned", false):
			continue
		var txt := "%s  %d/%d" % [rb["label"], int(rb["value"]), int(rb["target"])]
		var tw := _font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		var r := Rect2(Vector2(x - tw - 46, y), Vector2(tw + 46, 30))
		draw_style_box(UiKit._box(UiKit.PAPER, UiKit.PLUM, 2, 8, 0), r)
		UiKit.draw_icon(self, "sys_ribbon", r.position + Vector2(16, 15), 20)
		draw_string(_font, r.position + Vector2(32, 21), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UiKit.INK)
		y += 36.0
		break
	for n in notices:
		var text: String = n["text"]
		var tw2 := minf(380.0, _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x)
		var r2 := Rect2(Vector2(x - tw2 - 50, y), Vector2(tw2 + 50, 34))
		draw_style_box(UiKit._box(Color("#FFF1C9"), Art.CORAL.darkened(0.15), 3, 8, 0), r2)
		UiKit.draw_icon(self, n["icon"], r2.position + Vector2(18, 17), 24)
		draw_string(_font, r2.position + Vector2(36, 23), text, HORIZONTAL_ALIGNMENT_LEFT, tw2 + 4, 16, UiKit.INK)
		y += 40.0
	# Useful jobs (LB/R): up to three suggestions.
	var jobs: Array = s.get("_jobs", [])
	if Settings.g("hints") and not jobs.is_empty() and s.get("phase", "") == "active":
		var jx := W - 14.0 - jobs.size() * 34.0
		for i in jobs.size():
			var j: Dictionary = jobs[i]
			var c := Vector2(jx + i * 34.0 + 16, y + 18)
			var lit := false
			for st in s.get("staff", []):
				if local_seats.has(st["seat"]) and int(st.get("hint_t", 0)) > 0 and int(st.get("hint_i", -1)) == i:
					lit = true
			UiKit.draw_bubble(self, c, 14, Color("#FFF1C9") if lit else UiKit.PAPER)
			UiKit.draw_icon(self, j["icon"], c, 20)
			if lit:
				var a: Vector3 = j.get("pos", Vector3.ZERO)
				if a != Vector3.ZERO:
					var wp := _w2s(a + Vector3(0, 1.4, 0))
					var bob := 0.0 if Settings.g("reduced_motion") else sin(_t * 6.0) * 4.0
					UiKit.draw_icon(self, "ui_arrow_down", wp + Vector2(0, bob - 20), 26)

func _draw_bottom() -> void:
	var staff: Array = s.get("staff", [])
	var n := staff.size()
	var w := 168.0
	var total := n * (w + 10) - 10
	var x := size.x * 0.5 - total * 0.5
	var y := size.y - 58.0
	for st in staff:
		var seat: int = st["seat"]
		var col: Color = SEAT_COLORS[seat % 4]
		var r := Rect2(Vector2(x, y), Vector2(w, 48))
		draw_style_box(UiKit._box(UiKit.PAPER, col.darkened(0.35), 3, 10, 0), r)
		UiKit.draw_icon(self, "staff_" + st["char"], r.position + Vector2(26, 24), 40)
		draw_string(_font, r.position + Vector2(48, 20), "P%d" % (seat + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, col.darkened(0.45))
		if int(st["held"]) != 0:
			var it: Dictionary = s["items"].get(int(st["held"]), {})
			UiKit.draw_bubble(self, r.position + Vector2(w - 26, 24), 16)
			UiKit.draw_icon(self, ITEM_ICON.get(it.get("k", ""), "sys_help"), r.position + Vector2(w - 26, 24), 24)
		elif int(st["grip"]) != 0:
			UiKit.draw_icon(self, "item_trunk", r.position + Vector2(w - 26, 24), 24)
		var ax := r.position.x + 52.0
		var ass: Dictionary = st.get("assists", {})
		if ass.get("steady_feet", false):
			UiKit.draw_icon(self, "sys_move", Vector2(ax + 8, r.position.y + 36), 14)
			ax += 18
		if ass.get("toggle_work", false):
			UiKit.draw_icon(self, "sys_check", Vector2(ax + 8, r.position.y + 36), 14)
			ax += 18
		var conn: String = connection.get(seat, "")
		if conn != "":
			UiKit.draw_icon(self, "sys_connection_good" if conn == "good" else ("sys_connection_poor" if conn == "poor" else "sys_disconnected"), Vector2(r.position.x + w - 56, r.position.y + 14), 16)
		if not st["present"]:
			UiKit.draw_icon(self, "sys_controller", Vector2(r.position.x + 92, r.position.y + 24), 22, Color(1, 1, 1, 0.9))
		if s.get("phase", "") == "planning":
			UiKit.draw_icon(self, "sys_check" if st.get("ready", false) else "sys_wait", Vector2(r.position.x + 96, r.position.y + 30), 22)
		x += w + 10
	if s.get("gus", {}).get("on", false):
		UiKit.draw_icon(self, "sys_assist", Vector2(size.x * 0.5 + total * 0.5 + 26, y + 24), 26)

func _draw_center() -> void:
	var phase: String = s.get("phase", "")
	var c := Vector2(size.x * 0.5, size.y * 0.26)
	if phase == "planning":
		var txt := Loc.t("ui.plan.title")
		var sub := Loc.t("ui.plan.sub")
		_draw_card(c, txt, sub, "sys_inspect")
		# Per-seat ready hints with glyphs, just above the staff portraits.
		var y := size.y - 82.0
		var parts: Array = []
		for seat in local_seats:
			parts.append(seat)
		var x := size.x * 0.5 - parts.size() * 100.0 * 0.5
		for seat2 in parts:
			var g := InputRouter.glyph(seat_device.get(seat2, seat2), "hint")
			UiKit.draw_glyph(self, Vector2(x + 20, y), g, 24)
			draw_string(_font, Vector2(x + 38, y + 6), Loc.t("ui.plan.ready"), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UiKit.INK)
			x += 100.0
	elif phase == "countdown":
		var n := 3 - int(float(s.get("phase_t", 0)) / 30.0)
		UiKit.draw_text_outlined(self, Vector2(size.x * 0.5, size.y * 0.42), str(maxi(1, n)), 96, UiKit.CORAL.darkened(0.2), UiKit.CREAM)
	if not coach.is_empty():
		_draw_card(c, Loc.t("coach." + str(coach["id"]) + ".title"), Loc.t("coach." + str(coach["id"]) + ".body") + "   " + Loc.t("ui.coach.skip"), "sys_coach")
	if not tutorial.is_empty():
		_draw_tutorial()
	if not banner.is_empty():
		_draw_card(Vector2(size.x * 0.5, size.y * 0.42), banner["text"], banner.get("sub", ""), banner.get("icon", ""))

func _draw_card(c: Vector2, text: String, sub: String, icon: String) -> void:
	var w := maxf(_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x, minf(560.0, _font.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x)) + 90
	w = minf(w, 680.0)
	var sub_lines := 1 if _font.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x <= w - 70 else 2
	var h := (54.0 + 22.0 * sub_lines) if sub != "" else 54.0
	var r := Rect2(c - Vector2(w * 0.5, h * 0.5), Vector2(w, h))
	draw_rect(Rect2(r.position + Vector2(0, 5), r.size), UiKit.SHADOW)
	draw_style_box(UiKit._box(UiKit.PAPER, UiKit.WALNUT, 3, 12, 0), r)
	if icon != "":
		UiKit.draw_icon(self, icon, r.position + Vector2(32, h * 0.5), 34)
	draw_string(_font, r.position + Vector2(58, 32), text, HORIZONTAL_ALIGNMENT_LEFT, w - 70, 26, UiKit.INK)
	if sub != "":
		draw_multiline_string(_font, r.position + Vector2(58, 60), sub, HORIZONTAL_ALIGNMENT_LEFT, w - 70, 17, 2, Color("#5B5148"))

func _draw_tutorial() -> void:
	for c in tutorial.get("circles", []):
		var pc := _w2s(Vector3(float(c[0]) / 1e6, 0.05, float(c[1]) / 1e6))
		var pulse := 1.0 if Settings.g("reduced_motion") else 1.0 + 0.1 * sin(_t * 5.0)
		var col := Color("#8BD17C") if c[2] else UiKit.GOLD
		draw_arc(pc, 30.0 * pulse, 0, TAU, 32, UiKit.INK, 7.0)
		draw_arc(pc, 30.0 * pulse, 0, TAU, 32, col, 4.0)
		if c[2]:
			UiKit.draw_icon(self, "sys_check", pc, 22)
	var cap: String = tutorial.get("caption", "")
	var speaker: String = tutorial.get("speaker", "nana")
	var y := size.y - 150.0
	var w := minf(760.0, size.x - 80)
	var r := Rect2(Vector2(size.x * 0.5 - w * 0.5, y), Vector2(w, 74))
	draw_rect(Rect2(r.position + Vector2(0, 5), r.size), UiKit.SHADOW)
	draw_style_box(UiKit._box(UiKit.PAPER, UiKit.PLUM, 3, 12, 0), r)
	var portrait := "npc_" + speaker if speaker in ["nana", "gus", "dot"] else ("guest_" + speaker if Icons.has("guest_" + speaker) else "npc_nana")
	UiKit.draw_icon(self, portrait, r.position + Vector2(38, 37), 52)
	UiKit.draw_icon(self, tutorial.get("icon", "sys_help"), r.position + Vector2(w - 34, 37), 34)
	draw_string(_font, r.position + Vector2(76, 24), Loc.t("cast." + speaker), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, UiKit.PLUM.darkened(0.3))
	draw_multiline_string(_font, r.position + Vector2(76, 46), cap, HORIZONTAL_ALIGNMENT_LEFT, w - 130, 18, 2, UiKit.INK)
	if hint_level >= 3:
		var g := InputRouter.glyph(seat_device.get(local_seats[0] if not local_seats.is_empty() else 0, 0), "hint")
		var hp := Vector2(size.x * 0.5, y - 22)
		var t := Loc.t("ui.tut.try_for_me")
		var tw := _font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		var rr := Rect2(hp - Vector2(tw * 0.5 + 26, 14), Vector2(tw + 52, 28))
		draw_style_box(UiKit._box(Color("#FFF1C9"), UiKit.GOLD.darkened(0.3), 2, 8, 0), rr)
		UiKit.draw_glyph(self, Vector2(rr.position.x + 16, hp.y), g, 22)
		draw_string(_font, Vector2(rr.position.x + 34, hp.y + 6), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UiKit.INK)
