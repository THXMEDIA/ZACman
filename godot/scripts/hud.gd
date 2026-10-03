extends CanvasLayer
## Hud — score/level/lives, minimap, power-timer bar, and the start / pause /
## game-over / level-clear overlays. Built entirely in code (no .tscn UI tree
## to keep in sync by hand).

signal start_pressed
signal resume_pressed
signal restart_pressed
signal manhattan_pressed
signal reduce_fx_toggled(on: bool)
signal chaos_toggled(on: bool)
signal twitch_toggled(is_enabled: bool, channel: String)

const BG := Color(0.035, 0.055, 0.11, 0.86)
const BORDER := Color(0.31, 0.66, 1.0, 0.35)
const ACCENT := Color(0.2, 0.878, 1.0)
const PELLET_COLOR := Color(1.0, 0.82, 0.4)
const POWER_COLOR := Color(1.0, 0.365, 0.635)
const DANGER := Color(1.0, 0.231, 0.365)
## Condition title card (spec 2.2): good = green, bad = magenta.
const COND_GOOD := Color("3ce37a")
const COND_BAD := Color("ff3cc8")
const RABBIT_WHITE := Color("f2f2ed")
## Board badge colors (spec 2.5): the weekly board neutral, Chaos amber,
## Chat violet (Twitch-ish) — none of them the good/bad condition colors.
const BOARD_COLORS := {"woche": Color(1.0, 0.82, 0.4), "chaos": Color("ffa41f"), "chat": Color("b78cff")}
const MUTED := Color(0.56, 0.64, 0.78)
const LevelsScript := preload("res://scripts/levels.gd")
const WhiteRabbitScript := preload("res://scripts/white_rabbit.gd")

var score_label: Label
var level_label: Label
var lives_box: HBoxContainer
var timer_label: Label
var best_label: Label
var power_bar: ProgressBar
var power_wrap: Control
var minimap: Control

var start_panel: PanelContainer
var pause_panel: PanelContainer
var gameover_panel: PanelContainer
var levelclear_panel: Control
var levelclear_label: Label
var levelclear_sub: Label

var pause_note_label: Label
## Board chip (BRETT): "KW 40" on the weekly board, "CHAOS", "CHAT".
var board_label: Label
var board_chip: Control
## Chat mode (Twitch on): the rabbit's current good share (spec 2.6).
var chat_chip: PanelContainer
var chat_share_label: Label
var chat_share_bar: Control
var chat_share := 0.6
var chat_share_voters := 0
var chaos_start: CheckBox
## Bestenliste (start screen): board tabs, level switcher, top entries.
var leaderboard_panel: PanelContainer
var lb_board := "woche"
var lb_level_index := 0
var lb_title_label: Label
var lb_level_label: Label
var lb_info_label: Label
var lb_rows: GridContainer
var lb_tabs := {}
## The ISO week the HUD treats as "this week" (Main sets it; tests force it).
var current_week := Vector2i(0, 0)
var reduce_fx_start: CheckBox
var reduce_fx_pause: CheckBox
## Condition title card (top, under the power bar) and the start intro.
var condition_card: PanelContainer
var condition_icon: Control
var condition_name_label: Label
var condition_sub_label: Label
## "Chat 72 % → MATRIX" when the chat shifted the rabbit (spec 2.6).
var condition_chat_label: Label
var condition_bar: ProgressBar
var condition_fill: StyleBoxFlat
var condition_icon_kind := ""
var condition_color := COND_GOOD
var start_intro: CenterContainer
var start_intro_panel: PanelContainer
## Chips that only make sense in a timed, scored level (hidden in Manhattan).
var timed_chips: Array = []

var final_score_label: Label
var final_level_label: Label
var final_hs_label: Label
var start_hs_label: Label
var manhattan_btn: Button
var manhattan_bonus_label: Label
var debug_label: Label
var twitch_toggle: CheckBox
var twitch_channel_edit: LineEdit
var twitch_status_label: Label

var minimap_maze = null
var minimap_maze_view = null # MazeView — read for pellet_cells/pellet_alive/power_cells/power_alive
var minimap_player: Node3D = null
var minimap_enemies: Array = []
var minimap_frightened := false


func _ready() -> void:
	_build_hud_bar()
	_build_power_timer()
	_build_start_panel()
	_build_pause_panel()
	_build_gameover_panel()
	_build_leaderboard_panel()
	_build_levelclear_label()
	_build_condition_card()
	_build_start_intro()


func _panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = BG
	sb.border_color = BORDER
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(12)
	return sb


func _build_hud_bar() -> void:
	var top := Control.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 16
	top.offset_right = -16
	top.offset_top = 14
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top)

	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 6)
	top.add_child(left)

	score_label = _make_chip(left, "PUNKTE", "0")
	level_label = _make_chip(left, "LEVEL", "1")
	timer_label = _make_chip(left, "ZEIT", "0:00.00")
	best_label = _make_chip(left, "BESTZEIT", "--:--")
	board_label = _make_chip(left, "BRETT", "")
	board_chip = board_label.get_parent().get_parent()
	board_chip.visible = false
	timed_chips = [score_label.get_parent().get_parent(), timer_label.get_parent().get_parent(), best_label.get_parent().get_parent()]
	_build_chat_chip(left)

	# Debug overlay (FPS / player position / cell) — hidden unless
	# set_debug_overlay(true) is called (F3 in debug builds, see main.gd).
	debug_label = _make_chip(left, "DEBUG", "--")
	debug_label.get_parent().get_parent().visible = false

	var lives_chip := PanelContainer.new()
	lives_chip.add_theme_stylebox_override("panel", _panel_style())
	left.add_child(lives_chip)
	timed_chips.append(lives_chip)
	lives_box = HBoxContainer.new()
	lives_box.add_theme_constant_override("separation", 6)
	lives_chip.add_child(lives_box)
	var lives_tag := Label.new()
	lives_tag.text = "LEBEN "
	lives_tag.add_theme_color_override("font_color", Color(0.56, 0.64, 0.78))
	lives_tag.add_theme_font_size_override("font_size", 12)
	lives_box.add_child(lives_tag)

	minimap = Control.new()
	minimap.custom_minimum_size = Vector2(150, 150)
	minimap.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	minimap.offset_left = -166
	minimap.offset_top = 0
	minimap.offset_right = -16
	minimap.offset_bottom = 150
	minimap.draw.connect(_draw_minimap)
	top.add_child(minimap)


