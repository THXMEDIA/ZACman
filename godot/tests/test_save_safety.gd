extends SceneTree
## Headless test (W4, 03.10. review): broken or wrong-typed save files are
## kept as "<name>.corrupt-<unix time>" before the game writes over them, and
## SavePaths.write_atomic leaves its target untouched when a write fails.
## Covers Speedrun, Leaderboard, Settings and the high score. Run with
##   godot --headless --path . --script res://tests/test_save_safety.gd
## Exits with code 0 on success, 1 on any failure. Works in its own save
## folder (SaveIsolation); the real saves are checked to stay unchanged.

const SaveIsolation := preload("res://tests/save_isolation.gd")
const SavePathsScript := preload("res://scripts/save_paths.gd")
const SettingsScript := preload("res://scripts/settings.gd")

var failures := 0
var checks := 0


func _check(name: String, cond: bool, detail := "") -> void:
	checks += 1
	if not cond:
		failures += 1
		print("FAIL %s %s" % [name, detail])


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _read(path: String) -> String:
	if not FileAccess.file_exists(path):
		return "<missing>"
	var f := FileAccess.open(path, FileAccess.READ)
	var t := f.get_as_text()
	f.close()
	return t


func _remove_backups(path: String) -> void:
	for b in SavePathsScript.corrupt_backups(path):
		DirAccess.remove_absolute(b)


## One backup of `path` exists and holds exactly `original`.
func _backup_ok(path: String, original: String) -> String:
	var backups: Array = SavePathsScript.corrupt_backups(path)
	if backups.size() != 1:
		return "backups=%s" % [backups]
	var name: String = String(backups[0]).get_file()
	var stamp := name.substr(name.find(".corrupt-") + 9)
	if not stamp.split("-")[0].is_valid_int():
		return "bad name %s" % name
	if _read(backups[0]) != original:
		return "backup content differs"
	return ""


