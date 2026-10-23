class_name StationNode
extends Node3D
## Runtime node for a procedural station, fixture or stateful item (§7.3, §17.3).
## ModelStations / ModelItems build the geometry and install a per-kind state
## callable and idle-animation callable. apply() is called every frame with the
## latest presentation state; the installed callables only touch the scene when
## a watched value changes (see changed()), so repeated calls are cheap and
## idempotent. Animation is cosmetic and never feeds back into the simulation.

## Station / item kind id (e.g. "hamper", "watering_can").
var kind: String = ""
## Named child nodes for animation and toggles (e.g. parts["drum"]).
var parts: Dictionary = {}
## Build options the model was created with (room_color, side, palette, ...).
var opts: Dictionary = {}
## Seconds of accumulated idle animation time.
var t := 0.0
## Live animation values written by apply() and read by tick() (e.g. "sway").
var anim: Dictionary = {}
## func(node: StationNode, state: Dictionary) -> void
var apply_fn: Callable
## func(node: StationNode, dt: float) -> void
var tick_fn: Callable
## When true the node ticks itself from _process (galleries, menus). In play the
## view layer calls tick() explicitly, so this stays off.
var auto_tick := false
var _memo: Dictionary = {}

func _ready() -> void:
	set_process(auto_tick)

func _process(dt: float) -> void:
	tick(dt)

func set_auto_tick(on: bool) -> void:
	auto_tick = on
	set_process(on)

## Applies the latest presentation state. Default: no-op.
func apply(state: Dictionary) -> void:
	if apply_fn.is_valid():
		apply_fn.call(self, state)

## Advances idle animation (spinning drums, swaying bells, steam puffs).
func tick(dt: float) -> void:
	t += dt
	if tick_fn.is_valid():
		tick_fn.call(self, dt)

## True when `value` differs from the last value recorded for `key`; records it.
func changed(key: String, value) -> bool:
	if _memo.has(key):
		var old = _memo[key]
		if typeof(old) == typeof(value) and old == value:
			return false
	_memo[key] = value.duplicate() if (value is Array or value is Dictionary) else value
	return true

## Last recorded value for `key` (see changed()).
func last(key: String, default_v = null):
	return _memo.get(key, default_v)

## Shows/hides a named part without touching the scene when already correct.
func show_part(key: String, on: bool) -> void:
	var n: Node3D = parts.get(key)
	if n != null and n.visible != on:
		n.visible = on

## Swaps a named MeshInstance3D part's mesh only when it differs.
func set_part_mesh(key: String, mesh: Mesh) -> void:
	var mi: MeshInstance3D = parts.get(key)
	if mi != null and mi.mesh != mesh:
		mi.mesh = mesh

## Swaps a named GeometryInstance3D part's material only when it differs.
func set_part_material(key: String, mat: Material) -> void:
	var gi: GeometryInstance3D = parts.get(key)
	if gi != null and gi.material_override != mat:
		gi.material_override = mat