func _make_chip(parent: Control, label_text: String, value_text: String) -> Label:
	var chip := PanelContainer.new()
	chip.add_theme_stylebox_override("panel", _panel_style())
	parent.add_child(chip)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	chip.add_child(row)
	var tag := Label.new()
	tag.text = label_text
	tag.add_theme_color_override("font_color", Color(0.56, 0.64, 0.78))
	tag.add_theme_font_size_override("font_size", 12)
	row.add_child(tag)
	var value := Label.new()
	value.text = value_text
	value.add_theme_color_override("font_color", PELLET_COLOR)
	value.add_theme_font_size_override("font_size", 16)
	row.add_child(value)
	return value


func _build_power_timer() -> void:
	power_wrap = Control.new()
	power_wrap.custom_minimum_size = Vector2(160, 34)
	power_wrap.set_anchors_preset(Control.PRESET_CENTER_TOP)
	power_wrap.offset_left = -80
	power_wrap.offset_right = 80
	power_wrap.offset_top = 14
	power_wrap.offset_bottom = 48
	power_wrap.visible = false
	add_child(power_wrap)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style())
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	power_wrap.add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	panel.add_child(row)
	var tag := Label.new()
	tag.text = "ENERGIE"
	tag.add_theme_color_override("font_color", POWER_COLOR)
	tag.add_theme_font_size_override("font_size", 11)
	row.add_child(tag)
	power_bar = ProgressBar.new()
	power_bar.custom_minimum_size = Vector2(70, 6)
	power_bar.show_percentage = false
	power_bar.max_value = 1.0
	power_bar.value = 1.0
	var fg := StyleBoxFlat.new()
	fg.bg_color = POWER_COLOR
	fg.set_corner_radius_all(3)
	var bgs := StyleBoxFlat.new()
	bgs.bg_color = Color(1.0, 0.365, 0.635, 0.2)
	bgs.set_corner_radius_all(3)
	power_bar.add_theme_stylebox_override("fill", fg)
	power_bar.add_theme_stylebox_override("background", bgs)
	row.add_child(power_bar)


## Manhattan has no clock, score, lives or best time: hide those chips.
func set_explorer_hud(is_explorer: bool) -> void:
	for chip in timed_chips:
		chip.visible = not is_explorer
	if is_explorer:
		set_board_badge("")
		set_chat_share_visible(false)


## Board badge under the best time (spec 2.5): on the weekly board the week
## of its rabbits ("KW 40"), otherwise "CHAOS" or "CHAT" in their own color.
## "" hides it (Manhattan).
func set_board_badge(board: String, week_text: String = "") -> void:
	board_chip.visible = board != ""
	if board == "":
		board_label.text = ""
		return
	board_label.text = ("WOCHE · %s" % week_text) if board == LevelsScript.BOARD_WEEK else board.to_upper()
	board_label.add_theme_color_override("font_color", BOARD_COLORS.get(board, PELLET_COLOR))


## Chat mode chip (spec 2.6): "Kaninchen: 72 % gut" with a small green /
## magenta bar; under 3 different voters the base share applies, the chip
## then says how many voted.
func _build_chat_chip(parent: Control) -> void:
	chat_chip = PanelContainer.new()
	chat_chip.add_theme_stylebox_override("panel", _panel_style())
	chat_chip.visible = false
	parent.add_child(chat_chip)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	chat_chip.add_child(col)
	chat_share_label = Label.new()
	chat_share_label.add_theme_font_size_override("font_size", 13)
	chat_share_label.add_theme_color_override("font_color", RABBIT_WHITE)
	col.add_child(chat_share_label)
	chat_share_bar = Control.new()
	chat_share_bar.custom_minimum_size = Vector2(150, 6)
	chat_share_bar.draw.connect(func():
		var w := chat_share_bar.size.x * clampf(chat_share, 0.0, 1.0)
		chat_share_bar.draw_rect(Rect2(0, 0, w, chat_share_bar.size.y), COND_GOOD)
		chat_share_bar.draw_rect(Rect2(w, 0, chat_share_bar.size.x - w, chat_share_bar.size.y), COND_BAD))
	col.add_child(chat_share_bar)


func set_chat_share_visible(on: bool) -> void:
	chat_chip.visible = on


## `share` 0..1 (good), `voters` = different voters in the 60-s window.
func set_chat_share(share: float, voters: int, min_voters: int) -> void:
	chat_share = share
	chat_share_voters = voters
	var text := "Kaninchen: %d %% gut" % roundi(share * 100.0)
	if voters < min_voters:
		text += "  (Chat: %d/%d Stimmen)" % [voters, min_voters]
	chat_share_label.text = text
	chat_share_bar.queue_redraw()


