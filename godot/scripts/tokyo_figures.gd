extends RefCounted
## TokyoFigures — the meshes of the moving Tokyo line city (docs/design/
## tokyo-explorer.md, M2). Every one is drawn as ONE MultiMesh by
## tokyo_life.gd; animation happens in the shaders (INSTANCE_CUSTOM), the
## CPU only moves instance transforms.
##   car_mesh()     wire car: body lines, white headlights at the front
##                  (-Z), red tail lights at the back; COLOR = line color,
##                  UV.x = brightness, UV.y = part (0 body, 1 head, 2 tail)
##   walker_mesh()  line figure with umbrella; UV.y = part for the gait in
##                  shaders/tokyo_walker.gdshader (see WALKER_* below)
##   cone_mesh()    open light cone, apex at the origin, base circle (r 1)
##                  at y = -1; UV.y 0 at the apex, 1 at the base
## Local frame of cars and walkers: forward -Z, up +Y, origin on the floor.

## Walker parts (UV.y), animated in tokyo_walker.gdshader.
const WALKER_BODY := 0.0
const WALKER_LEG_L := 1.0
const WALKER_LEG_R := 2.0
const WALKER_ARM_L := 3.0
const WALKER_ARM_R := 4.0 # free arm, only without umbrella
const WALKER_UMBRELLA := 5.0 # canopy and stick, only with umbrella
const WALKER_ARM_UMB := 6.0 # arm holding the umbrella, only with umbrella
const HIP_Y := 0.92
const SHOULDER_Y := 1.43

const CAR_HALF_LEN := 2.2
const CAR_HALF_WID := 0.9
## Light positions in the car's local frame (left/right mirrored in x).
const CAR_HEAD := Vector3(0.62, 0.72, -2.23)
const CAR_TAIL := Vector3(0.62, 0.85, 2.23)


class Tubes:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()

	## Square tube from a to b (open ends), `thick` m wide.
	func line(a: Vector3, b: Vector3, thick: float, col: Color, mul: float, part: float) -> void:
		var d := b - a
		var length := d.length()
		if length < 0.0005:
			return
		var y := d / length
		var x := y.cross(Vector3.UP)
		if x.length() < 0.01:
			x = y.cross(Vector3.RIGHT)
		x = x.normalized() * (thick * 0.5)
		var z := x.cross(y).normalized() * (thick * 0.5)
		var base := verts.size()
		for p in [a, b]:
			verts.append(p - x - z)
			verts.append(p + x - z)
			verts.append(p + x + z)
			verts.append(p - x + z)
		var ns := [(-x - z).normalized(), (x - z).normalized(), (x + z).normalized(), (-x + z).normalized()]
		for k in 2:
			for n in ns:
				normals.append(n)
		for i in 8:
			colors.append(col)
			uvs.append(Vector2(mul, part))
		for s in 4:
			var a0 := base + s
			var a1 := base + (s + 1) % 4
			idx.append_array([a0, a1, a1 + 4, a0, a1 + 4, a0 + 4])

	func ring(center: Vector3, ax1: Vector3, ax2: Vector3, r: float, segs: int, thick: float, col: Color, mul: float, part: float) -> void:
		var prev := center + ax1 * r
		for i in range(1, segs + 1):
			var a := TAU * i / segs
			var p := center + (ax1 * cos(a) + ax2 * sin(a)) * r
			line(prev, p, thick, col, mul, part)
			prev = p

	func to_mesh() -> ArrayMesh:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_INDEX] = idx
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return mesh


## Wire car after the approved prototype (natriumregen): box body, cabin,
## four wheels, white headlights in front, red tail lights at the back.
static func car_mesh(body: Color, head: Color, tail: Color) -> ArrayMesh:
	var t := Tubes.new()
	var th := 0.045
	var hl := CAR_HALF_LEN
	var hw := CAR_HALF_WID
	# P(forward, right, up): forward is -Z
	var P := func(fr: float, rr: float, uu: float) -> Vector3: return Vector3(rr, uu, -fr)
	for uu in [0.35, 0.95]:
		t.line(P.call(hl, -hw, uu), P.call(hl, hw, uu), th, body, 1.0, 0.0)
		t.line(P.call(-hl, -hw, uu), P.call(-hl, hw, uu), th, body, 1.0, 0.0)
		t.line(P.call(hl, -hw, uu), P.call(-hl, -hw, uu), th, body, 1.0, 0.0)
		t.line(P.call(hl, hw, uu), P.call(-hl, hw, uu), th, body, 1.0, 0.0)
	for fr in [hl, -hl]:
		for rr in [-hw, hw]:
			t.line(P.call(fr, rr, 0.35), P.call(fr, rr, 0.95), th, body, 1.0, 0.0)
	for rr in [-0.82, 0.82]:
		t.line(P.call(1.0, rr, 0.95), P.call(0.35, rr, 1.45), th, body, 1.0, 0.0)
		t.line(P.call(0.35, rr, 1.45), P.call(-1.1, rr, 1.45), th, body, 1.0, 0.0)
		t.line(P.call(-1.1, rr, 1.45), P.call(-1.6, rr, 0.95), th, body, 1.0, 0.0)
	t.line(P.call(0.35, -0.82, 1.45), P.call(0.35, 0.82, 1.45), th, body, 1.0, 0.0)
	t.line(P.call(-1.1, -0.82, 1.45), P.call(-1.1, 0.82, 1.45), th, body, 1.0, 0.0)
	for fr in [1.4, -1.4]:
		for rr in [-0.92, 0.92]:
			t.ring(P.call(fr, rr, 0.33), Vector3(0, 0, -1), Vector3.UP, 0.32, 10, th, body, 0.8, 0.0)
	for rr in [-CAR_HEAD.x, CAR_HEAD.x]:
		t.line(P.call(hl + 0.03, rr - 0.18, CAR_HEAD.y), P.call(hl + 0.03, rr + 0.18, CAR_HEAD.y), 0.12, head, 1.0, 1.0)
		t.line(P.call(-hl - 0.03, rr - 0.22, CAR_TAIL.y), P.call(-hl - 0.03, rr + 0.22, CAR_TAIL.y), 0.11, tail, 1.0, 2.0)
	return t.to_mesh()


