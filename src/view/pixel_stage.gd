class_name PixelStage
extends SubViewportContainer
## Pixel-art 3D presentation (DECISIONS.md D-002/D-003): the world renders into
## a SubViewport at ~360 lines, upscaled by an integer factor with nearest
## filtering, through a fixed high-angle perspective camera (Overcooked-style)
## that is fitted to the whole floor from the actual projected bounds (§17.2).

signal fitted

const PITCH_DEG := 53.0
const FOV_DEG := 30.0
const SAFE_X := 0.965
const SAFE_TOP := 0.86
const SAFE_BOTTOM := -0.92

var viewport: SubViewport
var world: Node3D
var camera: Camera3D
var sun: DirectionalLight3D
var env: WorldEnvironment
var post: MeshInstance3D
var target_lines := 360
var bounds_min := Vector3(-1.6, 0.0, -1.4)
var bounds_max := Vector3(28.6, 0.6, 20.6)
var dynamic_offset := Vector3.ZERO
var pitch_deg := PITCH_DEG
var fov_deg := FOV_DEG
var safe_top := SAFE_TOP
var safe_bottom := SAFE_BOTTOM
var _base_xf := Transform3D()
var _last_size := Vector2i.ZERO

func _init() -> void:
	stretch = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	viewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	viewport.positional_shadow_atlas_size = 0
	viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	viewport.audio_listener_enable_3d = false
	add_child(viewport)
	world = Node3D.new()
	world.name = "World"
	viewport.add_child(world)
	camera = Camera3D.new()
	camera.fov = FOV_DEG
	camera.near = 1.0
	camera.far = 120.0
	camera.current = true
	viewport.add_child(camera)
	sun = DirectionalLight3D.new()
	sun.light_color = Color("#FFF2DC")
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	sun.shadow_blur = 0.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 80.0
	sun.rotation_degrees = Vector3(-56.0, -38.0, 0.0)
	viewport.add_child(sun)
	env = WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("#9DBF8A")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	e.glow_enabled = false
	e.ssao_enabled = false
	env.environment = e
	viewport.add_child(env)
	post = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	post.mesh = q
	var pm := ShaderMaterial.new()
	pm.shader = preload("res://src/view/shaders/outline_post.gdshader")
	post.material_override = pm
	post.extra_cull_margin = 16384.0
	post.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	post.custom_aabb = AABB(Vector3(-1e4, -1e4, -1e4), Vector3(2e4, 2e4, 2e4))
	camera.add_child(post)
	post.position = Vector3(0, 0, -2.0)
	# The outline pass reads the normal buffer, which only Forward+ provides.
	if RenderingServer.get_current_rendering_method() != "forward_plus":
		post.visible = false

func _ready() -> void:
	resized.connect(_apply_scale)
	get_viewport().size_changed.connect(_apply_scale)
	_apply_scale()

func set_pixel_lines(lines: int) -> void:
	target_lines = lines
	_apply_scale()

## Graphics quality: "low" drops the sun's shadow pass (and with it about a
## sixth of the floor's draw calls) for integrated GPUs and handhelds.
func set_quality(q: String) -> void:
	sun.shadow_enabled = q != "low"

func set_outlines(on: bool) -> void:
	(post.material_override as ShaderMaterial).set_shader_parameter("enabled", 1.0 if on else 0.0)
	post.visible = on and RenderingServer.get_current_rendering_method() == "forward_plus"

func pixel_factor() -> int:
	var h := get_viewport().get_visible_rect().size.y
	var win := DisplayServer.window_get_size()
	var real_h := float(win.y) if win.y > 0 else h
	if target_lines <= 0:
		return 1
	return maxi(1, int(round(real_h / float(target_lines))))

