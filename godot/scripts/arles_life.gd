extends Node3D
## ArlesLife — the passers-by of the Arles night city (Abnahme 06.10.2026):
## evening figures in coat and hat, painted with the city's impasto brush
## (shaders/arles_walker.gdshader), who stroll slowly through the lanes and
## squares: pairs along the Rhône quay, round the Mistral monument, past the
## café terrace, a few round the arena ring. The static figures of the café
## scene (arles_scenery.gd FIGURES) stay where they are.
##
## Draw calls: ONE MultiMesh for all of them, whatever their number. The gait
## is animated in the shader (INSTANCE_CUSTOM), the CPU only moves instance
## transforms and allocates nothing per frame (all state lives in packed
## arrays, no node per figure, no mesh rebuild; tests/test_arles.gd counts it).
## Everything is built in map space under the "City" node (world + (1, 0, 1)).
##
## Every walker follows a closed polyline (out and back on the two sides of a
## lane, or a loop round a monument) as a pure function of the time: same seed
## and same steps -> same people. They are slow (0.5-0.9 m/s, stride well below
## 1 Hz: far below the 3 Hz flicker limit), harmless (Main gives them the same
## soft push as Tokyo's passers-by, never a lost life, never the camera) and
## stand still with "Effekte reduzieren" (set_reduce_fx).

const Style := preload("res://scripts/arles_style.gd")

const MAP_SHIFT := Vector3(1.0, 0.0, 1.0)
## Half width of the out-and-back loop of a lane (m).
const LANE_HALF := 0.45
## Side by side: lateral offset of the two members of a pair (m).
const PAIR_HALF := 0.32
const SPEED_MIN := 0.5
const SPEED_MAX := 0.9
## Metres walked per gait cycle (two steps); stride frequency = speed / this.
const STRIDE := 1.1

## Where they walk (map space x, z). Lanes are straight (out and back round
## LANE_HALF), loops are closed shapes; `n` walkers, `pair` makes the first two
## walk side by side. The tests keep every walker 0.5 m off every obstacle
## and 0.85 m off every wall, away from the start and the exit.
const LANES := [
	{"id": "calade", "a": Vector2(44.0, 71.0), "b": Vector2(60.0, 71.0), "n": 2, "pair": true},
	{"id": "republique", "a": Vector2(20.5, 67.0), "b": Vector2(30.5, 67.0), "n": 2, "pair": false},
	{"id": "hotel_de_ville", "a": Vector2(27.0, 54.0), "b": Vector2(27.0, 62.0), "n": 2, "pair": false},
	{"id": "terrasse", "a": Vector2(22.5, 37.4), "b": Vector2(33.0, 37.4), "n": 2, "pair": false},
	{"id": "rue_forum_west", "a": Vector2(12.5, 40.8), "b": Vector2(25.0, 40.8), "n": 2, "pair": false},
	{"id": "rue_forum_ost", "a": Vector2(40.0, 41.2), "b": Vector2(46.5, 41.2), "n": 1, "pair": false},
	{"id": "quai_nord", "a": Vector2(7.0, 10.0), "b": Vector2(7.0, 23.0), "n": 1, "pair": false},
	{"id": "quai_mitte", "a": Vector2(7.0, 29.0), "b": Vector2(7.0, 41.0), "n": 2, "pair": true},
	{"id": "quai_sued", "a": Vector2(7.0, 47.0), "b": Vector2(7.0, 57.0), "n": 1, "pair": false},
	{"id": "lamartine", "a": Vector2(9.0, 7.3), "b": Vector2(26.0, 7.3), "n": 3, "pair": false},
	{"id": "rue_cavalerie", "a": Vector2(51.0, 5.0), "b": Vector2(51.0, 21.5), "n": 2, "pair": false},
	{"id": "porte_cavalerie", "a": Vector2(38.5, 10.4), "b": Vector2(46.0, 10.4), "n": 1, "pair": false},
	{"id": "seitengasse", "a": Vector2(12.5, 20.0), "b": Vector2(27.0, 20.0), "n": 1, "pair": false},
]
## Closed loops: the walk round the Mistral monument and the arena ring.
const LOOPS := [
	{"id": "statue", "kind": "circle", "c": Vector2(31.0, 45.0), "r": 3.6, "n": 3, "pair": true},
	{"id": "arenes", "kind": "rect", "x0": 51.0, "z0": 27.0, "x1": 85.0, "z1": 63.0, "r": 3.0, "n": 6, "pair": true},
]

