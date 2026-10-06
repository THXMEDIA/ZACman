extends Node3D
## AmsterdamLife — what moves in the cardboard model of Amsterdam (Abnahme
## 06.10.2026): little card people who stroll slowly along the quays and
## bridges, cyclists (card figures on bicycles) who ride loops over streets
## and bridges, and some parked bicycles leaning on bridge rails and trees.
## Main creates it for an Explorer city with traffic "amsterdam"
## (explorer_cities.gd) and calls update() every frame.
##
## Draw calls: TWO MultiMeshes whatever the number of figures - Passanten
## (people) and Fahrräder (riders and parked bicycles). The gait, the pedals
## and the wheel markers run in amsterdam_folk.gdshader from the phase the CPU
## hands in (distance travelled); the CPU only moves instance transforms and
## allocates nothing per frame (tests/test_amsterdam.gd counts objects).
##
## Everything is a pure function of the level seed and the time: same seed and
## same steps -> same figures. All of it is harmless: a figure gives the
## player at most the soft push of Manhattan and Tokyo (push_for(), Main moves
## the player's position by it; the camera and the mouse are never touched),
## nothing costs a life.
##
## Lanes (the player's pins run on the street centre lines, streets are 6 m
## wide, the alleys 4 m): cyclists keep right at 1.3 m from the centre line
## (loops: rectangles over two bridges, hairpins along the long streets, the
## corners rounded); people stroll on a lane 0.8 m from the facade / kerb in
## pieces of 9-18 m (one person per piece, they turn round at its ends and
## pause), never closer than 1.2 m to a tree or a parked bicycle, 5 m to the
## start and 7 m to the exit. So the pins and the middle of every street stay
## free. "Effekte reduzieren" stops all movement (the figures stand where they
## are, upright).

const M := preload("res://scripts/amsterdam_maze.gd")
const Scenery := preload("res://scripts/amsterdam_scenery.gd")
const Style := preload("res://scripts/amsterdam_style.gd")
const Figures := preload("res://scripts/amsterdam_figures.gd")
const FOLK_SHADER := preload("res://shaders/amsterdam_folk.gdshader")

const CELL := 2.0

## ---- people ----
const WALKER_COUNT := 36
const WALKER_SPEED := Vector2(0.75, 1.25) # m/s
const WALK_PAUSE := Vector2(2.0, 5.0) # s at the ends of a piece
const STRIDE := 1.4 # m per gait cycle (two steps)
const LANE_EDGE := 0.8 # a stroller keeps this far from kerb / facade
const SEG_LEN := Vector2(6.0, 16.0)
const SEG_GAP := 3.0
const SEG_TRIM := 0.5
const TREE_CLEAR := 1.2
const WALKER_RADIUS := 0.35 # soft push (same as Manhattan's pedestrians)
const KID_SHARE := 0.14

## ---- bicycles ----
const BIKE_LANE := 1.3 # riders keep right at this distance from the centre line
const BIKE_SPEED := Vector2(2.8, 3.8) # m/s
const BIKE_SPACING := 28.0 # m between two riders of a loop
const BIKE_RADIUS := 0.4
const PEDAL_CYCLE := 4.27 # m per pedal turn (the wheel turns twice)
const CORNER_R := 1.8
const PARKED_MAX := 14
const PARKED_RADIUS := 0.3
const PARKED_HALF := 0.7
const PARK_INSET := 0.42 # a bridge bicycle stands this far inside the rail

## Where nothing walks or rides near: the start and the exit (m).
const KEEP_START := 5.0
const KEEP_EXIT := 7.0

