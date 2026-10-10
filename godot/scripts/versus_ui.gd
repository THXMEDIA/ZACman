extends Node
## VersusUI — the screens of a Versus race (E17): the lobby (name, host or
## join, Twitch, connection help), the race bar during a round (both players'
## progress, lives, the chat duel, events like "BOB IM ZIEL"), the 3-2-1
## countdown and the round / match result with REVANCHE.
##
## Lives under the HUD and builds its panels with the HUD's own helpers, so it
## looks like every other screen. Sizes are made for a 1080p stream that is
## watched transcoded on phones (UX review W7): names 20 px, bars 18 px.
## No IP address is ever shown in clear text without a click (UX review K1).

signal host_requested(player_name: String, port: int)
signal join_requested(player_name: String, address: String, port: int)
signal start_requested
signal leave_requested
signal rematch_requested
## The host picked the mode: "arena" or "race".
signal mode_changed(mode: String)
signal result_menu_requested

const DEFAULT_PORT := 47823
## The opponent's color: an orange the game uses nowhere else, clear of the
## player's cyan, the good green, the bad magenta and the ghosts (UX N7, QA N2).
const OPP_COLOR := Color("ff9f1c")
const NEUTRAL := Color(1.0, 0.82, 0.4)
const NAME_PX := 20
const SMALL_PX := 16

var hud
var lobby: PanelContainer
var name_edit: LineEdit
var address_edit: LineEdit
var address_show: Button
var port_edit: LineEdit
var my_ip_label: Label
var my_ip_show: Button
var my_ip_copy: Button
var host_btn: Button
var join_btn: Button
var start_btn: Button
var mode_btn: Button
var _mode := "arena"
var status_label: Label
var duel_label: Label
var lobby_twitch: CheckBox
var lobby_channel: LineEdit
var help_btn: Button
var help_label: Label
var _my_ips: Array = []
var _ip_shown := false

var race_bar: PanelContainer
var race_round_label: Label
var race_rows: Array = [] # [{tag, name, bar, pct, lives}] me, opponent
var race_duel_label: Label
var race_duel_help: Label
var race_status_label: Label
var race_event_label: Label
var _event_until := 0.0
var _clock := 0.0

var countdown: CenterContainer
var countdown_label: Label

var result: CenterContainer
var result_title: Label
var result_sub: Label
var result_table: Label
var result_next: Label
var result_btn_row: HBoxContainer
var result_rematch_btn: Button
var result_menu_btn: Button


func setup(hud_node) -> void:
	hud = hud_node
	_build_lobby()
	_build_race_bar()
	_build_countdown()
	_build_result()


func _process(delta: float) -> void:
	_clock += delta
	if race_event_label != null and race_event_label.visible and _clock >= _event_until:
		race_event_label.visible = false


## ---- lobby -------------------------------------------------------------------

