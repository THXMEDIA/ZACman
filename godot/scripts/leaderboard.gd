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
const SavePathsScript := preload("res://scripts/save_paths.gd")

const SAVE_FILE := "kugelschlucker_leaderboards.json"
## Version of the file format written by _save(). History:
##   1 (implicit): the whole file is {board_key: [entries]}.
##   2: {"version": 2, "boards": {board_key: [entries]}}; every entry
##      type-checked on load (Code-W3). Etappe 3 migrates the board keys.
const SAVE_VERSION := 2
const MAX_ENTRIES_PER_BOARD := 20
const DEFAULT_PLAYER_NAME := "Player"

var _boards: Dictionary = {} # board_key (String) -> Array[{"name": String, "time": float}], sorted ascending (fastest first)
## Version of the file that was loaded (0 = no file / unreadable). A file
## from a newer game version is neither loaded nor overwritten.
var loaded_version := 0
var _loaded := false
var _read_only := false


func _ready() -> void:
	_load()


## Where this instance reads and writes (see SavePaths; tests redirect it).
func save_path() -> String:
	return SavePathsScript.path(SAVE_FILE)


## Drops the in-memory boards and reads the file again from the current
## SavePaths root (tests call this after redirecting the root).
func reload() -> void:
	_boards = {}
	loaded_version = 0
	_read_only = false
	_loaded = false
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


## Test/debug hook: wipes every board, in memory and on disk at the current
## SavePaths root. Same pattern as Speedrun.reset_all(); tests redirect the
## root first, so this never deletes a real save.
func reset_all() -> void:
	_boards = {}
	loaded_version = 0
	_read_only = false
	_loaded = true
	if FileAccess.file_exists(save_path()):
		DirAccess.remove_absolute(save_path())


func _load() -> void:
	if _loaded:
		return
	_loaded = true
	var path := save_path()
	if not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var text := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var version := file_version(parsed)
	if version > SAVE_VERSION:
		push_warning("Leaderboard: save file version %d is newer than %d — not loaded, not overwritten" % [version, SAVE_VERSION])
		_read_only = true
		return
	loaded_version = version
	var raw_boards = parsed
	if version >= 2:
		raw_boards = parsed.get("boards", {})
		if typeof(raw_boards) != TYPE_DICTIONARY:
			return
	for key in raw_boards.keys():
		var new_key := _migrate_key(str(key))
		if new_key == "":
			continue
		var board := sanitize_board(raw_boards[key])
		if board.is_empty():
			continue
		if _boards.has(new_key):
			board.append_array(_boards[new_key])
			board.sort_custom(func(a, b): return a.time < b.time)
			if board.size() > MAX_ENTRIES_PER_BOARD:
				board.resize(MAX_ENTRIES_PER_BOARD)
		_boards[new_key] = board


## Version of a parsed save: the "version" field if it is a whole number,
## otherwise 1. Version-1 files have board keys at the top level; a board
## key never is "version", so the field can not be mistaken for a board.
static func file_version(parsed: Dictionary) -> int:
	if not parsed.has("version"):
		return 1
	var v = parsed.version
	if (typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT) and float(v) == floorf(float(v)) and v >= 1:
		return int(v)
	return 1


## Only well-formed entries survive: a Dictionary with a String "name" and a
## finite "time" above zero. A broken entry used to make submit_time crash
## before saving, so the board never took a time again (Code-W3). Sorted
## fastest first and capped, like a board written by submit_time.
static func sanitize_board(raw) -> Array:
	var out := []
	if typeof(raw) != TYPE_ARRAY:
		return out
	for e in raw:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		if not e.has("name") or typeof(e.name) != TYPE_STRING:
			continue
		if not e.has("time") or (typeof(e.time) != TYPE_FLOAT and typeof(e.time) != TYPE_INT):
			continue
		var t := float(e.time)
		if t <= 0.0 or is_nan(t) or is_inf(t):
			continue
		out.append({"name": e.name, "time": t})
	out.sort_custom(func(a, b): return a.time < b.time)
	if out.size() > MAX_ENTRIES_PER_BOARD:
		out.resize(MAX_ENTRIES_PER_BOARD)
	return out


## Boards from before the level pool were keyed "normal-N|cond" (N = 0-based
## level index) and "manhattan|cond". normal-0..3 are now klassik-1..4; any
## higher index never existed as a pool level and is dropped instead of
## leaving an orphan board in the file (Code-W3). Manhattan boards are
## dropped too (Manhattan no longer has a time board).
static func _migrate_key(key: String) -> String:
	if key == "version" or key == "boards":
		return ""
	if key.begins_with("manhattan|"):
		return ""
	if key.begins_with("normal-"):
		var rest := key.substr(7)
		var parts := rest.split("|")
		if parts.size() == 2 and parts[0].is_valid_int():
			var idx := parts[0].to_int()
			if idx >= 0 and idx < 4:
				return "klassik-%d|%s" % [idx + 1, parts[1]]
		return ""
	return key


func _save() -> void:
	if _read_only:
		return
	SavePathsScript.write_atomic(save_path(), JSON.stringify({"version": SAVE_VERSION, "boards": _boards}))
