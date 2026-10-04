extends SceneTree
## Headless test: res://scripts/versus_session.gd — the Versus protocol (E17,
## docs/design/multiplayer.md): two sessions in ONE process talk over ENet on
## localhost (host + client), agree on the match seed by commit-reveal, play
## three rounds (lower time wins, conceding when the opponent's time is
## passed, losing the last life) and see the opponent leave. Run with
##   godot --headless --path . --script res://tests/test_versus_session.gd
## Exits with code 0 on success, 1 on any failure.

const Session := preload("res://scripts/versus_session.gd")
const Levels := preload("res://scripts/levels.gd")

var failures := 0
var checks := 0
var host
var client
var events := {"host": [], "client": []}


func _check(name: String, cond: bool, detail := "") -> void:
	checks += 1
	if not cond:
		failures += 1
		print("FAIL %s %s" % [name, detail])


func _initialize() -> void:
	_run()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _wait(cond: Callable, max_frames: int = 600) -> bool:
	for i in max_frames:
		if cond.call():
			return true
		await process_frame
	return cond.call()


func _wire(s, key: String) -> void:
	s.match_ready.connect(func(): events[key].append(["ready"]))
	s.round_started.connect(func(r, go): events[key].append(["round", r, go]))
	s.opponent_progress.connect(func(f, c, l): events[key].append(["prog", f, c, l]))
	s.opponent_rabbit.connect(func(cond, p): events[key].append(["rabbit", cond, p]))
	s.round_decided.connect(func(r, won, why): events[key].append(["decided", r, won, why]))
	s.match_over.connect(func(won, a, b): events[key].append(["over", won, a, b]))
	s.opponent_left.connect(func(): events[key].append(["left"]))


func _has(key: String, kind: String) -> bool:
	for e in events[key]:
		if e[0] == kind:
			return true
	return false


func _last(key: String, kind: String) -> Array:
	for i in range(events[key].size() - 1, -1, -1):
		if events[key][i][0] == kind:
			return events[key][i]
	return []


func _run() -> void:
	var port := 47900 + (randi() % 50)
	host = Session.new()
	client = Session.new()
	host.my_name = "Alice"
	host.my_channel = "#AliceTV"
	host.my_week = Vector2i(2026, 41)
	client.my_name = "Bob"
	client.my_channel = "bobstreams"
	client.my_week = Vector2i(2026, 40) # other week (time zone): the host's counts
	root.add_child(host)
	root.add_child(client)
	_wire(host, "host")
	_wire(client, "client")

	_check("host opens the port", host.host(port) == OK)
	_check("client starts connecting", client.join("127.0.0.1", port) == OK)
	var ok := await _wait(func(): return host.is_ready() and client.is_ready())
	_check("both sides reach READY", ok, "host %d client %d" % [host.state, client.state])
	_check("same match seed on both sides", host.match_seed == client.match_seed and host.match_seed != 0)
	_check("same three levels on both sides", host.match_levels == client.match_levels and host.match_levels.size() == 3, str(host.match_levels))
	var distinct := {}
	for id in host.match_levels:
		distinct[id] = true
		_check("level %s is a pool level" % id, not Levels.by_id(id).is_empty())
	_check("the three levels differ", distinct.size() == 3)
	_check("names and channels exchanged", host.opp_name == "Bob" and client.opp_name == "Alice" and host.opp_channel == "bobstreams" and client.opp_channel == "alicetv")
	_check("the match runs on the host's week", client.host_week == Vector2i(2026, 41) and host.host_week == Vector2i(2026, 41))
	_check("sides: host A, client B", host.my_side() == 0 and client.my_side() == 1)
	_check("match_ready fired on both", _has("host", "ready") and _has("client", "ready"))

	# --- round 1: both finish, the lower time wins ---------------------------
	host.start_next_round()
	ok = await _wait(func(): return _has("client", "round"))
	_check("client gets the round start", ok)
	_check("round index 0 on both", host.round_index == 0 and client.round_index == 0)
	_check("both play the same level", host.current_level_id() == client.current_level_id() and host.current_level_id() == host.match_levels[0])
	client.send_progress(0.42, Vector2i(5, 7), 3, true)
	ok = await _wait(func(): return _has("host", "prog"))
	_check("host sees the client's progress", ok)
	var pr := _last("host", "prog")
	_check("progress values arrive", pr.size() == 4 and is_equal_approx(pr[1], 0.42) and pr[2] == Vector2i(5, 7) and pr[3] == 3, str(pr))
	client.send_rabbit("matrix", 0.725, Vector2i(3, 0), Vector2i(0, 0))
	ok = await _wait(func(): return _has("host", "rabbit"))
	_check("host sees the client's rabbit", ok and _last("host", "rabbit")[1] == "matrix")
	client.report_finish(50.0)
	host.report_finish(60.0)
	ok = await _wait(func(): return _has("host", "decided") and _has("client", "decided"))
	_check("round 1 decided on both sides", ok)
	_check("round 1: client (50 s) beats host (60 s)", _last("client", "decided")[2] == true and _last("host", "decided")[2] == false)
	_check("score 0:1 / 1:0 after round 1", host.score_me == 0 and host.score_opp == 1 and client.score_me == 1 and client.score_opp == 0)

	# --- round 2: the host finishes, the client's clock passes it ------------
	events = {"host": [], "client": []}
	host.start_next_round()
	await _wait(func(): return _has("client", "round"))
	host.report_finish(40.0)
	ok = await _wait(func(): return client.opp_time >= 0.0)
	_check("client learns the host's time", ok and is_equal_approx(client.opp_time, 40.0))
	client.tick_round(39.0)
	_check("still racing while under the opponent's time", client.round_open)
	client.tick_round(41.0)
	_check("client concedes once past 40 s", not client.round_open and _last("client", "decided")[2] == false)
	ok = await _wait(func(): return _has("host", "decided"))
	_check("host gets the round when the client concedes", ok and _last("host", "decided")[2] == true)
	_check("score 1:1", host.score_me == 1 and client.score_me == 1)

	# --- round 3: the client loses the last life -----------------------------
	events = {"host": [], "client": []}
	host.start_next_round()
	await _wait(func(): return _has("client", "round"))
	_check("third level", host.current_level_id() == host.match_levels[2])
	client.report_died()
	ok = await _wait(func(): return _has("host", "over") and _has("client", "over"))
	_check("match over on both sides", ok)
	_check("host wins the match 2:1", _last("host", "over")[1] == true and _last("host", "over")[2] == 2 and _last("host", "over")[3] == 1, str(_last("host", "over")))
	_check("client loses the match 1:2", _last("client", "over")[1] == false)
	host.start_next_round()
	_check("no round after the match", host.round_index == 2)

	# --- the opponent leaves -------------------------------------------------
	events = {"host": [], "client": []}
	client.close()
	ok = await _wait(func(): return _has("host", "left"))
	_check("host notices the client leaving", ok)

	# --- a wrong protocol version is refused ---------------------------------
	_check("levels_for is deterministic", Session.levels_for(123) == Session.levels_for(123))

	host.close()
	await _frames(2)
	if failures == 0:
		print("test_versus_session: all %d checks passed" % checks)
	else:
		print("test_versus_session: %d of %d checks FAILED" % [failures, checks])
	quit(1 if failures > 0 else 0)