func _build_lobby() -> void:
	lobby = hud._overlay_panel(true)
	lobby.visible = false
	var box: VBoxContainer = hud._panel_box(lobby)
	box.add_theme_constant_override("separation", 9)
	box.add_child(hud._title_label("VERSUS · GEGENWIND"))
	box.add_child(hud._subtitle_label("Zu zweit, gleiche 3 Level, Best of 3. Arena: wer zuerst alle eigenen Kugeln hat. Spiegelrennen: schnellere Zeit."))
	name_edit = _labeled_edit(box, "DEIN NAME", "", 200)
	name_edit.placeholder_text = "Spieler"

	# Twitch right here (UX W5): the chat duel needs both chats.
	var tw_row := HBoxContainer.new()
	tw_row.alignment = BoxContainer.ALIGNMENT_CENTER
	tw_row.add_theme_constant_override("separation", 8)
	box.add_child(tw_row)
	lobby_twitch = CheckBox.new()
	lobby_twitch.text = "Twitch-Chat"
	tw_row.add_child(lobby_twitch)
	lobby_channel = LineEdit.new()
	lobby_channel.placeholder_text = "twitch-kanal"
	lobby_channel.custom_minimum_size = Vector2(150, 0)
	tw_row.add_child(lobby_channel)
	lobby_twitch.toggled.connect(func(pressed: bool):
		hud.twitch_channel_edit.text = lobby_channel.text
		hud.twitch_toggle.set_pressed_no_signal(pressed)
		hud.twitch_toggled.emit(pressed, lobby_channel.text))
	duel_label = hud._subtitle_label("")
	box.add_child(duel_label)

	box.add_child(_section("DU HOSTEST"))
	var ip_row := HBoxContainer.new()
	ip_row.alignment = BoxContainer.ALIGNMENT_CENTER
	ip_row.add_theme_constant_override("separation", 8)
	box.add_child(ip_row)
	my_ip_label = Label.new()
	my_ip_label.add_theme_color_override("font_color", hud.MUTED)
	ip_row.add_child(my_ip_label)
	my_ip_show = Button.new()
	my_ip_show.text = "ZEIGEN"
	my_ip_show.pressed.connect(func():
		_ip_shown = not _ip_shown
		_refresh_my_ip())
	ip_row.add_child(my_ip_show)
	my_ip_copy = Button.new()
	my_ip_copy.text = "KOPIEREN"
	my_ip_copy.pressed.connect(func():
		if not _my_ips.is_empty():
			DisplayServer.clipboard_set(String(_my_ips[0]))
			set_lobby_state("IP kopiert – nur privat teilen (z. B. per DM).", false, false, true))
	ip_row.add_child(my_ip_copy)
	var host_row := HBoxContainer.new()
	host_row.alignment = BoxContainer.ALIGNMENT_CENTER
	host_row.add_theme_constant_override("separation", 8)
	box.add_child(host_row)
	var port_tag := Label.new()
	port_tag.text = "PORT"
	port_tag.add_theme_color_override("font_color", hud.MUTED)
	host_row.add_child(port_tag)
	port_edit = LineEdit.new()
	port_edit.text = str(DEFAULT_PORT)
	port_edit.custom_minimum_size = Vector2(90, 0)
	host_row.add_child(port_edit)
	host_btn = hud._make_button("HOSTEN")
	host_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host_btn.pressed.connect(func(): host_requested.emit(_name(), _port()))
	host_row.add_child(host_btn)

	var or_label: Label = hud._subtitle_label("— oder —")
	box.add_child(or_label)
	box.add_child(_section("DU TRITTST BEI"))
	var join_row := HBoxContainer.new()
	join_row.alignment = BoxContainer.ALIGNMENT_CENTER
	join_row.add_theme_constant_override("separation", 8)
	box.add_child(join_row)
	address_edit = LineEdit.new()
	address_edit.placeholder_text = "IP des Hosts"
	address_edit.secret = true
	address_edit.custom_minimum_size = Vector2(190, 0)
	address_edit.text_submitted.connect(func(_t): _emit_join())
	join_row.add_child(address_edit)
	address_show = Button.new()
	address_show.text = "ZEIGEN"
	address_show.pressed.connect(func():
		address_edit.secret = not address_edit.secret
		address_show.text = "VERBERGEN" if not address_edit.secret else "ZEIGEN")
	join_row.add_child(address_show)
	join_btn = hud._make_button("BEITRETEN")
	join_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join_btn.pressed.connect(_emit_join)
	join_row.add_child(join_btn)
	var stream_hint: Label = hud._subtitle_label("Streamst du? IP-Adressen nur privat teilen (z. B. per DM), nie im Chat oder im Bild.")
	box.add_child(stream_hint)

	status_label = hud._subtitle_label("Hoste ein Match oder tritt per IP-Adresse bei.")
	status_label.add_theme_color_override("font_color", hud.RABBIT_WHITE)
	box.add_child(status_label)

	mode_btn = hud._make_button("")
	mode_btn.pressed.connect(func():
		set_mode("race" if _mode == "arena" else "arena")
		mode_changed.emit(_mode))
	box.add_child(mode_btn)
	set_mode(_mode)
	start_btn = hud._make_button("MATCH STARTEN")
	start_btn.disabled = true
	start_btn.pressed.connect(func(): start_requested.emit())
	box.add_child(start_btn)

	help_btn = Button.new()
	help_btn.text = "VERBINDUNG KLAPPT NICHT?"
	help_btn.flat = true
	box.add_child(help_btn)
	help_label = hud._subtitle_label("Der Host muss erreichbar sein:\n1. Die Firewall-Abfrage beim Hosten zulassen.\n2. Im Router den UDP-Port (Standard 47823) an diesen PC weiterleiten.\n3. Klappt das nicht (z. B. DS-Lite, Glasfaser): ein virtuelles LAN wie Tailscale oder ZeroTier nutzen und dessen IP eingeben.\nIm selben Netz: die lokale IP (192.168. …) des Hosts verwenden.")
	help_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	help_label.visible = false
	box.add_child(help_label)
	help_btn.pressed.connect(func(): help_label.visible = not help_label.visible)
	var back: Button = hud._make_button("ZURÜCK")
	back.pressed.connect(func(): leave_requested.emit())
	box.add_child(back)