## Shows/hides the DEBUG chip in the top HUD bar (F3 in debug builds).
func set_debug_overlay(visible_now: bool) -> void:
	debug_label.get_parent().get_parent().visible = visible_now


## Updates the DEBUG chip's text — FPS, player world position, and the
## player's current maze cell — called every frame while the overlay is on
## (see main.gd::_process).
func update_debug_overlay(fps: float, pos: Vector3, cell: Vector2i) -> void:
	debug_label.text = "%d fps  ·  (%.1f, %.1f, %.1f)  ·  cell (%d, %d)" % [int(fps), pos.x, pos.y, pos.z, cell.x, cell.y]


func set_power_timer(remaining: float, duration: float) -> void:
	if remaining > 0.0:
		power_wrap.visible = true
		power_bar.value = clampf(remaining / duration, 0.0, 1.0)
	else:
		power_wrap.visible = false


func _title_label(text: String, size := 22) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", ACCENT)
	l.add_theme_font_size_override("font_size", size)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


func _subtitle_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", Color(0.56, 0.64, 0.78))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	l.custom_minimum_size = Vector2(360, 0)
	return l


func _make_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 46)
	return b


func _build_start_panel() -> void:
	start_panel = _overlay_panel(true)
	var box := _panel_box(start_panel)
	box.add_child(_title_label("KUGELSCHLUCKER"))
	box.add_child(_subtitle_label("Lauf durchs Labyrinth, schlucke jede Kugel, weich den Wesen aus."))

	var hs_row := HBoxContainer.new()
	hs_row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(hs_row)
	var hs_tag := Label.new()
	hs_tag.text = "BESTPUNKTZAHL  "
	hs_tag.add_theme_color_override("font_color", Color(0.56, 0.64, 0.78))
	hs_row.add_child(hs_tag)
	start_hs_label = Label.new()
	start_hs_label.text = "0"
	start_hs_label.add_theme_color_override("font_color", PELLET_COLOR)
	hs_row.add_child(start_hs_label)

	var controls := _subtitle_label("WASD laufen   ·   Maus umschauen   ·   Esc Pause")
	box.add_child(controls)

	var twitch_row := HBoxContainer.new()
	twitch_row.alignment = BoxContainer.ALIGNMENT_CENTER
	twitch_row.add_theme_constant_override("separation", 8)
	box.add_child(twitch_row)
	twitch_toggle = CheckBox.new()
	twitch_toggle.text = "Twitch-Chat (!power, !fruit, !gut, !schlecht)"
	twitch_row.add_child(twitch_toggle)
	twitch_channel_edit = LineEdit.new()
	twitch_channel_edit.placeholder_text = "twitch-kanal"
	twitch_channel_edit.custom_minimum_size = Vector2(130, 0)
	twitch_row.add_child(twitch_channel_edit)
	twitch_toggle.toggled.connect(func(pressed: bool): twitch_toggled.emit(pressed, twitch_channel_edit.text))

	twitch_status_label = _subtitle_label("Aus — für ernsthafte Speedruns ausgeschaltet lassen.")
	twitch_status_label.add_theme_font_size_override("font_size", 11)
	box.add_child(twitch_status_label)

	var mode_tag := _subtitle_label("WÄHLE DEINEN MODUS")
	mode_tag.add_theme_font_size_override("font_size", 11)
	box.add_child(mode_tag)

	var btn := _make_button("SPEEDRUN")
	btn.pressed.connect(func(): start_pressed.emit())
	box.add_child(btn)
	var speedrun_sub := _subtitle_label("Zufälliges Level, Geister, Zeitjagd. In jedem Level sitzt ein weißes Kaninchen: freiwillig, mit einer Kondition der Woche – gut oder schlecht. Bestzeiten pro Level und Brett (Woche, Chaos, Chat).")
	speedrun_sub.add_theme_font_size_override("font_size", 11)
	box.add_child(speedrun_sub)
	chaos_start = CheckBox.new()
	chaos_start.text = "Chaos-Modus: echter Zufall beim Kaninchen (eigenes Brett)"
	chaos_start.toggled.connect(func(pressed: bool): chaos_toggled.emit(pressed))
	box.add_child(chaos_start)
	var lb_btn := _make_button("BESTENLISTE")
	lb_btn.pressed.connect(func(): show_leaderboard())
	box.add_child(lb_btn)

	# Always available as its own choice, right from the start screen —
	# not gated behind the speedrun bonus-unlock anymore (that still
	# exists, see manhattan_bonus_label below, just as a nice badge now
	# rather than a lock on the button).
	manhattan_btn = _make_button("EXPLORER-LEVEL")
	manhattan_btn.pressed.connect(func(): manhattan_pressed.emit())
	box.add_child(manhattan_btn)
	var explorer_sub := _subtitle_label("Ruhige Stadt ohne Uhr und Punkte. Die Kugeln zeigen den Weg zur U-Bahn (SUBWAY); sie ist der Ausgang in einen Speedrun.")
	explorer_sub.add_theme_font_size_override("font_size", 11)
	box.add_child(explorer_sub)
	manhattan_bonus_label = _subtitle_label("★ Zielzeit in einem Level geschafft")
	manhattan_bonus_label.add_theme_font_size_override("font_size", 11)
	manhattan_bonus_label.add_theme_color_override("font_color", PELLET_COLOR)
	manhattan_bonus_label.visible = false
	box.add_child(manhattan_bonus_label)

	reduce_fx_start = _make_reduce_fx_toggle()
	box.add_child(reduce_fx_start)


