extends RefCounted
## AmsterdamMaze — the Explorer city "Amsterdam": the canal ring as a 1:100
## cardboard architecture model, look "Pappmodell, Abend" (direction J,
## owner decision E21, docs/design/amsterdam-explorer.md). Same Maze shape as
## MazeGen (grid/rows/cols/house/door_col/tunnel_row), so MazeView and Main
## drive it like Kyoto. Hand-authored; real places, freely rearranged so the
## way to the exit runs past all three landmarks:
##   Damrak          the northern canal: the leaning gable row ("dancing
##                   houses") stands right on the water, seen across it from
##                   the Damrak quay where the player starts (looking west)
##   Westermarkt     the square in front of the Westerkerk; its tower closes
##                   the Damrak axis and is the tallest thing in the model.
##                   The Damrak quay only opens to the Westermarkt, and the
##                   Prinsengracht is only crossed there, so the way passes
##                   the church (Kyoto review lesson)
##   Keizersgracht   the middle canal with two quays and three bridges
##   Prinsengracht   the southern canal; its south quay runs straight onto the
##   Magere Brug     the white drawbridge over the Amstel (the only crossing),
##                   east of it the tram stop with the green exit tram
##
## 1 cell = MazeView.CELL = 2 m, row = south (z), col = east (x).
## Cell kinds (cell_kind): "street", "bridge" (open), "water", "block",
## "church", "tram" (walls). Water cells are walls with a water look below
## street level; the quay edge is the collision edge.

const MazeGenScript := preload("res://scripts/maze_gen.gd")

const ROWS := 49
const COLS := 49

## The exit: the platform cell next to the tram doors.
const METRO_CELL := Vector2i(32, 44)
## Start on the Damrak quay, looking west: dancing houses to the right across
## the water, the Westerkerk tower at the end of the quay.
const START_CELL := Vector2i(12, 28)

## Water: canals (rows, cols inclusive) and the Amstel (cols). Bridges are
## open cells inside the water (BRIDGES).
const WATER := [
	{"id": "damrak", "r0": 7, "c0": 10, "r1": 10, "c1": 41},
	{"id": "keizersgracht", "r0": 22, "c0": 0, "r1": 25, "c1": 41},
	{"id": "prinsengracht", "r0": 37, "c0": 0, "r1": 40, "c1": 41},
	{"id": "amstel", "r0": 0, "c0": 36, "r1": 48, "c1": 41},
]

## Open streets (inclusive cell rects); `center` is the line the pins follow.
const STREETS := [
	{"id": "damrak_kade", "axis": "ew", "r0": 11, "c0": 7, "r1": 13, "c1": 35, "center": 12},
	{"id": "westermarkt", "axis": "ns", "r0": 7, "c0": 7, "r1": 43, "c1": 9, "center": 8},
	{"id": "keizers_nord", "axis": "ew", "r0": 19, "c0": 7, "r1": 21, "c1": 35, "center": 20},
	{"id": "keizers_sued", "axis": "ew", "r0": 26, "c0": 7, "r1": 28, "c1": 35, "center": 27},
	{"id": "prinsen_nord", "axis": "ew", "r0": 34, "c0": 7, "r1": 36, "c1": 35, "center": 35},
	{"id": "prinsen_sued", "axis": "ew", "r0": 41, "c0": 7, "r1": 43, "c1": 35, "center": 42},
	{"id": "gasse_west", "axis": "ns", "r0": 29, "c0": 14, "r1": 33, "c1": 15, "center": 14},
	{"id": "gasse_mitte", "axis": "ns", "r0": 29, "c0": 25, "r1": 33, "c1": 26, "center": 25},
	{"id": "amstel_oost", "axis": "ns", "r0": 28, "c0": 42, "r1": 43, "c1": 44, "center": 43},
]

## Bridges: open cells inside the water. "magere_brug" is the white drawbridge.
const BRIDGES := [
	{"id": "westermarkt_keizers", "r0": 22, "c0": 7, "r1": 25, "c1": 9, "axis": "ns"},
	{"id": "westermarkt_prinsen", "r0": 37, "c0": 7, "r1": 40, "c1": 9, "axis": "ns"},
	{"id": "keizers_west", "r0": 22, "c0": 18, "r1": 25, "c1": 20, "axis": "ns"},
	{"id": "keizers_ost", "r0": 22, "c0": 29, "r1": 25, "c1": 31, "axis": "ns"},
	{"id": "magere_brug", "r0": 41, "c0": 36, "r1": 43, "c1": 41, "axis": "ew"},
]

