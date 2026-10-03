extends SceneTree
## Headless test: res://scripts/levels.gd (level pool) and the maze options
## it relies on. Run with
##   godot --headless --path . --script res://tests/test_levels.gd

var failures := 0
var checks := 0


func check(ok: bool, msg: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL " + msg)


## Room cells with exactly one open neighbour.
func dead_ends(mg, maze) -> int:
	var n := 0
	for c in mg.cells_in_room(maze, true):
		if mg.neighbors_of(maze, c.x, c.y).size() == 1:
			n += 1
	return n


## Can the right half be reached from the start without the wrap tunnel?
func halves_joined_without_tunnel(maze) -> bool:
	var start := Vector2i(1, 1)
	var seen := {start: true}
	var queue := [start]
	var qi := 0
	while qi < queue.size():
		var cur: Vector2i = queue[qi]
		qi += 1
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = cur + d
			if n.x < 0 or n.y < 0 or n.x >= maze.rows or n.y >= maze.cols:
				continue
			if maze.grid[n.x][n.y] == 0 and not seen.has(n):
				seen[n] = true
				queue.append(n)
	return seen.has(Vector2i(1, maze.cols - 2))


func _initialize() -> void:
	var L = load("res://scripts/levels.gd")
	var mg = load("res://scripts/maze_gen.gd").new()

	# --- pool basics -------------------------------------------------
	var seen_ids := {}
	for lv in L.POOL:
		check(not seen_ids.has(lv.id), "duplicate level id %s" % lv.id)
		seen_ids[lv.id] = true
		check(L.by_id(lv.id).id == lv.id, "by_id(%s)" % lv.id)
	# N4: an unknown id is no longer silently the first level
	check(L.by_id("gibt-es-nicht").is_empty() and L.by_id("").is_empty(), "by_id(unknown) must return {}")
	check(L.POOL.size() >= 6, "pool should contain the 4 classic + 2 new layout levels")
	check(L.by_id("offen").loop_prob > L.by_id("klassik-2").loop_prob, "'offen' needs more loops than klassik-2")
	check(L.by_id("durchbruch").breakthroughs >= 2, "'durchbruch' needs >= 2 doors")

	# --- every level: connected, target reachable but not trivial ------
	var dead := {}
	for lv in L.POOL:
		var maze = mg.generate_maze(lv.rows, lv.cols, lv.seed, L.maze_opts(lv))
		check(mg.connectivity_check(maze).ok, "%s: maze not fully connected" % lv.id)
		var start: Vector2i = L.start_cell(mg, maze)
		check(maze.grid[start.x][start.y] == 0, "%s: start cell is a wall" % lv.id)
		var route: float = L.reference_route_seconds(mg, maze)
		var bound: float = L.lower_bound_seconds(mg, maze)
		check(lv.target_s >= bound, "%s: target %.0f s is below the physical lower bound %.1f s" % [lv.id, lv.target_s, bound])
		check(absf(lv.target_s - route) <= 5.0, "%s: target %.0f s is not the reference route time %.1f s (+-5 s) — recompute target_s" % [lv.id, lv.target_s, route])
		dead[lv.id] = dead_ends(mg, maze)

	# --- layout proposals do what they claim ---------------------------
	check(dead["offen"] < dead["klassik-2"], "'offen' should have fewer dead ends than klassik-2 (%d vs %d)" % [dead["offen"], dead["klassik-2"]])
	var k2 = mg.generate_maze(21, 25, 20080, L.maze_opts(L.by_id("klassik-2")))
	check(not halves_joined_without_tunnel(k2), "klassik-2 (even mid) should only join its halves via the tunnel")
	var dl = L.by_id("durchbruch")
	var db = mg.generate_maze(dl.rows, dl.cols, dl.seed, L.maze_opts(dl))
	check(halves_joined_without_tunnel(db), "'durchbruch' should join its halves without the tunnel")
	var doors := 0
	var mid := int((db.cols - 1) / 2)
	for r in range(1, db.rows, 2):
		if r < db.house.r0 or r > db.house.r1:
			if db.grid[r][mid] == 0:
				doors += 1
	check(doors == dl.breakthroughs, "'durchbruch' should have exactly %d doors, has %d" % [dl.breakthroughs, doors])
	# Options must not change the default maze.
	var a = mg.generate_maze(19, 21, 10003)
	var b = mg.generate_maze(19, 21, 10003, {"loop_prob": 0.16, "breakthroughs": 0})
	check(a.grid == b.grid, "default options must reproduce the original maze")

	# --- random draw -----------------------------------------------------
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var played: Array = []
	var last := ""
	for i in L.POOL.size():
		var lv: Dictionary = L.draw_next(played, last, rng)
		check(not played.has(lv.id), "draw_next repeated %s within a round" % lv.id)
		played.append(lv.id)
		last = lv.id
	check(played.size() == L.POOL.size(), "a round should visit every level once")
	for i in 40:
		var lv2: Dictionary = L.draw_next(played, last, rng)
		check(lv2.id != last, "draw_next repeated the last level back to back")
		last = lv2.id
	var starts := {}
	for i in 60:
		rng.seed = 1000 + i
		starts[L.draw_next([], "", rng).id] = true
	check(starts.size() >= 4, "random start should reach most levels, got %d" % starts.size())

	mg.free()
	print("")
	if failures == 0:
		print("ALL %d LEVEL CHECKS PASSED" % checks)
		quit(0)
	else:
		print("%d/%d LEVEL CHECKS FAILED" % [failures, checks])
		quit(1)
