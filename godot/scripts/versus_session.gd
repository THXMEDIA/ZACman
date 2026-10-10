extends Node
## VersusSession — the network side of a Versus race ("Gegenwind", E17,
## docs/design/multiplayer.md 2–3).
##
## Two players race the same levels in their OWN copy of the maze (mirror
## race): nothing about walls, pellets or ghosts is synced, every client
## simulates its own run. Only small messages travel:
##
##   hello   {v, name, channel, commit, week}   both, on connect
##   reveal  {seed}                              both, after both hellos / rematch
##   rematch {commit}                            both, REVANCHE pressed
##   round   {round, go_in}                      host: start round N in go_in s
##   prog    {round, frac, r, c, lives}          both, ~5 per second (own channel)
##   rabbit  {round, cond, good, p, own, opp}    both, when a rabbit is picked
##   finish  {round, cs}                         both, own level cleared (1/100 s)
##   died    {round, frac, cs}                   both, own last life lost
##   lost    {round}                             client: my clock passed the host's time
##   result  {round, winner, cause}              host: the round's result
##   bye     {why}                               both, leaving
##
## Protocol 3 adds the mode "arena" (both players in ONE maze, `round` carries
## `mode`). Only in that mode:
##   pos     {round, x, z, yaw}                  both, ~15/s, unreliable channel
##   eat     {round, r, c}                       both, I ate a pickup of my set
##   gh      {round, g:[[fr,fc,tr,tc,t,mode]…], f, gs}  host: the ghosts, ~10/s
##   ghit    {round, i}                          client: ghost i caught me (send it home)
##   gate    {round, i}                          client: I ate the frightened ghost i
##   power   {round, gs}                         client: I ate a power pellet (only gs counts:
##                                               the host opens the window on the `eat` of a power cell)
##   mode    {mode}                              host: the chosen mode, in the lobby (UX K1)
## and `prog` carries `gs` (my ghost speed factor from a rabbit condition). The
## HOST simulates the ghosts (the nearest player is the target); every client
## decides its own lives (trust-based, like everything here).
##
## The HOST decides every round (code review K1): both report what happened
## to them, the host applies the rules and sends `result`, both apply the same
## result. Rules (docs/design/multiplayer.md 2):
##   both finished              -> lower time (hundredths); equal -> host
##   finished vs. dead/conceded -> the finisher
##   dead vs. still running     -> the runner
##   both dead                  -> the one who got further; equal -> later death; equal -> no point
## The match seed comes from both players' secret seeds by commit-reveal
## (ChatDuel.commit / match_seed), so neither side can choose it. From it both
## derive the same three levels and the same rabbit generator per round.
##
## Everything that comes from the network is checked (types, ranges, state):
## the opponent may run a broken or modified client (code review K2, W1–W3).
##
## Transport: Godot's ENetMultiplayerPeer used as a plain packet peer (JSON
## packets, no RPCs, not attached to the SceneTree's multiplayer), so two
## sessions can run in one process for tests and a Steam peer can replace
## ENet later (docs/STEAM_ROADMAP.md) without touching the protocol.

const ChatDuelScript := preload("res://scripts/chat_duel.gd")
const LevelsScript := preload("res://scripts/levels.gd")

signal state_changed(state: int, text: String)
## Both players are known and the match seed is agreed (also after a rematch).
signal match_ready
## The host started round `round`; it goes in `go_in` seconds.
signal round_started(round: int, go_in: float)
signal opponent_progress(frac: float, cell: Vector2i, lives: int)
## Arena: the opponent's position and facing (world x/z, yaw).
signal opponent_pos(x: float, z: float, yaw: float)
## Arena: the opponent ate the pickup in this cell.
signal opponent_ate(cell: Vector2i)
## Arena, client: the host's ghosts. `list` = snapshots, `frightened` seconds left.
signal ghosts_received(list: Array, frightened: float, gscale: float)
## Client: the host chose this mode in the lobby.
signal mode_announced(mode: String)
## Arena, host: the client's ghost events: "hit" (send ghost i home), "ate", "power".
signal ghost_event(kind: String, index: int)
signal opponent_rabbit(cond: String, good: bool, p: float)
## The opponent cleared their level in `cs` hundredths.
signal opponent_finished(cs: int)
## The opponent lost their last life.
signal opponent_out
## The round's result, the same on both sides. `outcome`: "win", "loss" or
## "none"; `cause`: "time", "lives", "progress", "tie", "conceded", "none".
signal round_decided(round: int, outcome: String, cause: String)
signal match_over(i_won: bool, score_me: int, score_opp: int)
## The opponent asked for a rematch (REVANCHE) — or both did, see match_ready.
signal rematch_requested
## The opponent is gone. `during_match`: a match was running (not finished).
signal opponent_left(during_match: bool)

