extends Node
## Speedrun — autoload singleton for speedrunning support: live level timer
## bookkeeping lives in Main, but best-times-per-level, target times and the
## resulting bonus-level unlock all live here so they persist across runs and
## across scenes (the future Manhattan bonus level reads is_bonus_unlocked()
## the same way Main does).

const SAVE_FILE := "zapmaniac_speedrun.json"
## Version of the file format written by _save(). History:
##   1 (implicit, no "version" field): {"best_times": {...}, "bonus_unlocked": bool};
##     the oldest saves keyed best_times by level index ("0".."3").
##   2: same fields plus "version"; every value type-checked on load (Code-W3).
##      Keys "level|condition[|mode]" (none, matrix_ghost, fear_and_loathing)
##      and, since Etappe 2, "level|woche[|mode]".
##   3: keys "level|board|mode" (Levels.board_key); every best time is
##      {"time": float, "week": "2026-W40"} — the ISO week only on the weekly
##      board ("" = unknown, a time from before weeks were stored). Old
##      condition keys are moved into "archive" (kept, never shown).
const SAVE_VERSION := 3

const LevelsScript := preload("res://scripts/levels.gd")
const SavePathsScript := preload("res://scripts/save_paths.gd")

## Best times per (level, board, mode) — key from Levels.board_key(), e.g.
## "klassik-2|woche|solo" -> {"time": 131.2, "week": "2026-W40"}. On the
## weekly board this is the all-time best of the level, with the week it was
## set in. Target times live in Levels.POOL[].target_s.
var best_times: Dictionary = {}
## Best times of old, no longer shown boards (condition keys from before
## Etappe 3), exactly as they were: {old_key: seconds}. Kept in the file so
## nothing a player achieved is deleted; never read by the game.
var archive: Dictionary = {}
var bonus_unlocked := false
## Version of the file that was loaded (0 = no file / unreadable). Saves from
## a newer game version are left alone: they are not loaded and never
## overwritten, so going back to an older build can not destroy them.
var loaded_version := 0

var _loaded := false
var _read_only := false


func _ready() -> void:
	_load()


## Where this instance reads and writes (see SavePaths; tests redirect it).
func save_path() -> String:
	return SavePathsScript.path(SAVE_FILE)


## Drops the in-memory state and reads the save file again from the current
## SavePaths root — used by tests right after redirecting the root, because
## the autoload already loaded once at startup.
func reload() -> void:
	best_times = {}
	archive = {}
	bonus_unlocked = false
	loaded_version = 0
	_read_only = false
	_loaded = false
	_load()


func target_for(level_id: String) -> float:
	return float(LevelsScript.by_id(level_id).get("target_s", -1.0))


func best_for(level_id: String, board: String = LevelsScript.BOARD_WEEK, mode: String = "solo") -> float:
	return float(best_entry(level_id, board, mode).get("time", -1.0))


## {"time": seconds, "week": "2026-W40" or ""} of a board, {} if none yet.
func best_entry(level_id: String, board: String = LevelsScript.BOARD_WEEK, mode: String = "solo") -> Dictionary:
	_load()
	var key := LevelsScript.board_key(level_id, board, mode)
	if best_times.has(key):
		return best_times[key]
	return {}