## "Effekte reduzieren" (spec 1.2) — no settings menu yet, so the same switch
## sits on the start screen and in the pause menu; both stay in sync.
func _make_reduce_fx_toggle() -> CheckBox:
	var cb := CheckBox.new()
	cb.text = "Effekte reduzieren (ruhigere Konditions-Looks)"
	cb.toggled.connect(func(pressed: bool): reduce_fx_toggled.emit(pressed))
	return cb


func set_chaos_mode(on: bool) -> void:
	if chaos_start != null:
		chaos_start.set_pressed_no_signal(on)


func set_reduce_fx(on: bool) -> void:
	for cb in [reduce_fx_start, reduce_fx_pause]:
		if cb != null:
			cb.set_pressed_no_signal(on)


func _build_pause_panel() -> void:
	pause_panel = _overlay_panel()
	pause_panel.visible = false
	var box := pause_panel.get_child(0)
	box.add_child(_title_label("PAUSE"))
	pause_note_label = _subtitle_label("Das Labyrinth wartet. Die Speedrun-Zeit läuft weiter.")
	box.add_child(pause_note_label)
	var resume_btn := _make_button("WEITER")
	resume_btn.pressed.connect(func(): resume_pressed.emit())
	box.add_child(resume_btn)
	var restart_btn := _make_button("NEUSTART")
	restart_btn.pressed.connect(func(): restart_pressed.emit())
	box.add_child(restart_btn)
	reduce_fx_pause = _make_reduce_fx_toggle()
	box.add_child(reduce_fx_pause)


## ---------------- Bestenliste (spec 2.5) ----------------

## Start screen -> BESTENLISTE: one board (Woche / Chaos / Chat) of one level
## at a time, top 10 fastest first. On the weekly board every time names its
## calendar week, the header names the all-time best with its week and the
## best of the current week. Old condition boards (archive) are never shown.
func _build_leaderboard_panel() -> void:
	leaderboard_panel = _overlay_panel()
	leaderboard_panel.visible = false
	var box: VBoxContainer = leaderboard_panel.get_child(0)
	box.add_theme_constant_override("separation", 10)
	lb_title_label = _title_label("BESTENLISTE")
	box.add_child(lb_title_label)
	var tabs := HBoxContainer.new()
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	tabs.add_theme_constant_override("separation", 6)
	box.add_child(tabs)
	for b in LevelsScript.BOARDS:
		var t := Button.new()
		t.text = LevelsScript.BOARD_LABELS[b].to_upper()
		t.toggle_mode = true
		t.custom_minimum_size = Vector2(96, 32)
		t.pressed.connect(func(): _set_lb_board(b))
		tabs.add_child(t)
		lb_tabs[b] = t
	var lvl_row := HBoxContainer.new()
	lvl_row.alignment = BoxContainer.ALIGNMENT_CENTER
	lvl_row.add_theme_constant_override("separation", 10)
	box.add_child(lvl_row)
	var prev := Button.new()
	prev.text = "<"
	prev.custom_minimum_size = Vector2(36, 30)
	prev.pressed.connect(func(): _step_lb_level(-1))
	lvl_row.add_child(prev)
	lb_level_label = Label.new()
	lb_level_label.custom_minimum_size = Vector2(170, 0)
	lb_level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lb_level_label.add_theme_font_size_override("font_size", 18)
	lb_level_label.add_theme_color_override("font_color", PELLET_COLOR)
	lvl_row.add_child(lb_level_label)
	var nxt := Button.new()
	nxt.text = ">"
	nxt.custom_minimum_size = Vector2(36, 30)
	nxt.pressed.connect(func(): _step_lb_level(1))
	lvl_row.add_child(nxt)
	lb_info_label = _subtitle_label("")
	lb_info_label.add_theme_font_size_override("font_size", 13)
	box.add_child(lb_info_label)
	var rows_center := CenterContainer.new()
	box.add_child(rows_center)
	lb_rows = GridContainer.new()
	lb_rows.add_theme_constant_override("h_separation", 18)
	lb_rows.add_theme_constant_override("v_separation", 2)
	rows_center.add_child(lb_rows)
	var back := _make_button("ZURÜCK")
	back.pressed.connect(func(): show_only(start_panel))
	box.add_child(back)


func show_leaderboard(board: String = "", level_id: String = "") -> void:
	if board != "":
		lb_board = board
	if level_id != "":
		lb_level_index = maxi(LevelsScript.index_of(level_id), 0)
	refresh_leaderboard()
	show_only(leaderboard_panel)


func _set_lb_board(board: String) -> void:
	lb_board = board
	refresh_leaderboard()


func _step_lb_level(d: int) -> void:
	lb_level_index = posmod(lb_level_index + d, LevelsScript.POOL.size())
	refresh_leaderboard()


## The rows of the current board/level, top 10: [rank, time, (week,) name]
## — the week column only on the weekly board.
func leaderboard_rows() -> Array:
	var lv: Dictionary = LevelsScript.POOL[lb_level_index]
	var out := []
	var top: Array = Leaderboard.get_top(lv.id, lb_board, 10)
	for i in top.size():
		var e: Dictionary = top[i]
		var row := ["%d." % (i + 1), Speedrun.format_time(e.time)]
		if lb_board == LevelsScript.BOARD_WEEK:
			row.append(WhiteRabbitScript.week_display(e.get("week", ""), _week_now()))
		row.append(e.name)
		out.append(row)
	return out


## The same rows as text lines ("1.  1:23.45  KW 40  Player"), for tests.
func leaderboard_lines() -> Array:
	var out := []
	for row in leaderboard_rows():
		out.append("  ".join(PackedStringArray(row)))
	return out


