extends CanvasLayer

const ExplorerCitiesReg := preload("res://scripts/explorer_cities.gd")
## Hud — score/level/lives, minimap, power-timer bar, and the start / pause /
## game-over / level-clear overlays. Built entirely in code (no .tscn UI tree
## to keep in sync by hand).

signal start_pressed
signal resume_pressed
signal restart_pressed
## Explorer city chosen on the start screen (explorer_cities.gd id).
signal explorer_pressed(city_id: String)
## UX-K2: back to the start screen (pause after the confirmation in a
## speedrun, game over) and quitting the game (start screen).
signal menu_pressed
signal quit_pressed
signal reduce_fx_toggled(on: bool)
signal reduce_rain_toggled(on: bool)
## UX-K1 comfort block: field of view (degrees) and mouse sensitivity (factor).
signal fov_changed(value: float)
signal mouse_sens_changed(value: float)
signal chaos_toggled(on: bool)
signal twitch_toggled(is_enabled: bool, channel: String)
signal versus_pressed

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
## Kippbild with "Effekte reduzieren" (UX-K1): the world does not tip, a thin
## frame in the complement palette's light cyan shows the manipulation.
const FLIP_FRAME_COLOR := Color("4dccf2")
const FLIP_FRAME_PX := 6.0
## UX-W5/Nice: chips keep a fixed minimum width, explanation texts >= 14 px.
const CHIP_MIN_W := 170.0
## Explorer city buttons on the start screen (UX N-B; checked at 1280x800
## and 1152x648).
const EXPLORER_BTN_FONT := 16
const TEXT_PX := 14
## UX-W6: the Bestenliste always has room for this many rows.
const LB_ROWS := 10
const LB_ROW_H := 24.0
## Short labels of the conditions in the Bestenliste (UX-W6): which
## condition the rabbit gave in that level, "OHNE" = rabbit left alone,
## "–" = unknown (an entry from before this was stored).
const COND_TAGS := {"matrix": "MTX", "taschenuhr": "UHR", "fear_and_loathing": "F&L", "stromausfall": "STROM", "": "OHNE", "?": "–"}
const LevelsScript := preload("res://scripts/levels.gd")
const WhiteRabbitScript := preload("res://scripts/white_rabbit.gd")
const ConditionsScript := preload("res://scripts/conditions.gd")
const SettingsScript := preload("res://scripts/settings.gd")

var score_label: Label
var level_label: Label
var lives_box: HBoxContainer
var timer_label: Label
var best_label: Label
var power_bar: ProgressBar
var power_wrap: Control
var minimap: Control
## Everything that only belongs to a running game (chips, minimap): hidden on
## the start screen, in the Bestenliste and on the game-over screen (UX-W5,
## QA-W10).
var game_hud: Control

var start_panel: PanelContainer
var pause_restart_btn: Button
var pause_confirm_q: Label
var pause_confirm_yes: Button
## Versus screens (lobby, race bar, countdown, result) — versus_ui.gd (E17).
var versus_ui
## The Versus opponent's cell on the minimap (-1, -1 = none).
var minimap_opponent_cell := Vector2i(-1, -1)
var pause_panel: PanelContainer
var gameover_panel: PanelContainer
var levelclear_panel: Control
var levelclear_label: Label
var levelclear_sub: Label

var pause_note_label: Label
## UX-K2: the pause's HAUPTMENÜ asks once in a speedrun.
var menu_btn: Button
var menu_confirm_row: Control
var _menu_needs_confirm := true
## Board chip (BRETT): "KW 40" on the weekly board, "CHAOS", "CHAT".
var board_label: Label
var board_chip: Control
## Chat mode (Twitch connected): where the rabbit comes from, or the good
## share once the chat shifted it (spec 2.6).
var chat_chip: PanelContainer
var chat_share_label: Label
var chat_share_bar: Control
var chat_share := 0.6
var chat_share_voters := 0
var chat_shifted := false
var chaos_start: CheckBox
## Bestenliste (start screen / game over): board tabs, level switcher, week
## or all-time filter, top 10.
var leaderboard_panel: PanelContainer
var lb_board := "woche"
var lb_level_index := 0
## "week" = only this ISO week, "all" = all time (UX-W6).
var lb_range := "all"
var lb_title_label: Label
var lb_level_label: Label
var lb_info_label: Label
var lb_rows: GridContainer
var lb_rows_box: Control
var lb_tabs := {}
var lb_range_tabs := {}
## The panel the Bestenliste returns to (start screen or game over).
var lb_return_panel: Control = null
## The ISO week the HUD treats as "this week" (Main sets it; tests force it).
var current_week := Vector2i(0, 0)
var reduce_fx_start: CheckBox
var reduce_fx_pause: CheckBox
var reduce_rain_start: CheckBox
var reduce_rain_pause: CheckBox
## UX-K1 comfort sliders, one pair on the start screen, one in the pause.
var fov_sliders: Array = []
var sens_sliders: Array = []
var fov_value_labels: Array = []
var sens_value_labels: Array = []
var comfort_start_block: Control
var comfort_pause_block: Control
var _comfort_syncing := false
## Condition title card (top, under the power bar) and the start intro.
var condition_card: PanelContainer
var condition_icon: Control
var condition_name_label: Label
var condition_sub_label: Label
## "Chat 70 % → MATRIX" when the chat shifted the rabbit (spec 2.6).
var condition_chat_label: Label
## UX-W1: right column of the card: "GUT ▲" / "SCHLECHT ▼" and the seconds left.
var condition_kind_label: Label
var condition_secs_label: Label
var condition_bar: ProgressBar
var condition_fill: StyleBoxFlat
var condition_icon_kind := ""
var condition_color := COND_GOOD
var _condition_secs_shown := -1
## UX-W1: in the last 3 s the bar pulses at 1 Hz.
const CARD_PULSE_HZ := 1.0
const CARD_WARN_S := 3.0
var condition_bar_pulse := 1.0
var start_intro: CenterContainer
var start_intro_panel: PanelContainer
var start_intro_skip_label: Label
## UX-W7: after the intro, until the first step.
var clock_hint: Control
var clock_hint_label: Label
const CLOCK_HINT_TEXT := "Die Uhr startet mit deinem ersten Schritt"
## Explorer exits drawn on the minimap (cells), see set_minimap_exits.
var minimap_exit_cells: Array = []
## Explorer hints (the fold, the way, the exit): own box in the upper third,
## centred under the level chip, off the pellet trail (UX W-C). Counts down
## in _process only while the pause is closed (UX N-A: the game pause is not
## the tree pause, so a SceneTreeTimer would run on).
const HINT_MAX_W := 560.0
const HINT_TOP := 96.0
var hint_box: PanelContainer
var hint_label: Label
var _hint_left := 0.0
## Minimap (UX K-A, QA K3, code H3): the static layer (background, walls,
## water) is painted once per maze into a texture; in explorer cities the
## player arrow is white with a black rim and the exit a ring glyph that
## pulses at 0.5 Hz (still with "Effekte reduzieren").
const MINIMAP_PLAYER_EXPLORER := Color("f4f1e8")
const MINIMAP_EXIT_PULSE_HZ := 0.5
var _explorer_hud := false
var _reduce_fx := false
var _mm_static_tex: ImageTexture = null
var _mm_static_key := []
var _mm_t := 0.0
## Start screen: one line under the city buttons that says what the hovered
## or focused city is like (UX N-B).
var explorer_desc_label: Label
const EXPLORER_DESC_DEFAULT := "Ruhige Städte ohne Uhr und Punkte. Die Kugeln zeigen den Weg zum Ausgang; er führt in einen Speedrun."
## UX-K1: thin frame of the Kippbild with "Effekte reduzieren".
var flip_frame: Control
var flip_frame_alpha := 0.0
## Chips that only make sense in a timed, scored level (hidden in Manhattan).
var timed_chips: Array = []

