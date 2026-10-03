extends SceneTree
## Headless test: res://scripts/leaderboard.gd — the local Leaderboard
## autoload (one board per level × board × mode, key "level|brett|modus").
## A bare `--script` run has no autoloads initialized, so this instantiates
## fresh instances directly instead of referencing the `Leaderboard` global —
## its public methods call _load()/_save() themselves, so a bare instance
## behaves like the real autoload (fields read directly need reload() first).
## Run with
##   godot --headless --path . --script res://tests/test_leaderboard.gd
## Exits with code 0 on success, 1 on any failure.

const SaveIsolation := preload("res://tests/save_isolation.gd")

var failures := 0
var checks := 0


func _check(name: String, cond: bool, detail := "") -> void:
	checks += 1
	if not cond:
		failures += 1
		print("FAIL %s %s" % [name, detail])


func _initialize() -> void:
	# QA-W6: own save folder for the whole run; the real file stays untouched.
	var real_saves := SaveIsolation.begin()
	var lb_script = load("res://scripts/leaderboard.gd")
	var lb = lb_script.new()
	_check("the test writes to the test save folder", lb.save_path().begins_with(SaveIsolation.SavePathsScript.TEST_ROOT), lb.save_path())
	lb.reset_all()

	# --- board keys: level|brett|modus, the condition is not part of it ----
	_check("board key form level|brett|modus", lb.board_key("klassik-1", "woche") == "klassik-1|woche|solo", lb.board_key("klassik-1", "woche"))
	var keys := {}
	for b in ["woche", "chaos", "chat"]:
		for m in ["solo", "pvp", "coop"]:
			keys[lb.board_key("offen", b, m)] = true
	_check("every board and mode has its own key", keys.size() == 9, str(keys.keys()))
	_check("different levels are different boards", lb.board_key("offen", "woche") != lb.board_key("klassik-1", "woche"))

	# --- an empty board has no entries yet ---
	_check("a fresh board starts empty", lb.get_top("klassik-1", "woche").size() == 0)

	# --- submit_time: sorted fastest-first, rank reported correctly ------
	var r1 = lb.submit_time("klassik-1", "woche", 90.0, "Alice", "solo", "2026-W40")
	_check("first submission is rank 1 and a new best", r1.rank == 1 and r1.is_new_best, str(r1))
	var r2 = lb.submit_time("klassik-1", "woche", 60.0, "Bob", "solo", "2026-W40")
	_check("a faster time takes rank 1", r2.rank == 1, str(r2))
	var r3 = lb.submit_time("klassik-1", "woche", 120.0, "Carol", "solo", "2026-W41")
	_check("a slower time ranks behind", r3.rank == 3, str(r3))
	var top: Array = lb.get_top("klassik-1", "woche", 5)
	_check("top entries sorted fastest-first", top.size() == 3 and top[0].name == "Bob" and top[1].name == "Alice" and top[2].name == "Carol", str(top))

	# --- weekly board: every entry carries its ISO week -------------------
	_check("weekly entries carry their week", top[0].week == "2026-W40" and top[2].week == "2026-W41", str(top))
	lb.submit_time("klassik-1", "chaos", 70.0, "Dora", "solo", "2026-W40")
	_check("chaos entries store no week", lb.get_top("klassik-1", "chaos")[0].week == "")

	# --- is_new_best is per player name, not board-wide ------------------
	_check("slower than own best: no new best", not lb.submit_time("klassik-1", "woche", 200.0, "Alice").is_new_best)
	_check("faster than own best: new best", lb.submit_time("klassik-1", "woche", 50.0, "Alice", "solo", "2026-W41").is_new_best)

	# --- boards are separate -----------------------------------------------
	lb.submit_time("durchbruch", "chat", 70.0, "Streamer")
	lb.submit_time("durchbruch", "woche", 90.0, "Streamer", "solo", "2026-W40")
	_check("chat and woche submissions land on separate boards", lb.get_top("durchbruch", "chat").size() == 1 and lb.get_top("durchbruch", "woche").size() == 1)
	_check("the faster chat time is not on the weekly board", lb.get_top("durchbruch", "woche")[0].time == 90.0)
	_check("chaos/pvp/coop boards stay empty", lb.get_top("durchbruch", "chaos").size() == 0 and lb.get_top("durchbruch", "woche", 5, "pvp").size() == 0 and lb.get_top("durchbruch", "woche", 5, "coop").size() == 0)

	# --- Code-W8: unknown board, mode or level records nothing -------------
	var bad1: Dictionary = lb.submit_time("klassik-1", "matrix_ghost", 10.0, "X")
	var bad2: Dictionary = lb.submit_time("klassik-1", "woche", 10.0, "X", "chat")
	var bad3: Dictionary = lb.submit_time("manhattan", "woche", 10.0, "X")
	lb.reload()
	var any_bad := false
	for k in lb._boards.keys():
		if not load("res://scripts/levels.gd").is_valid_board_key(k):
			any_bad = true
	_check("invalid keys are refused (rank -1, no new board)", bad1.rank == -1 and bad2.rank == -1 and bad3.rank == -1 and not any_bad, str(lb._boards.keys()))

	# --- board caps at MAX_ENTRIES_PER_BOARD, keeping the fastest --------
	lb.reset_all()
	for i in lb.MAX_ENTRIES_PER_BOARD + 5:
		lb.submit_time("klassik-1", "woche", float(100 - i), "P%d" % i)
	var capped: Array = lb.get_top("klassik-1", "woche", lb.MAX_ENTRIES_PER_BOARD + 10)
	_check("board caps at MAX_ENTRIES_PER_BOARD", capped.size() == lb.MAX_ENTRIES_PER_BOARD, str(capped.size()))

	# --- written file: version 3, boards, atomic --------------------------
	var saved = _read_json(lb.save_path())
	_check("a written save is {version: 3, boards: {...}}", typeof(saved) == TYPE_DICTIONARY and saved.get("version", 0) == lb_script.SAVE_VERSION and lb_script.SAVE_VERSION == 3 and typeof(saved.get("boards")) == TYPE_DICTIONARY, str(saved).left(120))
	_check("the atomic write leaves no .tmp file", not FileAccess.file_exists(lb.save_path() + ".tmp"))

	# --- migration v1 (before the level pool, top-level boards) -----------
	lb.reset_all()
	_write(lb.save_path(), JSON.stringify({
		"normal-1|none": [{"name": "Old", "time": 80.0}],
		"normal-3|matrix_ghost": [{"name": "Old", "time": 90.0}],
		"normal-7|none": [{"name": "Orphan", "time": 60.0}],
		"manhattan|none": [{"name": "Old", "time": 50.0}],
	}))
	var m1 = lb_script.new()
	m1.reload()
	_check("v1: no board survives (all were condition boards)", m1._boards.is_empty(), str(m1._boards.keys()))
	_check("v1: every old board is archived under its original key (nothing deleted)", m1.archive.has("normal-1|none") and m1.archive.has("normal-3|matrix_ghost") and m1.archive.has("normal-7|none") and m1.archive.has("manhattan|none") and not m1._boards.has("klassik-8|none"), str(m1.archive.keys()))
	_check("v1: loaded as version 1", m1.loaded_version == 1)
	m1.free()

	# --- migration v2 (condition keys + Etappe-2 weekly keys) --------------
	var v2_boards := {
		"klassik-1|none": [{"name": "A", "time": 130.0}, {"name": "B", "time": 140.0}],
		"klassik-1|matrix_ghost": [{"name": "A", "time": 90.0}],
		"klassik-2|fear_and_loathing|chat": [{"name": "A", "time": 150.0}],
		"offen|none|chat": [{"name": "A", "time": 99.0}],
		"durchbruch|woche": [{"name": "W", "time": 140.0}],
		"durchbruch|woche|chat": [{"name": "C", "time": 111.0}],
		"klassik-3|woche|coop": [{"name": "K", "time": 160.0}],
		"klassik-4|none": "kaputt",
	}
	_write(lb.save_path(), JSON.stringify({"version": 2, "boards": v2_boards}))
	var m2 = lb_script.new()
	m2.reload()
	var archived := ["klassik-1|none", "klassik-1|matrix_ghost", "klassik-2|fear_and_loathing|chat", "offen|none|chat"]
	var all_in := true
	for k in archived:
		if not m2.archive.has(k) or m2.archive[k].size() != v2_boards[k].size():
			all_in = false
	_check("v2: condition boards are archived with all their entries", all_in and m2.archive.size() == archived.size(), str(m2.archive.keys()))
	_check("v2: archived boards are never shown", m2.get_top("klassik-1", "woche").size() == 0 and m2.get_top("offen", "chat").size() == 0)
	_check("v2: old 'none' times are not taken over to the weekly board", m2.get_top("klassik-1", "woche").is_empty())
	_check("v2: Etappe-2 weekly boards move to level|woche|mode (week unknown)", m2.get_top("durchbruch", "woche").size() == 1 and m2.get_top("durchbruch", "woche")[0].week == "" and m2.get_top("klassik-3", "woche", 5, "coop").size() == 1)
	_check("v2: |woche|chat moves to the chat board", m2.get_top("durchbruch", "chat").size() == 1 and m2.get_top("durchbruch", "chat")[0].name == "C")
	m2.submit_time("klassik-1", "woche", 125.0, "Neu", "solo", "2026-W40")
	m2.free()
	var after = _read_json(lb.save_path())
	_check("v2 -> v3: file rewritten as version 3 with the archive", after.get("version") == 3 and typeof(after.get("archive")) == TYPE_DICTIONARY and after.archive.size() == archived.size(), str(after).left(160))

	# --- round trip: v3 load + save changes nothing --------------------------
	var rt1 = lb_script.new()
	rt1.reload()
	var boards1: Dictionary = rt1._boards.duplicate(true)
	var arch1: Dictionary = rt1.archive.duplicate(true)
	rt1._save()
	rt1.free()
	var rt2 = lb_script.new()
	rt2.reload()
	_check("v3 round trip keeps boards and archive", rt2._boards == boards1 and rt2.archive == arch1 and rt2.loaded_version == 3)
	_check("v3 round trip keeps the week of an entry", rt2.get_top("klassik-1", "woche")[0].week == "2026-W40")
	rt2.free()

	# --- v3 with an unknown key: archived; dirty entries dropped -----------
	_write(lb.save_path(), JSON.stringify({"version": 3, "boards": {
		"klassik-1|woche|solo": [
			{"name": "Ok", "time": 90.0, "week": "2026-W40"},
			{"name": "NoTime"},
			{"time": 50.0},
			{"name": "Neg", "time": -3.0},
			{"name": "Str", "time": "fast"},
			{"name": 7, "time": 40.0},
			{"name": "BadWeek", "time": 95.0, "week": 40},
			"garbage",
			null,
		],
		"klassik-2|woche|solo": "not a board",
		"klassik-1|psychedelic|solo": [{"name": "Z", "time": 70.0}],
	}, "archive": {"alt|none": [{"name": "Alt", "time": 12.0}]}}))
	var dirty = lb_script.new()
	var top1: Array = dirty.get_top("klassik-1", "woche")
	_check("only well-formed entries survive", top1.size() == 2 and top1[0].name == "Ok" and top1[1].name == "BadWeek" and top1[1].week == "", str(top1))
	_check("an unknown v3 key goes to the archive, the old archive stays", dirty.archive.has("klassik-1|psychedelic|solo") and dirty.archive.has("alt|none"), str(dirty.archive.keys()))
	var r_dirty: Dictionary = dirty.submit_time("klassik-1", "woche", 80.0, "After")
	_check("submit_time keeps working after a dirty file", r_dirty.rank == 1, str(r_dirty))
	dirty.free()

	# truncated JSON and wrong top-level type: start empty, still accept times
	for broken in ['{"version": 3, "boards": {"klassik-1|woche|solo": [{"name": "A", "ti', '[1, 2, 3]', '{"version": 3, "boards": 5}']:
		_write(lb.save_path(), broken)
		var b = lb_script.new()
		var rb: Dictionary = b.submit_time("klassik-1", "woche", 99.0, "B")
		_check("a broken file (%s) loads empty and still takes a time" % broken.left(30), b.get_top("klassik-1", "woche").size() == 1 and rb.rank == 1)
		b.free()

	# a file from a newer game version: not loaded, never overwritten
	var future := JSON.stringify({"version": lb_script.SAVE_VERSION + 1, "boards": {"klassik-1|woche|solo": [{"name": "F", "time": 10.0}]}})
	_write(lb.save_path(), future)
	var fut = lb_script.new()
	fut.submit_time("klassik-1", "woche", 50.0, "Now")
	fut.free()
	var ff := FileAccess.open(lb.save_path(), FileAccess.READ)
	_check("a newer-version save is not overwritten", ff.get_as_text() == future)
	ff.close()
	lb.free()

	# --- GD (03.10. review): the condition the rabbit gave is metadata of
	# every entry (never part of the key), plus the local date (UX-W6) ---
	var lm = lb_script.new()
	lm.reset_all()
	lm.date_override = "2026-10-03"
	lm.submit_time("klassik-1", "woche", 120.0, "Player", "solo", "2026-W40", "matrix")
	lm.submit_time("klassik-1", "woche", 125.0, "Player", "solo", "2026-W40", "")
	lm.submit_time("klassik-1", "woche", 130.0, "Player", "solo", "2026-W40")
	lm.submit_time("klassik-1", "woche", 135.0, "Player", "solo", "2026-W40", "kaputt")
	var ct: Array = lm.get_top("klassik-1", "woche")
	_check("cond: stored per entry (matrix / '' = no rabbit / '?' = unknown)", ct[0].cond == "matrix" and ct[1].cond == "" and ct[2].cond == "?" and ct[3].cond == "?", str(ct))
	_check("cond: not part of the key — all four on the same board", ct.size() == 4 and lm._boards.size() == 1, str(lm._boards.keys()))
	_check("date: stored per entry", ct[0].date == "2026-10-03")
	lm.reload()
	var ct2: Array = lm.get_top("klassik-1", "woche")
	_check("cond and date survive save and load", ct2.size() == 4 and ct2[0].cond == "matrix" and ct2[1].cond == "" and ct2[0].date == "2026-10-03", str(ct2))
	_write(lm.save_path(), JSON.stringify({"version": 3, "boards": {"klassik-2|woche|solo": [{"name": "Player", "time": 100.0, "week": "2026-W39"}]}}))
	lm.reload()
	var old_e: Dictionary = lm.get_top("klassik-2", "woche")[0]
	_check("an older entry without cond/date loads as unknown", old_e.cond == "?" and old_e.date == "", str(old_e))
	lm.reset_all()
	lm.free()

	# --- QA-W6: the real save file was never touched ----------------------
	_check("the real save files are unchanged", SaveIsolation.end(real_saves))

	print("")
	if failures == 0:
		print("ALL %d LEADERBOARD CHECKS PASSED" % checks)
		quit(0)
	else:
		print("%d/%d LEADERBOARD CHECKS FAILED" % [failures, checks])
		quit(1)


func _read_json(path: String):
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed if parsed != null else {}


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()
