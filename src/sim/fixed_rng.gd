class_name FixedRng
extends RefCounted
## Deterministic 32-bit xorshift-multiply generator. Independent of engine RNG so
## replays stay reproducible. Mechanical and cosmetic streams use separate
## instances (§9.8).

var state: int = 0x9E3779B9

func _init(seed_value: int = 1) -> void:
	reseed(seed_value)

func reseed(seed_value: int) -> void:
	state = (seed_value ^ 0x5DEECE66D) & 0xFFFFFFFF
	if state == 0:
		state = 0x1234567
	for i in 4:
		next_u32()

func next_u32() -> int:
	var x := state
	x ^= (x << 13) & 0xFFFFFFFF
	x ^= x >> 17
	x ^= (x << 5) & 0xFFFFFFFF
	state = x & 0xFFFFFFFF
	return (state * 0x2545F491) & 0xFFFFFFFF

func range_i(lo: int, hi_inclusive: int) -> int:
	if hi_inclusive <= lo:
		return lo
	return lo + int(next_u32() % (hi_inclusive - lo + 1))

func pick(arr: Array):
	if arr.is_empty():
		return null
	return arr[range_i(0, arr.size() - 1)]
