extends SceneTree
## Headless test: the Kyoto Explorer city (docs/design/kyoto-explorer.md) —
## street grid (kyoto_maze.gd), pellet trails to the exit, the pop-up card
## city (kyoto_scenery.gd): cards on the collision edge, landmarks, determinism
## with the level seed, draw-call budget, comfort switch, palette rules, exit.
## Run with
##   godot --headless --path . --script res://tests/test_kyoto.gd

const KyotoMaze := preload("res://scripts/kyoto_maze.gd")
const KyotoScenery := preload("res://scripts/kyoto_scenery.gd")
const Style := preload("res://scripts/kyoto_style.gd")
const CityThemes := preload("res://scripts/city_themes.gd")
const ExplorerCities := preload("res://scripts/explorer_cities.gd")
const KyotoLife := preload("res://scripts/kyoto_life.gd")

const LEVEL_SEED := 1765
## Static draw calls: wall MultiMesh, floor, card MultiMesh, sky, petals.
const STATIC_DRAW_BUDGET := 6
## The whole of Kyoto with everything that moves: statics + the passers-by
## MultiMesh + the pellets (the exit adds a few small meshes of its own).
const TOTAL_DRAW_BUDGET := 7

var failures := 0
var checks := 0


func _check(name: String, cond: bool, detail := "") -> void:
	checks += 1
	if not cond:
		failures += 1
		print("FAIL ", name, (" -> " + detail) if detail != "" else "")


