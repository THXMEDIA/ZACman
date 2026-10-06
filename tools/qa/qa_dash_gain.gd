extends SceneTree
## QA: how much time can a dash save on the reference route of every
## Speedrun level? Walks the "nearest pellet next" route (the one behind
## Levels.target_s), counts the straight stretches long enough for a full dash
## and prints the saving per dash and per run.
## Run: copy to godot/tests/ and call
##   godot --headless --path godot --script res://tests/qa_dash_gain.gd
## (it only reads Levels/MazeGen/PlayerController).

const LevelsScript := preload("res://scripts/levels.gd")
const MazeGenScript := preload("res://scripts/maze_gen.gd")
const PlayerScript := preload("res://scripts/player_controller.gd")

var mg = MazeGenScript.new()


func _init() -> void:
	var speed: float = PlayerScript.PLAYER_SPEED
	var dash_m: float = PlayerScript.DASH_SPEED * PlayerScript.DASH_TIME
	var save_per_dash: float = dash_m / speed - PlayerScript.DASH_TIME
	print("walk %.2f m/s, dash %.1f m in %.2f s -> saves %.2f s per dash on a free stretch" % [speed, dash_m, PlayerScript.DASH_TIME, save_per_dash])
	print("%-12s %7s %7s %8s %9s %9s" % ["level", "target", "route", "runs>=2", "1 dash", "3 dashes"])
	for lv in LevelsScript.POOL:
		var maze = mg.generate_maze(lv.rows, lv.cols, lv.seed, LevelsScript.maze_opts(lv))
		var route_s: float = LevelsScript.reference_route_seconds(mg, maze)
		var runs := _count_runs(maze)
		print("%-12s %6.0fs %6.1fs %8d %7.1f%% %8.1f%%" % [lv.id, lv.target_s, route_s, runs, 100.0 * save_per_dash / route_s, 300.0 * save_per_dash / route_s])
	quit(0)


## Straight stretches of >= 2 steps (4 m) on the nearest-pellet route.
func _count_runs(maze) -> int:
	var start: Vector2i = LevelsScript.start_cell(mg, maze)
	var todo := {}
	for c in mg.cells_in_room(maze, false):
		if c != start:
			todo[c] = true
	var cur: Vector2i = start
	var runs := 0
	while not todo.is_empty():
		var dist: Array = mg.bfs(maze, cur.x, cur.y)
		var next_cell = null
		var next_d := 1 << 30
		for c in todo:
			var d: int = dist[c.x][c.y]
			if d >= 0 and d < next_d:
				next_d = d
				next_cell = c
		if next_cell == null:
			break
		# walk back from the target along falling distances to get the leg
		var path: Array = [next_cell]
		var p: Vector2i = next_cell
		while dist[p.x][p.y] > 0:
			var stepped := false
			for dv in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var q: Vector2i = p + dv
				if q.x < 0 or q.y < 0 or q.x >= dist.size() or q.y >= dist[0].size():
					continue
				if dist[q.x][q.y] == dist[p.x][p.y] - 1 and dist[q.x][q.y] >= 0:
					p = q
					path.append(p)
					stepped = true
					break
			if not stepped:
				break
		path.reverse()
		var run := 1
		var last_dir := Vector2i.ZERO
		for i in range(1, path.size()):
			var dir: Vector2i = path[i] - path[i - 1]
			if dir == last_dir:
				run += 1
			else:
				if run >= 2:
					runs += 1
				run = 1
				last_dir = dir
		if run >= 2:
			runs += 1
		cur = next_cell
		todo.erase(next_cell)
	return runs