## Riding loops: "rect" = a block of two bridges (centre lines), clockwise,
## right-hand traffic, lane inside; "hair" = out and back along a centre
## polyline with a U-turn at both ends. Lanes are 1.3 m beside the centre line,
## so the pins stay free and the loops stay inside the streets.
const LOOP_DEFS := [
	{"type": "rect", "x0": 16.0, "z0": 40.0, "x1": 38.0, "z1": 54.0}, # Westermarkt bridge, Keizersgracht bridge west
	{"type": "rect", "x0": 38.0, "z0": 40.0, "x1": 60.0, "z1": 54.0}, # ... west to east bridge
	{"type": "hair", "pts": [Vector2(21, 24), Vector2(45, 24)]}, # Damrak quay (ends well before the start)
	{"type": "hair", "pts": [Vector2(16, 19), Vector2(16, 35)]}, # Westermarkt, church side
	{"type": "hair", "pts": [Vector2(16, 61), Vector2(16, 89)]}, # Westermarkt south, over the Prinsengracht bridge
	{"type": "hair", "pts": [Vector2(21, 70), Vector2(65, 70)]}, # Prinsengracht north quay
	{"type": "hair", "pts": [Vector2(23, 84), Vector2(86, 84), Vector2(86, 73)]}, # south quay, Magere Brug, Amstel bank
]

var seed_value := 0
var time := 0.0 # seconds since the level start (simulation time)
var reduce_fx := false

var maze_view: Node3D
var walker_mmi: MultiMeshInstance3D
var bike_mmi: MultiMeshInstance3D
var walker_material: ShaderMaterial
var bike_material: ShaderMaterial

## people: a stroll piece a -> b (ping-pong with pauses)
var w_a := PackedVector2Array()
var w_b := PackedVector2Array()
var w_dir := PackedVector2Array()
var w_h0 := PackedFloat32Array() # heading of a -> b (angle of (dx, dz))
var w_len := PackedFloat32Array()
var w_speed := PackedFloat32Array()
var w_pause := PackedFloat32Array()
var w_t0 := PackedFloat32Array() # offset into the cycle (s)
var w_off := PackedFloat32Array() # gait phase offset (0..1)
var w_col := PackedFloat32Array() # colour pick, (index + 0.5) / 8
var w_scale := PackedFloat32Array()
var w_pos := PackedVector3Array()
var w_mov := PackedByteArray()
## riding loops
var loop_pts: Array = []
var loop_cum: Array = []
var loop_len := PackedFloat32Array()
var loop_speed := PackedFloat32Array()
## riders
var r_loop := PackedInt32Array()
var r_s0 := PackedFloat32Array()
var r_off := PackedFloat32Array()
var r_col := PackedFloat32Array()
var r_pos := PackedVector3Array()
## parked bicycles
var pk_pos := PackedVector3Array()
var pk_a := PackedVector2Array() # capsule ends
var pk_b := PackedVector2Array()

var _pt := Vector2.ZERO # scratch result of _loop_at
var _wp := Vector2.ZERO # scratch results of _walker_state
var _wh := 0.0
var _wd := 0.0
var _wamp := 0.0
var _frozen := false


func setup(view: Node3D, level_seed: int) -> void:
	maze_view = view
	seed_value = level_seed
	name = "AmsterdamLife"
	_build_data()
	_build_nodes()
	_place()


## ---------------------------------------------------------------- lanes

static func start_pos() -> Vector2:
	return Vector2(M.START_CELL.y * CELL, M.START_CELL.x * CELL)


static func exit_pos() -> Vector2:
	return Vector2(M.METRO_CELL.y * CELL, M.METRO_CELL.x * CELL)


## Whether the point and a ring of `r` m around it lie on open ground (street
## or bridge): clear of kerbs, facades, rails.
static func clear_at(p: Vector2, r: float) -> bool:
	var c := Scenery.cell_of(Vector3(p.x, 0.0, p.y))
	if not Scenery.is_open(Scenery.kind(c.x, c.y)):
		return false
	for k in 8:
		var a := TAU * float(k) / 8.0
		var q := p + Vector2(cos(a), sin(a)) * r
		var cq := Scenery.cell_of(Vector3(q.x, 0.0, q.y))
		if not Scenery.is_open(Scenery.kind(cq.x, cq.y)):
			return false
	return true


## Streets and bridges as lane rectangles: {axis, a0, a1 (along, m), centre
## (across, m), hw (half width, m)}. The bridges of the Westermarkt lie inside
## its street rectangle already.
static func lane_rects() -> Array:
	var out := []
	for s in M.STREETS:
		out.append(_rect_of(s))
	for b in M.BRIDGES:
		if M.street_at(b.r0, b.c0).is_empty():
			out.append(_rect_of(b))
	return out


