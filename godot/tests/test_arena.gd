extends SceneTree
## Headless test: Versus mode "Arena" (both players in ONE maze, ZAP-9):
##   - MazeView.arena_owners / arena_split: the two pellet sets, the second start
##   - Enemy snapshots (host -> client puppets)
##   - the Arena messages of versus_session.gd (protocol 3) over ENet on
##     localhost, including broken and hostile packets
##   - the solid opponent body (player mask) and the dash passing it
## Run with
##   godot --headless --path . --script res://tests/test_arena.gd
## Exits with code 0 on success, 1 on any failure.

const Session := preload("res://scripts/versus_session.gd")
const Levels := preload("res://scripts/levels.gd")

# loaded at run time: these scripts name the MazeGen autoload, which does not
# exist yet while a --script test is compiled
var MazeViewScript
var EnemyScript
var PlayerScript
var failures := 0
var checks := 0
var host
var client
var ev := {"host": [], "client": []}


func _check(name: String, cond: bool, detail := "") -> void:
	checks += 1
	if not cond:
		failures += 1
		print("FAIL %s %s" % [name, detail])


func _initialize() -> void:
	MazeViewScript = load("res://scripts/maze_view.gd")
	EnemyScript = load("res://scripts/enemy.gd")
	PlayerScript = load("res://scripts/player_controller.gd")
	_run()


func _mg():
	return root.get_node("MazeGen")


func _wait(cond: Callable, max_frames: int = 600) -> bool:
	for i in max_frames:
		if cond.call():
			return true
		await process_frame
	return cond.call()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _run() -> void:
	_test_owners()
	for level in Levels.POOL:
		_test_level_split(level)
	_test_enemy_snapshot()
	await _test_player_body()
	await _test_session()
	if failures == 0:
		print("test_arena: all %d checks passed" % checks)
	else:
		print("test_arena: %d OF %d CHECKS FAILED" % [failures, checks])
	quit(1 if failures > 0 else 0)


## ---- the pellet rule -------------------------------------------------------------

func _test_owners() -> void:
	var cells: Array = []
	for r in range(1, 12, 2):
		for c in range(1, 14, 2):
			cells.append(Vector2i(r, c))
	var o: Dictionary = MazeViewScript.arena_owners(cells, [Vector2i(1, 1), Vector2i(3, 3), Vector2i(5, 5), Vector2i(7, 7)])
	var n := [0, 0]
	for x in o.pellets:
		n[x] += 1
	_check("owners: every pellet has an owner (0/1)", o.pellets.size() == cells.size() and n[0] + n[1] == cells.size())
	_check("owners: the sets differ by at most one", absi(n[0] - n[1]) <= 1, str(n))
	_check("owners: power pellets alternate", o.power == [0, 1, 0, 1], str(o.power))
	var again: Dictionary = MazeViewScript.arena_owners(cells, [Vector2i(1, 1), Vector2i(3, 3), Vector2i(5, 5), Vector2i(7, 7)])
	_check("owners: deterministic", again.pellets == o.pellets)
	# neighbouring room cells belong to different players (a chessboard)
	var mixed := 0
	for i in cells.size() - 1:
		if cells[i + 1].x == cells[i].x and o.pellets[i] != o.pellets[i + 1]:
			mixed += 1
	_check("owners: neighbours alternate along a street", mixed >= 30, str(mixed))
	var odd: Dictionary = MazeViewScript.arena_owners([Vector2i(1, 1), Vector2i(1, 3), Vector2i(1, 5)], [])
	var odd_n := [0, 0]
	for x in odd.pellets:
		odd_n[x] += 1
	_check("owners: 3 pellets split 2/1", absi(odd_n[0] - odd_n[1]) == 1)
	var skew: Dictionary = MazeViewScript.arena_owners([Vector2i(1, 1), Vector2i(1, 2), Vector2i(2, 1), Vector2i(2, 2), Vector2i(3, 3)], [])
	var skew_n := [0, 0]
	for x in skew.pellets:
		skew_n[x] += 1
	_check("owners: a lopsided set is balanced", absi(skew_n[0] - skew_n[1]) <= 1, str(skew.pellets))


