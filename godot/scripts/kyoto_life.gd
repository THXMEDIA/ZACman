extends Node3D
## KyotoLife — the passers-by of the Kyoto pop-up city: paper figures in the
## same print as the houses (yukata, a person under a vermilion wagasa, a
## tourist with a backpack) who walk the lanes slowly, back and forth on a
## street segment or round a ring of streets. Main creates it for an Explorer
## city with traffic "kyoto" (explorer_cities.gd) and calls update() every
## frame while the level runs.
##
## Harmless, like Tokyo's passers-by: no life lost, at most a soft push when
## the player steps into one (Main, WALKER_RADIUS). The camera is never
## touched. The routes keep to the lane sides: a lane is 6 m wide, a figure's
## push circle 0.8 m, so there is always a free lane past every figure
## (tests/test_kyoto.gd measures it).
##
## Draw calls: ONE MultiMesh for all figures (the card shader of the city,
## kind K_WALKER). Every figure is a standing card turned to the camera
## (yaw only) and mirrored in its direction of travel (instance COLOR.g, only
## written when the direction flips). All state sits in packed arrays; a frame
## allocates nothing (tests count objects). "Effekte reduzieren": everybody
## stands still (set_comfort).
##
## Deterministic for a level seed: same seed and same steps -> same walkers.

const Style := preload("res://scripts/kyoto_style.gd")
const CardShader := preload("res://shaders/kyoto_card.gdshader")

const CARD_BASE_Y := 0.07
const WALKER_W := 1.5
const WALKER_H := 1.75
const WALKER_RADIUS := 0.4 # push circle around a figure (player radius 0.34)
const SPEED_MIN := 0.7 # m/s, slow strolling (the player runs 5 m/s)
const SPEED_MAX := 1.1
const BOB_AMP := 0.035
const BOB_HZ := 1.7

## Routes in world metres (x east, z south), kept 1.4-2.5 m from the facades
## of their 6 m wide lanes. "loop" routes are closed (the last point joins
## the first), the others are walked back and forth. `n` = walkers on it.
const ROUTES := [
	{"id": "shijo_west", "pts": [Vector2(14.0, 18.4), Vector2(44.0, 18.4)], "n": 1},
	{"id": "shijo_west2", "pts": [Vector2(20.0, 22.2), Vector2(40.0, 22.2)], "n": 1},
	{"id": "shijo_mid", "pts": [Vector2(52.0, 23.2), Vector2(88.0, 23.2)], "n": 2},
	{"id": "shijo_east", "pts": [Vector2(56.0, 17.5), Vector2(92.0, 17.5)], "n": 1},
	{"id": "hanamikoji_nord", "pts": [Vector2(44.8, 4.0), Vector2(44.8, 13.0)], "n": 1},
	{"id": "hanamikoji_a", "pts": [Vector2(44.8, 28.0), Vector2(44.8, 58.0)], "n": 2},
	{"id": "hanamikoji_b", "pts": [Vector2(47.4, 56.0), Vector2(47.4, 84.0)], "n": 1},
	{"id": "seitengasse_a", "pts": [Vector2(10.0, 43.4), Vector2(58.0, 43.4)], "n": 1},
	{"id": "seitengasse_b", "pts": [Vector2(12.0, 40.6), Vector2(40.0, 40.6)], "n": 1},
	{"id": "yasaka", "pts": [Vector2(53.0, 63.4), Vector2(70.0, 63.4)], "n": 1},
	{"id": "sannenzaka_a", "pts": [Vector2(53.0, 72.6), Vector2(82.0, 72.6)], "n": 2},
	{"id": "sannenzaka_b", "pts": [Vector2(60.0, 75.4), Vector2(84.0, 75.4)], "n": 1},
	{"id": "ninenzaka_nord", "pts": [Vector2(89.5, 28.0), Vector2(89.5, 44.0)], "n": 1},
	# the ring: Shijo-dori east, Ninenzaka south, Seitengasse west, Hanamikoji north
	{"id": "ring", "loop": true, "n": 3, "pts": [Vector2(47.6, 21.6), Vector2(86.4, 21.6), Vector2(86.4, 40.4), Vector2(47.6, 40.4)]},
]

