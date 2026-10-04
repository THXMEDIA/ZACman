extends SceneTree
## Headless test: the Arles Explorer city (docs/design/arles-explorer.md) —
## grid from the art director's map (arles_maze.gd), the way past the
## landmarks to the green door, deterministic pellet trails with the must
## branches, the painted city (arles_scenery.gd): every street ends on a
## landmark, what reaches into the street has collision, draw-call / light /
## vertex budget, baked sky, stroke LOD, light-pool tile list, comfort
## switches, exclusive colours (vermilion only the pellets, mint green only the
## exit, halo rims gold), registry, minimap, exit.
## Run with
##   godot --headless --path . --script res://tests/test_arles.gd

const M := preload("res://scripts/arles_maze.gd")
const Scenery := preload("res://scripts/arles_scenery.gd")
const Style := preload("res://scripts/arles_style.gd")
const CityThemes := preload("res://scripts/city_themes.gd")
const ExplorerCities := preload("res://scripts/explorer_cities.gd")

const LEVEL_SEED := 1888
## Static draw calls (visible geometry without the pellets): floor, houses,
## objects, arcades, tympanum, Rhône, sky, halos. The wall MultiMesh is physics
## only (not drawn).
const STATIC_DRAW_BUDGET := 9
const OBJECT_VERT_BUDGET := 60000
const HOUSE_VERT_BUDGET := 40000
const OMNI_BUDGET := 8 # technical condition: at most 7-8 real omni lights, none with shadows
const EYE := 1.9

var failures := 0
var checks := 0


func _check(name: String, cond: bool, detail := "") -> void:
	checks += 1
	if not cond:
		failures += 1
		print("FAIL ", name, (" -> " + detail) if detail != "" else "")


