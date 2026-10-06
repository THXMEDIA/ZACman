extends RefCounted
## TokyoMaze — the Explorer city "Tokyo": a coarse grid approximation of the
## area around a big scramble crossing in front of a station (Shibuya as the
## mood reference, docs/design/tokyo-explorer.md). Hand-authored, built to
## the same Maze shape MazeGen produces (grid/rows/cols/house/door_col/
## tunnel_row) so MazeView and Main drive it like Manhattan.
##
## Layout (1 cell = MazeView.CELL = 2 m, row = south, col = east):
##   rows 0-2      station building across the whole north edge; the subway
##                 exit (地下鉄) sits in its facade, the way into a speedrun
##   rows 3-5      station-front plaza (pedestrian, no curb)
##   cols 20-26    north-south avenue: 1 sidewalk cell, 5 road cells, 1 sidewalk
##   rows 20-26    east-west avenue, same profile
##   crossing      rows 20-26 x cols 20-26: one open 7x7 field (the scramble)
##   alleys        3 cells wide: NW (cols 8-10), NE (cols 36-38), SE (cols
##                 36-38 south of the avenue), SW (rows 34-36)
## Everything else is a building block. Blocks are whole rectangles of wall
## cells; with CityTheme.wall_footprint_scale 1.0 their collision is exactly
## their outline, which is where the neon base line (Sockellinie) is drawn.
##
## No real brands, logos or landmark replicas: the round tower is an
## octagon with a slanted crown (not a cylinder with a sign pillar), there is
## no statue at the meeting point, the signs are plain generic words.

const MazeGenScript := preload("res://scripts/maze_gen.gd")

const ROWS := 47
const COLS := 47

## The open crossing field (inclusive cell rect) and the road part of it.
const CROSSING := {"r0": 20, "c0": 20, "r1": 26, "c1": 26}
const CROSSING_ROAD := {"r0": 21, "c0": 21, "r1": 25, "c1": 25}
## The subway exit: the plaza cell in front of the station facade.
const METRO_CELL := Vector2i(3, 23)
## Start on the southern avenue, looking north over the crossing to the station.
const START_CELL := Vector2i(42, 23)

## Open areas (inclusive cell rects). `road` = the cells between the curbs
## along the street's cross axis (avenues only), `center` = the center line
## the pellet trails follow.
const STREETS := [
	{"id": "plaza", "axis": "ew", "r0": 3, "c0": 1, "r1": 5, "c1": 45, "center": 4},
	{"id": "allee_nord", "axis": "ns", "r0": 6, "c0": 20, "r1": 19, "c1": 26, "center": 23, "road": [21, 25]},
	{"id": "allee_sued", "axis": "ns", "r0": 27, "c0": 20, "r1": 45, "c1": 26, "center": 23, "road": [21, 25]},
	{"id": "allee_west", "axis": "ew", "r0": 20, "c0": 1, "r1": 26, "c1": 19, "center": 23, "road": [21, 25]},
	{"id": "allee_ost", "axis": "ew", "r0": 20, "c0": 27, "r1": 26, "c1": 45, "center": 23, "road": [21, 25]},
	{"id": "kreuzung", "axis": "x", "r0": 20, "c0": 20, "r1": 26, "c1": 26, "center": 23},
	{"id": "gasse_nw", "axis": "ns", "r0": 6, "c0": 8, "r1": 19, "c1": 10, "center": 9},
	{"id": "gasse_no", "axis": "ns", "r0": 6, "c0": 36, "r1": 19, "c1": 38, "center": 37},
	{"id": "gasse_sw", "axis": "ew", "r0": 34, "c0": 1, "r1": 36, "c1": 19, "center": 35},
	{"id": "gasse_so", "axis": "ns", "r0": 27, "c0": 36, "r1": 45, "c1": 38, "center": 37},
]

## Building blocks (inclusive cell rects), height in m, line color role
## ("amber" | "weiss"), and what the scenery builder puts on top or in front.
const BUILDINGS := [
	{"id": "bahnhof", "r0": 0, "c0": 0, "r1": 2, "c1": 46, "h": 9.0, "col": "weiss", "kind": "station"},
	{"id": "nw_block", "r0": 6, "c0": 0, "r1": 19, "c1": 7, "h": 17.0, "col": "weiss"},
	{"id": "rundturm_sockel", "r0": 6, "c0": 11, "r1": 19, "c1": 19, "h": 5.0, "col": "amber", "kind": "octagon_tower"},
	{"id": "nordturm", "r0": 6, "c0": 27, "r1": 19, "c1": 35, "h": 20.0, "col": "amber", "kind": "screen_tower"},
	{"id": "skydeck_block", "r0": 6, "c0": 39, "r1": 19, "c1": 46, "h": 26.0, "col": "weiss", "kind": "skydeck"},
	{"id": "sw_block", "r0": 27, "c0": 0, "r1": 33, "c1": 19, "h": 14.0, "col": "amber"},
	{"id": "sw_block_sued", "r0": 37, "c0": 0, "r1": 46, "c1": 19, "h": 20.0, "col": "weiss"},
	{"id": "so_block", "r0": 27, "c0": 27, "r1": 46, "c1": 35, "h": 18.0, "col": "amber"},
	{"id": "so_block_ost", "r0": 27, "c0": 39, "r1": 46, "c1": 46, "h": 12.0, "col": "weiss"},
	# Thin edge buildings closing the streets at the map border.
	{"id": "rand_plaza_w", "r0": 3, "c0": 0, "r1": 5, "c1": 0, "h": 12.0, "col": "weiss", "kind": "edge"},
	{"id": "rand_plaza_o", "r0": 3, "c0": 46, "r1": 5, "c1": 46, "h": 12.0, "col": "weiss", "kind": "edge"},
	{"id": "rand_allee_w", "r0": 20, "c0": 0, "r1": 26, "c1": 0, "h": 16.0, "col": "amber", "kind": "edge"},
	{"id": "rand_allee_o", "r0": 20, "c0": 46, "r1": 26, "c1": 46, "h": 16.0, "col": "amber", "kind": "edge"},
	{"id": "rand_allee_s", "r0": 46, "c0": 20, "r1": 46, "c1": 26, "h": 14.0, "col": "weiss", "kind": "edge"},
	{"id": "rand_gasse_sw", "r0": 34, "c0": 0, "r1": 36, "c1": 0, "h": 10.0, "col": "amber", "kind": "edge"},
	{"id": "rand_gasse_so", "r0": 46, "c0": 36, "r1": 46, "c1": 38, "h": 10.0, "col": "amber", "kind": "edge"},
]