## Landmark blocks (wall cells, no generic houses): the Westerkerk faces the
## Westermarkt (face +x); the tram stop lies east of the platform.
const LANDMARKS := [
	{"id": "westerkerk", "kind": "church", "r0": 4, "c0": 0, "r1": 18, "c1": 6, "face": Vector2(1, 0)},
	{"id": "tram", "kind": "tram", "r0": 28, "c0": 45, "r1": 36, "c1": 46, "face": Vector2(-1, 0)},
]

## Westerkerk tower: centre (world x, z) on the Damrak quay axis, height (m).
## Its 7 m base stands flush with the church front on the Westermarkt (x 13).
const TOWER_X := 9.5
const TOWER_Z := 24.0
const TOWER_H := 62.0

## The leaning gable row on the Damrak (world x range of the strongest lean).
const DANCING_X0 := 26.0
const DANCING_X1 := 62.0

## Collision height of every wall box (m; CityTheme wall_height_min/max). The
## wall MultiMesh is not drawn (CityTheme.walls_visible = false): houses,
## quays and water are the scenery; this is only physics.
const WALL_H := 3.0

const TRAIL_LINES := [
	{"row": 12, "from": 8, "to": 35},
	{"col": 8, "from": 8, "to": 42},
	{"row": 20, "from": 8, "to": 35},
	{"row": 27, "from": 8, "to": 35},
	{"row": 35, "from": 8, "to": 35},
	{"row": 42, "from": 8, "to": 43},
	{"col": 43, "from": 28, "to": 42},
	{"col": 19, "from": 20, "to": 27},
	{"col": 30, "from": 20, "to": 27},
	{"col": 14, "from": 27, "to": 35},
	{"col": 25, "from": 27, "to": 35},
]
## The Westermarkt north end (the canal end in front of the church) always
## carries pins; the level seed picks TRAIL_COUNT more ends from TRAIL_ENDS.
const MUST_ENDS := [Vector2i(8, 8)]
const TRAIL_ENDS := [Vector2i(12, 35), Vector2i(20, 35), Vector2i(27, 35), Vector2i(35, 35), Vector2i(28, 43), Vector2i(31, 25)]
const TRAIL_COUNT := 2


static func _in(r: int, c: int, b: Dictionary) -> bool:
	return r >= b.r0 and r <= b.r1 and c >= b.c0 and c <= b.c1


static func street_at(row: int, col: int) -> Dictionary:
	for s in STREETS:
		if _in(row, col, s):
			return s
	return {}


static func bridge_at(row: int, col: int) -> Dictionary:
	for b in BRIDGES:
		if _in(row, col, b):
			return b
	return {}


static func water_at(row: int, col: int) -> Dictionary:
	for w in WATER:
		if _in(row, col, w):
			return w
	return {}


static func landmark_block_at(row: int, col: int) -> Dictionary:
	for b in LANDMARKS:
		if _in(row, col, b):
			return b
	return {}


## "street" | "bridge" | "water" | "block" | "church" | "tram"; outside the
## map: "outside".
static func cell_kind(row: int, col: int) -> String:
	if row < 0 or row >= ROWS or col < 0 or col >= COLS:
		return "outside"
	if not bridge_at(row, col).is_empty():
		return "bridge"
	if not street_at(row, col).is_empty():
		return "street"
	if not water_at(row, col).is_empty():
		return "water"
	var lm := landmark_block_at(row, col)
	if not lm.is_empty():
		return lm.kind
	return "block"


static func is_open_kind(k: String) -> bool:
	return k == "street" or k == "bridge"


static var _water_cache := PackedByteArray()


## Minimap hook (CityTheme.minimap_water_script); cached, the HUD asks every
## frame for every wall cell.
static func is_water(row: int, col: int) -> bool:
	if row < 0 or row >= ROWS or col < 0 or col >= COLS:
		return false
	if _water_cache.is_empty():
		_water_cache.resize(ROWS * COLS)
		for r in ROWS:
			for c in COLS:
				_water_cache[r * COLS + c] = 1 if cell_kind(r, c) == "water" else 0
	return _water_cache[row * COLS + col] == 1


## The base plate is everything that is not canal (water or bridge).
static func is_plate(row: int, col: int) -> bool:
	var k := cell_kind(row, col)
	return k != "water" and k != "bridge" and k != "outside"


static func is_house_kind(k: String) -> bool:
	return k == "block" or k == "church" or k == "tram"


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
		for c in COLS:
			row[c] = 0 if is_open_kind(cell_kind(r, c)) else 1
		grid.append(row)
	maze.grid = grid
	# No ghosts, no side tunnel (same as Tokyo and Kyoto).
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


## Wayfinding pins: BFS from the exit over the street centre lines, then the
## walked-back paths from the start, the must ends and TRAIL_COUNT seeded
## trail ends — unbroken blue lines that all end at the tram. Deterministic
## per seed.
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
