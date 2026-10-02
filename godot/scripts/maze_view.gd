extends Node3D
## MazeView — builds the 3D geometry (walls, floor, ceiling, pellets, power
## pellets, fruit) for one generated maze, and owns pickup consumption.
## Instanced fresh by Main.gd for every level.

const CELL := 2.0
const WALL_H := 4.4 # was 3.8 (doubled from the original 1.9 earlier); raised again per user request — taller, more imposing corridors. Only the "normal"/Matrix theme actually uses this as its wall height: Manhattan sets its own real-world building heights (CityTheme.wall_height_min/max) and ignores WALL_H except as a last-resort fallback (see _wall_height_for_cell).
## The voxel-cloud sky sits well above the wall tops rather than hugging
## them: both the sky ceiling and the clouds under it float at
## WALL_H * CLOUD_HEIGHT_MULT (see _build_floor_ceiling/_build_sky_clouds),
## and CLOUD_MIN_WALL_CLEARANCE is an explicit floor under that so a cloud
## can never end up closer to the wall tops than that, regardless of its
## own (randomized) size.
const CLOUD_HEIGHT_MULT := 1.5
const CLOUD_MIN_WALL_CLEARANCE := 0.6
const WordMeshScript := preload("res://scripts/word_mesh.gd")
const CityThemesScript := preload("res://scripts/city_themes.gd")
const CloudMeshScript := preload("res://scripts/cloud_mesh.gd")
const PixelRabbitMeshScript := preload("res://scripts/pixel_rabbit_mesh.gd")
const PsychedelicHeadMeshScript := preload("res://scripts/psychedelic_head_mesh.gd")

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
##
## More than one now spawns per level ("mehr spawn der Kondition Items") —
## parallel arrays, same pattern as power_cells/power_nodes/power_alive
## above, rather than a single cell/node/alive triple.
const WORD_POWERUP_COUNT := 2
var word_powerup_cells: Array = [] # Array[Vector2i]
var word_powerup_nodes: Array = [] # Array[Node3D] — each a MultiMeshInstance3D (the pixel-rabbit — see pixel_rabbit_mesh.gd), typed as the common Node3D base
var word_powerup_alive: Array = [] # Array[bool]

## The Fear & Loathing pickup (normal levels only, same rules as the WORD
## pickup above): eating it temporarily applies the Fear & Loathing
## condition's control-scrambling (see Main._activate_fear_powerup), turns
## the matrix_rain wall shader psychedelic (see set_psychedelic), and
## randomly flips the player's wall collision on and off for a few seconds.
const FEAR_POWERUP_COUNT := 2
var fear_powerup_cells: Array = [] # Array[Vector2i]
var fear_powerup_nodes: Array = [] # Array[Node3D]
var fear_powerup_alive: Array = [] # Array[bool]

var walls_body: StaticBody3D
var normal_wall_mmi: MultiMeshInstance3D
var word_wall_root: Node3D
var word_mode_active := false
var landmark_lights: Array = [] # Array[OmniLight3D], Manhattan only — pulsed in _process
var sky_cloud_nodes: Array = [] # Array[MultiMeshInstance3D], sky-cloud themes only — see _build_sky_clouds; tracked mainly so tests can check their height
var _t := 0.0

var wall_material: Material # StandardMaterial3D normally, or a matrix_rain ShaderMaterial (see CityTheme.wall_matrix_rain)
var pellet_material: StandardMaterial3D
var power_material: StandardMaterial3D
var fruit_material: StandardMaterial3D


## `reserved_cells` (Manhattan only) are cells a stationary obstacle
## (Pedestrian) will occupy — excluded from pellet placement up front so a
## pedestrian standing on a pellet can never permanently block it (taxis
## are moving obstacles and don't need this: they pass through, they don't
## park on a pellet forever). `metro_cells` (Manhattan only) are the metro-
## station cells pellets should route toward — see
## CityTheme.pellets_follow_metro_trails / _metro_trail_cells.
func build(new_maze, start_cell: Vector2i, maze_theme: String = "normal", reserved_cells: Array = [], metro_cells: Array = []) -> void:
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
	word_powerup_cells.clear()
	word_powerup_nodes.clear()
	word_powerup_alive.clear()
	fear_powerup_cells.clear()
	fear_powerup_nodes.clear()
	fear_powerup_alive.clear()
	sky_cloud_nodes.clear()

	maze = new_maze
	theme = maze_theme
	city_theme = CityThemesScript.get_theme(theme)
	_make_materials()
	_build_walls()
	_build_floor_ceiling()
	_build_sky_clouds()
	_build_tunnel_vistas()
	_build_pellets(start_cell, reserved_cells, metro_cells)
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