## Called by Main when a level's pellets are all eaten. Returns a Dictionary
## with is_new_best (for this level/board/mode), previous_best (-1.0 if
## none), beat_target, target, newly_unlocked_bonus (true only on the frame
## the badge is earned) so the caller can show the right banner text.
## `week` ("2026-W40") is stored with the time on the weekly board only.
## Only a solo run on the weekly board (Levels.BADGE_BOARDS) can earn the
## badge — with or without a rabbit condition. An invalid key (unknown
## level, board or mode; Code-W8) records nothing.
func record_level_time(level_id: String, elapsed_seconds: float, board: String = LevelsScript.BOARD_WEEK, mode: String = "solo", week: String = "") -> Dictionary:
	_load()
	var key := LevelsScript.board_key(level_id, board, mode)
	var target := target_for(level_id)
	if not LevelsScript.is_valid_board_key(key):
		push_error("Speedrun: refusing to record on unknown board '%s'" % key)
		return {"is_new_best": false, "previous_best": -1.0, "beat_target": false, "target": target, "newly_unlocked_bonus": false}
	# QA 04.10. N8: the loader only accepts times > 0, so a 0-s time (a level
	# "cleared" in the frame it started — tools, tests) is never written.
	if not (elapsed_seconds > 0.0):
		return {"is_new_best": false, "previous_best": best_for(level_id, board, mode), "beat_target": false, "target": target, "newly_unlocked_bonus": false}
	var previous_best := best_for(level_id, board, mode)
	var is_new_best := previous_best < 0.0 or elapsed_seconds < previous_best
	if is_new_best:
		best_times[key] = {"time": elapsed_seconds, "week": week if board == LevelsScript.BOARD_WEEK else ""}

	var beat_target := elapsed_seconds <= target
	var newly_unlocked := false
	if beat_target and LevelsScript.board_earns_badge(board) and mode == "solo" and not bonus_unlocked:
		bonus_unlocked = true
		newly_unlocked = true

	if is_new_best or newly_unlocked:
		_save()

	return {
		"is_new_best": is_new_best,
		"previous_best": previous_best,
		"beat_target": beat_target,
		"target": target,
		"newly_unlocked_bonus": newly_unlocked,
	}


func is_bonus_unlocked() -> bool:
	_load()
	return bonus_unlocked


## Test/debug hook: wipes best times + bonus-unlocked state, in memory and
## on disk at the current SavePaths root. Not exposed anywhere in the UI (a
## player's progress here should be sticky). Tests redirect the root first
## (SavePaths.use_root), so this never deletes a real save.
func reset_all() -> void:
	best_times = {}
	archive = {}
	bonus_unlocked = false
	loaded_version = 0
	_read_only = false
	_loaded = true
	if FileAccess.file_exists(save_path()):
		DirAccess.remove_absolute(save_path())


## Format helper shared by HUD: 74.2 -> "1:14.20"
static func format_time(seconds: float) -> String:
	if seconds < 0.0:
		return "--:--"
	var total_cs := int(round(seconds * 100.0))
	var cs := total_cs % 100
	var total_s := total_cs / 100
	var s := total_s % 60
	var m := total_s / 60
	return "%d:%02d.%02d" % [m, s, cs]


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
		SavePathsScript.backup_corrupt(path) # W4: kept before the next save overwrites it
		return
	var broken := not version_field_ok(parsed)
	var version := file_version(parsed)
	if version > SAVE_VERSION:
		push_warning("Speedrun: save file version %d is newer than %d — not loaded, not overwritten" % [version, SAVE_VERSION])
		_read_only = true
		return
	loaded_version = version
	var raw_times = parsed.get("best_times", {})
	if typeof(raw_times) == TYPE_DICTIONARY:
		var migrated := migrate_best_times(raw_times, version)
		best_times = migrated.best_times
		archive = migrated.archive
		broken = broken or migrated.dropped > 0
	else:
		broken = true
	var raw_archive = parsed.get("archive", {})
	if typeof(raw_archive) == TYPE_DICTIONARY:
		for k in raw_archive:
			if not archive.has(str(k)):
				archive[str(k)] = raw_archive[k]
	else:
		broken = true
	if parsed.has("bonus_unlocked"):
		if typeof(parsed.bonus_unlocked) == TYPE_BOOL:
			bonus_unlocked = parsed.bonus_unlocked
		else:
			broken = true
	if broken:
		# W4: a value of the wrong type was dropped — keep the original file
		# before the next save writes the cleaned state over it.
		SavePathsScript.backup_corrupt(path)


