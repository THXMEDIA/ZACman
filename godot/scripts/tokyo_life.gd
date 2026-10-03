extends Node3D
## TokyoLife — everything that moves in the Tokyo line city (docs/design/
## tokyo-explorer.md, M2): rain, traffic, passers-by and the scramble
## crossing, plus the halos, light cones and light streaks that belong to
## them. Main creates it for an Explorer city with traffic "tokyo"
## (explorer_cities.gd) and calls update() every frame.
##
## Draw calls: SIX MultiMeshes, whatever the number of drops, cars and
## people — Regen, Autos, Passanten (walkers and the scramble crowd),
## Halos, Lichtkegel, Lichtstreifen. Animation runs in the shaders (rain
## falls and wraps in the vertex shader, the gait swings legs and arms via
## INSTANCE_CUSTOM); the CPU only moves instance transforms of cars and
## people (no mesh rebuild, no node per figure) and allocates nothing per
## frame (tests/test_tokyo_life.gd counts objects and resources).
##
## Scramble cycle (CYCLE s, starts at CYCLE_START so the first "All Walk"
## comes ~24 s after the level start):
##   0-26 s    north-south traffic green        26-30 s  all red
##   30-56 s   east-west traffic green          56-60 s  all red
##   60-80 s   ALL WALK: every car waits at its stop line, a wave of
##             passers-by (4 corners x CROWD_PER_CORNER) crosses straight
##             and diagonally; a synthetic crossing tone announces it
##             (signal walk_started -> Main -> Sfx.crossing_signal()).
## Japan drives on the left: northbound traffic on the west half of the
## north-south avenue, eastbound on the north half of the east-west avenue.
## Cars run on closed loops (straight lanes plus U-turns hidden in the
## edge buildings or, at the station, in front of the plaza), follow each
## other, stop at red lights and for the player standing in their lane.
## Cars are obstacles (Main pushes the player out, like Manhattan),
## passers-by are harmless (a soft push, like Manhattan).
##
## Everything is deterministic for a level seed: same seed and same steps
## -> same traffic, same people.

signal walk_started
signal walk_ended

const Style := preload("res://scripts/tokyo_style.gd")
const Figures := preload("res://scripts/tokyo_figures.gd")
const Wet := preload("res://scripts/tokyo_wet.gd")
const TokyoScenery := preload("res://scripts/tokyo_scenery.gd")
const TokyoMaze := preload("res://scripts/tokyo_maze.gd")
const RAIN_SHADER := preload("res://shaders/tokyo_rain.gdshader")
const CAR_SHADER := preload("res://shaders/tokyo_car.gdshader")
const WALKER_SHADER := preload("res://shaders/tokyo_walker.gdshader")
const HALO_SHADER := preload("res://shaders/tokyo_halo.gdshader")
const CONE_SHADER := preload("res://shaders/tokyo_cone.gdshader")
const STREAK_SHADER := preload("res://shaders/tokyo_streak.gdshader")

const CELL := 2.0

## ---- scramble cycle (s) ----
const CYCLE := 80.0
const NS_GREEN_END := 26.0
const EW_GREEN_START := 30.0
const EW_GREEN_END := 56.0
const WALK_START := 60.0
const WALK_END := 80.0
const CYCLE_START := 36.0
const CROSS_DONE := 16.5 # every crossing ends this long after WALK_START

## ---- rain ----
const RAIN_MAX := 8000
const RAIN_REDUCED := 0.35 # "Regen reduzieren"
const RAIN_FX := 0.7 # "Effekte reduzieren"

## ---- traffic ----
const CARS_PER_LOOP := 4
const CAR_ACCEL := 2.6
const CAR_BRAKE := 4.5 # comfortable braking towards an obstacle
const CAR_BRAKE_MAX := 8.0
const CAR_GAP := 6.6 # center distance of two waiting cars
const CAR_RADIUS := 1.05 # push-out radius around the car's axis
const CAR_AXIS_HALF := 1.3 # half length of that axis (capsule)
const PLAYER_LANE := 1.2 # the player blocks a lane closer than this
## Lanes (world m): north-south x, east-west z; outer and inner per direction.
const NS_X := [[42.4, 49.6], [44.5, 47.5]]
const EW_Z := [[42.4, 49.6], [44.5, 47.5]]
const NS_NORTH_TURN := 15.6 # U-turn center z in front of the station plaza
const NS_SOUTH_TURN := 96.0 # behind the south edge building
const EW_WEST_TURN := -4.0
const EW_EAST_TURN := 96.0
## Stop lines (the car's front stops here): before the zebras.
const STOP_NORTH := 35.7 # southbound cars, north arm
const STOP_SOUTH := 56.3 # northbound cars, south arm
const STOP_WEST := 35.7 # eastbound cars, west arm
const STOP_EAST := 56.3 # westbound cars, east arm
const CROSS_MIN := 39.0 # the crossing field (world m, both axes)
const CROSS_MAX := 53.0

## ---- passers-by ----
const WALKER_COUNT := 28
const CROWD_PER_CORNER := 28
const WALKER_RADIUS := 0.35
const UMBRELLA_SHARE := 0.85

var seed_value := 0
var time := 0.0 # seconds since the level start (simulation time)
var cycle_time := CYCLE_START
var reduce_rain := false
var reduce_fx := false
var _was_walk := false

var maze_view: Node3D
var rain_mmi: MultiMeshInstance3D
var car_mmi: MultiMeshInstance3D
var walker_mmi: MultiMeshInstance3D
var halo_mmi: MultiMeshInstance3D
var cone_mmi: MultiMeshInstance3D
var streak_mmi: MultiMeshInstance3D
var rain_material: ShaderMaterial
var floor_material: ShaderMaterial

## loops: [{pts: PackedVector2Array, cum: PackedFloat32Array, length,
## group (0 north-south, 1 east-west), stops: PackedFloat32Array (car
## center s where it waits)}]
var loops: Array = []
var _loop_ps := PackedFloat32Array() # player's s on each loop (this step)
var _loop_pl := PackedFloat32Array() # player's distance to each loop

