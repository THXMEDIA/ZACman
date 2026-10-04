extends Node3D
## MazeView — builds the 3D geometry (walls, floor, ceiling, pellets, power
## pellets, fruit) for one generated maze, and owns pickup consumption.
## Instanced fresh by Main.gd for every level.

const CELL := 2.0
const WALL_H := 4.4 # was 3.8 (doubled from the original 1.9 earlier); raised again per user request — taller, more imposing corridors. Only the "normal" (Speedrun) theme actually uses this as its wall height: Manhattan sets its own real-world building heights (CityTheme.wall_height_min/max) and ignores WALL_H except as a last-resort fallback (see _wall_height_for_cell).
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
const WhiteRabbitScript := preload("res://scripts/white_rabbit.gd")
const ConditionLooksScript := preload("res://scripts/condition_looks.gd")

var maze # MazeGen.Maze
var theme := "normal" # theme id — see city_themes.gd's registry ("normal" | "manhattan" | ...)
var city_theme # CityTheme — the resolved visual/gameplay bundle for `theme` (see city_theme.gd)
var pellet_cells: Array = [] # Array[Vector2i]
var pellet_alive: Array = [] # Array[bool], parallel to pellet_cells
## All pellets of a level are ONE MultiMesh (one draw call, docs/design/
## tokyo-explorer.md M2): instance i is pellet_cells[i]; an eaten pellet's
## instance is collapsed to a zero-size transform (no node per pellet).
var pellet_mmi: MultiMeshInstance3D = null
var pellet_multimesh: MultiMesh = null
var power_cells: Array = [] # Array[Vector2i]
var power_nodes: Array = [] # Array[MeshInstance3D]
var power_alive: Array = [] # Array[bool]

var fruit_node: MeshInstance3D = null
var fruit_alive := false
var fruit_expire_at := 0.0

## The white rabbit (speedrun levels only, spec 2.2): exactly one per level,
## in a dead end far from the start (WhiteRabbit.pick_cell), on a cell that
## carries no pellet — it is voluntary and never counts toward clearing the
## level. Picking it up starts a condition (Main._on_rabbit_picked).
const RABBIT_COLOR := Color("f2f2ed") # rabbit white (spec 1.2)
var rabbit_cell := Vector2i(-1, -1)
var rabbit_node: Node3D = null # container on the floor of the rabbit cell (light cone stays on the floor)
var rabbit_figure: Node3D = null # the voxel rabbit inside it: floats, bobs and turns
var rabbit_alive := false
var rabbit_material: StandardMaterial3D = null
## UX-W3: hovering height of the figure's feet, bob amplitude / frequency and
## turn rate — every motion below 0.5 Hz.
const RABBIT_HOVER := 0.22
const RABBIT_BOB := 0.05
const RABBIT_BOB_HZ := 0.4
const RABBIT_TURN_RAD_S := 1.5 # one turn in ~4.2 s = 0.24 Hz
const RABBIT_SCALE := 1.3 # ears up to ~1.5 m: reads from down the corridor

var walls_body: StaticBody3D
var normal_wall_mmi: MultiMeshInstance3D
var word_wall_root: Node3D = null # word-built skin, only for permanently word-built themes (Manhattan)
var word_mode_active := false
var landmark_lights: Array = [] # Array[OmniLight3D], Manhattan only — pulsed in _process
var sky_cloud_nodes: Array = [] # Array[MultiMeshInstance3D], sky-cloud themes only — see _build_sky_clouds; tracked mainly so tests can check their height
var _t := 0.0

## The level's color variant of a shader look (CityTheme.level_looks entry,
## {top, base, body, ghosts}); empty when the theme has no level looks.
var level_look_id := ""
var level_look: Dictionary = {}
## Cell map for the floor shader, one pixel per cell: R = wall,
## G = junction (open cell with >= 3 open neighbors). Shader themes only.
var maze_tex: ImageTexture
var floor_mesh: MeshInstance3D
## The theme's own static scenery (CityTheme.scenery_builder_script, Tokyo's
## neon contours); null for every other theme.
var scenery_root: Node3D = null
## The level seed the scenery and the pellet trails were built with (Tokyo).
var scenery_seed := 0
var screen_overlay: CanvasLayer = null # CRT overlay (CityTheme.screen_overlay_shader_path), else null