## The pellet trail network: the center lines of plaza, avenues and alleys
## ([fixed row or col, from, to] in cells), and the trail ends a level seed
## chooses from. The trails always converge on the subway exit.
const TRAIL_LINES := [
	{"row": 4, "from": 1, "to": 45},
	{"col": 23, "from": 3, "to": 45},
	{"row": 23, "from": 1, "to": 45},
	{"col": 9, "from": 4, "to": 23},
	{"col": 37, "from": 4, "to": 45},
	{"row": 35, "from": 1, "to": 23},
]
const TRAIL_ENDS := [Vector2i(4, 1), Vector2i(4, 45), Vector2i(23, 1), Vector2i(23, 45), Vector2i(45, 23), Vector2i(35, 1), Vector2i(45, 37)]
## How many trail ends (besides the start) carry pellets in one level.
const TRAIL_COUNT := 4


## The building block id at a wall cell ("" for open cells) — used as the
## landmark provider so MazeView gives every cell of a block its height
## (CityTheme.landmark_heights, see city_themes.gd tokyo()).
static func landmark_at(row: int, col: int) -> String:
	var b := building_at(row, col)
	return b.get("id", "")


static func building_at(row: int, col: int) -> Dictionary:
	for b in BUILDINGS:
		if row >= b.r0 and row <= b.r1 and col >= b.c0 and col <= b.c1:
			return b
	return {}


static func building_heights() -> Dictionary:
	var out := {}
	for b in BUILDINGS:
		out[b.id] = b.h
	return out


static func metro_cells() -> Array:
	return [METRO_CELL]


static func in_rect(cell: Vector2i, rect: Dictionary) -> bool:
	return cell.x >= rect.r0 and cell.x <= rect.r1 and cell.y >= rect.c0 and cell.y <= rect.c1


func generate() -> MazeGenScript.Maze:
	var maze: MazeGenScript.Maze = MazeGenScript.Maze.new()
	maze.rows = ROWS
	maze.cols = COLS
	var grid := []
	for r in ROWS:
		var row := []
		row.resize(COLS)
		row.fill(0)
		grid.append(row)
	for b in BUILDINGS:
		for r in range(b.r0, b.r1 + 1):
			for c in range(b.c0, b.c1 + 1):
				grid[r][c] = 1
	maze.grid = grid
	# No ghosts and no side tunnel: the house lies outside the grid (nothing is
	# ever "inside" it), the closed border makes the tunnel wrap unreachable.
	maze.house = {"r0": -100, "r1": -100, "c0": -100, "c1": -100, "mid": -100}
	maze.door_col = -1
	maze.tunnel_row = -1
	maze.start_cell = START_CELL
	return maze


## Network cells of the trail lines (Dictionary used as a set).
static func trail_network() -> Dictionary:
	var net := {}
	for l in TRAIL_LINES:
		for i in range(l.from, l.to + 1):
			var cell := Vector2i(l.row, i) if l.has("row") else Vector2i(i, l.col)
			net[cell] = true
	return net


## The wayfinding pellets (CityTheme.pellet_trail_provider_script): BFS from
## the subway exit over the center-line network, then the walked-back paths
## from the start and TRAIL_COUNT trail ends the level seed picks. Every cell
## of a path carries a pellet (2 m apart), so each trail is an unbroken gold
## line that ends at the subway. Deterministic per seed.
static func trail_cells(maze, metro: Array, start_cell: Vector2i, seed: int) -> Array:
	var net := trail_network()
	var came_from := {}
	var visited := {}
	var queue: Array = []
	for m in metro:
		visited[m] = true
		queue.append(m)
	var qi := 0
	while qi < queue.size():
		var cur: Vector2i = queue[qi]
		qi += 1
		for d in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
			var n: Vector2i = cur + d
			if visited.has(n) or not net.has(n):
				continue
			if n.x < 0 or n.x >= maze.rows or n.y < 0 or n.y >= maze.cols or maze.grid[n.x][n.y] != 0:
				continue
			visited[n] = true
			came_from[n] = cur
			queue.append(n)

	var ends: Array = TRAIL_ENDS.duplicate()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	for i in range(ends.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = ends[i]
		ends[i] = ends[j]
		ends[j] = tmp
	var seeds: Array = ends.slice(0, TRAIL_COUNT)
	if net.has(start_cell):
		seeds.push_front(start_cell)

	var on_trail := {}
	var out: Array = []
	for s in seeds:
		var cur: Vector2i = s
		var guard := 0
		while came_from.has(cur) and guard < maze.rows * maze.cols:
			if not on_trail.has(cur):
				on_trail[cur] = true
				out.append(cur)
			cur = came_from[cur]
			guard += 1
	return out
