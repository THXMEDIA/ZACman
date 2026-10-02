extends Node
## MazeGen — autoload singleton with pure maze-generation logic.
##
## This is a 1:1 port of core/maze-core.js (the tested JS/Node maze
## generator): same randomized-DFS-spanning-tree + loop-carving algorithm,
## same mirrored symmetry, same wall-parity house/door placement, same
## tunnel row. Ported so both the web and Godot builds produce the same
## kind of level (they do not need byte-identical output, just the same
## verified-connected algorithm). See tests/test_maze.gd for the headless
## connectivity proof of this file specifically.

class LcgRng:
	var s: int
	func _init(seed_value: int) -> void:
		s = seed_value & 0xFFFFFFFF
	func next_float() -> float:
		s = (s * 1664525 + 1013904223) & 0xFFFFFFFF
		return float(s) / 4294967296.0

class Maze:
	var grid: Array # Array[Array[int]], 1 = wall, 0 = open
	var rows: int
	var cols: int
	var tunnel_row: int
	var house := {} # r0, r1, c0, c1, mid
	var door_col: int
	var start_cell: Vector2i = Vector2i(-1, -1)

const DEFAULT_LOOP_PROB := 0.16

## `opts` (all optional, defaults reproduce the original mazes exactly):
##   loop_prob (float)    chance per room edge to knock out an extra wall
##                        after the spanning tree — higher = fewer dead ends.
##   breakthroughs (int)  with an even mirror column (`mid`), the middle
##                        column stays closed and both halves only meet at
##                        the wrap tunnel; this opens that many doors in it
##                        (spread over the room rows). No effect when `mid`
##                        is odd (already a room column). Drawn from the rng
##                        after everything else, so it never shifts a
##                        level's base layout.
func generate_maze(rows: int, cols: int, seed_value: int, opts: Dictionary = {}) -> Maze:
	assert(rows % 2 == 1 and cols % 2 == 1, "rows/cols must be odd")
	var loop_prob: float = opts.get("loop_prob", DEFAULT_LOOP_PROB)
	var breakthroughs: int = opts.get("breakthroughs", 0)
	var rng := LcgRng.new(seed_value)
	var maze := Maze.new()
	maze.rows = rows
	maze.cols = cols

	var grid := []
	for r in range(rows):
		var row := []
		row.resize(cols)
		row.fill(1)
		grid.append(row)

	var mid := int((cols - 1) / 2)

	var even_near := func(n: int) -> int:
		return n if n % 2 == 0 else n - 1
	var mid_row_even: int = even_near.call(int(rows / 2))
	var hw: int = max(2, even_near.call(int(cols * 0.14)))
	var hh := 2
	var house := {
		"r0": mid_row_even - hh,
		"r1": mid_row_even + hh,
		"c0": mid - hw,
		"c1": mid + hw,
		"mid": mid,
	}
	var inside_house := func(r: int, c: int) -> bool:
		return r > house.r0 and r < house.r1 and c > house.c0 and c < house.c1

	var room_rows := []
	var r := 1
	while r < rows:
		room_rows.append(r)
		r += 2
	var room_cols_left := []
	var c := 1
	while c <= mid:
		room_cols_left.append(c)
		c += 2

	for rr in room_rows:
		for cc in room_cols_left:
			if not inside_house.call(rr, cc):
				grid[rr][cc] = 0

	var visited := {}
	var start_room := 0
	var start_col := 0
	for rr in room_rows:
		var found := false
		for cc in room_cols_left:
			if not inside_house.call(rr, cc):
				start_room = rr
				start_col = cc
				found = true
				break
		if found:
			break

	var stack := [[start_room, start_col]]
	visited[str(start_room) + "," + str(start_col)] = true
	while stack.size() > 0:
		var cur = stack[stack.size() - 1]
		var cr: int = cur[0]
		var cc2: int = cur[1]
		var candidates := [
			[cr - 2, cc2, cr - 1, cc2],
			[cr + 2, cc2, cr + 1, cc2],
			[cr, cc2 - 2, cr, cc2 - 1],
			[cr, cc2 + 2, cr, cc2 + 1],
		]
		var valid := []
		for cand in candidates:
			var nr: int = cand[0]
			var nc: int = cand[1]
			if room_rows.has(nr) and room_cols_left.has(nc) and not inside_house.call(nr, nc):
				var key := str(nr) + "," + str(nc)
				if not visited.has(key):
					valid.append(cand)
		if valid.is_empty():
			stack.pop_back()
			continue
		var pick: Array = valid[int(rng.next_float() * valid.size())]
		var wr: int = pick[2]
		var wc: int = pick[3]
		grid[wr][wc] = 0
		visited[str(pick[0]) + "," + str(pick[1])] = true
		stack.append([pick[0], pick[1]])

	for rr in room_rows:
		for cc in room_cols_left:
			if inside_house.call(rr, cc):
				continue
			if cc + 2 <= mid and not inside_house.call(rr, cc + 2) and rng.next_float() < loop_prob:
				grid[rr][cc + 1] = 0
			var r2: int = rr + 2
			if room_rows.has(r2) and not inside_house.call(r2, cc) and rng.next_float() < loop_prob:
				grid[rr + 1][cc] = 0

	for rr in range(rows):
		for cc in range(mid + 1):
			grid[rr][cols - 1 - cc] = grid[rr][cc]

	if breakthroughs > 0 and mid % 2 == 0:
		var rows_free := []
		for rr in room_rows:
			if rr < house.r0 or rr > house.r1:
				rows_free.append(rr)
		var n := mini(breakthroughs, rows_free.size())
		var used := {}
		for i in n:
			var idx := int((i + 0.5) * rows_free.size() / float(n))
			idx = clampi(idx + int(rng.next_float() * 3.0) - 1, 0, rows_free.size() - 1)
			while used.has(idx):
				idx = (idx + 1) % rows_free.size()
			used[idx] = true
			grid[rows_free[idx]][mid] = 0

	var tunnel_row: int = room_rows[int(room_rows.size() / 2)]
	grid[tunnel_row][0] = 0
	grid[tunnel_row][1] = 0
	grid[tunnel_row][cols - 1] = 0
	grid[tunnel_row][cols - 2] = 0

	for rr in range(house.r0 + 1, house.r1):
		for cc in range(house.c0 + 1, house.c1):
			grid[rr][cc] = 0
	var door_col: int = (mid - 1) if mid % 2 == 0 else mid
	grid[house.r0][door_col] = 0

	maze.grid = grid
	maze.tunnel_row = tunnel_row
	maze.house = house
	maze.door_col = door_col
	return maze