## Deterministic per-cell "is this block a SKYSCRAPER (vs. a regular
## BUILDING)" pick — a hash of the cell coordinates, not randf(), so the
## same maze always looks the same and the boxy multimesh, the word-mesh
## skin and the collision shape all agree on the same cell without sharing
## state. See CityTheme.wall_word_tall/skyscraper_chance_pct.
func _is_skyscraper_cell(cell: Vector2i) -> bool:
	if city_theme.wall_word_tall == "" or city_theme.skyscraper_chance_pct <= 0:
		return false
	return absi(cell.x * 73 + cell.y * 131) % 100 < city_theme.skyscraper_chance_pct


## The generic (non-landmark) height for a block: WALL_H unless the theme
## opts into height variation (CityTheme.wall_height_min > 0), in which case
## it's a skyscraper- or building-range height, again picked deterministically
## from the cell so every consumer (walls, word skin, collision) agrees.
func _generic_wall_height(cell: Vector2i) -> float:
	if _is_skyscraper_cell(cell):
		var span: float = city_theme.wall_height_tall_max - city_theme.wall_height_tall_min
		var frac: float = float(absi(cell.x * 17 + cell.y * 29) % 1000) / 1000.0
		return city_theme.wall_height_tall_min + span * frac
	elif city_theme.wall_height_min > 0.0:
		var span2: float = city_theme.wall_height_max - city_theme.wall_height_min
		var frac2: float = float(absi(cell.x * 11 + cell.y * 41) % 1000) / 1000.0
		return city_theme.wall_height_min + span2 * frac2
	return WALL_H


## The actual height to build this block at — a real landmark's real-world
## height (CityTheme.landmark_heights, see city_themes.gd's manhattan())
## when landmark_name names one, otherwise _generic_wall_height's
## BUILDING/SKYSCRAPER pick. Falls back to WALL_H whenever the theme hasn't
## opted into height variation at all, exactly the old uniform-height look.
func _wall_height_for_cell(cell: Vector2i, landmark_name: String) -> float:
	if landmark_name != "":
		return city_theme.landmark_heights.get(landmark_name, city_theme.landmark_default_height if city_theme.landmark_default_height > 0.0 else WALL_H)
	return _generic_wall_height(cell)


## Builds one block's word skin at the given height: a vertical letter
## totem (word_mesh.gd's build_vertical_stack) when
## CityTheme.wall_vertical_text is set (Manhattan's "hochkant" skyscraper
## look), otherwise the original single horizontal word centered on the
## block (every other theme, unchanged). The returned node's local Y origin
## is already correct for its cell (0 for a totem's floor-up stack, height*
## 0.5 for a centered horizontal word) — callers only need to set X/Z and
## the facing rotation.
func _build_wall_word(word: String, color: Color, height: float, font_size: int, depth: float, emission_energy: float) -> Node3D:
	if city_theme.wall_vertical_text:
		return WordMeshScript.build_vertical_stack(word, color, height, {"font_size": font_size, "depth": depth, "emission_energy": emission_energy})
	var wm := WordMeshScript.build(word, color, {"font_size": font_size, "depth": depth, "emission_energy": emission_energy})
	wm.position.y = height * 0.5
	return wm


