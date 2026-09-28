extends Node3D
## Enemy — one leuchtendes Wesen. Grid-based BFS chase along the maze graph,
## the same state machine as the web prototype's enemy AI: house -> chase ->
## frightened -> eaten -> house.

const CELL := 2.0

var palette_color := Color(1, 0.23, 0.36)
var palette_glow := Color(1, 0.42, 0.51)
var base_speed := 2.0

var mode := "house" # house | chase | frightened | eaten
var r := 0
var c := 0
var from_r := 0
var from_c := 0
var target_r := 0
var target_c := 0
var t := 1.0
var release_at := 0.0
var eaten_until := 0.0

var body_mesh: MeshInstance3D
var body_material: StandardMaterial3D
var light: OmniLight3D

var _bob_seed := 0.0


func setup(color: Color, glow: Color, speed: float) -> void:
	palette_color = color
	palette_glow = glow
	base_speed = speed
	_bob_seed = randf() * 10.0

	var icosa := SphereMesh.new()
	icosa.radius = 0.36
	icosa.height = 0.72
	icosa.radial_segments = 8
	icosa.rings = 5

	body_material = StandardMaterial3D.new()
	body_material.albedo_color = color
	body_material.emission_enabled = true
	body_material.emission = color
	body_material.emission_energy_multiplier = 0.7
	body_material.metallic = 0.2
	body_material.roughness = 0.3

	body_mesh = MeshInstance3D.new()
	body_mesh.mesh = icosa
	body_mesh.material_override = body_material
	add_child(body_mesh)

	light = OmniLight3D.new()
	light.light_color = glow
	light.omni_range = 3.2
	light.light_energy = 0.8
	add_child(light)


func place_in_house(cell: Vector2i) -> void:
	r = cell.x
	c = cell.y
	from_r = r
	from_c = c
	target_r = r
	target_c = c
	t = 1.0
	mode = "house"


## Advances this enemy by `delta`. `maze` is a MazeGen.Maze, `player_cell`
## is Vector2i(row, col), `frightened_active` is whether a power pellet
## window is open, `now` is the game clock in seconds.
func update(delta: float, maze, player_cell: Vector2i, frightened_active: bool, now: float, world_width: float) -> void:
	if mode == "house":
		if now >= release_at:
			mode = "chase"
			from_r = r
			from_c = c
			target_r = maze.house.r0
			target_c = maze.door_col
			t = 0.0
		else:
			var bob := sin(now * 3.0 + _bob_seed) * 0.08
			position = Vector3(c * CELL, 0.5 + bob, r * CELL)
			rotate_y(delta * 1.5)
			return

	if mode == "eaten":
		body_material.albedo_color = Color(0.62, 0.7, 0.85)
		body_material.emission = Color(0.62, 0.7, 0.85)
	elif frightened_active and mode != "eaten":
		mode = "frightened"
		body_material.albedo_color = Color(0.13, 0.2, 0.93)
		body_material.emission = Color(0.33, 0.47, 1.0)
	elif mode == "frightened" and not frightened_active:
		mode = "chase"
		body_material.albedo_color = palette_color
		body_material.emission = palette_color

	var use_speed := base_speed
	if mode == "frightened":
		use_speed = base_speed * 0.55
	elif mode == "eaten":
		use_speed = base_speed * 2.2

	t += (delta * use_speed) / CELL
	if t >= 1.0:
		t = 1.0
		r = target_r
		c = target_c
		var target_cell: Vector2i
		if mode == "eaten":
			target_cell = Vector2i(int((maze.house.r0 + maze.house.r1) / 2.0), maze.door_col)
		else:
			target_cell = player_cell
		var next_cell := _pick_next_cell(maze, target_cell)
		from_r = r
		from_c = c
		target_r = next_cell.x
		target_c = next_cell.y
		t = 0.0

	var from_x := from_c * CELL
	var to_x := target_c * CELL
	if absf(to_x - from_x) > world_width * 0.5:
		to_x += -world_width if to_x > from_x else world_width
	var from_z := from_r * CELL
	var to_z := target_r * CELL
	var x := lerpf(from_x, to_x, t)
	var z := lerpf(from_z, to_z, t)
	if x < -CELL:
		x += world_width
	if x > world_width:
		x -= world_width

	var bob := sin(now * 4.0 + _bob_seed) * 0.06
	position = Vector3(x, 0.5 + bob, z)
	var dx := to_x - from_x
	var dz := to_z - from_z
	if absf(dx) + absf(dz) > 0.001:
		rotation.y = atan2(dx, dz)


func _pick_next_cell(maze, target_cell: Vector2i) -> Vector2i:
	var options: Array = MazeGen.neighbors_of(maze, target_r, target_c)
	var filtered := []
	for opt in options:
		if not (opt.x == from_r and opt.y == from_c):
			filtered.append(opt)
	var pool: Array = filtered if not filtered.is_empty() else options
	if pool.is_empty():
		return Vector2i(target_r, target_c)

	if mode == "frightened":
		return pool[randi() % pool.size()]

	var dist: Array = MazeGen.bfs(maze, target_cell.x, target_cell.y)
	var best: Vector2i = pool[0]
	var best_d := 999999
	for cell in pool:
		var d: int = dist[cell.x][cell.y]
		if d == -1:
			d = 9999
		if d < best_d:
			best_d = d
			best = cell
	return best


func send_to_house(cell: Vector2i, now: float, delay: float) -> void:
	r = cell.x
	c = cell.y
	from_r = r
	from_c = c
	target_r = r
	target_c = c
	t = 1.0
	mode = "house"
	release_at = now + delay
	body_material.albedo_color = palette_color
	body_material.emission = palette_color
