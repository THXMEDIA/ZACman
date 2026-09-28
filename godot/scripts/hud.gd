extends CanvasLayer
## Hud — score/level/lives, minimap, power-timer bar, and the start / pause /
## game-over / level-clear overlays. Built entirely in code (no .tscn UI tree
## to keep in sync by hand).

signal start_pressed
signal resume_pressed
signal restart_pressed

const BG := Color(0.035, 0.055, 0.11, 0.86)
const BORDER := Color(0.31, 0.66, 1.0, 0.35)
const ACCENT := Color(0.2, 0.878, 1.0)
const PELLET_COLOR := Color(1.0, 0.82, 0.4)
const POWER_COLOR := Color(1.0, 0.365, 0.635)
const DANGER := Color(1.0, 0.231, 0.365)

var score_label: Label
var level_label: Label
var lives_box: HBoxContainer
var power_bar: ProgressBar
var power_wrap: Control
var minimap: Control

var start_panel: PanelContainer
var pause_panel: PanelContainer
var gameover_panel: PanelContainer
var levelclear_label: Label

var final_score_label: Label
var final_level_label: Label
var final_hs_label: Label
var start_hs_label: Label

var minimap_maze = null
var minimap_view = null
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

	var lives_chip := PanelContainer.new()
	lives_chip.add_theme_stylebox_override("panel", _panel_style())
	left.add_child(lives_chip)
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
	start_panel = _overlay_panel()
	var box := start_panel.get_child(0)
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

	var btn := _make_button("SPIEL STARTEN")
	btn.pressed.connect(func(): start_pressed.emit())
	box.add_child(btn)


func _build_pause_panel() -> void:
	pause_panel = _overlay_panel()
	pause_panel.visible = false
	var box := pause_panel.get_child(0)
	box.add_child(_title_label("PAUSE"))
	box.add_child(_subtitle_label("Das Labyrinth wartet."))
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
	levelclear_label = _title_label("LEVEL GESCHAFFT!", 20)
	levelclear_label.set_anchors_preset(Control.PRESET_CENTER)
	levelclear_label.visible = false
	add_child(levelclear_label)


func _overlay_panel() -> PanelContainer:
	var root := PanelContainer.new()
	root.set_anchors_preset(Control.PRESET_CENTER)
	root.custom_minimum_size = Vector2(420, 0)
	var sb := _panel_style()
	sb.set_content_margin_all(26)
	sb.bg_color = Color(0.035, 0.055, 0.11, 0.97)
	root.add_theme_stylebox_override("panel", sb)
	add_child(root)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(box)
	return root


func show_only(panel: Control) -> void:
	for p in [start_panel, pause_panel, gameover_panel]:
		p.visible = p == panel


func hide_all_panels() -> void:
	start_panel.visible = false
	pause_panel.visible = false
	gameover_panel.visible = false


func set_score(v: int) -> void:
	score_label.text = str(v)


func set_level(v: int) -> void:
	level_label.text = str(v)


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


func show_gameover(score: int, level: int, highscore: int) -> void:
	final_score_label.text = str(score)
	final_level_label.text = str(level)
	final_hs_label.text = str(highscore)
	hide_all_panels()
	gameover_panel.visible = true


func show_levelclear(visible_flag: bool) -> void:
	levelclear_label.visible = visible_flag


## Minimap: fed a maze + player + enemies each frame by Main, drawn via _draw().
func update_minimap(maze, player: Node3D, enemies: Array, frightened: bool) -> void:
	minimap_maze = maze
	minimap_player = player
	minimap_enemies = enemies
	minimap_frightened = frightened
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
	for e in minimap_enemies:
		var col: Color = Color(0.35, 0.82, 1.0) if minimap_frightened else e.palette_color
		minimap.draw_circle(Vector2((e.position.x / 2.0) * sx, (e.position.z / 2.0) * sy), 2.4, col)
	if minimap_player != null:
		var pr := minimap_player.global_position.x / 2.0
		var pc := minimap_player.global_position.z / 2.0
		var yaw: float = minimap_player.yaw if minimap_player.has_method("cell") else 0.0
		var pts := PackedVector2Array([Vector2(0, -4.2), Vector2(3, 3.6), Vector2(-3, 3.6)])
		var rotated := PackedVector2Array()
		for p in pts:
			var rp := p.rotated(yaw)
			rotated.append(Vector2(pr * sx, pc * sy) + rp)
		minimap.draw_colored_polygon(rotated, ACCENT)
