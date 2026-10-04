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

const LEVEL_SEED := 1765
## Static draw calls: wall MultiMesh, floor, card MultiMesh, sky.
const STATIC_DRAW_BUDGET := 6

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
	_check("budget: static geometry <= %d draw calls" % STATIC_DRAW_BUDGET, geo.size() <= STATIC_DRAW_BUDGET, "%d: %s" % [geo.size(), ", ".join(geo.map(func(g): return String(g.name)))])
	var lights := []
	_collect_lights(mv, lights)
	_check("budget: no lights (printed, unlit world)", lights.is_empty())
	var sr = mv.scenery_root
	_check("comfort: pop-ups fold by default", sr.fold_enabled())
	sr.set_reduce_fx(true)
	_check("comfort: 'Effekte reduzieren' stands every card up", not sr.fold_enabled())
	sr.set_reduce_fx(false)
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
	_check("registry: exit script, no traffic, own exit text", city.metro_script.ends_with("kyoto_exit.gd") and city.traffic == "" and city.exit_text != "")

	# ---- palette: gold only pellets, green only the exit ----
	var world := [Style.AI1, Style.AI2, Style.AI3, Style.AI4, Style.PAPER, Style.SUMI, Style.BENI, Style.SLAB]
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