func _initialize() -> void:
	var real_saves := SaveIsolation.begin()
	var speedrun_script = load("res://scripts/speedrun.gd")
	var leaderboard_script = load("res://scripts/leaderboard.gd")

	# ---- write_atomic ------------------------------------------------------
	var target := SavePathsScript.path("atomic_test.json")
	_check("write_atomic: normal write", SavePathsScript.write_atomic(target, "{\"a\": 1}") and _read(target) == "{\"a\": 1}")
	_check("write_atomic: overwrite replaces the content", SavePathsScript.write_atomic(target, "{\"a\": 2}") and _read(target) == "{\"a\": 2}")
	_check("write_atomic: no .tmp left behind", not FileAccess.file_exists(target + ".tmp"))
	# a failing write (as on a full disk): target untouched, result false, no tmp
	SavePathsScript.simulate_write_failure = true
	var ok := SavePathsScript.write_atomic(target, "{\"a\": 3}")
	_check("write_atomic: a failed write returns false", not ok)
	_check("write_atomic: a failed write leaves the target untouched", _read(target) == "{\"a\": 2}", _read(target))
	_check("write_atomic: a failed write removes its .tmp", not FileAccess.file_exists(target + ".tmp"))
	# the temporary file can not even be opened (a directory sits in its place)
	DirAccess.make_dir_absolute(target + ".tmp")
	var ok2 := SavePathsScript.write_atomic(target, "{\"a\": 4}")
	_check("write_atomic: tmp not writable -> false, target untouched", not ok2 and _read(target) == "{\"a\": 2}")
	DirAccess.remove_absolute(target + ".tmp")
	DirAccess.remove_absolute(target)

	# ---- Speedrun: unparseable file -----------------------------------------
	var sr_path := SavePathsScript.path("zapmaniac_speedrun.json")
	var broken_text := "{ this is not json"
	_write(sr_path, broken_text)
	var sr = speedrun_script.new()
	sr.reload()
	_check("speedrun: an unparseable save is kept as .corrupt-<time>", _backup_ok(sr_path, broken_text) == "", _backup_ok(sr_path, broken_text))
	sr.record_level_time("klassik-1", 150.0, "woche", "solo", "2026-W40")
	_check("speedrun: the next save writes a fresh file, the backup stays", _read(sr_path).find("klassik-1|woche|solo") != -1 and _backup_ok(sr_path, broken_text) == "")
	_remove_backups(sr_path)

	# ---- Speedrun: wrong types inside a valid file ---------------------------
	var typed_text := JSON.stringify({"version": 5, "best_times": {"klassik-1|woche|solo": {"time": "schnell", "week": 5}, "klassik-2|woche|solo": {"time": 140.0, "week": "2026-W40"}}, "bonus_unlocked": "ja"})
	_write(sr_path, typed_text)
	sr.reload()
	_check("speedrun: wrong-typed values -> backup of the original", _backup_ok(sr_path, typed_text) == "", _backup_ok(sr_path, typed_text))
	_check("speedrun: the valid entry still loads", sr.best_for("klassik-2") == 140.0 and sr.best_for("klassik-1") == -1.0)
	_remove_backups(sr_path)
	# the game's next save writes the cleaned state; that clean file makes no backup
	sr.record_level_time("klassik-3", 200.0, "woche", "solo", "2026-W40")
	sr.reload()
	_check("speedrun: a clean file makes no backup", SavePathsScript.corrupt_backups(sr_path).is_empty())
	sr.reset_all()

	# ---- Leaderboard ----------------------------------------------------------
	var lb_path := SavePathsScript.path("zapmaniac_leaderboards.json")
	_write(lb_path, "[1, 2, 3")
	var lb = leaderboard_script.new()
	lb.reload()
	_check("leaderboard: an unparseable save is kept", _backup_ok(lb_path, "[1, 2, 3") == "")
	_remove_backups(lb_path)
	var lb_typed := JSON.stringify({"version": 5, "boards": {"klassik-1|woche|solo": [{"name": "Player", "time": 120.0, "week": "2026-W40"}, {"name": 7, "time": 99.0}, "kaputt"]}})
	_write(lb_path, lb_typed)
	lb.reload()
	_check("leaderboard: wrong-typed entries -> backup of the original", _backup_ok(lb_path, lb_typed) == "", _backup_ok(lb_path, lb_typed))
	_check("leaderboard: the valid entry still loads", lb.get_top("klassik-1", "woche").size() == 1)
	_remove_backups(lb_path)
	lb.submit_time("klassik-1", "woche", 110.0, "Player", "solo", "2026-W40", "matrix")
	lb.reload()
	_check("leaderboard: a file the game wrote makes no backup", SavePathsScript.corrupt_backups(lb_path).is_empty())
	lb.reset_all()

	# ---- Settings --------------------------------------------------------------
	var st_path := SettingsScript.save_path()
	var st_typed := "{\"version\": 3, \"reduce_fx\": \"yes\", \"fov\": 90}"
	_write(st_path, st_typed)
	var st := SettingsScript.load_settings()
	_check("settings: a wrong-typed field -> backup, default for it", _backup_ok(st_path, st_typed) == "" and st.reduce_fx == false and is_equal_approx(st.fov, 90.0))
	_remove_backups(st_path)
	_write(st_path, "nope")
	SettingsScript.load_settings()
	_check("settings: an unparseable file is kept", _backup_ok(st_path, "nope") == "")
	_remove_backups(st_path)
	SettingsScript.save_settings({"reduce_fx": true, "fov": 300.0, "mouse_sens": 0.01})
	var st2 := SettingsScript.load_settings()
	_check("settings v3: fov and mouse sensitivity stored, clamped to their ranges", st2.reduce_fx and is_equal_approx(st2.fov, SettingsScript.FOV_MAX) and is_equal_approx(st2.mouse_sens, SettingsScript.SENS_MIN))
	_check("settings v3: a clean file makes no backup", SavePathsScript.corrupt_backups(st_path).is_empty())
	_write(st_path, "{\"version\": 2, \"reduce_fx\": true, \"chaos\": true}")
	var st3 := SettingsScript.load_settings()
	_check("settings: a version-2 file loads, comfort values at their defaults", st3.reduce_fx and st3.chaos and is_equal_approx(st3.fov, 72.0) and is_equal_approx(st3.mouse_sens, 1.0) and SavePathsScript.corrupt_backups(st_path).is_empty())
	_remove_backups(st_path)
	DirAccess.remove_absolute(st_path)

	# ---- backup names never collide --------------------------------------------
	var p := SavePathsScript.path("twice.json")
	_write(p, "x")
	var b1 := SavePathsScript.backup_corrupt(p)
	var b2 := SavePathsScript.backup_corrupt(p)
	_check("backup: two backups in the same second get different names", b1 != "" and b2 != "" and b1 != b2 and SavePathsScript.corrupt_backups(p).size() == 2)
	_remove_backups(p)
	DirAccess.remove_absolute(p)

	_check("test isolation: real save files unchanged", SaveIsolation.end(real_saves))
	print("")
	if failures == 0:
		print("ALL %d SAVE SAFETY CHECKS PASSED" % checks)
		quit(0)
	else:
		print("%d/%d SAVE SAFETY CHECKS FAILED" % [failures, checks])
		quit(1)
