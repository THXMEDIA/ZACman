extends Node3D
## MazeView — builds the 3D geometry (walls, floor, ceiling, pellets, power
## pellets, fruit) for one generated maze, and owns pickup consumption.
## Instanced fresh by Main.gd for every level.

const CELL := 2.0
const WALL_H := 1.9

var maze # MazeGen.Maze
var pellet_cells: Array = [] # Array[Vector2i]
var pellet_alive: Array = [] # Array[bool], parallel to pellet_cells
var pellet_meshes: Array = [] # Array[MeshInstance3D], parallel to pellet_cells
var power_cells: Array = [] # Array[Vector2i]
var power_nodes: Array = [] # Array[MeshInstance3D]
var power_alive: Array = [] # Array[bool]

var fruit_node: MeshInstance3D = null
var fruit_alive := false
var fruit_expire_at := 0.0

var walls_body: StaticBody3D
var _t := 0.0

var wall_material: StandardMaterial3D
var pellet_material: StandardMaterial3D
var power_material: StandardMaterial3D
var fruit_material: StandardMaterial3D


func build(new_maze, start_cell: Vector2i) -> void:
	for child in get_children():
		child.queue_free()
	pellet_cells.clear()
	pellet_alive.clear()
	pellet_meshes.clear()
	power_cells.clear()
	power_nodes.clear()
	power_alive.clear()
	fruit_node = null
	fruit_alive = false

	maze = new_maze
	_make_materials()
	_build_walls()
	_build_floor_ceiling()
	_build_pellets(start_cell)


func _make_materials() -> void:
	wall_material = StandardMaterial3D.new()
	wall_material.albedo_color = Color(0.047, 0.086, 0.22)
	wall_material.emission_enabled = true
	wall_material.emission = Color(0.118, 0.373, 1.0)
	wall_material.emission_energy_multiplier = 0.55
	wall_material.roughness = 0.55
	wall_material.metallic = 0.15

	pellet_material = StandardMaterial3D.new()
	pellet_material.albedo_color = Color(1.0, 0.82, 0.4)
	pellet_material.emission_enabled = true
	pellet_material.emission = Color(1.0, 0.69, 0.18)
	pellet_material.emission_energy_multiplier = 1.3

	power_material = StandardMaterial3D.new()
	power_material.albedo_color = Color(1.0, 0.365, 0.635)
	power_material.emission_enabled = true
	power_material.emission = Color(1.0, 0.184, 0.525)
	power_material.emission_energy_multiplier = 1.6

	fruit_material = StandardMaterial3D.new()
	fruit_material.albedo_color = Color(0.486, 1.0, 0.42)
	fruit_material.emission_enabled = true
	fruit_material.emission = Color(0.247, 0.75, 0.18)
	fruit_material.emission_energy_multiplier = 1.2


func _build_walls() -> void:
	var wall_cells := []
	for r in maze.rows:
		for c in maze.cols:
			if maze.grid[r][c] == 1:
				wall_cells.append(Vector2i(r, c))

	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3(CELL, WALL_H, CELL)
	box_mesh.material = wall_material

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = box_mesh
	mm.instance_count = wall_cells.size()
	for i in wall_cells.size():
		var cell: Vector2i = wall_cells[i]
		var xf := Transform3D(Basis(), Vector3(cell.y * CELL, WALL_H * 0.5, cell.x * CELL))
		mm.set_instance_transform(i, xf)

	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	add_child(mmi)

	walls_body = StaticBody3D.new()
	walls_body.collision_layer = 2
	walls_body.collision_mask = 0
	add_child(walls_body)
	for cell in wall_cells:
		var shape := BoxShape3D.new()
		shape.size = Vector3(CELL, WALL_H, CELL)
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.position = Vector3(cell.y * CELL, WALL_H * 0.5, cell.x * CELL)
		walls_body.add_child(cs)


func _build_floor_ceiling() -> void:
	var floor_w: float = maze.cols * CELL
	var floor_d: float = maze.rows * CELL
	var plane := PlaneMesh.new()
	plane.size = Vector2(floor_w, floor_d)

	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.024, 0.039, 0.094)
	floor_mat.roughness = 0.9

	var floor_mesh := MeshInstance3D.new()
	floor_mesh.mesh = plane
	floor_mesh.material_override = floor_mat
	floor_mesh.position = Vector3((maze.cols - 1) * CELL * 0.5, 0.0, (maze.rows - 1) * CELL * 0.5)
	add_child(floor_mesh)

	var ceil_mat := StandardMaterial3D.new()
	ceil_mat.albedo_color = Color(0.016, 0.024, 0.067)
	var ceil_mesh := MeshInstance3D.new()
	ceil_mesh.mesh = plane
	ceil_mesh.material_override = ceil_mat
	ceil_mesh.position = Vector3((maze.cols - 1) * CELL * 0.5, WALL_H, (maze.rows - 1) * CELL * 0.5)
	ceil_mesh.rotation.x = PI
	add_child(ceil_mesh)


