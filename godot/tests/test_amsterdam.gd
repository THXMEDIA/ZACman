extends SceneTree
## Headless test: the Amsterdam Explorer city (docs/design/amsterdam-explorer.md)
## — canal-ring grid (amsterdam_maze.gd), the way past the three landmarks,
## pin trails to the exit, the cardboard model (amsterdam_scenery.gd): nothing
## visible in the walkable space (readable collision edge), facades on the
## facade lines, quay cut edges on every plate/water boundary, determinism,
## draw-call / vertex / light budget, colour rules (blue only pins, #00B894
## only the exit), registry, exit, texture and licence files.
## Run with
##   godot --headless --path . --script res://tests/test_amsterdam.gd

const M := preload("res://scripts/amsterdam_maze.gd")
const Scenery := preload("res://scripts/amsterdam_scenery.gd")
const Style := preload("res://scripts/amsterdam_style.gd")
const CityThemes := preload("res://scripts/city_themes.gd")
const ExplorerCities := preload("res://scripts/explorer_cities.gd")

const LEVEL_SEED := 2121
## Static draw calls (visible geometry without the pellets): floor, panel
## MultiMesh, cut-outs, quay flutes, water, cutting mat, desk, desk things,
## glue MultiMesh. The wall MultiMesh is physics only (not drawn).
const STATIC_DRAW_BUDGET := 9
const PANEL_BUDGET := 9000 # board instances in the one MultiMesh
const FLUTE_VERT_BUDGET := 260000
const CUT_VERT_BUDGET := 80000
const LIGHT_BUDGET := 3 # scenery: sun, bounce, desk lamp (+1 omni in the exit)
const SHADOW_BUDGET := 1 # only the sun (QA W3, code W2)
## Second build of the scenery (caches warm), headless (QA W2, code W1).
const REBUILD_BUDGET_MS := 50.0
const EYE := 1.9 # everything below this height in a street would be walked through

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
	_check("grid: 49 x 49", maze.rows == 49 and maze.cols == 49)
	var border_closed := true
	for r in maze.rows:
		for c in maze.cols:
			if (r == 0 or c == 0 or r == maze.rows - 1 or c == maze.cols - 1) and maze.grid[r][c] != 1:
				border_closed = false
	_check("grid: closed border (nobody walks off the model)", border_closed)
	_check("grid: start and exit are open street cells", maze.grid[start.x][start.y] == 0 and maze.grid[exit_cell.x][exit_cell.y] == 0)
	_check("grid: the exit platform faces the tram block (east)", M.cell_kind(exit_cell.x, exit_cell.y + 1) == "tram")
	var reach := _reachable(maze, start)
	var open_n := 0
	var water_open := 0
	for r in maze.rows:
		for c in maze.cols:
			if maze.grid[r][c] == 0:
				open_n += 1
			if M.cell_kind(r, c) == "water" and maze.grid[r][c] == 0:
				water_open += 1
	_check("grid: every street cell is reachable from the start", reach.size() == open_n, "%d of %d" % [reach.size(), open_n])
	_check("grid: canals are not walkable (water cells are walls)", water_open == 0)
	_check("grid: no ghost house, no tunnel", maze.door_col == -1 and maze.tunnel_row == -1)
	var widths_ok := true
	var bad_w := ""
	for s in M.STREETS:
		var w: int = (s.c1 - s.c0 + 1) if s.axis == "ns" else (s.r1 - s.r0 + 1)
		var need := 2 if s.id.begins_with("gasse") else 3
		if w < need:
			widths_ok = false
			bad_w = s.id
	_check("grid: quays and streets 3 cells (6 m), lanes 2 cells", widths_ok, bad_w)
	var bridges_ok := true
	for b in M.BRIDGES:
		# a bridge spans water: water on both sides across its width
		for i in range((b.r0 if b.axis == "ns" else b.c0), (b.r1 if b.axis == "ns" else b.c1) + 1):
			var side_a := M.cell_kind(i, b.c0 - 1) if b.axis == "ns" else M.cell_kind(b.r0 - 1, i)
			var side_b := M.cell_kind(i, b.c1 + 1) if b.axis == "ns" else M.cell_kind(b.r1 + 1, i)
			if side_a != "water" or side_b != "water":
				bridges_ok = false
	_check("grid: every bridge has water on both sides (rails = collision edge)", bridges_ok)
	_check("grid: the water lies below street level", Style.WATER_Y < -0.5 and Style.WATER_Y > Style.PLATE_Y)

	# ---- the way past the landmarks (Kyoto review lesson) ----
	var path := _shortest(maze, start, exit_cell)
	var via_damrak := 0
	var via_westermarkt := false
	var via_magere := false
	for pc in path:
		if pc.x >= 11 and pc.x <= 13 and pc.y * 2.0 >= M.DANCING_X0 - 6.0 and pc.y * 2.0 <= M.DANCING_X1:
			via_damrak += 1
		if pc.y >= 7 and pc.y <= 9 and pc.x >= 7 and pc.x <= 18:
			via_westermarkt = true
		if M.bridge_at(pc.x, pc.y).get("id", "") == "magere_brug":
			via_magere = true
	_check("route: the shortest way runs along the Damrak quay, across from the dancing houses", via_damrak >= 10, "%d cells" % via_damrak)
	_check("route: ... past the Westerkerk front on the Westermarkt", via_westermarkt)
	_check("route: ... and over the Magere Brug to the tram", via_magere, "%d cells" % path.size())
	_check("route: every way to the exit crosses the Magere Brug (no other crossing)", _reachable_without(maze, start, exit_cell, "magere_brug") == false)
	_check("route: the Damrak quay only opens to the Westermarkt (the church is passed)", _blocked_cols_between(maze) )
	_check("route: the Westerkerk tower closes the start axis (west, on the quay's centre line)",
		is_equal_approx(M.TOWER_Z, start.x * 2.0) and M.TOWER_X < start.y * 2.0 and _start_faces_west(maze, start))

	# ---- trails ----
	var trail: Array = M.trail_cells(maze, [exit_cell], start, LEVEL_SEED)
	_check("trails: a pin trail exists", trail.size() > 80, "%d" % trail.size())
	var trail_open := true
	for t in trail:
		if maze.grid[t.x][t.y] != 0:
			trail_open = false
	_check("trails: only on open cells", trail_open)
	_check("trails: exit cell carries no pin", not (exit_cell in trail))
	_check("trails: deterministic per seed", trail == M.trail_cells(maze, [exit_cell], start, LEVEL_SEED))
	var varies := false
	for sd in [99, 4242, 7, 123]:
		if trail != M.trail_cells(maze, [exit_cell], start, sd):
			varies = true
	_check("trails: other seeds lay other trails", varies)
	var net := M.trail_network()
	var ends_ok := true
	for e in M.TRAIL_ENDS + M.MUST_ENDS:
		if not net.has(e) or maze.grid[e.x][e.y] != 0:
			ends_ok = false
	_check("trails: all trail ends lie on the open network", ends_ok)
	var hi_ok := true
	for sd in [LEVEL_SEED, 1, 2, 3, 99, 4242]:
		var tr: Array = M.trail_cells(maze, [exit_cell], start, sd)
		var on_bridge := false
		for c in tr:
			if M.bridge_at(c.x, c.y).get("id", "") == "magere_brug":
				on_bridge = true
		if not tr.has(Vector2i(8, 8)) or not on_bridge or not (tr.has(start) or _touches(tr, start)):
			hi_ok = false
	_check("trails: every seed: from the start, to the church front and over the Magere Brug", hi_ok)
	# GD W4a: the way to the exit dense, side branches on every second cell
	var way: Array = M.route(maze)
	_check("route: the pin route runs start -> exit", way.size() > 1 and way[0] == start and way[way.size() - 1] == exit_cell)
	var dense := true
	var dotted := true
	var branch_n := 0
	for sd in [LEVEL_SEED, 1, 2, 3, 99, 4242]:
		var tr: Array = M.trail_cells(maze, [exit_cell], start, sd)
		for c in way:
			if c != exit_cell and not tr.has(c):
				dense = false
		for c in tr:
			if way.has(c):
				continue
			branch_n += 1
			# a branch pin never has a branch pin as its neighbour along the line
			for d in [Vector2i(1, 0), Vector2i(0, 1)]:
				if tr.has(c + d) and not way.has(c + d):
					dotted = false
	_check("trails: the way to the exit carries a pin on every cell", dense)
	_check("trails: side branches are dotted (every second cell)", dotted and branch_n > 20, "%d branch pins" % branch_n)
	# view points (Arles test): every trail end looks at something, and no end
	# looks across the water at the exit it cannot reach from there (GD W1)
	for e in M.TRAIL_ENDS + M.MUST_ENDS:
		var vp: Array = M.VIEW_POINTS.get(e, [])
		_check("view: trail end %s has a view point" % e, vp.size() == 2, str(vp))
		if vp.size() != 2:
			continue
		var hit := _ray_kind(maze, e, vp[0])
		_check("view: trail end %s looks at %s" % [e, vp[1]], hit == vp[1], hit)
		var across := _across_water(maze, e, vp[0])
		_check("view: from trail end %s the tram stop is not in sight across the water" % e, across != "street" or not _amstel_oost(maze, e, vp[0]), across)
	_check("view: no trail end on the Prinsengracht quay looking at the tram (35,35), none past the exit (28,43)", not (Vector2i(35, 35) in M.TRAIL_ENDS) and not (Vector2i(28, 43) in M.TRAIL_ENDS))
	# GD K1: the Westermarkt runs out to the model edge and ends on the mug
	_check("scale reveal: the Westermarkt runs south to the cut edge of the model", _ray_kind(maze, Vector2i(42, 8), Vector2i(1, 0)) == "cut" and maze.grid[47][8] == 0 and maze.grid[48][8] == 1)
	_check("scale reveal: the mug stands in the street's axis, a few metres beyond the edge", absf(Scenery.MUG_POS.x - 8 * 2.0) < 1.0 and Scenery.MUG_POS.z - Scenery.MUG_R > Scenery.PLATE_Z1 + 1.0 and Scenery.MUG_POS.z - Scenery.MUG_R < Scenery.PLATE_Z1 + 6.0)
	_check("scale reveal: the cut cells carry no plate (cut edge = collision edge)", not M.is_plate(48, 8) and Scenery.kind(48, 8) == "outside")

	# ---- the model as data ----
	var K = Scenery.kit(LEVEL_SEED)
	var K2 = Scenery.kit(LEVEL_SEED)
	_check("model: deterministic per level seed", _same_panels(K.panels, K2.panels) and K.cuts.size() == K2.cuts.size())
	_check("model: another seed varies the houses", not _same_panels(K.panels, Scenery.kit(4242).panels))
	_check("model: panel budget (one MultiMesh) <= %d" % PANEL_BUDGET, K.panels.size() <= PANEL_BUDGET and K.panels.size() > 3000, "%d" % K.panels.size())
	# Nothing of the model stands in the walkable space below eye height: the
	# visible edge (facade foot, quay cut edge, rail) IS the collision edge.
	var intr := ""
	for p in K.panels:
		var hit := _intrudes(p.xf)
		if hit != "":
			intr = hit
			break
	_check("collision edge: no board stands in a street or on a bridge below %.1f m" % EYE, intr == "", intr)
	var tree_ok := true
	for tp in K.trees:
		var tc := Scenery.cell_of(tp)
		if M.cell_kind(tc.x, tc.y) != "street":
			tree_ok = false
	_check("trees: crossed cut-outs on the quays (%d)" % K.trees.size(), K.trees.size() >= 10 and tree_ok)
	_check("trees: the trunk box closes the gap to the quay edge (no squeezing)", Scenery.TREE_IN - Scenery.TREE_BOX * 0.5 < 0.34 * 2.0)
	# facades: houses fill every facade line, fronts on the line
	var fac_ok := true
	var fac_bad := ""
	var fronts: Array = Scenery.facade_runs() + Scenery.waterfront_runs()
	for run in fronts:
		var length: float = run.a.distance_to(run.b)
		if length < 2.5:
			continue
		var covered := 0.0
		for h in K.houses:
			if h.n.is_equal_approx(run.n) and _on_segment(h.o, run.a, run.b):
				covered += h.w + 0.02
		# at a street corner the crossing row's corner house shows its second front here
		for cb in K.cutbacks:
			if cb.n.is_equal_approx(run.n) and (cb.p.distance_to(run.a) < 0.01 or cb.p.distance_to(run.b) < 0.01):
				covered += cb.depth
		if absf(covered - length) > 0.1:
			fac_ok = false
			fac_bad = "%s..%s: %.1f of %.1f m" % [run.a, run.b, covered, length]
	_check("facades: houses fill every facade line, fronts on the collision edge", fac_ok, fac_bad)
	var kinds := {}
	var dancing := 0
	var lean_max_generic := 0.0
	for h in K.houses:
		kinds[h.gable] = true
		if h.dancing and absf(h.lean) > 0.02:
			dancing += 1
		if not h.dancing:
			lean_max_generic = maxf(lean_max_generic, absf(h.lean))
	_check("houses: step, bell, neck and spout gables", kinds.size() == 4)
	var corners_ok: bool = K.cutbacks.size() >= 10 and K.corner_fronts.size() >= 10
	for cf in K.corner_fronts:
		if cf.depth < 3.0 or cf.depth > 12.0:
			corners_ok = false
	_check("corners: the corner house shows a second front (%d corners), no fire wall in a window" % K.cutbacks.size(), corners_ok)
	_check("houses: the Damrak row dances (strong lean), the others are only slightly off", dancing >= 4 and lean_max_generic <= 0.0045, "%d dancing, generic max %.4f" % [dancing, lean_max_generic])
	var solid := 0
	var taped := 0
	var white := 0
	var top := 0.0
	var top_at := Vector3.ZERO
	for p in K.panels:
		if p.flags & Scenery.FLAG_SOLID:
			solid += 1
		if p.flags & Scenery.FLAG_TAPE:
			taped += 1
		if is_equal_approx(p.paint, Scenery.PAINT_WHITE):
			white += 1
		if p.xf.origin.y > top:
			top = p.xf.origin.y
			top_at = p.xf.origin
	for ct in K.cuts:
		if ct.xf.origin.y > top:
			top = ct.xf.origin.y
			top_at = ct.xf.origin
	_check("windows: every house has a dark room behind its cut-out windows", solid >= K.houses.size())
	_check("model making: tape strips, cutter overruns, glue beads", taped > 40 and solid > K.houses.size() + 50 and K.glue.size() > 40, "tape %d, solid %d, glue %d" % [taped, solid, K.glue.size()])
	_check("Westerkerk: the tower is the highest thing, on the start axis", top > 50.0 and absf(top_at.z - M.TOWER_Z) < 1.0 and absf(top_at.x - M.TOWER_X) < 4.5, "%.1f m at %s" % [top, top_at])
	var crown_white := 0
	for ct in K.cuts:
		if ct.xf.origin.y > 45.0 and is_equal_approx(ct.paint, Scenery.PAINT_WHITE):
			crown_white += 1
	_check("Westerkerk: white imperial crown (crossed cut-outs)", crown_white >= 4)
	var mb := 0
	var mb_high := 0.0
	var mbr: Dictionary = {}
	for b in M.BRIDGES:
		if b.id == "magere_brug":
			mbr = b
	for p in K.panels:
		var o: Vector3 = p.xf.origin
		if is_equal_approx(p.paint, Scenery.PAINT_WHITE) and o.x > mbr.c0 * 2.0 - 3.0 and o.x < mbr.c1 * 2.0 + 3.0 and o.z > mbr.r0 * 2.0 - 3.0 and o.z < mbr.r1 * 2.0 + 3.0:
			mb += 1
			mb_high = maxf(mb_high, o.y)
	_check("Magere Brug: a white drawbridge with portals and balance beams", mb > 40 and mb_high > 7.0, "%d boards, %.1f m" % [mb, mb_high])
	var enc_ok := true
	for p in K.panels:
		if p.seed < 0.0 or p.seed > 1.0 or p.b < 0.0 or p.b > 1.0 or p.flags > 7 or not (p.paint in [0.0, 0.5, 1.0]):
			enc_ok = false
	_check("model: custom data fits the half-float encoding", enc_ok)
	# quay cut edges on every plate / water boundary
	var fl_len := 0.0
	for r in Scenery.runs(Scenery.is_plate, func(k): return k == "water"):
		fl_len += r.a.distance_to(r.b)
	var edges := 0
	for r in maze.rows:
		for c in maze.cols:
			if not Scenery.is_plate(M.cell_kind(r, c)):
				continue
			for d in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
				if M.cell_kind(r + d.x, c + d.y) == "water":
					edges += 1
	_check("quays: corrugated cut edge on every plate/water boundary", is_equal_approx(fl_len, edges * 2.0), "%.0f m vs %d edges" % [fl_len, edges])
	_check("beyond the edge: pencil, mug and ruler lie off the model (scale reveal)", Scenery.PENCIL_X < Scenery.PLATE_X0 - 5.0 and Scenery.MUG_POS.z > Scenery.PLATE_Z1 + 3.0 and Scenery.RULER_X > Scenery.PLATE_X1 + 5.0)
	# the roofs around the street's end (the low houses reach a house width
	# further than this)
	var view_rect := Rect2(6.0, 86.0, 24.0, 12.0)
	var roof := 0.0
	for p in K.panels:
		var o: Vector3 = p.xf.origin
		if view_rect.has_point(Vector2(o.x, o.z)):
			roof = maxf(roof, (p.xf * Vector3(0, 0.5, 0)).y)
	for ct in K.cuts:
		var o2: Vector3 = ct.xf.origin
		if view_rect.has_point(Vector2(o2.x, o2.z)):
			roof = maxf(roof, o2.y + Scenery.poly_top(ct.poly))
	var pencil_top := Style.PLATE_Y + 1.0 + 17.4 * cos(Scenery.MUG_PENCIL_TILT)
	_check("scale reveal: the mug with pencil and ruler rises clearly over the roofs at the edge", view_rect.end.x + 6.0 < Scenery.LOW_HOUSES.end.x and Scenery.mug_top() > roof + 10.0
		and pencil_top > Style.PLATE_Y + Scenery.MUG_H + 3.0 and Style.PLATE_Y + Scenery.MUG_H > roof - 1.0, "ruler %.1f m, pencil %.1f m, mug %.1f m, roofs %.1f m" % [Scenery.mug_top(), pencil_top, Style.PLATE_Y + Scenery.MUG_H, roof])

	# ---- view / budget / comfort ----
	var mv = load("res://scripts/maze_view.gd").new()
	root.add_child(mv)
	mv.build(maze, start, "amsterdam", M.metro_cells(), M.metro_cells(), -1, "", LEVEL_SEED)
	var sr = mv.scenery_root
	_check("view: Amsterdam model built", sr != null and sr.panel_count == K.panels.size())
	_check("view: pins follow the trails", mv.pellet_cells.size() > 80 and not (exit_cell in mv.pellet_cells))
	_check("view: no power pellets, no rabbit (calm explorer)", mv.power_cells.size() == 0 and mv.rabbit_node == null)
	_check("view: the wall boxes are physics only (not drawn)", mv.normal_wall_mmi != null and mv.normal_wall_mmi.visible == false)
	var geo := []
	_collect(mv, geo, {mv.pellet_mmi: true})
	_check("budget: static geometry <= %d draw calls" % STATIC_DRAW_BUDGET, geo.size() <= STATIC_DRAW_BUDGET, "%d: %s" % [geo.size(), ", ".join(geo.map(func(g): return String(g.name)))])
	var panels_node = sr.get_node_or_null("Panels")
	var glue_node = sr.get_node_or_null("Glue")
	_check("budget: repeated parts as MultiMesh (boards, glue)", panels_node is MultiMeshInstance3D and glue_node is MultiMeshInstance3D)
	var fl_v: int = sr.get_node("Flutes").mesh.surface_get_array_len(0)
	var cut_v: int = sr.get_node("Cuts").mesh.surface_get_array_len(0)
	_check("budget: quay flutes <= %d vertices" % FLUTE_VERT_BUDGET, fl_v <= FLUTE_VERT_BUDGET, "%d" % fl_v)
	_check("budget: cut-outs <= %d vertices" % CUT_VERT_BUDGET, cut_v <= CUT_VERT_BUDGET, "%d" % cut_v)
	var lights := []
	_collect_lights(mv, lights)
	var shadowed := lights.filter(func(l): return l.shadow_enabled)
	_check("budget: %d lights (sun, bounce, desk lamp), %d with shadows" % [LIGHT_BUDGET, SHADOW_BUDGET], lights.size() == LIGHT_BUDGET and shadowed.size() <= SHADOW_BUDGET, "%d / %d" % [lights.size(), shadowed.size()])
	_check("shadows: the sun alone, hard source (angular distance 0, soft rim by blur), two splits", sr.sun.shadow_enabled and is_zero_approx(sr.sun.light_angular_distance) and sr.sun.shadow_blur > 1.0
		and sr.sun.directional_shadow_mode == DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS and sr.lamp.shadow_enabled == false)
	# QA W2 / code W1: the second build only creates nodes
	var t0 := Time.get_ticks_usec()
	var sr2: Node3D = Scenery.build(maze, CityThemes.get_theme("amsterdam"), LEVEL_SEED)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	_check("build time: the second build reuses the flute mesh, boards and cut-outs (same instances)", sr2.get_node("Flutes").mesh == sr.get_node("Flutes").mesh
		and sr2.get_node("Panels").multimesh == sr.get_node("Panels").multimesh and sr2.get_node("Cuts").mesh == sr.get_node("Cuts").mesh)
	_check("build time: second build < %.0f ms headless" % REBUILD_BUDGET_MS, ms < REBUILD_BUDGET_MS, "%.1f ms" % ms)
	_check("build time: quay flutes indexed (shared wave samples)", sr.get_node("Flutes").mesh.surface_get_array_index_len(0) > sr.get_node("Flutes").mesh.surface_get_array_len(0))
	var mm: MultiMesh = sr.get_node("Panels").multimesh
	var pi: int = K.panels.size() / 2
	var bf: PackedFloat32Array = mm.buffer.slice(pi * 16, pi * 16 + 16)
	var pxf: Transform3D = K.panels[pi].xf
	var want := [pxf.basis.x.x, pxf.basis.y.x, pxf.basis.z.x, pxf.origin.x, pxf.basis.x.y, pxf.basis.y.y, pxf.basis.z.y, pxf.origin.y,
		pxf.basis.x.z, pxf.basis.y.z, pxf.basis.z.z, pxf.origin.z, K.panels[pi].seed, K.panels[pi].b, K.panels[pi].paint, float(K.panels[pi].flags) / 8.0]
	var buf_ok: bool = mm.buffer.size() == K.panels.size() * 16
	for i in 16:
		buf_ok = buf_ok and absf(bf[i] - want[i]) < 0.0001
	_check("boards: the MultiMesh is filled in one go (buffer: basis rows, origin, custom data)", buf_ok)

	sr2.free()
	_check("light: low warm evening sun (about 10-20 degrees)", sr.sun != null and -Style.SUN_DIR.normalized().y > sin(deg_to_rad(10.0)) and -Style.SUN_DIR.normalized().y < sin(deg_to_rad(20.0)) and Style.SUN_COLOR.r > Style.SUN_COLOR.b * 1.5)
	var texts := []
	_collect_texts(mv, texts)
	_check("text: the model carries no lettering", texts.is_empty(), str(texts))
	var hs := []
	for cs in mv.walls_body.get_children():
		hs.append(cs.shape.size.y)
	_check("collision: every wall box %.1f m, above the camera" % M.WALL_H, hs.min() == hs.max() and is_equal_approx(hs.min(), M.WALL_H) and hs.min() > 1.9, "%s..%s" % [hs.min(), hs.max()])
	var tb = sr.get_node_or_null("TreeBlocks")
	_check("collision: a block at every tree trunk", tb is StaticBody3D and tb.collision_layer == 2 and tb.get_child_count() == K.trees.size())
	_check("comfort: nothing in the city is animated", sr.animated_nodes().is_empty())
	sr.set_reduce_fx(true)
	_check("comfort: the model takes the 'Effekte reduzieren' switch", sr.fx_reduced())
	sr.set_reduce_fx(false)

	# ---- theme / registry ----
	var th = CityThemes.get_theme("amsterdam")
	_check("theme: registered", th.id == "amsterdam" and ExplorerCities.has_city("amsterdam") and ExplorerCities.EXPLORER_IDS.has("amsterdam"))
	_check("theme: lit by the HDRI room (sky for background, ambient, reflection)", th.env_sky_script != null and th.env_sky_script.sky() is Sky and th.env_sky_script.sky().sky_material is PanoramaSkyMaterial)
	_check("theme: no glow, no depth of field / grain (none exists in the game view)", not th.env_glow_enabled)
	_check("theme: pins as pellets (blue glass head, own shader)", th.pellet_shape == "pin" and th.pellet_shader_path.ends_with("amsterdam_pin.gdshader") and th.pellet_color == Style.PIN)
	var far := 0.0
	for pnt in [Vector3(Scenery.PENCIL_X, 0, 30), Scenery.MUG_POS, Vector3(Scenery.RULER_X, 0, 74)]:
		for cc in [Vector2(start.y * 2.0, start.x * 2.0), Vector2(exit_cell.y * 2.0, exit_cell.x * 2.0)]:
			far = maxf(far, Vector2(pnt.x - cc.x, pnt.z - cc.y).length())
	_check("theme: the camera reaches the desk beyond the model", th.camera_far > far + 40.0, "far %.0f, camera %.0f" % [far, th.camera_far])
	var city: Dictionary = ExplorerCities.get_city("amsterdam")
	_check("registry: label, exit script, no traffic, quiet, own texts", city.label == "AMSTERDAM" and city.metro_script.ends_with("amsterdam_exit.gd") and city.traffic == "" and city.siren == false and city.exit_text != "" and city.exit_title != "" and city.exit_hint != "" and city.intro_hint != "" and city.metro_radius > 0.9)
	_check("minimap: exit marker #00B894, canals in their own colour", th.minimap_exit_color == Style.EXIT and th.minimap_water_script != null and M.is_water(8, 20) and not M.is_water(12, 20))
	var bg: Color = th.minimap_bg_color
	_check("minimap: pins and blocks stand out from the dark streets (>= 3:1)", _contrast(th.pellet_color, bg) >= 3.0 and _contrast(th.minimap_wall_color, bg) >= 3.0, "pins %.1f, blocks %.1f" % [_contrast(th.pellet_color, bg), _contrast(th.minimap_wall_color, bg)])
	_check("minimap: canals differ from streets and blocks", _dist(th.minimap_water_color, bg) > 0.12 and _dist(th.minimap_water_color, th.minimap_wall_color) > 0.12)

	# ---- palette: blue only the pins, #00B894 only the exit ----
	_check("palette: pins #2E6BFF, exit #00B894", Style.PIN.to_html(false) == "2e6bff" and Style.EXIT.to_html(false) == "00b894")
	var world := [Style.HAZE, Style.KRAFT_LIT, Style.KRAFT, Style.VOID, Style.WATER, Style.TABLE, Style.PENCIL, Style.MUG, Style.WHITE_PAINT,
		Style.MAT, Style.FOG, Style.SUN_COLOR, Style.LAMP_COLOR, Style.BOUNCE_COLOR, Style.MINIMAP_WATER]
	var blue_ok := true
	var green_ok := true
	var near := ""
	for col in world:
		if _dist(col, Style.PIN) < 0.12:
			blue_ok = false
			near += col.to_html(false) + " "
		if _dist(col, Style.EXIT) < 0.12:
			green_ok = false
			near += col.to_html(false) + " "
		var hsv_h: float = col.h * 360.0
		if col.s > 0.25 and hsv_h > 190.0 and hsv_h < 260.0:
			blue_ok = false
			near += "blue-ish " + col.to_html(false)
	_check("palette: no world colour near the pin blue (and none blue at all)", blue_ok, near)
	_check("palette: no world colour near the exit green", green_ok, near)
	var paint_ok := true
	for p in K.panels:
		if is_equal_approx(p.paint, Scenery.PAINT_EXIT):
			paint_ok = false
	for ct in K.cuts:
		if is_equal_approx(ct.paint, Scenery.PAINT_EXIT):
			paint_ok = false
	_check("palette: no exit green in the city model (only the exit node)", paint_ok)

	# ---- exit ----
	var ex = Node3D.new()
	ex.set_script(load("res://scripts/amsterdam_exit.gd"))
	root.add_child(ex)
	ex.setup(Vector3(exit_cell.y * 2.0, 0.9, exit_cell.x * 2.0))
	_check("exit: green tram, inner light, flag on a pin", ex.tram != null and ex.glow != null and ex.light != null and ex.flag != null and ex.pin_head != null)
	var green := 0
	var behind := true
	for p in ex.panels():
		if is_equal_approx(p.paint, Scenery.PAINT_EXIT):
			green += 1
		var o: Vector3 = ex.position + p.xf.origin
		var oc := Scenery.cell_of(o)
		if p.xf.origin.y < EYE and Scenery.is_open(M.cell_kind(oc.x, oc.y)) and p.xf.origin.x > 0.3:
			behind = false
	_check("exit: the tram is painted green (%d boards)" % green, green > 25)
	_check("exit: tram and stop stand behind the kerb (nothing on the platform)", behind)
	_check("exit: the flag flies over the roofs, unfogged", ex.FLAG_TOP > 20.0 and ex._flag_mat.disable_fog)
	_check("exit: the inner light is the brightest thing (unshaded)", ex._glow_mat.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED and ex.light.shadow_enabled == false)
	# UX W-B: an open double door where the last pin stands, light, green spot
	var last_pin := Vector2i(exit_cell.x, exit_cell.y - 1)
	_check("exit: the last pin stands in front of the exit, in the door's axis", trail.has(last_pin) or M.trail_cells(maze, [exit_cell], start, 1).has(last_pin))
	_check("exit: open double door (~1.2 m) in the platform side, centred on the trigger", is_equal_approx(ex.DOOR_W, 1.2) and absf(ex.DOOR_Z) < 0.05 and ex.door_light != null and ex.door_light.position.x < ex.TRAM_X)
	var gap := true
	for p in ex.panels():
		var o3: Vector3 = p.xf.origin
		if absf(o3.x - (ex.TRAM_X - ex.TRAM_W * 0.5)) < 0.15 and o3.y > 0.3 and o3.y < 2.2 and absf(o3.z - ex.DOOR_Z) < ex.DOOR_W * 0.5 - 0.05:
			gap = false
	_check("exit: nothing closes the door opening", gap)
	_check("exit: a bright green spot on the platform in front of the door", ex.floor_spot != null and ex.floor_spot.position.x < ex.TRAM_X - ex.TRAM_W * 0.5 and absf(ex.floor_spot.position.z - ex.DOOR_Z) < 0.1)
	_check("exit: the green paint glows a little in the sun (QA K2), #00B894 unchanged", ex.EXIT_EMIT > 0.2 and Style.EXIT.to_html(false) == "00b894")
	ex.update(0.1, 0.0)
	var g0: Color = ex._glow_mat.albedo_color
	ex.update(0.6, 0.0)
	_check("exit: slow pulse (0.5 Hz, far below 3 Hz)", not g0.is_equal_approx(ex._glow_mat.albedo_color) and ex.PULSE_HZ < 3.0)
	ex.set_reduce_fx(true)
	var g1: Color = ex._glow_mat.albedo_color
	ex.update(0.7, 0.0)
	_check("exit: 'Effekte reduzieren' stops the pulse", g1.is_equal_approx(ex._glow_mat.albedo_color) and not ex.pulse_enabled())

	# ---- textures and licences ----
	var tex_ok := true
	var missing := ""
	for tp in Style.TEXTURES:
		if not FileAccess.file_exists(tp) or not FileAccess.file_exists(tp + ".import"):
			tex_ok = false
			missing += tp + " "
		elif tp.ends_with(".jpg") and Style.tex(tp) == null:
			tex_ok = false
			missing += tp + "(load) "
	_check("textures: every scan exists with its import file and loads", tex_ok, missing)
	if DirAccess.dir_exists_absolute("res://.godot/imported"):
		var imp_ok := true
		for tp in Style.TEXTURES:
			if not Style.imported(tp):
				imp_ok = false
		_check("textures: after the import every scan is imported (code W4)", imp_ok)
	_check("textures: raw files only outside exported builds", Style.raw_fallback_allowed() == not OS.has_feature("template"))
	# QA K1: the room behind the model has no glaring patch
	var pano: Image = Style.sky().sky_material.panorama.get_image()
	var lmax := 0.0
	if pano != null:
		if pano.is_compressed():
			pano.decompress()
		for y in range(0, pano.get_height(), 2):
			for x in range(0, pano.get_width(), 2):
				var pc := pano.get_pixel(x, y)
				lmax = maxf(lmax, (pc.r + pc.g + pc.b) / 3.0)
	_check("sky: the brightest spot of the room is clamped (no glare competing with the exit)", pano != null and lmax <= Style.SKY_MAX + 0.02, "%.2f" % lmax)

	var lic_path := ProjectSettings.globalize_path("res://").path_join("../docs/art/lizenzen.md")
	var lic := FileAccess.get_file_as_string(lic_path)
	var lic_ok := lic != ""
	for tp in Style.TEXTURES:
		if not lic.contains(tp.get_file().get_basename().trim_suffix("_albedo").trim_suffix("_normal").trim_suffix("_rough")) or not lic.contains("godot/textures/amsterdam"):
			lic_ok = false
	_check("licences: every scan listed in docs/art/lizenzen.md (CC0, source, where used)", lic_ok and lic.contains("CC0"))

	mv.queue_free()
	ex.queue_free()
	if failures == 0:
		print("ALL %d AMSTERDAM CHECKS PASSED" % checks)
	else:
		print("%d/%d AMSTERDAM CHECKS FAILED" % [failures, checks])
	quit(1 if failures > 0 else 0)