## ---- Look switching (rabbit conditions, spec 1.2) ----
## A look is a pair of materials for the SAME wall MultiMesh and floor mesh
## plus shader parameters; set_look() only swaps material_override and sets
## the parameters, it never builds a second set of walls. build() registers
## LOOK_BASE (the theme's own materials) and, for a theme with condition
## shaders, every ConditionLooks look on the shared kond_wall/kond_floor
## materials (only the `look` uniform differs).
const LOOK_BASE := "base"
var current_look := LOOK_BASE
var _looks: Dictionary = {} # look id -> {"wall": Material, "floor": Material, "params": Dictionary}
var cond_wall_material: ShaderMaterial = null
var cond_floor_material: ShaderMaterial = null

var wall_material: Material # the CURRENT wall material: StandardMaterial3D, the theme's wall shader or a condition look's (see _make_materials / set_look)
var pellet_material: Material # StandardMaterial3D, or the theme's pellet shader
var power_material: StandardMaterial3D
var fruit_material: StandardMaterial3D


## `reserved_cells` (Manhattan only) are cells a stationary obstacle
## (Pedestrian) will occupy — excluded from pellet placement up front so a
## pedestrian standing on a pellet can never permanently block it (taxis
## are moving obstacles and don't need this: they pass through, they don't
## park on a pellet forever). `metro_cells` (Manhattan only) are the metro-
## station cells pellets should route toward — see
## CityTheme.pellets_follow_metro_trails / _metro_trail_cells.
##
## `rabbit_seed` >= 0 places the white rabbit (deterministic per level seed,
## see WhiteRabbit.pick_cell); -1 = no rabbit (Manhattan).
##
## `look_id` names the level's color variant (Levels.POOL[].look, e.g.
## "lagune"/"riff"); "" or an unknown id uses CityTheme.default_level_look.
##
## `level_seed` drives everything decorative of a theme with its own scenery
## (Tokyo: floor bands, background silhouettes, which trails carry pellets) —
## the same seed always builds the same city (tests/test_tokyo.gd).
func build(new_maze, start_cell: Vector2i, maze_theme: String = "normal", reserved_cells: Array = [], metro_cells: Array = [], rabbit_seed: int = -1, look_id: String = "", level_seed: int = 0) -> void:
	visible = true # Main hides the maze behind the start screen (QA W1)
	for child in get_children():
		child.queue_free()
	pellet_cells.clear()
	pellet_alive.clear()
	pellet_mmi = null
	pellet_multimesh = null
	power_cells.clear()
	power_nodes.clear()
	power_alive.clear()
	fruit_node = null
	fruit_alive = false
	rabbit_cell = Vector2i(-1, -1)
	rabbit_node = null
	rabbit_figure = null
	rabbit_alive = false
	rabbit_material = null
	word_wall_root = null
	word_mode_active = false
	sky_cloud_nodes.clear()
	screen_overlay = null
	scenery_root = null
	scenery_seed = level_seed
	_looks.clear()
	current_look = LOOK_BASE

	maze = new_maze
	theme = maze_theme
	city_theme = CityThemesScript.get_theme(theme)
	level_look_id = ""
	level_look = {}
	if not city_theme.level_looks.is_empty():
		level_look_id = look_id if city_theme.level_looks.has(look_id) else city_theme.default_level_look
		level_look = city_theme.level_looks.get(level_look_id, {})
	_make_materials()
	_build_walls()
	_build_floor_ceiling()
	if city_theme.scenery_builder_script != null:
		scenery_root = city_theme.scenery_builder_script.build(maze, city_theme, level_seed)
		add_child(scenery_root)
	_build_sky_clouds()
	_build_tunnel_vistas()
	_build_pellets(start_cell, reserved_cells, metro_cells, rabbit_seed)
	_build_screen_overlay()
	register_look(LOOK_BASE, wall_material, floor_mesh.material_override)
	_register_condition_looks()
	# A permanently-word-built theme (Manhattan) shows the word-built-world
	# look for good; every other theme never does (Word Mode is gone).
	set_word_mode(city_theme.permanently_word_built)


