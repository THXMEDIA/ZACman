extends Node3D
## AmsterdamExit — the exit of the Amsterdam Explorer city: a tram stop on the
## Amstel bank with a green-painted cardboard tram (generic, no operator's
## colours or logos), lit from inside, and a giant pin with a green paper flag
## stuck into the tram block, high over the roofs so it guides from far away
## (green #00B894 is exclusive to the exit). Same interface as the other
## stations (Main: setup(pos), update(delta, now), distance check) plus
## set_reduce_fx: the 0.5 Hz pulse of the inner light and the flag stops with
## "Effekte reduzieren". The exit cell is the platform; the tram stands one
## cell further east, behind the kerb (the collision edge). Its open double
## door (1.2 m) faces the platform right where the last pin stands, the inner
## light shines out of it onto a bright green spot on the platform, and the
## trigger lies centred in front of the door (UX W-B).

const Style := preload("res://scripts/amsterdam_style.gd")
const Scenery := preload("res://scripts/amsterdam_scenery.gd")
const SPOT_SHADER := preload("res://shaders/amsterdam_spot.gdshader")
## Emission of the green paint (share of #00B894), so the tram stays green
## in the low sun (QA K2).
const EXIT_EMIT := 0.32


const PULSE_HZ := 0.5
## Tram centre relative to the exit cell (local x east), length along z.
const TRAM_X := 2.75
const TRAM_L := 11.0
const TRAM_W := 2.5
const TRAM_H := 3.2
## The pin with the flag: on the tram block, behind the tram, 24 m high.
const FLAG_POS := Vector3(5.6, 0.0, -4.0)
const FLAG_TOP := 24.0
## The open double door in the tram's platform side (local z centre, width).
const DOOR_Z := 0.0
const DOOR_W := 1.2
const DOOR_H := 2.3

var tram: MultiMeshInstance3D
var glow: MeshInstance3D
var light: OmniLight3D
var flag: MeshInstance3D
var pin_head: MeshInstance3D
var door_light: MeshInstance3D
var floor_spot: MeshInstance3D
var panel_material: ShaderMaterial
var _glow_mat: StandardMaterial3D
var _flag_mat: StandardMaterial3D
var _door_mat: StandardMaterial3D
var _spot_mat: ShaderMaterial
var _t := 0.0
var _reduce_fx := false