func _initialize() -> void:
	var maze = M.new().generate()
	var start: Vector2i = maze.start_cell
	var exit_cell: Vector2i = M.METRO_CELL

	# ---- grid ----
	_check("grid: 41 x 45 (art director's map)", maze.rows == 41 and maze.cols == 45)
	var border_closed := true
	for r in maze.rows:
		for c in maze.cols:
			if (r == 0 or c == 0 or r == maze.rows - 1 or c == maze.cols - 1) and maze.grid[r][c] != 1:
				border_closed = false
	_check("grid: closed border", border_closed)
	_check("grid: start and exit are open street cells", maze.grid[start.x][start.y] == 0 and maze.grid[exit_cell.x][exit_cell.y] == 0)
	_check("grid: the exit cell lies in front of the Yellow House", M.landmark_block_at(exit_cell.x - 1, exit_cell.y).get("id", "") == "maison_jaune")
	var reach := _reachable(maze, start)
	var open_n := 0
	for r in maze.rows:
		for c in maze.cols:
			if maze.grid[r][c] == 0:
				open_n += 1
	_check("grid: all 790 street cells, every one reachable", open_n == 790 and reach.size() == open_n, "%d of %d" % [reach.size(), open_n])
	_check("grid: no ghost house, no tunnel", maze.door_col == -1 and maze.tunnel_row == -1)
	var par_ok := true
	for r in range(M.PARAPET_R0, M.PARAPET_R1 + 1):
		if maze.grid[r][0] != 1 or maze.grid[r][1] != 0:
			par_ok = false
	_check("grid: the quay runs along the parapet (closed) the whole way", par_ok)
	_check("grid: the passage of the Porte de la Cavalerie is open, its towers are not", maze.grid[4][20] == 0 and maze.grid[1][20] == 1 and maze.grid[7][20] == 1)
	_check("grid: start at the east end of the Calade, longest view west", _longest_dir(maze, start) == Vector2i(0, -1))

	# ---- every street ends on a landmark (or the Rhône) ----
	var ends := {
		"rue_calade west": [Vector2i(35, 21), Vector2i(0, -1), "hotel_de_ville"],
		"rue_calade east": [Vector2i(35, 33), Vector2i(0, 1), "theatre_antique"],
		"rue_hotel_de_ville north": [Vector2i(26, 13), Vector2i(-1, 0), "cafe"],
		"rue_hotel_de_ville south": [Vector2i(31, 13), Vector2i(1, 0), "saint_trophime"],
		"rue_forum east": [Vector2i(20, 23), Vector2i(0, 1), "arenes"],
		"rue_forum west (Rhône)": [Vector2i(20, 5), Vector2i(0, -1), "parapet"],
		"lane to the baths": [Vector2i(9, 15), Vector2i(0, 1), "thermes"],
		"quay south": [Vector2i(34, 3), Vector2i(1, 0), "grand_prieure"],
		"rue_cavalerie north": [Vector2i(1, 25), Vector2i(-1, 0), "remparts"],
		"place_lamartine north (exit)": [exit_cell, Vector2i(-1, 0), "maison_jaune"],
	}
	for k in ends:
		var e: Array = ends[k]
		var hit := _ray(maze, e[0], e[1])
		_check("view: %s ends on %s" % [k, e[2]], hit == e[2], hit)

	# ---- the way along the pellets ----
	var route: Array = M.route(maze)
	_check("route: start -> exit along the trails", route.size() > 1 and route[0] == start and route[route.size() - 1] == exit_cell)
	var steps := route.size() - 1
	var shortest := _shortest(maze, start, exit_cell).size()
	_check("route: about 67 cells (134 m, ~30 s), barely longer than the shortest way", steps >= 62 and steps <= 72 and steps - shortest <= 4, "%d steps, shortest %d" % [steps, shortest])
	var streets_seen: Array = []
	for cell in route:
		var s := M.street_at(cell.x, cell.y)
		if not s.is_empty() and not streets_seen.has(s.id):
			streets_seen.append(s.id)
	var in_order := true
	var last := -1
	for sid in M.ROUTE:
		var i := streets_seen.find(sid)
		if i < 0 or i < last:
			in_order = false
		last = maxi(last, i)
	_check("route: Calade > République > Rue de l'Hôtel de Ville > Forum > Rue du Forum > quay > Lamartine", in_order, str(streets_seen))
	var lm_seen := {}
	for sid in streets_seen:
		var s := _street(sid)
		for r in range(s.r0 - 1, s.r1 + 2):
			for c in range(s.c0 - 1, s.c1 + 2):
				var lm := M.landmark_block_at(r, c)
				if not lm.is_empty() and M.cell_kind(r, c) == "landmark":
					lm_seen[lm.id] = true
	var wanted := ["theatre_antique", "hotel_de_ville", "saint_trophime", "cafe", "colonnes_forum", "grand_prieure", "porte_cavalerie", "maison_jaune"]
	var missing := wanted.filter(func(w): return not lm_seen.has(w))
	_check("route: passes theatre, Hôtel de Ville, Saint-Trophime, café, columns, Grand Prieuré, Porte, Yellow House", missing.is_empty(), str(missing))
	var quay_cells := route.filter(func(c): return c.y >= 1 and c.y <= 4 and c.x >= 4)
	_check("route: more than 30 m along the parapet with the mirrored lamps", quay_cells.size() >= 16, "%d cells" % quay_cells.size())

	# ---- pellet trails ----
	var t1: Array = M.trail_cells(maze, M.metro_cells(), start, LEVEL_SEED)
	var t2: Array = M.trail_cells(maze, M.metro_cells(), start, LEVEL_SEED)
	_check("trails: deterministic per seed", t1 == t2)
	var net := M.trail_network()
	var on_open := true
	for c in t1:
		if maze.grid[c.x][c.y] != 0 or not net.has(c):
			on_open = false
	_check("trails: only on street centre lines", on_open)
	var route_on := true
	for c in route:
		if c != exit_cell and not t1.has(c):
			route_on = false
	_check("trails: the whole way to the exit carries pellets", route_on)
	var ring_ok := true
	for c in range(25, 43):
		if not t1.has(Vector2i(13, c)) or not t1.has(Vector2i(31, c)):
			ring_ok = false
	for r in range(13, 32):
		if not t1.has(Vector2i(r, 42)):
			ring_ok = false
	_check("trails: the arena ring is complete (must branch)", ring_ok)
	_check("trails: the lane to the baths (must branch)", t1.has(Vector2i(9, 15)) and t1.has(Vector2i(9, 4)))
	var other_seed: Array = M.trail_cells(maze, M.metro_cells(), start, 7)
	_check("trails: the seed picks the other branches", other_seed.size() > 100 and t1.size() > 150, "%d / %d" % [t1.size(), other_seed.size()])

	# ---- view / budget ----
	var mv = load("res://scripts/maze_view.gd").new()
	root.add_child(mv)
	mv.build(maze, start, "arles", M.metro_cells(), M.metro_cells(), -1, "", LEVEL_SEED)
	var sr = mv.scenery_root
	_check("view: the painted city is built", sr != null and sr.get_node_or_null("City/Houses") != null and sr.get_node_or_null("City/Objects") != null)
	_check("view: pellets follow the trails", mv.pellet_cells.size() > 150 and not (exit_cell in mv.pellet_cells))
	_check("view: no power pellets, no rabbit (calm explorer)", mv.power_cells.size() == 0 and mv.rabbit_node == null)
	_check("view: the wall boxes are physics only (not drawn)", mv.normal_wall_mmi != null and mv.normal_wall_mmi.visible == false)
	var geo := []
	_collect(mv, geo, {mv.pellet_mmi: true})
	_check("budget: static geometry <= %d draw calls" % STATIC_DRAW_BUDGET, geo.size() <= STATIC_DRAW_BUDGET, "%d: %s" % [geo.size(), ", ".join(geo.map(func(g): return String(g.name)))])
	var ov: int = sr.get_node("City/Objects").mesh.surface_get_array_len(0)
	var hv: int = sr.get_node("City/Houses").mesh.surface_get_array_len(0)
	_check("budget: objects <= %d vertices, houses <= %d" % [OBJECT_VERT_BUDGET, HOUSE_VERT_BUDGET], ov <= OBJECT_VERT_BUDGET and hv <= HOUSE_VERT_BUDGET, "%d / %d" % [ov, hv])
	var halos = sr.get_node_or_null("City/Halos")
	var types := {}
	for h in Scenery.halos(LEVEL_SEED):
		types[int(h[5])] = true
	_check("budget: every lamp, star and the moon in ONE halo MultiMesh", halos is MultiMeshInstance3D and halos.multimesh.instance_count == sr.halo_count and sr.halo_count >= 70 and types.has(0) and types.has(1) and types.has(2))
	var lights := []
	_collect_lights(mv, lights)
	var omnis := lights.filter(func(l): return l is OmniLight3D)
	var dirs := lights.filter(func(l): return l is DirectionalLight3D)
	var shadowed := lights.filter(func(l): return l.shadow_enabled)
	_check("light: 6 omni lights in the city (+1 at the exit <= %d), the moon, no shadows" % OMNI_BUDGET, omnis.size() == 6 and omnis.size() + 1 <= OMNI_BUDGET and dirs.size() == 1 and shadowed.is_empty(), "%d omni, %d dir, %d shadowed" % [omnis.size(), dirs.size(), shadowed.size()])
	var texts := []
	_collect_texts(mv, texts)
	_check("text: no lettering in the city (no names, no signs)", texts.is_empty(), str(texts))

	# ---- collision ----
	var hs := []
	for cs in mv.walls_body.get_children():
		hs.append(cs.shape.size.y)
	_check("collision: every wall box %.1f m, above the camera" % M.WALL_H, hs.min() == hs.max() and is_equal_approx(hs.min(), M.WALL_H) and hs.min() > EYE, "%s..%s" % [hs.min(), hs.max()])
	var ob = sr.get_node_or_null("City/Obstacles")
	_check("collision: obstacles on the wall layer, above eye height", ob is StaticBody3D and ob.collision_layer == 2 and ob.get_child_count() == sr.obstacle_boxes.size() and ob.get_children().all(func(cs): return cs.shape.size.y > EYE))
	var uncovered := ""
	for p in sr.object_parts:
		var bb: AABB = p.aabb
		if bb.position.y > EYE or bb.end.y < 0.05:
			continue
		if not Scenery.intrudes(Vector2(bb.position.x, bb.position.z), Vector2(bb.end.x, bb.end.z)):
			continue
		var covered := false
		for o in sr.obstacle_boxes:
			if o.aabb.grow(0.01).encloses(AABB(Vector3(bb.position.x, 0.0, bb.position.z), Vector3(bb.size.x, 0.1, bb.size.z))):
				covered = true
		if not covered:
			uncovered += "%s %s; " % [p.mat, bb]
	_check("collision: everything that reaches into a street below eye height is an obstacle", uncovered == "", uncovered)
	var blocked := ""
	for i in range(route.size() - 1):
		var a: Vector2i = route[i]
		var b: Vector2i = route[i + 1]
		var pa := Vector2(a.y * 2.0 + 1.0, a.x * 2.0 + 1.0)
		var pb := Vector2(b.y * 2.0 + 1.0, b.x * 2.0 + 1.0)
		for o in sr.obstacle_boxes:
			var r2 := Rect2(Vector2(o.aabb.position.x, o.aabb.position.z), Vector2(o.aabb.size.x, o.aabb.size.z)).grow(0.5)
			for k in 5:
				if r2.has_point(pa.lerp(pb, k / 4.0)):
					blocked += "%s at %s; " % [o.name, a]
					break
	_check("collision: no obstacle within 0.5 m of the way along the pellets", blocked == "", blocked)
	var on_pellet := ""
	for c in mv.pellet_cells:
		var pc := Vector2(c.y * 2.0 + 1.0, c.x * 2.0 + 1.0)
		for o in sr.obstacle_boxes:
			if Rect2(Vector2(o.aabb.position.x, o.aabb.position.z), Vector2(o.aabb.size.x, o.aabb.size.z)).grow(0.45).has_point(pc):
				on_pellet += "%s %s; " % [o.name, c]
	_check("collision: every pellet stays reachable (no obstacle on it)", on_pellet == "", on_pellet)
	# landmark faces at the street: something solid stands on every landmark
	# cell next to a street (the edge you bump into is visible)
	var bare := ""
	var house_boxes: Array = Scenery.houses(LEVEL_SEED).boxes
	for r in maze.rows:
		for c in maze.cols:
			if M.cell_kind(r, c) != "landmark" or M.landmark_block_at(r, c).id == "maison_jaune":
				continue
			var at_street := false
			for d in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
				if M.is_open(r + d.x, c + d.y):
					at_street = true
			if not at_street:
				continue
			var cell := Rect2(c * 2.0, r * 2.0, 2.0, 2.0)
			var solid := false
			for p in sr.object_parts:
				var bb: AABB = p.aabb
				if bb.end.y > 0.5 and bb.position.y < 0.3 and Rect2(Vector2(bb.position.x, bb.position.z), Vector2(bb.size.x, bb.size.z)).intersects(cell):
					solid = true
					break
			if not solid:
				for hb in house_boxes:
					if Rect2(Vector2(hb.position.x, hb.position.z), Vector2(hb.size.x, hb.size.z)).intersects(cell):
						solid = true
						break
			if not solid:
				bare += "%s(%d,%d) " % [M.landmark_block_at(r, c).id, r, c]
	_check("collision: every landmark cell at a street carries its building", bare == "", bare)

	# ---- look: sky, LOD, pools, floor ----
	_check("sky: baked once at level start (2048 x 1024, update once)", sr.bake_viewport != null and sr.bake_viewport.size == Vector2i(2048, 1024) and sr.bake_viewport.render_target_update_mode == SubViewport.UPDATE_ONCE)
	_check("sky: the sky material reads the baked texture", sr.sky_material.get_shader_parameter("baked") is Texture2D and sr.sky_state != "")
	var sky_code: String = sr.sky_material.shader.code
	_check("sky: run time without noise or loops (3 texture reads)", not sky_code.contains("for (") and not sky_code.contains("vnoise") and sky_code.count("texture(") == 3)
	var bake_code: String = sr.bake_material.shader.code
	_check("sky: seamless all around (periodic swirl field and noise in x)", bake_code.contains("r.x -= W * round(r.x / W)") and bake_code.contains("mod(i.x, per)"))
	_check("sky: drift 0.04 phase/s (far below 0.5 Hz)", is_equal_approx(_f(sr.sky_material.get_shader_parameter("speed"), 0.0), 0.04) and Style.SKY_DRIFT <= 0.04)
	var lod_ok := true
	for m in sr.brush_materials:
		if m.shader.code.contains("stroke_lod") or m.shader.code.contains("arles_common"):
			if not is_equal_approx(_f(m.get_shader_parameter("lod_near"), 0.0), 14.0) or not is_equal_approx(_f(m.get_shader_parameter("lod_far"), 0.0), 28.0):
				lod_ok = false
	var common := FileAccess.get_file_as_string("res://shaders/arles_common.gdshaderinc")
	_check("LOD: stroke LOD 14-28 m and below ~3 px, far strokes become soft dabs", lod_ok and common.contains("smoothstep(lod_near, lod_far, dist)") and common.contains("smoothstep(0.30, 0.75, pix)") and common.contains("vec3 far = mean"))
	var floor_mat: ShaderMaterial = mv.floor_mesh.material_override
	_check("LOD: walls, objects, arcades, floor and water use it", sr.brush_materials.size() >= 4 and floor_mat.shader.resource_path.ends_with("arles_floor.gdshader") and is_equal_approx(_f(floor_mat.get_shader_parameter("lod_near"), 0.0), 14.0))
	var tex: Array = Scenery.pool_textures()
	var lamps := Scenery.pool_lamps()
	var used := {}
	for tz in Scenery.TILE_COUNT.y:
		for tx in Scenery.TILE_COUNT.x:
			for i in Scenery.tile_lamps(tx, tz, lamps):
				used[i] = true
	_check("pools: light pools from a tile list, at most 8 lamps per tile", Scenery._tile_max <= 8 and Scenery._tile_max >= 4 and tex[1].get_width() == Scenery.TILE_COUNT.x * 2 and common.contains("k < 2"), "max %d" % Scenery._tile_max)
	_check("pools: every gas lamp paints its pool (%d lamps)" % lamps.size(), used.size() == lamps.size() and lamps.size() >= 40)
	var fl := FileAccess.get_file_as_string("res://shaders/arles_floor.gdshader")
	_check("floor: calm paving, gutter exactly on the block edge", fl.contains("calm_floor") and fl.contains("if (dmin < 0.26) c = gutter;") and _f(floor_mat.get_shader_parameter("calm_floor"), 0.45) >= 0.4)
	_check("halos: fade out right in front of the camera (no full-screen flash), unfogged", FileAccess.get_file_as_string("res://shaders/arles_halo.gdshader").contains("smoothstep(2.5, 7.0, d)") and FileAccess.get_file_as_string("res://shaders/arles_halo.gdshader").contains("fog_disabled"))

	# ---- comfort ----
	_check("comfort: sky and Rhône move without reduced effects", sr.animated_nodes().size() == 2 and _f(sr.sky_material.get_shader_parameter("moving"), 1.0) != 0.0)
	sr.set_reduce_fx(true)
	var calm_ok: bool = sr.brush_materials.all(func(m): return _f(m.get_shader_parameter("calm"), 0.0) == 1.0)
	_check("comfort: 'Effekte reduzieren' stops sky and Rhône, calms the brush", sr.fx_reduced() and _f(sr.sky_material.get_shader_parameter("moving"), 1.0) == 0.0 and _f(sr.water_material.get_shader_parameter("shimmer"), 1.0) == 0.0 and calm_ok and _f(floor_mat.get_shader_parameter("calm"), 0.0) == 1.0 and sr.animated_nodes().is_empty())
	sr.set_reduce_fx(false)
	_check("comfort: and back", _f(sr.sky_material.get_shader_parameter("moving"), 1.0) == 1.0)

	# ---- theme / registry ----
	var th = CityThemes.get_theme("arles")
	_check("theme: registered", th.id == "arles" and ExplorerCities.has_city("arles") and ExplorerCities.EXPLORER_IDS.has("arles") and CityThemes.EXPLORER_IDS.has("arles"))
	_check("theme: night, glow for lamps and pellets, no SSR/SSAO", th.env_glow_enabled and not th.env_ssr_enabled and not th.env_ssao_enabled and th.env_sky_script == null)
	_check("theme: the camera reaches the sky sphere", th.camera_far > Scenery.SKY_RADIUS + 100.0)
	_check("theme: vermilion pellets with contour (own shader)", th.pellet_shader_path.ends_with("arles_orb.gdshader") and th.pellet_color == Style.PELLET and FileAccess.get_file_as_string(th.pellet_shader_path).contains("outline"))
	var city: Dictionary = ExplorerCities.get_city("arles")
	_check("registry: label ARLES, exit script, no traffic, quiet, own texts", city.label == "ARLES" and city.metro_script.ends_with("arles_exit.gd") and city.traffic == "" and city.siren == false and city.exit_text != "" and city.exit_title != "" and city.exit_hint != "" and city.intro_hint != "" and city.metro_radius > 0.9 and city.seed == LEVEL_SEED)
	var all_text: String = city.label + city.exit_text + city.exit_title + city.exit_hint + city.intro_hint + th.display_name
	_check("registry: 'Van Gogh' never as a title or name", not all_text.to_lower().contains("gogh"))
	_check("minimap: exit marker mint green, pellets with a dark ring, the quay as water", th.minimap_exit_color == Style.EXIT and th.minimap_pellet_outline.a > 0.0 and th.minimap_water_script != null and M.is_water(10, 0) and not M.is_water(10, 1))
	var bg: Color = th.minimap_bg_color
	_check("minimap: pellets, blocks and exit stand out from the dark streets (>= 3:1)", _contrast(th.pellet_color, bg) >= 3.0 and _contrast(th.minimap_wall_color, bg) >= 3.0 and _contrast(Style.EXIT, bg) >= 3.0, "pellets %.1f, blocks %.1f, exit %.1f" % [_contrast(th.pellet_color, bg), _contrast(th.minimap_wall_color, bg), _contrast(Style.EXIT, bg)])
	_check("minimap: the quay differs from streets and blocks", _dist(th.minimap_water_color, bg) > 0.08 and _dist(th.minimap_water_color, th.minimap_wall_color) > 0.12)

	# ---- palette: vermilion only the pellets, mint only the exit, gold rims ----
	_check("palette: pellets #FF4A1C, exit #3AF5C8", Style.PELLET.to_html(false) == "ff4a1c" and Style.EXIT.to_html(false) == "3af5c8")
	var near_p := ""
	var near_e := ""
	for col in Style.world_colors():
		if _dist(col, Style.PELLET) < 0.15 or (col.s > 0.6 and col.v > 0.7 and (col.h * 360.0 < 25.0 or col.h * 360.0 > 345.0)):
			near_p += col.to_html(false) + " "
		if _dist(col, Style.EXIT) < 0.15 or (col.s > 0.4 and col.v > 0.5 and col.h * 360.0 > 140.0 and col.h * 360.0 < 185.0):
			near_e += col.to_html(false) + " "
	_check("palette: no world colour near the vermilion (no other red-orange)", near_p == "", near_p)
	_check("palette: no world colour near the mint green", near_e == "", near_e)
	for c in [Style.HALO_RIM, Style.REFL_RIM]:
		var hue: float = c.h * 360.0
		_check("palette: halo rim / reflection %s is gold (not orange), apart from the pellets" % c.to_html(false), hue > 33.0 and hue < 50.0 and _dist(c, Style.PELLET) > 0.15, "hue %.0f" % hue)
	var ochre := 0
	for p in Style.FACADE_PICK:
		if p == 1 or p == 5:
			ochre += 1
	_check("palette: ochre facades rare (protanopia), plinth row darkened", ochre <= 2 and FileAccess.get_file_as_string("res://shaders/arles_facade.gdshader").contains("if (y < 0.55) c *= 0.5;"))
	_check("palette: brush material table fits the shader (<= 48)", Style.MATS.size() <= Style.MAX_MATS)

	# ---- exit ----
	var ex = Node3D.new()
	ex.set_script(load("res://scripts/arles_exit.gd"))
	root.add_child(ex)
	ex.setup(Vector3(exit_cell.y * 2.0, 0.9, exit_cell.x * 2.0))
	_check("exit: Yellow House, green door, green shutters, green star, green light", ex.house != null and ex.door != null and ex.shutters != null and ex.star != null and ex.light != null)
	_check("exit: everything green is mint green #3AF5C8", ex.door_material.get_shader_parameter("col") == Style.EXIT and ex.shutter_material.get_shader_parameter("col") == Style.EXIT and ex.star_material.get_shader_parameter("g_mid") == Style.EXIT and ex.light.light_color == Style.EXIT)
	var door_world: Vector3 = ex.position + ex.local(ex.DOOR)
	_check("exit: the door is flush with the house front at the exit cell", absf(door_world.z - (exit_cell.x * 2.0 - 1.0)) < 0.1 and absf(door_world.x - exit_cell.y * 2.0) < 0.6, str(door_world))
	_check("exit: the star stands high over the house (over the roofs)", ex.STAR.y >= 15.0 and ex.STAR_SIZE >= 5.0)
	var ex_intr := ""
	for p in ex.house_parts:
		var bb: AABB = p.aabb
		var lo: Vector3 = bb.position + ex.MAP_ORIGIN
		var hi: Vector3 = bb.end + ex.MAP_ORIGIN
		if lo.y < EYE and Scenery.intrudes(Vector2(lo.x, lo.z), Vector2(hi.x, hi.z)):
			ex_intr += p.mat + " "
	_check("exit: the house stays behind its front (nothing in the square)", ex_intr == "", ex_intr)
	ex.update(0.1, 0.0)
	var p0 = ex.door_material.get_shader_parameter("pulse")
	ex.update(0.4, 0.0)
	_check("exit: slow pulse (0.5 Hz, far below 3 Hz)", p0 != ex.door_material.get_shader_parameter("pulse") and ex.PULSE_HZ <= 0.5)
	ex.set_reduce_fx(true)
	var p1 = ex.door_material.get_shader_parameter("pulse")
	ex.update(0.7, 0.0)
	_check("exit: 'Effekte reduzieren' stops the pulse", p1 == ex.door_material.get_shader_parameter("pulse") and not ex.pulse_enabled())

	# ---- fonts / licences: no foreign material in this city ----
	_check("assets: no textures or fonts of its own (all procedural)", not DirAccess.dir_exists_absolute("res://textures/arles"))

	mv.queue_free()
	ex.queue_free()
	if failures == 0:
		print("ALL %d ARLES CHECKS PASSED" % checks)
	else:
		print("%d/%d ARLES CHECKS FAILED" % [failures, checks])
	quit(1 if failures > 0 else 0)


