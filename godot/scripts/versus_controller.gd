extends Node
## VersusController — glue between Main, the network session and the Versus
## screens (E17, docs/design/multiplayer.md). A Versus round is an ordinary
## speedrun level run by Main in this game's own copy of the maze; this node
## adds what differs:
##   - the lobby (host / join / start, Twitch) and the opponent's chat
##   - a synchronized 3-2-1 start instead of the intro and "first step" hold
##   - the rabbit from the chat duel and the match's shared round generator
##   - progress, lives and events of the opponent: race bar, minimap, events
##     ("BOB IM ZIEL 1:02.31 · NOCH 0:07.4", "BOB: STROMAUSFALL · schlecht")
##   - round results (host decides), an intermission for the chats, best of
##     three, the match summary and REVANCHE on the same connection
## Main asks `active` at its hook points and otherwise stays single-player.

const SessionScript := preload("res://scripts/versus_session.gd")
const ChatDuelScript := preload("res://scripts/chat_duel.gd")
const ConditionsScript := preload("res://scripts/conditions.gd")
const WhiteRabbitScript := preload("res://scripts/white_rabbit.gd")
const LevelsScript := preload("res://scripts/levels.gd")
const ArenaWorldScript := preload("res://scripts/arena_world.gd")
## Between rounds: time to read the result and for the chats to vote (design W3).
const INTERMISSION_S := 12.0
## After both pressed REVANCHE, the host starts round 1 after this.
const REMATCH_START_S := 5.0
## Where the condition card goes in a Versus round: under the race bar (QA W5).
const CARD_TOP_VERSUS := 236.0
const CARD_TOP_SOLO := 56.0

var main: Node
var hud
var ui
var session: Node
## Arena (one shared maze): the world node with the opponent and the ghosts,
## and whether the running match is an Arena match.
var arena: Node3D
var arena_mode := false
var duel = ChatDuelScript.new()
## true from the first round start until the match is left.
var active := false
var go_at_real := 0.0
var _opp_frac := 0.0
var _opp_lives := 3
var _my_frac := 0.0
## Main.rabbit_week_override before the match (restored when leaving).
var _saved_week_override := Vector2i(-1, -1)
## Bumped whenever a match starts or is left: timers of an old match check it
## and do nothing in a new one (QA W8).
var _token := 0
var _next_round_at := -1.0
var _paused := false
var _last_count := -1


func setup(main_node: Node) -> void:
	main = main_node
	hud = main.hud
	ui = hud.versus_ui
	session = SessionScript.new()
	add_child(session)
	arena = ArenaWorldScript.new()
	main.add_child(arena)
	arena.setup(main, session)
	session.state_changed.connect(_on_state_changed)
	session.mode_announced.connect(_on_mode_announced)
	session.match_ready.connect(_on_match_ready)
	session.round_started.connect(_on_round_started)
	session.opponent_progress.connect(_on_opponent_progress)
	session.opponent_rabbit.connect(_on_opponent_rabbit)
	session.opponent_finished.connect(_on_opponent_finished)
	session.opponent_out.connect(_on_opponent_out)
	session.round_decided.connect(_on_round_decided)
	session.match_over.connect(_on_match_over)
	session.rematch_requested.connect(_on_rematch_requested)
	session.opponent_left.connect(_on_opponent_left)
	hud.versus_pressed.connect(open_lobby)
	ui.host_requested.connect(_on_host_requested)
	ui.join_requested.connect(_on_join_requested)
	ui.start_requested.connect(func(): session.start_next_round())
	ui.mode_changed.connect(_on_mode_changed)
	ui.leave_requested.connect(leave)
	ui.result_menu_requested.connect(leave)
	ui.rematch_requested.connect(_on_rematch_pressed)
	Twitch.channel_command.connect(_on_channel_command)


func player_name() -> String:
	return session.my_name


## ---- lobby -------------------------------------------------------------------

func _on_mode_changed(mode: String) -> void:
	if session.is_host and not session.match_running():
		session.set_mode(mode)


## Client: the host's mode, shown in the lobby (UX K1).
func _on_mode_announced(mode: String) -> void:
	ui.set_mode(mode, true)


