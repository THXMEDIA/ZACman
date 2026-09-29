extends Node3D
## MazeView — builds the 3D geometry (walls, floor, ceiling, pellets, power
## pellets, fruit) for one generated maze, and owns pickup consumption.
## Instanced fresh by Main.gd for every level.

const CELL := 2.0
const WALL_H := 1.9
const WordMeshScript := preload("res://scripts/word_mesh.gd")
const ManhattanMazeScript := preload("res://scripts/manhattan_maze.gd")

## Neo-Noir cyberpunk palette for Manhattan's ordinary "BUILDING" blocks —
## cycled per-cell so the skyline reads as varied neon rather than one flat
## tint. Named landmarks (see manhattan_maze.gd's LANDMARKS) get their own,
## brighter accent colors instead, cycled from MANHATTAN_LANDMARK_ACCENTS.
const MANHATTAN_NEON_PALETTE := [
	Color(1.0, 0.05, 0.75), # magenta
	Color(0.0, 0.95, 1.0), # cyan
	Color(0.6, 0.05, 1.0), # violet
	Color(1.0, 0.8, 0.0), # neon amber
	Color(0.05, 1.0, 0.45), # neon green
]
const MANHATTAN_LANDMARK_ACCENTS := [
	Color(1.0, 0.85, 0.25), # neon gold
	Color(1.0, 0.05, 0.55), # hot pink
	Color(0.15, 0.85, 1.0), # electric blue
]

var maze # MazeGen.Maze
var theme := "normal" # "normal" | "manhattan"
var pellet_cells: Array = [] # Array[Vector2i]
var pellet_alive: Array = [] # Array[bool], parallel to pellet_cells
var pellet_meshes: Array = [] # Array[MeshInstance3D], parallel to pellet_cells
var power_cells: Array = [] # Array[Vector2i]
var power_nodes: Array = [] # Array[MeshInstance3D]
var power_alive: Array = [] # Array[bool]

var fruit_node: MeshInstance3D = null
var fruit_alive := false
var fruit_expire_at := 0.0

## The "Word Mode" power-up (normal levels only — see spawn_word_powerup
## note in _build_pellets). Manhattan never has one: it's set permanently
## into word-mode instead, and has no power-ups at all.
var word_powerup_cell := Vector2i(-1, -1)
var word_powerup_node: MeshInstance3D = null
var word_powerup_alive := false

var walls_body: StaticBody3D
var normal_wall_mmi: MultiMeshInstance3D
var word_wall_root: Node3D
var word_mode_active := false
var landmark_lights: Array = [] # Array[OmniLight3D], Manhattan only — pulsed in _process
var _t := 0.0

var wall_material: StandardMaterial3D
var pellet_material: StandardMaterial3D
var power_material: StandardMaterial3D
var fruit_material: StandardMaterial3D