func _week_now() -> Vector2i:
	return current_week if current_week.x > 0 else WhiteRabbitScript.current_iso_week()


func refresh_leaderboard() -> void:
	if leaderboard_panel == null:
		return
	var lv: Dictionary = LevelsScript.POOL[lb_level_index]
	for b in lb_tabs:
		lb_tabs[b].set_pressed_no_signal(b == lb_board)
	lb_level_label.text = lv.name
	var info := ""
	match lb_board:
		LevelsScript.BOARD_WEEK:
			var best: Dictionary = Speedrun.best_entry(lv.id, lb_board)
			if best.is_empty():
				info = "Kaninchen der Woche · noch keine Zeit"
			else:
				info = "Allzeit-Bestzeit %s · %s" % [Speedrun.format_time(best.time), WhiteRabbitScript.week_display(best.get("week", ""), _week_now())]
			var this_week := WhiteRabbitScript.week_label(_week_now())
			var week_best := -1.0
			for e in Leaderboard.get_top(lv.id, lb_board):
				if e.get("week", "") == this_week:
					week_best = e.time
					break
			info += "\nDiese Woche (%s): %s" % [WhiteRabbitScript.week_display(this_week, _week_now()), Speedrun.format_time(week_best) if week_best > 0.0 else "noch keine Zeit"]
		LevelsScript.BOARD_CHAOS:
			info = "Chaos-Modus: echter Zufall beim Kaninchen"
		LevelsScript.BOARD_CHAT:
			info = "Der Chat hat mitgeholfen oder das Kaninchen gewichtet"
	lb_info_label.text = info
	for ch in lb_rows.get_children():
		lb_rows.remove_child(ch)
		ch.queue_free()
	var rows := leaderboard_rows()
	lb_rows.columns = 4 if lb_board == LevelsScript.BOARD_WEEK else 3
	if rows.is_empty():
		lb_rows.columns = 1
		rows = [["Noch keine Einträge."]]
	for row in rows:
		for col in row.size():
			var l := Label.new()
			l.text = row[col]
			l.add_theme_font_size_override("font_size", 14)
			l.add_theme_color_override("font_color", PELLET_COLOR if col == 1 else (MUTED if col == 2 and row.size() == 4 else RABBIT_WHITE))
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if col <= 1 else HORIZONTAL_ALIGNMENT_LEFT
			lb_rows.add_child(l)


func _build_gameover_panel() -> void:
	gameover_panel = _overlay_panel()
	gameover_panel.visible = false
	var box := gameover_panel.get_child(0)
	box.add_child(_title_label("VERSCHLUNGEN!"))

	var stats := HBoxContainer.new()
	stats.alignment = BoxContainer.ALIGNMENT_CENTER
	stats.add_theme_constant_override("separation", 24)
	box.add_child(stats)
	final_score_label = _stat_block(stats, "PUNKTE")
	final_level_label = _stat_block(stats, "LEVEL")
	final_hs_label = _stat_block(stats, "BESTWERT")

	var btn := _make_button("NOCHMAL")
	btn.pressed.connect(func(): restart_pressed.emit())
	box.add_child(btn)


func _stat_block(parent: Control, tag_text: String) -> Label:
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	parent.add_child(col)
	var tag := Label.new()
	tag.text = tag_text
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.add_theme_color_override("font_color", Color(0.56, 0.64, 0.78))
	tag.add_theme_font_size_override("font_size", 11)
	col.add_child(tag)
	var val := Label.new()
	val.text = "0"
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	val.add_theme_color_override("font_color", PELLET_COLOR)
	val.add_theme_font_size_override("font_size", 18)
	col.add_child(val)
	return val


## Level-clear banner: a centered panel with background (QA-W2: it used to
## hang with its top-left corner in the screen center, without background).
func _build_levelclear_label() -> void:
	levelclear_panel = _centered_overlay()
	levelclear_panel.visible = false
	var panel := PanelContainer.new()
	var sb := _panel_style()
	sb.set_content_margin_all(18)
	sb.bg_color = Color(0.02, 0.03, 0.05, 0.92)
	panel.add_theme_stylebox_override("panel", sb)
	levelclear_panel.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(col)
	levelclear_label = _title_label("LEVEL GESCHAFFT!", 20)
	col.add_child(levelclear_label)
	levelclear_sub = _subtitle_label("")
	levelclear_sub.add_theme_color_override("font_color", PELLET_COLOR)
	col.add_child(levelclear_sub)


## A full-screen, input-transparent CenterContainer: whatever goes in sits
## exactly in the middle at any resolution.
func _centered_overlay() -> CenterContainer:
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cc)
	return cc