func open_lobby() -> void:
	ui.set_mode(session.mode)
	ui.show_lobby(Twitch.channel if Twitch.enabled else "", Twitch.enabled, Twitch.channel)
	ui.set_lobby_state("Hoste ein Match oder tritt per IP-Adresse bei.", false, false)
	_update_duel_text()


func _prepare_session(player_name: String) -> void:
	session.my_name = SessionScript.clean_name(player_name)
	session.my_channel = Twitch.channel if Twitch.enabled else ""
	session.my_week = main.rabbit_week_override if main.rabbit_week_override.x > 0 else WhiteRabbitScript.current_iso_week()


func _on_host_requested(player_name: String, port: int) -> void:
	_prepare_session(player_name)
	session.host(port)


func _on_join_requested(player_name: String, address: String, port: int) -> void:
	if address == "":
		ui.set_lobby_state("Bitte die IP-Adresse des Hosts eingeben.", false, false)
		return
	_prepare_session(player_name)
	session.join(address, port)


func _on_state_changed(state: int, text: String) -> void:
	var connected: bool = state == SessionScript.State.HANDSHAKE or state == SessionScript.State.READY
	var can_start: bool = state == SessionScript.State.READY and session.is_host and session.round_index < 0
	if ui.lobby.visible:
		ui.set_lobby_state(text, connected, can_start)
		if session.is_host:
			ui.set_mode(session.mode)
		elif state == SessionScript.State.IDLE:
			ui.set_mode(session.mode)
		ui.set_mode_editable(state == SessionScript.State.IDLE or (session.is_host and session.round_index < 0))
		_update_duel_text()


func _on_match_ready() -> void:
	var a: String = session.my_channel if session.is_host else session.opp_channel
	var b: String = session.opp_channel if session.is_host else session.my_channel
	duel.set_channels(a, b)
	_refresh_duel_active()
	if Twitch.enabled and session.opp_channel != "":
		Twitch.join_extra(session.opp_channel)
	_update_duel_text()
	if active:
		# REVANCHE: both agreed, a new match on the same connection
		_token += 1
		ui.show_result("REVANCHE", "Neue Level, neuer Seed. Gleich geht's los.", "none", false)
		if session.is_host:
			_schedule_next_round(REMATCH_START_S)
		return
	var who := "Du hostest – starte das Match, wenn ihr bereit seid." if session.is_host else "Warte, bis der Host das Match startet."
	ui.set_lobby_state("Gegner: %s.  %s" % [session.opp_name, who], true, session.is_host)


## The duel only runs while this game reads both chats on a live connection
## (QA N10): Twitch on and connected, both channel names valid.
func _refresh_duel_active() -> void:
	duel.active = Twitch.enabled and Twitch.is_connected_to_chat() and duel.channels[0] != "" and duel.channels[1] != ""


func on_twitch_changed() -> void:
	_refresh_duel_active()
	_update_duel_text()


func _update_duel_text() -> void:
	var text := ""
	if not Twitch.enabled:
		text = "Chat-Duell aus: Twitch-Chat einschalten (beide Spieler)."
	elif session.state != SessionScript.State.READY:
		text = "Twitch an (#%s). Das Chat-Duell läuft, wenn auch der Gegner seinen Chat verbindet." % Twitch.channel
	elif duel.active:
		text = "Chat-Duell an: #%s gegen #%s.  !gut hilft dem eigenen Spieler, !schlecht bremst den Gegner – und kostet den eigenen etwas." % [duel.channels[0], duel.channels[1]]
	elif session.opp_channel == "":
		text = "Chat-Duell aus: %s hat keinen Twitch-Chat verbunden." % session.opp_name
	else:
		text = "Chat-Duell aus: dein Twitch-Chat ist nicht verbunden."
	ui.set_duel_text(text)


func leave() -> void:
	var was_active := active
	active = false
	arena_mode = false
	arena.set_active(false)
	_token += 1
	_next_round_at = -1.0
	_paused = false
	session.close()
	duel.clear()
	duel.active = false
	Twitch.leave_extras()
	hud.minimap_opponent_cell = Vector2i(-1, -1)
	hud.minimap_opponent_yaw = NAN
	ui.race_mode_tag = ""
	hud.set_condition_card_top(CARD_TOP_SOLO)
	if _saved_week_override.x >= 0:
		main.rabbit_week_override = _saved_week_override
		_saved_week_override = Vector2i(-1, -1)
	ui.hide_all()
	if was_active or main.running:
		main.go_to_main_menu()
	else:
		hud.show_only(hud.start_panel)