var car_loop := PackedInt32Array()
var car_s := PackedFloat32Array()
var car_v := PackedFloat32Array()
var car_vmax := PackedFloat32Array()
var car_leader := PackedInt32Array()
var car_brake := PackedFloat32Array()
var car_pos := PackedVector3Array()
var car_fwd := PackedVector3Array()

## regular walkers: segment a->b ping-pong
var w_a := PackedVector2Array()
var w_b := PackedVector2Array()
var w_len := PackedFloat32Array()
var w_s0 := PackedFloat32Array()
var w_speed := PackedFloat32Array()
## scramble crowd: E(ntry) S(pot) A B T(arget) X(exit), 6 points each
var c_pts := PackedVector2Array()
var c_t_in := PackedFloat32Array()
var c_v_in := PackedFloat32Array()
var c_delay := PackedFloat32Array()
var c_v_cross := PackedFloat32Array()
var c_v_out := PackedFloat32Array()
## all people (walkers first, then the crowd)
var p_pos := PackedVector3Array()
var p_dir := PackedVector2Array()
var p_vis := PackedByteArray()
var p_freq := PackedFloat32Array() # current stride frequency (0 standing)
var p_freq_set := PackedFloat32Array() # last value sent to the MultiMesh
var p_phase := PackedFloat32Array()
var p_bright := PackedFloat32Array()
var p_umb := PackedFloat32Array()
var p_walk_freq := PackedFloat32Array() # stride frequency when walking

## light candidates (tokyo_wet.gd layout) for the floor and the rain
var _floor_lights := {}
var _rain_pos := PackedColorArray()
var _rain_col := PackedColorArray()
var _rain_prio := PackedFloat32Array()
var _static_rain_n := 0
var _out_pos := PackedColorArray() # rain lights (own arrays: the material keeps a reference)
var _out_col := PackedColorArray()
var _floor_pos := PackedColorArray() # floor lights
var _floor_col := PackedColorArray()
var _score := PackedFloat32Array()
var _used := PackedByteArray()

var _lamp_count := 0
var _halo_car0 := 0
var _cone_car0 := 0
## scratch results of _loop_point (no allocation)
var _pt := Vector2.ZERO
var _tg := Vector2.ZERO


func setup(view: Node3D, level_seed: int) -> void:
	maze_view = view
	seed_value = level_seed
	name = "TokyoLife"
	if view != null and view.floor_mesh != null:
		floor_material = view.floor_mesh.material_override as ShaderMaterial
	_build_loops()
	_build_cars()
	_build_people()
	_build_rain()
	_build_lights()
	update(0.0, Vector3(-1000, 0, -1000), Vector3(46, 1, 84))


## ---------------------------------------------------------------- phases

func is_walk_phase() -> bool:
	return cycle_time >= WALK_START


## Whether cars of `group` (0 north-south, 1 east-west) may pass their stop line.
func is_green(group: int) -> bool:
	if group == 0:
		return cycle_time < NS_GREEN_END
	return cycle_time >= EW_GREEN_START and cycle_time < EW_GREEN_END


## Phase name for the HUD-free tests and tools: "ns", "ew", "rot", "walk".
func phase() -> String:
	if is_walk_phase():
		return "walk"
	if is_green(0):
		return "ns"
	if is_green(1):
		return "ew"
	return "rot"


## ---------------------------------------------------------------- update

## One frame: simulation step, instance transforms, light lists.
func update(delta: float, player_pos: Vector3, cam_pos: Vector3) -> void:
	_simulate(delta, player_pos)
	_place_cars()
	_place_people()
	_update_lights(cam_pos)


## Fast-forward `seconds` in fixed steps (tests, screenshots).
func advance(seconds: float, player_pos: Vector3 = Vector3(-1000, 0, -1000), step: float = 1.0 / 30.0) -> void:
	var n := int(ceil(seconds / step))
	for i in n:
		_simulate(step, player_pos)
	_place_cars()
	_place_people()


func _simulate(delta: float, player_pos: Vector3) -> void:
	var left := delta
	while left > 0.0:
		var dt := minf(left, 0.05)
		left -= dt
		time += dt
		cycle_time = fmod(CYCLE_START + time, CYCLE)
		var walk := is_walk_phase()
		if walk != _was_walk:
			_was_walk = walk
			if walk:
				walk_started.emit()
			else:
				walk_ended.emit()
		_project_player(player_pos)
		_step_cars(dt)
	_step_people()


## ---------------------------------------------------------------- loops

func _build_loops() -> void:
	loops.clear()
	for k in 2:
		var xw: float = NS_X[k][0]
		var xe: float = NS_X[k][1]
		var r := (xe - xw) * 0.5
		var cx := (xw + xe) * 0.5
		var pts := PackedVector2Array()
		# northbound on the west lane (-z), U-turn over the top (station),
		# southbound on the east lane (+z), U-turn behind the south edge
		pts.append(Vector2(xw, NS_SOUTH_TURN))
		pts.append(Vector2(xw, NS_NORTH_TURN))
		_arc(pts, Vector2(cx, NS_NORTH_TURN), r, PI, 0.0, 14, true)
		pts.append(Vector2(xe, NS_SOUTH_TURN))
		_arc(pts, Vector2(cx, NS_SOUTH_TURN), r, 0.0, PI, 14, false)
		var loop := _make_loop(pts, 0)
		loop.stops = PackedFloat32Array([_s_of(loop, Vector2(xw, STOP_SOUTH + Figures.CAR_HALF_LEN + 0.2)), _s_of(loop, Vector2(xe, STOP_NORTH - Figures.CAR_HALF_LEN - 0.2))])
		loops.append(loop)
	for k in 2:
		var zn: float = EW_Z[k][0]
		var zs: float = EW_Z[k][1]
		var r2 := (zs - zn) * 0.5
		var cz := (zn + zs) * 0.5
		var pts2 := PackedVector2Array()
		# eastbound on the north lane (+x), westbound on the south lane (-x)
		pts2.append(Vector2(EW_WEST_TURN, zn))
		pts2.append(Vector2(EW_EAST_TURN, zn))
		_arc(pts2, Vector2(EW_EAST_TURN, cz), r2, -PI * 0.5, PI * 0.5, 14, false)
		pts2.append(Vector2(EW_WEST_TURN, zs))
		_arc(pts2, Vector2(EW_WEST_TURN, cz), r2, PI * 0.5, PI * 1.5, 14, false)
		var loop2 := _make_loop(pts2, 1)
		loop2.stops = PackedFloat32Array([_s_of(loop2, Vector2(STOP_WEST - Figures.CAR_HALF_LEN - 0.2, zn)), _s_of(loop2, Vector2(STOP_EAST + Figures.CAR_HALF_LEN + 0.2, zs))])
		loops.append(loop2)
	_loop_ps.resize(loops.size())
	_loop_pl.resize(loops.size())


