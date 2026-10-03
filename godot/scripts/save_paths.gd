extends RefCounted
## SavePaths — the one place that decides where persistent files live
## (Speedrun best times, Leaderboard boards, Main's high score).
##
## Normally everything goes to "user://". Tests switch the root to their own
## directory (use_root) before touching any save, so a test run never reads,
## overwrites or deletes a player's real save files (QA-W6), and put it back
## with reset_root() when they are done.
##
## Static state lives on the script resource, so every user of this script
## (autoloads, Main, test scripts) sees the same root.

const DEFAULT_ROOT := "user://"
## The directory tests use. Kept under user:// so it works on every
## platform, but in its own folder with its own file names' copies — the
## real files next to it are never opened by a test.
const TEST_ROOT := "user://test_saves"

static var root := DEFAULT_ROOT


## Full path of a save file under the current root.
static func path(file_name: String) -> String:
	return root.path_join(file_name)


## The path the file has in a normal (non-test) game, independent of the
## current root — only for tests that check the real file stays untouched.
static func default_path(file_name: String) -> String:
	return DEFAULT_ROOT.path_join(file_name)


static func use_root(dir: String) -> void:
	root = dir
	DirAccess.make_dir_recursive_absolute(dir)


static func reset_root() -> void:
	root = DEFAULT_ROOT


static func is_default_root() -> bool:
	return root == DEFAULT_ROOT


## Writes `text` atomically: first to "<path>.tmp", then renamed over the
## target, so a crash mid-write never leaves a half-written save behind.
static func write_atomic(target: String, text: String) -> bool:
	var tmp := target + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(text)
	f.close()
	if DirAccess.rename_absolute(tmp, target) == OK:
		return true
	# Platforms whose rename does not replace an existing file: fall back to
	# remove + rename (a short non-atomic window, still never a torn file).
	DirAccess.remove_absolute(target)
	return DirAccess.rename_absolute(tmp, target) == OK