var final_score_label: Label
var final_level_label: Label
var final_hs_label: Label
var gameover_note_label: Label
var start_hs_label: Label
var explorer_buttons: Dictionary = {} # city id -> Button
var manhattan_btn: Button
var tokyo_btn: Button
var manhattan_bonus_label: Label
var debug_label: Label
## Dash charges ("● ○"), see set_dash(); the chip is hidden in Explorer cities.
var dash_label: Label
var dash_chip: Control
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
	_build_flip_frame()
	_build_start_panel()
	_build_pause_panel()
	_build_gameover_panel()
	_build_leaderboard_panel()
	_build_levelclear_label()
	_build_condition_card()
	_build_start_intro()
	_build_clock_hint()
	_build_hint_box()
	versus_ui = load("res://scripts/versus_ui.gd").new()
	add_child(versus_ui)
	versus_ui.setup(self)


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
	game_hud = top

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

	dash_label = _make_chip(left, "DASH", "●")
	dash_chip = dash_label.get_parent().get_parent()

	# Debug overlay (FPS / player position / cell) — hidden unless
	# set_debug_overlay(true) is called (F3 in debug builds, see main.gd).
	debug_label = _make_chip(left, "DEBUG", "--")
	debug_label.get_parent().get_parent().visible = false

	var lives_chip := PanelContainer.new()
	lives_chip.add_theme_stylebox_override("panel", _panel_style())
	lives_chip.custom_minimum_size.x = CHIP_MIN_W
	lives_chip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	left.add_child(lives_chip)
	timed_chips.append(lives_chip)
	lives_box = HBoxContainer.new()
	lives_box.add_theme_constant_override("separation", 6)
	lives_chip.add_child(lives_box)
	var lives_tag := Label.new()
	lives_tag.text = "LEBEN "
	lives_tag.add_theme_color_override("font_color", MUTED)
	lives_tag.add_theme_font_size_override("font_size", 12)
	lives_box.add_child(lives_tag)

	minimap = Control.new()
	minimap.custom_minimum_size = Vector2(150, 150)
	minimap.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	minimap.offset_left = -166
	minimap.offset_top = 0
	minimap.offset_right = -16
	minimap.offset_bottom = 150
	minimap.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST # the static layer: one pixel per cell
	minimap.draw.connect(_draw_minimap)
	top.add_child(minimap)


## Nice-to-have from the UX review: every chip at least CHIP_MIN_W wide, so
## the column does not jump when a value gets longer.
func _make_chip(parent: Control, label_text: String, value_text: String) -> Label:
	var chip := PanelContainer.new()
	chip.add_theme_stylebox_override("panel", _panel_style())
	chip.custom_minimum_size.x = CHIP_MIN_W
	chip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	parent.add_child(chip)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	chip.add_child(row)
	var tag := Label.new()
	tag.text = label_text
	tag.add_theme_color_override("font_color", MUTED)
	tag.add_theme_font_size_override("font_size", 12)
	row.add_child(tag)
	var value := Label.new()
	value.text = value_text
	value.add_theme_color_override("font_color", PELLET_COLOR)
	value.add_theme_font_size_override("font_size", 16)
	row.add_child(value)
	return value


## UX-W5 / QA-W10: the in-game HUD (chips, minimap, power bar, condition
## card) only while a game runs — not over the start screen, the Bestenliste
## or the game over.
func set_game_hud_visible(on: bool) -> void:
	game_hud.visible = on
	if not on:
		power_wrap.visible = false
		condition_card.visible = false
		set_flip_frame(0.0)


func is_game_hud_visible() -> bool:
	return game_hud.visible


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
	tag.add_theme_font_size_override("font_size", 12)
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
	_explorer_hud = is_explorer
	if not is_explorer:
		hide_hint()
	for chip in timed_chips:
		chip.visible = not is_explorer
	dash_chip.visible = not is_explorer
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


## Chat mode chip (spec 2.6, GD review): while the chat has not shifted the
## ratio it names where the rabbit comes from — "Kaninchen: Woche" (or
## "Kaninchen: Chaos") plus how many voted; once >= 3 viewers shifted it,
## "Kaninchen: 70 % gut" with a small green / magenta bar.
func _build_chat_chip(parent: Control) -> void:
	chat_chip = PanelContainer.new()
	chat_chip.add_theme_stylebox_override("panel", _panel_style())
	chat_chip.custom_minimum_size.x = CHIP_MIN_W
	chat_chip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
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
		if not chat_shifted:
			chat_share_bar.draw_rect(Rect2(Vector2.ZERO, chat_share_bar.size), Color(MUTED, 0.35))
			return
		var w := chat_share_bar.size.x * clampf(chat_share, 0.0, 1.0)
		chat_share_bar.draw_rect(Rect2(0, 0, w, chat_share_bar.size.y), COND_GOOD)
		chat_share_bar.draw_rect(Rect2(w, 0, chat_share_bar.size.x - w, chat_share_bar.size.y), COND_BAD))
	col.add_child(chat_share_bar)


func set_chat_share_visible(on: bool) -> void:
	chat_chip.visible = on


## `share` 0..1 (good), `voters` = different voters in the 60-s window,
## `shifted` = the chat moved the ratio (>= min_voters and not 60 %),
## `source` = "Woche" / "Chaos" — where an unshifted rabbit comes from.
func set_chat_share(share: float, voters: int, min_voters: int, shifted: bool = true, source: String = "Woche") -> void:
	chat_share = share
	chat_share_voters = voters
	chat_shifted = shifted
	var text := ""
	if shifted:
		text = "Kaninchen: %d %% gut" % roundi(share * 100.0)
	else:
		text = "Kaninchen: %s" % source
		if voters < min_voters:
			text += "  (Chat %d/%d)" % [voters, min_voters]
	if chat_share_label.text != text:
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


## Dash chip: one filled dot per charge, empty dots up to the maximum; a
## dimmed text while the cooldown runs.
func set_dash(charges: int, max_charges: int, ready: bool) -> void:
	var s := ""
	for i in max_charges:
		s += ("● " if i < charges else "○ ")
	dash_label.text = s.strip_edges()
	dash_label.modulate = Color(1, 1, 1, 1.0 if ready or charges == 0 else 0.55)


func set_dash_visible(on: bool) -> void:
	dash_chip.visible = on


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