## ---- rounds ------------------------------------------------------------------

func _schedule_next_round(delay: float) -> void:
	_next_round_at = main.real_now + delay


func _on_round_started(round: int, go_in: float) -> void:
	if not active:
		_token += 1
	active = true
	_paused = false
	_next_round_at = -1.0
	ui.hide_result()
	hud.hide_all_panels()
	go_at_real = main.real_now + go_in
	_my_frac = 0.0
	_opp_frac = 0.0
	_opp_lives = 3
	hud.minimap_opponent_cell = Vector2i(-1, -1)
	hud.set_condition_card_top(CARD_TOP_VERSUS)
	ui.set_race_status("")
	if _saved_week_override.x < 0:
		_saved_week_override = main.rabbit_week_override
	if session.host_week.x > 0:
		main.rabbit_week_override = session.host_week
	# Same ghost randomness on both sides (design N2): the frightened ghosts'
	# turns follow the match, not this machine (seeded before the level).
	main.ai_rng.seed = hash("zapmaniac-ai|%d|%d" % [session.match_seed, round])
	arena_mode = session.mode == SessionScript.MODE_ARENA
	ui.race_mode_tag = "ARENA" if arena_mode else ""
	hud.minimap_opponent_yaw = NAN
	main.begin_game(session.current_level_id())
	hud.set_level(round + 1) # the LEVEL chip shows the round (QA N4)
	ui.set_race_visible(true)
	_refresh_race()


## Main._begin_start_hold in a Versus round: no intro, the world waits for
## the common GO.
func begin_hold() -> void:
	main.start_hold = true
	main.player.movement_locked = true
	main.level_start_real = main.real_now
	hud.show_start_intro(false)
	hud.show_clock_hint(false)
	_last_count = -1
	_show_countdown()


## Main._update_start_hold in a Versus round: count down, release at GO for
## both players at once (the clock starts with it).
func update_hold() -> void:
	main.level_start_real = main.real_now
	hud.show_clock_hint(false)
	if main.real_now < go_at_real:
		_show_countdown()
		return
	main.start_hold = false
	main.hold_release_position = main.player.global_position
	main.player.movement_locked = false
	ui.show_countdown("LOS!")
	Sfx.level_clear()
	var token := _token
	var round: int = session.round_index
	get_tree().create_timer(0.7).timeout.connect(func():
		if token == _token and round == session.round_index and ui.countdown_label.text == "LOS!":
			ui.show_countdown(""))


func _show_countdown() -> void:
	if _paused:
		ui.show_countdown("")
		return
	var left := maxi(ceili(go_at_real - main.real_now), 1)
	ui.show_countdown(str(left))
	if left != _last_count:
		_last_count = left
		Sfx.condition_tick()


## Pause (Main.toggle_pause): the digit must never cover the menu (QA W4).
func on_paused(on: bool) -> void:
	_paused = on
	if on:
		ui.show_countdown("")


## Every frame while a match is active (Main._process).
func tick() -> void:
	if not active:
		return
	if _next_round_at >= 0.0:
		var left: float = _next_round_at - main.real_now
		if left <= 0.0:
			_next_round_at = -1.0
			if session.is_host and session.state == SessionScript.State.READY:
				session.start_next_round()
		else:
			ui.set_result_next(_intermission_text(left))
	if not main.running or main.start_hold:
		return
	var total: int = main.maze_view.total_pickups()
	_my_frac = 1.0 - float(main.maze_view.remaining_pickups()) / float(maxi(total, 1))
	var elapsed: float = main.real_now - main.level_start_real
	var gscale: float = main.active_condition.ghost_speed_scale() if main.active_condition != null else 1.0
	session.send_progress(_my_frac, main.player.cell(), main.lives, false, gscale)
	if arena_mode:
		arena.send_my_position()
		arena.send_ghost_state()
		hud.minimap_opponent_cell = arena.opponent_cell()
		hud.minimap_opponent_yaw = arena.opponent_yaw()
	if session.tick_round(elapsed):
		# my clock passed the opponent's time: this round is over for me
		main.stop_run_for_versus()
		ui.set_race_status("")
		ui.show_result("ZU LANGSAM", "%s war schneller." % session.opp_name, "loss")
		return
	if session.opp_cs >= 0:
		var left_s: float = float(session.opp_cs) / 100.0 - elapsed
		ui.set_race_status("%s IM ZIEL %s  ·  NOCH %s" % [session.opp_name.to_upper(), _fmt_cs(session.opp_cs), _fmt_s(maxf(left_s, 0.0))], left_s < 5.0)
	_refresh_race()


