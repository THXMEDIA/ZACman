extends Node3D
## MazeView — builds the 3D geometry (walls, floor, ceiling, pellets, power
## pellets, fruit) for one generated maze, and owns pickup consumption.
## Instanced fresh by Main.gd for every level.

const CELL := 2.0
const WALL_H := 3.8 # doubled from the original 1.9 per user request — taller, more imposing corridors
const WordMeshScript := preload("res://scripts/word_mesh.gd")
const CityThemesScript := preload("res://scripts/city_themes.gd")
const CloudMeshScript := preload("res://scripts/cloud_mesh.gd")

var maze # MazeGen.Maze
var theme := "normal" # theme id — see city_themes.gd's registry ("normal" | "manhattan" | ...)
var city_theme # CityTheme — the resolved visual/gameplay bundle for `theme` (see city_theme.gd)
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

var wall_material: Material # StandardMaterial3D normally, or a matrix_rain ShaderMaterial (see CityTheme.wall_matrix_rain)
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
	city_theme = CityThemesScript.get_theme(theme)
	_make_materials()
	_build_walls()
	_build_floor_ceiling()
	_build_sky_clouds()
	_build_tunnel_vistas()
	_build_pellets(start_cell, reserved_cells)
	# A permanently-word-built theme (Manhattan) starts in the word-built-
	# world look; other themes start out looking normal and only switch when
	# the Word Mode power-up is eaten (see Main._on_word_powerup / set_word_mode).
	set_word_mode(city_theme.permanently_word_built)


func _make_materials() -> void:
	if city_theme.wall_matrix_rain:
		# Scrolling green ASCII glyphs baked into the wall surface itself —
		# see matrix_rain.gdshader. Always fully "ASCII", never a flat real
		# color, at any distance (unlike the old screen-space post effect).
		var shader_mat := ShaderMaterial.new()
		shader_mat.shader = load("res://shaders/matrix_rain.gdshader")
		wall_material = shader_mat
	else:
		var sm := StandardMaterial3D.new()
		sm.albedo_color = Color(0.047, 0.086, 0.22)
		sm.emission_enabled = true
		sm.emission = Color(0.118, 0.373, 1.0)
		sm.emission_energy_multiplier = 0.55
		sm.roughness = 0.55
		sm.metallic = 0.15
		wall_material = sm

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
	# Entirely data-driven off city_theme (see city_theme.gd/city_themes.gd):
	# an ordinary block cycles through city_theme.wall_palette as
	# city_theme.wall_word, and any block city_theme.landmark_provider_script
	# actually names (e.g. manhattan_maze.gd's real Midtown buildings) gets
	# that name, a brighter accent color, and its own pulsing light (animated
	# in _process, see landmark_lights) instead.
	word_wall_root = Node3D.new()
	add_child(word_wall_root)
	landmark_lights.clear()
	for cell in wall_cells:
		var landmark_name := ""
		if city_theme.landmark_provider_script != null:
			landmark_name = city_theme.landmark_provider_script.landmark_at(cell.x, cell.y)
		var rot_y := 0.0
		if city_theme.wall_alternate_rotation and (cell.x + cell.y) % 2 != 0:
			rot_y = PI / 2.0
		if landmark_name != "":
			var accent: Color = city_theme.landmark_accents[landmark_lights.size() % city_theme.landmark_accents.size()]
			var wm := WordMeshScript.build(landmark_name, accent, {"font_size": city_theme.landmark_font_size, "depth": WALL_H * city_theme.landmark_depth_scale, "emission_energy": city_theme.landmark_emission_energy})
			wm.position = Vector3(cell.y * CELL, WALL_H * city_theme.landmark_depth_scale, cell.x * CELL)
			wm.rotation.y = rot_y
			word_wall_root.add_child(wm)
			var light := OmniLight3D.new()
			light.light_color = accent
			light.omni_range = 3.4
			light.light_energy = 1.2
			wm.add_child(light)
			landmark_lights.append(light)
		else:
			var block_color: Color = city_theme.wall_palette[absi(cell.x * 31 + cell.y) % city_theme.wall_palette.size()]
			var bw := WordMeshScript.build(city_theme.wall_word, block_color, {"font_size": city_theme.wall_font_size, "depth": WALL_H * city_theme.wall_depth_scale, "emission_energy": city_theme.wall_emission_energy})
			bw.position = Vector3(cell.y * CELL, WALL_H * 0.5, cell.x * CELL)
			bw.rotation.y = rot_y
			word_wall_root.add_child(bw)

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
	floor_mat.albedo_color = city_theme.floor_color
	floor_mat.roughness = city_theme.floor_roughness
	floor_mat.metallic = city_theme.floor_metallic
	if city_theme.floor_emission_enabled:
		floor_mat.emission_enabled = true
		floor_mat.emission = city_theme.floor_emission_color
		floor_mat.emission_energy_multiplier = city_theme.floor_emission_energy

	var ceil_mat := StandardMaterial3D.new()
	ceil_mat.albedo_color = city_theme.ceil_color
	if city_theme.ceil_emission_enabled:
		ceil_mat.emission_enabled = true
		ceil_mat.emission = city_theme.ceil_emission_color
		ceil_mat.emission_energy_multiplier = city_theme.ceil_emission_energy

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