## A shader parameter as float; `def` when the material never set it.
func _f(v, def: float) -> float:
	return def if v == null else float(v)


func _street(id: String) -> Dictionary:
	for s in M.STREETS:
		if s.id == id:
			return s
	return {}


## First closed cell from `from` in direction `d`: its landmark id, "parapet",
## or "block".
func _ray(maze, from: Vector2i, d: Vector2i) -> String:
	var c: Vector2i = from
	while c.x >= 0 and c.y >= 0 and c.x < maze.rows and c.y < maze.cols and maze.grid[c.x][c.y] == 0:
		c += d
	var k := M.cell_kind(c.x, c.y)
	if k == "landmark":
		return M.landmark_block_at(c.x, c.y).id
	return k


func _longest_dir(maze, s: Vector2i) -> Vector2i:
	var best := Vector2i.ZERO
	var best_len := -1
	for d in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var n := 0
		var c: Vector2i = s + d
		while c.x >= 0 and c.y >= 0 and c.x < maze.rows and c.y < maze.cols and maze.grid[c.x][c.y] == 0:
			n += 1
			c += d
		if n > best_len:
			best_len = n
			best = d
	return best


func _reachable(maze, from: Vector2i) -> Dictionary:
	var seen := {from: true}
	var q := [from]
	var i := 0
	while i < q.size():
		var cur: Vector2i = q[i]
		i += 1
		for d in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
			var n: Vector2i = cur + d
			if n.x < 0 or n.y < 0 or n.x >= maze.rows or n.y >= maze.cols:
				continue
			if seen.has(n) or maze.grid[n.x][n.y] != 0:
				continue
			seen[n] = true
			q.append(n)
	return seen