## Explanation text (UX-W5: at least TEXT_PX = 14 px).
func _subtitle_label(text: String, font_px: int = TEXT_PX) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", MUTED)
	l.add_theme_font_size_override("font_size", font_px)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	l.custom_minimum_size = Vector2(360, 0)
	return l


func _make_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 46)
	return b


## Start screen, top to bottom (UX-K1, W5): title, the comfort block (always
## visible without scrolling, also at 1152x720), the options (Chaos, Twitch),
## SPEEDRUN with its explanation, BESTENLISTE, EXPLORER (Manhattan | Tokyo), BEENDEN.
func _build_start_panel() -> void:
	start_panel = _overlay_panel(true)
	var box := _panel_box(start_panel)
	box.add_theme_constant_override("separation", 10)
	box.add_child(_title_label("ZAPMANIAC"))
	comfort_start_block = _build_comfort_block()
	reduce_fx_start = comfort_start_block.get_meta("reduce_fx")
	reduce_rain_start = comfort_start_block.get_meta("reduce_rain")
	reduce_rain_start.text = "Regen reduzieren (Tokyo)"
	box.add_child(comfort_start_block)

	box.add_child(_subtitle_label("Lauf durchs Labyrinth, schlucke jede Kugel, weich den Wesen aus.  WASD laufen · Maus umschauen · Esc Pause"))

	var hs_row := HBoxContainer.new()
	hs_row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(hs_row)
	var hs_tag := Label.new()
	hs_tag.text = "BESTPUNKTZAHL  "
	hs_tag.add_theme_color_override("font_color", MUTED)
	hs_row.add_child(hs_tag)
	start_hs_label = Label.new()
	start_hs_label.text = "0"
	start_hs_label.add_theme_color_override("font_color", PELLET_COLOR)
	hs_row.add_child(start_hs_label)

	# Options above the SPEEDRUN button (UX-W5): Chaos, Twitch.
	chaos_start = CheckBox.new()
	chaos_start.text = "Chaos-Modus: echter Zufall beim Kaninchen (eigenes Brett)"
	chaos_start.toggled.connect(func(pressed: bool): chaos_toggled.emit(pressed))
	box.add_child(chaos_start)

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
	box.add_child(twitch_status_label)

	# QA N6: SPEEDRUN and VERSUS share one row, so the start screen still fits.
	var run_row := HBoxContainer.new()
	run_row.add_theme_constant_override("separation", 10)
	box.add_child(run_row)
	var btn := _make_button("SPEEDRUN")
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.size_flags_stretch_ratio = 2.0
	btn.pressed.connect(func(): start_pressed.emit())
	run_row.add_child(btn)
	var vs_btn := _make_button("VERSUS")
	vs_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vs_btn.pressed.connect(func(): versus_pressed.emit())
	run_row.add_child(vs_btn)
	box.add_child(_subtitle_label("Speedrun: zufälliges Level, Zeitjagd, in jedem Level ein weißes Kaninchen – gut oder schlecht. Versus: zu zweit übers Netz, gleiche Level, schnellere Zeit gewinnt."))
	var lb_btn := _make_button("BESTENLISTE")
	lb_btn.pressed.connect(func(): show_leaderboard())
	box.add_child(lb_btn)

	# Always available as its own choice, right from the start screen —
	# not gated behind the speedrun bonus-unlock anymore (that still
	# exists, see manhattan_bonus_label below, just as a nice badge now
	# rather than a lock on the button).
	# Explorer selection: one row with a button per city (same height as the
	# former single EXPLORER-LEVEL button, so the start screen still fits).
	var explorer_row := HBoxContainer.new()
	explorer_row.alignment = BoxContainer.ALIGNMENT_CENTER
	explorer_row.add_theme_constant_override("separation", 10)
	box.add_child(explorer_row)
	var explorer_tag := Label.new()
	explorer_tag.text = "EXPLORER"
	explorer_tag.add_theme_color_override("font_color", MUTED)
	explorer_row.add_child(explorer_tag)
	# One button per registered city (ExplorerCities.EXPLORER_IDS is the
	# single list; QA W3), so a new city only needs its registry entry.
	explorer_buttons.clear()
	for city_id in ExplorerCitiesReg.EXPLORER_IDS:
		var city: Dictionary = ExplorerCitiesReg.get_city(city_id)
		var b := _make_button(String(city.get("label", city_id.to_upper())))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", EXPLORER_BTN_FONT)
		b.pressed.connect(func(): explorer_pressed.emit(city_id))
		var desc := String(city.get("desc", ""))
		b.tooltip_text = desc
		b.mouse_entered.connect(func(): show_explorer_desc(city_id))
		b.focus_entered.connect(func(): show_explorer_desc(city_id))
		b.mouse_exited.connect(func(): show_explorer_desc(""))
		b.focus_exited.connect(func(): show_explorer_desc(""))
		explorer_row.add_child(b)
		explorer_buttons[city_id] = b
	manhattan_btn = explorer_buttons.get("manhattan")
	tokyo_btn = explorer_buttons.get("tokyo")
	explorer_desc_label = _subtitle_label(EXPLORER_DESC_DEFAULT)
	box.add_child(explorer_desc_label)
	manhattan_bonus_label = _subtitle_label("★ Zielzeit in einem Level geschafft")
	manhattan_bonus_label.add_theme_color_override("font_color", PELLET_COLOR)
	manhattan_bonus_label.visible = false
	box.add_child(manhattan_bonus_label)

	var quit_btn := _make_button("BEENDEN")
	quit_btn.pressed.connect(func(): quit_pressed.emit())
	box.add_child(quit_btn)


## UX-K1: the comfort block "Komfort" — "Effekte reduzieren", field of view
## (60–100°, default 72) and mouse sensitivity — once under the start
## screen's title and once in the pause; both stay in sync (set_comfort,
## set_reduce_fx) and Main stores every change in the settings.
func _build_comfort_block() -> Control:
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.0, 0.0, 0.0, 0.25)
	sb.border_color = Color(ACCENT, 0.35)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", sb)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	panel.add_child(col)
	var head := Label.new()
	head.text = "KOMFORT"
	head.add_theme_color_override("font_color", ACCENT)
	head.add_theme_font_size_override("font_size", 13)
	col.add_child(head)
	# both switches in one row, so the block keeps its height (the start
	# screen still fits 1152 x 720)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	col.add_child(row)
	var cb := CheckBox.new()
	cb.text = "Effekte reduzieren (ruhigere Looks, kein Kippen)"
	cb.tooltip_text = "Ruhigere Looks, kein Kippen. Kyoto: die Häuser klappen nicht auf."
	cb.add_theme_font_size_override("font_size", TEXT_PX)
	cb.toggled.connect(func(pressed: bool): reduce_fx_toggled.emit(pressed))
	row.add_child(cb)
	panel.set_meta("reduce_fx", cb)
	var rain := CheckBox.new()
	rain.text = "Regen reduzieren"
	rain.add_theme_font_size_override("font_size", TEXT_PX)
	rain.toggled.connect(func(pressed: bool): reduce_rain_toggled.emit(pressed))
	row.add_child(rain)
	panel.set_meta("reduce_rain", rain)
	var fov_s := _comfort_slider(col, "Sichtfeld", SettingsScript.FOV_MIN, SettingsScript.FOV_MAX, 1.0, fov_value_labels)
	fov_s.value_changed.connect(func(v: float):
		if not _comfort_syncing:
			fov_changed.emit(v))
	fov_sliders.append(fov_s)
	var sens_s := _comfort_slider(col, "Mausempfindlichkeit", SettingsScript.SENS_MIN, SettingsScript.SENS_MAX, 0.05, sens_value_labels)
	sens_s.value_changed.connect(func(v: float):
		if not _comfort_syncing:
			mouse_sens_changed.emit(v))
	sens_sliders.append(sens_s)
	set_comfort(SettingsScript.FOV_DEFAULT, 1.0)
	return panel


