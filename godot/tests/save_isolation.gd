extends RefCounted
## SaveIsolation — test helper (QA-W6): every test that touches Speedrun,
## Leaderboard or Main's high score calls begin() first and end() last.
##
## begin() points SavePaths at SavePaths.TEST_ROOT (an empty folder of its
## own) and remembers a fingerprint of the REAL save files; end() deletes
## the test folder, restores the default root and reports whether the real
## files are byte-for-byte what they were before. A test that wrote to the
## real location would change that fingerprint (in a clean environment the
## real files do not exist, so any write there shows up as "created").

const SavePathsScript := preload("res://scripts/save_paths.gd")

const SAVE_FILES := [
	"kugelschlucker_speedrun.json",
	"kugelschlucker_leaderboards.json",
	"kugelschlucker_highscore.txt",
	"kugelschlucker_settings.json",
]


## Returns the fingerprint of the real files, to hand to end().
static func begin() -> Dictionary:
	var snapshot := real_fingerprint()
	_wipe_test_root()
	SavePathsScript.use_root(SavePathsScript.TEST_ROOT)
	return snapshot


## Cleans up and returns true if the real save files are unchanged.
static func end(snapshot: Dictionary) -> bool:
	_wipe_test_root()
	SavePathsScript.reset_root()
	return real_fingerprint() == snapshot


## {file name: md5 of its content, or "" if it does not exist}.
static func real_fingerprint() -> Dictionary:
	var out := {}
	for name in SAVE_FILES:
		var p: String = SavePathsScript.default_path(name)
		out[name] = FileAccess.get_md5(p) if FileAccess.file_exists(p) else ""
	return out


static func _wipe_test_root() -> void:
	var dir := DirAccess.open(SavePathsScript.TEST_ROOT)
	if dir == null:
		return
	for f in dir.get_files():
		dir.remove(f)
	DirAccess.remove_absolute(SavePathsScript.TEST_ROOT)