func _shortest(maze, a: Vector2i, b: Vector2i) -> Array:
	var prev := {a: a}
	var q := [a]
	var i := 0
	while i < q.size():
		var cur: Vector2i = q[i]
		i += 1
		if cur == b:
			break
		for d in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
			var n: Vector2i = cur + d
			if n.x < 0 or n.y < 0 or n.x >= maze.rows or n.y >= maze.cols or prev.has(n) or maze.grid[n.x][n.y] != 0:
				continue
			prev[n] = cur
			q.append(n)
	var out := []
	var c: Vector2i = b
	while prev.has(c) and c != a:
		out.append(c)
		c = prev[c]
	return out


func _collect(node: Node, geo: Array, skip: Dictionary) -> void:
	for ch in node.get_children():
		if ch.is_queued_for_deletion() or skip.has(ch):
			continue
		if ch is GeometryInstance3D and ch.visible:
			geo.append(ch)
		_collect(ch, geo, skip)


func _collect_lights(node: Node, out: Array) -> void:
	for ch in node.get_children():
		if ch is Light3D:
			out.append(ch)
		_collect_lights(ch, out)


func _collect_texts(node: Node, out: Array) -> void:
	for ch in node.get_children():
		if ch is Label3D:
			out.append(ch.text)
		_collect_texts(ch, out)


