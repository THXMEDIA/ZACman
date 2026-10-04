extends RefCounted
## ArlesMaze — the Explorer city "Arles": a starry night over real places of
## Arles, stylised and freely arranged (direction B v2 "Sternennacht, echte
## Orte stilisiert", owner decisions E19/E23, docs/design/arles-explorer.md).
## Same Maze shape as MazeGen (grid/rows/cols/house/door_col/tunnel_row), so
## MazeView and Main drive it like Kyoto and Amsterdam. The map is the art
## director's sketch (tools/art/explorer_proto/arles_v2/karte.json on the
## art branch); every street ends on a landmark or on the Rhône:
##   Rue de la Calade     start at its east end (Théâtre antique behind),
##                        west over the Place de la République to the
##                        Hôtel de Ville with its clock tower
##   Place de la République   portal of Saint-Trophime (south), obelisk
##   Rue de l'Hôtel de Ville  north, frontal onto the café terrace
##   Place du Forum       café terrace (north, no name, no sign), two Roman
##                        columns in the house corner, the Mistral monument
##   Rue du Forum         east: the arena's west tower; west: the Rhône
##   Quai (Rhône)         50 m along the parapet with the mirrored lamps,
##                        south end: Grand Prieuré
##   Seitengasse          ends on the apse of the Constantine baths
##   Place Lamartine      the Yellow House with the green door = EXIT, the
##                        green star above it; east: Porte de la Cavalerie
##   Rue de la Cavalerie  north: rampart tower; south: the arena ring
##   Rond-point des Arènes    the ring round the amphitheatre (must branch)
## Not in the city: Pont de Langlois, Alyscamps (owner decision).
##
## 1 cell = MazeView.CELL = 2 m, row = south (z), col = east (x). Map space
## (the prototype's coordinates, used by arles_scenery.gd and the shaders) is
## world + (1, 0, 1): cell (r, c) spans map x 2c..2c+2, z 2r..2r+2.

const MazeGenScript := preload("res://scripts/maze_gen.gd")

const ROWS := 41
const COLS := 45

## The exit: the cell in front of the green door of the Yellow House.
const METRO_CELL := Vector2i(1, 7)
## Start at the east end of the Rue de la Calade, looking west.
const START_CELL := Vector2i(35, 32)

## Open streets (inclusive cell rects), from karte.json.
const STREETS := [
	{"id": "place_lamartine", "r0": 1, "c0": 1, "r1": 7, "c1": 17},
	{"id": "porte_cavalerie", "r0": 3, "c0": 18, "r1": 5, "c1": 23},
	{"id": "rue_cavalerie", "r0": 1, "c0": 24, "r1": 11, "c1": 26},
	{"id": "rond_point_nord", "r0": 12, "c0": 24, "r1": 14, "c1": 43},
	{"id": "rond_point_sued", "r0": 30, "c0": 24, "r1": 32, "c1": 43},
	{"id": "rond_point_west", "r0": 12, "c0": 24, "r1": 32, "c1": 26},
	{"id": "rond_point_ost", "r0": 12, "c0": 41, "r1": 32, "c1": 43},
	{"id": "quai", "r0": 1, "c0": 1, "r1": 34, "c1": 4},
	{"id": "seitengasse", "r0": 9, "c0": 5, "r1": 10, "c1": 15},
	{"id": "rue_forum", "r0": 19, "c0": 5, "r1": 21, "c1": 23},
	{"id": "place_forum", "r0": 15, "c0": 8, "r1": 25, "c1": 18},
	{"id": "rue_hotel_de_ville", "r0": 26, "c0": 12, "r1": 31, "c1": 14},
	{"id": "place_republique", "r0": 32, "c0": 8, "r1": 37, "c1": 20},
	{"id": "rue_calade", "r0": 34, "c0": 21, "r1": 36, "c1": 33},
]

## Landmark blocks (wall cells drawn as one landmark instead of houses).
## `gate`: the street cells inside stay open (the passage of the gate).
const LANDMARKS := [
	{"id": "maison_jaune", "r0": 0, "c0": 5, "r1": 0, "c1": 9},
	{"id": "porte_cavalerie", "r0": 1, "c0": 18, "r1": 7, "c1": 23, "gate": true},
	{"id": "remparts", "r0": 0, "c0": 24, "r1": 0, "c1": 26},
	{"id": "arenes", "r0": 15, "c0": 27, "r1": 29, "c1": 40},
	{"id": "thermes", "r0": 8, "c0": 16, "r1": 11, "c1": 17},
	{"id": "cafe", "r0": 13, "c0": 11, "r1": 14, "c1": 15},
	{"id": "colonnes_forum", "r0": 14, "c0": 7, "r1": 14, "c1": 8},
	{"id": "hotel_de_ville", "r0": 32, "c0": 7, "r1": 37, "c1": 7},
	{"id": "saint_trophime", "r0": 38, "c0": 11, "r1": 40, "c1": 16},
	{"id": "theatre_antique", "r0": 33, "c0": 34, "r1": 37, "c1": 36},
	{"id": "grand_prieure", "r0": 35, "c0": 1, "r1": 36, "c1": 4},
]

## The quay parapet: column 0 between these rows; the Rhône lies beyond.
const PARAPET_COL := 0
const PARAPET_R0 := 1
const PARAPET_R1 := 34

