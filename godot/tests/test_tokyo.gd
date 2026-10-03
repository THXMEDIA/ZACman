extends SceneTree
## Headless test: the Tokyo Explorer city (docs/design/tokyo-explorer.md, M1)
## — street grid (tokyo_maze.gd), pellet trails, neon line city
## (tokyo_scenery.gd / neon_lines.gd), draw-call budget of the statics,
## collision exactly at the neon base line, determinism with the level seed,
## palette and readability rules, no brands. Run with
##   godot --headless --path . --script res://tests/test_tokyo.gd
## Exits with code 0 on success, 1 on any failure. (The theme reset Tokyo ->
## speedrun runs in the bot simulation, tests/bot_test.gd, against Main.)

const TokyoMaze := preload("res://scripts/tokyo_maze.gd")
const TokyoScenery := preload("res://scripts/tokyo_scenery.gd")
const Style := preload("res://scripts/tokyo_style.gd")
const CityThemes := preload("res://scripts/city_themes.gd")
const ExplorerCities := preload("res://scripts/explorer_cities.gd")

## Static draw calls Tokyo may cost (wall MultiMesh, floor, neon colors,
## mass, paint, shop fronts, screens, sign lettering). Pellets are dynamic
## and not part of it (they are counted separately below).
const STATIC_DRAW_BUDGET := 20
const LIGHT_BUDGET := 10 # 8 lamps + 2 screens (the subway light is Main's)
const LEVEL_SEED := 7310

var failures := 0
var checks := 0


func _check(name: String, cond: bool, detail := "") -> void:
	checks += 1
	if not cond:
		failures += 1
		print("FAIL ", name, (" -> " + detail) if detail != "" else "")