var seed_value := 0
var time := 0.0 # seconds walked (stands still with reduced effects)
var mmi: MultiMeshInstance3D = null
var material: ShaderMaterial = null

# paths: flat segment arrays (closed polylines)
var seg_a := PackedVector2Array()
var seg_d := PackedVector2Array()
var seg_s := PackedFloat32Array() # path position of the segment start
var seg_l := PackedFloat32Array()
var path_first := PackedInt32Array()
var path_segs := PackedInt32Array()
var path_len := PackedFloat32Array()
var path_ids: Array = []

# walkers
var w_path := PackedInt32Array()
var w_s0 := PackedFloat32Array()
var w_speed := PackedFloat32Array()
var w_lat := PackedFloat32Array()
var w_phase := PackedFloat32Array()
var w_look := PackedFloat32Array() # coat index + hat colour / 10
var w_hat := PackedFloat32Array()
var w_scale := PackedFloat32Array()
var gait_sent := PackedFloat32Array() # stride frequency last sent to the shader (tests)
var w_pos := PackedVector3Array() # map space
var w_dir := PackedVector2Array()

var _moving := true


## ---------------------------------------------------------------- paths

## Closed out-and-back loop round the lane a -> b (half width h): along the
## +n side to b, a half circle round b, back along the -n side, a half circle
## round a.
static func lane_loop(a: Vector2, b: Vector2, h: float) -> PackedVector2Array:
	var d := (b - a).normalized()
	var n := Vector2(-d.y, d.x)
	var out := PackedVector2Array()
	out.append(a + n * h)
	out.append(b + n * h)
	for k in range(1, 5):
		var ang := PI * float(k) / 5.0
		out.append(b + (n * cos(ang) + d * sin(ang)) * h)
	out.append(b - n * h)
	out.append(a - n * h)
	for k in range(1, 5):
		var ang := PI * float(k) / 5.0
		out.append(a + (-n * cos(ang) - d * sin(ang)) * h)
	return out