func _apply_scale() -> void:
	if custom_minimum_size != Vector2.ZERO:
		# Embedded stage (photos, postcards): pixel size from its own height.
		var sh := maxi(1, int(round(size.y / float(maxi(1, target_lines)))))
		if stretch_shrink != sh:
			stretch_shrink = sh
		fit_camera()
		return
	# Integer shrink relative to the real window pixels (canvas stretch aside).
	var f := pixel_factor()
	var win := DisplayServer.window_get_size()
	var canvas_h := get_viewport().get_visible_rect().size.y
	var canvas_scale := float(win.y) / maxf(1.0, canvas_h) if win.y > 0 else 1.0
	var shrink := maxi(1, int(round(f / maxf(0.01, canvas_scale))))
	if stretch_shrink != shrink:
		stretch_shrink = shrink
	fit_camera()

func set_bounds(mn: Vector3, mx: Vector3) -> void:
	bounds_min = mn
	bounds_max = mx
	fit_camera()

func _corners() -> Array:
	var pts: Array = []
	for x in [bounds_min.x, bounds_max.x]:
		for y in [bounds_min.y, bounds_max.y]:
			for z in [bounds_min.z, bounds_max.z]:
				pts.append(Vector3(x, y, z))
	pts.append(Vector3(bounds_min.x + 1.5, 2.4, bounds_min.z + 1.7))
	pts.append(Vector3(bounds_max.x - 1.5, 2.4, bounds_min.z + 1.7))
	return pts

func _project(xf: Transform3D, p: Vector3, tan_v: float, aspect: float) -> Vector2:
	var v := xf.affine_inverse() * p
	var depth := -v.z
	if depth <= 0.01:
		return Vector2(99, 99)
	return Vector2(v.x / depth / (tan_v * aspect), v.y / depth / tan_v)

func fit_camera() -> void:
	var vs := viewport.size
	if vs.x <= 0 or vs.y <= 0:
		return
	var aspect := float(vs.x) / float(vs.y)
	camera.fov = fov_deg
	var tan_v := tan(deg_to_rad(fov_deg) * 0.5)
	var pitch := deg_to_rad(pitch_deg)
	var back := Vector3(0, sin(pitch), cos(pitch))
	var target := Vector3((bounds_min.x + bounds_max.x) * 0.5, 0.0, (bounds_min.z + bounds_max.z) * 0.5)
	var pts := _corners()
	var dist := 40.0
	for it in 4:
		var lo := 5.0
		var hi := 200.0
		for k in 40:
			var mid := (lo + hi) * 0.5
			var xf := _cam_xf(target, back, mid)
			var ok := true
			var ymin := 99.0
			var ymax := -99.0
			for p in pts:
				var n := _project(xf, p, tan_v, aspect)
				if absf(n.x) > SAFE_X:
					ok = false
				ymin = minf(ymin, n.y)
				ymax = maxf(ymax, n.y)
			if ymax - ymin > safe_top - safe_bottom:
				ok = false
			if ok:
				hi = mid
			else:
				lo = mid
		dist = hi
		# Re-centre vertically inside the safe band.
		var xf2 := _cam_xf(target, back, dist)
		var y0 := 99.0
		var y1 := -99.0
		for p in pts:
			var n2 := _project(xf2, p, tan_v, aspect)
			y0 = minf(y0, n2.y)
			y1 = maxf(y1, n2.y)
		var want_mid := (safe_top + safe_bottom) * 0.5
		var cur_mid := (y0 + y1) * 0.5
		target.z += (want_mid - cur_mid) * dist * tan_v * 0.9
	_base_xf = _cam_xf(target, back, dist)
	camera.transform = _base_xf
	_last_size = vs
	fitted.emit()

func _cam_xf(target: Vector3, back: Vector3, dist: float) -> Transform3D:
	var pos := target + back * dist
	return Transform3D(Basis(), pos).looking_at(target, Vector3.UP)

func _process(_dt: float) -> void:
	if viewport.size != _last_size:
		fit_camera()
	camera.transform = Transform3D(_base_xf.basis, _base_xf.origin + dynamic_offset)

## Projects a world point to canvas coordinates of this control (for HUD overlay).
func world_to_screen(p: Vector3) -> Vector2:
	if camera.is_position_behind(p):
		return Vector2(-9999, -9999)
	var vp := camera.unproject_position(p)
	var scale_f := size / Vector2(viewport.size)
	return vp * scale_f