## Start intro "Follow the white rabbit. But beware" (spec 2.1): its own
## centered panel with background, shown for Main.START_INTRO_S at every
## speedrun start.
func _build_start_intro() -> void:
	start_intro = _centered_overlay()
	start_intro.visible = false
	start_intro_panel = PanelContainer.new()
	var sb := _panel_style()
	sb.set_content_margin_all(28)
	sb.bg_color = Color(0.0, 0.0, 0.0, 0.88)
	sb.border_color = Color(RABBIT_WHITE, 0.45)
	start_intro_panel.add_theme_stylebox_override("panel", sb)
	start_intro.add_child(start_intro_panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	start_intro_panel.add_child(col)
	var l1 := _title_label("Follow the white rabbit.", 30)
	l1.add_theme_color_override("font_color", RABBIT_WHITE)
	col.add_child(l1)
	var l2 := _title_label("But beware", 22)
	l2.add_theme_color_override("font_color", COND_BAD)
	col.add_child(l2)


func show_start_intro(on: bool) -> void:
	start_intro.visible = on


func is_start_intro_visible() -> bool:
	return start_intro.visible


## Condition title card (spec 2.2): name, symbol, remaining-time bar; green
## for good, magenta for bad conditions; for Fear & Loathing the symbol of
## the drawn manipulation. Sits under the power bar, top center.
func _build_condition_card() -> void:
	condition_card = PanelContainer.new()
	condition_card.set_anchors_preset(Control.PRESET_CENTER_TOP)
	condition_card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	condition_card.offset_left = -150
	condition_card.offset_right = 150
	condition_card.offset_top = 56
	condition_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	condition_card.visible = false
	add_child(condition_card)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	condition_card.add_child(row)
	condition_icon = Control.new()
	condition_icon.custom_minimum_size = Vector2(40, 40)
	condition_icon.draw.connect(func(): _draw_condition_icon(condition_icon, condition_icon_kind, condition_color))
	row.add_child(condition_icon)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	condition_name_label = Label.new()
	condition_name_label.add_theme_font_size_override("font_size", 18)
	col.add_child(condition_name_label)
	condition_sub_label = Label.new()
	condition_sub_label.add_theme_font_size_override("font_size", 11)
	condition_sub_label.add_theme_color_override("font_color", Color(0.8, 0.84, 0.9))
	col.add_child(condition_sub_label)
	condition_chat_label = Label.new()
	condition_chat_label.add_theme_font_size_override("font_size", 13)
	condition_chat_label.add_theme_color_override("font_color", BOARD_COLORS.chat)
	condition_chat_label.visible = false
	col.add_child(condition_chat_label)
	condition_bar = ProgressBar.new()
	condition_bar.custom_minimum_size = Vector2(200, 6)
	condition_bar.show_percentage = false
	condition_bar.max_value = 1.0
	condition_fill = StyleBoxFlat.new()
	condition_fill.set_corner_radius_all(3)
	var bgs := StyleBoxFlat.new()
	bgs.bg_color = Color(1, 1, 1, 0.12)
	bgs.set_corner_radius_all(3)
	condition_bar.add_theme_stylebox_override("fill", condition_fill)
	condition_bar.add_theme_stylebox_override("background", bgs)
	col.add_child(condition_bar)


func show_condition_card(c, chat_line: String = "") -> void:
	condition_color = COND_GOOD if c.is_good else COND_BAD
	condition_icon_kind = c.icon
	condition_name_label.text = c.display_name.to_upper()
	condition_name_label.add_theme_color_override("font_color", condition_color)
	condition_sub_label.text = c.subtitle()
	condition_sub_label.visible = condition_sub_label.text != ""
	condition_chat_label.text = chat_line
	condition_chat_label.visible = chat_line != ""
	condition_fill.bg_color = condition_color
	condition_bar.value = 1.0
	var sb := _panel_style()
	sb.bg_color = Color(0.02, 0.02, 0.03, 0.9)
	sb.border_color = Color(condition_color, 0.8)
	sb.set_border_width_all(2)
	condition_card.add_theme_stylebox_override("panel", sb)
	condition_card.visible = true
	condition_icon.queue_redraw()


func update_condition_card(remaining: float, duration: float) -> void:
	condition_bar.value = clampf(remaining / maxf(duration, 0.001), 0.0, 1.0)


func hide_condition_card() -> void:
	condition_card.visible = false


## Vector symbols of the conditions (no font glyphs needed).
func _draw_condition_icon(ci: Control, kind: String, col: Color) -> void:
	var s := ci.size
	var c := s * 0.5
	var r := minf(s.x, s.y) * 0.42
	match kind:
		"matrix":
			# falling code columns
			for i in 4:
				var x := s.x * (0.2 + i * 0.2)
				var top := s.y * (0.1 + 0.15 * float(i % 2))
				for j in 4:
					var y := top + j * s.y * 0.2
					if y < s.y * 0.9:
						ci.draw_rect(Rect2(x - 2, y, 4, s.y * 0.12), Color(col, 1.0 - j * 0.22))
		"taschenuhr":
			ci.draw_arc(c, r, 0, TAU, 32, col, 2.5, true)
			ci.draw_rect(Rect2(c.x - 3, c.y - r - 6, 6, 5), col)
			ci.draw_line(c, c + Vector2(0, -r * 0.75), col, 2.5, true)
			ci.draw_line(c, c + Vector2(r * 0.5, 0), col, 2.5, true)
		"stromausfall":
			var bolt := PackedVector2Array([c + Vector2(r * 0.2, -r), c + Vector2(-r * 0.45, r * 0.1), c + Vector2(0, r * 0.1), c + Vector2(-r * 0.2, r), c + Vector2(r * 0.45, -r * 0.1), c + Vector2(0, -r * 0.1)])
			ci.draw_colored_polygon(bolt, col)
			ci.draw_line(c + Vector2(-r, -r), c + Vector2(r, r), Color(0, 0, 0), 5, true)
			ci.draw_line(c + Vector2(-r, -r), c + Vector2(r, r), col, 2.5, true)
		"fl_swap":
			# A <-> D: two opposite arrows
			ci.draw_line(c + Vector2(-r, -r * 0.35), c + Vector2(r, -r * 0.35), col, 2.5, true)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(r, -r * 0.35), c + Vector2(r * 0.55, -r * 0.65), c + Vector2(r * 0.55, -r * 0.05)]), col)
			ci.draw_line(c + Vector2(r, r * 0.35), c + Vector2(-r, r * 0.35), col, 2.5, true)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-r, r * 0.35), c + Vector2(-r * 0.55, r * 0.05), c + Vector2(-r * 0.55, r * 0.65)]), col)
		"fl_drift":
			# straight intent (faint) vs. drifting path (bright)
			ci.draw_line(c + Vector2(-r * 0.4, r), c + Vector2(-r * 0.4, -r), Color(col, 0.35), 2.0, true)
			var pts := PackedVector2Array()
			for i in 9:
				var t := float(i) / 8.0
				pts.append(c + Vector2(-r * 0.4 + t * t * r * 1.2, r - t * 2.0 * r))
			ci.draw_polyline(pts, col, 2.5, true)
			var tip: Vector2 = pts[pts.size() - 1]
			ci.draw_colored_polygon(PackedVector2Array([tip + Vector2(0, -4), tip + Vector2(-6, 4), tip + Vector2(5, 5)]), col)
		"fl_delay":
			# hourglass
			ci.draw_line(c + Vector2(-r * 0.7, -r), c + Vector2(r * 0.7, -r), col, 2.5, true)
			ci.draw_line(c + Vector2(-r * 0.7, r), c + Vector2(r * 0.7, r), col, 2.5, true)
			ci.draw_polyline(PackedVector2Array([c + Vector2(-r * 0.6, -r), c + Vector2(r * 0.6, r), c + Vector2(-r * 0.6, r), c + Vector2(r * 0.6, -r), c + Vector2(-r * 0.6, -r)]), col, 2.0, true)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.35, r * 0.9), c + Vector2(r * 0.35, r * 0.9), c + Vector2(0, r * 0.4)]), col)
		_:
			ci.draw_circle(c, r * 0.5, col)