static func _rect_of(s: Dictionary) -> Dictionary:
	var ew: bool = s.axis == "ew"
	if ew:
		return {"axis": "ew", "a0": s.c0 * CELL - 1.0, "a1": s.c1 * CELL + 1.0, "centre": float(s.r0 + s.r1), "hw": float(s.r1 - s.r0 + 1)}
	return {"axis": "ns", "a0": s.r0 * CELL - 1.0, "a1": s.r1 * CELL + 1.0, "centre": float(s.c0 + s.c1), "hw": float(s.c1 - s.c0 + 1)}


static func _lane_ok(p: Vector2, trees: Array, obstacles: Array) -> bool:
	if not clear_at(p, 0.6):
		return false
	if p.distance_to(start_pos()) < KEEP_START or p.distance_to(exit_pos()) < KEEP_EXIT:
		return false
	for t in trees:
		if Vector2(t.x, t.z).distance_to(p) < TREE_CLEAR:
			return false
	for o in obstacles:
		if o.distance_to(p) < TREE_CLEAR + 0.2:
			return false
	# the pins run along the centre line of every street: a lane that crosses
	# another street keeps off that line (walkers stop at junctions; the lanes
	# of the street itself lie >= 1.2 m off its own centre line)
	for r in lane_rects():
		var ew: bool = r.axis == "ew"
		var along: float = p.x if ew else p.y
		var across: float = p.y if ew else p.x
		if along >= r.a0 and along <= r.a1 and absf(across - r.centre) < 1.1:
			return false
	return true


