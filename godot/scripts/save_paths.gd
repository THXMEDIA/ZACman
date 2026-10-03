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


## Test hook (W4): makes the next write_atomic fail right after writing the
## temporary file, like a full disk would. Reset automatically.
static var simulate_write_failure := false


## Writes `text` atomically: first to "<path>.tmp", checked for write errors,
## then renamed over the target, so a crash or a failed write never leaves a
## half-written save behind. W4: on ANY failure the target stays exactly as
## it was (the temporary file is removed) and the result is false.
static func write_atomic(target: String, text: String) -> bool:
	var tmp := target + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(text)
	f.flush()
	var err := f.get_error()
	f.close()
	if simulate_write_failure:
		simulate_write_failure = false
		err = ERR_FILE_CANT_WRITE
	if err != OK or not _tmp_is_complete(tmp, text):
		DirAccess.remove_absolute(tmp)
		return false
	if DirAccess.rename_absolute(tmp, target) == OK:
		return true
	# Platforms whose rename does not replace an existing file: move the old
	# target aside first and put it back if the second rename fails too, so
	# the target is never lost.
	if not FileAccess.file_exists(target):
		DirAccess.remove_absolute(tmp)
		return false
	var bak := target + ".bak"
	DirAccess.remove_absolute(bak)
	if DirAccess.rename_absolute(target, bak) != OK:
		DirAccess.remove_absolute(tmp)
		return false
	if DirAccess.rename_absolute(tmp, target) == OK:
		DirAccess.remove_absolute(bak)
		return true
	DirAccess.rename_absolute(bak, target)
	DirAccess.remove_absolute(tmp)
	return false


## The temporary file holds exactly what was meant to be written (catches
## short writes that do not set an error flag).
static func _tmp_is_complete(tmp: String, text: String) -> bool:
	var f := FileAccess.open(tmp, FileAccess.READ)
	if f == null:
		return false
	var ok := f.get_length() == text.to_utf8_buffer().size()
	f.close()
	return ok


## W4: a save file that could not be read or had values of the wrong type is
## copied to "<name>.corrupt-<unix time>" before the game writes its next
## save over it — nothing the player had is ever destroyed silently. Returns
## the backup path ("" if there was nothing to back up or the copy failed).
## A second backup in the same second gets a counter suffix.
static func backup_corrupt(file_path: String) -> String:
	if not FileAccess.file_exists(file_path):
		return ""
	var stamp := int(Time.get_unix_time_from_system())
	var dest := "%s.corrupt-%d" % [file_path, stamp]
	var n := 1
	while FileAccess.file_exists(dest):
		dest = "%s.corrupt-%d-%d" % [file_path, stamp, n]
		n += 1
	if DirAccess.copy_absolute(file_path, dest) != OK:
		return ""
	push_warning("SavePaths: unreadable or invalid save kept as %s" % dest)
	return dest


## Backups made by backup_corrupt for `file_path` (tests).
static func corrupt_backups(file_path: String) -> Array:
	var out := []
	var dir := file_path.get_base_dir()
	var prefix := file_path.get_file() + ".corrupt-"
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for name in d.get_files():
		if name.begins_with(prefix):
			out.append(dir.path_join(name))
	return out