## Mario/Minecraft-style voxel sky: scatters a handful of blocky white
## pixel-cloud clusters (cloud_mesh.gd) just below the ceiling, over open
## (non-wall) cells only — floating one directly above a wall column would
## sit half-buried in the top of that wall block. Purely decorative, no
## collision. Only runs for themes with CityTheme.ceil_sky_clouds set.
func _build_sky_clouds() -> void:
	if not city_theme.ceil_sky_clouds:
		return
	var candidates: Array = MazeGen.cells_in_room(maze, false)
	if candidates.is_empty():
		return
	candidates.shuffle()
	var cloud_count: int = clampi(candidates.size() / 22, 4, 14)
	for i in mini(cloud_count, candidates.size()):
		var cell: Vector2i = candidates[i]
		# 1.5x the original 0.10-0.16 range, per the user's "clouds 1.5x
		# taller" request.
		var voxel_size: float = (0.1 + randf() * 0.06) * 1.5
		var cloud := CloudMeshScript.build({"voxel_size": voxel_size})
		var jitter_x := (randf() - 0.5) * CELL * 0.6
		var jitter_z := (randf() - 0.5) * CELL * 0.6
		# Keep the cloud's top edge just under the ceiling regardless of its
		# (now bigger) size: CloudMesh is CloudMeshScript.ROWS tall, centered
		# on its own origin, so half that height plus a small gap sits above
		# the origin we place it at.
		var half_h: float = CloudMeshScript.ROWS * voxel_size * 0.5
		cloud.position = Vector3(cell.y * CELL + jitter_x, WALL_H - 0.15 - half_h, cell.x * CELL + jitter_z)
		cloud.rotation.y = randf() * TAU
		add_child(cloud)


## Caps both ends of the maze's side tunnel (maze.tunnel_row, where
## MazeGen leaves the two edge columns open for the Pac-Man-style
## wraparound — see player_controller.gd's wrap_tunnel) with a flat
## Super-Mario-style backdrop panel (mario_vista.gdshader) instead of
## letting the tunnel mouth open straight onto the plain background clear
## color. That background is now a bright "sky" blue for this theme (see
## city_themes.gd), and it was bleeding through those two open tunnel
## ends looking like a flat blue void — this caps it with an actual
## (deliberately non-blue) vista instead. Only runs for themes with
## CityTheme.ceil_sky_clouds set, same as the clouds above; other themes'
## backgrounds (e.g. Manhattan's neo-noir violet) don't have this problem.
func _build_tunnel_vistas() -> void:
	if not city_theme.ceil_sky_clouds:
		return
	var shader := load("res://shaders/mario_vista.gdshader")
	var world_width: float = maze.cols * CELL
	var z: float = maze.tunnel_row * CELL
	# Left end: sits at the wrap threshold (see wrap_tunnel's -CELL*0.5),
	# facing +X so its front is visible to a player approaching from inside.
	_add_tunnel_vista_panel(Vector3(-CELL * 0.5, WALL_H * 0.5, z), PI / 2.0, shader)
	# Right end: mirrored, facing -X.
	_add_tunnel_vista_panel(Vector3(world_width - CELL * 0.5, WALL_H * 0.5, z), -PI / 2.0, shader)


func _add_tunnel_vista_panel(pos: Vector3, rot_y: float, shader: Shader) -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(CELL, WALL_H)
	var mat := ShaderMaterial.new()
	mat.shader = shader
	quad.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = quad
	mi.position = pos
	mi.rotation.y = rot_y
	add_child(mi)


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

	# A "calm explorer" theme (city_theme.has_power_ups == false, e.g.
	# Manhattan) has no power-ups at all (no power pellets, no Word Mode
	# pickup below) — it has no ghosts to use them against. Every open cell
	# there is just a plain collectible pellet.
	power_cells = _pick_power_cells(candidates) if city_theme.has_power_ups else []
	var power_set := {}
	for cell in power_cells:
		power_set[cell] = true
	pellet_cells = []
	for cell in candidates:
		if not power_set.has(cell):
			pellet_cells.append(cell)

	# Word Mode power-up: one per level that has power-ups at all, taken out
	# of the regular pellet grid (not an extra pellet on top of it) so
	# there's exactly one clearly-special pickup to find. A "calm explorer"
	# theme like Manhattan has none (see build()/has_power_ups).
	if city_theme.has_power_ups and pellet_cells.size() > 0:
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