func _build_walls() -> void:
	var wall_cells := []
	for r in maze.rows:
		for c in maze.cols:
			if maze.grid[r][c] == 1:
				wall_cells.append(Vector2i(r, c))

	# Landmark name + final height precomputed once per cell so the boxy
	# multimesh, the word-mesh skin and the collision shape all agree.
	var landmark_names := {}
	var heights := {}
	for cell in wall_cells:
		var nm := ""
		if city_theme.landmark_provider_script != null:
			nm = city_theme.landmark_provider_script.landmark_at(cell.x, cell.y)
		landmark_names[cell] = nm
		heights[cell] = _wall_height_for_cell(cell, nm)

	# Unit-height box mesh, scaled per-instance below — lets one shared
	# MultiMesh still give every block its own real height (a MultiMesh
	# can't vary its mesh, only each instance's transform).
	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3(CELL, 1.0, CELL)
	box_mesh.material = wall_material

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = box_mesh
	mm.instance_count = wall_cells.size()
	var fp: float = city_theme.wall_footprint_scale
	for i in wall_cells.size():
		var cell: Vector2i = wall_cells[i]
		var h: float = heights[cell]
		var basis := Basis().scaled(Vector3(fp, h, fp))
		var xf := Transform3D(basis, Vector3(cell.y * CELL, h * 0.5, cell.x * CELL))
		mm.set_instance_transform(i, xf)

	normal_wall_mmi = MultiMeshInstance3D.new()
	normal_wall_mmi.multimesh = mm
	add_child(normal_wall_mmi)

	# The word-built-world skin: every wall cell doubles as a 3D letterform,
	# now at that cell's real height (see _wall_height_for_cell) instead of
	# a uniform WALL_H — a theme that opts in (CityTheme.wall_vertical_text,
	# e.g. Manhattan) reads it hochkant, one letter stacked per row up the
	# block's full height, so a SKYSCRAPER or a landmark actually looks
	# taller than an ordinary BUILDING next to it. Built alongside the
	# normal boxy walls (not on demand) so toggling Word Mode mid-level is
	# instant; hidden until set_word_mode() turns it on. Entirely data-
	# driven off city_theme (see city_theme.gd/city_themes.gd): an ordinary
	# block cycles through city_theme.wall_palette as city_theme.wall_word
	# (or wall_word_tall, see _is_skyscraper_cell), and any block
	# city_theme.landmark_provider_script actually names (e.g.
	# manhattan_maze.gd's real Midtown buildings) gets that name, a
	# brighter accent color, and its own pulsing light (animated in
	# _process, see landmark_lights) instead.
	word_wall_root = Node3D.new()
	add_child(word_wall_root)
	landmark_lights.clear()
	for cell in wall_cells:
		var landmark_name: String = landmark_names[cell]
		var h: float = heights[cell]
		var rot_y := 0.0
		if city_theme.wall_alternate_rotation and (cell.x + cell.y) % 2 != 0:
			rot_y = PI / 2.0
		if landmark_name != "":
			var accent: Color = city_theme.landmark_accents[landmark_lights.size() % city_theme.landmark_accents.size()]
			var node := _build_wall_word(landmark_name, accent, h, city_theme.landmark_font_size, WALL_H * city_theme.landmark_depth_scale, city_theme.landmark_emission_energy)
			node.position.x = cell.y * CELL
			node.position.z = cell.x * CELL
			node.rotation.y = rot_y
			word_wall_root.add_child(node)
			var light := OmniLight3D.new()
			light.light_color = accent
			light.omni_range = 3.4 + h * 0.06
			light.light_energy = 1.2
			light.position = Vector3(cell.y * CELL, h * 0.5, cell.x * CELL)
			word_wall_root.add_child(light)
			landmark_lights.append(light)
		else:
			var block_color: Color = city_theme.wall_palette[absi(cell.x * 31 + cell.y) % city_theme.wall_palette.size()]
			var word: String = city_theme.wall_word
			if city_theme.wall_word_tall != "" and _is_skyscraper_cell(cell):
				word = city_theme.wall_word_tall
			var node2 := _build_wall_word(word, block_color, h, city_theme.wall_font_size, WALL_H * city_theme.wall_depth_scale, city_theme.wall_emission_energy)
			node2.position.x = cell.y * CELL
			node2.position.z = cell.x * CELL
			node2.rotation.y = rot_y
			word_wall_root.add_child(node2)

	walls_body = StaticBody3D.new()
	walls_body.collision_layer = 2
	walls_body.collision_mask = 0
	add_child(walls_body)
	for cell in wall_cells:
		var h2: float = heights[cell]
		var shape := BoxShape3D.new()
		shape.size = Vector3(CELL * fp, h2, CELL * fp)
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.position = Vector3(cell.y * CELL, h2 * 0.5, cell.x * CELL)
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

	# A theme with much-taller-than-WALL_H buildings (e.g. Manhattan's real
	# skyscraper heights) skips the ceiling plane entirely — see CityTheme.
	# ceil_enabled's own comment for why a fixed-height ceiling and tall
	# buildings don't mix (it hides everything above it, letter by letter).
	if city_theme.ceil_enabled:
		# A sky-cloud theme's ceiling sits at CLOUD_HEIGHT_MULT x WALL_H
		# (matching where _build_sky_clouds floats its clouds), not right at
		# the wall tops — the voxel clouds need real headroom above the maze
		# to read as sky rather than as a low cap sitting on the walls.
		var ceil_h: float = WALL_H * CLOUD_HEIGHT_MULT if city_theme.ceil_sky_clouds else WALL_H
		var ceil_mesh := MeshInstance3D.new()
		ceil_mesh.mesh = plane
		ceil_mesh.material_override = ceil_mat
		ceil_mesh.position = Vector3((maze.cols - 1) * CELL * 0.5, ceil_h, (maze.rows - 1) * CELL * 0.5)
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
	# The sky ceiling itself floats at WALL_H * CLOUD_HEIGHT_MULT for this
	# theme (see _build_floor_ceiling) — clouds hug just under it, same as
	# before, just at that raised height instead of right at the wall tops.
	var sky_ceil_h: float = WALL_H * CLOUD_HEIGHT_MULT
	for i in mini(cloud_count, candidates.size()):
		var cell: Vector2i = candidates[i]
		# 1.5x the original 0.10-0.16 voxel-size range, per an earlier
		# request that the clouds themselves be visually bigger.
		var voxel_size: float = (0.1 + randf() * 0.06) * 1.5
		var cloud := CloudMeshScript.build({"voxel_size": voxel_size})
		var jitter_x := (randf() - 0.5) * CELL * 0.6
		var jitter_z := (randf() - 0.5) * CELL * 0.6
		# Keep the cloud's top edge just under the (raised) ceiling
		# regardless of its own randomized size: CloudMesh is
		# CloudMeshScript.ROWS tall, centered on its own origin, so half
		# that height plus a small gap sits above the origin we place it
		# at. CLOUD_MIN_WALL_CLEARANCE is then an explicit floor under that
		# — the cloud can never end up nearer the wall tops than this, even
		# for an unusually large cloud.
		var half_h: float = CloudMeshScript.ROWS * voxel_size * 0.5
		var cloud_y: float = maxf(sky_ceil_h - 0.15 - half_h, WALL_H + CLOUD_MIN_WALL_CLEARANCE)
		cloud.position = Vector3(cell.y * CELL + jitter_x, cloud_y, cell.x * CELL + jitter_z)
		cloud.rotation.y = randf() * TAU
		add_child(cloud)
		sky_cloud_nodes.append(cloud)


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