## scrollable=true anchors the panel to a tall, centered column (5%-95% of
## the viewport height) and wraps its content box in a ScrollContainer,
## instead of shrink-centering the panel to its content's natural size. The
## start panel needs this: it has picked up enough buttons/labels over time
## (Explorer-Level, Condition row, Twitch row, ...) that on a smaller window it
## no longer reliably fits — the lower buttons could end up pushed off
## screen with nothing to scroll them into view. Other panels stay on the
## original shrink-centered behavior, which still looks right for them.
## Use _panel_box() to get the actual content box back, since its position
## in the tree differs between the two modes.
func _overlay_panel(scrollable: bool = false) -> PanelContainer:
	var root := PanelContainer.new()
	root.custom_minimum_size = Vector2(420, 0)
	if scrollable:
		root.anchor_left = 0.5
		root.anchor_right = 0.5
		root.anchor_top = 0.05
		root.anchor_bottom = 0.95
		root.offset_left = -210
		root.offset_right = 210
		root.offset_top = 0
		root.offset_bottom = 0
	else:
		# QA-W2: grow from the center in both directions, so the panel sits
		# centered instead of hanging from its top-left corner.
		root.set_anchors_preset(Control.PRESET_CENTER)
		root.grow_horizontal = Control.GROW_DIRECTION_BOTH
		root.grow_vertical = Control.GROW_DIRECTION_BOTH
	var sb := _panel_style()
	sb.set_content_margin_all(26)
	sb.bg_color = Color(0.035, 0.055, 0.11, 0.97)
	root.add_theme_stylebox_override("panel", sb)
	add_child(root)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	if scrollable:
		var scroll := ScrollContainer.new()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		root.add_child(scroll)
		scroll.add_child(box)
	else:
		root.add_child(box)
	return root


## Returns the content VBoxContainer for a panel built by _overlay_panel(),
## whether or not it's the scrollable variant (where the box sits one level
## deeper, inside a ScrollContainer).
func _panel_box(panel: PanelContainer) -> VBoxContainer:
	var child: Node = panel.get_child(0)
	if child is VBoxContainer:
		return child
	return child.get_child(0)


func show_only(panel: Control) -> void:
	for p in [start_panel, pause_panel, gameover_panel, leaderboard_panel]:
		p.visible = p == panel


func hide_all_panels() -> void:
	start_panel.visible = false
	pause_panel.visible = false
	gameover_panel.visible = false
	leaderboard_panel.visible = false


func set_score(v: int) -> void:
	score_label.text = str(v)


func set_level(v) -> void:
	level_label.text = str(v)


## The Explorer-level button is always enabled (see _build_start_panel);
## beating a level's target time just shows a badge next to it.
func set_bonus_unlocked(v: bool) -> void:
	manhattan_bonus_label.visible = v


## The pause note is only true in a timed level (Manhattan has no clock).
func set_pause_note(timed_level: bool) -> void:
	pause_note_label.text = "Das Labyrinth wartet. Die Speedrun-Zeit läuft weiter." if timed_level else "Die Stadt wartet."


func set_twitch_status(text: String) -> void:
	twitch_status_label.text = text


func set_lives(v: int) -> void:
	for child in lives_box.get_children():
		if child is ColorRect:
			child.queue_free()
	for i in v:
		var dot := ColorRect.new()
		dot.custom_minimum_size = Vector2(12, 12)
		dot.color = PELLET_COLOR
		lives_box.add_child(dot)


func set_start_highscore(v: int) -> void:
	start_hs_label.text = str(v)


func show_gameover(score: int, level, highscore: int) -> void:
	final_score_label.text = str(score)
	final_level_label.text = str(level)
	final_hs_label.text = str(highscore)
	hide_all_panels()
	gameover_panel.visible = true


func show_levelclear(visible_flag: bool, subtitle: String = "") -> void:
	levelclear_panel.visible = visible_flag
	if visible_flag:
		levelclear_sub.text = subtitle
		levelclear_sub.visible = subtitle != ""