func _initialize() -> void:
	var maze = KyotoMaze.new().generate()

	# ---- grid ----
	_check("grid: 45 rows x 49 cols", maze.rows == 45 and maze.cols == 49)
	var border_closed := true
	for r in maze.rows:
		for c in maze.cols:
			if (r == 0 or c == 0 or r == maze.rows - 1 or c == maze.cols - 1) and maze.grid[r][c] != 1:
				border_closed = false
	_check("grid: closed border (no way out of the book)", border_closed)
	var start: Vector2i = maze.start_cell
	var exit_cell: Vector2i = KyotoMaze.METRO_CELL
	_check("grid: start and exit are open street cells", maze.grid[start.x][start.y] == 0 and maze.grid[exit_cell.x][exit_cell.y] == 0)
	_check("grid: the exit faces the Kiyomizu block (wall south of it)", maze.grid[exit_cell.x + 1][exit_cell.y] == 1 and KyotoMaze.landmark_block_at(exit_cell.x + 1, exit_cell.y).get("id", "") == "kiyomizu")
	var reach := _reachable(maze, start)
	var open_n := 0
	for r in maze.rows:
		for c in maze.cols:
			if maze.grid[r][c] == 0:
				open_n += 1
	_check("grid: every street cell is reachable from the start", reach.size() == open_n, "%d of %d" % [reach.size(), open_n])
	_check("grid: no ghost house, no tunnel", maze.door_col == -1 and maze.tunnel_row == -1)
	var streets_ok := true
	for s in KyotoMaze.STREETS:
		var w: int = (s.c1 - s.c0 + 1) if s.axis == "ns" else (s.r1 - s.r0 + 1)
		if w < 3:
			streets_ok = false
	_check("grid: every street at least 3 cells (6 m) wide", streets_ok)

	# ---- trails ----
	var trail: Array = KyotoMaze.trail_cells(maze, [exit_cell], start, LEVEL_SEED)
	_check("trails: a pellet trail exists", trail.size() > 60, "%d" % trail.size())
	var trail_open := true
	for t in trail:
		if maze.grid[t.x][t.y] != 0:
			trail_open = false
	_check("trails: only on open cells", trail_open)
	_check("trails: exit cell carries no pellet", not (exit_cell in trail))
	_check("trails: deterministic per seed", trail == KyotoMaze.trail_cells(maze, [exit_cell], start, LEVEL_SEED))
	var varies := false
	for sd in [99, 4242, 7, 123]:
		if trail != KyotoMaze.trail_cells(maze, [exit_cell], start, sd):
			varies = true
	_check("trails: other seeds lay other trails", varies)
	var ends_ok := true
	var net := KyotoMaze.trail_network()
	for e in KyotoMaze.TRAIL_ENDS:
		if not net.has(e) or maze.grid[e.x][e.y] != 0:
			ends_ok = false
	_check("trails: all trail ends lie on the open network", ends_ok)
	var full: Array = KyotoMaze.trail_cells(maze, [exit_cell], start, LEVEL_SEED)
	_check("trails: the start's trail leads to the exit (start next to a trail cell)", _touches(full, start) or full.has(start))

	# ---- cards ----
	var cards: Array = KyotoScenery.cards(maze, LEVEL_SEED)
	_check("cards: deterministic per level seed", _same_cards(cards, KyotoScenery.cards(maze, LEVEL_SEED)))
	_check("cards: another seed varies the houses", not _same_cards(cards, KyotoScenery.cards(maze, 4242)))
	var by_kind := {}
	for c in cards:
		by_kind[c.kind] = by_kind.get(c.kind, 0) + 1
	var houses: int = by_kind.get(Style.K_MACHIYA, 0) + by_kind.get(Style.K_SHOP, 0) + by_kind.get(Style.K_TEMPLE_WALL, 0)
	_check("cards: house rows along the streets", houses > 120, "%d" % houses)
	var NF := Style.NO_FOLD
	_check("cards: landmarks never fold — theatre, shrine gate, Kiyomizu, four temple gates, Inari shrine", by_kind.get(Style.K_THEATER + NF, 0) == 1 and by_kind.get(Style.K_GATE + NF, 0) == 1 and by_kind.get(Style.K_KIYOMIZU + NF, 0) == 1 and by_kind.get(Style.K_TEMPLE_GATE + NF, 0) == 4 and by_kind.get(Style.K_SHRINE + NF, 0) == 1)
	_check("cards: the pagoda as two crossed cards, standing", by_kind.get(Style.K_PAGODA + NF, 0) == 2)
	_check("cards: a torii tunnel", by_kind.get(Style.K_TORII, 0) >= 15)
	_check("cards: backdrop hills and the tower never fold", by_kind.get(Style.K_MOUNTAINS + Style.NO_FOLD, 0) >= 3 and by_kind.get(Style.K_TOWER + Style.NO_FOLD, 0) == 1)
	_check("cards: figures in doorways", by_kind.get(Style.K_FIGURE, 0) >= 8)

	# ---- cherry trees ----
	var trees: Array = []
	for c in cards:
		if c.kind == Style.K_SAKURA:
			trees.append(c)
	_check("trees: cherry trees along the lanes (40..140)", trees.size() >= 40 and trees.size() <= 140, "%d" % trees.size())
	var trees2: Array = KyotoScenery.tree_cards(maze, LEVEL_SEED)
	var tree_same := trees2.size() == trees.size()
	for i in mini(trees.size(), trees2.size()):
		if not trees[i].pos.is_equal_approx(trees2[i].pos) or not is_equal_approx(trees[i].w, trees2[i].w) or not is_equal_approx(trees[i].yaw, trees2[i].yaw) or not is_equal_approx(trees[i].s, trees2[i].s):
			tree_same = false
	_check("trees: deterministic per level seed (position, size, yaw, variation)", tree_same)
	var other_trees: Array = KyotoScenery.tree_cards(maze, 4242)
	var tree_differs := other_trees.size() != trees.size()
	for i in mini(trees.size(), other_trees.size()):
		if not trees[i].pos.is_equal_approx(other_trees[i].pos):
			tree_differs = true
	_check("trees: another seed plants other trees", tree_differs)
	var widths := {}
	var heights := {}
	var yaws := {}
	for t in trees:
		widths[snappedf(t.w, 0.1)] = true
		heights[snappedf(t.h, 0.1)] = true
		yaws[snappedf(t.yaw, 0.01)] = true
	_check("trees: varied size and rotation", widths.size() >= 8 and heights.size() >= 8 and yaws.size() >= 6, "%d widths, %d heights, %d yaws" % [widths.size(), heights.size(), yaws.size()])
	var tree_place := true
	var tree_bad := ""
	var crowns_over_walls := 0
	var tall_ok := true
	for t in trees:
		var tn := Vector3(sin(t.yaw), 0, cos(t.yaw))
		var tr := Vector3(tn.z, 0, -tn.x)
		for e in [t.pos + tr * t.w * 0.5, t.pos - tr * t.w * 0.5, t.pos]:
			var inside := KyotoScenery.cell_of(e - tn * 0.3)
			if not KyotoScenery.in_map(maze, inside) or maze.grid[inside.x][inside.y] != 1:
				tree_place = false
				tree_bad = "tree at %s (edge %s)" % [t.pos, e]
		var behind_wall := KyotoScenery.cell_of(t.pos)
		if maze.grid[behind_wall.x][behind_wall.y] == 1:
			crowns_over_walls += 1
			if t.h < 6.0:
				tall_ok = false
		if t.h > 8.7 or t.w > 5.3 or t.h < 4.3:
			tall_ok = false
	_check("trees: every card stands on its block, never across a street end", tree_place, tree_bad)
	_check("trees: some stand behind temple walls with their crown above the wall", crowns_over_walls >= 4 and tall_ok, "%d behind walls" % crowns_over_walls)
	var tree_near_fig := false
	for t in trees:
		for sp in KyotoScenery.figure_spots():
			if Vector2(t.pos.x - sp[0].x, t.pos.z - sp[0].z).length() < 0.4 * t.w:
				tree_near_fig = true
	_check("trees: none covers a doorway figure", not tree_near_fig)
	var tree_edges_ok := true
	for t in trees:
		var cc := KyotoScenery.cell_of(t.pos)
		var tn2 := Vector3(sin(t.yaw), 0, cos(t.yaw))
		var front := KyotoScenery.cell_of(t.pos + tn2 * 0.6)
		if maze.grid[cc.x][cc.y] == 0 and maze.grid[front.x][front.y] != 0:
			tree_edges_ok = false
	_check("trees: a tree on the facade line has open street in front of it", tree_edges_ok)
	var plain_a := cards.filter(func(c): return c.kind != Style.K_SAKURA)
	var plain_b := KyotoScenery.cards(maze, LEVEL_SEED).filter(func(c): return c.kind != Style.K_SAKURA)
	_check("trees: planting them leaves every other card as before (own random stream)", _same_cards(plain_a, plain_b) and plain_a.size() + trees.size() == cards.size())
	var petals: Array = KyotoScenery.petal_spots(cards, LEVEL_SEED)
	_check("petals: a few, from the crowns (<= %d)" % KyotoScenery.PETAL_MAX, petals.size() > 30 and petals.size() <= KyotoScenery.PETAL_MAX, "%d" % petals.size())
	var petals2: Array = KyotoScenery.petal_spots(cards, LEVEL_SEED)
	_check("petals: deterministic", petals.size() == petals2.size() and petals[0].pos.is_equal_approx(petals2[0].pos) and petals[petals.size() - 1].pos.is_equal_approx(petals2[petals2.size() - 1].pos))
	_check("petals: fall slowly, nothing flickers (turn rate far below 3 Hz)", KyotoScenery.PETAL_FALL_SPEED * KyotoScenery.PETAL_TUMBLE < 1.0 and KyotoScenery.PETAL_FALL_SPEED < 0.5)
	# House cards stand on the collision edge: wall behind, street in front.
	var on_edge := true
	var bad := ""
	for c in cards:
		if c.kind > Style.K_TEMPLE_WALL:
			continue
		var n := Vector3(sin(c.yaw), 0, cos(c.yaw))
		var behind := KyotoScenery.cell_of(c.pos - n * 0.5)
		var front := KyotoScenery.cell_of(c.pos + n * 0.5)
		if maze.grid[behind.x][behind.y] != 1 or maze.grid[front.x][front.y] != 0:
			on_edge = false
			bad = "%s at %s" % [c.kind, c.pos]
			break
	_check("cards: every house card on the facade line (wall behind, street in front)", on_edge, bad)
	# Back-layer cards stand inside blocks, never in a street.
	var back_ok := true
	for c in cards:
		if c.kind == Style.K_ROOFS or c.kind == Style.K_PINE:
			var cc := KyotoScenery.cell_of(c.pos)
			if maze.grid[cc.x][cc.y] != 1:
				back_ok = false
	_check("cards: roofs and pines stand inside the blocks", back_ok)
	# A folded card stays on its own block (never lies across a street).
	var lying_ok := true
	var lying_bad := ""
	for c in cards:
		if c.kind >= Style.NO_FOLD or c.kind == Style.K_TORII or c.kind == Style.K_FIGURE:
			continue
		var n := Vector3(sin(c.yaw), 0, cos(c.yaw))
		var right := Vector3(n.z, 0, -n.x)
		var lie: float = minf(c.h, c.fold_len)
		for e in [Vector3.ZERO, right * c.w * 0.45, -right * c.w * 0.45]:
			var tip := KyotoScenery.cell_of(c.pos + e - n * lie)
			if tip.x >= 0 and tip.y >= 0 and tip.x < maze.rows and tip.y < maze.cols and maze.grid[tip.x][tip.y] == 0:
				lying_ok = false
				lying_bad = "kind %d at %s" % [c.kind, c.pos]
	_check("cards: a lying card stays on its block (no card over a street)", lying_ok, lying_bad)
	# The camera never runs through a torii post: the rails keep the player
	# (radius 0.34) off the post line.
	var rails: Array = KyotoScenery.torii_rails()
	var inner: float = KyotoScenery.TORII_POST - KyotoScenery.TORII_POST_HALF
	_check("torii: posts inside the lane, rails along them", rails.size() == 2 and inner > 1.5 and KyotoScenery.TORII_POST + KyotoScenery.TORII_POST_HALF < 3.0 - 0.34)
	var rail_cover := true
	for r in rails:
		var x0: float = r.center.x - r.size.x * 0.5
		var x1: float = r.center.x + r.size.x * 0.5
		if x0 > KyotoScenery.TORII_FROM * 2.0 - 0.3 or x1 < KyotoScenery.TORII_TO * 2.0 + 0.3:
			rail_cover = false
		# from the inner post face out to the lane wall: no gap to slip behind
		var z_in: float = absf(r.center.z - KyotoScenery.TORII_Z) - r.size.z * 0.5
		var z_out: float = absf(r.center.z - KyotoScenery.TORII_Z) + r.size.z * 0.5
		if z_in > inner + 0.001 or z_out < KyotoScenery.TORII_LANE_HALF:
			rail_cover = false
	_check("torii: the rails cover every post and reach the wall", rail_cover)
	# Trails always run through the torii lane and to the pagoda.
	var hi_ok := true
	for sd in [1765, 1, 2, 3, 99, 4242]:
		var tr: Array = KyotoMaze.trail_cells(maze, [exit_cell], start, sd)
		if not tr.has(Vector2i(39, 5)) or not tr.has(Vector2i(31, 34)):
			hi_ok = false
	_check("trails: every seed leads through the torii lane and to the pagoda", hi_ok)
	# Custom data is stored as 16-bit floats in Compatibility (code review H1):
	# keep every encoded value in a safe range.
	var enc_ok := true
	for c in cards:
		if c.kind > 255 or c.w > 300.0 or c.h > 300.0 or c.fold_len > 100.0:
			enc_ok = false
	_check("cards: encoded values fit the half-float custom data", enc_ok)
	# Way to the exit passes the highlights (GD K1): the shortest path runs
	# down Hanamikoji, past the pagoda lane and the torii lane.
	var path := _shortest(maze, start, exit_cell)
	var via_hanamikoji := false
	var via_sannenzaka := false
	for pc in path:
		if pc.x == 31 and pc.y >= 22 and pc.y <= 24:
			via_hanamikoji = true
		if pc.y == 30 and pc.x >= 36 and pc.x <= 38:
			via_sannenzaka = true
	_check("route: the shortest way to the exit runs down Hanamikoji and Sannenzaka", via_hanamikoji and via_sannenzaka, "%d cells" % path.size())
	var base_ok := true
	for c in cards:
		if c.kind < Style.NO_FOLD + Style.K_TOWER and absf(c.pos.y - KyotoScenery.CARD_BASE_Y) > 0.001:
			base_ok = false
	_check("cards: all pop-ups hinge on the page (same base height)", base_ok)

	# ---- view / budget / comfort ----
	var mv = load("res://scripts/maze_view.gd").new()
	root.add_child(mv)
	mv.build(maze, start, "kyoto", KyotoMaze.metro_cells(), KyotoMaze.metro_cells(), -1, "", LEVEL_SEED)
	_check("view: Kyoto scenery built", mv.scenery_root != null and mv.scenery_root.card_count == cards.size(), str(mv.scenery_root.card_count if mv.scenery_root != null else -1))
	_check("view: pellets follow the trails", mv.pellet_cells.size() > 50 and not (exit_cell in mv.pellet_cells))
	_check("view: no power pellets, no rabbit (calm explorer)", mv.power_cells.size() == 0 and mv.rabbit_node == null)
	var geo := []
	_collect(mv, geo, {mv.pellet_mmi: true})
	_check("view: trees and petals counted by the root", mv.scenery_root.tree_count == trees.size() and mv.scenery_root.petal_count == petals.size() and mv.scenery_root.petals is MultiMeshInstance3D)
	_check("budget: static geometry <= %d draw calls" % STATIC_DRAW_BUDGET, geo.size() <= STATIC_DRAW_BUDGET, "%d: %s" % [geo.size(), ", ".join(geo.map(func(g): return String(g.name)))])
	var lights := []
	_collect_lights(mv, lights)
	_check("budget: no lights (printed, unlit world)", lights.is_empty())
	var sr = mv.scenery_root
	_check("comfort: pop-ups fold by default", sr.fold_enabled())
	_check("comfort: petals fall by default", sr.petals.visible)
	sr.set_reduce_fx(true)
	_check("comfort: 'Effekte reduzieren' stands every card up", not sr.fold_enabled())
	_check("comfort: 'Effekte reduzieren' hides the falling petals", not sr.petals.visible)
	var geo_fx := []
	_collect(mv, geo_fx, {mv.pellet_mmi: true})
	_check("budget: one draw call fewer without petals", geo_fx.size() == geo.size() - 1, "%d vs %d" % [geo_fx.size(), geo.size()])
	sr.set_reduce_fx(false)
	_check("comfort: petals come back with effects on", sr.petals.visible)
	var texts := []
	_collect_texts(mv, texts)
	_check("text: the city carries no lettering (no fake Japanese)", texts.is_empty(), str(texts))
	# collision: the printed plan is thin, but the built boxes are full height
	var hs := []
	for cs in mv.walls_body.get_children():
		hs.append(cs.shape.size.y)
	_check("collision: every wall box %.1f m, above the camera (1.9 m)" % KyotoMaze.WALL_H, hs.min() == hs.max() and is_equal_approx(hs.min(), KyotoMaze.WALL_H) and hs.min() > 1.9, "%s..%s" % [hs.min(), hs.max()])
	var rails_node = sr.get_node_or_null("ToriiRails")
	_check("torii: rails built as wall-layer bodies", rails_node is StaticBody3D and rails_node.collision_layer == 2 and rails_node.get_child_count() == 2)
	var coll_kids := 0
	for ch in sr.get_children():
		if ch is CollisionObject3D:
			coll_kids += 1
	_check("trees: no collision bodies of their own (only torii rails and figure blocks)", coll_kids == 2, "%d" % coll_kids)
	var fig_node = sr.get_node_or_null("FigureBlocks")
	_check("figures: a block in front of each figure", fig_node is StaticBody3D and fig_node.collision_layer == 2 and fig_node.get_child_count() == by_kind.get(Style.K_FIGURE, 0))
	sr.start_intro()
	_check("intro: running after start_intro", sr.intro_running())
	sr.set_reduce_fx(true)
	_check("intro: reduced effects end the intro at once", not sr.intro_running())
	sr.set_reduce_fx(false)
	sr.start_intro()
	sr._process(5.0)
	_check("intro: ends after INTRO_S with the normal fold distances", not sr.intro_running() and is_equal_approx(float(sr.card_material.get_shader_parameter("fold_near")), Style.FOLD_NEAR))

	# ---- theme / registry ----
	var th = CityThemes.get_theme("kyoto")
	_check("theme: registered", th.id == "kyoto" and ExplorerCities.has_city("kyoto") and ExplorerCities.EXPLORER_IDS.has("kyoto"))
	_check("theme: no glow, no SSR, linear tonemap (print colours exact)", not th.env_glow_enabled and not th.env_ssr_enabled and th.env_tonemap_mode == 0)
	var far := 0.0
	for c in cards:
		far = maxf(far, Vector2(c.pos.x - start.y * 2.0, c.pos.z - start.x * 2.0).length())
	_check("theme: the camera reaches the backdrop", th.camera_far > far + 40.0, "far %.0f, camera %.0f" % [far, th.camera_far])
	var city: Dictionary = ExplorerCities.get_city("kyoto")
	_check("registry: exit script, passers-by (no cars), own exit text", city.metro_script.ends_with("kyoto_exit.gd") and city.traffic == "kyoto" and city.exit_text != "")

	# ---- palette: gold only pellets, green only the exit ----
	var world := [Style.AI1, Style.AI2, Style.AI3, Style.AI4, Style.PAPER, Style.SUMI, Style.BENI, Style.SLAB, Style.BLOSSOM]
	var gold_ok := true
	var green_ok := true
	var near := ""
	for col in world:
		if _dist(col, Style.PELLET) < 0.12: # same bar as Tokyo
			gold_ok = false
			near += col.to_html(false) + " %.2f " % _dist(col, Style.PELLET)
		if _dist(col, Style.EXIT) < 0.12:
			green_ok = false
	_check("palette: no world colour near the pellet gold", gold_ok, near)
	_check("palette: no world colour near the exit green", green_ok)

	# ---- passers-by (kyoto_life.gd) ----
	var life = Node3D.new()
	life.set_script(KyotoLife)
	root.add_child(life)
	life.setup(mv, LEVEL_SEED)
	var n_walk: int = life.walker_count()
	_check("life: 15..30 passers-by", n_walk >= 15 and n_walk <= 30, "%d" % n_walk)
	_check("life: all in ONE MultiMesh (one draw call)", life.draw_calls() == 1 and life.walker_mmi.multimesh.instance_count == n_walk and life.get_child_count() == 1)
	var life_bodies := 0
	var stack: Array = [life]
	while not stack.is_empty():
		var nd: Node = stack.pop_back()
		if nd is CollisionObject3D:
			life_bodies += 1
		stack.append_array(nd.get_children())
	_check("life: no collision bodies (a figure never blocks the way, Main only pushes softly)", life_bodies == 0)
	_check("life: slow strolling (<= 1.2 m/s, the player runs 5 m/s)", KyotoLife.SPEED_MAX <= 1.2 and KyotoLife.SPEED_MIN >= 0.4)
	_check("life: push circle small (<= 0.5 m), lane 6 m", KyotoLife.WALKER_RADIUS <= 0.5)
	var kinds := {}
	for i in n_walk:
		kinds[int(life.w_s[i] * 3.0)] = true
	_check("life: all three looks (yukata, wagasa, tourist) appear", kinds.size() == 3, str(kinds.keys()))
	# routes: every sample on open street, with free room on both sides and
	# a wide free gap past the figure (player radius 0.34)
	var route_ok := true
	var route_bad := ""
	var min_side := 99.0
	var min_gap := 99.0
	for r in KyotoLife.ROUTES.size():
		var route: Dictionary = KyotoLife.ROUTES[r]
		var pts: Array = route.pts
		var segs: int = pts.size() if route.get("loop", false) else pts.size() - 1
		for k in segs:
			var a: Vector2 = pts[k]
			var b: Vector2 = pts[(k + 1) % pts.size()]
			var dir := (b - a).normalized()
			var perp := Vector2(-dir.y, dir.x)
			var seg_len := a.distance_to(b)
			var t := 0.0
			while t <= seg_len:
				var p := a + dir * t
				var dl := _clear(maze, p, perp)
				var dr := _clear(maze, p, -perp)
				if dl < 0.0 or dr < 0.0:
					route_ok = false
					route_bad = "%s at %s" % [route.id, p]
				min_side = minf(min_side, minf(dl, dr))
				min_gap = minf(min_gap, maxf(dl, dr) - KyotoLife.WALKER_RADIUS)
				t += 0.5
	_check("life: every route stays on open street cells", route_ok, route_bad)
	_check("life: a figure never presses into a facade (>= push circle + player radius)", min_side >= KyotoLife.WALKER_RADIUS + 0.34, "%.2f" % min_side)
	_check("life: past every figure at least 2 m of free lane (needs 0.68)", min_gap >= 2.0, "%.2f" % min_gap)
	# over two minutes: at every moment, at every figure's cross-section
	# (all figures' circles counted) a free gap of >= 1.2 m remains
	var worst_gap := 99.0
	var gl = Node3D.new()
	gl.set_script(KyotoLife)
	root.add_child(gl)
	gl.setup(mv, LEVEL_SEED)
	var pos_ok := true
	for step in 40:
		gl.advance(3.0)
		for i in n_walk:
			worst_gap = minf(worst_gap, _cross_gap(maze, gl, i))
			var cc := KyotoScenery.cell_of(gl.walker_position(i))
			if maze.grid[cc.x][cc.y] != 0:
				pos_ok = false
	_check("life: in 2 minutes the lane past a figure never closes (all circles counted, gap >= 1.2 m)", worst_gap >= 1.2, "%.2f" % worst_gap)
	_check("life: for 2 minutes everybody stays on open street", pos_ok)
	# movement, determinism, comfort
	var before := PackedVector3Array(life.w_pos)
	life.advance(10.0)
	var moved := 0
	for i in n_walk:
		if life.w_pos[i].distance_to(before[i]) > 4.0:
			moved += 1
	_check("life: people walk (10 s -> several metres)", moved >= n_walk - 4, "%d of %d" % [moved, n_walk])
	var l1 = Node3D.new()
	l1.set_script(KyotoLife)
	root.add_child(l1)
	l1.setup(mv, LEVEL_SEED)
	var l2 = Node3D.new()
	l2.set_script(KyotoLife)
	root.add_child(l2)
	l2.setup(mv, LEVEL_SEED)
	var l3 = Node3D.new()
	l3.set_script(KyotoLife)
	root.add_child(l3)
	l3.setup(mv, 4242)
	l1.advance(25.0)
	l2.advance(25.0)
	l3.advance(25.0)
	_check("life: same seed, same steps -> same people", l1.w_pos == l2.w_pos and l1.w_u == l2.w_u and l1.w_s == l2.w_s)
	_check("life: another seed -> other people", l1.w_s != l3.w_s or l1.w_u != l3.w_u)
	l1.set_comfort(true)
	var frozen := PackedVector3Array(l1.w_pos)
	l1.advance(10.0)
	_check("comfort: 'Effekte reduzieren' -> everybody stands still", l1.w_pos == frozen)
	l1.set_comfort(false)
	l1.advance(5.0)
	_check("comfort: and they walk again", l1.w_pos != frozen)
	# the camera is only read: yaw faces it, direction flips via instance colour
	var cam_a := Vector3(30.0, 0.95, 20.0)
	l2.advance(0.1, cam_a)
	# (the headless dummy renderer keeps no instance buffers: check the state
	# the transforms are built from)
	var facing_ok := true
	for i in n_walk:
		var nrm := Vector3(sin(l2._yaw[i]), 0, cos(l2._yaw[i]))
		var to_cam := Vector3(cam_a.x - l2.w_pos[i].x, 0, cam_a.z - l2.w_pos[i].z).normalized()
		if nrm.dot(to_cam) < 0.999:
			facing_ok = false
	_check("life: figures turn to the camera (yaw only, upright)", facing_ok)
	_check("life: instance data = standing card kind (never folds), fits half floats", Style.K_WALKER + Style.NO_FOLD <= 255 and KyotoLife.WALKER_W < 3.0 and KyotoLife.WALKER_H < 3.0 and Style.K_WALKER + Style.NO_FOLD > Style.NO_FOLD)
	# no allocations per frame
	var cam := Vector3(48.6, 0.95, 64.0)
	for i in 120:
		life.update(1.0 / 60.0, cam, cam)
	var obj0 := Performance.get_monitor(Performance.OBJECT_COUNT)
	var res0 := Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)
	var node0 := _count_nodes(root)
	for i in 600:
		var c2 := cam + Vector3(sin(i * 0.05) * 20.0, 0, -i * 0.05)
		life.update(1.0 / 60.0, c2, c2)
	var obj1 := Performance.get_monitor(Performance.OBJECT_COUNT)
	var res1 := Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)
	var node1 := _count_nodes(root)
	_check("frames: no new objects in 600 frames of passers-by", obj1 == obj0, "%d -> %d" % [obj0, obj1])
	_check("frames: no new resources, no new nodes", res1 == res0 and node1 == node0, "%d -> %d resources, %d -> %d nodes" % [res0, res1, node0, node1])
	# draw-call budget with everything that moves
	var geo_all := []
	_collect(mv, geo_all, {})
	_collect(life, geo_all, {})
	_check("budget: Kyoto total <= %d draw calls (statics, petals, passers-by, pellets)" % TOTAL_DRAW_BUDGET, geo_all.size() <= TOTAL_DRAW_BUDGET, "%d: %s" % [geo_all.size(), ", ".join(geo_all.map(func(g): return String(g.name)))])
	for l in [life, gl, l1, l2, l3]:
		l.queue_free()

	# ---- exit ----
	var ex = Node3D.new()
	ex.set_script(load("res://scripts/kyoto_exit.gd"))
	root.add_child(ex)
	ex.setup(Vector3(exit_cell.y * 2.0, 0.9, exit_cell.x * 2.0))
	_check("exit: door, page flap, pad and bookmark ribbon", ex.door_light != null and ex.flap != null and ex.pad != null and ex.ribbon != null)
	_check("exit: the ribbon rises over the roofs", ex.RIBBON_TOP > 12.0)
	var g0: Color = ex._glow_mat.albedo_color
	ex.update(1.0, 0.0)
	_check("exit: slow pulse (0.5 Hz)", not g0.is_equal_approx(ex._glow_mat.albedo_color) and ex.PULSE_HZ < 3.0)
	_check("exit: sign is the standard 出口 + EXIT", ex.sign_label.text.contains("出口") and ex.sign_label.text.contains("EXIT"))

	mv.queue_free()
	ex.queue_free()
	if failures == 0:
		print("ALL %d KYOTO CHECKS PASSED" % checks)
	else:
		print("%d/%d KYOTO CHECKS FAILED" % [failures, checks])
	quit(1 if failures > 0 else 0)


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