## Arc points (without the start point) around c from angle a0 to a1:
## c + (cos a, sin a) * r, or with `flip_z` c + (cos a, -sin a) * r.
func _arc(pts: PackedVector2Array, c: Vector2, r: float, a0: float, a1: float, segs: int, flip_z: bool) -> void:
	for i in range(1, segs + 1):
		var a := lerpf(a0, a1, float(i) / segs)
		pts.append(c + Vector2(cos(a), -sin(a) if flip_z else sin(a)) * r)


func _make_loop(pts: PackedVector2Array, group: int) -> Dictionary:
	# the last arc ends where the loop starts: no zero-length closing segment
	if pts.size() > 2 and pts[pts.size() - 1].distance_to(pts[0]) < 0.001:
		pts.resize(pts.size() - 1)
	var cum := PackedFloat32Array()
	cum.resize(pts.size() + 1)
	var total := 0.0
	cum[0] = 0.0
	for i in pts.size():
		total += pts[i].distance_to(pts[(i + 1) % pts.size()])
		cum[i + 1] = total
	return {"pts": pts, "cum": cum, "length": total, "group": group, "stops": PackedFloat32Array()}


## s of the loop point nearest to p.
func _s_of(loop: Dictionary, p: Vector2) -> float:
	var pts: PackedVector2Array = loop.pts
	var cum: PackedFloat32Array = loop.cum
	var best := INF
	var best_s := 0.0
	for i in pts.size():
		var a := pts[i]
		var b := pts[(i + 1) % pts.size()]
		var ab := b - a
		var l2 := ab.length_squared()
		var t := 0.0 if l2 < 1e-6 else clampf((p - a).dot(ab) / l2, 0.0, 1.0)
		var q := a + ab * t
		var d := q.distance_squared_to(p)
		if d < best:
			best = d
			best_s = cum[i] + sqrt(l2) * t
	return best_s


## Point and unit tangent at s (results in _pt/_tg, no allocation).
func _loop_point(loop: Dictionary, s: float) -> void:
	var pts: PackedVector2Array = loop.pts
	var cum: PackedFloat32Array = loop.cum
	var n := pts.size()
	var lo := 0
	var hi := n - 1
	while lo < hi:
		var mid := (lo + hi + 1) >> 1
		if cum[mid] <= s:
			lo = mid
		else:
			hi = mid - 1
	var a := pts[lo]
	var b := pts[(lo + 1) % n]
	var seg := cum[lo + 1] - cum[lo]
	var t := 0.0 if seg < 1e-6 else (s - cum[lo]) / seg
	_pt = a.lerp(b, t)
	_tg = (b - a) / maxf(seg, 1e-6)


func _project_player(p: Vector3) -> void:
	var pp := Vector2(p.x, p.z)
	for k in loops.size():
		var loop: Dictionary = loops[k]
		var pts: PackedVector2Array = loop.pts
		var cum: PackedFloat32Array = loop.cum
		var best := INF
		var best_s := 0.0
		for i in pts.size():
			var a := pts[i]
			var b := pts[(i + 1) % pts.size()]
			var ab := b - a
			var l2 := ab.length_squared()
			var t := 0.0 if l2 < 1e-6 else clampf((pp - a).dot(ab) / l2, 0.0, 1.0)
			var d := (a + ab * t).distance_squared_to(pp)
			if d < best:
				best = d
				best_s = cum[i] + sqrt(l2) * t
		_loop_ps[k] = best_s
		_loop_pl[k] = sqrt(best)


## ---------------------------------------------------------------- cars

func _build_cars() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 31 + 5
	var total := loops.size() * CARS_PER_LOOP
	car_s.resize(total)
	car_v.resize(total)
	car_vmax.resize(total)
	car_brake.resize(total)
	car_loop.resize(total)
	car_leader.resize(total)
	car_pos.resize(total)
	car_fwd.resize(total)
	var i := 0
	for k in loops.size():
		var length: float = loops[k].length
		var first := i
		for j in CARS_PER_LOOP:
			car_loop[i] = k
			car_s[i] = length * (float(j) + rng.randf_range(0.0, 0.35)) / CARS_PER_LOOP
			car_vmax[i] = rng.randf_range(6.0, 8.5)
			car_v[i] = car_vmax[i] * 0.6
			car_brake[i] = 0.0
			car_leader[i] = first + (j + 1) % CARS_PER_LOOP if CARS_PER_LOOP > 1 else -1
			i += 1

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = Figures.car_mesh(Style.WHITE, Style.HEADLIGHT, Style.TAILLIGHT)
	mm.instance_count = total
	var mat := ShaderMaterial.new()
	mat.shader = CAR_SHADER
	mat.set_shader_parameter("body_color", Style.WHITE)
	mat.set_shader_parameter("head_color", Style.HEADLIGHT)
	mat.set_shader_parameter("tail_color", Style.TAILLIGHT)
	mat.set_shader_parameter("body_energy", 0.55)
	car_mmi = _mmi("Autos", mm, mat)