const PROTOCOL := 3
const DEFAULT_PORT := 47823
const ROUNDS_TO_WIN := 2 # best of three
const MATCH_LEVELS := 3
const GO_DELAY_S := 3.0
const PROGRESS_INTERVAL_S := 0.2
const CH_RELIABLE := 0
const CH_PROGRESS := 1
## Arena positions and ghost snapshots (unreliable, ordered).
const CH_STATE := 2
const CHANNELS := 3
const MODE_RACE := "race"
const MODE_ARENA := "arena"
const POS_INTERVAL_S := 1.0 / 15.0
const GHOST_INTERVAL_S := 0.05 # 20/s: a puppet waits at most this long at a cell edge (code review W4)
const MIN_POS_GAP_S := 0.03
const MAX_GHOSTS := 16
const WORLD_LIMIT := 600.0
## Joining gives up after this long (QA W3).
const JOIN_TIMEOUT_S := 10.0
## Incoming limits (code review W3).
const MAX_PACKET_BYTES := 1024
const MAX_PACKETS_PER_POLL := 64
const MIN_PROGRESS_GAP_S := 0.05
## ENet notices a silent drop within 2–8 s (code review W5).
const PEER_TIMEOUT_LIMIT := 32
const PEER_TIMEOUT_MIN_MS := 2000
const PEER_TIMEOUT_MAX_MS := 8000
## A death against a still running opponent is decided after this grace, so
## two deaths a few frames apart (crossing packets) count as "both dead"
## (code review K1).
const DEATH_GRACE_S := 0.6
## A round never lasts longer than this (sanity bound for times from the net).
const MAX_ROUND_CS := 360000

enum State { IDLE, HOSTING, CONNECTING, HANDSHAKE, READY, CLOSED }

var state := State.IDLE
var is_host := false
var my_name := "Spieler"
var my_channel := ""
var opp_name := ""
var opp_channel := ""
## ISO week of the host (the match's board label).
var host_week := Vector2i.ZERO
## "race" (mirror race, each in an own copy) or "arena" (one shared maze). The
## host chooses it before a match; the client learns it with every `round`.
var mode := MODE_ARENA
var my_week := Vector2i.ZERO
var match_seed := 0
## The three level ids of the match, identical on both sides.
var match_levels: Array = []
var round_index := -1
var score_me := 0
var score_opp := 0
var round_open := false
var match_finished := false
## Per round, both sides (host bookkeeping; the client keeps its own part):
## finish time in hundredths (-1 = not finished), death and how far they got.
var my_cs := -1
var opp_cs := -1
var my_dead := false
var opp_dead := false
var my_dead_frac := 0.0
var opp_dead_frac := 0.0
var my_dead_cs := 0
var opp_dead_cs := 0
var opp_conceded := false
## Client: I passed the host's time and told it so (sent once per round).
var _i_conceded := false
## One entry per decided round: {level, my_cs, opp_cs, outcome, cause,
## my_cond, my_good, opp_cond, opp_good} — for the match summary.
var history: Array = []
var _my_cond := ""
var _my_good := true
var _opp_cond := ""
var _opp_good := true

var _peer: ENetMultiplayerPeer = null
var _other_id := 0
var _secret := 0
var _hello_sent := false
var _hello_got := false
var _reveal_sent := false
var _awaiting_reveal := false
var _opp_commit := ""
var _opp_seed := -1
var _rematch_me := false
var _rematch_opp := false
var _last_progress_sent := -1000.0
var _last_progress_got := -1000.0
## Arena: the opponent's ghost speed factor (from his rabbit condition).
var opp_gscale := 1.0
var _last_pos_sent := -1000.0
var _last_pos_got := -1000.0
var _last_ghosts_sent := -1000.0
var _last_ghosts_got := -1000.0
var _connect_started := 0.0
## Host: when a pending "dead vs running" decision falls (-1 = none).
var _death_decide_at := -1.0
var _clock := 0.0


