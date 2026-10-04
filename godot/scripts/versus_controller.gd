extends Node
## VersusController — glue between Main, the network session and the Versus
## screens (E17, docs/design/multiplayer.md). A Versus round is an ordinary
## speedrun level run by Main in this game's own copy of the maze; this node
## adds what differs:
##   - the lobby (host / join / start) and the opponent's Twitch chat
##   - a synchronized 3-2-1 start instead of the intro and "first step" hold
##   - the rabbit from the chat duel and the match's shared round generator
##   - progress to the opponent, the race bar and the opponent on the minimap
##   - finish / out of lives -> round result, best of three, match result
## Main asks `active` at its hook points and otherwise stays single-player.

const SessionScript := preload("res://scripts/versus_session.gd")
const ChatDuelScript := preload("res://scripts/chat_duel.gd")
const ConditionsScript := preload("res://scripts/conditions.gd")
const WhiteRabbitScript := preload("res://scripts/white_rabbit.gd")
const NEXT_ROUND_DELAY_S := 4.0

var main: Node
var hud
var ui
var session: Node
var duel = ChatDuelScript.new()
## true from the first round start until the match is left.
var active := false
var go_at_real := 0.0
var _opp_frac := 0.0
var _my_frac := 0.0
## Main.rabbit_week_override before the match (restored when leaving).
var _saved_week_override := Vector2i(-1, -1)


func setup(main_node: Node) -> void:
	main = main_node
	hud = main.hud
	ui = hud.versus_ui
	session = SessionScript.new()
	add_child(session)
	session.state_changed.connect(_on_state_changed)
	session.match_ready.connect(_on_match_ready)
	session.round_started.connect(_on_round_started)
	session.opponent_progress.connect(_on_opponent_progress)
	session.round_decided.connect(_on_round_decided)
	session.match_over.connect(_on_match_over)
	session.opponent_left.connect(_on_opponent_left)
	hud.versus_pressed.connect(open_lobby)
	ui.host_requested.connect(_on_host_requested)
	ui.join_requested.connect(_on_join_requested)
	ui.start_requested.connect(func(): session.start_next_round())
	ui.leave_requested.connect(leave)
	ui.result_menu_requested.connect(leave)
	Twitch.channel_command.connect(_on_channel_command)


## ---- lobby -------------------------------------------------------------------

func open_lobby() -> void:
	ui.show_lobby()
	ui.set_lobby_state("Hoste ein Match oder tritt per IP-Adresse bei.", false, false)
	_update_duel_text()


func _prepare_session(player_name: String) -> void:
	session.my_name = player_name
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


func _on_match_ready() -> void:
	var a: String = session.my_channel if session.is_host else session.opp_channel
	var b: String = session.opp_channel if session.is_host else session.my_channel
	duel.set_channels(a, b)
	duel.active = Twitch.enabled and a != "" and b != ""
	if Twitch.enabled and session.opp_channel != "":
		Twitch.join_extra(session.opp_channel)
	_update_duel_text()
	var who := "Du hostest – starte das Match, wenn ihr bereit seid." if session.is_host else "Warte, bis der Host das Match startet."
	ui.set_lobby_state("Gegner: %s.  %s" % [session.opp_name, who], true, session.is_host)


func _update_duel_text() -> void:
	var text := ""
	if not Twitch.enabled:
		text = "Chat-Duell aus: Twitch-Chat am Startscreen einschalten (beide Spieler)."
	elif session.state != SessionScript.State.READY:
		text = "Twitch-Chat verbunden (#%s). Das Chat-Duell läuft, wenn auch der Gegner seinen Chat verbindet." % Twitch.channel
	elif duel.active:
		text = "Chat-Duell an: #%s gegen #%s." % [duel.channels[0], duel.channels[1]]
	else:
		text = "Chat-Duell aus: %s hat keinen Twitch-Chat verbunden." % session.opp_name
	ui.set_duel_text(text)


func leave() -> void:
	var was_active := active
	active = false
	session.close()
	duel.clear()
	duel.active = false
	Twitch.leave_extras()
	hud.minimap_opponent_cell = Vector2i(-1, -1)
	if _saved_week_override.x >= 0:
		main.rabbit_week_override = _saved_week_override
		_saved_week_override = Vector2i(-1, -1)
	ui.hide_all()
	if was_active or main.running:
		main.go_to_main_menu()
	else:
		hud.show_only(hud.start_panel)


## ---- rounds ------------------------------------------------------------------

func _on_round_started(round: int, go_in: float) -> void:
	active = true
	ui.hide_result()
	hud.hide_all_panels()
	go_at_real = main.real_now + go_in
	_my_frac = 0.0
	_opp_frac = 0.0
	hud.minimap_opponent_cell = Vector2i(-1, -1)
	if _saved_week_override.x < 0:
		_saved_week_override = main.rabbit_week_override
	main.rabbit_week_override = session.host_week
	main.begin_game(session.current_level_id())
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
	_show_countdown()