func _build(level: Dictionary) -> Array:
	var maze = _mg().generate_maze(level.rows, level.cols, level.seed, Levels.maze_opts(level))
	var start: Vector2i = Levels.start_cell(_mg(), maze)
	var mv = MazeViewScript.new()
	root.add_child(mv)
	mv.build(maze, start, "normal", [], [], level.seed, level.get("look", ""))
	return [mv, maze, start]


func _test_level_split(level: Dictionary) -> void:
	var tag: String = level.id
	var built := _build(level)
	var mv = built[0]
	var maze = built[1]
	var a: Vector2i = built[2]
	var b: Vector2i = MazeViewScript.arena_second_start(maze, a)
	_check("%s: second start differs, open, outside the house" % tag, b != a and _mg().is_open(maze, b.x, b.y) and not (b.x > maze.house.r0 and b.x < maze.house.r1 and b.y > maze.house.c0 and b.y < maze.house.c1))
	_check("%s: second start is far (>= 10 steps)" % tag, int(_mg().bfs(maze, a.x, a.y)[b.x][b.y]) >= 10)
	var total_before: int = mv.total_pickups()
	var pellets_before: int = mv.pellet_cells.size()
	mv.arena_split(0, Color.ORANGE, [b])
	var mine := 0
	var theirs := 0
	for i in mv.pellet_cells.size():
		if mv.pellet_owner[i] == 0:
			mine += 1
		else:
			theirs += 1
	_check("%s: both sets about equal (%d / %d)" % [tag, mine, theirs], absi(mine - theirs) <= 2, "%d %d" % [mine, theirs])
	_check("%s: total_pickups counts only my set" % tag, mv.total_pickups() < total_before and mv.total_pickups() == mv.remaining_pickups())
	_check("%s: the sets together are the level's pickups" % tag, mine + theirs + mv.power_cells.size() >= total_before - 1 and pellets_before == mv.pellet_cells.size())
	# my pellets can be eaten, his can not
	var my_i := -1
	var opp_i := -1
	for i in mv.pellet_cells.size():
		if mv.pellet_alive[i]:
			if mv.pellet_owner[i] == 0 and my_i < 0:
				my_i = i
			elif mv.pellet_owner[i] == 1 and opp_i < 0:
				opp_i = i
	var r_opp: Dictionary = mv.consume_at(mv.pellet_position(opp_i), 0.0)
	_check("%s: walking over his pellet eats nothing" % tag, not r_opp.pellet and mv.pellet_alive[opp_i])
	var before: int = mv.remaining_pickups()
	var r_my: Dictionary = mv.consume_at(mv.pellet_position(my_i), 0.0)
	_check("%s: walking over mine eats it, with its cell" % tag, r_my.pellet and r_my.cells.has(mv.pellet_cells[my_i]) and mv.remaining_pickups() == before - 1)
	# the opponent's eat message
	var opp_cell: Vector2i = mv.pellet_cells[opp_i]
	_check("%s: his eaten pellet disappears" % tag, mv.arena_opp_ate(opp_cell) and not mv.pellet_alive[opp_i])
	_check("%s: ... only once" % tag, not mv.arena_opp_ate(opp_cell))
	var my_cell: Vector2i = mv.pellet_cells[my_i + 1 if my_i + 1 < mv.pellet_cells.size() and mv.pellet_owner[my_i + 1] == 0 else my_i]
	var alive_mine := 0
	for i in mv.pellet_cells.size():
		if mv.pellet_owner[i] == 0 and mv.pellet_alive[i]:
			my_cell = mv.pellet_cells[i]
			alive_mine += 1
			break
	_check("%s: a hostile 'eat' of MY pellet is refused" % tag, alive_mine == 1 and not mv.arena_opp_ate(my_cell))
	_check("%s: an 'eat' of an empty cell is refused" % tag, not mv.arena_opp_ate(Vector2i(0, 0)) and not mv.arena_opp_ate(Vector2i(-5, 99)))
	_check("%s: the opponent's start cell carries no pellet" % tag, not mv._pellet_index.has(b) or not mv.pellet_alive[mv._pellet_index[b]])
	# eat every pellet of mine -> nothing left to do for me, his are still there
	for i in mv.pellet_cells.size():
		if mv.pellet_owner[i] == 0 and mv.pellet_alive[i]:
			mv.consume_at(mv.pellet_position(i), 0.0)
	for k in mv.power_cells.size():
		if mv.power_owner[k] == 0 and mv.power_alive[k]:
			mv.consume_at(mv.power_nodes[k].position, 0.0)
	_check("%s: my set eaten = level done for me" % tag, mv.remaining_pickups() == 0)
	var his_left := 0
	for i in mv.pellet_cells.size():
		if mv.pellet_owner[i] == 1 and mv.pellet_alive[i]:
			his_left += 1
	_check("%s: his pellets are all still there" % tag, his_left > 0)
	# the rule is the same on the other machine
	var built2 := _build(level)
	var mv2 = built2[0]
	mv2.arena_split(1, Color.ORANGE, [b])
	_check("%s: the other player sees the same owners" % tag, mv2.pellet_owner == mv.pellet_owner and mv2.power_owner == mv.power_owner)
	_check("%s: he eats the other set" % tag, mv2.total_pickups() > 0 and mv2.remaining_pickups() == mv2.total_pickups())
	mv.queue_free()
	mv2.queue_free()
	# and a rebuild is an ordinary level again
	var built3 := _build(level)
	_check("%s: a rebuilt level has no Arena split" % tag, built3[0].arena_side == -1 and built3[0].total_pickups() == total_before)
	built3[0].queue_free()