func _intermission_text(left: float) -> String:
	var nxt: String = session.next_level_id()
	var lv: Dictionary = LevelsScript.by_id(nxt) if nxt != "" else {}
	var lname: String = lv.get("name", "")
	var line := "Runde %d: %s in %d s" % [session.round_index + 2, lname, ceili(left)]
	if duel.active:
		line += "  ·  Chats, stimmt jetzt ab!"
	return line


func _on_opponent_progress(frac: float, cell: Vector2i, lives: int) -> void:
	if lives < _opp_lives and lives > 0:
		ui.show_event("%s −1 LEBEN" % session.opp_name.to_upper(), ui.OPP_COLOR, 1.5)
	_opp_frac = frac
	_opp_lives = lives
	if cell.x >= 0 and not arena_mode:
		hud.minimap_opponent_cell = cell
	_refresh_race()


func _on_opponent_finished(cs: int) -> void:
	ui.show_event("%s IM ZIEL · %s" % [session.opp_name.to_upper(), _fmt_cs(cs)], ui.OPP_COLOR, 2.5)
	_opp_frac = 1.0
	Sfx.fruit()


func _on_opponent_out() -> void:
	_opp_lives = 0
	ui.show_event("%s HAT KEINE LEBEN MEHR" % session.opp_name.to_upper(), ui.OPP_COLOR, 2.5)


## The opponent's rabbit (UX W2, design K2): the moment the chats voted for.
func _on_opponent_rabbit(cond: String, good: bool, _p: float) -> void:
	if arena_mode:
		main.maze_view.arena_remove_rabbit() # one rabbit for both: he took it
	var c = ConditionsScript.get_condition(cond)
	var cname: String = c.display_name.to_upper() if c != null else cond.to_upper()
	var text := "%s: %s · %s" % [session.opp_name.to_upper(), cname, "gut" if good else "schlecht"]
	var side: int = session.my_side()
	# my own chat's sabotage share (.y) is what targets the opponent
	if not good and duel.active and duel.shares(side, main.real_now).y > 0.0:
		text += "  ·  Sabotage von #%s wirkt!" % duel.channels[side]
	ui.show_event(text, hud.COND_GOOD if good else hud.COND_BAD, 3.5)


func _refresh_race() -> void:
	var mp := ""
	if session.score_me == SessionScript.ROUNDS_TO_WIN - 1 and session.score_opp < SessionScript.ROUNDS_TO_WIN - 1:
		mp = session.my_name
	elif session.score_opp == SessionScript.ROUNDS_TO_WIN - 1 and session.score_me < SessionScript.ROUNDS_TO_WIN - 1:
		mp = session.opp_name
	ui.set_race(session.my_name, _my_frac, main.lives, session.opp_name, _opp_frac, _opp_lives,
		session.round_index + 1, session.score_me, session.score_opp, mp)
	var side: int = session.my_side()
	ui.set_duel(duel.active, session.my_name, duel.p_good(side, main.real_now), session.opp_name, duel.p_good(1 - side, main.real_now))


## Main._on_rabbit_picked in a Versus round: the share comes from the chat
## duel, the draw from the match's round generator (the same for both
## players, so their first number u is the same — E17a).
func rabbit_draw() -> Dictionary:
	_refresh_duel_active()
	var side: int = session.my_side()
	var p: float = duel.p_good(side, main.real_now)
	var shifted: bool = duel.shifted(side, main.real_now)
	return {"rng": ChatDuelScript.round_rng(session.match_seed, session.round_index), "p": p, "shifted": shifted}


