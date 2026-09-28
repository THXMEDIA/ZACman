extends SceneTree
## Headless test: res://scripts/maze_gen.gd connectivity, run with
##   godot --headless --script res://tests/test_maze.gd
## Exits with code 0 on success, 1 on any failure.

func _initialize() -> void:
	var maze_gen = load("res://scripts/maze_gen.gd").new()
	var level_sizes = [[19, 21], [21, 25], [23, 27], [23, 29]]
	var failures := 0
	var checks := 0

	for level_index in level_sizes.size():
		var size = level_sizes[level_index]
		for seed_value in range(1, 31):
			checks += 1
			var maze = maze_gen.generate_maze(size[0], size[1], level_index * 10000 + seed_value * 37)
			var check = maze_gen.connectivity_check(maze)
			if not check.ok:
				failures += 1
				print("FAIL level=%d size=%dx%d seed=%d unreachable=%d/%d" % [level_index, size[0], size[1], seed_value, check.unreachable, check.total])
			if maze.door_col % 2 != 1:
				failures += 1
				print("FAIL door_col not odd: level=%d seed=%d door_col=%d" % [level_index, seed_value, maze.door_col])
			if maze.grid[maze.house.r0][maze.door_col] != 0:
				failures += 1
				print("FAIL door tile not open: level=%d seed=%d" % [level_index, seed_value])
			if maze.grid[maze.tunnel_row][0] != 0 or maze.grid[maze.tunnel_row][maze.cols - 1] != 0:
				failures += 1
				print("FAIL tunnel row not open at edges: level=%d seed=%d" % [level_index, seed_value])

	maze_gen.free()
	print("")
	if failures == 0:
		print("ALL %d MAZE CHECKS PASSED" % checks)
		quit(0)
	else:
		print("%d/%d MAZE CHECKS FAILED" % [failures, checks])
		quit(1)