func _make_materials() -> void:
	maze_tex = null
	if city_theme.wall_shader_path != "" or city_theme.floor_shader_path != "":
		_build_maze_tex()
	if city_theme.wall_shader_path != "":
		# Speedrun base look: dark mass, glowing top edge, base dashes,
		# vertical lines only at free wall ends (neighbor mask per instance,
		# see _build_walls), colors from the level look.
		var sp_mat := ShaderMaterial.new()
		sp_mat.shader = load(city_theme.wall_shader_path)
		sp_mat.set_shader_parameter("cell", CELL)
		_apply_level_look(sp_mat)
		wall_material = sp_mat
	else:
		var sm := StandardMaterial3D.new()
		sm.albedo_color = Color(0.047, 0.086, 0.22)
		sm.emission_enabled = true
		sm.emission = Color(0.118, 0.373, 1.0)
		sm.emission_energy_multiplier = 0.55
		sm.roughness = 0.55
		sm.metallic = 0.15
		wall_material = sm

	if city_theme.pellet_shader_path != "":
		var pm := ShaderMaterial.new()
		pm.shader = load(city_theme.pellet_shader_path)
		pm.set_shader_parameter("col", city_theme.pellet_color)
		pellet_material = pm
	else:
		var sm2 := StandardMaterial3D.new()
		sm2.albedo_color = city_theme.pellet_color
		sm2.emission_enabled = true
		sm2.emission = city_theme.pellet_emission
		sm2.emission_energy_multiplier = city_theme.pellet_energy
		pellet_material = sm2

	power_material = StandardMaterial3D.new()
	power_material.albedo_color = city_theme.power_color
	power_material.emission_enabled = true
	power_material.emission = city_theme.power_emission
	power_material.emission_energy_multiplier = city_theme.power_energy

	# Condition looks: one shared material pair, same level-look colors as
	# the base so the swap at transition 0 is invisible.
	cond_wall_material = null
	cond_floor_material = null
	if city_theme.cond_wall_shader_path != "":
		cond_wall_material = ShaderMaterial.new()
		cond_wall_material.shader = load(city_theme.cond_wall_shader_path)
		cond_wall_material.set_shader_parameter("cell", CELL)
		cond_wall_material.set_shader_parameter("wall_top", WALL_H)
		_apply_level_look(cond_wall_material)
	if city_theme.cond_floor_shader_path != "":
		cond_floor_material = ShaderMaterial.new()
		cond_floor_material.shader = load(city_theme.cond_floor_shader_path)
		cond_floor_material.set_shader_parameter("cell", CELL)
		cond_floor_material.set_shader_parameter("maze_tex", maze_tex)
		cond_floor_material.set_shader_parameter("maze_size", Vector2(maze.cols, maze.rows))
		cond_floor_material.set_shader_parameter("floor_albedo", city_theme.floor_color)
		_apply_level_look(cond_floor_material)

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
		var opts := {"font_size": font_size, "depth": depth, "emission_energy": emission_energy}
		if city_theme.wall_word_fit_footprint:
			var fit: float = CELL * city_theme.wall_footprint_scale
			opts["max_width"] = fit
			opts["max_depth"] = fit
		return WordMeshScript.build_vertical_stack(word, color, height, opts)
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

	# The wall shader needs to know which neighbors are walls (to draw
	# vertical lines only at free ends): one Color per instance,
	# r/g/b/a = wall at row-1 / row+1 / col-1 / col+1.
	var neighbor_mask: bool = city_theme.wall_shader_path != ""
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = neighbor_mask
	mm.mesh = box_mesh
	mm.instance_count = wall_cells.size()
	var fp: float = city_theme.wall_footprint_scale
	for i in wall_cells.size():
		var cell: Vector2i = wall_cells[i]
		var h: float = heights[cell]
		var basis := Basis().scaled(Vector3(fp, h, fp))
		var xf := Transform3D(basis, Vector3(cell.y * CELL, h * 0.5, cell.x * CELL))
		mm.set_instance_transform(i, xf)
		if neighbor_mask:
			mm.set_instance_custom_data(i, Color(
				1.0 if _is_wall(cell.x - 1, cell.y) else 0.0,
				1.0 if _is_wall(cell.x + 1, cell.y) else 0.0,
				1.0 if _is_wall(cell.x, cell.y - 1) else 0.0,
				1.0 if _is_wall(cell.x, cell.y + 1) else 0.0))

	normal_wall_mmi = MultiMeshInstance3D.new()
	normal_wall_mmi.multimesh = mm
	# On the instance, not the mesh, so set_look() can swap it in place.
	normal_wall_mmi.material_override = wall_material
	add_child(normal_wall_mmi)

	# The word-built-world skin (permanently word-built themes only, e.g.
	# Manhattan; see _build_word_walls): every wall cell doubles as a 3D letterform,
	# now at that cell's real height (see _wall_height_for_cell) instead of
	# a uniform WALL_H — a theme that opts in (CityTheme.wall_vertical_text,
	# e.g. Manhattan) reads it hochkant, one letter stacked per row up the
	# block's full height, so a SKYSCRAPER or a landmark actually looks
	# taller than an ordinary BUILDING next to it. Entirely data-
	# driven off city_theme (see city_theme.gd/city_themes.gd): an ordinary
	# block cycles through city_theme.wall_palette as city_theme.wall_word
	# (or wall_word_tall, see _is_skyscraper_cell), and any block
	# city_theme.landmark_provider_script actually names (e.g.
	# manhattan_maze.gd's real Midtown buildings) gets that name, a
	# brighter accent color, and its own pulsing light (animated in
	# _process, see landmark_lights) instead.
	landmark_lights.clear()
	if city_theme.permanently_word_built:
		_build_word_walls(wall_cells, landmark_names, heights)

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