func rabbit_picked(cond_id: String, good: bool, p: float) -> void:
	var side: int = session.my_side()
	session.send_rabbit(cond_id, good, p, duel.counts(side, main.real_now), duel.counts(1 - side, main.real_now))


## The title card's chat line in a Versus round: "Duell 42 % → STROMAUSFALL ·
## Sabotage von #bob" — who tipped it (UX W2).
func chat_line(p: float, c) -> String:
	if not duel.active:
		return ""
	var side: int = session.my_side()
	var why: String = duel.influence(side, main.real_now)
	var who := ""
	if why == "hilfe":
		who = "Hilfe von #%s" % duel.channels[side]
	elif why == "sabotage":
		who = "Sabotage von #%s" % duel.channels[1 - side]
	elif why == "beides":
		who = "Hilfe #%s · Sabotage #%s" % [duel.channels[side], duel.channels[1 - side]]
	var line := "Duell %d %% → %s" % [roundi(p * 100.0), c.display_name.to_upper()]
	return line + ("  ·  " + who if who != "" else "")


## The chat chip on the left is not used in Versus: the race bar shows both
## shares (UX W1).
func update_chat_hud() -> void:
	hud.set_chat_share_visible(false)


## Main.level_complete_sequence in a Versus round, after the time was stored.
func on_level_cleared(elapsed: float) -> void:
	_my_frac = 1.0
	_refresh_race()
	main.player.input_enabled = false
	ui.set_race_status("")
	var sub := "Zeit %s – %s muss schneller sein." % [Speedrun.format_time(elapsed), session.opp_name]
	ui.show_result("IM ZIEL", sub, "none")
	session.report_finish(elapsed)


## Main.end_game in a Versus round (last life lost).
func on_out_of_lives() -> void:
	ui.set_race_status("")
	ui.show_result("KEINE LEBEN MEHR", "Warte auf %s …" % session.opp_name, "loss")
	session.report_died(_my_frac, main.real_now - main.level_start_real)


func _on_round_decided(round: int, outcome: String, cause: String) -> void:
	if main.running:
		main.stop_run_for_versus()
	ui.show_countdown("")
	ui.set_race_status("")
	ui.set_race_visible(true)
	_refresh_race()
	var h: Dictionary = session.history[session.history.size() - 1] if not session.history.is_empty() else {}
	var title := ""
	match outcome:
		"win":
			title = "RUNDE %d GEWONNEN" % (round + 1)
			Sfx.eat_enemy()
		"loss":
			title = "RUNDE %d VERLOREN" % (round + 1)
			Sfx.death()
		_:
			title = "RUNDE %d · KEIN PUNKT" % (round + 1)
	var sub := "%s  ·  Stand %d:%d" % [_round_line(h, cause), session.score_me, session.score_opp]
	var next_line := ""
	if not session.match_finished:
		next_line = _intermission_text(INTERMISSION_S)
		# the host starts the next round; the client only shows the countdown
		_schedule_next_round(INTERMISSION_S)
	ui.show_result(title, sub, outcome, false, "", next_line)


## "Alice 1:02.31 · Bob 1:05.80 (+3.49 s)" or why it ended.
func _round_line(h: Dictionary, cause: String) -> String:
	var me: String = session.my_name
	var opp: String = session.opp_name
	var mc: int = h.get("my_cs", -1)
	var oc: int = h.get("opp_cs", -1)
	match cause:
		"time":
			if mc >= 0 and oc >= 0:
				var diff := absf(float(mc - oc)) / 100.0
				return "%s %s · %s %s (%s%.2f s)" % [me, _fmt_cs(mc), opp, _fmt_cs(oc), "+" if mc > oc else "−", diff]
			if mc >= 0:
				return "%s im Ziel in %s" % [me, _fmt_cs(mc)]
			return "%s war in %s im Ziel" % [opp, _fmt_cs(oc)]
		"tie":
			return "%s %s · %s %s · Gleichstand: Punkt an den Host" % [me, _fmt_cs(mc), opp, _fmt_cs(oc)]
		"lives":
			return "Keine Leben mehr" if h.get("outcome", "") == "loss" else "%s ohne Leben" % opp
		"progress":
			return "Beide ohne Leben – wer weiter kam, gewinnt"
		"conceded":
			return "%s war schneller" % opp
		_:
			return "Beide ohne Leben, gleich weit – kein Punkt"