static func _unshaded(col: Color, no_fog := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_fog = no_fog
	return m


## The boards of the tram, the stop and the pin, in the node's frame.
static func panels() -> Array:
	var K := Scenery.Kit.new()
	K.rng.seed = 2121
	var G := Scenery.PAINT_EXIT
	var c := Vector3(TRAM_X, 0, 0)
	var L := TRAM_L
	var W := TRAM_W
	var H := TRAM_H
	var t := Style.T * 0.5
	var dz0 := DOOR_Z - DOOR_W * 0.5
	var dz1 := DOOR_Z + DOOR_W * 0.5
	for s in [-1.0, 1.0]:
		if s < 0.0:
			# platform side: the lower band is cut for the open door
			var la := dz0 + L * 0.5
			var lb := L * 0.5 - dz1
			K.board(c + Vector3(s * W * 0.5, 0.75, -L * 0.5 + la * 0.5), Vector3(t, 1.1, la), 0.6, Basis(), G)
			K.board(c + Vector3(s * W * 0.5, 0.75, dz1 + lb * 0.5), Vector3(t, 1.1, lb), 0.6, Basis(), G)
			# door posts (the upper band is the lintel)
			for z in [dz0 - 0.08, dz1 + 0.08]:
				K.board(c + Vector3(s * W * 0.5, (0.2 + H - 0.7) * 0.5, z), Vector3(t, H - 0.9, 0.16), 0.6, Basis(), G)
			# the two door leaves, folded open into the car
			for side in [-1.0, 1.0]:
				var hz: float = DOOR_Z + side * DOOR_W * 0.5
				K.board(c + Vector3(s * W * 0.5 + 0.28, 0.2 + DOOR_H * 0.5, hz - side * 0.1), Vector3(0.06, DOOR_H, 0.6), 0.6, Basis(Vector3.UP, side * 1.15), G)
			# the step into the car
			K.board(c + Vector3(s * W * 0.5 - 0.1, 0.12, DOOR_Z), Vector3(0.3, 0.06, DOOR_W), 0.6, Basis(), G)
		else:
			K.board(c + Vector3(s * W * 0.5, 0.75, 0), Vector3(t, 1.1, L), 0.6, Basis(), G)
		K.board(c + Vector3(s * W * 0.5, H - 0.35, 0), Vector3(t, 0.7, L), 0.6, Basis(), G)
		for k in 6:
			K.board(c + Vector3(s * W * 0.5, 1.8, -L * 0.5 + 0.2 + k * (L - 0.4) / 5.0), Vector3(t, 1.0, 0.3), 0.6, Basis(), G)
	# the floor of the car (seen through the open door)
	K.board(c + Vector3(0, 0.22, 0), Vector3(W - 0.1, 0.06, L - 0.2), 0.6)
	for s in [-1.0, 1.0]:
		K.board(c + Vector3(0, 0.85, s * L * 0.5), Vector3(W, 1.3, t), 0.6, Basis(), G)
		K.board(c + Vector3(0, H - 0.3, s * L * 0.5), Vector3(W, 0.6, t), 0.6, Basis(), G)
		for sx in [-1.0, 0.0, 1.0]:
			K.board(c + Vector3(sx * (W * 0.5 - 0.12), 1.95, s * L * 0.5), Vector3(0.24 if sx != 0.0 else 0.12, 1.0, t), 0.6, Basis(), G)
		# a dark (unlit) destination board, no text
		K.board(c + Vector3(0, H - 0.3, s * (L * 0.5 + 0.12)), Vector3(1.4, 0.32, 0.06), 0.0, Basis(), 0.0, Scenery.FLAG_SOLID)
	# roof, bogies, pantograph
	K.board(c + Vector3(0, H + 0.05, 0), Vector3(W + 0.2, t, L + 0.3), 0.6, Basis(), G)
	for s in [-1.0, 1.0]:
		K.board(c + Vector3(0, 0.12, s * L * 0.3), Vector3(W - 0.5, 0.24, 2.4), 0.0, Basis(), 0.0, Scenery.FLAG_SOLID)
	K.board(c + Vector3(0, H + 0.7, -0.6), Vector3(0.12, 1.4, 0.12), 0.6, Basis(Vector3(1, 0, 0), 0.6), G)
	K.board(c + Vector3(0, H + 0.7, 0.6), Vector3(0.12, 1.4, 0.12), 0.6, Basis(Vector3(1, 0, 0), -0.6), G)
	K.board(c + Vector3(0, H + 1.3, 0), Vector3(1.6, 0.08, 0.12), 0.0, Basis(), 0.0, Scenery.FLAG_SOLID)
	# rails, laid into the plate
	for s in [-0.72, 0.72]:
		K.board(c + Vector3(s, 0.04, 0), Vector3(0.16, 0.08, 17.0), 0.0, Basis(), 0.0, Scenery.FLAG_SOLID)
	# the stop: a post with a round board and a bench on the tram block's kerb
	K.board(Vector3(1.25, 1.4, 6.2), Vector3(0.16, 2.8, 0.16), 0.6)
	K.board(Vector3(1.25, 2.9, 6.2), Vector3(0.1, 0.9, 0.9), 0.6, Basis(), G)
	# the giant pin's needle (steel), from the plate up to the flag
	K.board(FLAG_POS + Vector3(0, FLAG_TOP * 0.5, 0), Vector3(0.22, FLAG_TOP, 0.22), 0.0, Basis(), 0.0, Scenery.FLAG_SOLID)
	return K.panels


func setup(cell_world_pos: Vector3) -> void:
	position = Vector3(cell_world_pos.x, 0.0, cell_world_pos.z)
	panel_material = Scenery.panel_material()
	tram = MultiMeshInstance3D.new()
	tram.name = "Tram"
	tram.multimesh = Scenery.panel_multimesh(panels())
	tram.material_override = panel_material
	add_child(tram)

	# the light inside the tram: a bright sheet behind the windows
	_glow_mat = _unshaded(Style.EXIT.lerp(Color.WHITE, 0.55))
	glow = MeshInstance3D.new()
	glow.name = "InnerLight"
	var qm := QuadMesh.new()
	qm.size = Vector2(TRAM_L - 0.6, 2.4)
	glow.mesh = qm
	glow.material_override = _glow_mat
	glow.position = Vector3(TRAM_X + 0.2, 1.75, 0)
	glow.rotation.y = PI * 0.5
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(glow)
	# the light pouring out of the open door: a bright sheet just inside it
	_door_mat = _unshaded(Style.EXIT.lerp(Color.WHITE, 0.7))
	door_light = MeshInstance3D.new()
	door_light.name = "DoorLight"
	var dq := QuadMesh.new()
	dq.size = Vector2(DOOR_W + 0.2, DOOR_H)
	door_light.mesh = dq
	door_light.material_override = _door_mat
	door_light.position = Vector3(TRAM_X - TRAM_W * 0.5 + 0.75, 0.2 + DOOR_H * 0.5, DOOR_Z)
	door_light.rotation.y = PI * 0.5
	door_light.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(door_light)
	# a bright green spot on the platform in front of the door (painted, soft)
	_spot_mat = ShaderMaterial.new()
	_spot_mat.shader = SPOT_SHADER
	_spot_mat.set_shader_parameter("col", Style.EXIT.lerp(Color.WHITE, 0.35))
	floor_spot = MeshInstance3D.new()
	floor_spot.name = "FloorSpot"
	var fq := PlaneMesh.new()
	fq.size = Vector2(2.6, 2.4)
	floor_spot.mesh = fq
	floor_spot.material_override = _spot_mat
	floor_spot.position = Vector3(TRAM_X - TRAM_W * 0.5 - 1.3, 0.015, DOOR_Z)
	floor_spot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(floor_spot)
	light = OmniLight3D.new()
	light.name = "TramLight"
	light.light_color = Style.EXIT.lerp(Color.WHITE, 0.25)
	light.light_energy = 2.2
	light.omni_range = 8.0
	light.shadow_enabled = false
	light.position = Vector3(TRAM_X - 0.6, 1.9, DOOR_Z)
	add_child(light)

	# the flag: a green paper pennant near the top of the pin, never fogged
	_flag_mat = _unshaded(Style.EXIT, true)
	flag = MeshInstance3D.new()
	flag.name = "Flag"
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var y1 := FLAG_TOP - 0.6
	var y0 := y1 - 3.4
	var pts := [Vector3(0, y0, 0), Vector3(0, y1, 0), Vector3(5.2, y1 - 0.4, 0), Vector3(4.0, (y0 + y1) * 0.5 - 0.2, 0), Vector3(5.2, y0 + 0.2, 0)]
	for rot in [0.0, PI * 0.5]:
		var b := Basis(Vector3.UP, rot + 0.4)
		for tri in [[0, 1, 3], [1, 2, 3], [0, 3, 4]]:
			for k in tri:
				st.add_vertex(b * pts[k])
	flag.mesh = st.commit()
	flag.material_override = _flag_mat
	flag.position = FLAG_POS
	flag.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(flag)
	pin_head = MeshInstance3D.new()
	pin_head.name = "PinHead"
	var sp := SphereMesh.new()
	sp.radius = 0.9
	sp.height = 1.8
	pin_head.mesh = sp
	pin_head.material_override = _flag_mat
	pin_head.position = FLAG_POS + Vector3(0, FLAG_TOP + 0.6, 0)
	add_child(pin_head)


func set_reduce_fx(on: bool) -> void:
	_reduce_fx = on
	if on:
		_apply(1.0)


func pulse_enabled() -> bool:
	return not _reduce_fx


func update(delta: float, _now: float) -> void:
	_t += delta
	if _reduce_fx:
		return
	_apply(0.92 + 0.08 * sin(_t * TAU * PULSE_HZ))


func _apply(p: float) -> void:
	if _glow_mat == null:
		return
	var g := Style.EXIT.lerp(Color.WHITE, 0.55) * p
	g.a = 1.0
	_glow_mat.albedo_color = g
	var f := Style.EXIT * (0.96 + 0.04 * p)
	f.a = 1.0
	_flag_mat.albedo_color = f
	light.light_energy = 2.2 * p
	var dg := Style.EXIT.lerp(Color.WHITE, 0.7) * p
	dg.a = 1.0
	_door_mat.albedo_color = dg
	_spot_mat.set_shader_parameter("strength", 0.85 * p)
	# QA K2: the paint keeps its green in the evening sun (the panel shader
	# darkens the exit albedo and adds this much of it as emission)
	panel_material.set_shader_parameter("exit_emit", EXIT_EMIT * p)