func set_timer(seconds: float) -> void:
	timer_label.text = Speedrun.format_time(seconds)


## Best time of the board the level counts on; on the weekly board with the
## week it was set in ("1:23.45 · KW 39").
func set_best_time(seconds: float, week_text: String = "") -> void:
	var text := Speedrun.format_time(seconds)
	if seconds >= 0.0 and week_text != "":
		text += " · " + week_text
	best_label.text = text


## Minimap: fed a maze + player + enemies + maze_view (for the pellets —
## consumed pickups just aren't drawn anymore, same pellet_alive/power_alive
## arrays MazeView already keeps, nothing new to track here) each frame by
## Main, drawn via _draw().
## Stromausfall switches the minimap off for its duration.
func set_minimap_visible(on: bool) -> void:
	minimap.visible = on


func update_minimap(maze, player: Node3D, enemies: Array, frightened: bool, maze_view = null) -> void:
	minimap_maze = maze
	minimap_player = player
	minimap_enemies = enemies
	minimap_frightened = frightened
	minimap_maze_view = maze_view
	minimap.queue_redraw()


func _draw_minimap() -> void:
	if minimap_maze == null:
		return
	var size := minimap.size
	var sx: float = size.x / float(minimap_maze.cols)
	var sy: float = size.y / float(minimap_maze.rows)
	# Colors follow the level's CityTheme (Speedrun: turquoise walls, never
	# blue; cream pickups); the defaults are the original minimap colors.
	var ct = minimap_maze_view.city_theme if minimap_maze_view != null and minimap_maze_view.city_theme != null else null
	var bg_col: Color = ct.minimap_bg_color if ct != null else Color(0.008, 0.012, 0.039, 0.4)
	var wall_col: Color = ct.minimap_wall_color if ct != null else Color(0.118, 0.227, 0.478)
	var pellet_col: Color = ct.pellet_color if ct != null else Color(1.0, 0.82, 0.4)
	var power_col: Color = ct.power_color if ct != null else Color(1.0, 0.365, 0.635)
	var frightened_col: Color = ct.minimap_frightened_color if ct != null else Color(0.35, 0.82, 1.0)
	minimap.draw_rect(Rect2(Vector2.ZERO, size), bg_col)
	for r in minimap_maze.rows:
		for c in minimap_maze.cols:
			if minimap_maze.grid[r][c] == 1:
				minimap.draw_rect(Rect2(c * sx, r * sy, sx + 0.6, sy + 0.6), wall_col)
	if minimap_maze_view != null:
		for i in minimap_maze_view.pellet_cells.size():
			if not minimap_maze_view.pellet_alive[i]:
				continue
			var pc: Vector2i = minimap_maze_view.pellet_cells[i]
			minimap.draw_circle(Vector2((pc.y + 0.5) * sx, (pc.x + 0.5) * sy), 0.9, pellet_col)
		for i in minimap_maze_view.power_cells.size():
			if not minimap_maze_view.power_alive[i]:
				continue
			var pw: Vector2i = minimap_maze_view.power_cells[i]
			minimap.draw_circle(Vector2((pw.y + 0.5) * sx, (pw.x + 0.5) * sy), 1.6, power_col)
		# The white rabbit is visible on the minimap from the level start on
		# (spec 2.2): a white dot with a dark ring, bigger than a pellet.
		if minimap_maze_view.rabbit_alive:
			var rc: Vector2i = minimap_maze_view.rabbit_cell
			var rp := Vector2((rc.y + 0.5) * sx, (rc.x + 0.5) * sy)
			minimap.draw_circle(rp, 3.4, Color(0, 0, 0))
			minimap.draw_circle(rp, 2.4, RABBIT_WHITE)
	# Review findings GD-K4/UX-K2/Code-W11: the player's real facing
	# direction is (-sin(yaw), -cos(yaw)) (see player_controller.gd's
	# _physics_process), but the arrow was rotated by `p.rotated(yaw)` —
	# the wrong sign, so turning left visibly swung the arrow right (north/
	# south happened to still look right; east/west were swapped). Fixed to
	# `p.rotated(-yaw)`. Player and enemy markers were also missing the
	# +0.5-cell offset the pellets/power-ups above already use, putting
	# them half a cell off from where they actually are.
	for e in minimap_enemies:
		var col: Color = frightened_col if minimap_frightened else e.palette_color
		minimap.draw_circle(Vector2((e.position.x / 2.0 + 0.5) * sx, (e.position.z / 2.0 + 0.5) * sy), 2.4, col)
	if minimap_player != null:
		var yaw: float = minimap_player.yaw if "yaw" in minimap_player else 0.0
		minimap.draw_colored_polygon(_minimap_arrow(Vector2((minimap_player.global_position.x / 2.0 + 0.5) * sx, (minimap_player.global_position.z / 2.0 + 0.5) * sy), yaw), ACCENT)


## The player arrow for the minimap, centred on `centre` (minimap pixels),
## tip pointing where the camera looks. The camera looks along
## (-sin(yaw), -cos(yaw)) in (x, z), which on the minimap (x right, z down) is
## the arrow's "up" vector (0, -1) rotated by -yaw.
static func _minimap_arrow(centre: Vector2, yaw: float) -> PackedVector2Array:
	var pts := PackedVector2Array([Vector2(0, -4.2), Vector2(3, 3.6), Vector2(-3, 3.6)])
	var out := PackedVector2Array()
	for p in pts:
		out.append(centre + p.rotated(-yaw))
	return out