func _build_word_walls(wall_cells: Array, landmark_names: Dictionary, heights: Dictionary) -> void:
	word_wall_root = Node3D.new()
	add_child(word_wall_root)
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


func _apply_level_look(m: ShaderMaterial) -> void:
	if level_look.is_empty():
		return
	m.set_shader_parameter("line_top", level_look.top)
	m.set_shader_parameter("line_base", level_look.base)
	m.set_shader_parameter("body_color", level_look.body)


## The ghost colors for this level: the level look's own list if it has
## one, else the theme's (see CityTheme.ghost_palette).
func ghost_palette() -> Array:
	if level_look.has("ghosts"):
		return level_look.ghosts
	return city_theme.ghost_palette


## Cell map as a texture (one pixel per cell) for the floor shader:
## R = wall, G = junction (open cell with >= 3 open neighbors).
func _build_maze_tex() -> void:
	var img := Image.create(maze.cols, maze.rows, false, Image.FORMAT_RGBA8)
	for r in maze.rows:
		for c in maze.cols:
			var wall: bool = maze.grid[r][c] == 1
			var open_n := 0
			if not wall:
				for d in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
					var rr: int = r + d.x
					var cc: int = c + d.y
					if rr >= 0 and rr < maze.rows and cc >= 0 and cc < maze.cols and maze.grid[rr][cc] != 1:
						open_n += 1
			img.set_pixel(c, r, Color(1.0 if wall else 0.0, 1.0 if open_n >= 3 else 0.0, 0.0, 1.0))
	maze_tex = ImageTexture.create_from_image(img)


func _is_wall(r: int, c: int) -> bool:
	if r < 0 or r >= maze.rows or c < 0 or c >= maze.cols:
		return false
	return maze.grid[r][c] == 1


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

	floor_mesh = MeshInstance3D.new()
	floor_mesh.mesh = plane
	floor_mesh.material_override = floor_mat
	if city_theme.floor_shader_path != "":
		# Lit (not unshaded) dark floor with a cell grid and junction frames.
		var fsm := ShaderMaterial.new()
		fsm.shader = load(city_theme.floor_shader_path)
		fsm.set_shader_parameter("cell", CELL)
		fsm.set_shader_parameter("maze_tex", maze_tex)
		fsm.set_shader_parameter("maze_size", Vector2(maze.cols, maze.rows))
		fsm.set_shader_parameter("floor_albedo", city_theme.floor_color)
		_apply_level_look(fsm)
		if city_theme.floor_setup_script != null:
			city_theme.floor_setup_script.setup_floor(fsm, maze, scenery_seed)
		floor_mesh.material_override = fsm
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


## Swaps the visible wall skin: word-built (letterforms) vs the normal boxy
## walls. Only a permanently word-built theme has the word skin at all; for
## every other theme this keeps the boxy walls. Collision (walls_body) is
## untouched either way.
func set_word_mode(active: bool) -> void:
	word_mode_active = active and word_wall_root != null
	if word_wall_root != null:
		word_wall_root.visible = word_mode_active
	normal_wall_mmi.visible = not word_mode_active


## ---- Look API (rabbit conditions switch looks at runtime) ----