## Main._update_start_hold in a Versus round: count down, release at GO for
## both players at once (the clock starts with it).
func update_hold() -> void:
	main.level_start_real = main.real_now
	if main.real_now < go_at_real:
		_show_countdown()
		return
	main.start_hold = false
	main.hold_release_position = main.player.global_position
	main.player.movement_locked = false
	ui.show_countdown("LOS!")
	get_tree().create_timer(0.7).timeout.connect(func():
		if ui.countdown_label.text == "LOS!":
			ui.show_countdown(""))


func _show_countdown() -> void:
	var left := ceili(go_at_real - main.real_now)
	ui.show_countdown(str(maxi(left, 1)))


## Every frame of a running round (Main._process).
func tick() -> void:
	if not active or not main.running or main.start_hold:
		return
	var total: int = main.maze_view.total_pickups()
	_my_frac = 1.0 - float(main.maze_view.remaining_pickups()) / float(maxi(total, 1))
	session.send_progress(_my_frac, main.player.cell(), main.lives)
	session.tick_round(main.real_now - main.level_start_real)
	_refresh_race()


func _on_opponent_progress(frac: float, cell: Vector2i, _lives: int) -> void:
	_opp_frac = frac
	hud.minimap_opponent_cell = cell
	_refresh_race()


func _refresh_race() -> void:
	ui.set_race(session.my_name, _my_frac, session.opp_name, _opp_frac,
		session.round_index + 1, SessionScript.MATCH_LEVELS, session.score_me, session.score_opp)


## Main._on_rabbit_picked in a Versus round: the share comes from the chat
## duel, the draw from the match's round generator (the same for both
## players, so their first number u is the same — E17a).
## Returns {rng, p, shifted, chat_line_fmt}.
func rabbit_draw() -> Dictionary:
	var side: int = session.my_side()
	var p: float = duel.p_good(side, main.real_now)
	var shifted: bool = duel.shifted(side, main.real_now)
	return {"rng": ChatDuelScript.round_rng(session.match_seed, session.round_index), "p": p, "shifted": shifted}


func rabbit_picked(cond_id: String, p: float) -> void:
	var side: int = session.my_side()
	session.send_rabbit(cond_id, p, duel.counts(side, main.real_now), duel.counts(1 - side, main.real_now))


## The chat duel's chip text: "Dein Kaninchen: 35 % gut".
func update_chat_hud() -> void:
	var show_it: bool = active and duel.active and main.running
	hud.set_chat_share_visible(show_it)
	if show_it:
		var side: int = session.my_side()
		var p: float = duel.p_good(side, main.real_now)
		hud.set_chat_share(p, duel.votes[side].voters(main.real_now), 0, duel.shifted(side, main.real_now), "Duell 60 %")


## Main.level_complete_sequence in a Versus round, after the time was stored.
func on_level_cleared(elapsed: float) -> void:
	_my_frac = 1.0
	_refresh_race()
	main.player.input_enabled = false
	ui.show_result("IM ZIEL", "Zeit %s – warte auf %s …" % [Speedrun.format_time(elapsed), session.opp_name], true)
	session.report_finish(elapsed)


## Main.end_game in a Versus round (last life lost).
func on_out_of_lives() -> void:
	ui.show_result("KEINE LEBEN MEHR", "Die Runde geht an %s." % session.opp_name, false)
	session.report_died()


func _on_round_decided(round: int, i_won: bool, reason: String) -> void:
	# The round is over for this player too (lost while still running).
	if main.running:
		main.running = false
		main._end_condition(false)
		main.player.input_enabled = false
		Sfx.stop_all()
	ui.set_race_visible(true)
	_refresh_race()
	var title := "RUNDE %d GEWONNEN" % (round + 1) if i_won else "RUNDE %d VERLOREN" % (round + 1)
	var sub := "%s  ·  Stand %d:%d" % [reason, session.score_me, session.score_opp]
	ui.show_result(title, sub, i_won)
	if session.is_host and not session.match_finished:
		get_tree().create_timer(NEXT_ROUND_DELAY_S).timeout.connect(func():
			if active and not session.match_finished:
				session.start_next_round())


func _on_match_over(i_won: bool, score_me: int, score_opp: int) -> void:
	var title := "SIEG" if i_won else ("UNENTSCHIEDEN" if score_me == score_opp else "NIEDERLAGE")
	var sub := "%s  %d : %d  %s" % [session.my_name, score_me, score_opp, session.opp_name]
	# show after the round banner had a moment
	get_tree().create_timer(2.0).timeout.connect(func():
		if active:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
			ui.show_result(title, sub, i_won or score_me == score_opp, true))


func _on_opponent_left() -> void:
	if not active:
		if ui.lobby.visible:
			ui.set_lobby_state("Gegner hat die Verbindung getrennt.", false, false)
		return
	if main.running:
		main.running = false
		main._end_condition(false)
		main.player.input_enabled = false
		Sfx.stop_all()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	ui.show_result("SIEG KAMPFLOS", "%s hat das Match verlassen." % session.opp_name, true, true)


## Votes of either chat (Twitch.channel_command): only the duel counts them.
func _on_channel_command(channel: String, user: String, command: String, _args: String) -> void:
	if session.state == SessionScript.State.READY:
		duel.on_command(channel, user, command, main.real_now)