func _wrap(d: float, length: float) -> float:
	return fposmod(d, length)


func _step_cars(dt: float) -> void:
	for i in car_s.size():
		var k := car_loop[i]
		var loop: Dictionary = loops[k]
		var length: float = loop.length
		var s := car_s[i]
		var v := car_v[i]
		var d_obs := INF
		var lead := car_leader[i]
		if lead >= 0 and lead != i:
			d_obs = _wrap(car_s[lead] - s, length) - CAR_GAP
		var green := is_green(int(loop.group))
		if not green:
			var stops: PackedFloat32Array = loop.stops
			for st in stops:
				var d := _wrap(st - s, length)
				if d < 45.0 and d + 0.4 >= v * v / (2.0 * CAR_BRAKE_MAX):
					d_obs = minf(d_obs, d)
		if _loop_pl[k] < PLAYER_LANE:
			var dp := _wrap(_loop_ps[k] - s, length)
			if dp < 16.0:
				d_obs = minf(d_obs, dp - (Figures.CAR_HALF_LEN + 0.9))
		var v_target := car_vmax[i]
		if d_obs < INF:
			v_target = minf(v_target, sqrt(2.0 * CAR_BRAKE * maxf(d_obs, 0.0)))
			if d_obs < 0.15:
				v_target = 0.0
		var braking := v_target < v - 0.05 or v < 0.3
		if v < v_target:
			v = minf(v_target, v + CAR_ACCEL * dt)
		else:
			v = maxf(v_target, v - CAR_BRAKE_MAX * dt)
		var move := v * dt
		if d_obs < INF:
			move = minf(move, maxf(d_obs, 0.0))
		car_s[i] = fposmod(s + move, length)
		car_v[i] = v
		car_brake[i] = 1.0 if braking else 0.0


func _place_cars() -> void:
	var mm := car_mmi.multimesh
	for i in car_s.size():
		_loop_point(loops[car_loop[i]], car_s[i])
		var pos := Vector3(_pt.x, 0.0, _pt.y)
		var fwd := Vector3(_tg.x, 0.0, _tg.y)
		car_pos[i] = pos
		car_fwd[i] = fwd
		var yaw := atan2(-fwd.x, -fwd.z)
		var xf := Transform3D(Basis(Vector3.UP, yaw), pos)
		mm.set_instance_transform(i, xf)
		mm.set_instance_custom_data(i, Color(1.0, car_brake[i], 0.0, 0.0))
		_place_car_lights(i, xf)


func car_count() -> int:
	return car_s.size()


func car_position(i: int) -> Vector3:
	return car_pos[i]


func car_speed(i: int) -> float:
	return car_v[i]


## The point on car i's axis nearest to p (Main pushes the player out of
## CAR_RADIUS around it, the Manhattan obstacle push on a capsule).
func car_closest_point(i: int, p: Vector3) -> Vector3:
	var c := car_pos[i]
	var f := car_fwd[i]
	var t := clampf((p - c).dot(f), -CAR_AXIS_HALF, CAR_AXIS_HALF)
	return c + f * t


## Whether car i stands inside the crossing field.
func car_in_crossing(i: int) -> bool:
	var p := car_pos[i]
	return p.x > CROSS_MIN and p.x < CROSS_MAX and p.z > CROSS_MIN and p.z < CROSS_MAX


## ---------------------------------------------------------------- people