## Collision height of every wall box (m; CityTheme wall_height_min/max). The
## wall MultiMesh is not drawn (CityTheme.walls_visible = false): houses,
## landmarks and the parapet are the scenery; this is only physics.
const WALL_H := 3.0

const TRAIL_LINES := [
	{"row": 35, "from": 9, "to": 32},
	{"col": 13, "from": 20, "to": 35},
	{"row": 20, "from": 3, "to": 25},
	{"col": 3, "from": 4, "to": 33},
	{"row": 4, "from": 3, "to": 25},
	{"col": 7, "from": 1, "to": 4},
	{"col": 25, "from": 2, "to": 31},
	{"row": 13, "from": 25, "to": 42},
	{"row": 31, "from": 25, "to": 42},
	{"col": 42, "from": 13, "to": 31},
	{"row": 9, "from": 3, "to": 15},
]
## The whole arena ring and the lane to the baths always carry pellets (the
## must branches of the art director's map); the level seed picks
## TRAIL_COUNT more ends from TRAIL_ENDS.
const MUST_ENDS := [Vector2i(13, 42), Vector2i(31, 42), Vector2i(9, 15)]
const TRAIL_ENDS := [Vector2i(33, 3), Vector2i(2, 25), Vector2i(35, 9), Vector2i(20, 25)]
const TRAIL_COUNT := 2
## The ring round the arena is a round walk: always all of it.
const MUST_LINES := [
	{"row": 13, "from": 25, "to": 42},
	{"row": 31, "from": 25, "to": 42},
	{"col": 42, "from": 13, "to": 31},
	{"col": 25, "from": 13, "to": 31},
]

## The way the pellets lead, street by street (test and design doc).
const ROUTE := ["rue_calade", "place_republique", "rue_hotel_de_ville", "place_forum", "rue_forum", "quai", "place_lamartine"]


static func _in(r: int, c: int, b: Dictionary) -> bool:
	return r >= b.r0 and r <= b.r1 and c >= b.c0 and c <= b.c1


static func street_at(row: int, col: int) -> Dictionary:
	for s in STREETS:
		if _in(row, col, s):
			return s
	return {}


static func landmark_block_at(row: int, col: int) -> Dictionary:
	for b in LANDMARKS:
		if _in(row, col, b):
			return b
	return {}


static func is_parapet(row: int, col: int) -> bool:
	return col == PARAPET_COL and row >= PARAPET_R0 and row <= PARAPET_R1


## "street" | "parapet" | "landmark" | "block"; outside the map: "outside".
static func cell_kind(row: int, col: int) -> String:
	if row < 0 or row >= ROWS or col < 0 or col >= COLS:
		return "outside"
	var lm := landmark_block_at(row, col)
	if not street_at(row, col).is_empty():
		if lm.is_empty() or lm.get("gate", false):
			return "street"
	if not lm.is_empty():
		return "landmark"
	if is_parapet(row, col):
		return "parapet"
	return "block"


static func is_open(row: int, col: int) -> bool:
	return cell_kind(row, col) == "street"


## Generic houses stand on these cells (not on landmarks, not on the quay).
static func is_house(row: int, col: int) -> bool:
	return cell_kind(row, col) == "block"


static var _water_cache := PackedByteArray()


## Minimap hook (CityTheme.minimap_water_script): the parapet column, with
## the Rhône beyond, in its own colour.
static func is_water(row: int, col: int) -> bool:
	if row < 0 or row >= ROWS or col < 0 or col >= COLS:
		return false
	if _water_cache.is_empty():
		_water_cache.resize(ROWS * COLS)
		for r in ROWS:
			for c in COLS:
				_water_cache[r * COLS + c] = 1 if is_parapet(r, c) else 0
	return _water_cache[row * COLS + col] == 1


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
			row[c] = 0 if is_open(r, c) else 1
		grid.append(row)
	maze.grid = grid
	# No ghosts, no side tunnel (same as the other explorer cities).
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


## Wayfinding pellets: BFS from the exit over the street centre lines, then
## the walked-back paths from the start, the must ends and TRAIL_COUNT seeded
## trail ends — unbroken vermilion lines that all end at the green door.
## Deterministic per seed.
static func trail_cells(maze, metro: Array, start_cell: Vector2i, seed: int) -> Array:
	var came_from := route_tree(maze, metro)
	var ends: Array = TRAIL_ENDS.duplicate()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	for i in range(ends.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = ends[i]
		ends[i] = ends[j]
		ends[j] = tmp
	var seeds: Array = MUST_ENDS + ends.slice(0, TRAIL_COUNT)
	if trail_network().has(start_cell):
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
	for l in MUST_LINES:
		for i in range(l.from, l.to + 1):
			var cell := Vector2i(l.row, i) if l.has("row") else Vector2i(i, l.col)
			if came_from.has(cell) and not on_trail.has(cell):
				on_trail[cell] = true
				out.append(cell)
	return out


## BFS tree over the trail network, rooted at the exit: cell -> next cell
## towards the exit.
static func route_tree(maze, metro: Array) -> Dictionary:
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
	return came_from


## The way along the pellets from the start to the exit (cells, both ends
## included).
static func route(maze) -> Array:
	var tree := route_tree(maze, metro_cells())
	var out: Array = [START_CELL]
	var cur: Vector2i = START_CELL
	while tree.has(cur):
		cur = tree[cur]
		out.append(cur)
	return out