## A board intrudes when a point of it (corners, edge middles, centre) lies
## between 5 cm and eye height in an open cell (street, bridge) more than
## 6 cm away from that cell's edge to a closed neighbour (paint-thin details
## on a facade - cutter overruns - are allowed).
func _intrudes(xf: Transform3D) -> String:
	var s := Vector3(xf.basis.x.length(), xf.basis.y.length(), xf.basis.z.length())
	for ix in [-0.5, 0.0, 0.5]:
		for iy in [-0.5, 0.0, 0.5]:
			for iz in [-0.5, 0.0, 0.5]:
				var w := xf * Vector3(ix, iy, iz)
				if w.y < 0.05 or w.y > EYE:
					continue
				var c := Scenery.cell_of(w)
				if not Scenery.is_open(M.cell_kind(c.x, c.y)):
					continue
				var d := 99.0
				var fx := w.x - (c.y * 2.0 - 1.0)
				var fz := w.z - (c.x * 2.0 - 1.0)
				if not Scenery.is_open(M.cell_kind(c.x, c.y - 1)):
					d = minf(d, fx)
				if not Scenery.is_open(M.cell_kind(c.x, c.y + 1)):
					d = minf(d, 2.0 - fx)
				if not Scenery.is_open(M.cell_kind(c.x - 1, c.y)):
					d = minf(d, fz)
				if not Scenery.is_open(M.cell_kind(c.x + 1, c.y)):
					d = minf(d, 2.0 - fz)
				if d > 0.06:
					return "board at %s (size %s) reaches %.2f m into %s %s" % [xf.origin, s, d, M.cell_kind(c.x, c.y), c]
	return ""


