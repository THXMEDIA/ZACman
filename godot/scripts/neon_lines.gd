extends RefCounted
## NeonLines — the line builder of the Tokyo line city (docs/design/
## tokyo-explorer.md): collects neon tubes (thin boxes from a to b) and
## bundles them per color into ONE mesh with ONE material
## (shaders/neon_line.gdshader), so the whole static city costs a handful of
## draw calls no matter how many lines it has. A per-line brightness factor
## travels in UV.x (edges, floor bands, base line and background share a
## color mesh). Pure data until build(): tests can count and hash the lines
## without a renderer (signature()).
##
## Also a tiny triangle batch (TriBatch) for the other merged static meshes
## of the city (black mass, road paint, shop fronts).

const LINE_SHADER := preload("res://shaders/neon_line.gdshader")

## color key -> {color: Color, energy: float, verts: PackedVector3Array,
## uvs: PackedVector2Array, idx: PackedInt32Array, count: int}
var groups := {}
var _order: Array = [] # keys in definition order (deterministic build order)


func define(key: String, color: Color, energy: float) -> void:
	if groups.has(key):
		return
	groups[key] = {"color": color, "energy": energy, "verts": PackedVector3Array(), "uvs": PackedVector2Array(), "idx": PackedInt32Array(), "count": 0}
	_order.append(key)


## One neon tube from a to b, `thick` m square, brightness factor `mul`.
func line(a: Vector3, b: Vector3, key: String, thick: float, mul: float = 1.0) -> void:
	var d := b - a
	var length := d.length()
	if length < 0.001:
		return
	var g: Dictionary = groups[key]
	var y := d / length
	var x := y.cross(Vector3.UP)
	if x.length() < 0.01:
		x = y.cross(Vector3.RIGHT)
	x = x.normalized() * (thick * 0.5)
	var z := x.cross(y).normalized() * (thick * 0.5)
	var verts: PackedVector3Array = g.verts
	var base := verts.size()
	for p in [a, b]:
		verts.append(p - x - z)
		verts.append(p + x - z)
		verts.append(p + x + z)
		verts.append(p - x + z)
	var uvs: PackedVector2Array = g.uvs
	for i in 8:
		uvs.append(Vector2(mul, 0.0))
	var idx: PackedInt32Array = g.idx
	# four sides (the tube is open at its ends — the lines meet or overlap)
	for s in 4:
		var a0 := base + s
		var a1 := base + (s + 1) % 4
		var b0 := a0 + 4
		var b1 := a1 + 4
		idx.append_array([a0, a1, b1, a0, b1, b0])
	g.verts = verts
	g.uvs = uvs
	g.idx = idx
	g.count += 1


## Lines through `points`, optionally closed into a loop.
func polyline(points: Array, key: String, thick: float, mul: float = 1.0, closed: bool = false) -> void:
	for i in range(points.size() - 1):
		line(points[i], points[i + 1], key, thick, mul)
	if closed and points.size() > 2:
		line(points[points.size() - 1], points[0], key, thick, mul)


## Arc around `center` in the plane of ax1/ax2 (radians a0..a1).
func arc(center: Vector3, ax1: Vector3, ax2: Vector3, r: float, segs: int, a0: float, a1: float, key: String, thick: float, mul: float = 1.0) -> void:
	var pts := []
	for i in segs + 1:
		var a := a0 + (a1 - a0) * float(i) / segs
		pts.append(center + (ax1 * cos(a) + ax2 * sin(a)) * r)
	polyline(pts, key, thick, mul)


func segment_count(key: String = "") -> int:
	if key != "":
		return int(groups[key].count) if groups.has(key) else 0
	var n := 0
	for k in groups:
		n += int(groups[k].count)
	return n


## A hash over every vertex of every color, in build order — equal for two
## identically built cities, different as soon as one line moves (tests).
func signature() -> int:
	var h := 17
	for k in _order:
		var g: Dictionary = groups[k]
		h = hash([h, k, g.count, hash(g.verts), hash(g.uvs)])
	return h