func _on_match_over(i_won: bool, score_me: int, score_opp: int) -> void:
	_next_round_at = -1.0
	var draw := score_me == score_opp
	var title := "SIEG" if i_won else ("UNENTSCHIEDEN" if draw else "NIEDERLAGE")
	var kind := "win" if i_won else ("none" if draw else "loss")
	var sub := "%s  %d : %d  %s" % [session.my_name, score_me, score_opp, session.opp_name]
	var token := _token
	get_tree().create_timer(2.5).timeout.connect(func():
		if token != _token or not active:
			return
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		ui.show_result(title, sub, kind, true, _match_table())
		var gone: bool = session.state != SessionScript.State.READY
		ui.set_rematch_state(not gone, "REVANCHE")
		if gone:
			ui.set_result_next("%s hat das Match verlassen." % session.opp_name)
		elif session.rematch_asked_by_opponent():
			ui.set_result_next("%s will eine Revanche." % session.opp_name)
		if i_won:
			Sfx.level_clear()
		else:
			Sfx.rabbit_bad())


## One line per round: "R1 Klassik I · 1:02.31 vs 1:05.80 · gewonnen · Kaninchen: Taschenuhr".
func _match_table() -> String:
	var lines: Array = []
	for i in session.history.size():
		var h: Dictionary = session.history[i]
		var lv: Dictionary = LevelsScript.by_id(String(h.level))
		var res: String = {"win": "gewonnen", "loss": "verloren"}.get(h.outcome, "kein Punkt")
		var t := "%s vs %s" % [_fmt_cs(h.my_cs) if h.my_cs >= 0 else "–", _fmt_cs(h.opp_cs) if h.opp_cs >= 0 else "–"]
		var cond := ""
		if String(h.my_cond) != "":
			var c = ConditionsScript.get_condition(String(h.my_cond))
			if c != null:
				cond = "  ·  Kaninchen: %s" % c.display_name
		lines.append("R%d %s  ·  %s  ·  %s%s" % [i + 1, lv.get("name", h.level), t, res, cond])
	return "\n".join(lines)


func _on_rematch_pressed() -> void:
	session.request_rematch()
	ui.set_rematch_state(false, "WARTE AUF GEGNER …")
	if session.rematch_asked_by_opponent():
		ui.set_result_next("Revanche angenommen …")


func _on_rematch_requested() -> void:
	if ui.result.visible:
		ui.set_result_next("%s will eine Revanche." % session.opp_name)


func _on_opponent_left(during_match: bool) -> void:
	_next_round_at = -1.0
	if not active:
		if ui.lobby.visible:
			ui.set_lobby_state("Gegner hat die Verbindung getrennt." + (" Warte auf einen neuen …" if session.is_host else ""), false, false)
		return
	if not during_match:
		# The match was already over (QA W1): the result stays, REVANCHE goes.
		ui.set_rematch_state(false, "REVANCHE")
		ui.set_result_next("%s hat das Match verlassen." % session.opp_name)
		return
	if main.running:
		main.stop_run_for_versus()
	ui.show_countdown("")
	ui.set_race_status("")
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	ui.show_result("SIEG KAMPFLOS", "%s hat das Match verlassen." % session.opp_name, "win", true)
	ui.set_rematch_state(false, "REVANCHE")


## Votes of either chat (Twitch.channel_command): only the duel counts them.
func _on_channel_command(channel: String, user: String, command: String, _args: String) -> void:
	if session.state == SessionScript.State.READY:
		duel.on_command(channel, user, command, main.real_now)


static func _fmt_cs(cs: int) -> String:
	var m := cs / 6000
	var rest := cs - m * 6000
	return "%d:%02d.%02d" % [m, rest / 100, rest % 100]


static func _fmt_s(s: float) -> String:
	return "%d:%04.1f" % [int(s / 60.0), fmod(s, 60.0)]
