extends Node
## VersusUI — the screens of a Versus race (E17): the lobby (name, host or
## join, start), the race bar during a round (both players' progress, round
## and score), the 3-2-1 countdown and the round / match result.
##
## Lives under the HUD and builds its panels with the HUD's own helpers, so it
## looks like every other screen. All texts German like the rest of the game.

signal host_requested(player_name: String, port: int)
signal join_requested(player_name: String, address: String, port: int)
signal start_requested
signal leave_requested
signal result_menu_requested

const DEFAULT_PORT := 47823

var hud
var lobby: PanelContainer
var name_edit: LineEdit
var address_edit: LineEdit
var port_edit: LineEdit
var host_btn: Button
var join_btn: Button
var start_btn: Button
var status_label: Label
var duel_label: Label

var race_bar: PanelContainer
var race_me_label: Label
var race_opp_label: Label
var race_round_label: Label
var race_me_bar: ProgressBar
var race_opp_bar: ProgressBar

var countdown: CenterContainer
var countdown_label: Label

var result: CenterContainer
var result_title: Label
var result_sub: Label
var result_menu_btn: Button


func setup(hud_node) -> void:
	hud = hud_node
	_build_lobby()
	_build_race_bar()
	_build_countdown()
	_build_result()


## ---- lobby -------------------------------------------------------------------

func _build_lobby() -> void:
	lobby = hud._overlay_panel()
	lobby.visible = false
	var box: VBoxContainer = hud._panel_box(lobby)
	box.add_theme_constant_override("separation", 10)
	box.add_child(hud._title_label("VERSUS · GEGENWIND"))
	box.add_child(hud._subtitle_label("Zwei Spieler, gleiche drei Level, jeder in seinem eigenen Labyrinth. Schnellere Zeit gewinnt die Runde, zwei Runden das Match. Mit Twitch-Chat auf beiden Seiten: !gut hilft deinem Spieler, !schlecht schadet dem Gegner."))

	name_edit = _labeled_edit(box, "NAME", "Spieler", 180)
	var host_row := HBoxContainer.new()
	host_row.alignment = BoxContainer.ALIGNMENT_CENTER
	host_row.add_theme_constant_override("separation", 8)
	box.add_child(host_row)
	port_edit = LineEdit.new()
	port_edit.text = str(DEFAULT_PORT)
	port_edit.custom_minimum_size = Vector2(90, 0)
	port_edit.tooltip_text = "Port (UDP)"
	host_btn = hud._make_button("HOSTEN")
	host_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host_btn.pressed.connect(func(): host_requested.emit(_name(), _port()))
	host_row.add_child(host_btn)
	host_row.add_child(port_edit)

	var join_row := HBoxContainer.new()
	join_row.alignment = BoxContainer.ALIGNMENT_CENTER
	join_row.add_theme_constant_override("separation", 8)
	box.add_child(join_row)
	address_edit = LineEdit.new()
	address_edit.placeholder_text = "IP-Adresse des Hosts"
	address_edit.custom_minimum_size = Vector2(200, 0)
	join_btn = hud._make_button("BEITRETEN")
	join_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join_btn.pressed.connect(func(): join_requested.emit(_name(), address_edit.text.strip_edges(), _port()))
	join_row.add_child(join_btn)
	join_row.add_child(address_edit)

	status_label = hud._subtitle_label("Hoste ein Match oder tritt per IP-Adresse bei.")
	box.add_child(status_label)
	duel_label = hud._subtitle_label("")
	box.add_child(duel_label)

	start_btn = hud._make_button("MATCH STARTEN")
	start_btn.disabled = true
	start_btn.pressed.connect(func(): start_requested.emit())
	box.add_child(start_btn)
	var back: Button = hud._make_button("ZURÜCK")
	back.pressed.connect(func(): leave_requested.emit())
	box.add_child(back)


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


func _name() -> String:
	var n := name_edit.text.strip_edges()
	return n if n != "" else "Spieler"


