extends RefCounted
## TokyoWet — the wet floor of the Tokyo line city (docs/design/
## tokyo-explorer.md, M2; shaders/tokyo_floor.gdshader):
##   - bake_puddle_mask(seed): the puddle mask, baked ONCE per level build
##     into a texture (native FastNoiseLite, level seed) — the floor shader
##     only samples it, no fbm per pixel
##   - static_lights(): the light sources the floor reflects as pools and
##     stretched streaks (lamps, screens, subway); tokyo_life.gd hands the 8
##     nearest to the floor shader each frame (and the rain shader)
##   - setup_floor(): CityTheme.floor_setup_script hook, called by MazeView
##     right after the floor material is made
##   - nearest(): picks the 8 nearest candidates without allocating.

const Style := preload("res://scripts/tokyo_style.gd")
const TokyoScenery := preload("res://scripts/tokyo_scenery.gd")
const TokyoMaze := preload("res://scripts/tokyo_maze.gd")

const REFLECT_SHADER := preload("res://shaders/tokyo_floor_reflect.gdshader")
const MASK_SIZE := 512
const MAX_LIGHTS := 8

## Light candidate layout (parallel arrays, one entry per source):
##   pos  Color(x, y, z, source size m)
##   col  Color(r * energy, g * energy, b * energy, pool radius m)
##   prio float, subtracted from the distance when picking the nearest (big
##        screens are seen and reflected from far away)


static var _mask_cache := {}


## The puddle mask of `seed` (cached: the floor and the reflection layer
## share one texture).
static func bake_puddle_mask(seed: int) -> ImageTexture:
	if _mask_cache.has(seed):
		return _mask_cache[seed]
	var n := FastNoiseLite.new()
	n.seed = seed
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = 0.034
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = 4
	n.fractal_lacunarity = 2.1
	n.fractal_gain = 0.5
	var img := n.get_image(MASK_SIZE, MASK_SIZE, false, false, true)
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_mask_cache[seed] = tex
	return tex


static func static_lights() -> Dictionary:
	var pos := PackedColorArray()
	var col := PackedColorArray()
	var prio := PackedFloat32Array()
	for l in TokyoScenery.LAMPS:
		var out := Vector3(l[2], 0, l[3])
		var head := Vector3(l[0], TokyoScenery.LAMP_Y - 0.1, l[1]) + out * 1.3
		var c: Color = Style.LAMP * 1.5
		pos.append(Color(head.x, head.y, head.z, 0.22))
		col.append(Color(c.r, c.g, c.b, 3.6))
		prio.append(0.0)
	# the big screen over the crossing (tokyo_scenery.gd _north_tower)
	var n := Vector3(-1, 0, 1).normalized()
	var big := Vector3(53.0, 12.0, 39.0) + n * 1.2
	var cb: Color = Style.MAGENTA.lerp(Style.AMBER, 0.35) * 1.15
	pos.append(Color(big.x, big.y, big.z, 2.6))
	col.append(Color(cb.r, cb.g, cb.b, 6.5))
	prio.append(18.0)
	# the small screen on the south-east block
	var cs: Color = Style.MAGENTA.lerp(Style.AMBER, 0.45) * 0.8
	pos.append(Color(52.4, 8.0, 64.0, 1.5))
	col.append(Color(cs.r, cs.g, cs.b, 4.0))
	prio.append(6.0)
	# the subway exit (green, its own color — readability rule 1 holds:
	# the green stays at the exit)
	var mcell: Vector2i = TokyoMaze.METRO_CELL
	var m := Vector3(mcell.y * TokyoScenery.CELL, 1.1, mcell.x * TokyoScenery.CELL - 0.9)
	var cm: Color = Style.METRO * 0.9
	pos.append(Color(m.x, m.y, m.z, 1.2))
	col.append(Color(cm.r, cm.g, cm.b, 3.2))
	prio.append(10.0)
	return {"pos": pos, "col": col, "prio": prio}


