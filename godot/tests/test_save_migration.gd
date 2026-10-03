extends SceneTree
## Headless test: res://scripts/save_migration.gd (one-time copy of the old
## "kugelschlucker_*" save files after the rename to ZAPmaniac). Run with
##   godot --headless --path . --script res://tests/test_save_migration.gd
## Exits with code 0 on success, 1 on any failure.
##
## Runs inside SaveIsolation (QA-W6): only in its own test folders
## (TEST_ROOT/ZAPmaniac as the "new" user folder, TEST_ROOT/ZACman as the
## "old" one), and SaveIsolation.end() checks that the real save files —
## new and old names, current and old folder — are untouched.

const MigrationScript := preload("res://scripts/save_migration.gd")
const SaveIsolation := preload("res://tests/save_isolation.gd")
const SavePathsScript := preload("res://scripts/save_paths.gd")

const TEST_ROOT := SavePathsScript.TEST_ROOT + "/migration"
const NEW_DIR := TEST_ROOT + "/ZAPmaniac"
const OLD_DIR := TEST_ROOT + "/ZACman"

var failures := 0
var checks := 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL %s %s" % [label, detail])


func _write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _read(path: String) -> String:
	if not FileAccess.file_exists(path):
		return "<missing>"
	return FileAccess.get_file_as_string(path)


func _wipe(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for sub in dir.get_directories():
		_wipe(dir_path.path_join(sub))
	for f in dir.get_files():
		dir.remove(f)
	DirAccess.remove_absolute(dir_path)


func _initialize() -> void:
	var real_saves := SaveIsolation.begin()
	_wipe(TEST_ROOT)

	# --- guard: never runs automatically in a test ---------------------
	_check("startup guard is off in a headless test run", not MigrationScript.should_run_on_startup())
	_check("SavePaths is redirected, so the autoload would skip too", not SavePathsScript.is_default_root())
	_check("the test folders lie under the test save root", TEST_ROOT.begins_with(SavePathsScript.TEST_ROOT), TEST_ROOT)
	var legacy: String = MigrationScript.legacy_user_dir()
	_check("old folder is the 'ZACman' sibling of the user folder",
		legacy.get_file() == "ZACman" and legacy.get_base_dir() == OS.get_user_data_dir().get_base_dir(), legacy)

	# --- scenario -------------------------------------------------------
	# speedrun:     only in the old folder               -> copied from there
	# leaderboards: old name in BOTH folders             -> same folder wins
	# highscore:    nowhere                              -> nothing created
	# settings:     new file already exists + old ones   -> left alone
	_write(OLD_DIR.path_join("kugelschlucker_speedrun.json"), "{\"old_dir\":\"speedrun\"}")
	_write(NEW_DIR.path_join("kugelschlucker_leaderboards.json"), "{\"same_dir\":\"boards\"}")
	_write(OLD_DIR.path_join("kugelschlucker_leaderboards.json"), "{\"old_dir\":\"boards\"}")
	_write(NEW_DIR.path_join("zapmaniac_settings.json"), "{\"new\":true}")
	_write(NEW_DIR.path_join("kugelschlucker_settings.json"), "{\"same_dir\":\"settings\"}")
	_write(OLD_DIR.path_join("kugelschlucker_settings.json"), "{\"old_dir\":\"settings\"}")

	var created: Array[String] = MigrationScript.migrate(NEW_DIR, OLD_DIR)
	_check("two files migrated", created.size() == 2, str(created))
	_check("speedrun copied from the old folder",
		_read(NEW_DIR.path_join("zapmaniac_speedrun.json")) == "{\"old_dir\":\"speedrun\"}")
	_check("leaderboards copied from the same folder first",
		_read(NEW_DIR.path_join("zapmaniac_leaderboards.json")) == "{\"same_dir\":\"boards\"}")
	_check("no high score file invented", not FileAccess.file_exists(NEW_DIR.path_join("zapmaniac_highscore.txt")))
	_check("an existing new file is never overwritten",
		_read(NEW_DIR.path_join("zapmaniac_settings.json")) == "{\"new\":true}")
	_check("old files are kept (old folder)",
		_read(OLD_DIR.path_join("kugelschlucker_speedrun.json")) == "{\"old_dir\":\"speedrun\"}"
		and _read(OLD_DIR.path_join("kugelschlucker_leaderboards.json")) == "{\"old_dir\":\"boards\"}")
	_check("old files are kept (same folder)",
		_read(NEW_DIR.path_join("kugelschlucker_leaderboards.json")) == "{\"same_dir\":\"boards\"}")
	_check("no temp files left behind", not FileAccess.file_exists(NEW_DIR.path_join("zapmaniac_speedrun.json.tmp")))

	# --- idempotent: a second start changes nothing ----------------------
	_write(OLD_DIR.path_join("kugelschlucker_speedrun.json"), "{\"old_dir\":\"changed later\"}")
	var again: Array[String] = MigrationScript.migrate(NEW_DIR, OLD_DIR)
	_check("second run migrates nothing", again.is_empty(), str(again))
	_check("second run keeps the already migrated file",
		_read(NEW_DIR.path_join("zapmaniac_speedrun.json")) == "{\"old_dir\":\"speedrun\"}")

	# --- the old folder may not exist at all (fresh install) -------------
	_wipe(TEST_ROOT)
	DirAccess.make_dir_recursive_absolute(NEW_DIR)
	_check("fresh install: nothing to migrate", MigrationScript.migrate(NEW_DIR, OLD_DIR).is_empty())

	# --- clean up, real files untouched ---------------------------------
	_wipe(TEST_ROOT)
	_check("test folder removed", not DirAccess.dir_exists_absolute(TEST_ROOT))
	_check("real save files unchanged", SaveIsolation.end(real_saves))
	_check("save root restored", SavePathsScript.is_default_root())

	print("")
	if failures == 0:
		print("ALL %d SAVE MIGRATION CHECKS PASSED" % checks)
		quit(0)
	else:
		print("%d/%d SAVE MIGRATION CHECKS FAILED" % [failures, checks])
		quit(1)