func _port() -> int:
	var p := port_edit.text.strip_edges().to_int()
	return p if p > 1024 and p < 65536 else DEFAULT_PORT


func show_lobby() -> void:
	hud.show_only(lobby)


## `connected`: an opponent is there; `can_start`: this side may press START
## (the host, once both are ready).
func set_lobby_state(text: String, connected: bool, can_start: bool) -> void:
	status_label.text = text
	host_btn.disabled = connected
	join_btn.disabled = connected
	start_btn.disabled = not can_start
	start_btn.text = "MATCH STARTEN" if can_start or not connected else "WARTE AUF HOST …"


func set_duel_text(text: String) -> void:
	duel_label.text = text


## ---- race bar ----------------------------------------------------------------

func _build_race_bar() -> void:
	race_bar = PanelContainer.new()
	race_bar.add_theme_stylebox_override("panel", hud._panel_style())
	race_bar.anchor_left = 0.5
	race_bar.anchor_right = 0.5
	race_bar.offset_left = -230
	race_bar.offset_right = 230
	race_bar.offset_top = 64
	race_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	race_bar.visible = false
	hud.add_child(race_bar)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	race_bar.add_child(col)
	race_round_label = Label.new()
	race_round_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	race_round_label.add_theme_color_override("font_color", hud.MUTED)
	race_round_label.add_theme_font_size_override("font_size", 14)
	col.add_child(race_round_label)
	var me := _race_row(col, hud.ACCENT)
	race_me_label = me[0]
	race_me_bar = me[1]
	var opp := _race_row(col, hud.POWER_COLOR)
	race_opp_label = opp[0]
	race_opp_bar = opp[1]


func _race_row(parent: Control, color: Color) -> Array:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	var l := Label.new()
	l.custom_minimum_size = Vector2(170, 0)
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", 15)
	l.clip_text = true
	row.add_child(l)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(240, 12)
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
	return [l, bar]


func set_race_visible(on: bool) -> void:
	race_bar.visible = on


func set_race(me_name: String, me_frac: float, opp_name: String, opp_frac: float, round_no: int, rounds: int, score_me: int, score_opp: int) -> void:
	race_round_label.text = "RUNDE %d/%d  ·  STAND %d:%d" % [round_no, rounds, score_me, score_opp]
	race_me_label.text = "%s  %d %%" % [me_name.to_upper(), roundi(me_frac * 100.0)]
	race_opp_label.text = "%s  %d %%" % [opp_name.to_upper(), roundi(opp_frac * 100.0)]
	race_me_bar.value = me_frac
	race_opp_bar.value = opp_frac


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
	sb.set_content_margin_all(22)
	sb.bg_color = Color(0.02, 0.03, 0.05, 0.94)
	panel.add_theme_stylebox_override("panel", sb)
	result.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(col)
	result_title = hud._title_label("", 30)
	col.add_child(result_title)
	result_sub = hud._subtitle_label("")
	result_sub.add_theme_color_override("font_color", hud.PELLET_COLOR)
	col.add_child(result_sub)
	result_menu_btn = hud._make_button("HAUPTMENÜ")
	result_menu_btn.visible = false
	result_menu_btn.pressed.connect(func(): result_menu_requested.emit())
	col.add_child(result_menu_btn)


## `final`: the match is over — the result stays with a HAUPTMENÜ button and
## takes mouse input; otherwise it is a passing banner between rounds.
func show_result(title: String, sub: String, won: bool, final: bool = false) -> void:
	result.visible = true
	result_title.text = title
	result_title.add_theme_color_override("font_color", hud.COND_GOOD if won else hud.DANGER)
	result_sub.text = sub
	result_menu_btn.visible = final
	result.mouse_filter = Control.MOUSE_FILTER_STOP if final else Control.MOUSE_FILTER_IGNORE


func hide_result() -> void:
	result.visible = false
	result_menu_btn.visible = false


func hide_all() -> void:
	lobby.visible = false
	race_bar.visible = false
	countdown.visible = false
	hide_result()