func _save() -> void:
	if _read_only:
		return
	var payload := {"version": SAVE_VERSION, "best_times": best_times, "bonus_unlocked": bonus_unlocked}
	if not archive.is_empty():
		payload["archive"] = archive
	SavePathsScript.write_atomic(save_path(), JSON.stringify(payload))


## Version of a parsed save: the "version" field if it is a whole number,
## otherwise 1 (files from before versioning). A malformed field counts as 1.
static func file_version(parsed: Dictionary) -> int:
	if not parsed.has("version"):
		return 1
	var v = parsed.version
	if (typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT) and float(v) == floorf(float(v)) and v >= 1:
		return int(v)
	return 1


## False when a "version" field exists but is not a whole number >= 1 (a
## damaged file; W4 keeps a copy of it).
static func version_field_ok(parsed: Dictionary) -> bool:
	if not parsed.has("version"):
		return true
	var v = parsed.version
	return (typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT) and float(v) == floorf(float(v)) and v >= 1


## A usable best time: a finite number above zero. Anything else in a save
## (null, string, negative, NaN) is dropped instead of crashing best_for /
## record_level_time later (Code-W3).
static func is_valid_time(v) -> bool:
	if typeof(v) != TYPE_FLOAT and typeof(v) != TYPE_INT:
		return false
	var t := float(v)
	return t > 0.0 and not is_nan(t) and not is_inf(t)


## A stored v3 best time: {"time": valid time, "week": String}. Anything
## else is dropped (Code-W3).
static func sanitize_entry(v) -> Dictionary:
	if typeof(v) != TYPE_DICTIONARY or not is_valid_time(v.get("time")):
		return {}
	var week = v.get("week", "")
	return {"time": float(v.time), "week": week if typeof(week) == TYPE_STRING else ""}


## Turns the "best_times" of a save of `version` into
## {"best_times": {v3 key: {time, week}}, "archive": {old key: seconds},
##  "dropped": number of values dropped for a wrong type (W4)}.
## Version 3: valid keys stay; entries under an unknown key are archived.
## Versions 1/2 (plain numbers):
##   - "0".."3" (before the level pool: plain solo runs of klassik-1..4,
##     without a rabbit) are archived as "klassik-N|none"; other indices
##     never existed and are dropped;
##   - "level|woche[|mode]" (Etappe 2, same rules as today) move to the v3
##     key, week unknown; "level|woche|chat" goes to the chat board;
##   - every other key (condition boards: |none, |matrix_ghost,
##     |fear_and_loathing, with or without mode) is archived unchanged.
## Times of the old "none" board are deliberately NOT taken over to the
## weekly board: their levels had a different set of required pellets (no
## free rabbit dead end; Word/Fear pickups replaced pellets from the second
## level of a run on), so they are not comparable (README, Bretter).
## Values that are not a valid time are dropped (Code-W3).
static func migrate_best_times(raw: Dictionary, version: int) -> Dictionary:
	var out := {}
	var arch := {}
	var dropped := 0
	for key in raw.keys():
		var k: String = str(key)
		var v = raw[key]
		if version >= 3:
			var e := sanitize_entry(v)
			if e.is_empty():
				dropped += 1
				continue
			if LevelsScript.is_valid_board_key(k):
				out[k] = e
			else:
				arch[k] = e.time
			continue
		if not is_valid_time(v):
			dropped += 1
			continue
		if k.is_valid_int():
			var idx := k.to_int()
			if idx >= 0 and idx < 4:
				arch["klassik-%d|none" % (idx + 1)] = float(v)
			continue
		var nk := LevelsScript.migrate_v2_key(k)
		if nk == "":
			arch[k] = float(v)
		elif not out.has(nk) or float(v) < out[nk].time:
			out[nk] = {"time": float(v), "week": ""}
	return {"best_times": out, "archive": arch, "dropped": dropped}