## ---- the ghosts ------------------------------------------------------------------

func _test_enemy_snapshot() -> void:
	var maze = _mg().generate_maze(19, 21, 10003, Levels.maze_opts(Levels.POOL[0]))
	var host_e := Node3D.new()
	host_e.set_script(EnemyScript)
	root.add_child(host_e)
	host_e.setup(Color.RED, Color.PINK, 2.0)
	var cli_e := Node3D.new()
	cli_e.set_script(EnemyScript)
	cli_e.puppet = true
	root.add_child(cli_e)
	cli_e.setup(Color.RED, Color.PINK, 2.0)
	var start: Vector2i = Levels.start_cell(_mg(), maze)
	host_e.place_in_house(Vector2i(maze.house.r0 + 1, maze.house.c0 + 1))
	host_e.release_at = 0.0
	var now := 0.0
	for i in 200:
		now += 0.05
		host_e.update(0.05, maze, start, false, now, maze.cols * 2.0)
	var snap: Array = host_e.snapshot()
	_check("snapshot has 6 numbers", snap.size() == 6)
	cli_e.apply_snapshot(snap)
	_check("puppet takes mode and edge", cli_e.mode == host_e.mode and cli_e.target_r == host_e.target_r and cli_e.target_c == host_e.target_c and cli_e.from_r == host_e.from_r)
	for i in 5:
		now += 0.05
		host_e.update(0.05, maze, start, false, now, maze.cols * 2.0)
		cli_e.puppet_update(0.05, now, maze.cols * 2.0)
	var d := Vector2(host_e.position.x - cli_e.position.x, host_e.position.z - cli_e.position.z).length()
	_check("puppet follows the host within a cell (%.2f m)" % d, d < 2.0)
	host_e.mode = "frightened"
	cli_e.apply_snapshot(host_e.snapshot())
	_check("frightened mode arrives (and the look follows)", cli_e.mode == "frightened" and cli_e.body_material.albedo_color == cli_e.frightened_color)
	host_e.mode = "eaten"
	cli_e.apply_snapshot(host_e.snapshot())
	_check("eaten mode arrives", cli_e.mode == "eaten")
	cli_e.apply_snapshot([1, 1, 1, 3, 0.5, 9])
	_check("a mode code out of range falls back to a valid mode", Enemy_modes_ok(cli_e.mode))
	host_e.queue_free()
	cli_e.queue_free()