func _build_people() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 17 + 3
	# sidewalk lanes (world m) the ordinary passers-by walk up and down
	var segs := [
		[Vector2(39.65, 12.5), Vector2(39.65, 31.5)], [Vector2(40.35, 31.5), Vector2(40.35, 12.5)],
		[Vector2(51.65, 12.5), Vector2(51.65, 31.5)], [Vector2(52.35, 31.5), Vector2(52.35, 12.5)],
		[Vector2(39.65, 60.5), Vector2(39.65, 89.0)], [Vector2(40.35, 89.0), Vector2(40.35, 60.5)],
		[Vector2(51.65, 60.5), Vector2(51.65, 89.0)], [Vector2(52.35, 89.0), Vector2(52.35, 60.5)],
		[Vector2(2.5, 39.65), Vector2(31.5, 39.65)], [Vector2(31.5, 40.35), Vector2(2.5, 40.35)],
		[Vector2(2.5, 52.35), Vector2(31.5, 52.35)], [Vector2(60.5, 39.65), Vector2(89.0, 39.65)],
		[Vector2(89.0, 52.35), Vector2(60.5, 52.35)], [Vector2(60.5, 51.65), Vector2(89.0, 51.65)],
		[Vector2(3.0, 8.0), Vector2(89.0, 8.0)], [Vector2(89.0, 9.6), Vector2(3.0, 9.6)],
		[Vector2(18.0, 13.0), Vector2(18.0, 37.0)], [Vector2(74.0, 13.0), Vector2(74.0, 37.0)],
		[Vector2(74.0, 55.0), Vector2(74.0, 89.0)], [Vector2(3.0, 70.0), Vector2(37.0, 70.0)],
	]
	var total := WALKER_COUNT + CROWD_PER_CORNER * 4
	p_pos.resize(total)
	p_dir.resize(total)
	p_vis.resize(total)
	p_freq.resize(total)
	p_freq_set.resize(total)
	p_phase.resize(total)
	p_bright.resize(total)
	p_umb.resize(total)
	p_walk_freq.resize(total)
	for i in WALKER_COUNT:
		var sg: Array = segs[i % segs.size()]
		var a: Vector2 = sg[0]
		var b: Vector2 = sg[1]
		var jitter := Vector2(rng.randf_range(-0.12, 0.12), rng.randf_range(-0.12, 0.12))
		w_a.append(a + jitter)
		w_b.append(b + jitter)
		var length := a.distance_to(b)
		w_len.append(length)
		w_s0.append(rng.randf_range(0.0, 2.0 * length))
		var sp := rng.randf_range(1.0, 1.45)
		w_speed.append(sp)
		_init_person(i, rng, sp / 1.45)

	# scramble crowd: corner 0 NW, 1 NE, 2 SW, 3 SE (mirrored about the
	# crossing center 46/46); every member waits at a spot on one of the two
	# sidewalk legs of its corner, crosses straight (along a zebra) or
	# diagonally to a spot at another corner, then walks off into a shop
	var corner_mirror := [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]
	for k in 4:
		for j in CROWD_PER_CORNER:
			var i := WALKER_COUNT + k * CROWD_PER_CORNER + j
			var roll := rng.randf()
			var target := 3 - k # diagonal
			if roll < 0.32:
				target = k ^ 1 # across the north/south arm (NW<->NE, SW<->SE)
			elif roll < 0.64:
				target = k ^ 2 # across the west/east arm (NW<->SW, NE<->SE)
			# local frame of the NW corner, mirrored per corner
			var leg_from := _leg_for(k, target)
			var leg_to := _leg_for(target, k)
			var s_local := _spot_on_leg(leg_from, rng)
			var t_local := _spot_on_leg(leg_to, rng)
			var e_local := _door_on_leg(leg_from, rng)
			var x_local := _door_on_leg(leg_to, rng)
			var sp := _mirror(s_local, corner_mirror[k])
			var tp := _mirror(t_local, corner_mirror[target])
			var ep := _mirror(e_local, corner_mirror[k])
			var xp := _mirror(x_local, corner_mirror[target])
			var anchors := _anchors(k, target, rng)
			var a0: Vector2 = anchors[0]
			var a1: Vector2 = anchors[1]
			c_pts.append_array([ep, sp, a0, a1, tp, xp])
			var v_in := rng.randf_range(1.0, 1.4)
			# arrive at the spot before the walk phase begins
			c_t_in.append(minf(rng.randf_range(35.0, 50.0), WALK_START - 1.5 - ep.distance_to(sp) / v_in))
			c_v_in.append(v_in)
			var delay := rng.randf_range(0.0, 2.5)
			c_delay.append(delay)
			var cross_len := sp.distance_to(a0) + a0.distance_to(a1) + a1.distance_to(tp)
			c_v_cross.append(maxf(rng.randf_range(1.15, 1.55), cross_len / (CROSS_DONE - delay)))
			c_v_out.append(rng.randf_range(1.0, 1.4))
			_init_person(i, rng, 1.0)

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = Figures.walker_mesh(Color.WHITE)
	mm.instance_count = total
	var mat := ShaderMaterial.new()
	mat.shader = WALKER_SHADER
	mat.set_shader_parameter("walker_color", Style.PASSERBY)
	mat.set_shader_parameter("energy", 0.75)
	walker_mmi = _mmi("Passanten", mm, mat)
	for i in total:
		p_freq_set[i] = -1.0


func _init_person(i: int, rng: RandomNumberGenerator, speed_ratio: float) -> void:
	p_phase[i] = rng.randf()
	p_bright[i] = rng.randf_range(0.8, 1.05)
	p_umb[i] = 1.0 if rng.randf() < UMBRELLA_SHARE else 0.0
	p_walk_freq[i] = rng.randf_range(0.82, 0.98) * maxf(speed_ratio, 0.85)
	p_vis[i] = 0
	p_freq[i] = 0.0


## Which sidewalk leg of `corner` faces `target`: 0 = the leg along the
## north-south avenue (faces the corner across the east-west... arm), see
## _spot_on_leg. Straight crossings start on the leg that runs towards the
## arm they cross; diagonals use the corner square itself (leg 2).
func _leg_for(corner: int, target: int) -> int:
	if corner ^ target == 1:
		return 0 # crossing the north/south arm: wait on the leg along the avenue
	if corner ^ target == 2:
		return 1 # crossing the west/east arm
	return 2 # diagonal: the corner square


## A waiting spot on a leg, in the NW corner's frame (the other corners
## mirror it). Leg 0: along the north avenue's west sidewalk; leg 1: along
## the west avenue's north sidewalk; leg 2: the corner square.
func _spot_on_leg(leg: int, rng: RandomNumberGenerator) -> Vector2:
	match leg:
		0:
			return Vector2(rng.randf_range(39.35, 40.85), rng.randf_range(33.5, 38.9))
		1:
			return Vector2(rng.randf_range(33.5, 38.9), rng.randf_range(39.35, 40.85))
	return Vector2(rng.randf_range(39.3, 40.9), rng.randf_range(39.3, 40.9))


## A shop door at the facade a few meters up the leg (where a member comes
## from before the crossing and goes into after it).
func _door_on_leg(leg: int, rng: RandomNumberGenerator) -> Vector2:
	if leg == 0 or (leg == 2 and rng.randf() < 0.5):
		return Vector2(39.12, rng.randf_range(27.0, 33.0))
	return Vector2(rng.randf_range(27.0, 33.0), 39.12)


func _mirror(p: Vector2, m: Vector2) -> Vector2:
	return Vector2(46.0 + (p.x - 46.0) * m.x, 46.0 + (p.y - 46.0) * m.y)


## The two turning points of a crossing from corner k to `target`: on the
## zebra of the arm for straight crossings, near the corners for diagonals.
func _anchors(k: int, target: int, rng: RandomNumberGenerator) -> Array:
	var corner_mirror := [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]
	var jit := rng.randf_range(-0.9, 0.9)
	var a: Vector2
	var b: Vector2
	if k ^ target == 1:
		# across the north or south arm: along its zebra (z 36.2-39.2)
		a = Vector2(41.2, 37.7 + jit)
		b = Vector2(50.8, 37.7 + jit)
		a = _mirror(a, Vector2(1, corner_mirror[k].y))
		b = _mirror(b, Vector2(1, corner_mirror[k].y))
		if corner_mirror[k].x < 0:
			var tmp := a
			a = b
			b = tmp
	elif k ^ target == 2:
		a = Vector2(37.7 + jit, 41.2)
		b = Vector2(37.7 + jit, 50.8)
		a = _mirror(a, Vector2(corner_mirror[k].x, 1))
		b = _mirror(b, Vector2(corner_mirror[k].x, 1))
		if corner_mirror[k].y < 0:
			var tmp2 := a
			a = b
			b = tmp2
	else:
		var off := Vector2(jit, -jit) * 0.8
		a = _mirror(Vector2(41.6, 41.6) + off, corner_mirror[k])
		b = _mirror(Vector2(50.4, 50.4) + off, corner_mirror[k])
	return [a, b]