## `reserved_cells` (Manhattan only) are cells a stationary obstacle
## (Pedestrian) will occupy — excluded from pellet placement up front so a
## pedestrian standing on a pellet can never permanently block it (taxis
## are moving obstacles and don't need this: they pass through, they don't
## park on a pellet forever).
func build(new_maze, start_cell: Vector2i, maze_theme: String = "normal", reserved_cells: Array = []) -> void:
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
	word_powerup_cell = Vector2i(-1, -1)
	word_powerup_node = null
	word_powerup_alive = false

	maze = new_maze
	theme = maze_theme
	_make_materials()
	_build_walls()
	_build_floor_ceiling()
	_build_pellets(start_cell, reserved_cells)
	# Manhattan is permanently in the word-built-world look; the normal
	# levels start out looking normal and only switch when the Word Mode
	# power-up is eaten (see Main._on_word_powerup / set_word_mode).
	set_word_mode(theme == "manhattan")


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

	normal_wall_mmi = MultiMeshInstance3D.new()
	normal_wall_mmi.multimesh = mm
	add_child(normal_wall_mmi)

	# The word-built-world skin: every wall cell doubles as a 3D letterform.
	# Built alongside the normal boxy walls (not on demand) so toggling Word
	# Mode mid-level is instant; hidden until set_word_mode() turns it on.
	# The normal levels use a flat Matrix green ("WALL", matching the ASCII
	# look they're switching out of); Manhattan is a Neo-Noir cyberpunk
	# skyline — every ordinary block cycles through a neon palette as
	# "BUILDING", and any block ManhattanMazeScript.LANDMARKS actually names
	# (see manhattan_maze.gd) gets that real name, a brighter accent color,
	# and its own pulsing light (animated in _process, see landmark_lights).
	word_wall_root = Node3D.new()
	add_child(word_wall_root)
	landmark_lights.clear()
	if theme == "manhattan":
		for cell in wall_cells:
			var landmark_name: String = ManhattanMazeScript.landmark_at(cell.x, cell.y)
			if landmark_name != "":
				var accent: Color = MANHATTAN_LANDMARK_ACCENTS[landmark_lights.size() % MANHATTAN_LANDMARK_ACCENTS.size()]
				var wm := WordMeshScript.build(landmark_name, accent, {"font_size": 15, "depth": WALL_H * 0.55, "emission_energy": 2.4})
				wm.position = Vector3(cell.y * CELL, WALL_H * 0.55, cell.x * CELL)
				wm.rotation.y = 0.0 if (cell.x + cell.y) % 2 == 0 else PI / 2.0
				word_wall_root.add_child(wm)
				var light := OmniLight3D.new()
				light.light_color = accent
				light.omni_range = 3.4
				light.light_energy = 1.2
				wm.add_child(light)
				landmark_lights.append(light)
			else:
				var neon: Color = MANHATTAN_NEON_PALETTE[absi(cell.x * 31 + cell.y) % MANHATTAN_NEON_PALETTE.size()]
				var bw := WordMeshScript.build("BUILDING", neon, {"font_size": 22, "depth": WALL_H * 0.6, "emission_energy": 1.1})
				bw.position = Vector3(cell.y * CELL, WALL_H * 0.5, cell.x * CELL)
				bw.rotation.y = 0.0 if (cell.x + cell.y) % 2 == 0 else PI / 2.0
				word_wall_root.add_child(bw)
	else:
		for cell in wall_cells:
			var wm2 := WordMeshScript.build("WALL", Color(0.25, 1.0, 0.35), {"font_size": 30, "depth": WALL_H * 0.6, "emission_energy": 1.1})
			wm2.position = Vector3(cell.y * CELL, WALL_H * 0.5, cell.x * CELL)
			# Alternate facing so corridors running either axis catch a
			# readable face at least some of the time — the reference look
			# is scattered lettering, not perfectly UV-mapped signage.
			wm2.rotation.y = 0.0 if (cell.x + cell.y) % 2 == 0 else PI / 2.0
			word_wall_root.add_child(wm2)

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
	var ceil_mat := StandardMaterial3D.new()
	if theme == "manhattan":
		# Neo-noir cyberpunk: near-black wet-asphalt floor with a faint
		# magenta sheen, and a deep violet "night sky" ceiling that catches
		# the neon glow from the word-built buildings.
		floor_mat.albedo_color = Color(0.015, 0.01, 0.03)
		floor_mat.roughness = 0.25
		floor_mat.metallic = 0.35
		floor_mat.emission_enabled = true
		floor_mat.emission = Color(0.35, 0.02, 0.3)
		floor_mat.emission_energy_multiplier = 0.12
		ceil_mat.albedo_color = Color(0.03, 0.01, 0.07)
		ceil_mat.emission_enabled = true
		ceil_mat.emission = Color(0.05, 0.02, 0.25)
		ceil_mat.emission_energy_multiplier = 0.1
	else:
		floor_mat.albedo_color = Color(0.024, 0.039, 0.094)
		floor_mat.roughness = 0.9
		ceil_mat.albedo_color = Color(0.016, 0.024, 0.067)

	var floor_mesh := MeshInstance3D.new()
	floor_mesh.mesh = plane
	floor_mesh.material_override = floor_mat
	floor_mesh.position = Vector3((maze.cols - 1) * CELL * 0.5, 0.0, (maze.rows - 1) * CELL * 0.5)
	add_child(floor_mesh)

	var ceil_mesh := MeshInstance3D.new()
	ceil_mesh.mesh = plane
	ceil_mesh.material_override = ceil_mat
	ceil_mesh.position = Vector3((maze.cols - 1) * CELL * 0.5, WALL_H, (maze.rows - 1) * CELL * 0.5)
	ceil_mesh.rotation.x = PI
	add_child(ceil_mesh)