func _pick_power_cells(candidates: Array) -> Array:
	var corners := [Vector2i(0, 0), Vector2i(0, maze.cols - 1), Vector2i(maze.rows - 1, 0), Vector2i(maze.rows - 1, maze.cols - 1)]
	var picked := []
	for corner in corners:
		var best = null
		var best_d := INF
		for cell in candidates:
			var d: float = (cell.x - corner.x) * (cell.x - corner.x) + (cell.y - corner.y) * (cell.y - corner.y)
			if d < best_d:
				best_d = d
				best = cell
		if best != null:
			picked.append(best)
	return picked


func _build_pellets(start_cell: Vector2i) -> void:
	var all_cells: Array = MazeGen.cells_in_room(maze, false)
	var candidates := []
	for cell in all_cells:
		if cell != start_cell:
			candidates.append(cell)

	power_cells = _pick_power_cells(candidates)
	var power_set := {}
	for cell in power_cells:
		power_set[cell] = true
	pellet_cells = []
	for cell in candidates:
		if not power_set.has(cell):
			pellet_cells.append(cell)

	var sphere := SphereMesh.new()
	sphere.radius = 0.11
	sphere.height = 0.22
	sphere.material = pellet_material
	for cell in pellet_cells:
		var mesh := MeshInstance3D.new()
		mesh.mesh = sphere
		mesh.position = Vector3(cell.y * CELL, 0.32, cell.x * CELL)
		add_child(mesh)
		pellet_meshes.append(mesh)
		pellet_alive.append(true)

	var power_sphere := SphereMesh.new()
	power_sphere.radius = 0.26
	power_sphere.height = 0.52
	power_sphere.material = power_material
	for cell in power_cells:
		var mesh := MeshInstance3D.new()
		mesh.mesh = power_sphere
		mesh.position = Vector3(cell.y * CELL, 0.4, cell.x * CELL)
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.365, 0.635)
		light.omni_range = 2.4
		light.light_energy = 0.7
		mesh.add_child(light)
		add_child(mesh)
		power_nodes.append(mesh)
		power_alive.append(true)


func total_pickups() -> int:
	return pellet_cells.size() + power_cells.size()


func remaining_pickups() -> int:
	var n := 0
	for a in pellet_alive:
		if a:
			n += 1
	for a in power_alive:
		if a:
			n += 1
	if fruit_alive:
		pass # fruit is a bonus, not counted toward level completion
	return n


func spawn_fruit(now: float) -> void:
	var door_r: int = maze.house.r0 - 1
	var door_c: int = maze.door_col
	var prism := PrismMesh.new()
	prism.size = Vector3(0.42, 0.42, 0.42)
	var mesh := MeshInstance3D.new()
	mesh.mesh = prism
	mesh.material_override = fruit_material
	mesh.position = Vector3(door_c * CELL, 0.45, door_r * CELL)
	add_child(mesh)
	fruit_node = mesh
	fruit_alive = true
	fruit_expire_at = now + 12.0


## Consumes any pickup within `radius` of `pos`. Returns a Dictionary describing
## what was eaten this call: {pellet: bool, power: bool, fruit: bool}.
func consume_at(pos: Vector3, now: float) -> Dictionary:
	var result := {"pellet": false, "power": false, "fruit": false}
	for i in pellet_cells.size():
		if not pellet_alive[i]:
			continue
		var cell: Vector2i = pellet_cells[i]
		var d := Vector2(cell.y * CELL - pos.x, cell.x * CELL - pos.z).length()
		if d < 0.42:
			pellet_alive[i] = false
			pellet_meshes[i].visible = false
			result.pellet = true

	for i in power_cells.size():
		if not power_alive[i]:
			continue
		var node: MeshInstance3D = power_nodes[i]
		var d := Vector2(node.position.x - pos.x, node.position.z - pos.z).length()
		if d < 0.5:
			power_alive[i] = false
			node.visible = false
			result.power = true

	if fruit_alive and fruit_node != null:
		var d := Vector2(fruit_node.position.x - pos.x, fruit_node.position.z - pos.z).length()
		if d < 0.5:
			fruit_alive = false
			fruit_node.visible = false
			result.fruit = true
		elif now > fruit_expire_at:
			fruit_alive = false
			fruit_node.visible = false

	return result


func _process(delta: float) -> void:
	_t += delta
	for i in power_nodes.size():
		if power_alive[i]:
			var s := 1.0 + sin(_t * 6.0 + i) * 0.14
			power_nodes[i].scale = Vector3.ONE * s
	if fruit_alive and fruit_node != null:
		fruit_node.rotate_y(delta * 1.4)