func _comfort_slider(parent: Control, text: String, lo: float, hi: float, step: float, value_labels: Array) -> HSlider:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)
	var l := Label.new()
	l.text = text
	l.custom_minimum_size.x = 170
	l.add_theme_font_size_override("font_size", TEXT_PX)
	l.add_theme_color_override("font_color", RABBIT_WHITE)
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.custom_minimum_size = Vector2(150, 20)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(s)
	var v := Label.new()
	v.custom_minimum_size.x = 48
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.add_theme_font_size_override("font_size", TEXT_PX)
	v.add_theme_color_override("font_color", PELLET_COLOR)
	row.add_child(v)
	value_labels.append(v)
	return s


## Shows the stored comfort values on both blocks without re-emitting.
func set_comfort(fov_deg: float, sens: float) -> void:
	_comfort_syncing = true
	for s in fov_sliders:
		s.value = fov_deg
	for s in sens_sliders:
		s.value = sens
	for l in fov_value_labels:
		l.text = "%d°" % roundi(fov_deg)
	for l in sens_value_labels:
		l.text = "%.2f×" % sens
	_comfort_syncing = false


## Start screen: the description of the hovered / focused city (registry
## "desc") in the line under the buttons; "" = the general line.
func show_explorer_desc(city_id: String) -> void:
	if explorer_desc_label == null:
		return
	var d := ""
	if city_id != "":
		d = String(ExplorerCitiesReg.get_city(city_id).get("desc", ""))
	if d == "":
		# leaving one button while another has the focus keeps that one's line
		for cid in explorer_buttons:
			if explorer_buttons[cid].has_focus() and cid != city_id:
				d = String(ExplorerCitiesReg.get_city(cid).get("desc", ""))
	explorer_desc_label.text = d if d != "" else EXPLORER_DESC_DEFAULT


func set_chaos_mode(on: bool) -> void:
	if chaos_start != null:
		chaos_start.set_pressed_no_signal(on)


func set_reduce_fx(on: bool) -> void:
	_reduce_fx = on
	for cb in [reduce_fx_start, reduce_fx_pause]:
		if cb != null:
			cb.set_pressed_no_signal(on)


func set_reduce_rain(on: bool) -> void:
	for cb in [reduce_rain_start, reduce_rain_pause]:
		if cb != null:
			cb.set_pressed_no_signal(on)


## QA K4: "Regen reduzieren" in the pause only where it rains (Tokyo); the
## start screen names the city.
func set_rain_option_visible(on: bool) -> void:
	if reduce_rain_pause != null:
		reduce_rain_pause.visible = on


## Pause (UX-K2): WEITER / NEUSTART / HAUPTMENÜ — HAUPTMENÜ asks once in a
## speedrun ("Lauf abbrechen?") — and the comfort block.
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
	pause_restart_btn = restart_btn
	menu_btn = _make_button("HAUPTMENÜ")
	menu_btn.pressed.connect(_on_pause_menu_pressed)
	box.add_child(menu_btn)
	var confirm := VBoxContainer.new()
	confirm.add_theme_constant_override("separation", 6)
	confirm.visible = false
	box.add_child(confirm)
	var q := _subtitle_label("Lauf abbrechen? Die Zeit dieses Levels wird nicht gewertet.")
	q.add_theme_color_override("font_color", RABBIT_WHITE)
	confirm.add_child(q)
	pause_confirm_q = q
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	confirm.add_child(row)
	var yes := Button.new()
	yes.text = "JA, ZUM MENÜ"
	pause_confirm_yes = yes
	yes.custom_minimum_size = Vector2(150, 40)
	yes.pressed.connect(func():
		menu_confirm_row.visible = false
		menu_pressed.emit())
	row.add_child(yes)
	var no := Button.new()
	no.text = "NEIN"
	no.custom_minimum_size = Vector2(110, 40)
	no.pressed.connect(cancel_menu_confirm)
	row.add_child(no)
	menu_confirm_row = confirm
	comfort_pause_block = _build_comfort_block()
	reduce_fx_pause = comfort_pause_block.get_meta("reduce_fx")
	reduce_rain_pause = comfort_pause_block.get_meta("reduce_rain")
	box.add_child(comfort_pause_block)


## Versus pause (QA N1, design W6): no NEUSTART, HAUPTMENÜ becomes
## MATCH AUFGEBEN with its own question, the note says the clock runs on.
func set_versus_pause(on: bool) -> void:
	pause_restart_btn.visible = not on
	menu_btn.text = "MATCH AUFGEBEN" if on else "HAUPTMENÜ"
	pause_confirm_q.text = "Match aufgeben? Der Gegner gewinnt kampflos." if on else "Lauf abbrechen? Die Zeit dieses Levels wird nicht gewertet."
	pause_confirm_yes.text = "JA, AUFGEBEN" if on else "JA, ZUM MENÜ"
	if on:
		pause_note_label.text = "Die Rennuhr läuft weiter – der Gegner läuft auch."


## Versus: the condition card sits below the race bar (QA W5).
func set_condition_card_top(px: float) -> void:
	condition_card.offset_top = px


## Whether HAUPTMENÜ in the pause asks first (speedrun: yes; Manhattan: no).
func set_menu_confirm(needed: bool) -> void:
	_menu_needs_confirm = needed
	menu_confirm_row.visible = false


func _on_pause_menu_pressed() -> void:
	if _menu_needs_confirm and not menu_confirm_row.visible:
		menu_confirm_row.visible = true
		return
	menu_confirm_row.visible = false
	menu_pressed.emit()


func is_menu_confirm_open() -> bool:
	return pause_panel.visible and menu_confirm_row.visible


func cancel_menu_confirm() -> void:
	menu_confirm_row.visible = false


## ---------------- Bestenliste (spec 2.5, UX-W6) ----------------