func _process(delta: float) -> void:
	_clock += delta
	poll()
	if _death_decide_at >= 0.0 and _clock >= _death_decide_at:
		_death_decide_at = -1.0
		_host_try_decide(true)


## ---- connection ----------------------------------------------------------

func host(port: int = DEFAULT_PORT) -> int:
	close()
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_server(port, 1, CHANNELS)
	if err != OK:
		_peer = null
		_set_state(State.IDLE, "Port %d ist belegt oder gesperrt." % port)
		return err
	is_host = true
	_wire_peer()
	_set_state(State.HOSTING, "Warte auf Gegner (Port %d) …" % port)
	return OK


## No address in any status text: streamers must not show IPs (UX K1).
func join(address: String, port: int = DEFAULT_PORT) -> int:
	close()
	if not address.is_valid_ip_address():
		_set_state(State.IDLE, "Bitte eine gültige IP-Adresse eingeben.")
		return ERR_INVALID_PARAMETER
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_client(address, port, CHANNELS)
	if err != OK:
		_peer = null
		_set_state(State.IDLE, "Verbindung zum Host nicht möglich.")
		return err
	is_host = false
	_wire_peer()
	_connect_started = _clock
	_set_state(State.CONNECTING, "Verbinde mit dem Host …")
	return OK


func close() -> void:
	if _peer != null:
		if _other_id != 0 and _peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
			_send({"t": "bye", "why": "leave"})
			_peer.poll()
		_peer.close()
	_peer = null
	_other_id = 0
	_reset_handshake()
	match_seed = 0
	match_levels.clear()
	round_index = -1
	score_me = 0
	score_opp = 0
	round_open = false
	match_finished = false
	history.clear()
	if state != State.IDLE:
		_set_state(State.IDLE, "")


func is_ready() -> bool:
	return state == State.READY


## A match is under way (started and not finished).
func match_running() -> bool:
	return state == State.READY and round_index >= 0 and not match_finished


## My side of the duel: the host is A, the client B.
func my_side() -> int:
	return ChatDuelScript.SIDE_A if is_host else ChatDuelScript.SIDE_B


func poll() -> void:
	if _peer == null:
		return
	_peer.poll()
	if _peer == null:
		return
	if state == State.CONNECTING:
		var st := _peer.get_connection_status()
		if st == MultiplayerPeer.CONNECTION_DISCONNECTED or _clock - _connect_started > JOIN_TIMEOUT_S:
			_fail("Host nicht erreichbar. Läuft dort HOSTEN, ist der Port freigegeben?")
			return
	var n := 0
	while _peer != null and _peer.get_available_packet_count() > 0 and n < MAX_PACKETS_PER_POLL:
		n += 1
		var from := _peer.get_packet_peer()
		var raw := _peer.get_packet()
		if from != _other_id or raw.size() > MAX_PACKET_BYTES:
			continue
		var msg = JSON.parse_string(raw.get_string_from_utf8())
		if msg is Dictionary:
			_on_message(msg)


func _wire_peer() -> void:
	_peer.peer_connected.connect(_on_peer_connected)
	_peer.peer_disconnected.connect(_on_peer_disconnected)


func _on_peer_connected(id: int) -> void:
	if _other_id != 0:
		return # a third player: ignored (two-player races only)
	_other_id = id
	var pp = _peer.get_peer(id)
	if pp != null:
		pp.set_timeout(PEER_TIMEOUT_LIMIT, PEER_TIMEOUT_MIN_MS, PEER_TIMEOUT_MAX_MS)
	_reset_handshake()
	_secret = _random_secret()
	_awaiting_reveal = true
	_set_state(State.HANDSHAKE, "Verbunden – Abgleich …")
	_send_hello()


func _on_peer_disconnected(id: int) -> void:
	if id != _other_id:
		return
	_opponent_gone()


