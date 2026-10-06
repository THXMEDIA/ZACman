extends RefCounted
## KyotoMaze — the Explorer city "Kyoto": Gion and Higashiyama as a coarse
## grid, look "Aizuri-Pop-up" (docs/design/kyoto-explorer.md). Same Maze shape
## as MazeGen (grid/rows/cols/house/door_col/tunnel_row), so MazeView and Main
## drive it like Tokyo. Hand-authored; real places, freely rearranged so every
## street ends on a landmark:
##   Shijo-dori      the wide east-west street; west end the theatre by the
##                   river (Minami-za as reference), east end the vermilion
##                   west gate of Yasaka shrine (Nishi-romon)
##   Hanamikoji      the tea-house street running south from Shijo, ending at
##                   the temple gate of Kennin-ji
##   Yasaka-dori     narrow lane ending on the five-storey Yasaka pagoda
##   Ninenzaka       the slope lane up to Kiyomizu-dera; the exit (green
##                   bookmark + page door) sits at the foot of its stage. Its
##                   middle is a temple precinct (closed), so the way to the
##                   exit runs down Hanamikoji and along Sannenzaka, past the
##                   pagoda lane and the torii lane (game-design review K1)
##   Torii lane      a tunnel of torii gates (Fushimi Inari as reference),
##                   ending at a small shrine
## Kyoto Tower and the Higashiyama hills stand outside the map as backdrop.
##
## 1 cell = MazeView.CELL = 2 m, row = south (z), col = east (x).
## Every cell not in a street is a wall (a block of the pop-up book).

const MazeGenScript := preload("res://scripts/maze_gen.gd")

const ROWS := 45
const COLS := 49

## The exit: the lane cell in front of Kiyomizu's stage.
const METRO_CELL := Vector2i(41, 44)
## Start at the west end of Shijo-dori, the theatre behind, the shrine gate ahead.
const START_CELL := Vector2i(10, 3)

## Open streets (inclusive cell rects); `center` is the line the pellets follow.
const STREETS := [
	{"id": "shijo", "axis": "ew", "r0": 8, "c0": 1, "r1": 12, "c1": 47, "center": 10},
	{"id": "hanamikoji_nord", "axis": "ns", "r0": 1, "c0": 22, "r1": 7, "c1": 24, "center": 23},
	{"id": "hanamikoji", "axis": "ns", "r0": 13, "c0": 22, "r1": 43, "c1": 24, "center": 23},
	{"id": "seitengasse", "axis": "ew", "r0": 20, "c0": 1, "r1": 22, "c1": 42, "center": 21},
	{"id": "yasaka_dori", "axis": "ew", "r0": 30, "c0": 25, "r1": 32, "c1": 36, "center": 31},
	{"id": "sannenzaka", "axis": "ew", "r0": 36, "c0": 25, "r1": 38, "c1": 42, "center": 37},
	{"id": "ninenzaka_nord", "axis": "ns", "r0": 13, "c0": 43, "r1": 23, "c1": 45, "center": 44},
	{"id": "ninenzaka", "axis": "ns", "r0": 36, "c0": 43, "r1": 41, "c1": 45, "center": 44},
	{"id": "torii_gasse", "axis": "ew", "r0": 38, "c0": 1, "r1": 40, "c1": 21, "center": 39},
]

