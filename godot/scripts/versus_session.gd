extends Node
## VersusSession — the network side of a Versus race ("Gegenwind", E17,
## docs/design/multiplayer.md 2–3).
##
## Two players race the same levels in their OWN copy of the maze (mirror
## race): nothing about walls, pellets or ghosts is synced, every client
## simulates its own run. Only small messages travel:
##
##   hello   {v, name, channel, commit, week}   both, on connect
##   reveal  {seed}                              both, after both hellos
##   round   {round, go_in}                      host: start round N in go_in s
##   prog    {round, frac, r, c, lives}          both, ~5 per second (own channel)
##   rabbit  {round, cond, p, own, opp}          both, when a rabbit is picked
##   finish  {round, time}                       both, own level cleared
##   died    {round}                             both, own last life lost
##   lost    {round}                             both, opponent's time passed mine
##   bye     {}                                  both, leaving
##
## The match seed comes from both players' secret seeds by commit-reveal
## (ChatDuel.commit / match_seed), so neither side can choose it. From it both
## derive the same three levels and the same rabbit generator per round.
## A round is won by the lower finish time; a player who loses their last
## life loses the round. Best of three.
##
## Transport: Godot's ENetMultiplayerPeer used as a plain packet peer (JSON
## packets, no RPCs, not attached to the SceneTree's multiplayer), so two
## sessions can run in one process for tests and a Steam peer can replace
## ENet later (docs/STEAM_ROADMAP.md) without touching the protocol.

const ChatDuelScript := preload("res://scripts/chat_duel.gd")
const LevelsScript := preload("res://scripts/levels.gd")

signal state_changed(state: int, text: String)
## Both players are known and the match seed is agreed.
signal match_ready
## The host started round `round`; it goes in `go_in` seconds.
signal round_started(round: int, go_in: float)
signal opponent_progress(frac: float, cell: Vector2i, lives: int)
signal opponent_rabbit(cond: String, p: float)
## The round's winner is known (both sides compute the same result).
signal round_decided(round: int, i_won: bool, reason: String)
signal match_over(i_won: bool, score_me: int, score_opp: int)
signal opponent_left

const PROTOCOL := 1
const DEFAULT_PORT := 47823
const ROUNDS_TO_WIN := 2 # best of three
const MATCH_LEVELS := 3
const GO_DELAY_S := 3.0
const PROGRESS_INTERVAL_S := 0.2
const CH_RELIABLE := 0
const CH_PROGRESS := 1

enum State { IDLE, HOSTING, CONNECTING, HANDSHAKE, READY, CLOSED }

var state := State.IDLE
var is_host := false
var my_name := "Spieler"
var my_channel := ""
var opp_name := ""
var opp_channel := ""
## ISO week of the host (the match runs on the host's week).
var host_week := Vector2i.ZERO
var my_week := Vector2i.ZERO
var match_seed := 0
## The three level ids of the match, identical on both sides.
var match_levels: Array = []
var round_index := -1
var score_me := 0
var score_opp := 0
## Per round: my finish time (-1 = not finished), the opponent's, deaths.
var my_time := -1.0
var opp_time := -1.0
var my_dead := false
var opp_dead := false
var round_open := false
var match_finished := false

var _peer: ENetMultiplayerPeer = null
var _other_id := 0
var _secret := 0
var _hello_sent := false
var _hello_got := false
var _reveal_sent := false
var _opp_commit := ""
var _opp_seed := -1
var _last_progress_sent := -1000.0
var _clock := 0.0


func _process(delta: float) -> void:
	_clock += delta
	poll()


## ---- connection ----------------------------------------------------------

func host(port: int = DEFAULT_PORT) -> int:
	close()
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_server(port, 1, 2)
	if err != OK:
		_peer = null
		_set_state(State.IDLE, "Port %d ist belegt oder gesperrt." % port)
		return err
	is_host = true
	_wire_peer()
	_set_state(State.HOSTING, "Warte auf Gegner an Port %d …" % port)
	return OK


func join(address: String, port: int = DEFAULT_PORT) -> int:
	close()
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_client(address, port, 2)
	if err != OK:
		_peer = null
		_set_state(State.IDLE, "Verbindung zu %s nicht möglich." % address)
		return err
	is_host = false
	_wire_peer()
	_set_state(State.CONNECTING, "Verbinde mit %s:%d …" % [address, port])
	return OK


func close() -> void:
	if _peer != null:
		if _other_id != 0 and _peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
			_send({"t": "bye"})
			_peer.poll()
		_peer.close()
	_peer = null
	_other_id = 0
	_hello_sent = false
	_hello_got = false
	_reveal_sent = false
	_opp_commit = ""
	_opp_seed = -1
	match_seed = 0
	match_levels.clear()
	round_index = -1
	score_me = 0
	score_opp = 0
	round_open = false
	match_finished = false
	if state != State.IDLE:
		_set_state(State.IDLE, "")