func is_open(maze: Maze, r: int, c: int) -> bool:
	if r < 0 or r >= maze.rows:
		return false
	var cc := c
	if cc < 0:
		cc = maze.cols - 1
	if cc >= maze.cols:
		cc = 0
	return maze.grid[r][cc] == 0

func cells_in_room(maze: Maze, include_house: bool) -> Array:
	var list := []
	var r := 1
	while r < maze.rows:
		var c := 1
		while c < maze.cols:
			if maze.grid[r][c] == 0:
				var in_house: bool = r > maze.house.r0 and r < maze.house.r1 and c > maze.house.c0 and c < maze.house.c1
				if not (in_house and not include_house):
					list.append(Vector2i(r, c))
			c += 2
		r += 2
	return list

func neighbors_of(maze: Maze, r: int, c: int) -> Array:
	var out := []
	var left_c := (maze.cols - 1) if c == 0 else c - 1
	var right_c := 0 if c == maze.cols - 1 else c + 1
	var candidates := [Vector2i(r - 1, c), Vector2i(r + 1, c), Vector2i(r, left_c), Vector2i(r, right_c)]
	for cand in candidates:
		if is_open(maze, cand.x, cand.y):
			out.append(cand)
	return out

func bfs(maze: Maze, start_r: int, start_c: int) -> Array:
	var dist := []
	for r in range(maze.rows):
		var row := []
		row.resize(maze.cols)
		row.fill(-1)
		dist.append(row)
	if not is_open(maze, start_r, start_c):
		return dist
	dist[start_r][start_c] = 0
	var queue := [Vector2i(start_r, start_c)]
	var qi := 0
	while qi < queue.size():
		var cur: Vector2i = queue[qi]
		qi += 1
		for n in neighbors_of(maze, cur.x, cur.y):
			if dist[n.x][n.y] == -1:
				dist[n.x][n.y] = dist[cur.x][cur.y] + 1
				queue.append(n)
	return dist

func connectivity_check(maze: Maze) -> Dictionary:
	var rooms := cells_in_room(maze, true)
	if rooms.is_empty():
		return {"total": 0, "unreachable": 0, "ok": true}
	var start: Vector2i = rooms[0]
	var dist := bfs(maze, start.x, start.y)
	var unreachable := 0
	for cell in rooms:
		if dist[cell.x][cell.y] == -1:
			unreachable += 1
	return {"total": rooms.size(), "unreachable": unreachable, "ok": unreachable == 0}


## Same as neighbors_of/bfs/connectivity_check above, but the column-wrap
## tunnel neighbor is never counted as a connection — used to prove the
## maze's left and right halves are connected by the maze's own geometry
## (see the mid-column breach carved above) and not merely by the single
## wrap-tunnel row, which `connectivity_check` would otherwise credit as a
## real path (see review findings GD-W4/Code-W9).
func neighbors_of_no_wrap(maze: Maze, r: int, c: int) -> Array:
	var out := []
	var candidates := []
	if c > 0:
		candidates.append(Vector2i(r, c - 1))
	if c < maze.cols - 1:
		candidates.append(Vector2i(r, c + 1))
	candidates.append(Vector2i(r - 1, c))
	candidates.append(Vector2i(r + 1, c))
	for cand in candidates:
		if is_open(maze, cand.x, cand.y):
			out.append(cand)
	return out


func bfs_no_wrap(maze: Maze, start_r: int, start_c: int) -> Array:
	var dist := []
	for r in range(maze.rows):
		var row := []
		row.resize(maze.cols)
		row.fill(-1)
		dist.append(row)
	if not is_open(maze, start_r, start_c):
		return dist
	dist[start_r][start_c] = 0
	var queue := [Vector2i(start_r, start_c)]
	var qi := 0
	while qi < queue.size():
		var cur: Vector2i = queue[qi]
		qi += 1
		for n in neighbors_of_no_wrap(maze, cur.x, cur.y):
			if dist[n.x][n.y] == -1:
				dist[n.x][n.y] = dist[cur.x][cur.y] + 1
				queue.append(n)
	return dist


func connectivity_check_no_wrap(maze: Maze) -> Dictionary:
	var rooms := cells_in_room(maze, true)
	if rooms.is_empty():
		return {"total": 0, "unreachable": 0, "ok": true}
	var start: Vector2i = rooms[0]
	var dist := bfs_no_wrap(maze, start.x, start.y)
	var unreachable := 0
	for cell in rooms:
		if dist[cell.x][cell.y] == -1:
			unreachable += 1
	return {"total": rooms.size(), "unreachable": unreachable, "ok": unreachable == 0}