## The opponent is gone (disconnect or bye). In the lobby a host keeps
## listening for the next opponent (QA W2); a client is done.
func _opponent_gone() -> void:
	var during := match_running()
	_other_id = 0
	round_open = false
	_reset_handshake()
	# Listen for a new opponent only in the lobby, never after a match was
	# played (re-review N1: a stranger must not start a "rematch").
	if is_host and _peer != null and round_index < 0:
		match_seed = 0
		match_levels.clear()
		round_index = -1
		match_finished = false
		_set_state(State.HOSTING, "Gegner hat die Verbindung getrennt – warte auf einen neuen …")
	else:
		_set_state(State.CLOSED, "Gegner hat die Verbindung getrennt.")
	opponent_left.emit(during)


func _reset_handshake() -> void:
	_hello_sent = false
	_hello_got = false
	_reveal_sent = false
	_awaiting_reveal = false
	_opp_commit = ""
	_opp_seed = -1
	_rematch_me = false
	_rematch_opp = false


func _fail(text: String) -> void:
	if _peer != null:
		_peer.poll() # flush a pending bye before closing (re-review W6)
		_peer.close()
	_peer = null
	_other_id = 0
	_reset_handshake()
	_set_state(State.IDLE, text)


func _send_hello() -> void:
	if _hello_sent:
		return
	_hello_sent = true
	_send({"t": "hello", "v": PROTOCOL, "name": my_name, "channel": my_channel,
		"commit": ChatDuelScript.commit(_secret), "week": [my_week.x, my_week.y]})


## ---- protocol ------------------------------------------------------------

