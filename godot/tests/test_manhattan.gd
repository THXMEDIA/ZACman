extends SceneTree
## Headless test: res://scripts/manhattan_maze.gd (the speedrun bonus level's
## hand-authored real-Midtown grid). Run with
##   godot --headless --path . --script res://tests/test_manhattan.gd
## Exits with code 0 on success, 1 on any failure.

func _initialize() -> void:
	var maze_gen = load("res://scripts/maze_gen.gd").new()
	var mm = load("res://scripts/manhattan_maze.gd").new()
	var failures := 0
	var checks := 0

	var maze = mm.generate()

	checks += 1
	if maze.rows <= 0 or maze.cols <= 0:
		failures += 1
		print("FAIL manhattan maze has non-positive dimensions: %dx%d" % [maze.rows, maze.cols])

	checks += 1
	var check = maze_gen.connectivity_check(maze)
	if not check.ok:
		failures += 1
		print("FAIL manhattan maze not fully connected: unreachable=%d/%d" % [check.unreachable, check.total])

	checks += 1
	if maze.door_col % 2 != 1:
		failures += 1
		print("FAIL manhattan door_col not odd: %d" % maze.door_col)

	checks += 1
	if maze.grid[maze.house.r0][maze.door_col] != 0:
		failures += 1
		print("FAIL manhattan door tile not open")

	checks += 1
	if maze.grid[maze.tunnel_row][0] != 0 or maze.grid[maze.tunnel_row][maze.cols - 1] != 0:
		failures += 1
		print("FAIL manhattan tunnel row not open at edges")

	checks += 1
	if maze.start_cell.x < 0 or maze.start_cell.y < 0:
		failures += 1
		print("FAIL manhattan start_cell not set")
	elif maze.grid[maze.start_cell.x][maze.start_cell.y] != 0:
		failures += 1
		print("FAIL manhattan start_cell is not an open tile")

	# Start cell must be able to reach every other open intersection — the
	# same property MazeGen guarantees for its procedural levels, checked
	# here specifically from the actual player spawn point rather than an
	# arbitrary room cell.
	checks += 1
	var dist = maze_gen.bfs(maze, maze.start_cell.x, maze.start_cell.y)
	var rooms: Array = maze_gen.cells_in_room(maze, true)
	var unreachable_from_start := 0
	for cell in rooms:
		if dist[cell.x][cell.y] == -1:
			unreachable_from_start += 1
	if unreachable_from_start > 0:
		failures += 1
		print("FAIL %d/%d rooms unreachable from Manhattan start_cell" % [unreachable_from_start, rooms.size()])

	# Every avenue/street name lookup for an intersection column/row should
	# resolve (this is what MazeView/HUD would show as flavor text later).
	checks += 1
	var mm_script = load("res://scripts/manhattan_maze.gd")
	var named_ok := true
	for si in mm_script.STREETS.size():
		if mm_script.street_at(si * 2 + 1) == "":
			named_ok = false
	for ai in mm_script.AVENUES.size():
		if mm_script.avenue_at(ai * 2 + 1) == "":
			named_ok = false
	if not named_ok:
		failures += 1
		print("FAIL avenue_at/street_at did not resolve every intersection")

	# Every hand-authored landmark (manhattan_maze.gd's LANDMARKS) must land
	# on a distinct, real wall cell — not open street, not another
	# landmark's cell, and not inside the (now-open) former ghost-house
	# interior — or maze_view.gd's word-wall builder would silently never
	# render it. This is the same check that caught GRAND CENTRAL's first
	# placement landing on open floor.
	checks += 1
	var seen_blocks := {}
	var landmark_problems := 0
	for entry in mm_script.LANDMARKS:
		var block: Vector2i = mm_script.block_for_intersection(entry[1], entry[2])
		if block.x < 0 or block.x >= maze.rows or block.y < 0 or block.y >= maze.cols:
			landmark_problems += 1
			print("FAIL landmark %s resolves out of grid bounds: %s" % [entry[0], block])
			continue
		if maze.grid[block.x][block.y] != 1:
			landmark_problems += 1
			print("FAIL landmark %s at %s is not a wall cell" % [entry[0], block])
		var key := "%d,%d" % [block.x, block.y]
		if seen_blocks.has(key):
			landmark_problems += 1
			print("FAIL landmark %s collides on cell %s with %s" % [entry[0], block, seen_blocks[key]])
		else:
			seen_blocks[key] = entry[0]
		if mm_script.landmark_at(block.x, block.y) != entry[0]:
			landmark_problems += 1
			print("FAIL landmark_at(%s) did not return %s" % [block, entry[0]])
	if landmark_problems > 0:
		failures += 1

	# An ordinary wall cell with no landmark on it must report "" (this is
	# what maze_view.gd's word-wall builder uses to fall back to the
	# generic "BUILDING" label).
	checks += 1
	if mm_script.landmark_at(0, 0) != "":
		failures += 1
		print("FAIL landmark_at(0,0) (corner, no landmark) should return \"\"")

	maze_gen.free()
	mm.free()
	print("")
	if failures == 0:
		print("ALL %d MANHATTAN CHECKS PASSED" % checks)
		quit(0)
	else:
		print("%d/%d MANHATTAN CHECKS FAILED" % [failures, checks])
		quit(1)