## Registers (or replaces) a look: the materials the wall MultiMesh and the
## floor use while it is active, plus shader parameters set on them when it
## is switched on (e.g. {"look": 1}). A null material keeps that surface's
## base material. build() registers LOOK_BASE with the theme's own materials.
func register_look(look_id: String, wall_mat: Material, floor_mat: Material, params: Dictionary = {}) -> void:
	_looks[look_id] = {"wall": wall_mat, "floor": floor_mat, "params": params}


## Every ConditionLooks look on the shared condition materials (only for a
## theme with condition shaders; Manhattan has none).
func _register_condition_looks() -> void:
	if cond_wall_material == null:
		return
	for id in ConditionLooksScript.LOOKS:
		var look: Dictionary = ConditionLooksScript.LOOKS[id]
		register_look(id, cond_wall_material, cond_floor_material, {"look": look.shader, "transition": 0.0, "flip": 0.0, "matrix_solid": 0.0})


func has_look(look_id: String) -> bool:
	return _looks.has(look_id)


## Switches the visible look by swapping material_override on the existing
## wall MultiMesh and floor mesh — the same instances, no second wall set,
## collision untouched. Returns false (and changes nothing) for an unknown id.
func set_look(look_id: String) -> bool:
	if not _looks.has(look_id):
		return false
	var base: Dictionary = _looks[LOOK_BASE]
	var look: Dictionary = _looks[look_id]
	var wall_mat: Material = look.wall if look.wall != null else base.wall
	var floor_mat: Material = look.floor if look.floor != null else base.floor
	wall_material = wall_mat
	normal_wall_mmi.material_override = wall_mat
	floor_mesh.material_override = floor_mat
	current_look = look_id
	for param in look.get("params", {}):
		set_look_param(param, look.params[param])
	return true


## Sets a shader uniform on the current look's wall and floor materials
## (for one shared condition shader with a `look`/`transition` uniform, see
## spec 1.2). Materials without that uniform ignore it.
## W2: no temporary array — this runs every frame a uniform changes.
func set_look_param(param: String, value) -> void:
	var wm: Material = normal_wall_mmi.material_override
	if wm is ShaderMaterial:
		wm.set_shader_parameter(param, value)
	var fm: Material = floor_mesh.material_override
	if fm is ShaderMaterial and fm != wm:
		fm.set_shader_parameter(param, value)


