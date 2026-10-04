extends Node3D
## KyotoExit — the exit of the Kyoto Explorer city, at the foot of the
## Kiyomizu stage: a page door folded open onto green light, and a long green
## bookmark ribbon hanging from the sky, visible over the roofs from far away
## (green is exclusive to the exit). Same interface as the other stations
## (Main: setup(pos), update(delta, now), distance check). The facade is one
## cell south of the exit cell (kyoto_maze.gd METRO_CELL), so the door sits
## at local z = +0.95. Pulse 0.5 Hz, far below the flicker limit; the ribbon
## never folds and ignores fog so it always guides.

const Style := preload("res://scripts/kyoto_style.gd")
const TokyoScenery := preload("res://scripts/tokyo_scenery.gd")

const PULSE_HZ := 0.5
const DOOR_Z := 0.95
const RIBBON_TOP := 15.0

var door_light: MeshInstance3D
var pad: MeshInstance3D
var flap: MeshInstance3D
var ribbon: MeshInstance3D
var sign_label: Label3D
var _glow_mat: StandardMaterial3D
var _t := 0.0


static func _unshaded(col: Color, no_fog := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_fog = no_fog
	return m


func setup(cell_world_pos: Vector3) -> void:
	position = Vector3(cell_world_pos.x, 0.0, cell_world_pos.z)
	_glow_mat = _unshaded(Style.EXIT)

	# the doorway: green light in the page
	door_light = MeshInstance3D.new()
	door_light.name = "Doorway"
	var dq := QuadMesh.new()
	dq.size = Vector2(2.0, 2.5)
	door_light.mesh = dq
	door_light.material_override = _glow_mat
	door_light.position = Vector3(0.0, 1.32, DOOR_Z)
	door_light.rotation.y = PI
	add_child(door_light)

	# frame of ink around the doorway
	var frame := MeshInstance3D.new()
	var fq := QuadMesh.new()
	fq.size = Vector2(2.3, 2.75)
	frame.mesh = fq
	frame.material_override = _unshaded(Style.SUMI)
	frame.position = Vector3(0.0, 1.38, DOOR_Z + 0.01)
	frame.rotation.y = PI
	add_child(frame)

	# the page flap, folded open into the lane (hinge on the west side)
	flap = MeshInstance3D.new()
	flap.name = "PageFlap"
	var flq := QuadMesh.new()
	flq.size = Vector2(2.0, 2.5)
	flq.center_offset = Vector3(1.0, 1.25, 0.0)
	flap.mesh = flq
	flap.material_override = _unshaded(Style.PAPER)
	flap.position = Vector3(-1.0, 0.07, DOOR_Z - 0.01)
	flap.rotation.y = PI - 1.15
	add_child(flap)

	# green light pad on the page in front of the door
	pad = MeshInstance3D.new()
	pad.name = "Pad"
	var pm := PlaneMesh.new()
	pm.size = Vector2(2.2, 1.6)
	pad.mesh = pm
	pad.material_override = _glow_mat
	pad.position = Vector3(0.0, 0.03, 0.1)
	add_child(pad)

	# bookmark ribbon: from the sky down to just above the door, V-notched end
	ribbon = MeshInstance3D.new()
	ribbon.name = "Bookmark"
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hw := 0.33
	var y0 := 3.0
	var pts := [Vector3(-hw, y0, 0), Vector3(0, y0 + 0.45, 0), Vector3(hw, y0, 0), Vector3(hw, RIBBON_TOP, 0), Vector3(-hw, RIBBON_TOP, 0)]
	for tri in [[0, 1, 4], [1, 3, 4], [1, 2, 3]]:
		for k in tri:
			st.add_vertex(pts[k])
	ribbon.mesh = st.commit()
	ribbon.material_override = _unshaded(Style.EXIT, true)
	ribbon.position = Vector3(1.45, 0.0, DOOR_Z - 0.05)
	add_child(ribbon)

	sign_label = Label3D.new()
	sign_label.text = "出口  EXIT"
	var font := TokyoScenery.load_sign_font()
	if font != null:
		sign_label.font = font
	sign_label.font_size = 64
	sign_label.pixel_size = 0.006
	sign_label.modulate = Style.PAPER
	sign_label.outline_modulate = Style.SUMI
	sign_label.outline_size = 10
	sign_label.position = Vector3(0.0, 2.95, DOOR_Z - 0.02)
	sign_label.rotation.y = PI
	sign_label.double_sided = false
	add_child(sign_label)


func update(delta: float, _now: float) -> void:
	_t += delta
	var p := 0.93 + 0.07 * sin(_t * TAU * PULSE_HZ)
	_glow_mat.albedo_color = Style.EXIT * p
	_glow_mat.albedo_color.a = 1.0