## Line figure (1.75 m) with an umbrella, after the prototype: legs and
## arms are separate parts so the shader can swing them around hip and
## shoulder. Both arm variants are in the mesh; the shader hides the one
## that does not fit the instance (umbrella or not).
static func walker_mesh(col: Color) -> ArrayMesh:
	var t := Tubes.new()
	var th := 0.026
	var f := Vector3(0, 0, -1)
	var r := Vector3(1, 0, 0)
	var u := Vector3.UP
	var hip := u * HIP_Y
	var sh := u * SHOULDER_Y
	# legs (straight down from the hip; the shader swings them)
	t.line(hip + r * 0.1, r * 0.12, th, col, 1.0, WALKER_LEG_R)
	t.line(hip - r * 0.1, -r * 0.12, th, col, 1.0, WALKER_LEG_L)
	# torso
	t.line(hip + r * 0.12, sh + r * 0.2, th, col, 1.0, WALKER_BODY)
	t.line(hip - r * 0.12, sh - r * 0.2, th, col, 1.0, WALKER_BODY)
	t.line(hip + r * 0.12, hip - r * 0.12, th, col, 1.0, WALKER_BODY)
	t.line(sh + u * 0.02 + r * 0.22, sh + u * 0.02 - r * 0.22, th, col, 1.0, WALKER_BODY)
	t.ring(u * 1.64, r, u, 0.11, 10, th, col, 1.0, WALKER_BODY)
	# arms
	t.line(sh - r * 0.22, u * 0.95 - r * 0.3, th, col, 1.0, WALKER_ARM_L)
	t.line(sh + r * 0.22, u * 0.95 + r * 0.3, th, col, 1.0, WALKER_ARM_R)
	var hand := u * 1.15 + f * 0.25 + r * 0.05
	t.line(sh + r * 0.22, hand, th, col, 1.0, WALKER_ARM_UMB)
	# umbrella: canopy ring, six ribs, stick
	var apex := u * 2.18 + f * 0.12
	var rc := u * 1.92 + f * 0.12
	var ur := 0.56
	t.ring(rc, r, f, ur, 16, th, col, 1.0, WALKER_UMBRELLA)
	for i in 6:
		var a := TAU * i / 6.0
		t.line(apex, rc + (r * cos(a) + f * sin(a)) * ur, th * 0.8, col, 0.9, WALKER_UMBRELLA)
	t.line(apex, hand, th * 0.8, col, 0.9, WALKER_UMBRELLA)
	return t.to_mesh()


## Open cone for light beams: apex at the origin, unit base at y = -1.
static func cone_mesh(segs: int = 16) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	for i in segs + 1:
		var a := TAU * i / segs
		var dir := Vector3(cos(a), 0, sin(a))
		var n := (dir + Vector3(0, 1, 0)).normalized()
		verts.append(Vector3.ZERO)
		normals.append(n)
		uvs.append(Vector2(float(i) / segs, 0.0))
		verts.append(Vector3(dir.x, -1.0, dir.z))
		normals.append(n)
		uvs.append(Vector2(float(i) / segs, 1.0))
	for i in segs:
		var a0 := i * 2
		idx.append_array([a0, a0 + 1, a0 + 3, a0, a0 + 3, a0 + 2])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Transform of a cone instance from `from` (apex) to `to` (base center),
## base radius `radius`.
static func cone_transform(from: Vector3, to: Vector3, radius: float) -> Transform3D:
	var d := to - from
	var length := d.length()
	var y := -d / length # local -Y points from apex to base
	var x := y.cross(Vector3.UP)
	if x.length() < 0.01:
		x = y.cross(Vector3.RIGHT)
	x = x.normalized()
	var z := x.cross(y).normalized()
	return Transform3D(Basis(x * radius, y * length, z * radius), from)