## Swaps the visible wall skin: word-built ("WALL" letterforms) vs the
## normal boxy walls. Collision (walls_body) is untouched either way — this
## is purely cosmetic; Main separately toggles the player's noclip.
func set_word_mode(active: bool) -> void:
	word_mode_active = active
	word_wall_root.visible = active
	normal_wall_mmi.visible = not active


func _pick_farthest_cell(cells: Array, from: Vector2i) -> Vector2i:
	var best: Vector2i = cells[0]
	var best_d := -1.0
	for cell in cells:
		var d: float = (cell.x - from.x) * (cell.x - from.x) + (cell.y - from.y) * (cell.y - from.y)
		if d > best_d:
			best_d = d
			best = cell
	return best


func _build_word_powerup_mesh() -> void:
	var mesh := WordMeshScript.build("WORD", Color(0.25, 1.0, 0.35), {"font_size": 26, "depth": 0.16, "emission_energy": 1.7})
	mesh.scale = Vector3.ONE * 0.5
	mesh.position = Vector3(word_powerup_cell.y * CELL, 0.55, word_powerup_cell.x * CELL)
	var light := OmniLight3D.new()
	light.light_color = Color(0.25, 1.0, 0.35)
	light.omni_range = 2.6
	light.light_energy = 0.85
	mesh.add_child(light)
	add_child(mesh)
	word_powerup_node = mesh
	word_powerup_alive = true


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


func _build_pellets(start_cell: Vector2i, reserved_cells: Array = []) -> void:
	var all_cells: Array = MazeGen.cells_in_room(maze, false)
	var reserved_set := {}
	for cell in reserved_cells:
		reserved_set[cell] = true
	var candidates := []
	for cell in all_cells:
		if cell != start_cell and not reserved_set.has(cell):
			candidates.append(cell)

	# Manhattan has no power-ups at all (no power pellets, no Word Mode
	# pickup below) — it has no ghosts to use them against and is meant to
	# be a calm explore, not a chase level. Every open cell there is just a
	# plain collectible pellet.
	power_cells = [] if theme == "manhattan" else _pick_power_cells(candidates)
	var power_set := {}
	for cell in power_cells:
		power_set[cell] = true
	pellet_cells = []
	for cell in candidates:
		if not power_set.has(cell):
			pellet_cells.append(cell)

	# Word Mode power-up: one per normal level, taken out of the regular
	# pellet grid (not an extra pellet on top of it) so there's exactly one
	# clearly-special pickup to find. Manhattan has none (see build()).
	if theme != "manhattan" and pellet_cells.size() > 0:
		word_powerup_cell = _pick_farthest_cell(pellet_cells, start_cell)
		pellet_cells.erase(word_powerup_cell)

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

	if word_powerup_cell.x >= 0:
		_build_word_powerup_mesh()


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
## what was eaten this call: {pellet, power, fruit, word_powerup: bool}.
func consume_at(pos: Vector3, now: float) -> Dictionary:
	var result := {"pellet": false, "power": false, "fruit": false, "word_powerup": false}
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

	if word_powerup_alive and word_powerup_node != null:
		var d := Vector2(word_powerup_node.position.x - pos.x, word_powerup_node.position.z - pos.z).length()
		if d < 0.5:
			word_powerup_alive = false
			word_powerup_node.visible = false
			result.word_powerup = true

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
	if word_powerup_alive and word_powerup_node != null:
		word_powerup_node.rotate_y(delta * 2.0)
		var ws := 0.5 + sin(_t * 5.0) * 0.06
		word_powerup_node.scale = Vector3.ONE * ws
	for i in landmark_lights.size():
		var light: OmniLight3D = landmark_lights[i]
		light.light_energy = 1.0 + sin(_t * 3.0 + i * 0.7) * 0.55
