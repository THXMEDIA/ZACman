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
	SAVE_PATH = SavePathsScript.path("zapmaniac_speedrun.json")
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

	# Third run beats the klassik-1 target (95.0) and is a new best -> unlocks bonus.
	var r3: Dictionary = sr.record_level_time("klassik-1", 85.0)
	checks += 1
	if not r3.is_new_best or not r3.beat_target or not r3.newly_unlocked_bonus:
		failures += 1
		print("FAIL fast run should be new best + beat target + unlock bonus: %s" % [r3])
	checks += 1
	if not sr.is_bonus_unlocked():
		failures += 1
		print("FAIL bonus should be unlocked after beating target")

	# Unlocking again on a later beat-target run must not re-report "newly" unlocked.
	var r4: Dictionary = sr.record_level_time("klassik-2", 130.0) # under the klassik-2 target (140.0)
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
	if sr2.best_for("klassik-1") != 85.0:
		failures += 1
		print("FAIL best_for should persist as 85.0, got %s" % sr2.best_for("klassik-1"))
	checks += 1
	if sr2.best_for("klassik-2") != 130.0:
		failures += 1
		print("FAIL best_for(klassik-2) should persist as 130.0, got %s" % sr2.best_for("klassik-2"))

	sr.free()
	sr2.free()

	# --- boards: woche / chaos / chat are separate; only woche+solo earns the badge
	DirAccess.remove_absolute(SAVE_PATH)
	var sr3 = speedrun_script.new()
	sr3.record_level_time("offen", 200.0, "woche", "solo", "2026-W40")
	var rc: Dictionary = sr3.record_level_time("offen", 120.0, "chaos")
	checks += 1
	if not rc.is_new_best or rc.previous_best != -1.0:
		failures += 1
		print("FAIL a chaos run should start its own best time: %s" % [rc])
	var rchat: Dictionary = sr3.record_level_time("offen", 100.0, "chat")
	checks += 1
	if not rchat.is_new_best or sr3.best_for("offen") != 200.0 or sr3.best_for("offen", "chaos") != 120.0 or sr3.best_for("offen", "chat") != 100.0:
		failures += 1
		print("FAIL woche, chaos and chat must not share best times: %s" % [sr3.best_times])
	checks += 1
	if sr3.best_for("offen", "woche", "pvp") != -1.0 or sr3.best_for("offen", "woche", "coop") != -1.0:
		failures += 1
		print("FAIL pvp/coop boards should start empty and separate")
	checks += 1
	if sr3.is_bonus_unlocked():
		failures += 1
		print("FAIL a chaos or chat run under the target must not earn the badge")
	checks += 1
	if not sr3.best_times.has("offen|woche|solo") or not sr3.best_times.has("offen|chaos|solo") or not sr3.best_times.has("offen|chat|solo"):
		failures += 1
		print("FAIL keys should have the form level|brett|modus, got %s" % [sr3.best_times.keys()])

	# --- the weekly board stores the ISO week with its (all-time) best -------
	checks += 1
	if sr3.best_entry("offen").get("week", "") != "2026-W40":
		failures += 1
		print("FAIL a weekly best time should carry its week, got %s" % [sr3.best_entry("offen")])
	sr3.record_level_time("offen", 210.0, "woche", "solo", "2026-W41") # slower: the all-time best keeps its week
	checks += 1
	if sr3.best_entry("offen").week != "2026-W40" or sr3.best_for("offen") != 200.0:
		failures += 1
		print("FAIL a slower run must not change the best time or its week")
	sr3.record_level_time("offen", 150.0, "woche", "solo", "2026-W41")
	checks += 1
	if sr3.best_entry("offen").week != "2026-W41" or sr3.best_for("offen") != 150.0:
		failures += 1
		print("FAIL a new all-time best should name its own week, got %s" % [sr3.best_entry("offen")])
	checks += 1
	if sr3.best_entry("offen", "chaos").get("week", "x") != "":
		failures += 1
		print("FAIL only the weekly board stores a week")
	var reread3 = speedrun_script.new()
	checks += 1
	if reread3.best_entry("offen").get("week", "") != "2026-W41" or reread3.best_for("offen", "chat") != 100.0:
		failures += 1
		print("FAIL week and boards must survive a save/load round trip")
	reread3.free()

	# --- badge: woche + solo, also with a condition (the condition is not in the key)
	var sr_badge = speedrun_script.new()
	sr_badge.reset_all()
	var rb_chaos: Dictionary = sr_badge.record_level_time("klassik-1", 50.0, "chaos")
	var rb_chat: Dictionary = sr_badge.record_level_time("klassik-1", 50.0, "chat")
	checks += 1
	if rb_chaos.newly_unlocked_bonus or rb_chat.newly_unlocked_bonus or sr_badge.is_bonus_unlocked():
		failures += 1
		print("FAIL chaos/chat runs must not earn the target-time badge")
	var rb_week: Dictionary = sr_badge.record_level_time("klassik-1", 50.0, "woche", "solo", "2026-W40")
	checks += 1
	if not rb_week.newly_unlocked_bonus:
		failures += 1
		print("FAIL a solo run on the weekly board under the target earns the badge")
	sr_badge.free()

	# --- Code-W8: an unknown board or mode records nothing --------------------
	var sr_bad = speedrun_script.new()
	sr_bad.reset_all()
	sr_bad.record_level_time("klassik-1", 50.0, "matrix_ghost")
	sr_bad.record_level_time("klassik-1", 50.0, "woche", "chat")
	sr_bad.record_level_time("manhattan", 50.0, "woche")
	checks += 1
	if not sr_bad.best_times.is_empty() or sr_bad.is_bonus_unlocked():
		failures += 1
		print("FAIL invalid keys must not create boards: %s" % [sr_bad.best_times])
	sr3.free()
	sr_bad.free()

	# --- migration v1/v2 -> v3 ----------------------------------------------
	# pre-pool index keys: plain solo runs without a rabbit -> archive
	DirAccess.remove_absolute(SAVE_PATH)
	_write(SAVE_PATH, JSON.stringify({"best_times": {"0": 61.5, "2": 99.0, "7": 10.0}, "bonus_unlocked": true}))
	var sr4 = speedrun_script.new()
	sr4.reload() # best_times/archive are read directly below: load first
	checks += 1
	if sr4.best_for("klassik-1") != -1.0 or sr4.archive.get("klassik-1|none", 0.0) != 61.5 or sr4.archive.get("klassik-3|none", 0.0) != 99.0 or sr4.archive.has("klassik-8|none"):
		failures += 1
		print("FAIL old index keys should be archived as klassik-N|none: %s / %s" % [sr4.best_times, sr4.archive])
	checks += 1
	if not sr4.is_bonus_unlocked() or sr4.loaded_version != 1:
		failures += 1
		print("FAIL migration must keep bonus_unlocked (version 1 file)")
	sr4.free()

	var v2 := {"version": 2, "bonus_unlocked": false, "best_times": {
		"klassik-1|none": 130.0,
		"klassik-1|matrix_ghost": 90.0,
		"klassik-2|fear_and_loathing": 150.0,
		"klassik-2|none|chat": 120.0,
		"offen|matrix_ghost|chat": 80.0,
		"durchbruch|woche": 140.0,
		"durchbruch|woche|chat": 111.0,
		"klassik-4|woche|pvp": 170.0,
		"klassik-3|none": "kaputt",
	}}
	_write(SAVE_PATH, JSON.stringify(v2))
	var mig = speedrun_script.new()
	mig.reload() # best_times/archive are read directly below: load first
	checks += 1
	var arch_keys := ["klassik-1|none", "klassik-1|matrix_ghost", "klassik-2|fear_and_loathing", "klassik-2|none|chat", "offen|matrix_ghost|chat"]
	var all_archived := true
	for k in arch_keys:
		if not mig.archive.has(k) or mig.archive[k] != v2.best_times[k]:
			all_archived = false
	if not all_archived or mig.archive.has("klassik-3|none"):
		failures += 1
		print("FAIL condition keys should be archived unchanged (invalid values dropped): %s" % [mig.archive])
	checks += 1
	if mig.best_for("klassik-1") != -1.0 or mig.best_for("klassik-2") != -1.0:
		failures += 1
		print("FAIL old 'none' times must not be taken over to the weekly board: %s" % [mig.best_times])
	checks += 1
	# Rules version 2 (Bewegungs-Paket): the Etappe-2 weekly keys still move to
	# level|woche|mode (chat board for |woche|chat), but as they were run without
	# Dash/Kehrtwende they land in the archive with the "|regel1" suffix.
	var rsuf: String = speedrun_script.RULES1_SUFFIX
	if mig.archive.get("durchbruch|woche|solo" + rsuf) != 140.0 or mig.archive.get("durchbruch|chat|solo" + rsuf) != 111.0 or mig.archive.get("klassik-4|woche|pvp" + rsuf) != 170.0:
		failures += 1
		print("FAIL Etappe-2 weekly keys should be archived as level|board|mode|regel1: %s" % [mig.archive])
	checks += 1
	if mig.best_times.size() != 0 or mig.archive.size() != arch_keys.size() + 3:
		failures += 1
		print("FAIL a file older than v4 must leave no live boards (all archived), got %s / %s" % [mig.best_times.keys(), mig.archive.keys()])
	var rmig: Dictionary = mig.record_level_time("klassik-1", 200.0, "woche", "solo", "2026-W40")
	checks += 1
	if not rmig.is_new_best:
		failures += 1
		print("FAIL the first weekly time after the migration is a new best (old none times archived)")
	mig.free()
	var rt_file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	var rt = JSON.parse_string(rt_file.get_as_text())
	rt_file.close()
	checks += 1
	if rt.get("version") != 4 or typeof(rt.get("archive")) != TYPE_DICTIONARY or rt.archive.size() != arch_keys.size() + 3:
		failures += 1
		print("FAIL the migrated file should be version 4 and keep the archive: %s" % str(rt).left(200))
	# round trip: load the v3 file, save it again: nothing changes
	var rt1 = speedrun_script.new()
	rt1.reload() # best_times/archive are read directly below: load first
	var times1: Dictionary = rt1.best_times.duplicate(true)
	var arch1: Dictionary = rt1.archive.duplicate(true)
	rt1.record_level_time("klassik-1", 250.0, "woche") # slower: no write
	rt1.bonus_unlocked = false
	rt1._save()
	rt1.free()
	var rt2 = speedrun_script.new()
	rt2.reload() # best_times/archive are read directly below: load first
	checks += 1
	if rt2.best_times != times1 or rt2.archive != arch1 or rt2.loaded_version != 4:
		failures += 1
		print("FAIL v4 round trip changed the data: %s vs %s" % [rt2.best_times, times1])
	rt2.free()
	# idempotent: migrating the same v2 file twice gives the same result
	var once: Dictionary = speedrun_script.migrate_best_times(v2.best_times, 2)
	var twice: Dictionary = speedrun_script.migrate_best_times(v2.best_times, 2)
	checks += 1
	if once != twice:
		failures += 1
		print("FAIL the migration should be deterministic")
	# a v3 file with an unknown key / broken entry: archived resp. dropped
	_write(SAVE_PATH, JSON.stringify({"version": 3, "best_times": {
		"klassik-1|woche|solo": {"time": 99.0, "week": "2026-W40"},
		"klassik-1|matrix|solo": {"time": 50.0, "week": ""},
		"klassik-2|woche|solo": {"time": "schnell"},
		"klassik-3|woche|solo": 77.0,
		"klassik-4|woche|solo": {"time": 120.0, "week": 40},
	}, "archive": {"alt|none": 12.0}}))
	var v3 = speedrun_script.new()
	v3.reload() # best_times/archive are read directly below: load first
	checks += 1
	# Rules version 2: valid v3 boards are archived as "|regel1", unknown keys and
	# the old archive stay; invalid values are dropped; no live board remains.
	if v3.best_for("klassik-1") != -1.0 or v3.best_times.size() != 0 or v3.archive.get("klassik-1|woche|solo" + rsuf) != 99.0 or v3.archive.get("klassik-4|woche|solo" + rsuf) != 120.0 or v3.archive.has("klassik-2|woche|solo" + rsuf) or v3.archive.has("klassik-3|woche|solo" + rsuf) or not v3.archive.has("klassik-1|matrix|solo") or not v3.archive.has("alt|none"):
		failures += 1
		print("FAIL v3 load should archive the boards as |regel1, type-check entries and keep the archive: %s / %s" % [v3.best_times, v3.archive])
	v3.free()

	# a v4 file keeps its live boards (the new rules' times count)
	_write(SAVE_PATH, JSON.stringify({"version": 4, "best_times": {
		"klassik-1|woche|solo": {"time": 88.0, "week": "2026-W41"},
	}, "archive": {"klassik-1|woche|solo" + rsuf: 99.0}}))
	var v4 = speedrun_script.new()
	v4.reload()
	checks += 1
	if v4.best_for("klassik-1") != 88.0 or v4.archive.get("klassik-1|woche|solo" + rsuf) != 99.0 or v4.loaded_version != 4:
		failures += 1
		print("FAIL a v4 file keeps live boards and its archive: %s / %s" % [v4.best_times, v4.archive])
	v4.free()

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
	dirty.reload() # best_times/archive are read directly below: load first
	checks += 1
	if not dirty.best_times.is_empty() or dirty.archive.size() != 1 or dirty.archive.get("offen|none", 0.0) != 88.0:
		failures += 1
		print("FAIL only valid times (> 0) should survive loading (and be archived): %s / %s" % [dirty.best_times, dirty.archive])
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

	for broken in ['{"version": 3, "best_times": {"klassik-1|woche|solo": 4', '"just a string"', '{"version": "zwei", "best_times": 3}']:
		_write(SAVE_PATH, broken)
		var b = speedrun_script.new()
		var rb: Dictionary = b.record_level_time("klassik-1", 150.0)
		checks += 1
		if not rb.is_new_best or b.best_for("klassik-1") != 150.0:
			failures += 1
			print("FAIL a broken save (%s) should load as empty and still record times" % broken.left(30))
		b.free()

	var future := JSON.stringify({"version": speedrun_script.SAVE_VERSION + 1, "best_times": {"klassik-1|woche|solo": 10.0}})
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

	# --- ZAP-8: split times ------------------------------------------
	var san = speedrun_script.sanitize_splits
	var split_cases := [
		[[10.0, 20.0, 30.0], 40.0, true],
		[[10.0, 20.0], 40.0, false],
		[[10.0, 10.0, 30.0], 40.0, true],
		[[30.0, 20.0, 10.0], 40.0, false],
		[[10.0, 20.0, 50.0], 40.0, false],
		[[0.0, 20.0, 30.0], 40.0, false],
		[[10.0, 20.0, "x"], 40.0, false],
		[[], 40.0, false],
	]
	for c in split_cases:
		checks += 1
		var got_ok: bool = san.call(c[0], c[1]).size() == 3
		if got_ok != c[2]:
			failures += 1
			print("FAIL sanitize_splits(%s, %s) accepted=%s, expected %s" % [c[0], c[1], got_ok, c[2]])
	DirAccess.remove_absolute(SAVE_PATH) # the previous test left a future-version file
	var sp = speedrun_script.new()
	sp.record_level_time("klassik-2", 60.0, "woche", "solo", "", [14.0, 30.0, 47.0])
	checks += 1
	if sp.best_splits_for("klassik-2", "woche", "solo") != [14.0, 30.0, 47.0]:
		failures += 1
		print("FAIL splits of a new best should be stored")
	sp.record_level_time("klassik-2", 70.0, "woche", "solo", "", [20.0, 40.0, 60.0])
	checks += 1
	if sp.best_splits_for("klassik-2", "woche", "solo") != [14.0, 30.0, 47.0]:
		failures += 1
		print("FAIL a slower run must not replace the best splits")
	sp.record_level_time("klassik-2", 55.0, "woche", "solo", "", [])
	checks += 1
	if not sp.best_splits_for("klassik-2", "woche", "solo").is_empty():
		failures += 1
		print("FAIL a new best without splits must not keep stale splits")
	sp.record_level_time("klassik-2", 50.0, "woche", "solo", "", [12.0, 25.0, 40.0])
	var sp2 = speedrun_script.new()
	checks += 1
	if sp2.best_splits_for("klassik-2", "woche", "solo") != [12.0, 25.0, 40.0]:
		failures += 1
		print("FAIL splits should survive a save/load round trip")
	checks += 1
	if sp2.best_splits_for("klassik-3", "woche", "solo") != []:
		failures += 1
		print("FAIL a board without a run has no splits")

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
