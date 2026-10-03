extends RefCounted
## WhiteRabbit — where the rabbit sits and how its result is drawn
## (spec docs/design/kaninchen-speedrun.md 2.2 and 2.5).
##
## Position: exactly one per speedrun level, deterministic per level seed, in
## a dead end whose BFS distance to the start is >= 40 % of the maximum. The
## cell carries no pellet (picking the rabbit up is voluntary, so its dead
## end must never be needed to clear the level).
##
## "Kaninchen der Woche": the result of every rabbit (which condition, which
## F&L manipulation) comes from its own RandomNumberGenerator seeded with
## level id + ISO calendar week. The week is taken from the player's LOCAL
## time (Time.get_datetime_dict_from_system(false)), not from Europe/Berlin:
## the game has no server and no time zone database, and "this week" should
## change on the player's own Monday. A restart of the level re-creates the
## same generator, so it never re-rolls. Never the global randf()/randi().

const MIN_DISTANCE_SHARE := 0.4
const POSITION_SALT := 0x5ab17 # keeps the position stream apart from the maze generator's use of the seed


## ISO 8601 week of a calendar date: Vector2i(iso_year, week 1..53).
## Weeks start on Monday; week 1 is the week with the year's first Thursday.
static func iso_week(year: int, month: int, day: int) -> Vector2i:
	var wd := _weekday_monday1(year, month, day) # 1 = Monday .. 7 = Sunday
	var ordinal := _day_of_year(year, month, day)
	var week := (ordinal - wd + 10) / 7
	if week < 1:
		return Vector2i(year - 1, weeks_in_year(year - 1))
	if week > weeks_in_year(year):
		return Vector2i(year + 1, 1)
	return Vector2i(year, week)


## 52 or 53: a year has 53 ISO weeks if it starts on a Thursday, or is a
## leap year starting on a Wednesday.
static func weeks_in_year(year: int) -> int:
	var jan1 := _weekday_monday1(year, 1, 1)
	if jan1 == 4 or (jan1 == 3 and _is_leap(year)):
		return 53
	return 52


## The ISO week right now in the player's local time.
static func current_iso_week() -> Vector2i:
	var d := Time.get_datetime_dict_from_system(false)
	return iso_week(int(d.year), int(d.month), int(d.day))


static func week_label(week: Vector2i) -> String:
	return "%d-W%02d" % [week.x, week.y]


## The seed of a level's rabbit in a given week: hash of "level_id|YYYY-Www".
static func week_seed(level_id: String, week: Vector2i) -> int:
	return ("%s|%s" % [level_id, week_label(week)]).hash()


## A fresh generator for the "Kaninchen der Woche" of `level_id` in `week`.
static func week_rng(level_id: String, week: Vector2i) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = week_seed(level_id, week)
	return rng


## A generator with real randomness (Chaos mode, Etappe 3).
static func chaos_rng() -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return rng


## The rabbit's cell for a maze: a dead end (exactly one open neighbor) among
## the room cells (no ghost house, not the start, not in `excluded`), with a
## BFS distance >= MIN_DISTANCE_SHARE of the largest distance to any room
## cell; picked deterministically from `level_seed`. Falls back to the
## farthest dead end (or farthest cell) if no dead end is far enough.
## Returns Vector2i(-1, -1) only for a maze without any usable cell.
static func pick_cell(maze_gen, maze, start: Vector2i, level_seed: int, excluded: Array = []) -> Vector2i:
	var dist: Array = maze_gen.bfs(maze, start.x, start.y)
	var rooms: Array = maze_gen.cells_in_room(maze, false)
	var max_d := 0
	for c in rooms:
		max_d = maxi(max_d, int(dist[c.x][c.y]))
	var excluded_set := {}
	for c in excluded:
		excluded_set[c] = true
	var far_dead_ends := []
	var best_fallback := Vector2i(-1, -1)
	var best_fallback_d := -1
	for c in rooms:
		if c == start or excluded_set.has(c):
			continue
		var d: int = dist[c.x][c.y]
		if d < 0:
			continue
		var dead_end: bool = maze_gen.neighbors_of(maze, c.x, c.y).size() == 1
		if dead_end and d >= MIN_DISTANCE_SHARE * max_d:
			far_dead_ends.append(c)
		var score := d + (100000 if dead_end else 0)
		if score > best_fallback_d:
			best_fallback_d = score
			best_fallback = c
	if far_dead_ends.is_empty():
		return best_fallback
	var rng := RandomNumberGenerator.new()
	rng.seed = level_seed ^ POSITION_SALT
	return far_dead_ends[rng.randi_range(0, far_dead_ends.size() - 1)]


static func _is_leap(y: int) -> bool:
	return (y % 4 == 0 and y % 100 != 0) or y % 400 == 0


static func _day_of_year(y: int, m: int, d: int) -> int:
	var days: Array = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
	var n := d
	for i in m - 1:
		n += days[i]
	if m > 2 and _is_leap(y):
		n += 1
	return n


## Sakamoto's day of week, mapped to 1 = Monday .. 7 = Sunday.
static func _weekday_monday1(y: int, m: int, d: int) -> int:
	var t: Array = [0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4]
	var yy: int = y - 1 if m < 3 else y
	var w: int = (yy + yy / 4 - yy / 100 + yy / 400 + t[m - 1] + d) % 7 # 0 = Sunday
	return 7 if w == 0 else w