## Free distance from p along dir (m) until the first wall cell; -1 if p itself
## is not open street.
func _clear(maze, p: Vector2, dir: Vector2) -> float:
	var d := 0.0
	while d < 12.0:
		var q := p + dir * d
		var cell := KyotoScenery.cell_of(Vector3(q.x, 0.0, q.y))
		if not KyotoScenery.in_map(maze, cell) or maze.grid[cell.x][cell.y] != 0:
			return d if d > 0.0 else -1.0
		d += 0.05
	return d


## The widest free gap (m) on the cross-section through walker i, counting
## the push circles of all walkers near that line.
func _cross_gap(maze, lf, i: int) -> float:
	var pos: Vector3 = lf.walker_position(i)
	var dir: Vector2 = lf.w_dir[i]
	var perp := Vector2(-dir.y, dir.x)
	var p := Vector2(pos.x, pos.z)
	var lo := -_clear(maze, p, -perp)
	var hi := _clear(maze, p, perp)
	var blocked: Array = []
	for j in lf.walker_count():
		var q: Vector3 = lf.walker_position(j)
		var rel := Vector2(q.x, q.z) - p
		var along := rel.dot(dir)
		var across := rel.dot(perp)
		var r: float = lf.WALKER_RADIUS + 0.34
		if absf(along) < r:
			var half := sqrt(maxf(0.0, r * r - along * along))
			blocked.append(Vector2(across - half, across + half))
	blocked.sort_custom(func(a, b): return a.x < b.x)
	var best := 0.0
	var cur := lo
	for iv in blocked:
		if iv.x > cur:
			best = maxf(best, minf(iv.x, hi) - cur)
		cur = maxf(cur, iv.y)
	best = maxf(best, hi - cur)
	return best


func _count_nodes(n: Node) -> int:
	var c := 1
	for ch in n.get_children():
		c += _count_nodes(ch)
	return c


func _touches(cells: Array, c: Vector2i) -> bool:
	for d in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
		if cells.has(c + d):
			return true
	return false


func _same_cards(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if a[i].kind != b[i].kind or not a[i].pos.is_equal_approx(b[i].pos) or not is_equal_approx(a[i].h, b[i].h):
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


func _dist(a: Color, b: Color) -> float:
	return _oklab(a).distance_to(_oklab(b))


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