## The stroll pieces of a level seed: [{a, b}] on the lanes (world x / z),
## in a seeded random order (the first WALKER_COUNT are used).
static func foot_segments(level_seed: int) -> Array:
	var trees: Array = Scenery.trees(level_seed)
	var obstacles := []
	for pk in parked_bikes(level_seed, trees):
		obstacles.append(Vector2(pk.pos.x, pk.pos.z))
	var rng := RandomNumberGenerator.new()
	rng.seed = level_seed * 31 + 7
	var cands := []
	for r in lane_rects():
		var ew: bool = r.axis == "ew"
		var off: float = r.hw - LANE_EDGE
		if r.hw < 1.9:
			continue # one-cell passages (2 m): the pins run through the middle, no room to stroll
		for side in [-1.0, 1.0]:
			if r.hw < 2.5 and side < 0.0:
				continue # alleys: one lane only (the pins run along the other side)
			var lane: float = r.centre + side * off
			var runs := []
			var start := -1.0
			var t: float = r.a0
			var prev := -1.0
			while t <= r.a1 + 0.001:
				var p := Vector2(t, lane) if ew else Vector2(lane, t)
				if _lane_ok(p, trees, obstacles):
					if start < 0.0:
						start = t
					prev = t
				elif start >= 0.0:
					runs.append([start, prev])
					start = -1.0
				t += 0.5
			if start >= 0.0:
				runs.append([start, prev])
			for run in runs:
				var from: float = run[0] + SEG_TRIM
				var to: float = run[1] - SEG_TRIM
				var pos := from
				while to - pos >= SEG_LEN.x:
					var ln := minf(to - pos, rng.randf_range(SEG_LEN.x, SEG_LEN.y))
					var a := Vector2(pos, lane) if ew else Vector2(lane, pos)
					var b := Vector2(pos + ln, lane) if ew else Vector2(lane, pos + ln)
					cands.append({"a": a, "b": b})
					pos += ln + SEG_GAP
	for i in range(cands.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = cands[i]
		cands[i] = cands[j]
		cands[j] = tmp
	return cands


static func _offset_polyline(pts: Array, off: float) -> PackedVector2Array:
	var n := pts.size()
	var out := PackedVector2Array()
	for i in n:
		var r1 := Vector2.ZERO
		var r2 := Vector2.ZERO
		if i > 0:
			var d1: Vector2 = (pts[i] - pts[i - 1]).normalized()
			r1 = Vector2(-d1.y, d1.x)
		if i < n - 1:
			var d2: Vector2 = (pts[i + 1] - pts[i]).normalized()
			r2 = Vector2(-d2.y, d2.x)
		if i == 0:
			r1 = r2
		if i == n - 1:
			r2 = r1
		out.append(pts[i] + (r1 + r2) * (off / maxf(1.0 + r1.dot(r2), 0.0001)))
	return out


## Closed polyline with every bend rounded by a quadratic curve of radius ~r.
static func _round_corners(pts: PackedVector2Array, r: float) -> PackedVector2Array:
	var n := pts.size()
	var out := PackedVector2Array()
	for i in n:
		var a := pts[(i + n - 1) % n]
		var p := pts[i]
		var b := pts[(i + 1) % n]
		var da := a - p
		var db := b - p
		if absf(da.normalized().cross(db.normalized())) < 0.05:
			_push_pt(out, p)
			continue
		var d1 := minf(r, da.length() * 0.5)
		var d2 := minf(r, db.length() * 0.5)
		var p1 := p + da.normalized() * d1
		var p2 := p + db.normalized() * d2
		for k in 7:
			var t := float(k) / 6.0
			_push_pt(out, p1 * ((1.0 - t) * (1.0 - t)) + p * (2.0 * (1.0 - t) * t) + p2 * (t * t))
	if out.size() > 1 and out[0].distance_to(out[out.size() - 1]) < 0.001:
		out.remove_at(out.size() - 1)
	return out


static func _push_pt(out: PackedVector2Array, p: Vector2) -> void:
	if out.is_empty() or out[out.size() - 1].distance_to(p) > 0.001:
		out.append(p)


## The riding loops as closed polylines (world x / z, 1.3 m beside the centre lines).
static func bike_loops() -> Array:
	var out := []
	for d in LOOP_DEFS:
		var pts := PackedVector2Array()
		if d.type == "rect":
			var l := BIKE_LANE
			pts = PackedVector2Array([Vector2(d.x0 + l, d.z0 + l), Vector2(d.x1 - l, d.z0 + l), Vector2(d.x1 - l, d.z1 - l), Vector2(d.x0 + l, d.z1 - l)])
		else:
			var fwd: Array = d.pts
			var rev := fwd.duplicate()
			rev.reverse()
			pts = _offset_polyline(fwd, BIKE_LANE)
			pts.append_array(_offset_polyline(rev, BIKE_LANE))
		out.append(_round_corners(pts, CORNER_R))
	return out


## Parked bicycles: [{pos (Vector3), yaw, lean}]: leaning on bridge rails
## (always inside the rail, along it) and on tree trunks along the quays.
static func parked_bikes(level_seed: int, trees: Array) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = level_seed * 13 + 5
	var out := []
	for b in M.BRIDGES:
		var ns: bool = b.axis == "ns"
		var x0: float = b.c0 * CELL - 1.0
		var x1: float = b.c1 * CELL + 1.0
		var z0: float = b.r0 * CELL - 1.0
		var z1: float = b.r1 * CELL + 1.0
		var cx := (x0 + x1) * 0.5
		var cz := (z0 + z1) * 0.5
		var hw := ((x1 - x0) if ns else (z1 - z0)) * 0.5
		var s0 := z0 if ns else x0
		var s1 := z1 if ns else x1
		for side in [-1.0, 1.0]:
			var take := rng.randf() < 0.7
			var t := rng.randf_range(s0 + 2.2, s1 - 2.2)
			var lean := rng.randf_range(0.10, 0.2)
			var flip := rng.randf() < 0.5
			if not take:
				continue
			var lat: float = side * (hw - PARK_INSET)
			var pos := Vector3(cx + lat, 0.0, t) if ns else Vector3(t, 0.0, cz + lat)
			var dv := Vector2(0, 1) if ns else Vector2(1, 0)
			if flip:
				dv = -dv
			var to_rail := Vector2(side, 0) if ns else Vector2(0, side)
			out.append(_park(pos, dv, to_rail, lean))
	var picks := 0
	for p in trees:
		var take2 := rng.randf() < 0.22
		var lean2 := rng.randf_range(0.12, 0.2)
		var flip2 := rng.randf() < 0.5
		if not take2 or picks >= 6:
			continue
		var n := Vector2.ZERO
		for dir in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
			var q: Vector2 = Vector2(p.x, p.z) + dir
			var c := Scenery.cell_of(Vector3(q.x, 0.0, q.y))
			if Scenery.kind(c.x, c.y) == "water":
				n = dir
		if n == Vector2.ZERO:
			continue
		var tg := Vector2(-n.y, n.x)
		var pos2 := Vector2(p.x, p.z) - n * 0.52 + tg * 0.35
		out.append(_park(Vector3(pos2.x, 0.0, pos2.y), -tg if flip2 else tg, n, lean2))
		picks += 1
	return out.slice(0, PARKED_MAX)


static func _park(pos: Vector3, dv: Vector2, to_rail: Vector2, lean: float) -> Dictionary:
	var yaw := atan2(-dv.x, -dv.y)
	var right := Vector2(-dv.y, dv.x)
	# rotating about the bicycle's Z axis by +a tips its top to the left
	return {"pos": pos, "yaw": yaw, "lean": -lean if right.dot(to_rail) > 0.0 else lean}


## ---------------------------------------------------------------- build

func _build_data() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 17 + 3
	# people
	var segs := foot_segments(seed_value)
	var nw := mini(WALKER_COUNT, segs.size())
	for i in nw:
		var a: Vector2 = segs[i].a
		var b: Vector2 = segs[i].b
		var len_ := a.distance_to(b)
		w_a.append(a)
		w_b.append(b)
		w_dir.append((b - a) / len_)
		w_h0.append((b - a).angle())
		w_len.append(len_)
		w_speed.append(rng.randf_range(WALKER_SPEED.x, WALKER_SPEED.y))
		w_pause.append(rng.randf_range(WALK_PAUSE.x, WALK_PAUSE.y))
		w_t0.append(rng.randf_range(0.0, 200.0))
		w_off.append(rng.randf())
		w_col.append((float(rng.randi() % 8) + 0.5) / 8.0)
		w_scale.append(0.72 if rng.randf() < KID_SHARE else rng.randf_range(0.93, 1.07))
		w_pos.append(Vector3.ZERO)
		w_mov.append(0)
	# riding loops and riders
	var loops := bike_loops()
	for li in loops.size():
		var pts: PackedVector2Array = loops[li]
		var cum := PackedFloat32Array()
		var acc := 0.0
		for i in pts.size():
			cum.append(acc)
			acc += pts[i].distance_to(pts[(i + 1) % pts.size()])
		loop_pts.append(pts)
		loop_cum.append(cum)
		loop_len.append(acc)
		loop_speed.append(rng.randf_range(BIKE_SPEED.x, BIKE_SPEED.y))
		var count := maxi(1, int(acc / BIKE_SPACING))
		var base := rng.randf() * acc
		for k in count:
			r_loop.append(li)
			r_s0.append(base + float(k) * acc / float(count))
			r_off.append(rng.randf())
			r_col.append((float(rng.randi() % 8) + 0.5) / 8.0)
			r_pos.append(Vector3.ZERO)
	# parked bicycles
	for pk in parked_bikes(seed_value, Scenery.trees(seed_value)):
		var f := Vector2(-sin(pk.yaw), -cos(pk.yaw))
		var c := Vector2(pk.pos.x, pk.pos.z)
		pk_pos.append(pk.pos)
		pk_a.append(c - f * PARKED_HALF)
		pk_b.append(c + f * PARKED_HALF)


func _mmi(node_name: String, mm: MultiMesh, mat: Material) -> MultiMeshInstance3D:
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.material_override = mat
	# the figures spread over the whole model: never culled by a stale AABB
	mmi.custom_aabb = AABB(Vector3(-6, -2, -6), Vector3(116, 8, 116))
	add_child(mmi)
	return mmi


func _build_nodes() -> void:
	var pal := Figures.folk_palette()
	var wm := MultiMesh.new()
	wm.transform_format = MultiMesh.TRANSFORM_3D
	wm.use_custom_data = true
	wm.mesh = Figures.walker_mesh()
	wm.instance_count = w_a.size()
	walker_material = ShaderMaterial.new()
	walker_material.shader = FOLK_SHADER
	walker_material.set_shader_parameter("pal", pal)
	walker_material.set_shader_parameter("kraft", Style.KRAFT)
	walker_material.set_shader_parameter("bike", false)
	walker_mmi = _mmi("Passanten", wm, walker_material)
	var bm := MultiMesh.new()
	bm.transform_format = MultiMesh.TRANSFORM_3D
	bm.use_custom_data = true
	bm.mesh = Figures.bike_mesh()
	bm.instance_count = r_loop.size() + pk_pos.size()
	bike_material = ShaderMaterial.new()
	bike_material.shader = FOLK_SHADER
	bike_material.set_shader_parameter("pal", pal)
	bike_material.set_shader_parameter("kraft", Style.KRAFT)
	bike_material.set_shader_parameter("bike", true)
	bike_mmi = _mmi("Fahrraeder", bm, bike_material)
	# parked bicycles never move: written once
	var prng := RandomNumberGenerator.new()
	prng.seed = seed_value * 7 + 11
	var parked := parked_bikes(seed_value, Scenery.trees(seed_value))
	for i in pk_pos.size():
		var pk: Dictionary = parked[i]
		bm.set_instance_transform(r_loop.size() + i, Transform3D(Basis(Vector3.UP, pk.yaw) * Basis(Vector3(0, 0, 1), pk.lean), pk.pos))
		bm.set_instance_custom_data(r_loop.size() + i, Color(prng.randf(), 0.0, (float(prng.randi() % 8) + 0.5) / 8.0, 0.0))


## ---------------------------------------------------------------- update

## One frame: advance the clock and move the instances. With "Effekte
## reduzieren" nothing moves.
func update(delta: float, _player_pos: Vector3 = Vector3.ZERO, _cam_pos: Vector3 = Vector3.ZERO) -> void:
	if _frozen:
		return
	time += minf(delta, 0.1)
	_place()


## Fast-forward `seconds` (tests, screenshots).
func advance(seconds: float) -> void:
	if _frozen:
		return
	time += seconds
	_place()


## "Effekte reduzieren": everybody stands where they are, upright.
func set_comfort(fx_reduced: bool) -> void:
	reduce_fx = fx_reduced
	if _frozen != fx_reduced:
		_frozen = fx_reduced
		if walker_mmi != null:
			_place()


func is_frozen() -> bool:
	return _frozen


func _walker_state(i: int) -> void:
	var length := w_len[i]
	var sp := w_speed[i]
	var pause := w_pause[i]
	var walk := length / sp
	var cycle := 2.0 * (walk + pause)
	var tt := time + w_t0[i]
	var cyc := floorf(tt / cycle)
	var tc := tt - cyc * cycle
	var d := w_dir[i]
	var h0 := w_h0[i]
	var turn := minf(1.0, pause * 0.6)
	var base := cyc * 2.0 * length
	_wamp = 0.0
	if tc < walk:
		_wp = w_a[i] + d * (sp * tc)
		_wh = h0
		_wd = base + sp * tc
		_wamp = minf(1.0, minf(tc, walk - tc) / 0.4)
	elif tc < walk + pause:
		_wp = w_b[i]
		_wh = h0 + PI * smoothstep(0.0, 1.0, (tc - walk - 0.15) / turn)
		_wd = base + length
	elif tc < 2.0 * walk + pause:
		var tw := tc - walk - pause
		_wp = w_b[i] - d * (sp * tw)
		_wh = h0 + PI
		_wd = base + length + sp * tw
		_wamp = minf(1.0, minf(tw, walk - tw) / 0.4)
	else:
		_wp = w_a[i]
		_wh = h0 + PI + PI * smoothstep(0.0, 1.0, (tc - 2.0 * walk - pause - 0.15) / turn)
		_wd = base + 2.0 * length


## Point of loop `li` at arc length `s` (wraps) -> _pt.
func _loop_at(li: int, s: float) -> void:
	var cum: PackedFloat32Array = loop_cum[li]
	var pts: PackedVector2Array = loop_pts[li]
	var total := loop_len[li]
	s = fposmod(s, total)
	var lo := 0
	var hi := cum.size() - 1
	while lo < hi:
		var mid := (lo + hi + 1) >> 1
		if cum[mid] <= s:
			lo = mid
		else:
			hi = mid - 1
	var nxt := cum[lo + 1] if lo + 1 < cum.size() else total
	var a := pts[lo]
	var b := pts[(lo + 1) % pts.size()]
	_pt = a.lerp(b, (s - cum[lo]) / maxf(nxt - cum[lo], 0.000001))


func _place() -> void:
	var amp_mul := 0.0 if _frozen else 1.0
	var wm := walker_mmi.multimesh
	for i in w_a.size():
		_walker_state(i)
		w_pos[i] = Vector3(_wp.x, 0.0, _wp.y)
		w_mov[i] = 1 if (_wamp > 0.0 and not _frozen) else 0
		var yaw := atan2(-cos(_wh), -sin(_wh))
		var sc := w_scale[i]
		wm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(sc, sc, sc)), w_pos[i]))
		wm.set_instance_custom_data(i, Color(fposmod(_wd / STRIDE + w_off[i], 1.0), _wamp * amp_mul, w_col[i], 0.0))
	var bm := bike_mmi.multimesh
	for i in r_loop.size():
		var li := r_loop[i]
		var s := r_s0[i] + loop_speed[li] * time
		_loop_at(li, s - 0.4)
		var p0 := _pt
		_loop_at(li, s)
		var p1 := _pt
		_loop_at(li, s + 0.4)
		var p2 := _pt
		var fwd := p2 - p0
		var yaw := atan2(-fwd.x, -fwd.y)
		var lean := clampf(-(p1 - p0).angle_to(p2 - p1) * 1.6, -0.3, 0.3)
		r_pos[i] = Vector3(p1.x, 0.0, p1.y)
		var sc := 1.0 + 0.04 * (r_off[i] - 0.5)
		bm.set_instance_transform(i, Transform3D((Basis(Vector3.UP, yaw) * Basis(Vector3(0, 0, 1), lean * amp_mul)).scaled(Vector3(sc, sc, sc)), r_pos[i]))
		bm.set_instance_custom_data(i, Color(fposmod(s / PEDAL_CYCLE + r_off[i], 1.0), amp_mul, r_col[i], 1.0))