func _on_message(m: Dictionary) -> void:
	var t: String = str(m.get("t", ""))
	var r := int(_num(m.get("round"), -1, 99, -1))
	match t:
		"hello":
			if state != State.HANDSHAKE or _hello_got:
				return
			if int(_num(m.get("v"), 0, 1000, 0)) != PROTOCOL:
				_send({"t": "bye", "why": "version"})
				_fail("Andere Spielversion beim Gegner (Protokoll %d) – bitte beide aktualisieren." % PROTOCOL)
				return
			_hello_got = true
			opp_name = clean_name(str(m.get("name", "")))
			var ch := ChatDuelScript.norm_channel(str(m.get("channel", "")))
			opp_channel = ch if ChatDuelScript.valid_channel(ch) else ""
			_opp_commit = str(m.get("commit", ""))
			host_week = my_week
			if not is_host:
				var w = m.get("week")
				host_week = Vector2i.ZERO
				if w is Array and w.size() == 2:
					var y := int(_num(w[0], 0, 3000, 0))
					var k := int(_num(w[1], 0, 60, 0))
					if y >= 2000 and y <= 2100 and k >= 1 and k <= 53:
						host_week = Vector2i(y, k)
			_send_hello()
			_maybe_reveal()
		"rematch":
			if state != State.READY or not match_finished or _rematch_opp:
				return
			_rematch_opp = true
			_opp_commit = str(m.get("commit", ""))
			rematch_requested.emit()
			_maybe_reveal()
		"reveal":
			if not _awaiting_reveal or _opp_seed >= 0:
				return
			var s = m.get("seed")
			if not (s is float or s is int):
				return
			_opp_seed = int(s)
			if not ChatDuelScript.verify(_opp_seed, _opp_commit):
				_send({"t": "bye", "why": "handshake"})
				_fail("Verbindung fehlerhaft – bitte neu verbinden.")
				return
			_maybe_reveal()
			_finish_handshake()
		"round":
			if is_host or state != State.READY or round_open or match_finished or r != round_index + 1 or r >= MATCH_LEVELS:
				return
			var rm := str(m.get("mode", MODE_RACE))
			mode = MODE_ARENA if rm == MODE_ARENA else MODE_RACE
			_open_round(r)
			round_started.emit(round_index, _num(m.get("go_in"), 0.5, 10.0, GO_DELAY_S))
		"prog":
			if r != round_index or not round_open:
				return
			if _clock - _last_progress_got < MIN_PROGRESS_GAP_S:
				return
			_last_progress_got = _clock
			opp_gscale = _num(m.get("gs"), 0.2, 3.0, 1.0)
			opponent_progress.emit(_num(m.get("frac"), 0.0, 1.0, 0.0),
				Vector2i(int(_num(m.get("r"), -1, 200, -1)), int(_num(m.get("c"), -1, 200, -1))),
				int(_num(m.get("lives"), 0, 9, 0)))
		"pos":
			if mode != MODE_ARENA or r != round_index or not round_open:
				return
			if _clock - _last_pos_got < MIN_POS_GAP_S:
				return
			_last_pos_got = _clock
			var px := _num(m.get("x"), -10.0, WORLD_LIMIT, NAN)
			var pz := _num(m.get("z"), -10.0, WORLD_LIMIT, NAN)
			if is_nan(px) or is_nan(pz):
				return
			opponent_pos.emit(px, pz, _num(m.get("yaw"), -7.0, 7.0, 0.0))
		"eat":
			if mode != MODE_ARENA or r != round_index or not round_open:
				return
			var er := int(_num(m.get("r"), 0, 400, -1))
			var ec := int(_num(m.get("c"), 0, 400, -1))
			if er >= 0 and ec >= 0:
				opponent_ate.emit(Vector2i(er, ec))
		"gh":
			if mode != MODE_ARENA or is_host or r != round_index or not round_open:
				return
			if _clock - _last_ghosts_got < MIN_POS_GAP_S:
				return
			var g = m.get("g")
			if not (g is Array) or g.size() > MAX_GHOSTS:
				return
			var list: Array = []
			for e in g:
				var snap := _clean_ghost(e)
				if snap.is_empty():
					return
				list.append(snap)
			_last_ghosts_got = _clock
			ghosts_received.emit(list, _num(m.get("f"), 0.0, 30.0, 0.0), _num(m.get("gs"), 0.2, 3.0, 1.0))
		"ghit", "gate":
			if mode != MODE_ARENA or not is_host or r != round_index or not round_open:
				return
			var gi := int(_num(m.get("i"), 0, MAX_GHOSTS - 1, -1))
			if gi >= 0:
				ghost_event.emit("hit" if t == "ghit" else "ate", gi)
		"power":
			if mode != MODE_ARENA or not is_host or r != round_index or not round_open:
				return
			opp_gscale = _num(m.get("gs"), 0.2, 3.0, opp_gscale)
			ghost_event.emit("power", 0)
		"mode":
			if is_host or state != State.READY or round_open:
				return
			var mm := str(m.get("mode", ""))
			if mm == MODE_ARENA or mm == MODE_RACE:
				mode = mm
				mode_announced.emit(mode)
		"rabbit":
			if r != round_index or not round_open:
				return
			_opp_cond = ChatDuelScript.clean_id(str(m.get("cond", "")))
			_opp_good = m.get("good", true) == true
			opponent_rabbit.emit(_opp_cond, _opp_good, _num(m.get("p"), 0.0, 1.0, 0.6))
		"finish":
			if r != round_index or not round_open or opp_cs >= 0 or opp_dead:
				return
			var cs := int(_num(m.get("cs"), 1, MAX_ROUND_CS, -1))
			if cs <= 0:
				return
			opp_cs = cs
			opponent_finished.emit(cs)
			_host_try_decide()
		"died":
			if r != round_index or not round_open or opp_dead or opp_cs >= 0:
				return
			opp_dead = true
			opp_dead_frac = _num(m.get("frac"), 0.0, 1.0, 0.0)
			opp_dead_cs = int(_num(m.get("cs"), 0, MAX_ROUND_CS, 0))
			opponent_out.emit()
			_host_try_decide()
		"lost":
			# client conceded: its clock passed the host's finish time
			if not is_host or r != round_index or not round_open or my_cs < 0:
				return
			opp_conceded = true
			_host_try_decide()
		"result":
			if is_host or r != round_index or not round_open:
				return
			var winner := str(m.get("winner", ""))
			var cause := str(m.get("cause", ""))
			if not ["host", "client", "none"].has(winner) or not ["time", "lives", "progress", "tie", "conceded", "none"].has(cause):
				return
			var outcome := "none"
			if winner == "client":
				outcome = "win"
			elif winner == "host":
				outcome = "loss"
			_apply_result(outcome, cause)
		"bye":
			if _other_id != 0:
				var why := str(m.get("why", ""))
				_opponent_gone()
				if why == "version":
					_set_state(State.CLOSED, "Der Gegner hat eine andere Spielversion – bitte beide aktualisieren.")
				elif why == "handshake":
					_set_state(State.CLOSED, "Verbindung fehlerhaft – bitte neu verbinden.")