## Turns the matrix_rain wall shader's psychedelic mode on/off (see
## shaders/matrix_rain.gdshader's psychedelic_amount uniform) — used by
## Main for the Fear & Loathing pickup's temporary "LSD trip" wall look.
## A no-op on themes that don't use the matrix_rain shader at all (Manhattan
## has no walls_body/wall_material of that kind — Godot silently ignores a
## shader-parameter set on a material without that uniform).
func set_psychedelic(active: bool) -> void:
	if wall_material is ShaderMaterial:
		wall_material.set_shader_parameter("psychedelic_amount", 1.0 if active else 0.0)


func _pick_farthest_cell(cells: Array, from: Vector2i) -> Vector2i:
	var best: Vector2i = cells[0]
	var best_d := -1.0
	for cell in cells:
		var d: float = (cell.x - from.x) * (cell.x - from.x) + (cell.y - from.y) * (cell.y - from.y)
		if d > best_d:
			best_d = d
			best = cell
	return best


## The WORD pickup's visual: a small blocky white pixel-rabbit (see
## pixel_rabbit_mesh.gd) rather than the literal word "WORD" — "follow the
## white rabbit" for the pickup that drops wall collision and reskins the
## level into its word-built-world look. One instance per cell in
## word_powerup_cells (see WORD_POWERUP_COUNT).
func _build_word_powerup_mesh(cell: Vector2i) -> void:
	var mesh := PixelRabbitMeshScript.build()
	mesh.scale = Vector3.ONE * 1.4
	mesh.position = Vector3(cell.y * CELL, 0.55, cell.x * CELL)
	var light := OmniLight3D.new()
	light.light_color = Color(0.85, 0.9, 1.0)
	light.omni_range = 2.6
	light.light_energy = 0.85
	mesh.add_child(light)
	add_child(mesh)
	word_powerup_nodes.append(mesh)
	word_powerup_alive.append(true)