func _section(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_color", hud.ACCENT)
	l.add_theme_font_size_override("font_size", 15)
	return l


func _labeled_edit(parent: Control, tag: String, text: String, w: float) -> LineEdit:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	var l := Label.new()
	l.text = tag
	l.add_theme_color_override("font_color", hud.MUTED)
	row.add_child(l)
	var e := LineEdit.new()
	e.text = text
	e.max_length = 20
	e.custom_minimum_size = Vector2(w, 0)
	row.add_child(e)
	return e


func _emit_join() -> void:
	join_requested.emit(_name(), address_edit.text.strip_edges(), _port())


func _name() -> String:
	var n := name_edit.text.strip_edges()
	return n if n != "" else "Spieler"


func _port() -> int:
	var p := port_edit.text.strip_edges().to_int()
	return p if p > 1024 and p < 65536 else DEFAULT_PORT


## Opens the lobby; `default_name` (the Twitch channel) fills an empty name.
func show_lobby(default_name: String, twitch_on: bool, channel: String) -> void:
	if name_edit.text.strip_edges() == "" and default_name != "":
		name_edit.text = default_name
	lobby_twitch.set_pressed_no_signal(twitch_on)
	lobby_channel.text = channel
	_my_ips = _local_ipv4()
	_ip_shown = false
	_refresh_my_ip()
	hud.show_only(lobby)


func _refresh_my_ip() -> void:
	if _my_ips.is_empty():
		my_ip_label.text = "Deine IP: unbekannt"
		my_ip_show.visible = false
		my_ip_copy.visible = false
		return
	my_ip_show.visible = true
	my_ip_copy.visible = true
	my_ip_show.text = "VERBERGEN" if _ip_shown else "ZEIGEN"
	my_ip_label.text = "Deine IP (LAN): %s" % (String(_my_ips[0]) if _ip_shown else "•••.•••.•••.•••")


## The local IPv4 addresses (LAN), private ranges first. The public address
## is not knowable offline; behind a router the host forwards the port.
static func _local_ipv4() -> Array:
	var out: Array = []
	for a in IP.get_local_addresses():
		var s := String(a)
		if s.count(".") == 3 and not s.begins_with("127.") and not s.begins_with("169.254."):
			out.append(s)
	out.sort_custom(func(x, y): return int(x.begins_with("192.168.")) > int(y.begins_with("192.168.")))
	return out


## `connected`: an opponent is there (HOSTEN/BEITRETEN locked); `can_start`:
## this side may press START (the host, once both are ready).
func set_lobby_state(text: String, connected: bool, can_start: bool, keep_buttons: bool = false) -> void:
	status_label.text = text
	if keep_buttons:
		return
	host_btn.disabled = connected
	join_btn.disabled = connected
	start_btn.disabled = not can_start
	start_btn.text = "MATCH STARTEN" if can_start or not connected else "WARTE AUF HOST …"


## The mode button (host only): ARENA = both in one maze, own pellets, shared
## ghosts; SPIEGELRENNEN = everyone in an own copy (Gegenwind).
func set_mode(mode: String) -> void:
	_mode = mode
	if mode_btn != null:
		mode_btn.text = "MODUS: ARENA · ein Labyrinth, eigene Kugeln" if mode == "arena" else "MODUS: SPIEGELRENNEN · jeder im eigenen Labyrinth"


func set_mode_editable(on: bool) -> void:
	if mode_btn != null:
		mode_btn.disabled = not on


func set_duel_text(text: String) -> void:
	duel_label.text = text


## ---- race bar ----------------------------------------------------------------

func _build_race_bar() -> void:
	race_bar = PanelContainer.new()
	race_bar.add_theme_stylebox_override("panel", hud._panel_style())
	race_bar.anchor_left = 0.5
	race_bar.anchor_right = 0.5
	race_bar.offset_left = -290
	race_bar.offset_right = 290
	race_bar.offset_top = 8
	race_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	race_bar.visible = false
	hud.add_child(race_bar)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 5)
	race_bar.add_child(col)
	race_round_label = _label(SMALL_PX, hud.MUTED)
	race_round_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(race_round_label)
	race_rows.append(_race_row(col, hud.ACCENT, true))
	race_rows.append(_race_row(col, OPP_COLOR, false))
	race_duel_label = _label(SMALL_PX, hud.RABBIT_WHITE)
	race_duel_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	race_duel_label.visible = false
	col.add_child(race_duel_label)
	race_duel_help = _label(14, hud.MUTED)
	race_duel_help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	race_duel_help.visible = false
	col.add_child(race_duel_help)
	race_status_label = _label(18, OPP_COLOR)
	race_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	race_status_label.visible = false
	col.add_child(race_status_label)
	race_event_label = _label(18, hud.RABBIT_WHITE)
	race_event_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	race_event_label.visible = false
	col.add_child(race_event_label)