## One board (Woche / Chaos / Chat) of one level at a time, "Diese Woche" or
## "Allzeit", top 10 fastest first, in a table of fixed height (10 rows, so
## nothing jumps when a board is short). Columns: rank, time, the condition
## the rabbit gave (short label; OHNE = rabbit left alone), on the weekly
## board its calendar week, and the date. The active tab is drawn in the
## accent color with an underline. Old condition boards (archive) are never
## shown. Esc and ZURÜCK return to where it was opened from.
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
		var t := _tab_button(LevelsScript.BOARD_LABELS[b].to_upper(), 96)
		t.pressed.connect(func(): _set_lb_board(b))
		tabs.add_child(t)
		lb_tabs[b] = t
	var range_row := HBoxContainer.new()
	range_row.alignment = BoxContainer.ALIGNMENT_CENTER
	range_row.add_theme_constant_override("separation", 6)
	box.add_child(range_row)
	for r in [["week", "DIESE WOCHE"], ["all", "ALLZEIT"]]:
		var rt := _tab_button(r[1], 130)
		var rid: String = r[0]
		rt.pressed.connect(func(): _set_lb_range(rid))
		range_row.add_child(rt)
		lb_range_tabs[rid] = rt
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
	lb_info_label.custom_minimum_size = Vector2(440, 50) # two lines on every board: fixed height
	box.add_child(lb_info_label)
	# fixed-height table: header + LB_ROWS rows
	lb_rows_box = Control.new()
	lb_rows_box.custom_minimum_size = Vector2(440, LB_ROW_H * (LB_ROWS + 1))
	box.add_child(lb_rows_box)
	var rows_center := CenterContainer.new()
	rows_center.set_anchors_preset(Control.PRESET_TOP_WIDE)
	rows_center.offset_bottom = LB_ROW_H * (LB_ROWS + 1)
	lb_rows_box.add_child(rows_center)
	lb_rows = GridContainer.new()
	lb_rows.add_theme_constant_override("h_separation", 22)
	lb_rows.add_theme_constant_override("v_separation", 2)
	rows_center.add_child(lb_rows)
	var legend := _subtitle_label("MTX Matrix · UHR Taschenuhr · F&L Fear & Loathing · STROM Stromausfall · OHNE ohne Kaninchen")
	legend.add_theme_color_override("font_color", Color(MUTED, 0.85))
	box.add_child(legend)
	var back := _make_button("ZURÜCK  (Esc)")
	back.pressed.connect(close_leaderboard)
	box.add_child(back)


## A tab button: toggle, the active one in the accent color with an underline.
func _tab_button(text: String, width: float) -> Button:
	var t := Button.new()
	t.text = text
	t.toggle_mode = true
	t.custom_minimum_size = Vector2(width, 32)
	var active := StyleBoxFlat.new()
	active.bg_color = Color(ACCENT, 0.16)
	active.border_color = ACCENT
	active.border_width_bottom = 3
	active.set_corner_radius_all(4)
	active.content_margin_left = 8
	active.content_margin_right = 8
	t.add_theme_stylebox_override("pressed", active)
	t.add_theme_stylebox_override("hover_pressed", active)
	t.add_theme_color_override("font_pressed_color", ACCENT)
	t.add_theme_color_override("font_hover_pressed_color", ACCENT)
	return t


## Opens the Bestenliste. `from` = the panel ZURÜCK / Esc return to (default:
## the start screen).
func show_leaderboard(board: String = "", level_id: String = "", from: Control = null) -> void:
	if board != "":
		lb_board = board
	if level_id != "":
		lb_level_index = maxi(LevelsScript.index_of(level_id), 0)
	lb_return_panel = from if from != null else start_panel
	refresh_leaderboard()
	show_only(leaderboard_panel)


func close_leaderboard() -> void:
	show_only(lb_return_panel if lb_return_panel != null else start_panel)


func _set_lb_board(board: String) -> void:
	lb_board = board
	refresh_leaderboard()


func _set_lb_range(r: String) -> void:
	lb_range = r
	refresh_leaderboard()


func _step_lb_level(d: int) -> void:
	lb_level_index = posmod(lb_level_index + d, LevelsScript.POOL.size())
	refresh_leaderboard()


## Is a leaderboard entry from the current ISO week? On the weekly board by
## its stored week, elsewhere by its date (no date = unknown = not shown).
func _entry_this_week(e: Dictionary) -> bool:
	var this_week := WhiteRabbitScript.week_label(_week_now())
	if lb_board == LevelsScript.BOARD_WEEK and e.get("week", "") != "":
		return e.week == this_week
	var d: PackedStringArray = String(e.get("date", "")).split("-")
	if d.size() != 3:
		return false
	return WhiteRabbitScript.week_label(WhiteRabbitScript.iso_week(d[0].to_int(), d[1].to_int(), d[2].to_int())) == this_week


## "03.10." (this year) / "03.10.25", "–" when unknown.
func _date_display(date: String) -> String:
	var d: PackedStringArray = date.split("-")
	if d.size() != 3:
		return "–"
	if d[0].to_int() == _week_now().x or d[0].to_int() == int(Time.get_datetime_dict_from_system(false).year):
		return "%s.%s." % [d[2], d[1]]
	return "%s.%s.%s" % [d[2], d[1], d[0].substr(2)]


## The rows of the current board/level/range, top 10: [rank, time,
## condition, (week,) date] — the week column only on the weekly board.
func leaderboard_rows() -> Array:
	var lv: Dictionary = LevelsScript.POOL[lb_level_index]
	var out := []
	var all: Array = Leaderboard.get_top(lv.id, lb_board)
	var n := 0
	for e in all:
		if lb_range == "week" and not _entry_this_week(e):
			continue
		n += 1
		var row := ["%d." % n, Speedrun.format_time(e.time), cond_tag(e.get("cond", "?"))]
		if lb_board == LevelsScript.BOARD_WEEK:
			row.append(WhiteRabbitScript.week_display(e.get("week", ""), _week_now()))
		row.append(_date_display(e.get("date", "")))
		out.append(row)
		if n >= LB_ROWS:
			break
	return out


static func cond_tag(cond: String) -> String:
	return COND_TAGS.get(cond, "–")


## The same rows as text lines ("1.  1:23.45  MTX  KW 40  03.10."), for tests.
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
	for r in lb_range_tabs:
		lb_range_tabs[r].set_pressed_no_signal(r == lb_range)
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
	var week_col := lb_board == LevelsScript.BOARD_WEEK
	var header := ["#", "ZEIT", "KANINCHEN"]
	if week_col:
		header.append("KW")
	header.append("DATUM")
	lb_rows.columns = header.size()
	if rows.is_empty():
		lb_rows.columns = 1
		rows = [["Noch keine Einträge." if lb_range == "all" else "Diese Woche noch keine Einträge."]]
	else:
		rows.push_front(header)
	for ri in rows.size():
		var row: Array = rows[ri]
		var is_header := ri == 0 and rows.size() > 1 and row == header
		for col in row.size():
			var l := Label.new()
			l.text = row[col]
			l.custom_minimum_size.y = LB_ROW_H - 2
			l.add_theme_font_size_override("font_size", 12 if is_header else 15)
			var c := RABBIT_WHITE
			if is_header:
				c = MUTED
			elif col == 1:
				c = PELLET_COLOR
			elif col == 2 and row.size() > 2:
				c = _cond_tag_color(row[col])
			elif col >= 3:
				c = MUTED
			l.add_theme_color_override("font_color", c)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if col <= 1 else HORIZONTAL_ALIGNMENT_LEFT
			lb_rows.add_child(l)


func _cond_tag_color(tag: String) -> Color:
	for id in COND_TAGS:
		if COND_TAGS[id] == tag:
			var e: Dictionary = ConditionsScript.entry(id)
			if e.is_empty():
				return MUTED
			return COND_GOOD if e.is_good else COND_BAD
	return MUTED