func Enemy_modes_ok(m: String) -> bool:
	return EnemyScript.MODE_CODES.has(m)


## ---- the solid opponent ------------------------------------------------------------

func _test_player_body() -> void:
	var p = PlayerScript.new()
	root.add_child(p)
	await process_frame
	_check("player: default mask = walls", p.collision_mask == 2)
	p.set_opponent_solid(true)
	_check("player: Arena mask = walls + opponent", p.collision_mask == 6)
	p.dash_charges = 1
	p.input_enabled = true
	_check("dash starts although the opponent stands in front", p.try_dash())
	_check("player: while dashing the opponent is not solid", p.collision_mask == 2)
	p.dash_time_left = 0.0
	p._refresh_mask()
	_check("player: solid again after the dash", p.collision_mask == 6)
	p.set_noclip(true)
	_check("player: noclip still means no collision at all", p.collision_mask == 0)
	p.set_noclip(false)
	p.set_opponent_solid(false)
	_check("player: back to walls only", p.collision_mask == 2)
	p.queue_free()

	# the real opponent body: it must stop a walking player although it was
	# MOVED after it entered the tree (a kinematic body ignores its parent's moves)
	var w = load("res://scripts/arena_world.gd").new()
	root.add_child(w)
	w._build_figure()
	var pl = PlayerScript.new()
	root.add_child(pl)
	pl.global_position = Vector3(10, 1.25, 10)
	pl.set_opponent_solid(true)
	await physics_frame
	w.place_opponent(Vector2i(4, 5)) # 2 m ahead (forward is -z), moved after entering the tree
	pl.move_input = Vector2(0, 1)
	for i in 90:
		await physics_frame
		await process_frame
	var gap: float = absf(pl.global_position.z - w.figure.position.z)
	_check("the player is stopped by the opponent (gap %.2f m)" % gap, gap > 0.6 and gap < 0.9, str(pl.global_position))
	w.place_opponent(Vector2i(4, 8)) # he steps aside (teleport)
	for i in 60:
		await physics_frame
		await process_frame
	_check("... and walks on when he stepped aside", pl.global_position.z < 6.0, str(pl.global_position))
	w.queue_free()
	pl.queue_free()


## ---- the messages --------------------------------------------------------------------

func _wire(s, key: String) -> void:
	s.round_started.connect(func(r, go): ev[key].append(["round", r, go]))
	s.opponent_pos.connect(func(x, z, yaw): ev[key].append(["pos", x, z, yaw]))
	s.opponent_ate.connect(func(cell): ev[key].append(["ate", cell]))
	s.ghosts_received.connect(func(list, f, gs): ev[key].append(["ghosts", list, f, gs]))
	s.ghost_event.connect(func(kind, i): ev[key].append(["gev", kind, i]))
	s.opponent_progress.connect(func(f, c, l): ev[key].append(["prog", f, c, l]))


func _count(key: String, kind: String) -> int:
	var n := 0
	for e in ev[key]:
		if e[0] == kind:
			n += 1
	return n


func _last(key: String, kind: String) -> Array:
	for i in range(ev[key].size() - 1, -1, -1):
		if ev[key][i][0] == kind:
			return ev[key][i]
	return []