func _step_people() -> void:
	for i in WALKER_COUNT:
		var length := w_len[i]
		var u := fposmod(w_s0[i] + w_speed[i] * time, 2.0 * length)
		var a := w_a[i]
		var b := w_b[i]
		var d := (b - a) / maxf(length, 0.001)
		var p := a + d * u if u < length else a + d * (2.0 * length - u)
		p_pos[i] = Vector3(p.x, 0.0, p.y)
		p_dir[i] = d if u < length else -d
		p_vis[i] = 1
		p_freq[i] = p_walk_freq[i]
	for j in CROWD_PER_CORNER * 4:
		_crowd_member(WALKER_COUNT + j, j)


## Position of crowd member j (person i) as a pure function of the cycle time.
func _crowd_member(i: int, j: int) -> void:
	var o := j * 6
	var t_in := c_t_in[j]
	var tt := cycle_time
	if tt < t_in - 1.0:
		tt += CYCLE # tail of the previous cycle (walking off)
	var e := c_pts[o]
	var s := c_pts[o + 1]
	var a := c_pts[o + 2]
	var b := c_pts[o + 3]
	var t := c_pts[o + 4]
	var x := c_pts[o + 5]
	if tt < t_in:
		p_vis[i] = 0
		return
	var walking := false
	var pos := s
	var dir := (a - s).normalized()
	var l_in := e.distance_to(s)
	var t_cross := WALK_START + c_delay[j]
	var l1 := s.distance_to(a)
	var l2 := a.distance_to(b)
	var l3 := b.distance_to(t)
	var cross_len := l1 + l2 + l3
	var t_arrive := t_cross + cross_len / c_v_cross[j]
	var l_out := t.distance_to(x)
	var t_gone := t_arrive + l_out / c_v_out[j]
	if tt < WALK_START:
		var d_in := (tt - t_in) * c_v_in[j]
		if d_in < l_in:
			walking = true
			dir = (s - e) / maxf(l_in, 0.001)
			pos = e + dir * d_in
	elif tt < t_cross:
		pass # waiting for the green light, facing the crossing
	elif tt < t_arrive:
		walking = true
		var d := (tt - t_cross) * c_v_cross[j]
		if d < l1:
			dir = (a - s) / maxf(l1, 0.001)
			pos = s + dir * d
		elif d < l1 + l2:
			dir = (b - a) / maxf(l2, 0.001)
			pos = a + dir * (d - l1)
		else:
			dir = (t - b) / maxf(l3, 0.001)
			pos = b + dir * minf(d - l1 - l2, l3)
	elif tt < t_gone:
		walking = true
		dir = (x - t) / maxf(l_out, 0.001)
		pos = t + dir * ((tt - t_arrive) * c_v_out[j])
	else:
		p_vis[i] = 0
		return
	p_vis[i] = 1
	p_pos[i] = Vector3(pos.x, 0.0, pos.y)
	p_dir[i] = dir
	p_freq[i] = p_walk_freq[i] * (c_v_cross[j] / 1.3 if tt >= WALK_START else 1.0) if walking else 0.0


func _place_people() -> void:
	var mm := walker_mmi.multimesh
	var hidden := Transform3D(Basis().scaled(Vector3.ZERO), Vector3(0, -50, 0))
	for i in p_pos.size():
		if p_vis[i] == 0:
			mm.set_instance_transform(i, hidden)
			continue
		var d := p_dir[i]
		var yaw := atan2(-d.x, -d.y)
		mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, yaw), p_pos[i]))
		if p_freq[i] != p_freq_set[i]:
			p_freq_set[i] = p_freq[i]
			mm.set_instance_custom_data(i, Color(p_phase[i], p_freq[i], p_bright[i], p_umb[i]))


func walker_count() -> int:
	return p_pos.size()


func walker_visible(i: int) -> bool:
	return p_vis[i] == 1


func walker_position(i: int) -> Vector3:
	return p_pos[i]


func walker_moving(i: int) -> bool:
	return p_vis[i] == 1 and p_freq[i] > 0.0


## Crowd members (scramble wave) currently visible / walking inside the crossing field.
func crowd_in_crossing() -> int:
	var n := 0
	for i in range(WALKER_COUNT, p_pos.size()):
		var p := p_pos[i]
		if p_vis[i] == 1 and p.x > CROSS_MIN and p.x < CROSS_MAX and p.z > CROSS_MIN and p.z < CROSS_MAX:
			n += 1
	return n


## ---------------------------------------------------------------- rain

func _build_rain() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var q := QuadMesh.new()
	q.size = Vector2(1.0, 1.0)
	mm.mesh = q
	mm.instance_count = RAIN_MAX
	rain_material = ShaderMaterial.new()
	rain_material.shader = RAIN_SHADER
	rain_material.set_shader_parameter("rain_color", Color("c8c0b4"))
	rain_material.set_shader_parameter("pellet_map", _pellet_map())
	if maze_view != null and maze_view.maze != null:
		rain_material.set_shader_parameter("map_size", Vector2(maze_view.maze.cols, maze_view.maze.rows))
	rain_mmi = _mmi("Regen", mm, rain_material)
	rain_mmi.custom_aabb = AABB(Vector3(-10000, -100, -10000), Vector3(20000, 400, 20000))
	_apply_comfort()


## One pixel per cell, white where a pellet lies (the rain thins out there).
func _pellet_map() -> ImageTexture:
	var cols := 47
	var rows := 47
	if maze_view != null and maze_view.maze != null:
		cols = maze_view.maze.cols
		rows = maze_view.maze.rows
	var img := Image.create(cols, rows, false, Image.FORMAT_L8)
	if maze_view != null:
		for cell in maze_view.pellet_cells:
			img.set_pixel(cell.y, cell.x, Color.WHITE)
	return ImageTexture.create_from_image(img)