func _label(px: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", color)
	return l


func _race_row(parent: Control, color: Color, is_me: bool) -> Dictionary:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	var tag := _label(13, hud.MUTED)
	tag.text = "DU" if is_me else ""
	tag.custom_minimum_size = Vector2(24, 0)
	row.add_child(tag)
	var nm := _label(NAME_PX, color)
	nm.custom_minimum_size = Vector2(150, 0)
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nm.clip_text = true
	row.add_child(nm)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(220, 18)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.max_value = 1.0
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(3)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(1, 1, 1, 0.12)
	bg.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("fill", fill)
	bar.add_theme_stylebox_override("background", bg)
	row.add_child(bar)
	var pct := _label(NAME_PX, color)
	pct.custom_minimum_size = Vector2(62, 0)
	pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(pct)
	var lives := _label(16, hud.PELLET_COLOR)
	lives.custom_minimum_size = Vector2(40, 0)
	row.add_child(lives)
	return {"tag": tag, "name": nm, "bar": bar, "pct": pct, "lives": lives}


func set_race_visible(on: bool) -> void:
	race_bar.visible = on


func set_race(me_name: String, me_frac: float, me_lives: int, opp_name: String, opp_frac: float, opp_lives: int, round_no: int, score_me: int, score_opp: int, match_point: String = "") -> void:
	var text := "BEST OF 3  ·  RUNDE %d  ·  %d:%d" % [round_no, score_me, score_opp]
	if match_point != "":
		text += "  ·  MATCHBALL %s" % match_point.to_upper()
	_set_text(race_round_label, text)
	_fill_row(race_rows[0], me_name, me_frac, me_lives)
	_fill_row(race_rows[1], opp_name, opp_frac, opp_lives)


func _fill_row(row: Dictionary, n: String, frac: float, lives: int) -> void:
	_set_text(row.name, n.to_upper())
	_set_text(row.pct, "%d %%" % roundi(frac * 100.0))
	row.bar.value = frac
	_set_text(row.lives, "■".repeat(clampi(lives, 0, 9)))


## The chat duel line (UX W1): both shares, and what this stream's chat can do.
func set_duel(visible_now: bool, me_name: String, p_me: float, opp_name: String, p_opp: float) -> void:
	race_duel_label.visible = visible_now
	race_duel_help.visible = visible_now
	if not visible_now:
		return
	_set_text(race_duel_label, "KANINCHEN   %s %d %% gut  ·  %s %d %% gut" % [me_name.to_upper(), roundi(p_me * 100.0), opp_name.to_upper(), roundi(p_opp * 100.0)])
	_set_text(race_duel_help, "Chat: !gut = Hilfe für %s  ·  !schlecht = Sabotage gegen %s" % [me_name, opp_name])


## A lasting status under the bars ("BOB IM ZIEL 1:02.31 · NOCH 0:07.4"); "" hides it.
func set_race_status(text: String, urgent: bool = false) -> void:
	race_status_label.visible = text != ""
	_set_text(race_status_label, text)
	race_status_label.add_theme_color_override("font_color", hud.DANGER if urgent else OPP_COLOR)


## A short event line in the race bar ("BOB: STROMAUSFALL · schlecht").
func show_event(text: String, color: Color, seconds: float = 3.0) -> void:
	race_event_label.text = text
	race_event_label.add_theme_color_override("font_color", color)
	race_event_label.visible = true
	_event_until = _clock + seconds


func _set_text(l: Label, t: String) -> void:
	if l.text != t:
		l.text = t


## ---- countdown -----------------------------------------------------------------

func _build_countdown() -> void:
	countdown = hud._centered_overlay()
	countdown.visible = false
	countdown_label = Label.new()
	countdown_label.add_theme_font_size_override("font_size", 96)
	countdown_label.add_theme_color_override("font_color", hud.PELLET_COLOR)
	countdown_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	countdown_label.add_theme_constant_override("outline_size", 12)
	countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	countdown.add_child(countdown_label)


func show_countdown(text: String) -> void:
	countdown.visible = text != ""
	if countdown_label.text != text:
		countdown_label.text = text


## ---- result ------------------------------------------------------------------

func _build_result() -> void:
	result = hud._centered_overlay()
	result.visible = false
	var panel := PanelContainer.new()
	var sb: StyleBoxFlat = hud._panel_style()
	sb.set_content_margin_all(24)
	sb.bg_color = Color(0.02, 0.03, 0.05, 0.94)
	panel.add_theme_stylebox_override("panel", sb)
	result.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(col)
	result_title = hud._title_label("", 40)
	col.add_child(result_title)
	result_sub = hud._subtitle_label("", 18)
	result_sub.add_theme_color_override("font_color", hud.RABBIT_WHITE)
	result_sub.custom_minimum_size = Vector2(460, 0)
	col.add_child(result_sub)
	result_table = Label.new()
	result_table.add_theme_font_size_override("font_size", 16)
	result_table.add_theme_color_override("font_color", hud.MUTED)
	result_table.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_table.visible = false
	col.add_child(result_table)
	result_next = hud._subtitle_label("", 16)
	result_next.add_theme_color_override("font_color", hud.PELLET_COLOR)
	col.add_child(result_next)
	result_btn_row = HBoxContainer.new()
	result_btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	result_btn_row.add_theme_constant_override("separation", 12)
	result_btn_row.visible = false
	col.add_child(result_btn_row)
	result_rematch_btn = hud._make_button("REVANCHE")
	result_rematch_btn.custom_minimum_size = Vector2(180, 46)
	result_rematch_btn.pressed.connect(func(): rematch_requested.emit())
	result_btn_row.add_child(result_rematch_btn)
	result_menu_btn = hud._make_button("HAUPTMENÜ")
	result_menu_btn.custom_minimum_size = Vector2(180, 46)
	result_menu_btn.pressed.connect(func(): result_menu_requested.emit())
	result_btn_row.add_child(result_menu_btn)


## `kind`: "win", "loss" or "none" (green, red, neutral — UX W8). `final`:
## the match is over — buttons, the round table, and the panel takes input.
func show_result(title: String, sub: String, kind: String, final: bool = false, table: String = "", next_line: String = "") -> void:
	result.visible = true
	result_title.text = title
	result_title.add_theme_font_size_override("font_size", 52 if final else 40)
	var c: Color = NEUTRAL
	if kind == "win":
		c = hud.COND_GOOD
	elif kind == "loss":
		c = hud.DANGER
	result_title.add_theme_color_override("font_color", c)
	result_sub.text = sub
	result_table.text = table
	result_table.visible = table != ""
	result_next.text = next_line
	result_next.visible = next_line != ""
	result_btn_row.visible = final
	result.mouse_filter = Control.MOUSE_FILTER_STOP if final else Control.MOUSE_FILTER_IGNORE


func set_result_next(text: String) -> void:
	result_next.text = text
	result_next.visible = text != ""


func set_rematch_state(enabled: bool, text: String) -> void:
	result_rematch_btn.disabled = not enabled
	result_rematch_btn.text = text


func hide_result() -> void:
	result.visible = false
	result_btn_row.visible = false


func hide_all() -> void:
	lobby.visible = false
	race_bar.visible = false
	countdown.visible = false
	race_event_label.visible = false
	race_status_label.visible = false
	hide_result()