## The Fear & Loathing pickup's visual — see psychedelic_head_mesh.gd. One
## instance per cell in fear_powerup_cells (see FEAR_POWERUP_COUNT).
func _build_fear_powerup_mesh(cell: Vector2i) -> void:
	var head := PsychedelicHeadMeshScript.build()
	head.scale = Vector3.ONE * 0.5
	head.position = Vector3(cell.y * CELL, 0.55, cell.x * CELL)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.4, 0.9)
	light.omni_range = 2.6
	light.light_energy = 0.9
	head.add_child(light)
	add_child(head)
	fear_powerup_nodes.append(head)
	fear_powerup_alive.append(true)


## Greedy farthest-point sampling seeded by `anchor` (not itself part of the
## output): picks up to `count` cells out of `cells` so each new pick is as
## far as possible from `anchor` *and* every cell already picked — spreads
## several same-type pickups across different neighborhoods instead of
## clustering them together. Used for the WORD/Fear & Loathing pickups below
## now that more than one of each can spawn per level.
func _pick_multiple_farthest(cells: Array, count: int, anchor: Vector2i) -> Array:
	var picked := []
	var refs := [anchor]
	var pool := cells.duplicate()
	for i in count:
		if pool.is_empty():
			break
		var best = null
		var best_d := -1.0
		for cell in pool:
			var d := INF
			for r in refs:
				var dd: float = (cell.x - r.x) * (cell.x - r.x) + (cell.y - r.y) * (cell.y - r.y)
				if dd < d:
					d = dd
			if d > best_d:
				best_d = d
				best = cell
		picked.append(best)
		refs.append(best)
		pool.erase(best)
	return picked


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


## Greedy farthest-point sampling: picks `count` cells out of `cells` so
## they're spread across different neighborhoods rather than clustering —
## used to seed the metro-trail pellet paths below at varied starting
## points across the map instead of all from one corner.
func _spread_seed_cells(cells: Array, count: int) -> Array:
	if cells.is_empty():
		return []
	var picked := [cells[0]]
	while picked.size() < count and picked.size() < cells.size():
		var best = null
		var best_d := -1.0
		for cell in cells:
			if cell in picked:
				continue
			var d := INF
			for p in picked:
				var dd: float = (cell.x - p.x) * (cell.x - p.x) + (cell.y - p.y) * (cell.y - p.y)
				if dd < d:
					d = dd
			if d > best_d:
				best_d = d
				best = cell
		if best == null:
			break
		picked.append(best)
	return picked


## Pellets-as-wayfinding-signposts (CityTheme.pellets_follow_metro_trails,
## Manhattan): a multi-source BFS rooted at every metro cell gives every
## open cell a came_from pointer one step closer to its nearest metro
## (the walking direction toward an exit). Rather than pelleting the whole
## map (which a fully-connected street grid like Manhattan's would turn
## right back into "every open cell", since almost every cell sits on some
## shortest path to some metro), only a handful of spread-out seed cells'
## walked-back paths actually get a pellet — so pellets read as a few
## signposted routes converging on the exits, not a uniform floor fill.
const TRAIL_SEED_COUNT := 9

func _metro_trail_cells(candidates: Array, metro_cells: Array, start_cell: Vector2i) -> Array:
	if metro_cells.is_empty():
		return candidates

	var came_from := {}
	var visited := {}
	var queue: Array = []
	for m in metro_cells:
		visited[m] = true
		queue.append(m)
	var qi := 0
	while qi < queue.size():
		var cur: Vector2i = queue[qi]
		qi += 1
		for n in MazeGen.neighbors_of(maze, cur.x, cur.y):
			if not visited.has(n):
				visited[n] = true
				came_from[n] = cur
				queue.append(n)

	var candidate_set := {}
	for cell in candidates:
		candidate_set[cell] = true

	var seeds := _spread_seed_cells(candidates, TRAIL_SEED_COUNT)
	if candidate_set.has(start_cell) and not (start_cell in seeds):
		seeds.append(start_cell)

	var trail := {}
	var guard_limit: int = maze.rows * maze.cols
	for seed in seeds:
		var cur: Vector2i = seed
		var guard := 0
		while came_from.has(cur) and guard < guard_limit:
			if candidate_set.has(cur):
				trail[cur] = true
			cur = came_from[cur]
			guard += 1
		if candidate_set.has(cur):
			trail[cur] = true

	var out := []
	for cell in candidates:
		if trail.has(cell):
			out.append(cell)
	return out


