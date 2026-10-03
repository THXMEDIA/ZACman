extends RefCounted
## Levels — the pool of Speedrun levels. A run starts on a random level of
## the pool and, after every clear, moves on to a random one it has not
## played yet in that run (see Levels.draw_next).
##
## Every level has a fixed seed, so a level is the same maze every time and
## its best time / board is comparable between runs (Speedrun-Fairness).
## `id` is the key for best times and leaderboards, never the position in
## the array, so adding or reordering levels does not touch saved times.
##
## The two "Labyrinth-Aufbau" proposals from the 2026-10-01 review (GD-W4)
## are built as levels of their own, same size, so they can be compared:
##   "offen"      more loops (loop_prob 0.45) => far fewer dead ends
##   "durchbruch" 3 doors in the closed middle column => the two halves are
##                no longer connected only by the wrap tunnel

## Player speed (player_controller.gd PLAYER_SPEED) and the length of one
## grid step (maze_view.gd CELL) — the basis of reference_route_seconds().
const PLAYER_SPEED := 4.4
const CELL_M := 2.0

## target_s (seconds) is data, not computed at runtime: tests/test_levels.gd
## rebuilds each maze and checks it against reference_route_seconds() (within
## 5 s). It is the time of a plain "nearest pellet next" route at full speed,
## so it is reachable without planning and beatable with it. (The first
## targets, 55/70/85/100 s, were below the physical lower bound of the
## levels; the test now guards against that too.)
##
## `look` picks the level's color variant of the Speedrun base look (see
## city_themes.gd normal().level_looks): "lagune" in Klassik I/III, "riff" in
## Klassik II/IV, the other levels alternate (spec 1.1).
const POOL := [
	{"id": "klassik-1", "name": "Klassik I", "rows": 19, "cols": 21, "ghost_speed": 2.0, "ghost_count": 3, "seed": 10003, "loop_prob": 0.16, "breakthroughs": 0, "target_s": 115.0, "look": "lagune"},
	{"id": "klassik-2", "name": "Klassik II", "rows": 21, "cols": 25, "ghost_speed": 2.25, "ghost_count": 4, "seed": 20080, "loop_prob": 0.16, "breakthroughs": 0, "target_s": 170.0, "look": "riff"},
	{"id": "klassik-3", "name": "Klassik III", "rows": 23, "cols": 27, "ghost_speed": 2.5, "ghost_count": 4, "seed": 30157, "loop_prob": 0.16, "breakthroughs": 0, "target_s": 205.0, "look": "lagune"},
	{"id": "klassik-4", "name": "Klassik IV", "rows": 23, "cols": 29, "ghost_speed": 2.75, "ghost_count": 5, "seed": 40234, "loop_prob": 0.16, "breakthroughs": 0, "target_s": 225.0, "look": "riff"},
	{"id": "offen", "name": "Offen", "rows": 21, "cols": 25, "ghost_speed": 2.25, "ghost_count": 4, "seed": 50003, "loop_prob": 0.45, "breakthroughs": 0, "target_s": 160.0, "look": "lagune"},
	{"id": "durchbruch", "name": "Durchbruch", "rows": 21, "cols": 25, "ghost_speed": 2.25, "ghost_count": 4, "seed": 60003, "loop_prob": 0.16, "breakthroughs": 3, "target_s": 175.0, "look": "riff"},
]


## Run modes. Every mode has its own best times and leaderboards, so runs
## that are not comparable never share a board:
##   solo  plain run, nobody interfered
##   chat  at least one Twitch chat command took effect during the level
##   pvp / coop  reserved for the planned multiplayer modes (no gameplay yet)
const MODES := ["solo", "chat", "pvp", "coop"]
const MODE_LABELS := {"solo": "Solo", "chat": "Chat", "pvp": "PvP", "coop": "Koop"}


## Key of the best time / leaderboard of one (level, condition, mode).
## "" condition is stored as "none". Solo keeps the short "level|cond" form
## the saved files already use; the other modes append "|mode".
static func board_key(level_id: String, condition_id: String, mode: String = "solo") -> String:
	var cond := condition_id if condition_id != "" else "none"
	if mode == "solo" or mode == "":
		return "%s|%s" % [level_id, cond]
	return "%s|%s|%s" % [level_id, cond, mode]


static func ids() -> Array:
	var out := []
	for lv in POOL:
		out.append(lv.id)
	return out


static func by_id(id: String) -> Dictionary:
	for lv in POOL:
		if lv.id == id:
			return lv
	return POOL[0]


static func index_of(id: String) -> int:
	for i in POOL.size():
		if POOL[i].id == id:
			return i
	return -1


## Generator options of a level, for MazeGen.generate_maze().
static func maze_opts(level: Dictionary) -> Dictionary:
	return {"loop_prob": level.loop_prob, "breakthroughs": level.breakthroughs}


## The next level of a run: a random one of the pool that is not in
## `played` (ids already cleared in this run). When all were played the run
## starts a new round, but never repeats `last_id` back to back.
static func draw_next(played: Array, last_id: String, rng: RandomNumberGenerator) -> Dictionary:
	var open := []
	for lv in POOL:
		if not played.has(lv.id):
			open.append(lv)
	if open.is_empty():
		for lv in POOL:
			if lv.id != last_id:
				open.append(lv)
	return open[rng.randi_range(0, open.size() - 1)]


## Where the player starts: the bottom-most room cell below the ghost house
## (the right-most of that row wins ties — first found in cells_in_room order).
static func start_cell(maze_gen, maze) -> Vector2i:
	var rooms: Array = maze_gen.cells_in_room(maze, false)
	var best: Vector2i = rooms[rooms.size() - 1]
	var best_r := -1
	for cell in rooms:
		if cell.x <= maze.house.r1:
			continue
		if cell.x > best_r:
			best_r = cell.x
			best = cell
	return best


## Seconds a "nearest remaining pellet next" route needs at full speed
## (BFS distance incl. the wrap tunnel, no pickup-radius credit).
static func reference_route_seconds(maze_gen, maze) -> float:
	var start: Vector2i = start_cell(maze_gen, maze)
	var todo := {}
	for c in maze_gen.cells_in_room(maze, false):
		if c != start:
			todo[c] = true
	var cur: Vector2i = start
	var steps := 0
	while not todo.is_empty():
		var dist: Array = maze_gen.bfs(maze, cur.x, cur.y)
		var next_cell = null
		var next_d := 1 << 30
		for c in todo:
			var d: int = dist[c.x][c.y]
			if d >= 0 and d < next_d:
				next_d = d
				next_cell = c
		if next_cell == null:
			break
		steps += next_d
		cur = next_cell
		todo.erase(next_cell)
	return steps * CELL_M / PLAYER_SPEED


## Physical lower bound: every pellet needs one 4 m hop, minus what the
## 0.42 m pickup radius saves on each end. No route can be faster.
static func lower_bound_seconds(maze_gen, maze) -> float:
	var hops: int = maze_gen.cells_in_room(maze, false).size() - 1
	return hops * (2.0 * CELL_M - 2.0 * 0.42) / PLAYER_SPEED
