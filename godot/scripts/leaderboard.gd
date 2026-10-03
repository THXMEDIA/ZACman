extends Node
## Leaderboard — autoload singleton for time boards, one per
## (level_id, board, mode) combination (Levels.board_key: "level|brett|modus").
## Boards: "woche" (Kaninchen der Woche; every entry carries its ISO week),
## "chaos" (Chaos mode) and "chat" (Twitch chat had a hand in the level);
## modes: solo, later pvp/coop (Levels.MODES). The rabbit condition is not
## part of the key. Boards from before Etappe 3 that were keyed by condition
## (|none, |matrix_ghost, |fear_and_loathing, ...) are moved into the file's
## "archive" on load: kept, never shown. Manhattan has no board: it is an
## untimed hub level.
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
##      type-checked on load (Code-W3).
##   3: {"version": 3, "boards": {"level|board|mode": [entries]},
##      "archive": {old key: [entries]}}; entries {name, time, week} (week
##      "2026-W40" on the weekly board, "" = unknown/other boards).
const SAVE_VERSION := 3
const MAX_ENTRIES_PER_BOARD := 20
const DEFAULT_PLAYER_NAME := "Player"

var _boards: Dictionary = {} # board_key (String) -> Array[{"name": String, "time": float, "week": String}], sorted ascending (fastest first)
## Old boards (condition keys from before Etappe 3), kept as they were and
## never shown: {old_key: [entries]}.
var archive: Dictionary = {}
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
	archive = {}
	loaded_version = 0
	_read_only = false
	_loaded = false
	_load()


## The board key for a (level, board, mode) — see Levels.board_key().
static func board_key(level_id: String, board: String, mode: String = "solo") -> String:
	return LevelsScript.board_key(level_id, board, mode)


## Records a completed run's time on the (level_id, board, mode) board.
## `week` ("2026-W40") is stored with the entry on the weekly board only.
## Returns {rank: int (1-based, -1 if it didn't make the top
## MAX_ENTRIES_PER_BOARD or the key is invalid), is_new_best: bool (a
## personal best for this player name on this specific board)}. An unknown
## level, board or mode records nothing (Code-W8: no silent new boards).
func submit_time(level_id: String, board: String, time_seconds: float, player_name: String = DEFAULT_PLAYER_NAME, mode: String = "solo", week: String = "") -> Dictionary:
	_load()
	var key := board_key(level_id, board, mode)
	if not LevelsScript.is_valid_board_key(key):
		push_error("Leaderboard: refusing to submit to unknown board '%s'" % key)
		return {"rank": -1, "is_new_best": false}
	var entries: Array = _boards.get(key, [])

	var previous_best := INF
	for entry in entries:
		if entry.name == player_name and entry.time < previous_best:
			previous_best = entry.time
	var is_new_best: bool = time_seconds < previous_best

	entries.append({"name": player_name, "time": time_seconds, "week": week if board == LevelsScript.BOARD_WEEK else ""})
	entries.sort_custom(func(a, b): return a.time < b.time)
	if entries.size() > MAX_ENTRIES_PER_BOARD:
		entries.resize(MAX_ENTRIES_PER_BOARD)
	_boards[key] = entries
	_save()

	var rank := -1
	for i in entries.size():
		if entries[i].name == player_name and is_equal_approx(entries[i].time, time_seconds):
			rank = i + 1
			break
	return {"rank": rank, "is_new_best": is_new_best}


## Top `n` entries for a board, fastest first. Each entry: {name, time, week}.
func get_top(level_id: String, board: String, n: int = MAX_ENTRIES_PER_BOARD, mode: String = "solo") -> Array:
	_load()
	var key := board_key(level_id, board, mode)
	var entries: Array = _boards.get(key, [])
	return entries.slice(0, mini(n, entries.size()))


## Test/debug hook: wipes every board, in memory and on disk at the current
## SavePaths root. Same pattern as Speedrun.reset_all(); tests redirect the
## root first, so this never deletes a real save.
func reset_all() -> void:
	_boards = {}
	archive = {}
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
			raw_boards = {}
	for key in raw_boards.keys():
		var old_key := str(key)
		var board := sanitize_board(raw_boards[key])
		if board.is_empty():
			continue
		var new_key := migrate_key(old_key, version)
		if new_key == "":
			_put(archive, old_key, board)
		else:
			_put(_boards, new_key, board)
	var raw_archive = parsed.get("archive", {}) if version >= 3 else {}
	if typeof(raw_archive) == TYPE_DICTIONARY:
		for key in raw_archive.keys():
			var board := sanitize_board(raw_archive[key])
			if not board.is_empty():
				_put(archive, str(key), board)


## Merges `board` into target[key] (fastest first, capped).
static func _put(target: Dictionary, key: String, board: Array) -> void:
	if target.has(key):
		board.append_array(target[key])
		board.sort_custom(func(a, b): return a.time < b.time)
		if board.size() > MAX_ENTRIES_PER_BOARD:
			board.resize(MAX_ENTRIES_PER_BOARD)
	target[key] = board


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
		var week = e.get("week", "")
		out.append({"name": e.name, "time": t, "week": week if typeof(week) == TYPE_STRING else ""})
	out.sort_custom(func(a, b): return a.time < b.time)
	if out.size() > MAX_ENTRIES_PER_BOARD:
		out.resize(MAX_ENTRIES_PER_BOARD)
	return out


## The v3 key of a board loaded from a file of `version`, or "" when it
## goes to the archive. Version 3: valid keys stay, anything else is
## archived. Versions 1/2: "normal-N|..." (before the level pool, N 0-based)
## is first renamed to klassik-(N+1); then Levels.migrate_v2_key keeps the
## Etappe-2 weekly boards ("level|woche[|mode]", "|woche|chat" -> chat
## board). Everything else — the condition boards (|none, |matrix_ghost,
## |fear_and_loathing, with or without mode), the old manhattan boards,
## normal-N without a pool level — is archived, never deleted. "none" times
## are not taken over to the weekly board (different required pellets back
## then, see Speedrun.migrate_best_times).
static func migrate_key(key: String, version: int) -> String:
	if version >= 3:
		return key if LevelsScript.is_valid_board_key(key) else ""
	var k := key
	if k.begins_with("normal-"):
		var parts := k.substr(7).split("|", true, 1)
		if parts.size() == 2 and parts[0].is_valid_int():
			var idx := parts[0].to_int()
			if idx >= 0 and idx < 4:
				k = "klassik-%d|%s" % [idx + 1, parts[1]]
	return LevelsScript.migrate_v2_key(k)


func _save() -> void:
	if _read_only:
		return
	var payload := {"version": SAVE_VERSION, "boards": _boards}
	if not archive.is_empty():
		payload["archive"] = archive
	SavePathsScript.write_atomic(save_path(), JSON.stringify(payload))
