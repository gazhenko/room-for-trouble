class_name MeshKit
extends RefCounted
## Procedural low-poly mesh builder. Flat-shaded faces with vertex colours and a
## transform stack. All game models are authored with this kit (§17.5): the
## sources are the build_* functions in src/view/models/.

var verts := PackedVector3Array()
var norms := PackedVector3Array()
var cols := PackedColorArray()
var uvs := PackedVector2Array()
var xf := Transform3D.IDENTITY
var _stack: Array = []
var jitter := 0.035
var _face := 0

func push(t: Transform3D) -> void:
	_stack.append(xf)
	xf = xf * t

func push_at(pos: Vector3, rot_deg: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> void:
	var b := Basis.from_euler(rot_deg * (PI / 180.0)).scaled(scl)
	push(Transform3D(b, pos))

func pop() -> void:
	xf = _stack.pop_back()

func _shade(c: Color) -> Color:
	_face += 1
	if jitter <= 0.0:
		return c
	var h := float(((_face * 2654435761) >> 8) & 1023) / 1023.0
	var k := 1.0 + (h - 0.5) * 2.0 * jitter
	return Color(clampf(c.r * k, 0, 1), clampf(c.g * k, 0, 1), clampf(c.b * k, 0, 1), c.a)

## Triangle given counter-clockwise when viewed from its front.
func tri(a: Vector3, b: Vector3, c: Vector3, col: Color, ua := Vector2.ZERO, ub := Vector2.ZERO, uc := Vector2.ZERO) -> void:
	var A := xf * a
	var B := xf * b
	var C := xf * c
	var n := (B - A).cross(C - A)
	if n.length_squared() < 1e-12:
		return
	n = n.normalized()
	var sc := _shade(col)
	# Godot front faces are clockwise: emit A, C, B.
	verts.append(A); verts.append(C); verts.append(B)
	norms.append(n); norms.append(n); norms.append(n)
	cols.append(sc); cols.append(sc); cols.append(sc)
	uvs.append(ua); uvs.append(uc); uvs.append(ub)

func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	tri(a, b, c, col, Vector2(0, 1), Vector2(1, 1), Vector2(1, 0))
	_face -= 1
	tri(a, c, d, col, Vector2(0, 1), Vector2(1, 0), Vector2(0, 0))

func box(center: Vector3, size: Vector3, col: Color, top_col = null, rot_y_deg := 0.0) -> void:
	push_at(center, Vector3(0, rot_y_deg, 0))
	var h := size * 0.5
	var tc: Color = col if top_col == null else top_col
	var p := [Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(-h.x, h.y, -h.z),
		Vector3(-h.x, -h.y, h.z), Vector3(h.x, -h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z)]
	quad(p[4], p[5], p[6], p[7], col)        # +z
	quad(p[1], p[0], p[3], p[2], col)        # -z
	quad(p[5], p[1], p[2], p[6], col)        # +x
	quad(p[0], p[4], p[7], p[3], col)        # -x
	quad(p[7], p[6], p[2], p[3], tc)         # +y
	quad(p[0], p[1], p[5], p[4], col.darkened(0.2))  # -y
	pop()

## Box with chamfered vertical edges (softer toy silhouette).
func rbox(center: Vector3, size: Vector3, col: Color, chamfer := 0.08, top_col = null) -> void:
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	var c := minf(chamfer, minf(hx, hz) * 0.9)
	var pts := [Vector2(-hx + c, -hz), Vector2(hx - c, -hz), Vector2(hx, -hz + c), Vector2(hx, hz - c),
		Vector2(hx - c, hz), Vector2(-hx + c, hz), Vector2(-hx, hz - c), Vector2(-hx, -hz + c)]
	prism(center, pts, size.y, col, col if top_col == null else top_col)

## Vertical prism from a 2D outline (points in increasing angle from +x toward +z).
func prism(center: Vector3, outline: Array, height: float, col: Color, top_col: Color) -> void:
	push_at(center)
	var n := outline.size()
	var y0 := -height * 0.5
	var y1 := height * 0.5
	for i in n:
		var a: Vector2 = outline[i]
		var b: Vector2 = outline[(i + 1) % n]
		quad(Vector3(b.x, y0, b.y), Vector3(a.x, y0, a.y), Vector3(a.x, y1, a.y), Vector3(b.x, y1, b.y), col)
	for i in range(1, n - 1):
		var a2: Vector2 = outline[0]
		var b2: Vector2 = outline[i]
		var c2: Vector2 = outline[i + 1]
		tri(Vector3(a2.x, y1, a2.y), Vector3(c2.x, y1, c2.y), Vector3(b2.x, y1, b2.y), top_col)
		tri(Vector3(a2.x, y0, a2.y), Vector3(b2.x, y0, b2.y), Vector3(c2.x, y0, c2.y), col.darkened(0.2))
	pop()

## Cylinder standing on `base` (centre of bottom cap).
func cyl(base: Vector3, radius: float, height: float, col: Color, seg := 8, top_col = null, r_top := -1.0) -> void:
	var rt := radius if r_top < 0.0 else r_top
	var tc: Color = col if top_col == null else top_col
	for i in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		var p0 := base + Vector3(cos(a0) * radius, 0, sin(a0) * radius)
		var p1 := base + Vector3(cos(a1) * radius, 0, sin(a1) * radius)
		var q0 := base + Vector3(cos(a0) * rt, height, sin(a0) * rt)
		var q1 := base + Vector3(cos(a1) * rt, height, sin(a1) * rt)
		quad(p1, p0, q0, q1, col)
		if rt > 0.0001:
			tri(base + Vector3(0, height, 0), q1, q0, tc)
		tri(base, p0, p1, col.darkened(0.2))

func cone(base: Vector3, radius: float, height: float, col: Color, seg := 8) -> void:
	cyl(base, radius, height, col, seg, null, 0.0)

## Faceted ellipsoid. `scl` stretches the unit sphere.
func sphere(center: Vector3, radius: float, col: Color, rings := 5, seg := 8, scl := Vector3.ONE, bottom_col = null) -> void:
	var bc: Color = col if bottom_col == null else bottom_col
	for r in rings:
		var t0 := PI * r / rings
		var t1 := PI * (r + 1) / rings
		for i in seg:
			var a0 := TAU * i / seg
			var a1 := TAU * (i + 1) / seg
			var p00 := _sp(t0, a0) * scl * radius + center
			var p01 := _sp(t0, a1) * scl * radius + center
			var p10 := _sp(t1, a0) * scl * radius + center
			var p11 := _sp(t1, a1) * scl * radius + center
			var cc: Color = col if r < rings * 0.6 else bc
			if r == 0:
				tri(p00, p11, p10, cc)
			elif r == rings - 1:
				tri(p00, p01, p10, cc)
			else:
				quad(p00, p01, p11, p10, cc)

func _sp(theta: float, phi: float) -> Vector3:
	return Vector3(sin(theta) * cos(phi), cos(theta), sin(theta) * sin(phi))

## Flat disc/ring lying on XZ at height y (for decals and pads).
func disc(center: Vector3, radius: float, col: Color, seg := 12, inner := 0.0) -> void:
	for i in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		var o0 := center + Vector3(cos(a0) * radius, 0, sin(a0) * radius)
		var o1 := center + Vector3(cos(a1) * radius, 0, sin(a1) * radius)
		if inner > 0.0:
			var i0 := center + Vector3(cos(a0) * inner, 0, sin(a0) * inner)
			var i1 := center + Vector3(cos(a1) * inner, 0, sin(a1) * inner)
			quad(i0, i1, o1, o0, col)
		else:
			tri(center, o1, o0, col)

## Flat horizontal rectangle (decals, rugs) at y.
func flat(center: Vector3, size: Vector2, col: Color, rot_y_deg := 0.0) -> void:
	push_at(center, Vector3(0, rot_y_deg, 0))
	var hx := size.x * 0.5
	var hz := size.y * 0.5
	quad(Vector3(-hx, 0, hz), Vector3(hx, 0, hz), Vector3(hx, 0, -hz), Vector3(-hx, 0, -hz), col)
	pop()

## Vertical panel facing +z (signs, pictures).
func panel(center: Vector3, size: Vector2, col: Color, rot_y_deg := 0.0) -> void:
	push_at(center, Vector3(0, rot_y_deg, 0))
	var hx := size.x * 0.5
	var hy := size.y * 0.5
	quad(Vector3(-hx, -hy, 0), Vector3(hx, -hy, 0), Vector3(hx, hy, 0), Vector3(-hx, hy, 0), col)
	pop()

## Torus lying on XZ (rings, bells' lips, wreaths).
func torus(center: Vector3, r_major: float, r_minor: float, col: Color, seg := 10, sides := 4) -> void:
	for i in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		for j in sides:
			var b0 := TAU * j / sides
			var b1 := TAU * (j + 1) / sides
			var p := func(a: float, b: float) -> Vector3:
				var r := r_major + r_minor * cos(b)
				return center + Vector3(cos(a) * r, r_minor * sin(b), sin(a) * r)
			quad(p.call(a0, b0), p.call(a0, b1), p.call(a1, b1), p.call(a1, b0), col)

func is_empty() -> bool:
	return verts.is_empty()

func commit() -> ArrayMesh:
	var m := ArrayMesh.new()
	if verts.is_empty():
		return m
	var arr: Array = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_TEX_UV] = uvs
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m

func clear() -> void:
	verts = PackedVector3Array(); norms = PackedVector3Array(); cols = PackedColorArray(); uvs = PackedVector2Array()
	xf = Transform3D.IDENTITY
	_stack.clear()