func _on_segment(p: Vector3, a: Vector3, b: Vector3) -> bool:
	var ab := b - a
	var t := (p - a).dot(ab) / ab.length_squared()
	return t > 0.0 and t < 1.0 and (a + ab * t).distance_to(p) < 0.05


func _start_faces_west(maze, s: Vector2i) -> bool:
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
	return best == Vector2i(0, -1)


## The Damrak quay (rows 11-13) has no exit to the south or east: from it
## the only way on is the Westermarkt (cols 7-9).
func _blocked_cols_between(maze) -> bool:
	for c in range(10, 36):
		if maze.grid[14][c] == 0 or maze.grid[10][c] == 0:
			return false
	for r in range(11, 14):
		if maze.grid[r][36] == 0:
			return false
	return true


func _reachable_without(maze, a: Vector2i, b: Vector2i, bridge_id: String) -> bool:
	var seen := {a: true}
	var q := [a]
	var i := 0
	while i < q.size():
		var cur: Vector2i = q[i]
		i += 1
		if cur == b:
			return true
		for d in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
			var n: Vector2i = cur + d
			if n.x < 0 or n.y < 0 or n.x >= maze.rows or n.y >= maze.cols or seen.has(n) or maze.grid[n.x][n.y] != 0:
				continue
			if M.bridge_at(n.x, n.y).get("id", "") == bridge_id:
				continue
			seen[n] = true
			q.append(n)
	return false


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