func _maybe_reveal() -> void:
	if _reveal_sent or not _awaiting_reveal:
		return
	if state == State.HANDSHAKE and not (_hello_got and _hello_sent):
		return
	if state == State.READY and not (_rematch_me and _rematch_opp):
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
	round_open = false
	match_finished = false
	history.clear()
	_awaiting_reveal = false
	_rematch_me = false
	_rematch_opp = false
	_set_state(State.READY, "Bereit: %s gegen %s" % [my_name, opp_name])
	if is_host:
		_send({"t": "mode", "mode": mode})
	match_ready.emit()


## REVANCHE: a new match on the same connection, with new seeds (both must ask).
func request_rematch() -> void:
	if state != State.READY or not match_finished or _rematch_me:
		return
	_rematch_me = true
	_secret = _random_secret()
	_opp_seed = -1
	_reveal_sent = false
	_awaiting_reveal = true
	_send({"t": "rematch", "commit": ChatDuelScript.commit(_secret)})
	_maybe_reveal()


func rematch_asked_by_opponent() -> bool:
	return _rematch_opp


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


## ---- rounds ------------------------------------------------------------------

## Host: starts the next round for both players.
func start_next_round(go_in: float = GO_DELAY_S) -> void:
	if not is_host or state != State.READY or match_finished or round_open or round_index + 1 >= MATCH_LEVELS:
		return
	_open_round(round_index + 1)
	_send({"t": "round", "round": round_index, "go_in": go_in, "mode": mode})
	round_started.emit(round_index, go_in)


func _open_round(r: int) -> void:
	round_index = r
	my_cs = -1
	opp_cs = -1
	my_dead = false
	opp_dead = false
	my_dead_frac = 0.0
	opp_dead_frac = 0.0
	my_dead_cs = 0
	opp_dead_cs = 0
	opp_conceded = false
	_i_conceded = false
	_death_decide_at = -1.0
	_my_cond = ""
	_opp_cond = ""
	opp_gscale = 1.0 # no old Taschenuhr factor in the new round
	round_open = true


func current_level_id() -> String:
	if round_index < 0 or match_levels.is_empty():
		return ""
	return String(match_levels[round_index % match_levels.size()])


func next_level_id() -> String:
	var n := round_index + 1
	if n < 0 or n >= match_levels.size():
		return ""
	return String(match_levels[n])


## My run sends its progress; throttled to PROGRESS_INTERVAL_S.
func send_progress(frac: float, cell: Vector2i, lives: int, force: bool = false, gscale: float = 1.0) -> void:
	if not round_open or _other_id == 0:
		return
	if not force and _clock - _last_progress_sent < PROGRESS_INTERVAL_S:
		return
	_last_progress_sent = _clock
	_send({"t": "prog", "round": round_index, "frac": snappedf(frac, 0.001), "r": cell.x, "c": cell.y, "lives": lives, "gs": snappedf(gscale, 0.01)}, CH_PROGRESS)


## Host: choose the mode (lobby only); the client is told right away.
func set_mode(m: String) -> void:
	if not is_host or match_running():
		return
	mode = MODE_ARENA if m == MODE_ARENA else MODE_RACE
	if state == State.READY:
		_send({"t": "mode", "mode": mode})


## ---- Arena senders (see the header) -------------------------------------------

func send_pos(x: float, z: float, yaw: float, force: bool = false) -> void:
	if mode != MODE_ARENA or not round_open or _other_id == 0:
		return
	if not force and _clock - _last_pos_sent < POS_INTERVAL_S:
		return
	_last_pos_sent = _clock
	_send({"t": "pos", "round": round_index, "x": snappedf(x, 0.01), "z": snappedf(z, 0.01), "yaw": snappedf(yaw, 0.01)}, CH_STATE, true)


