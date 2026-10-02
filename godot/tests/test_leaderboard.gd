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

func _initialize() -> void:
	var failures := 0
	var checks := 0

	var Leaderboard = load("res://scripts/leaderboard.gd").new()
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
	var f := FileAccess.open(Leaderboard.SAVE_PATH, FileAccess.WRITE)
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

	print("")
	if failures == 0:
		print("ALL %d LEADERBOARD CHECKS PASSED" % checks)
		quit(0)
	else:
		print("%d/%d LEADERBOARD CHECKS FAILED" % [failures, checks])
		quit(1)