## "Regen reduzieren" and "Effekte reduzieren" (comfort block).
func set_comfort(rain_reduced: bool, fx_reduced: bool) -> void:
	reduce_rain = rain_reduced
	reduce_fx = fx_reduced
	_apply_comfort()


func rain_visible_count() -> int:
	return rain_mmi.multimesh.visible_instance_count if rain_mmi.multimesh.visible_instance_count >= 0 else RAIN_MAX


func rain_gain() -> float:
	return float(rain_material.get_shader_parameter("gain"))


func _apply_comfort() -> void:
	if rain_mmi == null:
		return
	var share := 1.0
	var gain := 1.0
	if reduce_fx:
		share = RAIN_FX
		gain = 0.8
	if reduce_rain:
		share = RAIN_REDUCED
		gain = 0.6 if not reduce_fx else 0.5
	rain_mmi.multimesh.visible_instance_count = int(RAIN_MAX * share)
	rain_material.set_shader_parameter("gain", gain)


## ---------------------------------------------------------------- lights

func _build_lights() -> void:
	_floor_lights = Wet.static_lights()
	# rain light candidates: the floor's static lights plus each car's headlights
	var fl: Dictionary = _floor_lights
	for i in fl.pos.size():
		var p: Color = fl.pos[i]
		var c: Color = fl.col[i]
		var big: bool = p.a > 1.0
		_rain_pos.append(Color(p.r, p.g, p.b, 0.004 if big else 0.03))
		_rain_col.append(Color(c.r, c.g, c.b, 0.0) * (1.6 if big else 1.0))
		_rain_prio.append(fl.prio[i])
	_static_rain_n = _rain_pos.size()
	for i in car_s.size():
		_rain_pos.append(Color(0, -100, 0, 0.02))
		_rain_col.append(Color(Style.HEADLIGHT.r, Style.HEADLIGHT.g, Style.HEADLIGHT.b) * 1.8)
		_rain_prio.append(3.0)
	_out_pos.resize(Wet.MAX_LIGHTS)
	_out_col.resize(Wet.MAX_LIGHTS)
	_floor_pos.resize(Wet.MAX_LIGHTS)
	_floor_col.resize(Wet.MAX_LIGHTS)
	_score.resize(_rain_pos.size())
	_used.resize(_rain_pos.size())

	# halos: lamps, subway, then 4 per car (head L/R, tail L/R)
	_lamp_count = TokyoScenery.LAMPS.size()
	_halo_car0 = _lamp_count + 1
	var hm := MultiMesh.new()
	hm.transform_format = MultiMesh.TRANSFORM_3D
	hm.use_custom_data = true
	var q := QuadMesh.new()
	q.size = Vector2(1.0, 1.0)
	hm.mesh = q
	hm.instance_count = _halo_car0 + car_s.size() * 4
	var hmat := ShaderMaterial.new()
	hmat.shader = HALO_SHADER
	halo_mmi = _mmi("Halos", hm, hmat)
	# light cones: lamps, subway, then 2 headlight beams per car
	_cone_car0 = _lamp_count + 1
	var cm := MultiMesh.new()
	cm.transform_format = MultiMesh.TRANSFORM_3D
	cm.use_custom_data = true
	cm.mesh = Figures.cone_mesh()
	cm.instance_count = _cone_car0 + car_s.size() * 2
	var cmat := ShaderMaterial.new()
	cmat.shader = CONE_SHADER
	cone_mmi = _mmi("Lichtkegel", cm, cmat)
	# light streaks on the wet asphalt: 5 per car
	var sm := MultiMesh.new()
	sm.transform_format = MultiMesh.TRANSFORM_3D
	sm.use_custom_data = true
	var pm := PlaneMesh.new()
	pm.size = Vector2(1.0, 1.0)
	sm.mesh = pm
	sm.instance_count = car_s.size() * 5
	var smat := ShaderMaterial.new()
	smat.shader = STREAK_SHADER
	smat.set_shader_parameter("puddle_tex", Wet.bake_puddle_mask(seed_value))
	if maze_view != null and maze_view.maze != null:
		smat.set_shader_parameter("map_size", Vector2(maze_view.maze.cols, maze_view.maze.rows) * CELL)
	streak_mmi = _mmi("Lichtstreifen", sm, smat)

	# static entries: sodium lamps (halo + cone down to the floor)
	var lamp_c: Color = Style.LAMP
	for i in _lamp_count:
		var l: Array = TokyoScenery.LAMPS[i]
		var out := Vector3(l[2], 0, l[3])
		var head := Vector3(l[0], TokyoScenery.LAMP_Y - 0.08, l[1]) + out * 1.3
		hm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * 2.6), head))
		hm.set_instance_custom_data(i, Color(lamp_c.r, lamp_c.g, lamp_c.b, 0.0) * 0.55)
		cm.set_instance_transform(i, Figures.cone_transform(head - Vector3(0, 0.15, 0), Vector3(head.x, 0.0, head.z) + out * 0.4, 2.3))
		cm.set_instance_custom_data(i, Color(lamp_c.r, lamp_c.g, lamp_c.b, 0.0) * 0.07)
	# the subway exit: green halo and cone, pulsing at 0.5 Hz (< 3 Hz)
	var mcell: Vector2i = TokyoMaze.METRO_CELL
	var mpos := Vector3(mcell.y * CELL, 0.0, mcell.x * CELL)
	var g: Color = Style.METRO
	hm.set_instance_transform(_lamp_count, Transform3D(Basis().scaled(Vector3.ONE * 6.0), mpos + Vector3(0, 1.5, -0.4)))
	hm.set_instance_custom_data(_lamp_count, Color(g.r * 0.32, g.g * 0.32, g.b * 0.32, 0.5))
	cm.set_instance_transform(_lamp_count, Figures.cone_transform(mpos + Vector3(0, 3.3, -0.6), mpos + Vector3(0, 0.0, 4.2), 2.6))
	cm.set_instance_custom_data(_lamp_count, Color(g.r * 0.09, g.g * 0.09, g.b * 0.09, 0.5))