func _initialize() -> void:
	var mg = load("res://scripts/maze_gen.gd").new()
	var maze = TokyoMaze.new().generate()

	# ---- grid ----
	_check("grid: 47 x 47", maze.rows == 47 and maze.cols == 47, "%dx%d" % [maze.rows, maze.cols])
	var border_ok := true
	for i in maze.rows:
		if maze.grid[i][0] != 1 or maze.grid[i][maze.cols - 1] != 1:
			border_ok = false
	for j in maze.cols:
		if maze.grid[0][j] != 1 or maze.grid[maze.rows - 1][j] != 1:
			border_ok = false
	_check("grid: the border is closed (buildings all round, no tunnel)", border_ok)
	_check("grid: no ghost house inside the grid", maze.house.r0 < 0 and maze.house.r1 < 0)

	# every open cell lies in a declared street, every wall in a building
	var layout_ok := true
	var open_cells := []
	for r in maze.rows:
		for c in maze.cols:
			var cell := Vector2i(r, c)
			var in_street := false
			for st in TokyoMaze.STREETS:
				if TokyoMaze.in_rect(cell, st):
					in_street = true
			var b := TokyoMaze.building_at(r, c)
			if maze.grid[r][c] == 0:
				open_cells.append(cell)
				if not in_street or not b.is_empty():
					layout_ok = false
			elif b.is_empty() or in_street:
				layout_ok = false
	_check("grid: open cells = streets, walls = buildings (no overlaps, no gaps)", layout_ok)

	# ---- connected, subway reachable ----
	var start: Vector2i = maze.start_cell
	_check("start cell is open", maze.grid[start.x][start.y] == 0)
	var dist = mg.bfs_no_wrap(maze, start.x, start.y)
	var unreached := 0
	for cell in open_cells:
		if dist[cell.x][cell.y] < 0:
			unreached += 1
	_check("grid: every open cell is reachable from the start (connected)", unreached == 0, "%d unreachable of %d" % [unreached, open_cells.size()])
	var metro: Vector2i = TokyoMaze.METRO_CELL
	_check("subway exit cell is open", maze.grid[metro.x][metro.y] == 0)
	_check("subway exit is reachable from the start", dist[metro.x][metro.y] > 0, "dist %d" % dist[metro.x][metro.y])
	_check("subway exit lies in the station facade (station building right north of it)", TokyoMaze.building_at(metro.x - 1, metro.y).get("kind", "") == "station")
	_check("subway is the only metro cell", TokyoMaze.metro_cells() == [metro])

	# ---- open crossing field ----
	var cr: Dictionary = TokyoMaze.CROSSING
	var field_open := true
	for r in range(cr.r0, cr.r1 + 1):
		for c in range(cr.c0, cr.c1 + 1):
			if maze.grid[r][c] != 0:
				field_open = false
	var fw: int = cr.c1 - cr.c0 + 1
	var fh: int = cr.r1 - cr.r0 + 1
	_check("crossing field is one open area of at least 3 x 3 cells", field_open and fw >= 3 and fh >= 3, "%dx%d open=%s" % [fw, fh, field_open])
	# The crossing is a real square, not a corridor: from its center the
	# player can walk 3 cells in every direction without a wall.
	var cc := Vector2i((cr.r0 + cr.r1) / 2, (cr.c0 + cr.c1) / 2)
	var square_ok := true
	for dr in range(-3, 4):
		for dc in range(-3, 4):
			if maze.grid[cc.x + dr][cc.y + dc] != 0:
				square_ok = false
	_check("crossing: 7 x 7 free around its center", square_ok)

	# ---- pellet trails lead to the subway ----
	var trails: Array = TokyoMaze.trail_cells(maze, [metro], start, LEVEL_SEED)
	_check("trails: there are pellets", trails.size() > 40, "%d" % trails.size())
	var mdist = mg.bfs_no_wrap(maze, metro.x, metro.y)
	var trail_set := {}
	for t in trails:
		trail_set[t] = true
	var chain_ok := true
	var all_open := true
	for t in trails:
		if maze.grid[t.x][t.y] != 0:
			all_open = false
		# each trail cell has a 4-neighbour on the trail (or the subway) that is
		# strictly closer to the subway: following the gold always ends there
		var ok := false
		for d in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
			var n: Vector2i = t + d
			if (trail_set.has(n) or n == metro) and mdist[n.x][n.y] >= 0 and mdist[n.x][n.y] < mdist[t.x][t.y]:
				ok = true
		if not ok:
			chain_ok = false
	_check("trails: every pellet lies on an open cell", all_open)
	_check("trails: every pellet has a next pellet closer to the subway (unbroken lines ending at the subway)", chain_ok)
	var touches_metro := false
	for d in [Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
		if trail_set.has(metro + d):
			touches_metro = true
	_check("trails: the gold reaches the subway exit", touches_metro)
	var start_next := false
	for d in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
		if trail_set.has(start + d):
			start_next = true
	_check("trails: a trail starts right at the player's start", start_next)

	# ---- built level (MazeView) ----
	var mv := _build_view(maze, LEVEL_SEED)
	_check("view: pellets follow the trails (minus start and subway)", mv.pellet_cells.size() > 40 and not (start in mv.pellet_cells) and not (metro in mv.pellet_cells))
	var pellets_on_trail := true
	for p in mv.pellet_cells:
		if not trail_set.has(p):
			pellets_on_trail = false
	_check("view: every pellet is a trail cell", pellets_on_trail)
	_check("view: no power pellets, no rabbit (calm explorer)", mv.power_cells.size() == 0 and mv.rabbit_node == null)
	_check("view: Tokyo scenery built", mv.scenery_root != null and mv.scenery_root.get_meta("line_segments", 0) > 500, str(mv.scenery_root.get_meta("line_segments", 0) if mv.scenery_root != null else -1))

	# ---- draw-call budget of the statics ----
	var pellet_nodes := {}
	for m in mv.pellet_meshes:
		pellet_nodes[m] = true
	var geo := []
	var lights := []
	_collect(mv, geo, lights, pellet_nodes)
	_check("budget: static geometry <= %d draw calls" % STATIC_DRAW_BUDGET, geo.size() <= STATIC_DRAW_BUDGET, "%d: %s" % [geo.size(), ", ".join(geo.map(func(g): return String(g.name)))])
	var surfaces := 0
	for g in geo:
		if g is MeshInstance3D and g.mesh != null:
			surfaces += g.mesh.get_surface_count()
		else:
			surfaces += 1
	_check("budget: one surface per static mesh (merged per color)", surfaces == geo.size(), "%d surfaces for %d nodes" % [surfaces, geo.size()])
	var neon := 0
	for g in geo:
		if String(g.name).begins_with("Neon_"):
			neon += 1
	_check("budget: all neon lines in at most 4 color meshes", neon > 0 and neon <= 4, "%d" % neon)
	_check("budget: all building masses in one wall MultiMesh", mv.normal_wall_mmi != null and mv.normal_wall_mmi.multimesh.instance_count == _count_walls(maze))
	_check("budget: at most %d scenery lights (lamp light pools <= 8)" % LIGHT_BUDGET, lights.size() <= LIGHT_BUDGET, "%d" % lights.size())

	# ---- collision exactly at the base line ----
	var fp: float = mv.city_theme.wall_footprint_scale
	_check("collision: building cells are whole (footprint 1.0)", is_equal_approx(fp, 1.0))
	var boxes := {}
	for cs in mv.walls_body.get_children():
		var cell := Vector2i(int(round(cs.position.z / 2.0)), int(round(cs.position.x / 2.0)))
		boxes[cell] = cs
	var base_lines: Array = mv.scenery_root.get_meta("base_lines", [])
	var runs: Array = mv.scenery_root.get_meta("facade_runs", [])
	_check("collision: a base line for every facade run", base_lines.size() == runs.size() and runs.size() > 20, "%d lines, %d runs" % [base_lines.size(), runs.size()])
	var bad := 0
	var detail := ""
	for bl in base_lines:
		var n: Vector3 = bl.n
		var a: Vector3 = bl.a
		var b2: Vector3 = bl.b
		var inner: Vector3 = a - n * (float(bl.thick) * 0.5) # inner side of the tube
		_check_height(bl)
		# sample the run every cell: wall behind, open in front, box face == inner side
		var steps := int(round(a.distance_to(b2) / 2.0))
		for k in steps:
			var p := a.lerp(b2, (k + 0.5) / float(steps))
			var wall_cell := Vector2i(int(round((p.z - n.z) / 2.0)), int(round((p.x - n.x) / 2.0)))
			var open_cell := Vector2i(int(round((p.z + n.z) / 2.0)), int(round((p.x + n.x) / 2.0)))
			if not boxes.has(wall_cell) or maze.grid[open_cell.x][open_cell.y] != 0:
				bad += 1
				detail = "run at %s: wall %s open %s" % [p, wall_cell, open_cell]
				continue
			var cs: CollisionShape3D = boxes[wall_cell]
			var half: Vector3 = cs.shape.size * 0.5
			var face := cs.position + Vector3(n.x * half.x, 0, n.z * half.z)
			var d: float = (inner - face).dot(n)
			if absf(d) > 0.001:
				bad += 1
				detail = "face %s inner %s (d=%.4f)" % [face, inner, d]
	_check("collision: every base line's inner side lies exactly on the collision face", bad == 0, detail)
	# and every open/wall boundary has a base line: collision faces towards
	# the street count == base line coverage
	var boundary_len := 0.0
	for r in maze.rows:
		for c in maze.cols:
			if maze.grid[r][c] != 1:
				continue
			for d2 in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
				var o: Vector2i = Vector2i(r, c) + d2
				if o.x >= 0 and o.x < maze.rows and o.y >= 0 and o.y < maze.cols and maze.grid[o.x][o.y] == 0:
					boundary_len += 2.0
	var line_len := 0.0
	for bl in base_lines:
		line_len += (bl.a as Vector3).distance_to(bl.b)
	_check("collision: the base line covers the whole street-facing collision edge", is_equal_approx(boundary_len, line_len), "edge %.1f m, line %.1f m" % [boundary_len, line_len])

	# ---- determinism with the level seed ----
	var maze2 = TokyoMaze.new().generate()
	_check("determinism: the grid is identical on every generate()", maze2.grid == maze.grid)
	var mv_same := _build_view(maze2, LEVEL_SEED)
	_check("determinism: same seed -> identical neon city", mv_same.scenery_root.get_meta("line_signature") == mv.scenery_root.get_meta("line_signature"))
	_check("determinism: same seed -> identical decoration (mass, paint, shop fronts)", mv_same.scenery_root.get_meta("decor_signature") == mv.scenery_root.get_meta("decor_signature"))
	_check("determinism: same seed -> identical pellets", mv_same.pellet_cells == mv.pellet_cells)
	var mv_other := _build_view(TokyoMaze.new().generate(), LEVEL_SEED + 1)
	_check("determinism: another level seed -> other decoration", mv_other.scenery_root.get_meta("decor_signature") != mv.scenery_root.get_meta("decor_signature"))
	var other_runs: Array = mv_other.scenery_root.get_meta("facade_runs")
	_check("determinism: another level seed -> same collision outline", other_runs.size() == runs.size())
	var differs := false
	for s in range(1, 40):
		if TokyoMaze.trail_cells(maze, [metro], start, LEVEL_SEED + s) != trails:
			differs = true
	_check("determinism: the level seed chooses the trails", differs)
	_check("determinism: Tokyo's level seed comes from the city registry", int(ExplorerCities.get_city("tokyo").seed) == LEVEL_SEED)

	# ---- palette and readability rules ----
	var theme = CityThemes.get_theme("tokyo")
	_check("theme: registered as an explorer city", CityThemes.EXPLORER_IDS.has("tokyo") and ExplorerCities.has_city("tokyo"))
	_check("theme: glow and SSR on, volumetric fog off", theme.env_glow_enabled and theme.env_ssr_enabled and not theme.env_volumetric_fog_enabled)
	_check("theme: no ghosts' power-ups, pellets follow trails", not theme.has_power_ups and theme.pellets_follow_metro_trails)
	var keys: Array = []
	for g in geo:
		if String(g.name).begins_with("Neon_"):
			keys.append(String(g.name).substr(5))
	var allowed_keys := ["amber", "weiss", "magenta", "mast"]
	var keys_ok := true
	for k in keys:
		if not allowed_keys.has(k):
			keys_ok = false
	_check("palette: building lines only amber / white / magenta accent (+ dim brackets)", keys_ok, str(keys))
	var world := [Style.AMBER, Style.WHITE, Style.MAGENTA, Style.LAMP, Style.SHOP, Style.POLE, Style.PAINT]
	for c in world:
		var h: float = c.h * 360.0
		_check("palette: no violet/cyan/blue in the world (%s)" % c.to_html(false), c.s < 0.15 or not (h > 170.0 and h < 300.0), "hue %.0f" % h)
		_check("palette: world color %s is not green (green = subway only)" % c.to_html(false), c.s < 0.15 or not (h > 80.0 and h < 170.0), "hue %.0f" % h)
		_check("palette: world color %s is far from the pellet gold" % c.to_html(false), _dist(c, Style.PELLET) > 0.12 or c == Style.WHITE and _dist(c, Style.PELLET) > 0.08)
	_check("palette: pellets warm white-gold", theme.pellet_emission == Style.PELLET and theme.pellet_color == Style.PELLET_CORE)
	_check("palette: the subway green is a pure, saturated green", Style.METRO.g > 0.9 and Style.METRO.s > 0.7 and absf(Style.METRO.h * 360.0 - 135.0) < 15.0)
	var magenta_lines: int = 0
	for g in geo:
		if String(g.name) == "Neon_magenta":
			magenta_lines += 1
	var screens := 0
	for g in geo:
		if String(g.name) == "Screen":
			screens += 1
	_check("readability: at most two magenta screens", screens <= 2, "%d" % screens)
	_check("readability: top brightness falls to ~30 %", is_equal_approx(Style.TOP_MUL, 0.3))
	_check("readability: base line at 2.3 m", is_equal_approx(Style.BASE_LINE_Y, 2.3))

	# ---- legal: no brands, no landmark replicas ----
	var forbidden := ["109", "QFRONT", "TSUTAYA", "STARBUCKS", "HACHI", "ハチ公", "MAGNET", "SHIBUYA SKY", "SCRAMBLE SQUARE", "TRON"]
	var texts := []
	_collect_texts(mv, texts)
	var ids := []
	for b in TokyoMaze.BUILDINGS:
		ids.append(String(b.id).to_upper())
	var legal_ok := true
	for t in texts + ids:
		for f in forbidden:
			if String(t).to_upper().find(f) >= 0:
				legal_ok = false
				print("  brand/landmark word: ", t)
	_check("legal: no brand or landmark names on signs or buildings", legal_ok)
	var generic := ["居酒屋", "本屋", "ラーメン", "薬", "喫茶", "カラオケ"]
	var sign_ok := true
	for t in texts:
		if not generic.has(String(t).replace("\n", "")):
			sign_ok = false
			print("  unexpected sign text: ", t)
	_check("legal: signs only carry generic words", sign_ok and texts.size() >= 5)

	if failures == 0:
		print("ALL %d TOKYO CHECKS PASSED" % checks)
	else:
		print("%d OF %d TOKYO CHECKS FAILED" % [failures, checks])
	quit(1 if failures > 0 else 0)


func _check_height(bl: Dictionary) -> void:
	if absf((bl.a as Vector3).y - Style.BASE_LINE_Y) > 0.0001:
		_check("base line at %.2f m" % Style.BASE_LINE_Y, false, str(bl.a))


func _build_view(maze, seed: int) -> Node3D:
	var mv = load("res://scripts/maze_view.gd").new()
	root.add_child(mv)
	mv.build(maze, maze.start_cell, "tokyo", TokyoMaze.metro_cells(), TokyoMaze.metro_cells(), -1, "", seed)
	return mv


func _count_walls(maze) -> int:
	var n := 0
	for r in maze.rows:
		for c in maze.cols:
			if maze.grid[r][c] == 1:
				n += 1
	return n


func _collect(node: Node, geo: Array, lights: Array, skip: Dictionary) -> void:
	for ch in node.get_children():
		if ch.is_queued_for_deletion():
			continue
		if skip.has(ch):
			continue
		if ch is GeometryInstance3D and ch.visible:
			geo.append(ch)
		elif ch is Light3D:
			lights.append(ch)
		_collect(ch, geo, lights, skip)


func _collect_texts(node: Node, out: Array) -> void:
	for ch in node.get_children():
		if ch is Label3D:
			out.append(ch.text)
		_collect_texts(ch, out)


## Rough perceptual distance (OKLab-ish via linear RGB) between two colors.
func _dist(a: Color, b: Color) -> float:
	var la := _oklab(a)
	var lb := _oklab(b)
	return la.distance_to(lb)


func _oklab(c: Color) -> Vector3:
	var l := c.srgb_to_linear()
	var L := 0.4122214708 * l.r + 0.5363325363 * l.g + 0.0514459929 * l.b
	var M := 0.2119034982 * l.r + 0.6806995451 * l.g + 0.1073969566 * l.b
	var S := 0.0883024619 * l.r + 0.2817188376 * l.g + 0.6299787005 * l.b
	L = pow(L, 1.0 / 3.0)
	M = pow(M, 1.0 / 3.0)
	S = pow(S, 1.0 / 3.0)
	return Vector3(0.2104542553 * L + 0.7936177850 * M - 0.0040720468 * S,
		1.9779984951 * L - 2.4285922050 * M + 0.4505937099 * S,
		0.0259040371 * L + 0.7827717662 * M - 0.8086757660 * S)
