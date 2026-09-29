extends Node
## ManhattanMaze — the speedrun bonus level: a hand-authored grid of real
## Midtown Manhattan avenues and streets, in their real west-to-east /
## south-to-north order, built to the same Maze "shape" (grid/rows/cols/
## house/door_col/tunnel_row) that MazeGen produces so MazeView, Enemy and
## Main can drive it with zero special-casing.
##
## Not procedurally generated and not a live OSM/Overpass fetch (this
## sandbox cannot reach Overpass — see the ReclaimTheStreets project for a
## live-data pipeline at tools/osm_to_chunks.py, which the Godot desktop
## build can still run locally against real map data later). Instead this
## is the real Midtown grid itself: unlike the other levels it's not a maze
## with dead ends — Manhattan's avenues and streets are (almost) fully
## connected at every intersection, and that openness is the point: it's a
## deliberately different, faster, more exposed bonus level, not a bigger
## version of the same labyrinth.

## West -> east.
const AVENUES := [
	"12th Ave", "11th Ave", "10th Ave", "9th Ave", "8th Ave", "7th Ave",
	"6th Ave", "5th Ave", "Madison Ave", "Park Ave", "Lexington Ave",
]

## South -> north (Midtown, 34th to 58th).
const STREETS := [
	"34th St", "36th St", "38th St", "40th St", "42nd St", "44th St",
	"46th St", "48th St", "50th St", "52nd St", "54th St", "56th St", "58th St",
]

## Grand Central Terminal, at Park Ave & 42nd St, doubles as the ghost house.
const HOUSE_AVENUE_INDEX := 9 # Park Ave
const HOUSE_STREET_INDEX := 4 # 42nd St
## Penn Station, at 7th Ave & 34th St, is the start point.
const START_AVENUE_INDEX := 5 # 7th Ave
const START_STREET_INDEX := 0 # 34th St

## Build directly on MazeGen's own Maze class (not a lookalike) so every
## MazeGen function (is_open/neighbors_of/bfs/connectivity_check, all typed
## `maze: Maze`) and every consumer (MazeView, Enemy, Main) accepts this
## with zero special-casing.
const MazeGenScript := preload("res://scripts/maze_gen.gd")


static func avenue_at(col: int) -> String:
	if col % 2 == 1 and col / 2 < AVENUES.size():
		return AVENUES[col / 2]
	return ""


static func street_at(row: int) -> String:
	if row % 2 == 1 and row / 2 < STREETS.size():
		return STREETS[row / 2]
	return ""


func generate() -> MazeGenScript.Maze:
	var maze: MazeGenScript.Maze = MazeGenScript.Maze.new()
	maze.rows = STREETS.size() * 2 + 1
	maze.cols = AVENUES.size() * 2 + 1

	var grid := []
	for r in range(maze.rows):
		var row := []
		row.resize(maze.cols)
		row.fill(1)
		grid.append(row)

	# Every intersection is open ...
	for si in STREETS.size():
		var r := si * 2 + 1
		for ai in AVENUES.size():
			var c := ai * 2 + 1
			grid[r][c] = 0

	# ... and so is every block face along a street (east-west travel) ...
	for si in STREETS.size():
		var r := si * 2 + 1
		for ai in range(AVENUES.size() - 1):
			grid[r][ai * 2 + 2] = 0

	# ... and along an avenue (north-south travel). Building interiors — the
	# even/even grid cells — are never touched, so they stay walls: that's
	# what turns an open grid of lines into walkable streets around solid
	# city blocks.
	for ai in AVENUES.size():
		var c := ai * 2 + 1
		for si in range(STREETS.size() - 1):
			grid[si * 2 + 2][c] = 0

	var house_r := HOUSE_STREET_INDEX * 2 + 1
	var house_c := HOUSE_AVENUE_INDEX * 2 + 1
	var house := {
		"r0": house_r - 2,
		"r1": house_r + 2,
		"c0": house_c - 2,
		"c1": house_c + 2,
		"mid": house_c,
	}
	for rr in range(house.r0 + 1, house.r1):
		for cc in range(house.c0 + 1, house.c1):
			grid[rr][cc] = 0
	var door_col: int = house_c
	grid[house.r0][door_col] = 0

	var tunnel_row := 1 # 34th St — the crosstown tunnel row, like the other levels' edge tunnel.
	grid[tunnel_row][0] = 0
	grid[tunnel_row][1] = 0
	grid[tunnel_row][maze.cols - 1] = 0
	grid[tunnel_row][maze.cols - 2] = 0

	maze.grid = grid
	maze.house = house
	maze.door_col = door_col
	maze.tunnel_row = tunnel_row
	maze.start_cell = Vector2i(START_STREET_INDEX * 2 + 1, START_AVENUE_INDEX * 2 + 1)
	return maze
