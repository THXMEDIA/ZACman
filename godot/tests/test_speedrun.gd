extends SceneTree
## Headless test: res://scripts/speedrun.gd (best times, target-time bonus
## unlock, persistence, time formatting). Run with
##   godot --headless --path . --script res://tests/test_speedrun.gd
## Exits with code 0 on success, 1 on any failure.
##
## Runs against its own, empty save folder (SaveIsolation, QA-W6): the real
## save file is never read, overwritten or deleted, and the test checks that.

const SaveIsolation := preload("res://tests/save_isolation.gd")
const SavePathsScript := preload("res://scripts/save_paths.gd")

var SAVE_PATH := ""


func _initialize() -> void:
	var failures := 0
	var checks := 0

	var real_saves := SaveIsolation.begin()
	SAVE_PATH = SavePathsScript.path("kugelschlucker_speedrun.json")
	checks += 1
	if not SAVE_PATH.begins_with(SavePathsScript.TEST_ROOT):
		failures += 1
		print("FAIL the test should use the test save folder, got %s" % SAVE_PATH)

	# --- format_time -------------------------------------------------
	var fmt_cases := [
		[-1.0, "--:--"],
		[0.0, "0:00.00"],
		[5.4, "0:05.40"],
		[74.2, "1:14.20"],
		[125.0, "2:05.00"],
	]
	var speedrun_script = load("res://scripts/speedrun.gd")
	for c in fmt_cases:
		checks += 1
		var got: String = speedrun_script.format_time(c[0])
		if got != c[1]:
			failures += 1
			print("FAIL format_time(%s) = %s, expected %s" % [c[0], got, c[1]])

	# target_for()'s hard-lower-bound guarantee (GD-K1) is verified against
	# the actual per-level target_s / reference route in test_levels.gd,
	# which rebuilds each level's real maze — a stronger check than
	# hardcoded numbers here could be.

	# --- record_level_time on a fresh instance ------------------------
	var sr = speedrun_script.new()

	checks += 1
	if sr.is_bonus_unlocked():
		failures += 1
		print("FAIL bonus should start locked on a clean save")

	checks += 1
	if sr.best_for("klassik-1") != -1.0:
		failures += 1
		print("FAIL best_for(klassik-1) should be -1.0 before any run")

	# First run on klassik-1, slower than target -> no bonus, is new best.
	var r1: Dictionary = sr.record_level_time("klassik-1", 200.0)
	checks += 1
	if not r1.is_new_best or r1.beat_target or r1.newly_unlocked_bonus:
		failures += 1
		print("FAIL first slow run: unexpected result %s" % [r1])

	# Second run, slower than the first -> not a new best, still no bonus.
	var r2: Dictionary = sr.record_level_time("klassik-1", 210.0)
	checks += 1
	if r2.is_new_best or r2.beat_target:
		failures += 1
		print("FAIL slower second run: unexpected result %s" % [r2])
	checks += 1
	if sr.best_for("klassik-1") != 200.0:
		failures += 1
		print("FAIL best_for should stay 200.0, got %s" % sr.best_for("klassik-1"))

	# Third run beats the klassik-1 target (115.0) and is a new best -> unlocks bonus.
	var r3: Dictionary = sr.record_level_time("klassik-1", 100.0)
	checks += 1
	if not r3.is_new_best or not r3.beat_target or not r3.newly_unlocked_bonus:
		failures += 1
		print("FAIL fast run should be new best + beat target + unlock bonus: %s" % [r3])
	checks += 1
	if not sr.is_bonus_unlocked():
		failures += 1
		print("FAIL bonus should be unlocked after beating target")

	# Unlocking again on a later beat-target run must not re-report "newly" unlocked.
	var r4: Dictionary = sr.record_level_time("klassik-2", 150.0) # under the klassik-2 target (170.0)
	checks += 1
	if r4.newly_unlocked_bonus:
		failures += 1
		print("FAIL bonus unlock should only fire once: %s" % [r4])

	# --- persistence across instances ---------------------------------
	var sr2 = speedrun_script.new()
	checks += 1
	if not sr2.is_bonus_unlocked():
		failures += 1
		print("FAIL bonus_unlocked should persist to a fresh Speedrun instance")
	checks += 1
	if sr2.best_for("klassik-1") != 100.0:
		failures += 1
		print("FAIL best_for should persist as 100.0, got %s" % sr2.best_for("klassik-1"))
	checks += 1
	if sr2.best_for("klassik-2") != 150.0:
		failures += 1
		print("FAIL best_for(klassik-2) should persist as 150.0, got %s" % sr2.best_for("klassik-2"))

	sr.free()
	sr2.free()

	# --- condition and mode boards are separate; only clean solo runs earn the badge
	DirAccess.remove_absolute(SAVE_PATH)
	var sr3 = speedrun_script.new()
	sr3.record_level_time("offen", 200.0)
	var rc: Dictionary = sr3.record_level_time("offen", 120.0, "matrix_ghost")
	checks += 1
	if not rc.is_new_best or rc.previous_best != -1.0:
		failures += 1
		print("FAIL a condition run should start its own best time: %s" % [rc])
	checks += 1
	if sr3.best_for("offen") != 200.0 or sr3.best_for("offen", "matrix_ghost") != 120.0:
		failures += 1
		print("FAIL conditions must not share best times")
	var rchat: Dictionary = sr3.record_level_time("offen", 100.0, "", "chat")
	checks += 1
	if not rchat.is_new_best or sr3.best_for("offen") != 200.0 or sr3.best_for("offen", "", "chat") != 100.0:
		failures += 1
		print("FAIL chat runs must have their own best time")
	checks += 1
	if sr3.best_for("offen", "", "pvp") != -1.0 or sr3.best_for("offen", "", "coop") != -1.0:
		failures += 1
		print("FAIL pvp/coop boards should start empty and separate")
	checks += 1
	if sr3.is_bonus_unlocked():
		failures += 1
		print("FAIL a condition or chat run under the target must not earn the badge")
	sr3.free()

	# --- saves from before the level pool (keyed by level index) are migrated
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify({"best_times": {"0": 61.5, "2": 99.0}, "bonus_unlocked": true}))
	f.close()
	var sr4 = speedrun_script.new()
	checks += 1
	if sr4.best_for("klassik-1") != 61.5 or sr4.best_for("klassik-3") != 99.0 or sr4.best_for("klassik-2") != -1.0:
		failures += 1
		print("FAIL old index keys should migrate to klassik-N")
	checks += 1
	if not sr4.is_bonus_unlocked():
		failures += 1
		print("FAIL migration must keep bonus_unlocked")
	sr4.free()

	# --- Code-W3: version field and type checks ---------------------------
	var sr5 = speedrun_script.new()
	sr5.record_level_time("klassik-1", 50.0)
	var vf := FileAccess.open(SAVE_PATH, FileAccess.READ)
	var saved = JSON.parse_string(vf.get_as_text())
	vf.close()
	checks += 1
	if typeof(saved) != TYPE_DICTIONARY or saved.get("version", 0) != speedrun_script.SAVE_VERSION:
		failures += 1
		print("FAIL a written save should carry version %d, got %s" % [speedrun_script.SAVE_VERSION, str(saved).left(120)])
	checks += 1
	if sr5.save_path() != SAVE_PATH or FileAccess.file_exists(SAVE_PATH + ".tmp"):
		failures += 1
		print("FAIL the save should land at the test path without a leftover .tmp file")
	sr5.free()

	_write(SAVE_PATH, JSON.stringify({"best_times": {
		"klassik-1|none": null,
		"klassik-2|none": "schnell",
		"klassik-3|none": -5.0,
		"klassik-4|none": 0.0,
		"offen|none": 88.0,
		"1": [1, 2],
	}, "bonus_unlocked": "yes"}))
	var dirty = speedrun_script.new()
	checks += 1
	if dirty.best_for("klassik-1") != -1.0 or dirty.best_for("klassik-2") != -1.0 or dirty.best_for("klassik-3") != -1.0 or dirty.best_for("klassik-4") != -1.0 or dirty.best_for("offen") != 88.0:
		failures += 1
		print("FAIL only valid times (> 0) should survive loading: %s" % [dirty.best_times])
	checks += 1
	if dirty.is_bonus_unlocked():
		failures += 1
		print("FAIL a non-bool bonus_unlocked must not unlock the badge")
	var rd: Dictionary = dirty.record_level_time("klassik-1", 200.0)
	checks += 1
	if not rd.is_new_best or dirty.best_for("klassik-1") != 200.0:
		failures += 1
		print("FAIL record_level_time should work after loading typo'd values: %s" % [rd])
	dirty.free()

	for broken in ['{"version": 2, "best_times": {"klassik-1|none": 4', '"just a string"', '{"version": "zwei", "best_times": 3}']:
		_write(SAVE_PATH, broken)
		var b = speedrun_script.new()
		var rb: Dictionary = b.record_level_time("klassik-1", 150.0)
		checks += 1
		if not rb.is_new_best or b.best_for("klassik-1") != 150.0:
			failures += 1
			print("FAIL a broken save (%s) should load as empty and still record times" % broken.left(30))
		b.free()

	var future := JSON.stringify({"version": speedrun_script.SAVE_VERSION + 1, "best_times": {"klassik-1|none": 10.0}})
	_write(SAVE_PATH, future)
	var fut = speedrun_script.new()
	fut.record_level_time("klassik-1", 50.0)
	fut.free()
	var ff := FileAccess.open(SAVE_PATH, FileAccess.READ)
	var after_future := ff.get_as_text()
	ff.close()
	checks += 1
	if after_future != future:
		failures += 1
		print("FAIL a newer-version save must not be overwritten")

	# --- QA-W6: real save untouched; test folder cleaned up --------------
	checks += 1
	if not SaveIsolation.end(real_saves):
		failures += 1
		print("FAIL the test changed the real save files")
	checks += 1
	if DirAccess.dir_exists_absolute(SavePathsScript.TEST_ROOT) or not SavePathsScript.is_default_root():
		failures += 1
		print("FAIL the test save folder should be removed and the root reset")

	print("")
	if failures == 0:
		print("ALL %d SPEEDRUN CHECKS PASSED" % checks)
		quit(0)
	else:
		print("%d/%d SPEEDRUN CHECKS FAILED" % [failures, checks])
		quit(1)


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()