func send_eat(cell: Vector2i) -> void:
	if mode == MODE_ARENA and round_open:
		_send({"t": "eat", "round": round_index, "r": cell.x, "c": cell.y})


## Host: a ghost snapshot is due (so the list is only built when it is sent).
func ghosts_due() -> bool:
	return mode == MODE_ARENA and is_host and round_open and _clock - _last_ghosts_sent >= GHOST_INTERVAL_S


## Host only: the ghosts' state for the client.
func send_ghosts(list: Array, frightened: float, gscale: float, force: bool = false) -> void:
	if mode != MODE_ARENA or not is_host or not round_open or _other_id == 0:
		return
	if not force and _clock - _last_ghosts_sent < GHOST_INTERVAL_S:
		return
	_last_ghosts_sent = _clock
	_send({"t": "gh", "round": round_index, "g": list, "f": snappedf(frightened, 0.1), "gs": snappedf(gscale, 0.01)}, CH_STATE, true)


## Client only: "hit" (ghost i caught me), "ate" (I ate ghost i) or "power".
func send_ghost_event(kind: String, index: int, gscale: float = 1.0) -> void:
	if mode != MODE_ARENA or is_host or not round_open:
		return
	match kind:
		"hit":
			_send({"t": "ghit", "round": round_index, "i": index})
		"ate":
			_send({"t": "gate", "round": round_index, "i": index})
		"power":
			_send({"t": "power", "round": round_index, "gs": snappedf(gscale, 0.01)})


func send_rabbit(cond: String, good: bool, p: float, own: Vector2i, opp: Vector2i) -> void:
	if round_open:
		_my_cond = cond
		_my_good = good
		_send({"t": "rabbit", "round": round_index, "cond": cond, "good": good, "p": snappedf(p, 0.0001), "own": [own.x, own.y], "opp": [opp.x, opp.y]})


## Hundredths of a second, the unit of every comparison (code review W4).
static func to_cs(time_s: float) -> int:
	return int(round(time_s * 100.0))


func report_finish(time_s: float) -> void:
	if not round_open or my_cs >= 0 or my_dead or _i_conceded:
		return
	my_cs = clampi(to_cs(time_s), 1, MAX_ROUND_CS)
	_send({"t": "finish", "round": round_index, "cs": my_cs})
	_host_try_decide()


func report_died(frac: float = 0.0, time_s: float = 0.0) -> void:
	if not round_open or my_dead or my_cs >= 0 or _i_conceded:
		return
	my_dead = true
	my_dead_frac = clampf(frac, 0.0, 1.0)
	my_dead_cs = clampi(to_cs(time_s), 0, MAX_ROUND_CS)
	_send({"t": "died", "round": round_index, "frac": snappedf(my_dead_frac, 0.001), "cs": my_dead_cs})
	_host_try_decide()


## Every frame of my running round: has my clock passed the opponent's
## finish time? The host decides it itself; the client concedes (`lost`) and
## waits for the host's result. Returns true when the round is lost for me.
func tick_round(my_elapsed: float) -> bool:
	if not round_open or opp_cs < 0 or my_cs >= 0 or my_dead:
		return false
	if to_cs(my_elapsed) <= opp_cs:
		return false
	if is_host:
		_host_decide("client", "time")
	elif not _i_conceded:
		_i_conceded = true
		_send({"t": "lost", "round": round_index})
	return true


## Host only: decides once the facts suffice. A death against a running
## opponent waits DEATH_GRACE_S first (`grace_over` = the wait is done).
func _host_try_decide(grace_over: bool = false) -> void:
	if not is_host or not round_open:
		return
	if my_cs >= 0 and opp_cs >= 0:
		if my_cs == opp_cs:
			_host_decide("host", "tie")
		else:
			_host_decide("host" if my_cs < opp_cs else "client", "time")
	elif my_cs >= 0 and (opp_dead or opp_conceded):
		_host_decide("host", "lives" if opp_dead else "conceded")
	elif opp_cs >= 0 and my_dead:
		_host_decide("client", "lives")
	elif my_dead and opp_dead:
		if not is_equal_approx(my_dead_frac, opp_dead_frac):
			_host_decide("host" if my_dead_frac > opp_dead_frac else "client", "progress")
		elif my_dead_cs != opp_dead_cs:
			_host_decide("host" if my_dead_cs > opp_dead_cs else "client", "progress")
		else:
			_host_decide("none", "none")
	elif (opp_dead and my_cs < 0 and not my_dead) or (my_dead and opp_cs < 0 and not opp_dead):
		if not grace_over:
			if _death_decide_at < 0.0:
				_death_decide_at = _clock + DEATH_GRACE_S
			return
		_host_decide("host" if opp_dead else "client", "lives")