func _test_session() -> void:
	var port := 47960 + (randi() % 30)
	host = Session.new()
	client = Session.new()
	host.my_name = "Alice"
	client.my_name = "Bob"
	host.my_week = Vector2i(2026, 41)
	client.my_week = Vector2i(2026, 41)
	root.add_child(host)
	root.add_child(client)
	_wire(host, "host")
	_wire(client, "client")
	host.host(port)
	client.join("127.0.0.1", port)
	var ok := await _wait(func(): return host.is_ready() and client.is_ready())
	_check("pair ready", ok)
	_check("protocol is 3", Session.PROTOCOL == 3)
	_check("the default mode is the Arena", host.mode == Session.MODE_ARENA)

	# the round message carries the mode
	host.mode = Session.MODE_RACE
	host.start_next_round()
	ok = await _wait(func(): return _count("client", "round") == 1)
	_check("client learns the mode 'race'", ok and client.mode == Session.MODE_RACE, "ok=%s mode=%s ev=%s" % [ok, client.mode, ev.client])
	host._apply_result("none", "none") # end the round without a match logic detour
	client._apply_result("none", "none")
	host.mode = Session.MODE_ARENA
	host.start_next_round()
	ok = await _wait(func(): return _count("client", "round") == 2)
	_check("client learns the mode 'arena'", ok and client.mode == Session.MODE_ARENA)
	client._on_message({"t": "round", "round": 9, "mode": "banana"})
	_check("an unknown mode string means race", client.mode == Session.MODE_ARENA) # refused round: unchanged

	# positions, both directions
	client.send_pos(12.34, 56.78, 1.5, true)
	ok = await _wait(func(): return _count("host", "pos") >= 1)
	var p := _last("host", "pos")
	_check("host gets the client's position (unreliable channel)", ok and absf(p[1] - 12.34) < 0.01 and absf(p[2] - 56.78) < 0.01 and absf(p[3] - 1.5) < 0.01, str(p))
	host.send_pos(3.0, 4.0, -2.0, true)
	ok = await _wait(func(): return _count("client", "pos") >= 1)
	_check("client gets the host's position", ok and absf(_last("client", "pos")[1] - 3.0) < 0.01)
	var n_pos: int = _count("host", "pos")
	for bad in [{"x": "a", "z": 1.0, "yaw": 0.0}, {"x": 1e9, "z": 1.0, "yaw": 0.0}, {"x": NAN, "z": 1.0, "yaw": 0.0}, {"x": 1.0, "z": -999.0, "yaw": 0.0}, {"z": 1.0}]:
		var m: Dictionary = {"t": "pos", "round": host.round_index}
		m.merge(bad)
		host._last_pos_got = -1000.0
		host._on_message(m)
	_check("broken positions are dropped", _count("host", "pos") == n_pos)
	host._last_pos_got = -1000.0
	host._on_message({"t": "pos", "round": host.round_index, "x": 5.0, "z": 5.0, "yaw": 99.0})
	_check("an out-of-range yaw is clamped to 0, not trusted", _last("host", "pos")[3] == 0.0)
	var n_before: int = _count("host", "pos")
	host._on_message({"t": "pos", "round": host.round_index, "x": 6.0, "z": 6.0, "yaw": 0.0})
	_check("positions faster than ~30/s are dropped", _count("host", "pos") == n_before)
	host._on_message({"t": "pos", "round": 7, "x": 6.0, "z": 6.0, "yaw": 0.0})
	_check("a position of another round is dropped", _count("host", "pos") == n_before)

	# pickups
	client.send_eat(Vector2i(5, 7))
	ok = await _wait(func(): return _count("host", "ate") >= 1)
	_check("host hears which pickup the client ate", ok and _last("host", "ate")[1] == Vector2i(5, 7))
	var n_ate: int = _count("host", "ate")
	host._on_message({"t": "eat", "round": host.round_index, "r": "x", "c": 1})
	host._on_message({"t": "eat", "round": host.round_index, "r": -4, "c": 1})
	host._on_message({"t": "eat", "round": host.round_index, "r": 1, "c": 99999})
	_check("broken eat messages are dropped", _count("host", "ate") == n_ate)

	# the ghosts: host -> client
	var snaps := [[5, 5, 5, 7, 0.4, 1], [9, 9, 9, 9, 0.0, 0]]
	host.send_ghosts(snaps, 3.5, 0.5, true)
	ok = await _wait(func(): return _count("client", "ghosts") >= 1)
	var g := _last("client", "ghosts")
	_check("client gets the ghosts, the power window and the speed factor", ok and g[1].size() == 2 and g[1][0][2] == 5 and g[1][0][3] == 7 and absf(g[1][0][4] - 0.4) < 0.001 and absf(g[2] - 3.5) < 0.01 and absf(g[3] - 0.5) < 0.01, str(g))
	var n_g: int = _count("client", "ghosts")
	client._last_ghosts_got = -1000.0
	client._on_message({"t": "gh", "round": client.round_index, "g": [[1, 2, 3, 4, 0.5, 1], [1, 2, 3]], "f": 0, "gs": 1})
	client._on_message({"t": "gh", "round": client.round_index, "g": [[1, 2, 3, 4, 7.5, 1]], "f": 0, "gs": 1})
	client._on_message({"t": "gh", "round": client.round_index, "g": [[1, 2, 3, 4, 0.5, 8]], "f": 0, "gs": 1})
	client._on_message({"t": "gh", "round": client.round_index, "g": "ghosts", "f": 0, "gs": 1})
	var many: Array = []
	for i in 40:
		many.append([1, 2, 3, 4, 0.5, 1])
	client._on_message({"t": "gh", "round": client.round_index, "g": many, "f": 0, "gs": 1})
	_check("broken ghost snapshots are dropped whole", _count("client", "ghosts") == n_g)
	var n_h: int = _count("host", "ghosts")
	host._on_message({"t": "gh", "round": host.round_index, "g": [[1, 2, 3, 4, 0.5, 1]], "f": 0, "gs": 1})
	_check("the host never takes ghosts from the client", _count("host", "ghosts") == n_h)

	# ghost events: client -> host
	client.send_ghost_event("hit", 1)
	client.send_ghost_event("ate", 0)
	client.send_ghost_event("power", 0, 0.5)
	ok = await _wait(func(): return _count("host", "gev") >= 3)
	_check("host gets hit, ate and power", ok and ev.host.filter(func(e): return e[0] == "gev").map(func(e): return e[1]) == ["hit", "ate", "power"], str(ev.host))
	_check("the client's ghost speed factor arrives with 'power'", absf(host.opp_gscale - 0.5) < 0.01, str(host.opp_gscale))
	var n_e: int = _count("host", "gev")
	host._on_message({"t": "ghit", "round": host.round_index, "i": 99})
	host._on_message({"t": "ghit", "round": host.round_index, "i": -1})
	host._on_message({"t": "gate", "round": host.round_index, "i": "0"})
	_check("ghost events with a bad index are dropped", _count("host", "gev") == n_e)
	var n_ce: int = _count("client", "gev")
	client._on_message({"t": "ghit", "round": client.round_index, "i": 0})
	client._on_message({"t": "power", "round": client.round_index, "gs": 1})
	_check("only the host takes ghost events", _count("client", "gev") == n_ce)
	var before_gs: float = host.opp_gscale
	client.send_progress(0.1, Vector2i(1, 1), 3, true, 2.0)
	ok = await _wait(func(): return absf(host.opp_gscale - 2.0) < 0.01)
	_check("prog carries the ghost speed factor", ok, str(before_gs))
	host._last_progress_got = -1000.0
	host._on_message({"t": "prog", "round": host.round_index, "frac": 0.2, "r": 1, "c": 1, "lives": 3, "gs": 99.0})
	_check("a wild ghost speed factor falls back to 1", host.opp_gscale == 1.0)

	# in the mirror race none of this is accepted
	host.mode = Session.MODE_RACE
	var n_race: int = _count("host", "pos") + _count("host", "ate") + _count("host", "gev")
	host._last_pos_got = -1000.0
	host._on_message({"t": "pos", "round": host.round_index, "x": 1.0, "z": 1.0, "yaw": 0.0})
	host._on_message({"t": "eat", "round": host.round_index, "r": 1, "c": 1})
	host._on_message({"t": "ghit", "round": host.round_index, "i": 0})
	_check("in 'race' the Arena messages are ignored", _count("host", "pos") + _count("host", "ate") + _count("host", "gev") == n_race)
	host.send_pos(1.0, 1.0, 0.0, true)
	host.send_eat(Vector2i(1, 1))
	await _frames(20)
	_check("in 'race' nothing Arena is sent", _count("client", "pos") == 1)

	host.close()
	client.close()
	host.queue_free()
	client.queue_free()