func _build_pellets(start_cell: Vector2i, reserved_cells: Array = [], metro_cells: Array = []) -> void:
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
	var pellet_candidates := []
	for cell in candidates:
		if not power_set.has(cell):
			pellet_candidates.append(cell)

	if city_theme.pellets_follow_metro_trails and metro_cells.size() > 0:
		pellet_cells = _metro_trail_cells(pellet_candidates, metro_cells, start_cell)
	else:
		pellet_cells = pellet_candidates

	# Word Mode power-up: WORD_POWERUP_COUNT per level that has power-ups at
	# all, taken out of the regular pellet grid (not extra pellets on top of
	# it) and spread apart via farthest-point sampling so they land in
	# different corners of the maze rather than clustering. A "calm explorer"
	# theme like Manhattan has none (see build()/has_power_ups).
	if city_theme.has_power_ups and pellet_cells.size() > 0:
		word_powerup_cells = _pick_multiple_farthest(pellet_cells, WORD_POWERUP_COUNT, start_cell)
		for cell in word_powerup_cells:
			pellet_cells.erase(cell)

	# Fear & Loathing pickup: a second, rarer special pickup type, taken out
	# of the pellet grid the same way as the WORD pickups above and spread
	# apart from both the start and the WORD pickups so the two types don't
	# end up bunched together.
	if city_theme.has_power_ups and pellet_cells.size() > 0:
		var fear_anchor: Vector2i = word_powerup_cells[0] if word_powerup_cells.size() > 0 else start_cell
		fear_powerup_cells = _pick_multiple_farthest(pellet_cells, FEAR_POWERUP_COUNT, fear_anchor)
		for cell in fear_powerup_cells:
			pellet_cells.erase(cell)

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

	for cell in word_powerup_cells:
		_build_word_powerup_mesh(cell)
	for cell in fear_powerup_cells:
		_build_fear_powerup_mesh(cell)


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
	var result := {"pellet": false, "power": false, "fruit": false, "word_powerup": false, "fear_powerup": false}
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

	for i in word_powerup_nodes.size():
		if not word_powerup_alive[i]:
			continue
		var node: Node3D = word_powerup_nodes[i]
		var d := Vector2(node.position.x - pos.x, node.position.z - pos.z).length()
		if d < 0.5:
			word_powerup_alive[i] = false
			node.visible = false
			result.word_powerup = true

	for i in fear_powerup_nodes.size():
		if not fear_powerup_alive[i]:
			continue
		var node: Node3D = fear_powerup_nodes[i]
		var d := Vector2(node.position.x - pos.x, node.position.z - pos.z).length()
		if d < 0.5:
			fear_powerup_alive[i] = false
			node.visible = false
			result.fear_powerup = true

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
	for i in word_powerup_nodes.size():
		if not word_powerup_alive[i]:
			continue
		var wnode: Node3D = word_powerup_nodes[i]
		wnode.rotate_y(delta * 2.0)
		var ws := 1.4 + sin(_t * 5.0 + i) * 0.14
		wnode.scale = Vector3.ONE * ws
	for i in fear_powerup_nodes.size():
		if not fear_powerup_alive[i]:
			continue
		var fnode: Node3D = fear_powerup_nodes[i]
		fnode.rotate_y(delta * 1.4)
		var fs := 0.5 + sin(_t * 3.0 + i) * 0.05
		fnode.scale = Vector3.ONE * fs
		for child in fnode.get_children():
			if child is MeshInstance3D and child.name.begins_with("aura"):
				var hue := fmod(_t * 0.3 + float(child.get_index()) / 8.0 + i * 0.5, 1.0)
				var c := Color.from_hsv(hue, 0.9, 1.0)
				var mat: StandardMaterial3D = child.material_override
				mat.albedo_color = c
				mat.emission = c
	for i in landmark_lights.size():
		var light: OmniLight3D = landmark_lights[i]
		light.light_energy = 1.0 + sin(_t * 3.0 + i * 0.7) * 0.55