## Game over (UX-K2): NOCHMAL / HAUPTMENÜ / BESTENLISTE.
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
	gameover_note_label = _subtitle_label("Mit Chat-Hilfe gespielt: diese Punktzahl zählt nicht als Bestwert.")
	gameover_note_label.visible = false
	box.add_child(gameover_note_label)

	var btn := _make_button("NOCHMAL")
	btn.pressed.connect(func(): restart_pressed.emit())
	box.add_child(btn)
	var menu := _make_button("HAUPTMENÜ")
	menu.pressed.connect(func(): menu_pressed.emit())
	box.add_child(menu)
	var lb := _make_button("BESTENLISTE")
	lb.pressed.connect(func(): show_leaderboard("", "", gameover_panel))
	box.add_child(lb)


func _stat_block(parent: Control, tag_text: String) -> Label:
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	parent.add_child(col)
	var tag := Label.new()
	tag.text = tag_text
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.add_theme_color_override("font_color", MUTED)
	tag.add_theme_font_size_override("font_size", 12)
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
## speedrun start. From the second start of a session a small line says
## that any key skips it (UX-W7).
func _build_start_intro() -> void:
	start_intro = _centered_overlay()
	start_intro.visible = false
	start_intro.mouse_filter = Control.MOUSE_FILTER_IGNORE
	start_intro_panel = PanelContainer.new()
	start_intro_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	start_intro_skip_label = _subtitle_label("Beliebige Taste: überspringen")
	start_intro_skip_label.custom_minimum_size = Vector2(0, 0)
	start_intro_skip_label.visible = false
	col.add_child(start_intro_skip_label)


func show_start_intro(on: bool, skippable: bool = false) -> void:
	start_intro.visible = on
	start_intro_skip_label.visible = on and skippable


func is_start_intro_visible() -> bool:
	return start_intro.visible


## UX-W7: after the intro a small line stays until the first step.
func _build_clock_hint() -> void:
	clock_hint = Control.new()
	clock_hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	clock_hint.offset_top = -120
	clock_hint.offset_bottom = -84
	clock_hint.offset_left = -240
	clock_hint.offset_right = 240
	clock_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clock_hint.visible = false
	add_child(clock_hint)
	var panel := PanelContainer.new()
	var sb := _panel_style()
	sb.bg_color = Color(0.0, 0.0, 0.0, 0.7)
	sb.border_color = Color(RABBIT_WHITE, 0.3)
	sb.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel", sb)
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	clock_hint.add_child(panel)
	clock_hint_label = Label.new()
	clock_hint_label.text = CLOCK_HINT_TEXT
	clock_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	clock_hint_label.add_theme_font_size_override("font_size", 15)
	clock_hint_label.add_theme_color_override("font_color", RABBIT_WHITE)
	panel.add_child(clock_hint_label)


func show_clock_hint(on: bool) -> void:
	if on:
		clock_hint_label.text = CLOCK_HINT_TEXT
	clock_hint.visible = on


## The explorer hint box: anchored at the top centre, growing to both sides
## (really centred at any width), at most HINT_MAX_W wide, wrapping.
func _build_hint_box() -> void:
	hint_box = PanelContainer.new()
	hint_box.name = "HintBox"
	hint_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	hint_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hint_box.grow_vertical = Control.GROW_DIRECTION_END
	hint_box.offset_top = HINT_TOP
	hint_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint_box.visible = false
	var sb := _panel_style()
	sb.bg_color = Color(0.0, 0.0, 0.0, 0.72)
	sb.border_color = Color(RABBIT_WHITE, 0.3)
	sb.set_content_margin_all(10)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	hint_box.add_theme_stylebox_override("panel", sb)
	add_child(hint_box)
	hint_label = Label.new()
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.add_theme_font_size_override("font_size", 16)
	hint_label.add_theme_color_override("font_color", RABBIT_WHITE)
	hint_box.add_child(hint_label)


