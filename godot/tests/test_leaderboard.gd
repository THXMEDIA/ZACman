extends SceneTree
## Headless test: res://scripts/leaderboard.gd — the local Leaderboard
## autoload (one board per city_id/condition_id combination). A bare
## `--script` run has no autoloads initialized (same reason test_speedrun.gd
## does this), so this instantiates a fresh instance directly instead of
## referencing the `Leaderboard` global — its public methods all call
## _load()/_save() themselves rather than relying on _ready(), so a bare
## instance behaves identically to the real autoload. Run with
##   godot --headless --path . --script res://tests/test_leaderboard.gd
## Exits with code 0 on success, 1 on any failure.

const SaveIsolation := preload("res://tests/save_isolation.gd")


func _initialize() -> void:
	var failures := 0
	var checks := 0

	# QA-W6: own save folder for the whole run; the real file stays untouched.
	var real_saves := SaveIsolation.begin()

	var Leaderboard = load("res://scripts/leaderboard.gd").new()
	checks += 1
	if not Leaderboard.save_path().begins_with(SaveIsolation.SavePathsScript.TEST_ROOT):
		failures += 1
		print("FAIL the test should write to the test save folder, got %s" % Leaderboard.save_path())
	Leaderboard.reset_all()

	# --- board_key: "" normalizes to "none", different (city,cond) pairs
	# never collide ---
	checks += 1
	if Leaderboard.board_key("manhattan", "") != "manhattan|none":
		failures += 1
		print("FAIL board_key should normalize '' to 'none', got '%s'" % Leaderboard.board_key("manhattan", ""))
	checks += 1
	if Leaderboard.board_key("manhattan", "matrix_ghost") == Leaderboard.board_key("manhattan", "fear_and_loathing"):
		failures += 1
		print("FAIL different conditions on the same city should be different boards")
	checks += 1
	if Leaderboard.board_key("manhattan", "") == Leaderboard.board_key("klassik-1", ""):
		failures += 1
		print("FAIL different cities should be different boards")

	# --- modes: chat / pvp / coop never share a board with solo ---
	checks += 1
	var keys := {}
	for m in ["solo", "chat", "pvp", "coop"]:
		keys[Leaderboard.board_key("offen", "", m)] = true
	if keys.size() != 4:
		failures += 1
		print("FAIL every mode needs its own board key, got %s" % [keys.keys()])
	checks += 1
	if Leaderboard.board_key("offen", "") != "offen|none":
		failures += 1
		print("FAIL solo key should keep the short 'level|cond' form")

	# --- an empty board has no entries yet ---
	checks += 1
	if Leaderboard.get_top("manhattan", "").size() != 0:
		failures += 1
		print("FAIL a fresh board should start empty")

	# --- submit_time: sorted fastest-first, rank reported correctly ------
	var r1 = Leaderboard.submit_time("manhattan", "", 90.0, "Alice")
	checks += 1
	if r1.rank != 1 or not r1.is_new_best:
		failures += 1
		print("FAIL first submission should be rank 1 and a new best, got %s" % r1)

	var r2 = Leaderboard.submit_time("manhattan", "", 60.0, "Bob")
	checks += 1
	if r2.rank != 1:
		failures += 1
		print("FAIL a faster time should take rank 1, got %s" % r2)

	var r3 = Leaderboard.submit_time("manhattan", "", 120.0, "Carol")
	checks += 1
	if r3.rank != 3:
		failures += 1
		print("FAIL a slower time should rank behind the faster ones, got %s" % r3)

	var top = Leaderboard.get_top("manhattan", "", 5)
	checks += 1
	if top.size() != 3 or top[0].name != "Bob" or top[1].name != "Alice" or top[2].name != "Carol":
		failures += 1
		print("FAIL top entries should be sorted fastest-first: Bob, Alice, Carol — got %s" % [top])

	# --- is_new_best is per player name, not board-wide ------------------
	var r4 = Leaderboard.submit_time("manhattan", "", 200.0, "Alice") # slower than Alice's own 90.0
	checks += 1
	if r4.is_new_best:
		failures += 1
		print("FAIL a slower time than the same player's own best should not be a new best")

	var r5 = Leaderboard.submit_time("manhattan", "", 50.0, "Alice") # faster than Alice's own 90.0
	checks += 1
	if not r5.is_new_best:
		failures += 1
		print("FAIL a faster time than the same player's own best should be a new best")

	# --- a condition board is separate from the unconditioned one --------
	Leaderboard.submit_time("manhattan", "matrix_ghost", 999.0, "Solo")
	checks += 1
	if Leaderboard.get_top("manhattan", "matrix_ghost").size() != 1:
		failures += 1
		print("FAIL matrix_ghost board should have exactly the 1 entry submitted to it")
	checks += 1
	var unconditioned_names := []
	for e in Leaderboard.get_top("manhattan", ""):
		unconditioned_names.append(e.name)
	if "Solo" in unconditioned_names:
		failures += 1
		print("FAIL a matrix_ghost submission should not leak into the unconditioned board")

	# --- a chat run lands on the chat board only ---
	Leaderboard.submit_time("durchbruch", "", 70.0, "Streamer", "chat")
	Leaderboard.submit_time("durchbruch", "", 90.0, "Streamer", "solo")
	checks += 1
	if Leaderboard.get_top("durchbruch", "", 5, "chat").size() != 1 or Leaderboard.get_top("durchbruch", "", 5).size() != 1:
		failures += 1
		print("FAIL chat and solo submissions must land on separate boards")
	checks += 1
	if Leaderboard.get_top("durchbruch", "", 5)[0].time != 90.0:
		failures += 1
		print("FAIL the faster chat time must not appear on the solo board")
	checks += 1
	if Leaderboard.get_top("durchbruch", "", 5, "pvp").size() != 0 or Leaderboard.get_top("durchbruch", "", 5, "coop").size() != 0:
		failures += 1
		print("FAIL pvp/coop boards should be empty")

	# --- boards saved before the level pool are migrated ---
	Leaderboard.reset_all()
	var f := FileAccess.open(Leaderboard.save_path(), FileAccess.WRITE)
	f.store_string(JSON.stringify({
		"normal-1|none": [{"name": "Old", "time": 80.0}],
		"normal-3|matrix_ghost": [{"name": "Old", "time": 90.0}],
		"manhattan|none": [{"name": "Old", "time": 50.0}],
	}))
	f.close()
	var migrated = load("res://scripts/leaderboard.gd").new()
	checks += 1
	if migrated.get_top("klassik-2", "").size() != 1 or migrated.get_top("klassik-4", "matrix_ghost").size() != 1:
		failures += 1
		print("FAIL old normal-N boards should migrate to klassik-(N+1)")
	checks += 1
	if migrated.get_top("manhattan", "").size() != 0:
		failures += 1
		print("FAIL the old manhattan board should be dropped")
	migrated.free()

	# --- board caps at MAX_ENTRIES_PER_BOARD, keeping the fastest --------
	Leaderboard.reset_all()
	for i in Leaderboard.MAX_ENTRIES_PER_BOARD + 5:
		Leaderboard.submit_time("klassik-1", "", float(100 - i), "P%d" % i) # a range of distinct times
	var capped = Leaderboard.get_top("klassik-1", "", Leaderboard.MAX_ENTRIES_PER_BOARD + 10)
	checks += 1
	if capped.size() != Leaderboard.MAX_ENTRIES_PER_BOARD:
		failures += 1
		print("FAIL board should cap at MAX_ENTRIES_PER_BOARD (%d), got %d" % [Leaderboard.MAX_ENTRIES_PER_BOARD, capped.size()])

	# --- Code-W3: version field, type checks, no orphans ------------------
	var lb_script = load("res://scripts/leaderboard.gd")
	checks += 1
	var vf := FileAccess.open(Leaderboard.save_path(), FileAccess.READ)
	var saved = JSON.parse_string(vf.get_as_text())
	vf.close()
	if typeof(saved) != TYPE_DICTIONARY or saved.get("version", 0) != lb_script.SAVE_VERSION or typeof(saved.get("boards")) != TYPE_DICTIONARY:
		failures += 1
		print("FAIL a written save should be {version: %d, boards: {...}}, got %s" % [lb_script.SAVE_VERSION, str(saved).left(120)])
	checks += 1
	if FileAccess.file_exists(Leaderboard.save_path() + ".tmp"):
		failures += 1
		print("FAIL the atomic write must not leave its .tmp file behind")

	_write(Leaderboard.save_path(), JSON.stringify({
		"klassik-1|none": [
			{"name": "Ok", "time": 90.0},
			{"name": "NoTime"},
			{"time": 50.0},
			{"name": "Neg", "time": -3.0},
			{"name": "Str", "time": "fast"},
			{"name": 7, "time": 40.0},
			"garbage",
			null,
		],
		"klassik-2|none": "not a board",
		"normal-7|none": [{"name": "Orphan", "time": 60.0}],
		"normal-0|none": [{"name": "Old", "time": 70.0}],
	}))
	var dirty = lb_script.new()
	var top1: Array = dirty.get_top("klassik-1", "")
	checks += 1
	if top1.size() != 2 or top1[0].name != "Old" or top1[1].name != "Ok":
		failures += 1
		print("FAIL only well-formed entries should survive (and normal-0 merge into klassik-1), got %s" % [top1])
	checks += 1
	if dirty.get_top("klassik-8", "").size() != 0 or dirty._boards.has("klassik-8|none"):
		failures += 1
		print("FAIL normal-7 must not become an orphan klassik-8 board")
	checks += 1
	if dirty.loaded_version != 1:
		failures += 1
		print("FAIL an unversioned file should load as version 1, got %d" % dirty.loaded_version)
	var r_dirty: Dictionary = dirty.submit_time("klassik-1", "", 80.0, "After")
	checks += 1
	if r_dirty.rank != 2:
		failures += 1
		print("FAIL submit_time should keep working after loading a dirty board: %s" % [r_dirty])
	dirty.free()
	var reread = lb_script.new()
	var reread_top: Array = reread.get_top("klassik-1", "") # loads lazily, before loaded_version is read
	checks += 1
	if reread.loaded_version != lb_script.SAVE_VERSION or reread_top.size() != 3:
		failures += 1
		print("FAIL the re-saved file should be version %d with 3 klassik-1 entries" % lb_script.SAVE_VERSION)
	reread.free()

	# truncated JSON and wrong top-level type: start empty, still accept times
	for broken in ['{"version": 2, "boards": {"klassik-1|none": [{"name": "A", "ti', '[1, 2, 3]', '{"version": 2, "boards": 5}']:
		_write(Leaderboard.save_path(), broken)
		var b = lb_script.new()
		checks += 1
		var rb: Dictionary = b.submit_time("klassik-1", "", 99.0, "B")
		if b.get_top("klassik-1", "").size() != 1 or rb.rank != 1:
			failures += 1
			print("FAIL a broken file (%s) should load as empty and still take a time" % broken.left(30))
		b.free()

	# a file from a newer game version: not loaded, never overwritten
	var future := JSON.stringify({"version": lb_script.SAVE_VERSION + 1, "boards": {"klassik-1|none": [{"name": "F", "time": 10.0}]}})
	_write(Leaderboard.save_path(), future)
	var fut = lb_script.new()
	fut.submit_time("klassik-1", "", 50.0, "Now")
	fut.free()
	var ff := FileAccess.open(Leaderboard.save_path(), FileAccess.READ)
	var after_future := ff.get_as_text()
	ff.close()
	checks += 1
	if after_future != future:
		failures += 1
		print("FAIL a newer-version save must not be overwritten")
	Leaderboard.free()

	# --- QA-W6: the real save file was never touched ----------------------
	checks += 1
	if not SaveIsolation.end(real_saves):
		failures += 1
		print("FAIL the test changed the real save files")

	print("")
	if failures == 0:
		print("ALL %d LEADERBOARD CHECKS PASSED" % checks)
		quit(0)
	else:
		print("%d/%d LEADERBOARD CHECKS FAILED" % [failures, checks])
		quit(1)


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()