## Landmarks: the wall cells (inclusive rect) whose street facade is a single
## large pop-up instead of a row of houses. `face` = outward normal of the
## facade (into the street), `at` = the street-side cell rect it faces.
const LANDMARKS := [
	{"id": "theater", "r0": 8, "c0": 0, "r1": 12, "c1": 0, "face": Vector2(1, 0)},
	{"id": "nishiromon", "r0": 8, "c0": 48, "r1": 12, "c1": 48, "face": Vector2(-1, 0)},
	{"id": "kenninji", "r0": 44, "c0": 22, "r1": 44, "c1": 24, "face": Vector2(0, -1)},
	{"id": "kiyomizu", "r0": 42, "c0": 40, "r1": 44, "c1": 48, "face": Vector2(0, -1)},
	{"id": "inari", "r0": 38, "c0": 0, "r1": 40, "c1": 0, "face": Vector2(1, 0)},
	{"id": "pagoda", "r0": 23, "c0": 37, "r1": 35, "c1": 42, "face": Vector2(-1, 0)},
	{"id": "ninenzaka_tor", "r0": 24, "c0": 43, "r1": 35, "c1": 45, "face": Vector2(0, -1)},
	{"id": "hanamikoji_tor", "r0": 0, "c0": 22, "r1": 0, "c1": 24, "face": Vector2(0, 1)},
	{"id": "seitengasse_tor", "r0": 20, "c0": 0, "r1": 22, "c1": 0, "face": Vector2(1, 0)},
]

## Wall height of the collision boxes (m; CityTheme wall_height_min/max). The
## blocks are drawn as a thin printed plan on the page (kyoto_slab.gdshader);
## this is only physics.
const WALL_H := 3.0

const TRAIL_LINES := [
	{"row": 10, "from": 1, "to": 47},
	{"col": 23, "from": 1, "to": 43},
	{"row": 21, "from": 1, "to": 44},
	{"row": 31, "from": 23, "to": 36},
	{"row": 37, "from": 23, "to": 44},
	{"row": 39, "from": 1, "to": 23},
	{"col": 44, "from": 10, "to": 23},
	{"col": 44, "from": 36, "to": 41},
]
## The torii lane and the pagoda lane always carry pellets (the highlights);
## the level seed picks TRAIL_COUNT more ends from TRAIL_ENDS.
const MUST_ENDS := [Vector2i(39, 1), Vector2i(31, 36)]
const TRAIL_ENDS := [Vector2i(10, 1), Vector2i(10, 47), Vector2i(1, 23), Vector2i(43, 23), Vector2i(21, 1), Vector2i(23, 44)]
const TRAIL_COUNT := 2


static func street_at(row: int, col: int) -> Dictionary:
	for s in STREETS:
		if row >= s.r0 and row <= s.r1 and col >= s.c0 and col <= s.c1:
			return s
	return {}


static func landmark_block_at(row: int, col: int) -> Dictionary:
	for b in LANDMARKS:
		if row >= b.r0 and row <= b.r1 and col >= b.c0 and col <= b.c1:
			return b
	return {}


## Landmark provider for MazeView: every wall cell gets the same collision
## height (CityTheme.landmark_default_height); no per-block words.
static func landmark_at(_row: int, _col: int) -> String:
	return ""


static func metro_cells() -> Array:
	return [METRO_CELL]


func generate() -> MazeGenScript.Maze:
	var maze: MazeGenScript.Maze = MazeGenScript.Maze.new()
	maze.rows = ROWS
	maze.cols = COLS
	var grid := []
	for r in ROWS:
		var row := []
		row.resize(COLS)
		row.fill(1)
		grid.append(row)
	for s in STREETS:
		for r in range(s.r0, s.r1 + 1):
			for c in range(s.c0, s.c1 + 1):
				grid[r][c] = 0
	maze.grid = grid
	# No ghosts, no side tunnel (same as Tokyo).
	maze.house = {"r0": -100, "r1": -100, "c0": -100, "c1": -100, "mid": -100}
	maze.door_col = -1
	maze.tunnel_row = -1
	maze.start_cell = START_CELL
	return maze


static func trail_network() -> Dictionary:
	var net := {}
	for l in TRAIL_LINES:
		for i in range(l.from, l.to + 1):
			var cell := Vector2i(l.row, i) if l.has("row") else Vector2i(i, l.col)
			net[cell] = true
	return net


## Wayfinding pellets: BFS from the exit over the street center lines, then
## the walked-back paths from the start and TRAIL_COUNT seeded trail ends —
## unbroken gold lines that all end at the exit. Deterministic per seed.
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
	var seeds: Array = MUST_ENDS + ends.slice(0, TRAIL_COUNT)
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