func _host_decide(winner: String, cause: String) -> void:
	if not is_host or not round_open:
		return
	_death_decide_at = -1.0
	_send({"t": "result", "round": round_index, "winner": winner, "cause": cause})
	var outcome := "none"
	if winner == "host":
		outcome = "win"
	elif winner == "client":
		outcome = "loss"
	_apply_result(outcome, cause)


func _apply_result(outcome: String, cause: String) -> void:
	if not round_open:
		return
	round_open = false
	if outcome == "win":
		score_me += 1
	elif outcome == "loss":
		score_opp += 1
	history.append({"level": current_level_id(), "my_cs": my_cs, "opp_cs": opp_cs, "outcome": outcome, "cause": cause,
		"my_cond": _my_cond, "my_good": _my_good, "opp_cond": _opp_cond, "opp_good": _opp_good})
	# The match end is known BEFORE round_decided fires, so no listener
	# schedules a next round after the last one (QA W8).
	if score_me >= ROUNDS_TO_WIN or score_opp >= ROUNDS_TO_WIN or round_index + 1 >= MATCH_LEVELS:
		match_finished = true
	round_decided.emit(round_index, outcome, cause)
	if match_finished:
		match_over.emit(score_me > score_opp, score_me, score_opp)


## ---- helpers ---------------------------------------------------------------

func _send(msg: Dictionary, channel: int = CH_RELIABLE, unreliable: bool = false) -> void:
	if _peer == null or _other_id == 0:
		return
	_peer.set_target_peer(_other_id)
	_peer.transfer_channel = channel
	# Reliable on the first two channels: progress is only 5 small packets a
	# second, and unreliable ENet packets from the client were lost in testing
	# (QA 04.10.). Arena positions and ghosts are dated after a few 100 ms, so
	# they go unreliable (ordered) on their own channel: a lost one costs
	# nothing, and a late one never queues behind events.
	_peer.transfer_mode = MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED if unreliable else MultiplayerPeer.TRANSFER_MODE_RELIABLE
	_peer.put_packet(JSON.stringify(msg).to_utf8_buffer())


func _set_state(s: int, text: String) -> void:
	state = s
	state_changed.emit(s, text)


## A number from the network, or `dflt` when it is no number, NaN/inf or out
## of [lo, hi] (code review W2).
static func _num(v, lo: float, hi: float, dflt: float) -> float:
	if not (v is float or v is int):
		return dflt
	var f := float(v)
	if is_nan(f) or is_inf(f) or f < lo or f > hi:
		return dflt
	return f


## One ghost snapshot from the net: [fr, fc, tr, tc, t, mode 0–3] or [] if broken.
static func _clean_ghost(e) -> Array:
	if not (e is Array) or e.size() != 6:
		return []
	var out: Array = []
	for k in 4:
		var v := _num(e[k], 0, 400, -1)
		if v < 0:
			return []
		out.append(int(v))
	var tt := _num(e[4], 0.0, 1.0, -1.0)
	var md := _num(e[5], 0, 3, -1)
	if tt < 0.0 or md < 0:
		return []
	out.append(tt)
	out.append(int(md))
	return out


## Player names: control characters out, at most 20 characters.
static func clean_name(n: String) -> String:
	var out := ""
	for ch in n:
		var c := ch.unicode_at(0)
		if c >= 32 and c != 127:
			out += ch
	out = out.strip_edges()
	if out.length() > 20:
		out = out.substr(0, 20)
	return out if out != "" else "Gegner"


## 48 bits on purpose: the seed travels as a JSON number (a double), so it
## must stay below 2^53 or `verify` would fail on rounding.
static func _random_secret() -> int:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return int(rng.randi()) * 65536 + int(rng.randi() % 65536)