func _contrast(a: Color, b: Color) -> float:
	var la := a.srgb_to_linear()
	var lb := b.srgb_to_linear()
	var ya := 0.2126 * la.r + 0.7152 * la.g + 0.0722 * la.b
	var yb := 0.2126 * lb.r + 0.7152 * lb.g + 0.0722 * lb.b
	return (maxf(ya, yb) + 0.05) / (minf(ya, yb) + 0.05)


func _dist(a: Color, b: Color) -> float:
	return _oklab(a).distance_to(_oklab(b))


func _oklab(c: Color) -> Vector3:
	var l := c.srgb_to_linear()
	var L := 0.4122214708 * l.r + 0.5363325363 * l.g + 0.0514459929 * l.b
	var Mm := 0.2119034982 * l.r + 0.6806995451 * l.g + 0.1073969566 * l.b
	var S := 0.0883024619 * l.r + 0.2817188376 * l.g + 0.6299787005 * l.b
	L = pow(L, 1.0 / 3.0)
	Mm = pow(Mm, 1.0 / 3.0)
	S = pow(S, 1.0 / 3.0)
	return Vector3(0.2104542553 * L + 0.7936177850 * Mm - 0.0040720468 * S,
		1.9779984951 * L - 2.4285922050 * Mm + 0.4505937099 * S,
		0.0259040371 * L + 0.7827717662 * Mm - 0.8086757660 * S)