## A short hint (explorer cities: the way, the fold, the exit); hides itself
## after `seconds` of unpaused play unless another text replaced it. The text
## is wrapped here (greedy, by the font's widths) to at most HINT_MAX_W, so the
## box always has its exact size and stays centred.
func show_hint(text: String, seconds: float) -> void:
	var font := hint_label.get_theme_font("font")
	var fs := 16
	var inner := HINT_MAX_W - 32.0
	var lines: Array = []
	var line := ""
	for word in text.split(" ", false):
		var trial := word if line == "" else line + " " + word
		if line != "" and font != null and font.get_string_size(trial, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > inner:
			lines.append(line)
			line = word
		else:
			line = trial
	if line != "":
		lines.append(line)
	var w := 0.0
	for l in lines:
		w = maxf(w, font.get_string_size(l, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x if font != null else 400.0)
	hint_label.text = "\n".join(lines)
	hint_label.set_meta("hint", text)
	hint_box.offset_left = -(w + 34.0) * 0.5
	hint_box.offset_right = (w + 34.0) * 0.5
	hint_box.offset_bottom = hint_box.offset_top
	hint_box.reset_size()
	_hint_left = seconds
	hint_box.visible = pause_panel == null or not pause_panel.visible


func hide_hint() -> void:
	_hint_left = 0.0
	if hint_box != null:
		hint_box.visible = false


func is_hint_visible() -> bool:
	return hint_box != null and hint_box.visible


func hint_text() -> String:
	return String(hint_label.get_meta("hint", "")) if hint_box != null and _hint_left > 0.0 else ""


func _process(delta: float) -> void:
	var paused_now := pause_panel != null and pause_panel.visible
	if _hint_left > 0.0:
		if not paused_now:
			_hint_left -= delta
		hint_box.visible = _hint_left > 0.0 and not paused_now
	if not paused_now:
		_mm_t += delta



func is_clock_hint_visible() -> bool:
	return clock_hint.visible


## UX-K1: the Kippbild with "Effekte reduzieren" — a thin frame round the
## screen (FLIP_FRAME_PX) whose opacity follows the manipulation's "tipped"
## state; the world itself never tips then.
func _build_flip_frame() -> void:
	flip_frame = Control.new()
	flip_frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	flip_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flip_frame.visible = false
	flip_frame.draw.connect(func():
		var s := flip_frame.size
		var c := Color(FLIP_FRAME_COLOR, 0.85 * flip_frame_alpha)
		var w := FLIP_FRAME_PX
		flip_frame.draw_rect(Rect2(0, 0, s.x, w), c)
		flip_frame.draw_rect(Rect2(0, s.y - w, s.x, w), c)
		flip_frame.draw_rect(Rect2(0, w, w, s.y - 2 * w), c)
		flip_frame.draw_rect(Rect2(s.x - w, w, w, s.y - 2 * w), c))
	add_child(flip_frame)


func set_flip_frame(alpha: float) -> void:
	var a := clampf(alpha, 0.0, 1.0)
	if is_equal_approx(a, flip_frame_alpha) and flip_frame.visible == (a > 0.01):
		return
	flip_frame_alpha = a
	flip_frame.visible = a > 0.01
	flip_frame.queue_redraw()


## Condition title card (spec 2.2, UX-W1): symbol, name, second line
## (manipulation / effect, 15 px white), chat line (12 px), on the right
## "GUT ▲" / "SCHLECHT ▼" and the seconds left ("7 s"); green for good,
## magenta for bad. In the last 3 s the bar pulses at 1 Hz. Sits under the
## power bar, top center.
func _build_condition_card() -> void:
	condition_card = PanelContainer.new()
	condition_card.set_anchors_preset(Control.PRESET_CENTER_TOP)
	condition_card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	condition_card.offset_left = -190
	condition_card.offset_right = 190
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
	condition_sub_label.add_theme_font_size_override("font_size", 15)
	condition_sub_label.add_theme_color_override("font_color", Color(1, 1, 1))
	col.add_child(condition_sub_label)
	condition_chat_label = Label.new()
	condition_chat_label.add_theme_font_size_override("font_size", 12)
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
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 2)
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(right)
	condition_kind_label = Label.new()
	condition_kind_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	condition_kind_label.add_theme_font_size_override("font_size", 13)
	right.add_child(condition_kind_label)
	condition_secs_label = Label.new()
	condition_secs_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	condition_secs_label.add_theme_font_size_override("font_size", 20)
	condition_secs_label.add_theme_color_override("font_color", RABBIT_WHITE)
	right.add_child(condition_secs_label)


func show_condition_card(c, chat_line: String = "") -> void:
	condition_color = COND_GOOD if c.is_good else COND_BAD
	condition_icon_kind = c.icon
	condition_name_label.text = c.display_name.to_upper()
	condition_name_label.add_theme_color_override("font_color", condition_color)
	condition_sub_label.text = c.subtitle()
	condition_sub_label.visible = condition_sub_label.text != ""
	condition_chat_label.text = chat_line
	condition_chat_label.visible = chat_line != ""
	condition_kind_label.text = "GUT ▲" if c.is_good else "SCHLECHT ▼"
	condition_kind_label.add_theme_color_override("font_color", condition_color)
	_condition_secs_shown = -1
	condition_fill.bg_color = condition_color
	condition_bar.value = 1.0
	condition_bar.modulate.a = 1.0
	condition_bar_pulse = 1.0
	var sb := _panel_style()
	sb.bg_color = Color(0.02, 0.02, 0.03, 0.9)
	sb.border_color = Color(condition_color, 0.8)
	sb.set_border_width_all(2)
	condition_card.add_theme_stylebox_override("panel", sb)
	condition_card.visible = true
	condition_icon.queue_redraw()
	update_condition_card(c.duration_s, c.duration_s)


## Every frame while a condition runs: bar, seconds (text only when the
## whole second changes) and, in the last 3 s, a 1-Hz pulse of the bar.
func update_condition_card(remaining: float, duration: float) -> void:
	condition_bar.value = clampf(remaining / maxf(duration, 0.001), 0.0, 1.0)
	var secs := int(ceil(maxf(remaining, 0.0)))
	if secs != _condition_secs_shown:
		_condition_secs_shown = secs
		condition_secs_label.text = "%d s" % secs
	if remaining <= CARD_WARN_S:
		var phase := (CARD_WARN_S - remaining) * CARD_PULSE_HZ
		condition_bar_pulse = 0.35 + 0.65 * (0.5 + 0.5 * cos(TAU * phase))
	else:
		condition_bar_pulse = 1.0
	condition_bar.modulate.a = condition_bar_pulse


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
## that on a smaller window it no longer reliably fits — the lower buttons
## could end up pushed off screen with nothing to scroll them into view. The
## comfort block sits right under the title, so it is always visible without
## scrolling. Other panels stay shrink-centered.
## Use _panel_box() to get the actual content box back, since its position
## in the tree differs between the two modes.
func _overlay_panel(scrollable: bool = false) -> PanelContainer:
	var root := PanelContainer.new()
	root.custom_minimum_size = Vector2(480, 0)
	if scrollable:
		root.anchor_left = 0.5
		root.anchor_right = 0.5
		root.anchor_top = 0.04
		root.anchor_bottom = 0.96
		# Centered for real (UX W2): fixed width, grows both ways if its
		# content asks for more.
		root.offset_left = -360
		root.offset_right = 360
		root.offset_top = 0
		root.offset_bottom = 0
		root.grow_horizontal = Control.GROW_DIRECTION_BOTH
	else:
		# QA-W2: grow from the center in both directions, so the panel sits
		# centered instead of hanging from its top-left corner.
		root.set_anchors_preset(Control.PRESET_CENTER)
		root.grow_horizontal = Control.GROW_DIRECTION_BOTH
		root.grow_vertical = Control.GROW_DIRECTION_BOTH
	var sb := _panel_style()
	sb.set_content_margin_all(22)
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
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.alignment = BoxContainer.ALIGNMENT_BEGIN
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
	if versus_ui != null:
		versus_ui.lobby.visible = versus_ui.lobby == panel


func hide_all_panels() -> void:
	start_panel.visible = false
	pause_panel.visible = false
	gameover_panel.visible = false
	leaderboard_panel.visible = false
	if versus_ui != null:
		versus_ui.lobby.visible = false


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


## `chat_blocked`: the score would have been a new high score, but the chat
## helped in this run (Code-W8 Teil 1) — a note says why it does not count.
func show_gameover(score: int, level, highscore: int, chat_blocked: bool = false) -> void:
	final_score_label.text = str(score)
	final_level_label.text = str(level)
	final_hs_label.text = str(highscore)
	gameover_note_label.visible = chat_blocked
	hide_all_panels()
	gameover_panel.visible = true


func show_levelclear(visible_flag: bool, subtitle: String = "", title: String = "LEVEL GESCHAFFT!") -> void:
	levelclear_panel.visible = visible_flag
	if visible_flag:
		levelclear_label.text = title
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


func set_minimap_exits(cells: Array) -> void:
	minimap_exit_cells = cells.duplicate()


func update_minimap(maze, player: Node3D, enemies: Array, frightened: bool, maze_view = null) -> void:
	minimap_maze = maze
	minimap_player = player
	minimap_enemies = enemies
	minimap_frightened = frightened
	minimap_maze_view = maze_view
	minimap.queue_redraw()


## The static layer of the minimap (background, walls, water) as a texture,
## one pixel per cell, painted once per maze and theme (code H3); drawn
## scaled with nearest filtering.
func minimap_static_texture() -> ImageTexture:
	if minimap_maze == null:
		return null
	var ct = minimap_maze_view.city_theme if minimap_maze_view != null and minimap_maze_view.city_theme != null else null
	var key := [minimap_maze.get_instance_id(), ct.id if ct != null else "", ct.minimap_wall_color if ct != null else Color()]
	if _mm_static_tex != null and key == _mm_static_key:
		return _mm_static_tex
	var bg_col: Color = ct.minimap_bg_color if ct != null else Color(0.008, 0.012, 0.039, 0.4)
	var wall_col: Color = ct.minimap_wall_color if ct != null else Color(0.118, 0.227, 0.478)
	var water_script = ct.minimap_water_script if ct != null else null
	var water_col: Color = ct.minimap_water_color if ct != null else Color(0, 0, 0, 0)
	var img := Image.create(minimap_maze.cols, minimap_maze.rows, false, Image.FORMAT_RGBA8)
	for r in minimap_maze.rows:
		for c in minimap_maze.cols:
			var col := bg_col
			if minimap_maze.grid[r][c] == 1:
				col = wall_col
				if water_script != null and water_script.is_water(r, c):
					col = water_col
			img.set_pixel(c, r, col)
	_mm_static_tex = ImageTexture.create_from_image(img)
	_mm_static_key = key
	return _mm_static_tex


func _draw_minimap() -> void:
	if minimap_maze == null:
		return
	var size := minimap.size
	var sx: float = size.x / float(minimap_maze.cols)
	var sy: float = size.y / float(minimap_maze.rows)
	# Colors follow the level's CityTheme (Speedrun: turquoise walls, never
	# blue; cream pickups); the defaults are the original minimap colors.
	var ct = minimap_maze_view.city_theme if minimap_maze_view != null and minimap_maze_view.city_theme != null else null
	var pellet_col: Color = ct.pellet_color if ct != null else Color(1.0, 0.82, 0.4)
	var power_col: Color = ct.power_color if ct != null else Color(1.0, 0.365, 0.635)
	var frightened_col: Color = ct.minimap_frightened_color if ct != null else Color(0.35, 0.82, 1.0)
	var pellet_rim: Color = ct.minimap_pellet_outline if ct != null else Color(0, 0, 0, 0)
	# static layer: background, walls, canals (Amsterdam) / quay (Arles)
	minimap.draw_texture_rect(minimap_static_texture(), Rect2(Vector2.ZERO, size), false)
	if minimap_maze_view != null:
		for i in minimap_maze_view.pellet_cells.size():
			if not minimap_maze_view.pellet_alive[i]:
				continue
			var pc: Vector2i = minimap_maze_view.pellet_cells[i]
			if pellet_rim.a > 0.0: # Arles: a dark ring keeps the pellets readable
				minimap.draw_circle(Vector2((pc.y + 0.5) * sx, (pc.x + 0.5) * sy), 1.6, pellet_rim)
			minimap.draw_circle(Vector2((pc.y + 0.5) * sx, (pc.x + 0.5) * sy), 0.9, pellet_col)
		for i in minimap_maze_view.power_cells.size():
			if not minimap_maze_view.power_alive[i]:
				continue
			var pw: Vector2i = minimap_maze_view.power_cells[i]
			minimap.draw_circle(Vector2((pw.y + 0.5) * sx, (pw.x + 0.5) * sy), 1.6, power_col)
		# The white rabbit is visible on the minimap from the level start on
		# (spec 2.2): a small rabbit-ear symbol (UX-W2) — two upright ears on
		# a round head, rabbit white with a dark outline.
		if minimap_maze_view.rabbit_alive:
			var rc: Vector2i = minimap_maze_view.rabbit_cell
			_draw_rabbit_ears(Vector2((rc.y + 0.5) * sx, (rc.x + 0.5) * sy))
	# Review findings GD-K4/UX-K2/Code-W11: the player's real facing
	# direction is (-sin(yaw), -cos(yaw)) (see player_controller.gd's
	# _physics_process), so the arrow is rotated by -yaw; player and enemy
	# markers sit on the cell centre (+0.5) like the pellets.
	for e in minimap_enemies:
		var col: Color = frightened_col if minimap_frightened else e.palette_color
		minimap.draw_circle(Vector2((e.position.x / 2.0 + 0.5) * sx, (e.position.z / 2.0 + 0.5) * sy), 2.4, col)
	# Explorer exits (UX K-A, QA K3): told by shape, not only by colour - a
	# ring glyph (target), larger than the player arrow, with a dark rim; a
	# 0.5 Hz halo ring unless effects are reduced.
	var exit_col: Color = ct.minimap_exit_color if ct != null else Color(0.22, 1.0, 0.42)
	if exit_col.a > 0.0:
		for xc in minimap_exit_cells:
			_draw_exit_glyph(Vector2((xc.y + 0.5) * sx, (xc.x + 0.5) * sy), exit_col)
	# Versus: the opponent's position in their own copy of the maze (E17).
	if minimap_opponent_cell.x >= 0:
		var oc := Vector2((minimap_opponent_cell.y + 0.5) * sx, (minimap_opponent_cell.x + 0.5) * sy)
		minimap.draw_circle(oc, 4.2, Color(0, 0, 0))
		minimap.draw_circle(oc, 3.2, Color("ff9f1c")) # VersusUI.OPP_COLOR, own orange (QA N2)
	if minimap_player != null:
		var yaw: float = minimap_player.yaw if "yaw" in minimap_player else 0.0
		var arrow := _minimap_arrow(Vector2((minimap_player.global_position.x / 2.0 + 0.5) * sx, (minimap_player.global_position.z / 2.0 + 0.5) * sy), yaw)
		if _explorer_hud:
			# explorer cities: white arrow, 1.5 px black rim (cyan stays for text and frames)
			for rim in Geometry2D.offset_polygon(arrow, 1.5, Geometry2D.JOIN_MITER):
				minimap.draw_colored_polygon(rim, Color(0, 0, 0))
			minimap.draw_colored_polygon(arrow, MINIMAP_PLAYER_EXPLORER)
		else:
			minimap.draw_colored_polygon(arrow, ACCENT)


## The exit marker: a dark-rimmed ring (outer radius EXIT_GLYPH_R, ~10 px
## across) with a dot in the middle, plus a slow halo ring (0.5 Hz).
const EXIT_GLYPH_R := 5.5


func _draw_exit_glyph(p: Vector2, col: Color) -> void:
	if exit_glyph_pulsing():
		var ph := fmod(_mm_t * MINIMAP_EXIT_PULSE_HZ, 1.0)
		minimap.draw_arc(p, EXIT_GLYPH_R + 1.0 + ph * 4.0, 0.0, TAU, 24, Color(col, 0.7 * (1.0 - ph)), 1.4, true)
	minimap.draw_circle(p, EXIT_GLYPH_R + 1.5, Color(0, 0, 0))
	minimap.draw_arc(p, EXIT_GLYPH_R - 0.9, 0.0, TAU, 24, col, 2.2, true)
	minimap.draw_circle(p, 1.6, col)


## Whether the minimap's exit ring pulses (not with "Effekte reduzieren").
func exit_glyph_pulsing() -> bool:
	return not _reduce_fx


## The minimap's rabbit marker: head plus two ears, ~9 px tall.
func _draw_rabbit_ears(p: Vector2) -> void:
	var outline := Color(0, 0, 0)
	for ex in [-1.3, 1.3]:
		var ear := Rect2(p.x + ex - 1.1, p.y - 6.2, 2.2, 5.0)
		minimap.draw_rect(ear.grow(0.8), outline)
	minimap.draw_circle(p + Vector2(0, 1.0), 3.3, outline)
	for ex in [-1.3, 1.3]:
		minimap.draw_rect(Rect2(p.x + ex - 1.1, p.y - 6.2, 2.2, 5.0), RABBIT_WHITE)
	minimap.draw_circle(p + Vector2(0, 1.0), 2.5, RABBIT_WHITE)


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
