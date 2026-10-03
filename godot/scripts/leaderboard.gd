extends Node
## Leaderboard — autoload singleton for time boards, one per
## (level_id, condition_id, mode) combination. A Matrix-Ghost run (no wall
## collision) isn't comparable to an unmodified run, and neither is a run
## with Twitch chat interaction, so they never share a board (modes: see
## Levels.MODES). Manhattan has no board: it is an untimed hub level.
##
## This is the LOCAL backend: works fully offline, no account needed, and
## is what the game ships with today. Deliberately written behind a small
## interface (submit_time/get_top/board_key) so a future Steamworks backend
## (GodotSteam Leaderboards, once the project has a Steamworks App ID — see
## docs/STEAM_ROADMAP.md) can replace persistence without touching any
## calling code in Main/HUD — Steam isn't reachable from this dev sandbox,
## so that swap is future work, not done here.

const LevelsScript := preload("res://scripts/levels.gd")

const SAVE_PATH := "user://zapmaniac_leaderboards.json"
const MAX_ENTRIES_PER_BOARD := 20
const DEFAULT_PLAYER_NAME := "Player"

var _boards: Dictionary = {} # board_key (String) -> Array[{"name": String, "time": float}], sorted ascending (fastest first)
var _loaded := false


func _ready() -> void:
	_load()


## The board key for a (level, condition, mode) — see Levels.board_key().
static func board_key(level_id: String, condition_id: String, mode: String = "solo") -> String:
	return LevelsScript.board_key(level_id, condition_id, mode)


## Records a completed run's time on the (level_id, condition_id, mode) board.
## Returns {rank: int (1-based, -1 if it didn't make the top
## MAX_ENTRIES_PER_BOARD), is_new_best: bool (a personal best for this
## player name on this specific board)}.
func submit_time(level_id: String, condition_id: String, time_seconds: float, player_name: String = DEFAULT_PLAYER_NAME, mode: String = "solo") -> Dictionary:
	_load()
	var key := board_key(level_id, condition_id, mode)
	var board: Array = _boards.get(key, [])

	var previous_best := INF
	for entry in board:
		if entry.name == player_name and entry.time < previous_best:
			previous_best = entry.time
	var is_new_best: bool = time_seconds < previous_best

	board.append({"name": player_name, "time": time_seconds})
	board.sort_custom(func(a, b): return a.time < b.time)
	if board.size() > MAX_ENTRIES_PER_BOARD:
		board.resize(MAX_ENTRIES_PER_BOARD)
	_boards[key] = board
	_save()

	var rank := -1
	for i in board.size():
		if board[i].name == player_name and is_equal_approx(board[i].time, time_seconds):
			rank = i + 1
			break
	return {"rank": rank, "is_new_best": is_new_best}


## Top `n` entries for a board, fastest first. Each entry: {name, time}.
func get_top(level_id: String, condition_id: String, n: int = MAX_ENTRIES_PER_BOARD, mode: String = "solo") -> Array:
	_load()
	var key := board_key(level_id, condition_id, mode)
	var board: Array = _boards.get(key, [])
	return board.slice(0, mini(n, board.size()))


## Test/debug hook: wipes every board, in memory and on disk. Same pattern
## as Speedrun.reset_all() — used by BotTest.tscn so each headless run
## starts clean regardless of what a previous run in the same container
## persisted.
func reset_all() -> void:
	_boards = {}
	_loaded = true
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)


func _load() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var text := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	for key in parsed.keys():
		if typeof(parsed[key]) != TYPE_ARRAY:
			continue
		var new_key := _migrate_key(str(key))
		if new_key != "":
			_boards[new_key] = parsed[key]


## Boards from before the level pool were keyed "normal-N|cond" (N = 0-based
## level index) and "manhattan|cond". The former are now klassik-(N+1); the
## latter are dropped (Manhattan no longer has a time board).
static func _migrate_key(key: String) -> String:
	if key.begins_with("manhattan|"):
		return ""
	if key.begins_with("normal-"):
		var rest := key.substr(7)
		var parts := rest.split("|")
		if parts.size() == 2 and parts[0].is_valid_int():
			return "klassik-%d|%s" % [parts[0].to_int() + 1, parts[1]]
	return key


func _save() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(_boards))
	f.close()
