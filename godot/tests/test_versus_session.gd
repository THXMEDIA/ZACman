extends SceneTree
## Headless test: res://scripts/versus_session.gd — the Versus protocol (E17,
## docs/design/multiplayer.md): two sessions in ONE process talk over ENet on
## localhost (host + client), agree on the match seed by commit-reveal and
## play matches. The host decides every round (code review K1); both sides
## must always show the same result. Also: malformed and hostile packets,
## a second opponent after the first left, joining without a host, REVANCHE.
## Run with
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
	s.opponent_rabbit.connect(func(cond, good, p): events[key].append(["rabbit", cond, good, p]))
	s.opponent_finished.connect(func(cs): events[key].append(["finished", cs]))
	s.opponent_out.connect(func(): events[key].append(["out"]))
	s.round_decided.connect(func(r, outcome, cause): events[key].append(["decided", r, outcome, cause]))
	s.match_over.connect(func(won, a, b): events[key].append(["over", won, a, b]))
	s.rematch_requested.connect(func(): events[key].append(["rematch"]))
	s.opponent_left.connect(func(during): events[key].append(["left", during]))


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


func _clear() -> void:
	events = {"host": [], "client": []}


## Starts the next round on both sides and waits until the client has it.
func _round() -> bool:
	_clear()
	host.start_next_round()
	return await _wait(func(): return _has("client", "round"))


## Both decided the round; returns [host outcome, client outcome, host cause].
func _decided() -> Array:
	await _wait(func(): return _has("host", "decided") and _has("client", "decided"))
	var h := _last("host", "decided")
	var c := _last("client", "decided")
	if h.is_empty() or c.is_empty():
		return ["?", "?", "?"]
	return [h[2], c[2], h[3]]


func _connect_pair(port: int) -> bool:
	host = Session.new()
	client = Session.new()
	host.my_name = "Alice"
	host.my_channel = "alicetv"
	host.my_week = Vector2i(2026, 41)
	client.my_name = "Bob"
	client.my_channel = "bobstreams"
	client.my_week = Vector2i(2026, 40)
	root.add_child(host)
	root.add_child(client)
	_wire(host, "host")
	_wire(client, "client")
	host.host(port)
	client.join("127.0.0.1", port)
	return await _wait(func(): return host.is_ready() and client.is_ready())