## One MeshInstance3D per color that has lines, added to `parent`.
func build(parent: Node3D, fade_h: float, top_mul: float) -> Array:
	var out := []
	for k in _order:
		var g: Dictionary = groups[k]
		if g.count == 0:
			continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = g.verts
		arrays[Mesh.ARRAY_TEX_UV] = g.uvs
		arrays[Mesh.ARRAY_INDEX] = g.idx
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var mat := ShaderMaterial.new()
		mat.shader = LINE_SHADER
		mat.set_shader_parameter("line_color", g.color)
		mat.set_shader_parameter("energy", g.energy)
		mat.set_shader_parameter("fade_h", fade_h)
		mat.set_shader_parameter("top_mul", top_mul)
		var mi := MeshInstance3D.new()
		mi.name = "Neon_" + k
		mi.mesh = mesh
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mi)
		out.append(mi)
	return out


## ---- TriBatch: merged static triangles with UVs ----

class TriBatch:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()

	## Quad p0-p1-p2-p3 (in order around), with UVs.
	func quad(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, uv0 := Vector2(0, 0), uv1 := Vector2(1, 0), uv2 := Vector2(1, 1), uv3 := Vector2(0, 1)) -> void:
		var b := verts.size()
		verts.append_array([p0, p1, p2, p3])
		uvs.append_array([uv0, uv1, uv2, uv3])
		idx.append_array([b, b + 1, b + 2, b, b + 2, b + 3])

	## Flat rectangle on the floor (y), x0..x1 / z0..z1.
	func floor_rect(x0: float, x1: float, z0: float, z1: float, y: float) -> void:
		quad(Vector3(x0, y, z0), Vector3(x1, y, z0), Vector3(x1, y, z1), Vector3(x0, y, z1))

	## Rectangle on the floor along an arbitrary direction (center, unit
	## direction, length along it, width across it).
	func floor_strip(center: Vector3, dir: Vector3, length: float, width: float) -> void:
		var d := dir.normalized() * (length * 0.5)
		var s := Vector3(-dir.z, 0.0, dir.x).normalized() * (width * 0.5)
		quad(center - d - s, center + d - s, center + d + s, center - d + s)

	## Closed axis-aligned box (all six faces).
	func box(x0: float, x1: float, y0: float, y1: float, z0: float, z1: float) -> void:
		var p := [Vector3(x0, y0, z0), Vector3(x1, y0, z0), Vector3(x1, y0, z1), Vector3(x0, y0, z1),
			Vector3(x0, y1, z0), Vector3(x1, y1, z0), Vector3(x1, y1, z1), Vector3(x0, y1, z1)]
		quad(p[0], p[1], p[5], p[4])
		quad(p[1], p[2], p[6], p[5])
		quad(p[2], p[3], p[7], p[6])
		quad(p[3], p[0], p[4], p[7])
		quad(p[4], p[5], p[6], p[7])
		quad(p[3], p[2], p[1], p[0])

	## Vertical prism over a closed floor polygon, bottom y0, top per corner
	## (`tops`, same length as `poly`) — e.g. a slanted crown.
	func prism(poly: Array, y0: float, tops: Array) -> void:
		var n := poly.size()
		for i in n:
			var a: Vector3 = poly[i]
			var b: Vector3 = poly[(i + 1) % n]
			quad(Vector3(a.x, y0, a.z), Vector3(b.x, y0, b.z), Vector3(b.x, tops[(i + 1) % n], b.z), Vector3(a.x, tops[i], a.z))
		var c := Vector3.ZERO
		var ct := 0.0
		for i in n:
			c += poly[i]
			ct += tops[i]
		c /= n
		var top_c := Vector3(c.x, ct / n, c.z)
		for i in n:
			var a2: Vector3 = poly[i]
			var b2: Vector3 = poly[(i + 1) % n]
			var b0 := verts.size()
			verts.append_array([top_c, Vector3(a2.x, tops[i], a2.z), Vector3(b2.x, tops[(i + 1) % n], b2.z)])
			uvs.append_array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
			idx.append_array([b0, b0 + 1, b0 + 2])

	func is_empty() -> bool:
		return verts.is_empty()

	func signature() -> int:
		return hash([hash(verts), hash(uvs)])

	func to_instance(name: String, mat: Material) -> MeshInstance3D:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_INDEX] = idx
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var mi := MeshInstance3D.new()
		mi.name = name
		mi.mesh = mesh
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		return mi