var seed_value := 0
var time := 0.0
var still := false # "Effekte reduzieren"
var walker_mmi: MultiMeshInstance3D

var _route_pts: Array = [] # Array[PackedVector2Array]
var _route_len := PackedFloat32Array()
var _route_loop := PackedByteArray()
var w_route := PackedInt32Array()
var w_u := PackedFloat32Array() # progress along the route (m; ping-pong: 0..2L)
var w_speed := PackedFloat32Array()
var w_s := PackedFloat32Array() # variation 0..1 = the figure's look
var w_phase := PackedFloat32Array()
var w_flip := PackedByteArray() # last flip written to the MultiMesh
var w_pos := PackedVector3Array()
var w_dir := PackedVector2Array() # unit direction of travel
var _yaw := PackedFloat32Array()
var _scale: Basis


## Deterministic walker list for a level seed (also used by tests):
## [{route, u, speed, s, phase}].
static func specs(level_seed: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = level_seed ^ 0x6B79
	var out: Array = []
	for r in ROUTES.size():
		var route: Dictionary = ROUTES[r]
		var n: int = route.n
		var length := route_length(route)
		var period := length if route.get("loop", false) else 2.0 * length
		var off := rng.randf()
		for k in n:
			out.append({
				"route": r,
				"u": fposmod((off + float(k) / float(n)) * period + rng.randf_range(-0.08, 0.08) * period, period),
				"speed": rng.randf_range(SPEED_MIN, SPEED_MAX),
				"s": rng.randf(),
				"phase": rng.randf(),
			})
	return out


static func route_length(route: Dictionary) -> float:
	var pts: Array = route.pts
	var total := 0.0
	var n: int = pts.size()
	var segs: int = n if route.get("loop", false) else n - 1
	for i in segs:
		total += (pts[i] as Vector2).distance_to(pts[(i + 1) % n])
	return total


func setup(_view: Node3D, level_seed: int) -> void:
	seed_value = level_seed
	name = "KyotoLife"
	_scale = Basis.from_scale(Vector3(WALKER_W, WALKER_H, WALKER_H))
	_route_pts.clear()
	_route_len.resize(ROUTES.size())
	_route_loop.resize(ROUTES.size())
	for r in ROUTES.size():
		var route: Dictionary = ROUTES[r]
		var pts := PackedVector2Array()
		for p in route.pts:
			pts.append(p)
		_route_pts.append(pts)
		_route_len[r] = route_length(route)
		_route_loop[r] = 1 if route.get("loop", false) else 0
	var list := specs(level_seed)
	var n := list.size()
	w_route.resize(n)
	w_u.resize(n)
	w_speed.resize(n)
	w_s.resize(n)
	w_phase.resize(n)
	w_flip.resize(n)
	w_pos.resize(n)
	w_dir.resize(n)
	_yaw.resize(n)
	for i in n:
		var sp: Dictionary = list[i]
		w_route[i] = sp.route
		w_u[i] = sp.u
		w_speed[i] = sp.speed
		w_s[i] = sp.s
		w_phase[i] = sp.phase
		w_flip[i] = 0
		_yaw[i] = 0.0
		_sample(i)

	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	quad.center_offset = Vector3(0.0, 0.5, 0.0)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.use_colors = true
	mm.mesh = quad
	mm.instance_count = n
	for i in n:
		mm.set_instance_custom_data(i, Color(float(Style.K_WALKER + Style.NO_FOLD) / 255.0, WALKER_W / 100.0, WALKER_H / 100.0, w_s[i]))
		mm.set_instance_color(i, Color(0.0, 0.0, 0.0, 1.0))
	mm.custom_aabb = AABB(Vector3(-10.0, -1.0, -10.0), Vector3(130.0, 4.0, 120.0))
	var mat := ShaderMaterial.new()
	mat.shader = CardShader
	mat.set_shader_parameter("ai1", Style.AI1)
	mat.set_shader_parameter("ai2", Style.AI2)
	mat.set_shader_parameter("ai3", Style.AI3)
	mat.set_shader_parameter("ai4", Style.AI4)
	mat.set_shader_parameter("paper", Style.PAPER)
	mat.set_shader_parameter("sumi", Style.SUMI)
	mat.set_shader_parameter("beni", Style.BENI)
	mat.set_shader_parameter("blossom", Style.BLOSSOM)
	walker_mmi = MultiMeshInstance3D.new()
	walker_mmi.name = "Passanten"
	walker_mmi.multimesh = mm
	walker_mmi.material_override = mat
	walker_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(walker_mmi)
	update(0.0, Vector3(-1000, 0, -1000), Vector3(12.0, 1.0, 20.0))


func draw_calls() -> int:
	return 1


func set_comfort(reduce_fx: bool) -> void:
	still = reduce_fx


func walker_count() -> int:
	return w_pos.size()


func walker_position(i: int) -> Vector3:
	return w_pos[i]


## All figures are always visible (they are paper figures standing in the lanes).
func walker_visible(_i: int) -> bool:
	return true


func walker_moving(_i: int) -> bool:
	return not still


## One frame: walk, then place the figures facing the camera.
func update(delta: float, _player_pos: Vector3, cam_pos: Vector3) -> void:
	_step(delta)
	_place(cam_pos)


## Fast-forward `seconds` in fixed steps (tests, screenshots).
func advance(seconds: float, cam_pos: Vector3 = Vector3(12.0, 1.0, 20.0), step: float = 1.0 / 30.0) -> void:
	var n := int(ceil(seconds / step))
	for i in n:
		_step(step)
	_place(cam_pos)


func _step(delta: float) -> void:
	if still:
		return
	time += delta
	for i in w_u.size():
		var r: int = w_route[i]
		var period: float = _route_len[r] if _route_loop[r] == 1 else 2.0 * _route_len[r]
		w_u[i] = fposmod(w_u[i] + w_speed[i] * delta, period)
		_sample(i)


## Position and direction of walker i from its progress w_u.
func _sample(i: int) -> void:
	var r: int = w_route[i]
	var pts: PackedVector2Array = _route_pts[r]
	var length: float = _route_len[r]
	var loop := _route_loop[r] == 1
	var u: float = w_u[i]
	var sign_dir := 1.0
	if not loop and u > length:
		u = 2.0 * length - u
		sign_dir = -1.0
	var n := pts.size()
	var segs := n if loop else n - 1
	var acc := 0.0
	for k in segs:
		var a := pts[k]
		var b := pts[(k + 1) % n]
		var l := a.distance_to(b)
		if u <= acc + l or k == segs - 1:
			var t := clampf((u - acc) / maxf(l, 0.001), 0.0, 1.0)
			var p := a.lerp(b, t)
			w_pos[i] = Vector3(p.x, CARD_BASE_Y, p.y)
			w_dir[i] = (b - a).normalized() * sign_dir
			return
		acc += l


func _place(cam_pos: Vector3) -> void:
	var mm := walker_mmi.multimesh
	for i in w_pos.size():
		var p := w_pos[i]
		var to_x := cam_pos.x - p.x
		var to_z := cam_pos.z - p.z
		if to_x * to_x + to_z * to_z > 0.04:
			_yaw[i] = atan2(to_x, to_z)
		var yaw := _yaw[i]
		var bob := 0.0 if still else absf(sin((time * BOB_HZ + w_phase[i]) * PI)) * BOB_AMP
		# the card's local +x in the world is (cos yaw, 0, -sin yaw)
		var d := w_dir[i]
		var right := d.x * cos(yaw) - d.y * sin(yaw)
		var flip := 1 if right < -0.02 else (0 if right > 0.02 else int(w_flip[i]))
		if flip != w_flip[i]:
			w_flip[i] = flip
			mm.set_instance_color(i, Color(0.0, float(flip), 0.0, 1.0))
		mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, yaw) * _scale, Vector3(p.x, p.y + bob, p.z)))
