extends Node
## Speedrun — autoload singleton for speedrunning support: live level timer
## bookkeeping lives in Main, but best-times-per-level, target times and the
## resulting bonus-level unlock all live here so they persist across runs and
## across scenes (the future Manhattan bonus level reads is_bonus_unlocked()
## the same way Main does).

const SAVE_PATH := "user://kugelschlucker_speedrun.json"

## Zielzeiten (Sekunden) pro Level-Index, um das Bonuslevel freizuschalten.
## Grosszuegig genug fuer einen soliden, aber nicht perfekten Lauf; kann vom
## Spieler durch Uebung unterboten werden. Level-Groesse/-Ghost-Anzahl wächst
## mit main.gd::LEVELS, die Zielzeiten wachsen entsprechend mit.
const TARGET_TIMES := [55.0, 70.0, 85.0, 100.0]
const DEFAULT_TARGET := 110.0

var best_times: Dictionary = {} # level_index (int, as String key for JSON) -> float seconds
var bonus_unlocked := false

var _loaded := false


func _ready() -> void:
	_load()


func target_for(level_index: int) -> float:
	if level_index < TARGET_TIMES.size():
		return TARGET_TIMES[level_index]
	return DEFAULT_TARGET


func best_for(level_index: int) -> float:
	_load()
	var key := str(level_index)
	if best_times.has(key):
		return best_times[key]
	return -1.0


## Called by Main when a level's pellets are all eaten. Returns a Dictionary
## with is_new_best, previous_best (-1.0 if none), beat_target, target,
## newly_unlocked_bonus (true only on the frame the unlock happens) so the
## caller (Main/HUD) can show the right banner text without re-deriving it.
func record_level_time(level_index: int, elapsed_seconds: float) -> Dictionary:
	_load()
	var key := str(level_index)
	var previous_best := best_for(level_index)
	var is_new_best := previous_best < 0.0 or elapsed_seconds < previous_best
	if is_new_best:
		best_times[key] = elapsed_seconds

	var target := target_for(level_index)
	var beat_target := elapsed_seconds <= target
	var newly_unlocked := false
	if beat_target and not bonus_unlocked:
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
## on disk. Not exposed anywhere in the UI (a player's progress here should
## be sticky) — used by BotTest.tscn so each headless run starts clean
## regardless of what a previous run in the same container persisted.
func reset_all() -> void:
	best_times = {}
	bonus_unlocked = false
	_loaded = true
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)


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
	if parsed.has("best_times") and typeof(parsed.best_times) == TYPE_DICTIONARY:
		best_times = parsed.best_times
	if parsed.has("bonus_unlocked"):
		bonus_unlocked = bool(parsed.bonus_unlocked)


func _save() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return
	var payload := {"best_times": best_times, "bonus_unlocked": bonus_unlocked}
	f.store_string(JSON.stringify(payload))
	f.close()
