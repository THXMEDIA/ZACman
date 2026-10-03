extends Node
## Speedrun — autoload singleton for speedrunning support: live level timer
## bookkeeping lives in Main, but best-times-per-level, target times and the
## resulting bonus-level unlock all live here so they persist across runs and
## across scenes (the future Manhattan bonus level reads is_bonus_unlocked()
## the same way Main does).

const SAVE_FILE := "kugelschlucker_speedrun.json"
## Version of the file format written by _save(). History:
##   1 (implicit, no "version" field): {"best_times": {...}, "bonus_unlocked": bool};
##     the oldest saves keyed best_times by level index ("0".."3").
##   2: same fields plus "version"; every value type-checked on load (Code-W3).
const SAVE_VERSION := 2

const LevelsScript := preload("res://scripts/levels.gd")
const SavePathsScript := preload("res://scripts/save_paths.gd")

## Best times per (level, condition, mode) — key from Levels.board_key(),
## e.g. "klassik-2|none" (solo, no condition), "offen|matrix_ghost",
## "durchbruch|none|chat". Target times live in Levels.POOL[].target_s.
var best_times: Dictionary = {}
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
	bonus_unlocked = false
	loaded_version = 0
	_read_only = false
	_loaded = false
	_load()


func target_for(level_id: String) -> float:
	return LevelsScript.by_id(level_id).target_s


func best_for(level_id: String, condition_id: String = "", mode: String = "solo") -> float:
	_load()
	var key := LevelsScript.board_key(level_id, condition_id, mode)
	if best_times.has(key):
		return best_times[key]
	return -1.0


## Called by Main when a level's pellets are all eaten. Returns a Dictionary
## with is_new_best (for this level/condition/mode), previous_best (-1.0 if
## none), beat_target, target, newly_unlocked_bonus (true only on the frame
## the badge is earned) so the caller can show the right banner text.
## Only a clean run (no condition, mode "solo") can earn the badge.
func record_level_time(level_id: String, elapsed_seconds: float, condition_id: String = "", mode: String = "solo") -> Dictionary:
	_load()
	var key := LevelsScript.board_key(level_id, condition_id, mode)
	var previous_best := best_for(level_id, condition_id, mode)
	var is_new_best := previous_best < 0.0 or elapsed_seconds < previous_best
	if is_new_best:
		best_times[key] = elapsed_seconds

	var target := target_for(level_id)
	var beat_target := elapsed_seconds <= target
	var newly_unlocked := false
	if beat_target and condition_id == "" and mode == "solo" and not bonus_unlocked:
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
		return
	var version := file_version(parsed)
	if version > SAVE_VERSION:
		push_warning("Speedrun: save file version %d is newer than %d — not loaded, not overwritten" % [version, SAVE_VERSION])
		_read_only = true
		return
	loaded_version = version
	if parsed.has("best_times") and typeof(parsed.best_times) == TYPE_DICTIONARY:
		best_times = _migrate_keys(parsed.best_times)
	if parsed.has("bonus_unlocked") and typeof(parsed.bonus_unlocked) == TYPE_BOOL:
		bonus_unlocked = parsed.bonus_unlocked


func _save() -> void:
	if _read_only:
		return
	var payload := {"version": SAVE_VERSION, "best_times": best_times, "bonus_unlocked": bonus_unlocked}
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


## A usable best time: a finite number above zero. Anything else in a save
## (null, string, negative, NaN) is dropped instead of crashing best_for /
## record_level_time later (Code-W3).
static func is_valid_time(v) -> bool:
	if typeof(v) != TYPE_FLOAT and typeof(v) != TYPE_INT:
		return false
	var t := float(v)
	return t > 0.0 and not is_nan(t) and not is_inf(t)


## Saves from before the level pool keyed best times by level index ("0".."3")
## and knew neither conditions nor modes; those were plain solo runs of what
## are now klassik-1..4. Values that are not a valid time are dropped.
static func _migrate_keys(old: Dictionary) -> Dictionary:
	var out := {}
	for key in old.keys():
		var v = old[key]
		if not is_valid_time(v):
			continue
		var k: String = str(key)
		if k.is_valid_int():
			var idx := k.to_int()
			if idx >= 0 and idx < 4:
				out[LevelsScript.board_key("klassik-%d" % (idx + 1), "")] = float(v)
		else:
			out[k] = float(v)
	return out