## ---------------------------------------------------------------- queries

func walker_count() -> int:
	return w_a.size()


func walker_position(i: int) -> Vector3:
	return w_pos[i]


func walker_moving(i: int) -> bool:
	return w_mov[i] == 1


func walker_speed(i: int) -> float:
	return w_speed[i]


func rider_count() -> int:
	return r_loop.size()


func rider_position(i: int) -> Vector3:
	return r_pos[i]


func rider_speed(i: int) -> float:
	return loop_speed[r_loop[i]]


func parked_count() -> int:
	return pk_pos.size()


func parked_position(i: int) -> Vector3:
	return pk_pos[i]


## Highest frequency (Hz) of any periodic motion on screen: the stride bob
## (twice per gait cycle), the pedals and the wheel marker.
func max_motion_hz() -> float:
	var hz := 0.0
	for i in w_a.size():
		hz = maxf(hz, 2.0 * w_speed[i] / STRIDE)
	for li in loop_speed.size():
		hz = maxf(hz, 2.0 * loop_speed[li] / PEDAL_CYCLE)
	return hz


## The soft push of all figures on a player standing at `p` (world), as the
## offset to add to the player's x / z: people and riders push within their
## radius, parked bicycles as a capsule along their frame. Never more than
## 0.5 m per frame; the camera is not touched.
func push_for(p: Vector3) -> Vector2:
	var out := Vector2.ZERO
	for i in w_pos.size():
		out += _push_from(p, w_pos[i], WALKER_RADIUS)
	for i in r_pos.size():
		out += _push_from(p, r_pos[i], BIKE_RADIUS)
	for i in pk_a.size():
		var a := pk_a[i]
		var ab := pk_b[i] - a
		var t := clampf((Vector2(p.x, p.z) - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		var q := a + ab * t
		out += _push_from(p, Vector3(q.x, 0.0, q.y), PARKED_RADIUS)
	return out.limit_length(0.5)


static func _push_from(p: Vector3, o: Vector3, radius: float) -> Vector2:
	var dx := p.x - o.x
	var dz := p.z - o.z
	if absf(dx) >= radius or absf(dz) >= radius:
		return Vector2.ZERO
	var d := sqrt(dx * dx + dz * dz)
	if d >= radius:
		return Vector2.ZERO
	if d <= 0.0001:
		return Vector2(radius, 0.0)
	return Vector2(dx, dz) / d * (radius - d)