static func circle_loop(c: Vector2, r: float, segs: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in segs:
		var ang := TAU * float(i) / float(segs)
		out.append(c + Vector2(cos(ang), sin(ang)) * r)
	return out


## Rounded rectangle (corner radius r), clockwise seen from above (+x east, +z south).
static func rect_loop(x0: float, z0: float, x1: float, z1: float, r: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var corners := [
		[Vector2(x1 - r, z0 + r), -PI / 2.0],
		[Vector2(x1 - r, z1 - r), 0.0],
		[Vector2(x0 + r, z1 - r), PI / 2.0],
		[Vector2(x0 + r, z0 + r), PI],
	]
	for c in corners:
		var ctr: Vector2 = c[0]
		var a0: float = c[1]
		for k in 6:
			var ang := a0 + (PI / 2.0) * float(k) / 5.0
			out.append(ctr + Vector2(cos(ang), sin(ang)) * r)
	return out


## Every path of the city as [id, polyline, walkers, pair].
static func path_defs() -> Array:
	var out: Array = []
	for l in LANES:
		out.append([l.id, lane_loop(l.a, l.b, LANE_HALF), int(l.n), bool(l.pair)])
	for l in LOOPS:
		var pts: PackedVector2Array
		if l.kind == "circle":
			pts = circle_loop(l.c, l.r, 24)
		else:
			pts = rect_loop(l.x0, l.z0, l.x1, l.z1, l.r)
		out.append([l.id, pts, int(l.n), bool(l.pair)])
	return out


static func total_walkers() -> int:
	var n := 0
	for d in path_defs():
		n += int(d[2])
	return n


## ---------------------------------------------------------------- mesh

class Kit:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()

	## Surface of revolution round the Y axis through c; profile = [[y, r], ...]
	## from the bottom to the top (front faces look outwards, clockwise).
	func lathe(c: Vector3, profile: Array, segs: int, mat: float, part: float, sx := 1.0, sz := 1.0) -> void:
		var n := profile.size()
		var base := verts.size()
		for i in n:
			var i0 := maxi(i - 1, 0)
			var i1 := mini(i + 1, n - 1)
			var dy: float = profile[i1][0] - profile[i0][0]
			var dr: float = profile[i1][1] - profile[i0][1]
			var nr := dy
			var ny := -dr
			var l := maxf(sqrt(nr * nr + ny * ny), 0.00001)
			nr /= l
			ny /= l
			var y: float = profile[i][0]
			var r: float = profile[i][1]
			for j in segs + 1:
				var a := TAU * float(j) / float(segs)
				var ca := cos(a)
				var sa := sin(a)
				verts.append(c + Vector3(ca * r * sx, y, sa * r * sz))
				norms.append(Vector3(ca * nr / maxf(sx, 0.01), ny, sa * nr / maxf(sz, 0.01)).normalized())
				uvs.append(Vector2(mat, part))
		for i in n - 1:
			for j in segs:
				var a0 := base + i * (segs + 1) + j
				var a1 := a0 + 1
				var b0 := a0 + segs + 1
				var b1 := b0 + 1
				idx.append_array([a0, a1, b0, a1, b1, b0])

	## Sphere (ellipsoid with sx, sy, sz) as a lathe, bottom to top.
	func ball(c: Vector3, radius: float, mat: float, part: float, sx := 1.0, sy := 1.0, sz := 1.0, rings := 8, segs := 10, top_only := -1.0) -> void:
		var prof: Array = []
		var theta0 := PI if top_only < 0.0 else top_only
		for k in rings + 1:
			var th := theta0 * (1.0 - float(k) / float(rings))
			prof.append([cos(th) * radius * sy, sin(th) * radius])
		lathe(c, prof, segs, mat, part, sx, sz)

	func to_mesh() -> ArrayMesh:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = norms
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_INDEX] = idx
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return mesh


## One figure in coat and hat (1.7 m, feet on y = 0, facing -Z). The shader
## swings the parts (UV.y) and picks the hat type; UV.x is the material.
static func walker_mesh() -> ArrayMesh:
	var k := Kit.new()
	# coat: a long mantel, flattened front to back
	var coat: Array = [[0.20, 0.30], [0.45, 0.27], [0.80, 0.215], [1.00, 0.20], [1.20, 0.215], [1.38, 0.23], [1.47, 0.17], [1.52, 0.075]]
	k.lathe(Vector3.ZERO, coat, 12, 0.0, 0.0, 1.0, 0.78)
	# arms: sleeves hanging at the sides, hands, swing round the shoulder
	for s in [-1.0, 1.0]:
		var part := 3.0 if s < 0.0 else 4.0
		var sleeve: Array = [[1.37, 0.065], [1.10, 0.052], [0.86, 0.042]]
		k.lathe(Vector3(0.265 * s, 0.0, 0.0), sleeve, 8, 0.0, part)
		k.ball(Vector3(0.265 * s, 0.82, 0.0), 0.045, 1.0, part, 1.0, 1.0, 1.0, 5, 8)
	# feet
	for s in [-1.0, 1.0]:
		var part := 1.0 if s < 0.0 else 2.0
		k.ball(Vector3(0.10 * s, 0.06, -0.05), 0.07, 4.0, part, 0.8, 0.7, 1.7, 5, 8)
	# head, hair, hats
	k.ball(Vector3(0.0, 1.61, 0.0), 0.115, 1.0, 0.0, 1.0, 1.0, 1.0, 8, 12)
	# hair: a cap on top and at the back, the face stays free
	k.ball(Vector3(0.0, 1.635, 0.035), 0.12, 3.0, 7.0, 1.0, 1.0, 1.0, 5, 12, deg_to_rad(105.0))
	# brim: a thin disc (bottom face, rim, top face)
	var brim: Array = [[1.692, 0.10], [1.692, 0.23], [1.708, 0.23], [1.708, 0.10]]
	k.lathe(Vector3.ZERO, brim, 16, 2.0, 5.0)
	var crown: Array = [[1.70, 0.124], [1.78, 0.112], [1.84, 0.102], [1.845, 0.0]]
	k.lathe(Vector3.ZERO, crown, 16, 2.0, 6.0)
	return k.to_mesh()


## ---------------------------------------------------------------- setup

## `mat`: the walker material (ArlesScenery.walker_material()), `level_seed`:
## the city seed (the same seed gives the same people).
func setup(level_seed: int, mat: ShaderMaterial) -> void:
	name = "Life"
	seed_value = level_seed
	material = mat
	_build_paths()
	_build_walkers()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = walker_mesh()
	mm.instance_count = w_path.size()
	mmi = MultiMeshInstance3D.new()
	mmi.name = "Walkers"
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(-20, -2, -20), Vector3(140, 6, 140))
	add_child(mmi)
	_place()
	_send_gait()


