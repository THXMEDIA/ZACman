extends SceneTree
## End-to-end test of a Versus match (E17) with TWO real game instances over
## ENet on localhost. Start the host and the client as two processes:
##   VS_ROLE=host   VS_PORT=47950 godot --headless --path . --script res://tests/versus_e2e.gd &
##   VS_ROLE=client VS_PORT=47950 godot --headless --path . --script res://tests/versus_e2e.gd
## (tools/qa/versus_e2e.sh runs both and checks both exit codes.)
##
## Each instance runs the real Main scene. An autopilot clears its own maze by
## stepping onto the remaining pellets (`speed` pellets per frame), so the
## faster autopilot wins a round:
##   round 1: host 3/frame, client 1/frame  -> host wins
##   round 2: host 1/frame, client 3/frame  -> client wins (host concedes)
##   round 3: the client loses all lives    -> host wins the match 2:1
## Both pick up the rabbit in round 1 and must get the same condition (same
## round generator, duel off = 60 % on both sides).
## Exits 0 on success, 1 on any failure.

const CELL := 2.0
const SavePathsScript := preload("res://scripts/save_paths.gd")

var role := "host"
var main: Node
var vs
var failures := 0
var checks := 0
var log_prefix := ""
var my_rabbit := ""
var opp_rabbit := ""
var decided: Array = []
var over: Array = []


func _check(name: String, cond: bool, detail := "") -> void:
	checks += 1
	if not cond:
		failures += 1
		print("%s FAIL %s %s" % [log_prefix, name, detail])


func _initialize() -> void:
	role = OS.get_environment("VS_ROLE")
	if role == "":
		role = "host"
	log_prefix = "[%s]" % role
	# Own save folder per instance: the two processes never share a file, and
	# the player's real saves are never touched.
	SavePathsScript.use_root("user://test_saves_versus_%s" % role)
	root.get_node("Leaderboard").reload()
	root.get_node("Speedrun").reload()
	main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	_run()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _wait(cond: Callable, max_frames: int = 1800) -> bool:
	for i in max_frames:
		if cond.call():
			return true
		await process_frame
	return cond.call()


func _run() -> void:
	await _frames(5)
	vs = main.versus
	var port := OS.get_environment("VS_PORT").to_int()
	if port <= 0:
		port = 47950
	vs.session.round_decided.connect(func(r, outcome, cause): decided.append([r, outcome, cause]))
	vs.session.match_over.connect(func(won, a, b): over.append([won, a, b]))
	vs.session.opponent_rabbit.connect(func(cond, good, p): opp_rabbit = cond)
	main.rabbit_week_override = Vector2i(2026, 41)

	vs.open_lobby()
	_check("lobby opens", vs.ui.lobby.visible)
	if role == "host":
		vs._on_host_requested("Alice", port)
	else:
		await _frames(30) # let the host open its port first
		vs._on_join_requested("Bob", "127.0.0.1", port)
	var ok := await _wait(func(): return vs.session.is_ready(), 900)
	_check("session ready", ok, "state %d" % vs.session.state)
	if not ok:
		_finish()
		return
	_check("lobby shows the opponent", vs.ui.status_label.text.find("Alice" if role == "client" else "Bob") >= 0, vs.ui.status_label.text)
	_check("start only for the host", vs.ui.start_btn.disabled == (role != "host"))

	for r in 3:
		if role == "host" and r == 0:
			await _frames(20)
			vs.ui.start_requested.emit() # press MATCH STARTEN; later rounds start after the intermission
		ok = await _wait(func(): return vs.session.round_index == r and main.running, 60000)
		_check("round %d starts" % (r + 1), ok)
		if not ok:
			break
		_check("round %d: pvp mode" % (r + 1), main.run_mode() == "pvp")
		_check("round %d: the match's level" % (r + 1), main.level_id == vs.session.match_levels[r], "%s vs %s" % [main.level_id, vs.session.match_levels])
		_check("round %d: held until GO" % (r + 1), main.start_hold and main.player.movement_locked)
		ok = await _wait(func(): return not main.start_hold, 60000)
		_check("round %d: GO releases the hold" % (r + 1), ok)
		main.invuln_until = 1e9
		if r == 0:
			main._on_rabbit_picked()
			my_rabbit = main.level_condition_id
			main._end_condition(false)
		if r == 2 and role == "client":
			for i in 3:
				main.invuln_until = 0.0
				main.lose_life()
		else:
			var speed := 3 if (r == 0 and role == "host") or (r == 1 and role == "client") else 1
			await _autopilot(speed, r)
		var n_before := r + 1
		ok = await _wait(func(): return decided.size() >= n_before, 60000)
		_check("round %d decided" % (r + 1), ok)
		if r == 0:
			_check("the opponent's progress arrived", vs._opp_frac > 0.0, str(vs._opp_frac))
			await _wait(func(): return opp_rabbit != "", 300)
			_check("both players drew the same rabbit (shared round generator)", my_rabbit != "" and my_rabbit == opp_rabbit, "%s / %s" % [my_rabbit, opp_rabbit])
		if over.size() > 0:
			break

	ok = await _wait(func(): return over.size() > 0, 60000)
	_check("match over", ok)
	if decided.size() >= 3:
		var w := "win" if role == "host" else "loss"
		var l := "loss" if role == "host" else "win"
		_check("round 1 to the host", decided[0][1] == w, str(decided[0]))
		_check("round 2 to the client", decided[1][1] == l, str(decided[1]))
		_check("round 3 to the host", decided[2][1] == w, str(decided[2]))
	if over.size() > 0:
		_check("host wins the match 2:1", over[0][0] == (role == "host") and over[0][1] + over[0][2] == 3, str(over[0]))
	var lb_key := "%s|woche|pvp" % vs.session.match_levels[0]
	if role == "host":
		_check("the host's round-1 time is on the pvp board", not root.get_node("Leaderboard").get_top(vs.session.match_levels[0], "woche", 10, "pvp").is_empty(), lb_key)
	await _frames(120)
	vs.leave()
	await _frames(5)
	_check("leaving returns to the start screen", main.hud.start_panel.visible and not vs.active)
	_finish()


## Steps onto the alive pellets and power pellets of this instance's maze,
## `speed` per frame, until the level is cleared or the round is decided.
func _autopilot(speed: int, r: int) -> void:
	var mv = main.maze_view
	var cells: Array = []
	for i in mv.pellet_cells.size():
		cells.append(["p", i])
	for i in mv.power_cells.size():
		cells.append(["w", i])
	var k := 0
	while k < cells.size() and main.running and decided.size() <= r:
		for s in speed:
			while k < cells.size():
				var e: Array = cells[k]
				k += 1
				var alive: bool = mv.pellet_alive[e[1]] if e[0] == "p" else mv.power_alive[e[1]]
				if not alive:
					continue
				var cell: Vector2i = mv.pellet_cells[e[1]] if e[0] == "p" else mv.power_cells[e[1]]
				main.player.global_position = Vector3(cell.y * CELL, main.player.eye_h, cell.x * CELL)
				main.invuln_until = 1e9
				main._check_pickups()
				break
			if not main.running:
				break
		await process_frame


func _finish() -> void:
	_rm_tree(SavePathsScript.root)
	SavePathsScript.reset_root()
	if failures == 0:
		print("%s versus_e2e: all %d checks passed" % [log_prefix, checks])
	else:
		print("%s versus_e2e: %d of %d checks FAILED" % [log_prefix, failures, checks])
	quit(1 if failures > 0 else 0)


func _rm_tree(dir: String) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		d.remove(f)
	DirAccess.remove_absolute(dir)
