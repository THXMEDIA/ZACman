extends SceneTree
## End-to-end test of an ARENA match (ZAP-9: both players in ONE maze) with TWO
## real game instances over ENet on localhost. Start host and client:
##   VS_ROLE=host   VS_PORT=47950 godot --headless --path . --script res://tests/arena_e2e.gd &
##   VS_ROLE=client VS_PORT=47950 godot --headless --path . --script res://tests/arena_e2e.gd
## (tools/qa/arena_e2e.sh runs both and checks both exit codes.)
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
var opp_start_pellets := 0
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
	SavePathsScript.use_root("user://test_saves_arena_%s" % role)
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
	_check("the lobby offers the Arena by default", vs.session.mode == "arena" and vs.ui.mode_btn.text.find("ARENA") >= 0, vs.ui.mode_btn.text)
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
	if role == "client":
		await _wait(func(): return vs.ui.mode_btn.text.find("wählt der Host") >= 0, 300)
		_check("the client's lobby shows the host's mode", vs.ui.mode_btn.text.find("wählt der Host") >= 0 and vs.ui.mode_btn.text.find("ARENA") >= 0 and vs.ui.mode_btn.disabled, vs.ui.mode_btn.text)

	for r in 3:
		if role == "host" and r == 0:
			await _frames(20)
			vs.ui.start_requested.emit() # press MATCH STARTEN; later rounds start after the intermission
		ok = await _wait(func(): return vs.session.round_index == r and main.running, 60000)
		_check("round %d starts" % (r + 1), ok)
		if not ok:
			break
		_check("round %d: pvp mode" % (r + 1), main.run_mode() == "pvp")
		_check("round %d: both know it is an Arena round" % (r + 1), vs.arena_mode and main.arena_on() and vs.session.mode == "arena")
		var mv0 = main.maze_view
		_check("round %d: my pellet set is split off (side %d)" % [r + 1, mv0.arena_side], mv0.arena_side == (0 if role == "host" else 1) and mv0.total_pickups() > 0 and mv0.total_pickups() < mv0.pellet_cells.size())
		_check("round %d: the two players start on different cells" % (r + 1), vs.arena.my_start != vs.arena.opp_start and main.start_cell == vs.arena.my_start)
		_check("round %d: the opponent figure stands on his start" % (r + 1), vs.arena.figure.visible and vs.arena.opponent_cell() == vs.arena.opp_start)
		_check("round %d: the player collides with the opponent" % (r + 1), main.player.opponent_solid)
		_check("round %d: client ghosts are puppets, the host's are not" % (r + 1), main.enemies.all(func(e): return e.puppet == (role == "client")))
		opp_start_pellets = _opp_alive(mv0)
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
		if r < 2:
			_check("round %d: his eaten pellets vanished in my maze (%d of %d left)" % [r + 1, _opp_alive(main.maze_view), opp_start_pellets], _opp_alive(main.maze_view) < opp_start_pellets)
			_check("round %d: the opponent's position arrived (he moved off his start)" % (r + 1), vs.arena.opponent_cell() != vs.arena.opp_start or r == 2)
			if role == "client":
				_check("round %d: the host's ghost snapshots arrived (%d)" % [r + 1, vs.arena.snapshots_applied], vs.arena.snapshots_applied > 3)
		if r == 0:
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
		_check("Arena times go on no board (half the pellets, not comparable)", root.get_node("Leaderboard").get_top(vs.session.match_levels[0], "woche", 10, "pvp").is_empty(), lb_key)
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
		if mv.pellet_owner[i] == mv.arena_side:
			cells.append(["p", i])
	for i in mv.power_cells.size():
		if mv.power_owner[i] == mv.arena_side:
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
		# ~50 steps a second like a fast player, so the 15 Hz positions and 10 Hz
		# ghost snapshots have time to travel (a frame loop would finish in ms)
		await create_timer(0.02).timeout


## How many of the OPPONENT's pellets are still shown in my maze.
func _opp_alive(mv) -> int:
	var n := 0
	for i in mv.pellet_cells.size():
		if mv.pellet_owner[i] != mv.arena_side and mv.pellet_owner[i] >= 0 and mv.pellet_alive[i]:
			n += 1
	return n


func _finish() -> void:
	_rm_tree(SavePathsScript.root)
	SavePathsScript.reset_root()
	if failures == 0:
		print("%s arena_e2e: all %d checks passed" % [log_prefix, checks])
	else:
		print("%s arena_e2e: %d of %d checks FAILED" % [log_prefix, failures, checks])
	quit(1 if failures > 0 else 0)


func _rm_tree(dir: String) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		d.remove(f)
	DirAccess.remove_absolute(dir)
