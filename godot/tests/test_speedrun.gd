extends SceneTree
## Headless test: res://scripts/speedrun.gd (best times, target-time bonus
## unlock, persistence, time formatting). Run with
##   godot --headless --path . --script res://tests/test_speedrun.gd
## Exits with code 0 on success, 1 on any failure.
##
## Starts by wiping the real save file so this run doesn't inherit state
## left over from a normal play session or from BotTest.tscn (which also
## exercises Speedrun.record_level_time via Main's level-clear flow).

const SAVE_PATH := "user://kugelschlucker_speedrun.json"


func _initialize() -> void:
	var failures := 0
	var checks := 0

	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)

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

	# --- record_level_time on a fresh instance ------------------------
	var sr = speedrun_script.new()

	checks += 1
	if sr.is_bonus_unlocked():
		failures += 1
		print("FAIL bonus should start locked on a clean save")

	checks += 1
	if sr.best_for(0) != -1.0:
		failures += 1
		print("FAIL best_for(0) should be -1.0 before any run")

	# First run on level 0, slower than target (55.0) -> no bonus, is new best.
	var r1: Dictionary = sr.record_level_time(0, 80.0)
	checks += 1
	if not r1.is_new_best or r1.beat_target or r1.newly_unlocked_bonus:
		failures += 1
		print("FAIL first slow run: unexpected result %s" % [r1])

	# Second run, slower than the first -> not a new best, still no bonus.
	var r2: Dictionary = sr.record_level_time(0, 90.0)
	checks += 1
	if r2.is_new_best or r2.beat_target:
		failures += 1
		print("FAIL slower second run: unexpected result %s" % [r2])
	checks += 1
	if sr.best_for(0) != 80.0:
		failures += 1
		print("FAIL best_for(0) should stay 80.0, got %s" % sr.best_for(0))

	# Third run beats the level-0 target (55.0) and is a new best -> unlocks bonus.
	var r3: Dictionary = sr.record_level_time(0, 40.0)
	checks += 1
	if not r3.is_new_best or not r3.beat_target or not r3.newly_unlocked_bonus:
		failures += 1
		print("FAIL fast run should be new best + beat target + unlock bonus: %s" % [r3])
	checks += 1
	if not sr.is_bonus_unlocked():
		failures += 1
		print("FAIL bonus should be unlocked after beating target")

	# Unlocking again on a later beat-target run must not re-report "newly" unlocked.
	var r4: Dictionary = sr.record_level_time(1, 30.0) # well under level-1 target (70.0)
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
	if sr2.best_for(0) != 40.0:
		failures += 1
		print("FAIL best_for(0) should persist as 40.0, got %s" % sr2.best_for(0))
	checks += 1
	if sr2.best_for(1) != 30.0:
		failures += 1
		print("FAIL best_for(1) should persist as 30.0, got %s" % sr2.best_for(1))

	sr.free()
	sr2.free()

	# Leave no trace for the next real play session / BotTest run.
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)

	print("")
	if failures == 0:
		print("ALL %d SPEEDRUN CHECKS PASSED" % checks)
		quit(0)
	else:
		print("%d/%d SPEEDRUN CHECKS FAILED" % [failures, checks])
		quit(1)
