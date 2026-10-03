extends Node
## SaveMigration — autoload (first in the list, so it runs before Speedrun
## and Leaderboard load anything): carries save files over from the old
## project name once, silently.
##
## The project was renamed from "ZACman" (save files "kugelschlucker_*") to
## "ZAPmaniac" (save files "zapmaniac_*"). Changing application/config/name
## also moves Godot's user:// folder (…/app_userdata/ZACman →
## …/app_userdata/ZAPmaniac), so a player's best times and high score would
## silently vanish without this.
##
## For every save file that does NOT exist yet under its new name, the first
## of these that exists is copied over:
##   1. same folder, old file name   (user://kugelschlucker_<x>)
##   2. old folder, old file name    (<sibling "ZACman">/kugelschlucker_<x>)
## Existing new files are never overwritten and old files are never deleted,
## so the migration is idempotent and a player can always go back.
##
## Tests never trigger it: the automatic run only happens in a real game
## start (see should_run_on_startup()) while SavePaths points at its default
## root, and migrate() itself takes the two folders as parameters, so tests
## run it against their own test folders (SaveIsolation, QA-W6).

const SavePathsScript := preload("res://scripts/save_paths.gd")

const NEW_PREFIX := "zapmaniac_"
const OLD_PREFIX := "kugelschlucker_"
## Name of the user:// folder before the rename (old application/config/name).
const OLD_APP_DIR_NAME := "ZACman"
## The part of each save file name after the prefix (Speedrun, Leaderboard,
## Main's high score, Settings).
const FILE_SUFFIXES := [
	"speedrun.json",
	"leaderboards.json",
	"highscore.txt",
	"settings.json",
]


func _ready() -> void:
	if should_run_on_startup() and SavePathsScript.is_default_root():
		migrate(ProjectSettings.globalize_path(SavePathsScript.DEFAULT_ROOT), legacy_user_dir())


## The user:// folder the game used under its old name: a sibling of the
## current one (…/app_userdata/ZACman next to …/app_userdata/ZAPmaniac).
static func legacy_user_dir() -> String:
	return OS.get_user_data_dir().get_base_dir().path_join(OLD_APP_DIR_NAME)


## True only for a real game start. False for every test entry point: all
## tests run headless, run a script (--script/-s) or start a scene/script
## under res://tests/ or res://tools/ (QA screenshots) — none of them may
## ever touch a player's real save files.
static func should_run_on_startup() -> bool:
	if DisplayServer.get_name() == "headless":
		return false
	for arg in OS.get_cmdline_args():
		if arg == "--script" or arg == "-s":
			return false
		if arg.begins_with("res://tests/") or arg.begins_with("res://tools/"):
			return false
	return true


## Copies missing "zapmaniac_*" files in `new_dir` from their "kugelschlucker_*"
## predecessors (first `new_dir`, then `old_dir`). Returns the new file paths
## that were created. Safe to call any number of times.
static func migrate(new_dir: String, old_dir: String) -> Array[String]:
	var created: Array[String] = []
	for suffix in FILE_SUFFIXES:
		var target := new_dir.path_join(NEW_PREFIX + suffix)
		if FileAccess.file_exists(target):
			continue
		for source in [new_dir.path_join(OLD_PREFIX + suffix), old_dir.path_join(OLD_PREFIX + suffix)]:
			if FileAccess.file_exists(source):
				if _copy(source, target):
					created.append(target)
				break
	return created


## Copies via "<target>.tmp" + rename (like SavePaths.write_atomic), so an
## interrupted copy never leaves a half-written save under the real name.
static func _copy(source: String, target: String) -> bool:
	DirAccess.make_dir_recursive_absolute(target.get_base_dir())
	var tmp := target + ".tmp"
	if DirAccess.copy_absolute(source, tmp) != OK:
		DirAccess.remove_absolute(tmp)
		return false
	if DirAccess.rename_absolute(tmp, target) != OK:
		DirAccess.remove_absolute(tmp)
		return false
	return true