func _run() -> void:
	var port := 47900 + (randi() % 50)
	var ok := await _connect_pair(port)
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

	# --- hostile / broken packets do nothing (code review K2, W1, W2) ---------
	var seed_before: int = host.match_seed
	host._on_message({"t": "reveal", "seed": 123})
	host._on_message({"t": "hello", "v": 2, "name": "Mallory", "channel": "x", "commit": "y"})
	_check("a second reveal/hello after READY changes nothing", host.match_seed == seed_before and host.opp_name == "Bob" and host.is_ready())
	client._on_message({"t": "round", "round": 2, "go_in": 3.0})
	_check("a round jump (0 -> 2) is refused", client.round_index == -1 and not client.round_open)
	client._on_message({"t": "round", "round": 0, "go_in": 1e9})
	_check("go_in is clamped to 10 s", _last("client", "round").size() == 3 and _last("client", "round")[2] <= 10.0, str(_last("client", "round")))
	client.round_open = false
	client.round_index = -1
	_clear()
	_check("clean_name strips control characters", Session.clean_name("Bo\nb\t\u0007") == "Bob")
	_check("_num refuses strings / NaN / out of range", Session._num("5", 0, 10, -1) == -1 and Session._num(NAN, 0, 10, -1) == -1 and Session._num(50, 0, 10, -1) == -1 and Session._num(5, 0, 10, -1) == 5)

	# --- round 1: both finish, the lower time wins (host decides) --------------
	ok = await _round()
	_check("client gets the round start", ok)
	_check("both play the same level", host.current_level_id() == client.current_level_id() and host.current_level_id() == host.match_levels[0])
	client.send_progress(0.42, Vector2i(5, 7), 3, true)
	ok = await _wait(func(): return _has("host", "prog"))
	var pr := _last("host", "prog")
	_check("host sees the client's progress", ok and pr.size() == 4 and is_equal_approx(pr[1], 0.42) and pr[2] == Vector2i(5, 7) and pr[3] == 3, str(pr))
	client._on_message({"t": "finish", "round": 0, "cs": "fast"})
	client._on_message({"t": "finish", "round": 0, "cs": -5})
	_check("finish with a bad time is ignored", client.opp_cs == -1)
	client.send_rabbit("matrix", true, 0.725, Vector2i(3, 0), Vector2i(0, 0))
	ok = await _wait(func(): return _has("host", "rabbit"))
	_check("host sees the client's rabbit (id, good)", ok and _last("host", "rabbit")[1] == "matrix" and _last("host", "rabbit")[2] == true)
	client.report_finish(50.0)
	host.report_finish(60.0)
	var d := await _decided()
	_check("round 1: client (50 s) beats host (60 s) on both sides", d[0] == "loss" and d[1] == "win" and d[2] == "time", str(d))
	_check("the host's time arrived as hundredths", client.opp_cs == 6000 and host.opp_cs == 5000)
	_check("score 0:1 / 1:0", host.score_me == 0 and host.score_opp == 1 and client.score_me == 1 and client.score_opp == 0)

	# --- round 2: the host finishes, the client's clock passes it -------------
	ok = await _round()
	host.report_finish(40.0)
	ok = await _wait(func(): return client.opp_cs >= 0)
	_check("client learns the host's time", ok and client.opp_cs == 4000)
	_check("still racing at 39.99 s", not client.tick_round(39.99) and client.round_open)
	_check("40.004 s rounds to 40.00: still racing (hundredths)", not client.tick_round(40.004))
	_check("40.01 s: the round is lost", client.tick_round(40.01))
	d = await _decided()
	_check("round 2 to the host on both sides", d[0] == "win" and d[1] == "loss", str(d))
	_check("score 1:1", host.score_me == 1 and client.score_me == 1)

	# --- round 3: both die almost at once -> the one who got further ----------
	ok = await _round()
	client.report_died(0.30, 20.0)
	host.report_died(0.55, 19.0) # same frame, before any packet moved
	d = await _decided()
	_check("both dead: the host got further (55 % vs 30 %) on both sides", d[0] == "win" and d[1] == "loss" and d[2] == "progress", str(d))
	ok = await _wait(func(): return _has("host", "over") and _has("client", "over"))
	_check("match over on both sides", ok)
	_check("host wins 2:1, client loses 1:2", _last("host", "over")[1] == true and _last("host", "over")[2] == 2 and _last("client", "over")[1] == false and _last("client", "over")[3] == 2)
	_check("match_finished is set before round_decided (no round after the last, QA W8)", host.match_finished and client.match_finished)
	host.start_next_round()
	_check("no round after the match", host.round_index == 2)
	_check("history has three rounds on both sides", host.history.size() == 3 and client.history.size() == 3)

	# --- REVANCHE on the same connection ---------------------------------------
	_clear()
	var old_seed: int = host.match_seed
	host.request_rematch()
	ok = await _wait(func(): return _has("client", "rematch"))
	_check("the client sees the host's rematch request", ok and client.rematch_asked_by_opponent())
	client.request_rematch()
	ok = await _wait(func(): return _has("host", "ready") and _has("client", "ready"))
	_check("rematch: a new match is ready on both sides", ok)
	_check("rematch: new seed, same on both", host.match_seed == client.match_seed and host.match_seed != old_seed)
	_check("rematch: scores reset", host.score_me == 0 and client.score_opp == 0 and not host.match_finished)

	# --- the exact same death on both sides -> no point --------------------------
	ok = await _round()
	client.report_died(0.40, 15.0)
	host.report_died(0.40, 15.0)
	d = await _decided()
	_check("both dead, equally far, same time: no point on both sides", d[0] == "none" and d[1] == "none", str(d))

	# --- a finisher against a dead opponent ------------------------------------
	ok = await _round()
	client.report_died(0.2, 10.0)
	ok = await _wait(func(): return _has("host", "decided"))
	_check("dead client vs running host: host wins at once", ok and _last("host", "decided")[2] == "win")
	await _wait(func(): return _has("client", "decided"))

	# --- the opponent leaves; a new one can join the host (QA W2) -------------
	_clear()
	client.close()
	ok = await _wait(func(): return _has("host", "left"))
	_check("host notices the client leaving", ok)
	_check("during a running match it counts as during_match", _last("host", "left")[1] == true)
	host.close()
	client.queue_free()
	host.queue_free()
	await _frames(3)

	port += 60
	ok = await _connect_pair(port)
	_check("fresh pair ready", ok)
	client.close()
	await _wait(func(): return host.state == Session.State.HOSTING)
	_check("lobby: after the opponent left, the host listens again", host.state == Session.State.HOSTING)
	var second = Session.new()
	second.my_name = "Carol"
	root.add_child(second)
	second.join("127.0.0.1", port)
	ok = await _wait(func(): return host.is_ready() and second.is_ready(), 900)
	_check("a second opponent reaches READY", ok, "host %d second %d" % [host.state, second.state])
	_check("the host now plays Carol", host.opp_name == "Carol")
	second.close()
	host.close()

	# --- joining where nobody hosts gives up with a message (QA W3) -----------
	var lonely = Session.new()
	root.add_child(lonely)
	lonely.join("127.0.0.1", port + 1)
	ok = await _wait(func(): return lonely.state == Session.State.IDLE, 20000)
	_check("join without host ends in IDLE (no endless 'Verbinde …')", ok)
	_check("join with a malformed address is refused at once", lonely.join("not an ip", port) != OK and lonely.state == Session.State.IDLE)

	_check("levels_for is deterministic", Session.levels_for(123) == Session.levels_for(123))
	await _frames(2)
	if failures == 0:
		print("test_versus_session: all %d checks passed" % checks)
	else:
		print("test_versus_session: %d of %d checks FAILED" % [failures, checks])
	quit(1 if failures > 0 else 0)
