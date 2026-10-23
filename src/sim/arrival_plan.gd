class_name ArrivalPlan
extends RefCounted
## Deterministic roster expansion and arrival scheduling (§10.1, §10.2).

## Returns Array of waves; each wave is Array of family ids, already scaled.
static func expand_waves(level: Dictionary, humans: int, active_room_count: int) -> Array:
	var h := clampi(humans, 1, 4)
	var scale: int = SimC.PLAYER_SCALE_MILLI[h - 1]
	var cap := mini(6, mini(SimC.ROOM_CAP_BY_HUMANS[h - 1], active_room_count))
	var out: Array = []
	for w in level.get("waves", []):
		var roster: Array = w["roster"]
		var b := roster.size()
		var n := SimC.round_half_up_milli(b * scale)
		n = clampi(n, 1, cap)
		n = maxi(n, int(w.get("minimum_size", 1)))
		var wave: Array = []
		for i in n:
			wave.append(roster[i % b])
		out.append(wave)
	return out

## Last-arrival anchors for a shift of duration D hotel seconds.
static func anchors(duration_s: int) -> Array:
	return [30, int(floor((30 + duration_s - 150) / 2.0)), duration_s - 150]

## Flattened schedule: [{family, wave, index_in_wave, arrive_s, announce_s}] sorted by time.
static func schedule(level: Dictionary, humans: int, active_room_count: int, reserve_s: int = 150) -> Array:
	var waves := expand_waves(level, humans, active_room_count)
	var d := int(level["duration_hotel_s"])
	var an := [30, int(floor((30 + d - reserve_s) / 2.0)), d - reserve_s]
	var out: Array = []
	var arrival_index := 0
	for wi in waves.size():
		var wave: Array = waves[wi]
		var k := wave.size()
		for j in k:
			var t: int = an[wi] - 5 * (k - 1 - j)
			out.append({"family": wave[j], "wave": wi, "index_in_wave": j,
				"arrive_s": t, "announce_s": maxi(0, t - SimC.ANNOUNCE_S), "arrival_index": arrival_index})
			arrival_index += 1
	return out

## Final arrival reserve from patience + walk + max stay + departure (§10.2).
static func reserve_seconds(max_stay_s: int = 80, patience_s: int = SimC.PATIENCE_S) -> int:
	return patience_s + SimC.WALK_BOUND_S + max_stay_s + SimC.DEPART_S