func _touches(cells: Array, c: Vector2i) -> bool:
	for d in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
		if cells.has(c + d):
			return true
	return false


func _same_panels(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if not a[i].xf.is_equal_approx(b[i].xf) or a[i].flags != b[i].flags:
			return false
	return true


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


## First closed cell from `from` in direction `d` (M.cell_kind).
func _ray_kind(maze, from: Vector2i, d: Vector2i) -> String:
	var c: Vector2i = from
	while c.x >= 0 and c.y >= 0 and c.x < maze.rows and c.y < maze.cols and maze.grid[c.x][c.y] == 0:
		c += d
	return M.cell_kind(c.x, c.y)


## Looking from `from` in direction `d` over water: the kind of the first
## cell beyond the water ("" if the ray does not cross water).
func _across_water(maze, from: Vector2i, d: Vector2i) -> String:
	var c: Vector2i = from
	while c.x >= 0 and c.y >= 0 and c.x < maze.rows and c.y < maze.cols and maze.grid[c.x][c.y] == 0:
		c += d
	if M.cell_kind(c.x, c.y) != "water":
		return ""
	while M.cell_kind(c.x, c.y) == "water":
		c += d
	return M.cell_kind(c.x, c.y)


func _amstel_oost(_maze, from: Vector2i, d: Vector2i) -> bool:
	var c: Vector2i = from
	for i in 60:
		c += d
		if M.street_at(c.x, c.y).get("id", "") == "amstel_oost" or M.cell_kind(c.x, c.y) == "tram":
			return true
	return false