## Fills out_pos/out_col (size MAX_LIGHTS, preallocated) with the `count`
## candidates nearest to `from` (distance minus prio); returns how many.
## Selection sort into preallocated arrays: no allocation per call.
static func nearest(from: Vector3, pos: PackedColorArray, col: PackedColorArray, prio: PackedFloat32Array, count: int, out_pos: PackedColorArray, out_col: PackedColorArray, score: PackedFloat32Array, used: PackedByteArray) -> int:
	var total := mini(count, pos.size())
	for i in total:
		var p: Color = pos[i]
		score[i] = Vector3(p.r, p.g, p.b).distance_to(from) - prio[i]
		used[i] = 0
	var n := mini(MAX_LIGHTS, total)
	for k in n:
		var best := -1
		var best_s := INF
		for i in total:
			if used[i] == 0 and score[i] < best_s:
				best_s = score[i]
				best = i
		used[best] = 1
		out_pos[k] = pos[best]
		out_col[k] = col[best]
	return n


## CityTheme.floor_setup_script hook (MazeView._build_floor_ceiling): the
## baked puddle mask, road bands, the renderer-dependent strength of the
## fake reflection streaks and the 8 lights nearest to the start.
static func setup_floor(mat: ShaderMaterial, maze, seed: int) -> void:
	mat.set_shader_parameter("puddle_tex", bake_puddle_mask(seed))
	mat.set_shader_parameter("walk_albedo", Style.SIDEWALK)
	mat.set_shader_parameter("shop_color", Style.SHOP)
	mat.set_shader_parameter("sky_color", Style.FOG)
	mat.set_shader_parameter("fake_refl", fake_reflection_strength())
	var lights := static_lights()
	var out_pos := PackedColorArray()
	var out_col := PackedColorArray()
	out_pos.resize(MAX_LIGHTS)
	out_col.resize(MAX_LIGHTS)
	var score := PackedFloat32Array()
	score.resize(lights.pos.size())
	var used := PackedByteArray()
	used.resize(lights.pos.size())
	var start: Vector2i = maze.start_cell
	var from := Vector3(start.y * TokyoScenery.CELL, 1.0, start.x * TokyoScenery.CELL)
	var n := nearest(from, lights.pos, lights.col, lights.prio, lights.pos.size(), out_pos, out_col, score, used)
	mat.set_shader_parameter("light_pos", out_pos)
	mat.set_shader_parameter("light_col", out_col)
	mat.set_shader_parameter("light_n", n)


## Without SSR (Compatibility) the streaks carry the wet look alone; with
## SSR (Forward+) they only add the stretched glints SSR lacks.
static func fake_reflection_strength() -> float:
	return 0.45 if ssr_available() else 1.0


## The reflection layer for renderers without SSR (Compatibility): a
## plane just above the floor with tokyo_floor_reflect.gdshader; null when
## SSR is available (Forward+), which reflects the real scene instead.
static func build_reflection_layer(maze, seed: int, force: bool = false) -> MeshInstance3D:
	if ssr_available() and not force:
		return null
	var plane := PlaneMesh.new()
	plane.size = Vector2(maze.cols * TokyoScenery.CELL, maze.rows * TokyoScenery.CELL)
	var mat := ShaderMaterial.new()
	mat.shader = REFLECT_SHADER
	mat.set_shader_parameter("puddle_tex", bake_puddle_mask(seed))
	mat.set_shader_parameter("maze_size", Vector2(maze.cols, maze.rows))
	mat.set_shader_parameter("cell", TokyoScenery.CELL)
	var mi := MeshInstance3D.new()
	mi.name = "Bodenspiegelung"
	mi.mesh = plane
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# above the road paint (0.012 m), so the zebras mirror too
	mi.position = Vector3((maze.cols - 1) * TokyoScenery.CELL * 0.5, 0.016, (maze.rows - 1) * TokyoScenery.CELL * 0.5)
	return mi


## SSR exists only on the RenderingDevice renderers (Forward+); the
## Compatibility renderer (OpenGL, also the sandbox screenshots) has none.
static func ssr_available() -> bool:
	return RenderingServer.get_rendering_device() != null