## The white rabbit (UX-W3): a voxel rabbit in rabbit white that floats a
## little above the floor and slowly turns (pixel_rabbit_mesh.gd), a soft
## light around it and a weak light cone on the floor under it — a spot
## light from above plus a faint glow disk, so the cell reads as "something
## is here" from down the corridor. The container stays on the floor; only
## the figure moves.
func _build_rabbit_mesh(cell: Vector2i) -> void:
	var root := Node3D.new()
	root.name = "WhiteRabbit"
	root.position = Vector3(cell.y * CELL, 0.0, cell.x * CELL)
	var figure := PixelRabbitMeshScript.build({"color": RABBIT_COLOR})
	figure.name = "Figure"
	figure.scale = Vector3.ONE * RABBIT_SCALE
	figure.position.y = RABBIT_HOVER
	root.add_child(figure)
	rabbit_material = PixelRabbitMeshScript.body_material(figure)

	var light := OmniLight3D.new()
	light.light_color = Color(0.95, 0.95, 1.0)
	light.omni_range = 2.6
	light.light_energy = 0.7
	light.position.y = 0.7
	root.add_child(light)

	var spot := SpotLight3D.new()
	spot.name = "LightCone"
	spot.light_color = RABBIT_COLOR
	spot.light_energy = 1.4
	spot.spot_range = 3.4
	spot.spot_angle = 24.0
	spot.spot_attenuation = 0.6
	spot.position.y = 2.9
	spot.rotation.x = -PI / 2.0 # straight down
	root.add_child(spot)

	var disk := MeshInstance3D.new()
	disk.name = "FloorGlow"
	var plane := PlaneMesh.new()
	plane.size = Vector2(1.5, 1.5)
	disk.mesh = plane
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.set_color(1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 64
	tex.height = 64
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	dm.albedo_texture = tex
	dm.albedo_color = Color(RABBIT_COLOR, 0.22)
	dm.cull_mode = BaseMaterial3D.CULL_DISABLED
	disk.material_override = dm
	disk.position.y = 0.02
	root.add_child(disk)

	add_child(root)
	rabbit_node = root
	rabbit_figure = figure
	rabbit_alive = true


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


func _build_pellets(start_cell: Vector2i, reserved_cells: Array = [], metro_cells: Array = [], rabbit_seed: int = -1) -> void:
	var all_cells: Array = MazeGen.cells_in_room(maze, false)
	var reserved_set := {}
	for cell in reserved_cells:
		reserved_set[cell] = true
	var candidates := []
	for cell in all_cells:
		if cell != start_cell and not reserved_set.has(cell):
			candidates.append(cell)

	# A "calm explorer" theme (city_theme.has_power_ups == false, e.g.
	# Manhattan) has no power-ups at all (no power pellets, no rabbit
	# below) — it has no ghosts to use them against. Every open cell
	# there is just a plain collectible pellet.
	power_cells = _pick_power_cells(candidates) if city_theme.has_power_ups else []
	var power_set := {}
	for cell in power_cells:
		power_set[cell] = true
	var pellet_candidates := []
	for cell in candidates:
		if not power_set.has(cell):
			pellet_candidates.append(cell)

	if city_theme.pellets_follow_metro_trails and metro_cells.size() > 0 and city_theme.pellet_trail_provider_script != null:
		# The theme lays its own trails (Tokyo: along the street center lines,
		# every cell, not only the odd/odd room cells).
		pellet_cells = []
		for cell in city_theme.pellet_trail_provider_script.trail_cells(maze, metro_cells, start_cell, scenery_seed):
			if cell != start_cell and not reserved_set.has(cell) and not power_set.has(cell) and MazeGen.is_open(maze, cell.x, cell.y):
				pellet_cells.append(cell)
	elif city_theme.pellets_follow_metro_trails and metro_cells.size() > 0:
		pellet_cells = _metro_trail_cells(pellet_candidates, metro_cells, start_cell)
	else:
		pellet_cells = pellet_candidates

	# White rabbit: one per level (rabbit_seed >= 0), in a far dead end that
	# is neither the start nor a power pellet; its cell carries no pellet, so
	# the level never needs it (voluntary, spec 2.2).
	if rabbit_seed >= 0 and city_theme.has_power_ups:
		rabbit_cell = WhiteRabbitScript.pick_cell(MazeGen, maze, start_cell, rabbit_seed, power_cells)
		if rabbit_cell.x >= 0:
			pellet_cells.erase(rabbit_cell)

	var sphere: Mesh = _pickup_mesh(city_theme.pellet_shape, city_theme.pellet_size, pellet_material)
	pellet_multimesh = MultiMesh.new()
	pellet_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	pellet_multimesh.mesh = sphere
	pellet_multimesh.instance_count = pellet_cells.size()
	for i in pellet_cells.size():
		var cell: Vector2i = pellet_cells[i]
		pellet_multimesh.set_instance_transform(i, Transform3D(Basis(), Vector3(cell.y * CELL, city_theme.pellet_height, cell.x * CELL)))
		pellet_alive.append(true)
	pellet_mmi = MultiMeshInstance3D.new()
	pellet_mmi.name = "Kugeln"
	pellet_mmi.multimesh = pellet_multimesh
	add_child(pellet_mmi)

	var power_sphere: Mesh = _pickup_mesh(city_theme.power_shape, city_theme.power_size, power_material)
	for cell in power_cells:
		var mesh := MeshInstance3D.new()
		mesh.mesh = power_sphere
		mesh.position = Vector3(cell.y * CELL, 0.4, cell.x * CELL)
		if city_theme.power_diamond:
			# stood on its tip: a diamond, its own shape next to the cube pellets
			mesh.basis = Basis.from_euler(Vector3(PI * 0.25, 0.0, PI * 0.25))
		var light := OmniLight3D.new()
		light.light_color = city_theme.power_color
		light.omni_range = 2.4
		light.light_energy = 0.7
		mesh.add_child(light)
		add_child(mesh)
		power_nodes.append(mesh)
		power_alive.append(true)

	if rabbit_cell.x >= 0:
		_build_rabbit_mesh(rabbit_cell)


## Collapses pellet i's instance (zero scale): gone from the screen without
## touching the other instances or the draw call.
func _hide_pellet(i: int) -> void:
	var p := pellet_position(i)
	pellet_multimesh.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ZERO), p))


