extends CanvasLayer
## Hud — score/level/lives, minimap, power-timer bar, and the start / pause /
## game-over / level-clear overlays. Built entirely in code (no .tscn UI tree
## to keep in sync by hand).

signal start_pressed
signal resume_pressed
signal restart_pressed
signal manhattan_pressed
signal condition_selected(condition_id: String)
signal twitch_toggled(is_enabled: bool, channel: String)

const ConditionsScript := preload("res://scripts/conditions.gd")

const BG := Color(0.035, 0.055, 0.11, 0.86)
const BORDER := Color(0.31, 0.66, 1.0, 0.35)
const ACCENT := Color(0.2, 0.878, 1.0)
const PELLET_COLOR := Color(1.0, 0.82, 0.4)
const POWER_COLOR := Color(1.0, 0.365, 0.635)
const DANGER := Color(1.0, 0.231, 0.365)

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
var mode_label: Label
var condition_option: OptionButton
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
	_build_levelclear_label()


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
	mode_label = _make_chip(left, "MODUS", "")
	mode_label.get_parent().get_parent().visible = false
	timed_chips = [score_label.get_parent().get_parent(), timer_label.get_parent().get_parent(), best_label.get_parent().get_parent()]

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
	set_mode_badge("")


## Shows a run-mode badge under the best time ("CHAT" once a chat command took
## effect in this level — its time goes to the chat board). "" hides it.
func set_mode_badge(text: String) -> void:
	mode_label.text = text
	mode_label.get_parent().get_parent().visible = text != ""


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
	twitch_toggle.text = "Twitch-Chat-Effekte (!power, !fruit)"
	twitch_row.add_child(twitch_toggle)
	twitch_channel_edit = LineEdit.new()
	twitch_channel_edit.placeholder_text = "twitch-kanal"
	twitch_channel_edit.custom_minimum_size = Vector2(130, 0)
	twitch_row.add_child(twitch_channel_edit)
	twitch_toggle.toggled.connect(func(pressed: bool): twitch_toggled.emit(pressed, twitch_channel_edit.text))

	twitch_status_label = _subtitle_label("Aus — fuer ernsthafte Speedruns ausgeschaltet lassen.")
	twitch_status_label.add_theme_font_size_override("font_size", 11)
	box.add_child(twitch_status_label)

	var mode_tag := _subtitle_label("WÄHLE DEINEN MODUS")
	mode_tag.add_theme_font_size_override("font_size", 11)
	box.add_child(mode_tag)

	var btn := _make_button("MATRIX-LEVEL")
	btn.pressed.connect(func(): start_pressed.emit())
	box.add_child(btn)
	var matrix_sub := _subtitle_label("Zufälliges Level, Geister, Zeitjagd. Bestzeiten und Bestenlisten gibt es pro Level, Kondition und Modus (Solo, Chat).")
	matrix_sub.add_theme_font_size_override("font_size", 11)
	box.add_child(matrix_sub)

	var cond_row := HBoxContainer.new()
	cond_row.alignment = BoxContainer.ALIGNMENT_CENTER
	cond_row.add_theme_constant_override("separation", 8)
	box.add_child(cond_row)
	var cond_tag := Label.new()
	cond_tag.text = "KONDITION"
	cond_tag.add_theme_color_override("font_color", Color(0.56, 0.64, 0.78))
	cond_tag.add_theme_font_size_override("font_size", 12)
	cond_row.add_child(cond_tag)
	condition_option = OptionButton.new()
	condition_option.custom_minimum_size = Vector2(190, 0)
	for id in ConditionsScript.SELECTABLE_IDS:
		condition_option.add_item(ConditionsScript.display_name_for(id))
	condition_option.item_selected.connect(func(i: int): condition_selected.emit(ConditionsScript.SELECTABLE_IDS[i]))
	cond_row.add_child(condition_option)

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


func _build_levelclear_label() -> void:
	levelclear_panel = VBoxContainer.new()
	levelclear_panel.add_theme_constant_override("separation", 6)
	levelclear_panel.set_anchors_preset(Control.PRESET_CENTER)
	levelclear_panel.alignment = BoxContainer.ALIGNMENT_CENTER
	levelclear_panel.visible = false
	add_child(levelclear_panel)
	levelclear_label = _title_label("LEVEL GESCHAFFT!", 20)
	levelclear_panel.add_child(levelclear_label)
	levelclear_sub = _subtitle_label("")
	levelclear_sub.add_theme_color_override("font_color", PELLET_COLOR)
	levelclear_panel.add_child(levelclear_sub)


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
		root.set_anchors_preset(Control.PRESET_CENTER)
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
	for p in [start_panel, pause_panel, gameover_panel]:
		p.visible = p == panel


func hide_all_panels() -> void:
	start_panel.visible = false
	pause_panel.visible = false
	gameover_panel.visible = false


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


func set_best_time(seconds: float) -> void:
	best_label.text = Speedrun.format_time(seconds)


## Minimap: fed a maze + player + enemies + maze_view (for the pellets —
## consumed pickups just aren't drawn anymore, same pellet_alive/power_alive
## arrays MazeView already keeps, nothing new to track here) each frame by
## Main, drawn via _draw().
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
	minimap.draw_rect(Rect2(Vector2.ZERO, size), Color(0.008, 0.012, 0.039, 0.4))
	for r in minimap_maze.rows:
		for c in minimap_maze.cols:
			if minimap_maze.grid[r][c] == 1:
				minimap.draw_rect(Rect2(c * sx, r * sy, sx + 0.6, sy + 0.6), Color(0.118, 0.227, 0.478))
	if minimap_maze_view != null:
		for i in minimap_maze_view.pellet_cells.size():
			if not minimap_maze_view.pellet_alive[i]:
				continue
			var pc: Vector2i = minimap_maze_view.pellet_cells[i]
			minimap.draw_circle(Vector2((pc.y + 0.5) * sx, (pc.x + 0.5) * sy), 0.9, Color(1.0, 0.82, 0.4))
		for i in minimap_maze_view.power_cells.size():
			if not minimap_maze_view.power_alive[i]:
				continue
			var pw: Vector2i = minimap_maze_view.power_cells[i]
			minimap.draw_circle(Vector2((pw.y + 0.5) * sx, (pw.x + 0.5) * sy), 1.6, Color(1.0, 0.365, 0.635))
	for e in minimap_enemies:
		var col: Color = Color(0.35, 0.82, 1.0) if minimap_frightened else e.palette_color
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