func is_ready() -> bool:
	return state == State.READY


## My side of the duel: the host is A, the client B.
func my_side() -> int:
	return ChatDuelScript.SIDE_A if is_host else ChatDuelScript.SIDE_B


func poll() -> void:
	if _peer == null:
		return
	_peer.poll()
	while _peer != null and _peer.get_available_packet_count() > 0:
		var from := _peer.get_packet_peer()
		var raw := _peer.get_packet()
		var msg = JSON.parse_string(raw.get_string_from_utf8())
		if msg is Dictionary:
			_on_message(from, msg)


func _wire_peer() -> void:
	_peer.peer_connected.connect(_on_peer_connected)
	_peer.peer_disconnected.connect(_on_peer_disconnected)
	_secret = _random_secret()


func _on_peer_connected(id: int) -> void:
	if _other_id != 0:
		return # a third player: ignored (two-player races only)
	_other_id = id
	_set_state(State.HANDSHAKE, "Verbunden – Abgleich …")
	_send_hello()


func _on_peer_disconnected(id: int) -> void:
	if id != _other_id:
		return
	_other_id = 0
	_set_state(State.CLOSED, "Gegner hat die Verbindung getrennt.")
	opponent_left.emit()


func _send_hello() -> void:
	if _hello_sent:
		return
	_hello_sent = true
	_send({"t": "hello", "v": PROTOCOL, "name": my_name, "channel": my_channel,
		"commit": ChatDuelScript.commit(_secret), "week": [my_week.x, my_week.y]})


## ---- protocol ------------------------------------------------------------

func _on_message(_from: int, m: Dictionary) -> void:
	match String(m.get("t", "")):
		"hello":
			if int(m.get("v", 0)) != PROTOCOL:
				_set_state(State.CLOSED, "Andere Spielversion beim Gegner.")
				return
			_hello_got = true
			opp_name = _clean_name(String(m.get("name", "Gegner")))
			opp_channel = String(m.get("channel", "")).strip_edges().to_lower().trim_prefix("#")
			_opp_commit = String(m.get("commit", ""))
			var w = m.get("week", [0, 0])
			if not is_host and w is Array and w.size() == 2:
				host_week = Vector2i(int(w[0]), int(w[1]))
			if is_host:
				host_week = my_week
			_send_hello()
			_maybe_reveal()
		"reveal":
			_opp_seed = int(m.get("seed", -1))
			if not ChatDuelScript.verify(_opp_seed, _opp_commit):
				_set_state(State.CLOSED, "Abgleich fehlgeschlagen (Seed passt nicht).")
				return
			_maybe_reveal()
			_finish_handshake()
		"round":
			if is_host:
				return
			_open_round(int(m.get("round", 0)))
			round_started.emit(round_index, float(m.get("go_in", GO_DELAY_S)))
		"prog":
			if int(m.get("round", -1)) == round_index:
				opponent_progress.emit(float(m.get("frac", 0.0)), Vector2i(int(m.get("r", 0)), int(m.get("c", 0))), int(m.get("lives", 0)))
		"rabbit":
			if int(m.get("round", -1)) == round_index:
				opponent_rabbit.emit(String(m.get("cond", "")), float(m.get("p", 0.6)))
		"finish":
			if int(m.get("round", -1)) == round_index:
				opp_time = float(m.get("time", -1.0))
				_try_decide()
		"died":
			if int(m.get("round", -1)) == round_index:
				opp_dead = true
				_try_decide()
		"lost":
			if int(m.get("round", -1)) == round_index:
				_decide(true, "Schneller im Ziel")
		"bye":
			_other_id = 0
			_set_state(State.CLOSED, "Gegner hat das Match verlassen.")
			opponent_left.emit()


func _maybe_reveal() -> void:
	if _reveal_sent or not _hello_got or not _hello_sent:
		return
	_reveal_sent = true
	_send({"t": "reveal", "seed": _secret})


func _finish_handshake() -> void:
	if _opp_seed < 0 or not _reveal_sent:
		return
	var seed_a := _secret if is_host else _opp_seed
	var seed_b := _opp_seed if is_host else _secret
	match_seed = ChatDuelScript.match_seed(seed_a, seed_b)
	match_levels = levels_for(match_seed)
	score_me = 0
	score_opp = 0
	round_index = -1
	match_finished = false
	_set_state(State.READY, "Bereit: %s gegen %s" % [my_name, opp_name])
	match_ready.emit()