## Car lights: halos, beams and streaks follow the car transform.
func _place_car_lights(i: int, xf: Transform3D) -> void:
	var hm := halo_mmi.multimesh
	var cm := cone_mmi.multimesh
	var sm := streak_mmi.multimesh
	var head_l := xf * Vector3(-Figures.CAR_HEAD.x, Figures.CAR_HEAD.y, Figures.CAR_HEAD.z - 0.15)
	var head_r := xf * Vector3(Figures.CAR_HEAD.x, Figures.CAR_HEAD.y, Figures.CAR_HEAD.z - 0.15)
	var tail_l := xf * Vector3(-Figures.CAR_TAIL.x, Figures.CAR_TAIL.y, Figures.CAR_TAIL.z + 0.15)
	var tail_r := xf * Vector3(Figures.CAR_TAIL.x, Figures.CAR_TAIL.y, Figures.CAR_TAIL.z + 0.15)
	var w: Color = Style.HEADLIGHT
	var red: Color = Style.TAILLIGHT
	var brake := 1.0 + car_brake[i] * 0.9
	var h0 := _halo_car0 + i * 4
	var head_size := Basis().scaled(Vector3.ONE * 1.7)
	var tail_size := Basis().scaled(Vector3.ONE * 1.1)
	hm.set_instance_transform(h0, Transform3D(head_size, head_l))
	hm.set_instance_transform(h0 + 1, Transform3D(head_size, head_r))
	hm.set_instance_transform(h0 + 2, Transform3D(tail_size, tail_l))
	hm.set_instance_transform(h0 + 3, Transform3D(tail_size, tail_r))
	hm.set_instance_custom_data(h0, Color(w.r, w.g, w.b, 0.0) * 0.95)
	hm.set_instance_custom_data(h0 + 1, Color(w.r, w.g, w.b, 0.0) * 0.95)
	hm.set_instance_custom_data(h0 + 2, Color(red.r, red.g, red.b, 0.0) * (0.55 * brake))
	hm.set_instance_custom_data(h0 + 3, Color(red.r, red.g, red.b, 0.0) * (0.55 * brake))
	var fwd := -xf.basis.z.normalized()
	var c0 := _cone_car0 + i * 2
	cm.set_instance_transform(c0, Figures.cone_transform(head_l, head_l + fwd * 15.0 - Vector3(0, head_l.y, 0), 2.4))
	cm.set_instance_transform(c0 + 1, Figures.cone_transform(head_r, head_r + fwd * 15.0 - Vector3(0, head_r.y, 0), 2.4))
	cm.set_instance_custom_data(c0, Color(w.r, w.g, w.b, 0.0) * 0.045)
	cm.set_instance_custom_data(c0 + 1, Color(w.r, w.g, w.b, 0.0) * 0.045)
	var s0 := i * 5
	sm.set_instance_transform(s0, Transform3D(Basis(), head_l))
	sm.set_instance_transform(s0 + 1, Transform3D(Basis(), head_r))
	sm.set_instance_transform(s0 + 2, Transform3D(Basis(), tail_l))
	sm.set_instance_transform(s0 + 3, Transform3D(Basis(), tail_r))
	sm.set_instance_transform(s0 + 4, xf)
	sm.set_instance_custom_data(s0, Color(w.r * 1.1, w.g * 1.1, w.b * 1.1, 0.42))
	sm.set_instance_custom_data(s0 + 1, Color(w.r * 1.1, w.g * 1.1, w.b * 1.1, 0.42))
	sm.set_instance_custom_data(s0 + 2, Color(red.r, red.g, red.b, 0.0) * (0.8 * brake) + Color(0, 0, 0, 0.34))
	sm.set_instance_custom_data(s0 + 3, Color(red.r, red.g, red.b, 0.0) * (0.8 * brake) + Color(0, 0, 0, 0.34))
	sm.set_instance_custom_data(s0 + 4, Color(w.r * 0.16, w.g * 0.16, w.b * 0.16, -9.0))
	# the rain candidate of this car: between its headlights
	var hc := (head_l + head_r) * 0.5 + fwd * 0.4
	var rp: Color = _rain_pos[_static_rain_n + i]
	rp.r = hc.x
	rp.g = hc.y
	rp.b = hc.z
	_rain_pos[_static_rain_n + i] = rp


## The 8 lights nearest to the camera for the rain (with headlights) and
## the floor (lamps, screens, subway).
func _update_lights(cam: Vector3) -> void:
	var n := Wet.nearest(cam, _rain_pos, _rain_col, _rain_prio, _rain_pos.size(), _out_pos, _out_col, _score, _used)
	rain_material.set_shader_parameter("light_pos", _out_pos)
	rain_material.set_shader_parameter("light_col", _out_col)
	rain_material.set_shader_parameter("light_n", n)
	if floor_material != null:
		var fl: Dictionary = _floor_lights
		var n2 := Wet.nearest(cam, fl.pos, fl.col, fl.prio, fl.pos.size(), _floor_pos, _floor_col, _score, _used)
		floor_material.set_shader_parameter("light_pos", _floor_pos)
		floor_material.set_shader_parameter("light_col", _floor_col)
		floor_material.set_shader_parameter("light_n", n2)


## ---------------------------------------------------------------- helpers

func _mmi(node_name: String, mm: MultiMesh, mat: Material) -> MultiMeshInstance3D:
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(-60, -10, -60), Vector3(220, 140, 220))
	add_child(mmi)
	return mmi


## Draw calls of the moving city (one per MultiMesh).
func draw_calls() -> int:
	var n := 0
	for ch in get_children():
		if ch is GeometryInstance3D and ch.visible:
			n += 1
	return n