## World position of pellet i (its cell center at the theme's pellet height).
func pellet_position(i: int) -> Vector3:
	var cell: Vector2i = pellet_cells[i]
	return Vector3(cell.y * CELL, city_theme.pellet_height, cell.x * CELL)


## Whether pellet i is still drawn (not eaten; an eaten one is collapsed).
func pellet_visible(i: int) -> bool:
	return pellet_multimesh != null and pellet_alive[i]


## The one mesh every pellet instance uses (sphere or cube of the theme).
func pellet_mesh() -> Mesh:
	return pellet_multimesh.mesh if pellet_multimesh != null else null


func _pickup_mesh(shape: String, size: float, mat: Material) -> Mesh:
	if shape == "cube":
		var b := BoxMesh.new()
		b.size = Vector3.ONE * size * 2.0
		b.material = mat
		return b
	var sp := SphereMesh.new()
	sp.radius = size
	sp.height = size * 2.0
	sp.material = mat
	return sp


## Full-screen overlay (the Speedrun look's CRT lines + vignette) on a
## CanvasLayer below the HUD (layer 0 < the HUD's 1), so it shades the 3D
## view but not the HUD text. Child of MazeView, so a rebuild (e.g. into
## Manhattan) removes it again.
func _build_screen_overlay() -> void:
	if city_theme.screen_overlay_shader_path == "":
		return
	var layer := CanvasLayer.new()
	layer.name = "ScreenOverlay"
	layer.layer = 0
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = load(city_theme.screen_overlay_shader_path)
	rect.material = m
	layer.add_child(rect)
	add_child(layer)
	screen_overlay = layer


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
## what was eaten this call: {pellet, power, fruit, rabbit: bool}.
func consume_at(pos: Vector3, now: float) -> Dictionary:
	var result := {"pellet": false, "power": false, "fruit": false, "rabbit": false}
	for i in pellet_cells.size():
		if not pellet_alive[i]:
			continue
		var cell: Vector2i = pellet_cells[i]
		var d := Vector2(cell.y * CELL - pos.x, cell.x * CELL - pos.z).length()
		if d < 0.42:
			pellet_alive[i] = false
			_hide_pellet(i)
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

	if rabbit_alive and rabbit_node != null:
		var dr := Vector2(rabbit_node.position.x - pos.x, rabbit_node.position.z - pos.z).length()
		if dr < 0.5:
			rabbit_alive = false
			rabbit_node.visible = false
			result.rabbit = true

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
			if city_theme != null and city_theme.power_blink_hz > 0.0:
				# on/off like an arcade energizer, but slow (below 3 Hz)
				power_nodes[i].visible = fmod(_t * city_theme.power_blink_hz, 1.0) < city_theme.power_blink_on_fraction
			else:
				var s := 1.0 + sin(_t * 6.0 + i) * 0.14
				power_nodes[i].scale = Vector3.ONE * s
	if fruit_alive and fruit_node != null:
		fruit_node.rotate_y(delta * 1.4)
	if rabbit_alive and rabbit_figure != null:
		# slow turn (~0.24 Hz) and bob (0.4 Hz): all motion below 0.5 Hz
		rabbit_figure.rotate_y(delta * RABBIT_TURN_RAD_S)
		rabbit_figure.position.y = RABBIT_HOVER + sin(_t * TAU * RABBIT_BOB_HZ) * RABBIT_BOB
	for i in landmark_lights.size():
		var light: OmniLight3D = landmark_lights[i]
		light.light_energy = 1.0 + sin(_t * 3.0 + i * 0.7) * 0.55


## Object style of the condition looks (spec 1.2): pellets, power pellets,
## fruit and the rabbit keep their color and shape; `outline` adds the black
## inverted-hull contour, `ignore_fog` lets them glow through the Stromausfall
## fog. Main applies the same to the ghosts.
func set_object_style(outline: bool, ignore_fog: bool) -> void:
	var ol: Material = ConditionLooksScript.outline_material() if outline else null
	for m in [pellet_material, power_material, fruit_material, rabbit_material]:
		if m == null:
			continue
		m.next_pass = ol
		if m is BaseMaterial3D: # a theme's pellet shader has its own fog setting
			m.disable_fog = ignore_fog