## The match's levels: MATCH_LEVELS different pool levels drawn from the seed.
static func levels_for(seed: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("zapmaniac-levels|%d" % seed)
	var out: Array = []
	var last := ""
	for i in MATCH_LEVELS:
		var lv: Dictionary = LevelsScript.draw_next(out, last, rng)
		out.append(lv.id)
		last = lv.id
	return out


## ---- rounds (host drives the start, both decide the result) --------------

## Host: starts the next round for both players.
func start_next_round() -> void:
	if not is_host or state != State.READY or match_finished:
		return
	_open_round(round_index + 1)
	_send({"t": "round", "round": round_index, "go_in": GO_DELAY_S})
	round_started.emit(round_index, GO_DELAY_S)


func _open_round(r: int) -> void:
	round_index = r
	my_time = -1.0
	opp_time = -1.0
	my_dead = false
	opp_dead = false
	round_open = true


func current_level_id() -> String:
	if round_index < 0 or match_levels.is_empty():
		return ""
	return String(match_levels[round_index % match_levels.size()])


## My run sends its progress; throttled to PROGRESS_INTERVAL_S.
func send_progress(frac: float, cell: Vector2i, lives: int, force: bool = false) -> void:
	if not round_open or _other_id == 0:
		return
	if not force and _clock - _last_progress_sent < PROGRESS_INTERVAL_S:
		return
	_last_progress_sent = _clock
	_send({"t": "prog", "round": round_index, "frac": snappedf(frac, 0.001), "r": cell.x, "c": cell.y, "lives": lives}, CH_PROGRESS)


func send_rabbit(cond: String, p: float, own: Vector2i, opp: Vector2i) -> void:
	if round_open:
		_send({"t": "rabbit", "round": round_index, "cond": cond, "p": snappedf(p, 0.0001), "own": [own.x, own.y], "opp": [opp.x, opp.y]})


func report_finish(time_s: float) -> void:
	if not round_open or my_time >= 0.0 or my_dead:
		return
	my_time = time_s
	_send({"t": "finish", "round": round_index, "time": time_s})
	_try_decide()


func report_died() -> void:
	if not round_open or my_dead or my_time >= 0.0:
		return
	my_dead = true
	_send({"t": "died", "round": round_index})
	_try_decide()


## Called by Main every frame with the elapsed time of the running round:
## once the opponent's finish time is behind me, the round is lost (no need
## to play on).
func tick_round(my_elapsed: float) -> void:
	if round_open and opp_time >= 0.0 and my_time < 0.0 and not my_dead and my_elapsed > opp_time:
		_decide(false, "Gegner war schneller")


func _try_decide() -> void:
	if not round_open:
		return
	if my_dead and opp_dead:
		_decide_tie_dead()
		return
	if opp_dead and not my_dead:
		_decide(true, "Gegner ohne Leben")
		return
	if my_dead and not opp_dead:
		_decide(false, "Keine Leben mehr")
		return
	if my_time >= 0.0 and opp_time >= 0.0:
		if is_equal_approx(my_time, opp_time):
			_decide(is_host, "Gleichstand – Runde an den Host")
		else:
			_decide(my_time < opp_time, "Schneller im Ziel" if my_time < opp_time else "Gegner war schneller")
		return
	# Only my time is known: the opponent either reports a lower time
	# ("finish"), or their clock passes mine and they concede ("lost").


## Both players lost their last life in the same round: nobody gets the point.
func _decide_tie_dead() -> void:
	round_open = false
	round_decided.emit(round_index, false, "Beide ohne Leben – kein Punkt")
	_check_match_end()


func _decide(i_won: bool, reason: String) -> void:
	if not round_open:
		return
	round_open = false
	if i_won:
		score_me += 1
	else:
		score_opp += 1
	if not i_won and my_time < 0.0 and not my_dead:
		# I lost while still running (their time is behind me): tell the
		# opponent, who is waiting with only their own time.
		_send({"t": "lost", "round": round_index})
	round_decided.emit(round_index, i_won, reason)
	_check_match_end()


func _check_match_end() -> void:
	if score_me >= ROUNDS_TO_WIN or score_opp >= ROUNDS_TO_WIN or round_index + 1 >= MATCH_LEVELS:
		match_finished = true
		match_over.emit(score_me > score_opp, score_me, score_opp)


## ---- helpers ---------------------------------------------------------------

func _send(msg: Dictionary, channel: int = CH_RELIABLE) -> void:
	if _peer == null or _other_id == 0:
		return
	_peer.set_target_peer(_other_id)
	_peer.transfer_channel = channel
	# Reliable on both channels: progress is only 5 small packets a second,
	# and unreliable ENet packets from the client were lost in testing (QA
	# 04.10.). The own channel keeps progress from queueing behind events.
	_peer.transfer_mode = MultiplayerPeer.TRANSFER_MODE_RELIABLE
	_peer.put_packet(JSON.stringify(msg).to_utf8_buffer())


func _set_state(s: int, text: String) -> void:
	state = s
	state_changed.emit(s, text)


static func _clean_name(n: String) -> String:
	var t := n.strip_edges()
	if t.length() > 20:
		t = t.substr(0, 20)
	return t if t != "" else "Gegner"


static func _random_secret() -> int:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return int(rng.randi()) * 65536 + int(rng.randi() % 65536)
