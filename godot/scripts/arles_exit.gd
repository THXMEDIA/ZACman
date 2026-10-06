extends Node3D
## ArlesExit — the exit of the Arles Explorer city: the Yellow House on the
## Place Lamartine (historically reconstructed: two storeys, ochre yellow, the
## shop of 1888 gone since 1944 - no plaque, no lettering), seen frontally
## from the square. Its door and shutters are green, as they were, in mint
## green #3AF5C8 (exclusive to the exit), and a green star stands 18 m high
## over the house, visible over the roofs from everywhere (the Arles
## equivalent of the subway sign). Same interface as the other stations
## (Main: setup(pos), update(delta, now), distance check) plus set_reduce_fx:
## the 0.5 Hz pulse of door, shutters, star and light stops with "Effekte
## reduzieren". The door is flush with the north edge of the exit cell.

const Style := preload("res://scripts/arles_style.gd")
const Scenery := preload("res://scripts/arles_scenery.gd")

const PULSE_HZ := Style.PULSE_HZ
## Map-space position of the exit node (the exit cell's centre).
const MAP_ORIGIN := Vector3(15.0, 0.0, 3.0)
const DOOR := Vector3(15.0, 1.4, 2.04) # map space
const STAR := Vector3(15.0, 18.0, -1.0)
const STAR_SIZE := 7.0
const LIGHT_ENERGY := 2.2

var house: MeshInstance3D
var door: MeshInstance3D
var shutters: MeshInstance3D
var star: MultiMeshInstance3D
var light: OmniLight3D
var door_material: ShaderMaterial
var shutter_material: ShaderMaterial
var star_material: ShaderMaterial
var house_parts: Array = []
var _t := 0.0
var _reduce_fx := false


static func local(p: Vector3) -> Vector3:
	return p - MAP_ORIGIN


## The house itself (brush materials): body, hipped roof, lit windows, the
## two brown side doors, the lintel over the green door.
static func house_buf() -> Scenery.Buf:
	var B := Scenery.Buf.new()
	B.box(local(Vector3(15.0, 4.0, -2.0)), Vector3(6.0, 8.0, 8.0), "house_yellow")
	B.cyl(local(Vector3(15.0, 8.7, -2.0)), 2.4, 4.6, 1.4, "house_roof", 4, Basis(Vector3.UP, PI / 4) * Basis.from_scale(Vector3(0.95, 1, 1.15)))
	for x in [12.9, 15.0, 17.1]:
		B.box(local(Vector3(x, 5.6, 2.03)), Vector3(0.75, 1.5, 0.06), "house_window")
	for x in [12.9, 17.1]:
		B.box(local(Vector3(x, 1.3, 2.03)), Vector3(1.1, 2.4, 0.06), "house_door")
	B.box(local(Vector3(15.0, 2.95, 2.05)), Vector3(2.1, 0.2, 0.1), "dark")
	return B


static func _quad_arrays(centers: Array, size: Vector2) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for c in centers:
		var p: Vector3 = c
		var a := p + Vector3(-size.x * 0.5, -size.y * 0.5, 0)
		var b := p + Vector3(size.x * 0.5, -size.y * 0.5, 0)
		var d := p + Vector3(size.x * 0.5, size.y * 0.5, 0)
		var e := p + Vector3(-size.x * 0.5, size.y * 0.5, 0)
		# facing +z (the square); clockwise seen from the front
		for v in [[a, Vector2(0, 1)], [e, Vector2(0, 0)], [d, Vector2(1, 0)], [a, Vector2(0, 1)], [d, Vector2(1, 0)], [b, Vector2(1, 1)]]:
			st.set_normal(Vector3.BACK)
			st.set_uv(v[1])
			st.add_vertex(v[0])
	return st.commit()


static func _exit_mat(panels: float, energy: float) -> ShaderMaterial:
	var sm := ShaderMaterial.new()
	sm.shader = preload("res://shaders/arles_exit.gdshader")
	sm.set_shader_parameter("col", Style.EXIT)
	sm.set_shader_parameter("dark", Style.EXIT_DARK)
	sm.set_shader_parameter("panels", panels)
	sm.set_shader_parameter("energy", energy)
	return sm


func setup(cell_world_pos: Vector3) -> void:
	position = Vector3(cell_world_pos.x, 0.0, cell_world_pos.z)
	var B := house_buf()
	house_parts = B.parts
	house = MeshInstance3D.new()
	house.name = "YellowHouse"
	house.mesh = B.commit()
	house.material_override = Scenery.obj_material()
	add_child(house)

	door_material = _exit_mat(1.0, 1.8)
	door = MeshInstance3D.new()
	door.name = "GreenDoor"
	door.mesh = _quad_arrays([local(DOOR)], Vector2(1.7, 2.8))
	door.material_override = door_material
	add_child(door)

	shutter_material = _exit_mat(0.0, 0.85)
	var sc: Array = []
	for x in [12.9, 15.0, 17.1]:
		for s in [-1.0, 1.0]:
			sc.append(local(Vector3(x + s * 0.62, 5.6, 2.06)))
	shutters = MeshInstance3D.new()
	shutters.name = "GreenShutters"
	shutters.mesh = _quad_arrays(sc, Vector2(0.42, 1.5))
	shutters.material_override = shutter_material
	add_child(shutters)

	# the green star over the house (halo shader, type 3), never fogged
	star_material = Scenery.halo_material()
	star = MultiMeshInstance3D.new()
	star.name = "GreenStar"
	star.multimesh = Scenery.halo_multimesh([[local(STAR), STAR_SIZE, 2.2, 6.0, 1.5, 3]])
	star.material_override = star_material
	star.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(star)

	light = OmniLight3D.new()
	light.name = "DoorLight"
	light.light_color = Style.EXIT
	light.light_energy = LIGHT_ENERGY
	light.omni_range = 8.0
	light.shadow_enabled = false
	light.position = local(Vector3(15.0, 1.6, 4.6))
	add_child(light)


func set_reduce_fx(on: bool) -> void:
	_reduce_fx = on
	# the house is painted with the brush like the city: calmer as well (code H2)
	if house != null and house.material_override is ShaderMaterial:
		house.material_override.set_shader_parameter("calm", 1.0 if on else 0.0)
		house.material_override.set_shader_parameter("moving", 0.0 if on else 1.0) # no sway either
	if on:
		_apply(0.0)


## Whether the house's brush is calm ("Effekte reduzieren").
func house_calm() -> bool:
	return house != null and house.material_override is ShaderMaterial and float(house.material_override.get_shader_parameter("calm")) == 1.0



func pulse_enabled() -> bool:
	return not _reduce_fx


func update(delta: float, _now: float) -> void:
	_t += delta
	if _reduce_fx:
		return
	_apply(sin(_t * TAU * PULSE_HZ))


## s in -1..1 (0 = rest).
func _apply(s: float) -> void:
	if door_material == null:
		return
	var p := 0.86 + 0.14 * s
	door_material.set_shader_parameter("pulse", p)
	shutter_material.set_shader_parameter("pulse", p)
	star_material.set_shader_parameter("pulse", 1.0 + 0.25 * s)
	light.light_energy = LIGHT_ENERGY * p
