extends SceneTree
## Headless test: res://scripts/white_rabbit.gd — ISO week, the "Kaninchen
## der Woche" seed and the rabbit's position (spec 2.2, 2.5). Run with
##   godot --headless --path . --script res://tests/test_white_rabbit.gd
## Exits with code 0 on success, 1 on any failure.

var failures := 0
var checks := 0


func _check(name: String, cond: bool, detail := "") -> void:
	checks += 1
	if not cond:
		failures += 1
		print("FAIL ", name, (" -> " + detail) if detail != "" else "")


func _initialize() -> void:
	var WR = load("res://scripts/white_rabbit.gd")
	var Conditions = load("res://scripts/conditions.gd")
	var Levels = load("res://scripts/levels.gd")
	var maze_gen = load("res://scripts/maze_gen.gd").new()

	# --- ISO 8601 weeks (incl. year boundaries) ---
	var cases := [
		[2026, 10, 3, Vector2i(2026, 40)],
		[2026, 1, 1, Vector2i(2026, 1)],   # Thursday
		[2021, 1, 3, Vector2i(2020, 53)],  # Sunday, belongs to 2020-W53
		[2024, 12, 30, Vector2i(2025, 1)], # Monday, already 2025-W01
		[2020, 12, 31, Vector2i(2020, 53)],
		[2027, 1, 1, Vector2i(2026, 53)],  # 2026 starts on a Thursday -> 53 weeks
		[2024, 2, 29, Vector2i(2024, 9)],
	]
	for c in cases:
		var got: Vector2i = WR.iso_week(c[0], c[1], c[2])
		_check("iso_week %d-%02d-%02d" % [c[0], c[1], c[2]], got == c[3], "got %s want %s" % [got, c[3]])
	_check("weeks_in_year: 2026 has 53, 2025 has 52", WR.weeks_in_year(2026) == 53 and WR.weeks_in_year(2025) == 52)
	var now_week: Vector2i = WR.current_iso_week()
	_check("current_iso_week: a plausible week", now_week.y >= 1 and now_week.y <= 53 and now_week.x >= 2024)

	# --- seed: same week + level -> same result, other week can differ ---
	var w := Vector2i(2026, 40)
	var a: RandomNumberGenerator = WR.week_rng("klassik-1", w)
	var b: RandomNumberGenerator = WR.week_rng("klassik-1", w)
	var same := true
	for i in 50:
		if Conditions.pick_condition(a) != Conditions.pick_condition(b):
			same = false
	_check("week rng: same level + week -> same results", same)
	_check("week seed: other level, other week -> other seed", WR.week_seed("klassik-1", w) != WR.week_seed("klassik-2", w) and WR.week_seed("klassik-1", w) != WR.week_seed("klassik-1", Vector2i(2026, 41)))
	var firsts := {}
	for wk in range(1, 53):
		firsts[Conditions.pick_condition(WR.week_rng("klassik-1", Vector2i(2026, wk)))] = true
	_check("week rng: over the weeks of a year several conditions come up", firsts.size() >= 3, str(firsts.keys()))
	_check("week label", WR.week_label(Vector2i(2026, 4)) == "2026-W04")
	var cur: Vector2i = Vector2i(2026, 40)
	_check("week display: same year -> 'KW 4'", WR.week_display("2026-W04", cur) == "KW 4", WR.week_display("2026-W04", cur))
	_check("week display: other year -> 'KW 52/2025'", WR.week_display("2025-W52", cur) == "KW 52/2025")
	_check("week display: unknown week -> 'KW ?'", WR.week_display("", cur) == "KW ?" and WR.week_display("kaputt", cur) == "KW ?")
	var c1: RandomNumberGenerator = WR.chaos_rng()
	var c2: RandomNumberGenerator = WR.chaos_rng()
	_check("chaos rng: random seeds (two generators differ)", c1.seed != c2.seed)

	# --- position: every pool level ---
	for lv in Levels.POOL:
		var maze = maze_gen.generate_maze(lv.rows, lv.cols, lv.seed, Levels.maze_opts(lv))
		var start: Vector2i = Levels.start_cell(maze_gen, maze)
		var cell: Vector2i = WR.pick_cell(maze_gen, maze, start, lv.seed)
		var dist: Array = maze_gen.bfs(maze, start.x, start.y)
		var max_d := 0
		for rc in maze_gen.cells_in_room(maze, false):
			max_d = maxi(max_d, dist[rc.x][rc.y])
		_check("pick_cell %s: a room cell, not the start" % lv.id, cell != start and maze_gen.cells_in_room(maze, false).has(cell))
		_check("pick_cell %s: dead end" % lv.id, maze_gen.neighbors_of(maze, cell.x, cell.y).size() == 1)
		_check("pick_cell %s: >= 40 %% of the max BFS distance" % lv.id, dist[cell.x][cell.y] >= 0.4 * max_d, "%d / %d" % [dist[cell.x][cell.y], max_d])
		_check("pick_cell %s: deterministic per level seed" % lv.id, WR.pick_cell(maze_gen, maze, start, lv.seed) == cell)
		_check("pick_cell %s: respects excluded cells" % lv.id, WR.pick_cell(maze_gen, maze, start, lv.seed, [cell]) != cell)
	maze_gen.free()

	print("")
	if failures == 0:
		print("ALL %d WHITE RABBIT CHECKS PASSED" % checks)
		quit(0)
	else:
		print("%d/%d WHITE RABBIT CHECKS FAILED" % [failures, checks])
		quit(1)