func _build_paths() -> void:
	for d in path_defs():
		var pts: PackedVector2Array = d[1]
		path_ids.append(d[0])
		path_first.append(seg_a.size())
		path_segs.append(pts.size())
		var s := 0.0
		for i in pts.size():
			var a := pts[i]
			var b := pts[(i + 1) % pts.size()]
			var l := a.distance_to(b)
			seg_a.append(a)
			seg_d.append((b - a) / maxf(l, 0.0001))
			seg_s.append(s)
			seg_l.append(l)
			s += l
		path_len.append(s)


func _build_walkers() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 13 + 5
	var defs := path_defs()
	for p in defs.size():
		var n: int = defs[p][2]
		var pair: bool = defs[p][3]
		var s_base := rng.randf_range(0.0, path_len[p])
		# one speed per path: nobody overtakes anybody on a lane
		var sp := rng.randf_range(SPEED_MIN, SPEED_MAX)
		for i in n:
			var in_pair := pair and i < 2
			w_path.append(p)
			w_speed.append(sp)
			if in_pair:
				w_s0.append(s_base)
				w_lat.append(PAIR_HALF if i == 0 else -PAIR_HALF)
			else:
				# spread the others over the rest of the loop
				w_s0.append(fposmod(s_base + path_len[p] * (float(i) / float(n)) + rng.randf_range(-2.0, 2.0), path_len[p]))
				w_lat.append(0.0)
			w_phase.append(rng.randf())
			w_look.append(float(rng.randi() % 6) + float(rng.randi() % 3) / 10.0)
			w_hat.append(float(rng.randi() % 3))
			w_scale.append(rng.randf_range(0.93, 1.04))
			w_pos.append(Vector3.ZERO)
			w_dir.append(Vector2(0, -1))


## ---------------------------------------------------------------- update

## One frame: walk on (not with reduced effects), place the instances.
func update(delta: float, _player_pos: Vector3 = Vector3.ZERO) -> void:
	if _moving:
		time += minf(delta, 0.1)
		_place()


## Fast-forward `seconds` (tests, screenshots).
func advance(seconds: float) -> void:
	if _moving:
		time += seconds
		_place()


func _place() -> void:
	var mm := mmi.multimesh if mmi != null else null
	for i in w_path.size():
		var p := w_path[i]
		var u := fposmod(w_s0[i] + w_speed[i] * time, path_len[p])
		var k := path_first[p]
		var last := k + path_segs[p] - 1
		while k < last and u >= seg_s[k] + seg_l[k]:
			k += 1
		var d := seg_d[k]
		var q := seg_a[k] + d * (u - seg_s[k])
		q += Vector2(-d.y, d.x) * w_lat[i]
		w_pos[i] = Vector3(q.x, 0.0, q.y)
		w_dir[i] = d
		if mm != null:
			var yaw := atan2(-d.x, -d.y)
			var sc := w_scale[i]
			mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(sc, sc, sc)), w_pos[i]))


## Stride frequency and look of every walker to the shader (once, and again
## when the effects are switched).
func _send_gait() -> void:
	if mmi == null:
		return
	var mm := mmi.multimesh
	gait_sent.resize(w_path.size())
	for i in w_path.size():
		gait_sent[i] = stride_hz(i)
		mm.set_instance_custom_data(i, Color(w_phase[i], gait_sent[i], w_look[i], w_hat[i]))


## Stride frequency of walker i in Hz (0 while it stands still).
func stride_hz(i: int) -> float:
	return w_speed[i] / STRIDE if _moving else 0.0


## "Effekte reduzieren": the passers-by stand still (no walking, no gait).
func set_reduce_fx(on: bool) -> void:
	_moving = not on
	if material != null:
		material.set_shader_parameter("moving", 0.0 if on else 1.0)
	_send_gait()


func is_moving() -> bool:
	return _moving


## ---------------------------------------------------------------- queries

func walker_count() -> int:
	return w_path.size()


## Position of walker i in map space.
func walker_map_position(i: int) -> Vector3:
	return w_pos[i]


## Position of walker i in world space (what Main pushes the player away from).
func walker_position(i: int) -> Vector3:
	return w_pos[i] - MAP_SHIFT


func walker_direction(i: int) -> Vector2:
	return w_dir[i]


func walker_speed(i: int) -> float:
	return w_speed[i] if _moving else 0.0


func path_count() -> int:
	return path_len.size()


## Draw calls of the passers-by (one MultiMesh).
func draw_calls() -> int:
	var n := 0
	for ch in get_children():
		if ch is GeometryInstance3D and ch.visible:
			n += 1
	return n
