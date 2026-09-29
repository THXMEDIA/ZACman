extends Node3D
## Main — game orchestrator: level lifecycle, scoring, lives, input wiring,
## enemy/pickup collision. Direct port of the web prototype's game.js logic
## (see web/index.html) onto Godot nodes; MazeGen supplies the same kind of
## verified-connected maze.

const CELL := 2.0
const FRIGHTENED_DURATION := 7.0
const HIGHSCORE_PATH := "user://kugelschlucker_highscore.txt"

const LEVELS := [
	{"rows": 19, "cols": 21, "ghost_speed": 2.0, "ghost_count": 3, "seed_base": 10000},
	{"rows": 21, "cols": 25, "ghost_speed": 2.25, "ghost_count": 4, "seed_base": 20000},
	{"rows": 23, "cols": 27, "ghost_speed": 2.5, "ghost_count": 4, "seed_base": 30000},
	{"rows": 23, "cols": 29, "ghost_speed": 2.75, "ghost_count": 5, "seed_base": 40000},
]

const MANHATTAN_GHOST_SPEED := 3.0
const MANHATTAN_GHOST_COUNT := 6

const ENEMY_PALETTE := [
	{"color": Color(1.0, 0.231, 0.365), "glow": Color(1.0, 0.42, 0.514)},
	{"color": Color(1.0, 0.365, 0.635), "glow": Color(1.0, 0.62, 0.788)},
	{"color": Color(0.2, 0.878, 1.0), "glow": Color(0.616, 0.953, 1.0)},
	{"color": Color(1.0, 0.655, 0.2), "glow": Color(1.0, 0.816, 0.541)},
	{"color": Color(0.616, 0.361, 1.0), "glow": Color(0.788, 0.639, 1.0)},
]

var hud
var player: CharacterBody3D
var maze_view: Node3D
var enemy_root: Node3D

var maze # MazeGen.Maze
var level_index := 0
var score := 0
var lives := 3
var high_score := 0
var running := false
var paused := false
var frightened_until := 0.0
var combo_count := 0
var invuln_until := 0.0
var start_cell := Vector2i(1, 1)
var fruit_spawned := false
var now := 0.0
var level_start_time := 0.0
var playing_manhattan := false

var enemies: Array = [] # Array[Enemy]


func _ready() -> void:
	high_score = _load_highscore()
	_build_environment()
	_build_player()
	_build_hud()
	maze_view = Node3D.new()
	maze_view.set_script(load("res://scripts/maze_view.gd"))
	add_child(maze_view)
	enemy_root = Node3D.new()
	add_child(enemy_root)

	hud.set_start_highscore(high_score)
	hud.set_bonus_unlocked(Speedrun.is_bonus_unlocked())
	hud.show_only(hud.start_panel)


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.0196, 0.0275, 0.0627)
	env.fog_enabled = true
	env.fog_light_color = Color(0.0196, 0.0275, 0.0627)
	env.fog_density = 0.03
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.165, 0.227, 0.4)
	env.ambient_light_energy = 0.9
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


func _build_player() -> void:
	player = CharacterBody3D.new()
	player.set_script(load("res://scripts/player_controller.gd"))
	add_child(player)
	player.input_enabled = false


func _build_hud() -> void:
	hud = CanvasLayer.new()
	hud.set_script(load("res://scripts/hud.gd"))
	add_child(hud)
	hud.start_pressed.connect(_on_start_pressed)
	hud.resume_pressed.connect(_on_resume_pressed)
	hud.restart_pressed.connect(_on_restart_pressed)
	hud.manhattan_pressed.connect(_on_manhattan_pressed)
	hud.twitch_toggled.connect(_on_twitch_toggled)
	Twitch.chat_command.connect(_on_twitch_command)
	Twitch.connection_state_changed.connect(_on_twitch_connection_changed)


## ---------------- level lifecycle ----------------

func start_level(index: int) -> void:
	var cfg: Dictionary = LEVELS[mini(index, LEVELS.size() - 1)]
	var extra := maxi(0, index - (LEVELS.size() - 1))
	maze = MazeGen.generate_maze(cfg.rows, cfg.cols, cfg.seed_base + index * 77 + 3)

	var rooms: Array = MazeGen.cells_in_room(maze, false)
	var best: Vector2i = rooms[rooms.size() - 1]
	var best_r := -1
	for cell in rooms:
		if cell.x <= maze.house.r1:
			continue
		if cell.x > best_r:
			best_r = cell.x
			best = cell
	start_cell = best

	level_index = index
	maze_view.build(maze, start_cell)
	fruit_spawned = false

	player.warp_to(start_cell, PI)
	invuln_until = now + 1.2

	for e in enemies:
		e.queue_free()
	enemies.clear()
	var house_cells := []
	for r in range(maze.house.r0 + 1, maze.house.r1):
		for c in range(maze.house.c0 + 1, maze.house.c1):
			house_cells.append(Vector2i(r, c))

	var ghost_count: int = cfg.ghost_count + mini(extra, 3)
	for i in ghost_count:
		var enemy := Node3D.new()
		enemy.set_script(load("res://scripts/enemy.gd"))
		enemy_root.add_child(enemy)
		var pal: Dictionary = ENEMY_PALETTE[i % ENEMY_PALETTE.size()]
		enemy.setup(pal.color, pal.glow, cfg.ghost_speed + i * 0.05 + extra * 0.15)
		var cell: Vector2i = house_cells[i % house_cells.size()]
		enemy.place_in_house(cell)
		enemy.release_at = now + 1.5 + i * 1.4
		enemies.append(enemy)

	hud.set_level(level_index + 1)
	hud.set_score(score)
	hud.set_lives(lives)
	hud.set_best_time(Speedrun.best_for(level_index))
	level_start_time = now


func begin_game() -> void:
	Sfx.stop_all()
	score = 0
	lives = 3
	playing_manhattan = false
	hud.hide_all_panels()
	start_level(0)
	running = true
	paused = false
	player.input_enabled = true
	Sfx.set_siren(true, false)
	if not OS.has_feature("web"):
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


## ---------------- Manhattan bonus level ----------------
## Unlocked by Speedrun.is_bonus_unlocked() (beating a level's speedrun
## target — see Speedrun.record_level_time). Reuses every normal-level
## system (MazeView, Enemy, pickups, scoring, pause) against a hand-built
## real-Midtown-grid Maze instead of a MazeGen.generate_maze() result.
func start_manhattan_level() -> void:
	var mm = load("res://scripts/manhattan_maze.gd").new()
	maze = mm.generate()
	mm.free()

	start_cell = maze.start_cell
	level_index = -1
	maze_view.build(maze, start_cell)
	fruit_spawned = false

	player.warp_to(start_cell, PI)
	invuln_until = now + 1.2

	for e in enemies:
		e.queue_free()
	enemies.clear()
	var house_cells := []
	for r in range(maze.house.r0 + 1, maze.house.r1):
		for c in range(maze.house.c0 + 1, maze.house.c1):
			house_cells.append(Vector2i(r, c))

	for i in MANHATTAN_GHOST_COUNT:
		var enemy := Node3D.new()
		enemy.set_script(load("res://scripts/enemy.gd"))
		enemy_root.add_child(enemy)
		var pal: Dictionary = ENEMY_PALETTE[i % ENEMY_PALETTE.size()]
		enemy.setup(pal.color, pal.glow, MANHATTAN_GHOST_SPEED + i * 0.05)
		var cell: Vector2i = house_cells[i % house_cells.size()]
		enemy.place_in_house(cell)
		enemy.release_at = now + 1.5 + i * 1.4
		enemies.append(enemy)

	hud.set_level("MANHATTAN")
	hud.set_score(score)
	hud.set_lives(lives)
	hud.set_best_time(-1.0)
	level_start_time = now


func begin_manhattan_game() -> void:
	Sfx.stop_all()
	score = 0
	lives = 3
	playing_manhattan = true
	hud.hide_all_panels()
	start_manhattan_level()
	running = true
	paused = false
	player.input_enabled = true
	Sfx.set_siren(true, false)
	if not OS.has_feature("web"):
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func manhattan_complete_sequence() -> void:
	running = false
	Sfx.set_siren(false, false)
	Sfx.level_clear()
	if score > high_score:
		high_score = score
		_save_highscore(high_score)
	hud.show_levelclear(true, "Manhattan bezwungen! Punkte " + str(score))
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	await get_tree().create_timer(2.2).timeout
	hud.show_levelclear(false)
	playing_manhattan = false
	Sfx.stop_all()
	hud.set_start_highscore(high_score)
	hud.set_bonus_unlocked(Speedrun.is_bonus_unlocked())
	hud.show_only(hud.start_panel)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	player.input_enabled = false


func _on_manhattan_pressed() -> void:
	begin_manhattan_game()


## ---------------- Twitch chat (optional, opt-in) ----------------

func _on_twitch_toggled(is_enabled: bool, channel: String) -> void:
	Twitch.enabled = is_enabled
	if is_enabled:
		if channel.strip_edges() == "":
			hud.set_twitch_status("Bitte einen Twitch-Kanalnamen eingeben.")
			Twitch.enabled = false
			return
		hud.set_twitch_status("Verbinde mit #%s ..." % channel.strip_edges().to_lower())
		Twitch.connect_to_channel(channel)
	else:
		Twitch.disconnect_chat()
		hud.set_twitch_status("Aus — fuer ernsthafte Speedruns ausgeschaltet lassen.")


func _on_twitch_connection_changed(is_connected: bool) -> void:
	if is_connected:
		hud.set_twitch_status("Verbunden mit #%s — !power und !fruit sind aktiv." % Twitch.channel)
	elif Twitch.enabled:
		hud.set_twitch_status("Verbindung getrennt.")


## Viewer chat commands, opt-in only (see Twitch.enabled / the start-screen
## toggle). Deliberately small and harmless: they can only help the player
## (early power pellet, early fruit), never take away input or end the run,
## so turning this on can't be used to grief a streamer's run.
func _on_twitch_command(_user: String, command: String, _args: String) -> void:
	if not (running and not paused):
		return
	match command:
		"power":
			frightened_until = now + FRIGHTENED_DURATION
			combo_count = 0
			Sfx.power()
			Sfx.set_siren(true, true)
			for enemy in enemies:
				if enemy.mode == "chase":
					enemy.mode = "frightened"
		"fruit":
			if not fruit_spawned:
				fruit_spawned = true
				maze_view.spawn_fruit(now)


func next_level() -> void:
	invuln_until = now + 0.5
	start_level(level_index + 1)


func lose_life() -> void:
	lives -= 1
	Sfx.death()
	hud.set_lives(lives)
	if lives <= 0:
		end_game()
		return
	player.warp_to(start_cell, PI)
	invuln_until = now + 1.6
	var house_cells := []
	for r in range(maze.house.r0 + 1, maze.house.r1):
		for c in range(maze.house.c0 + 1, maze.house.c1):
			house_cells.append(Vector2i(r, c))
	for i in enemies.size():
		var cell: Vector2i = house_cells[i % house_cells.size()]
		enemies[i].send_to_house(cell, now, 1.2 + i * 1.2)


func end_game() -> void:
	running = false
	Sfx.stop_all()
	if score > high_score:
		high_score = score
		_save_highscore(high_score)
	var level_display = "MANHATTAN" if playing_manhattan else level_index + 1
	hud.show_gameover(score, level_display, high_score)
	hud.set_bonus_unlocked(Speedrun.is_bonus_unlocked())
	playing_manhattan = false
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func level_complete_sequence() -> void:
	running = false
	Sfx.set_siren(false, false)
	Sfx.level_clear()

	var elapsed := now - level_start_time
	var result := Speedrun.record_level_time(level_index, elapsed)
	var subtitle := "Zeit " + Speedrun.format_time(elapsed)
	if result.newly_unlocked_bonus:
		subtitle += "  ·  BONUSLEVEL FREIGESCHALTET!"
		Sfx.eat_enemy()
		hud.set_bonus_unlocked(true)
	elif result.is_new_best:
		subtitle += "  ·  neue Bestzeit!"
	elif result.beat_target:
		subtitle += "  ·  unter Zielzeit " + Speedrun.format_time(result.target)
	hud.set_best_time(Speedrun.best_for(level_index))

	hud.show_levelclear(true, subtitle)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	await get_tree().create_timer(1.7).timeout
	hud.show_levelclear(false)
	next_level()
	running = true
	Sfx.set_siren(true, false)
	if not OS.has_feature("web"):
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


## ---------------- UI callbacks ----------------

func _on_start_pressed() -> void:
	begin_game()


func _on_resume_pressed() -> void:
	toggle_pause()


func _on_restart_pressed() -> void:
	hud.hide_all_panels()
	begin_game()


func toggle_pause() -> void:
	if not running:
		return
	paused = not paused
	if paused:
		hud.show_only(hud.pause_panel)
		Sfx.set_siren(false, false)
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		player.input_enabled = false
	else:
		hud.hide_all_panels()
		Sfx.set_siren(true, now < frightened_until)
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		player.input_enabled = true


## ---------------- main loop ----------------

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause_toggle"):
		toggle_pause()
	if running and not paused and event is InputEventMouseButton and event.pressed:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _process(delta: float) -> void:
	now += delta
	if not (running and not paused):
		return

	player.wrap_tunnel(maze.cols * CELL)

	var frightened_active := now < frightened_until
	var player_cell: Vector2i = player.cell()
	var world_width: float = maze.cols * CELL

	for enemy in enemies:
		enemy.update(delta, maze, player_cell, frightened_active, now, world_width)
		_check_enemy_collision(enemy, frightened_active)

	_check_pickups()

	hud.set_timer(now - level_start_time)
	hud.set_power_timer(frightened_until - now, FRIGHTENED_DURATION)
	if now >= frightened_until and Sfx.siren_state() == "frightened":
		Sfx.set_siren(true, false)
	hud.update_minimap(maze, player, enemies, frightened_active)


func _check_enemy_collision(enemy, frightened_active: bool) -> void:
	if enemy.mode == "eaten":
		if now >= enemy.eaten_until:
			var house_cells := []
			for r in range(maze.house.r0 + 1, maze.house.r1):
				for c in range(maze.house.c0 + 1, maze.house.c1):
					house_cells.append(Vector2i(r, c))
			var idx := enemies.find(enemy)
			var cell: Vector2i = house_cells[idx % house_cells.size()]
			enemy.send_to_house(cell, now, 3.0)
		return
	if now <= invuln_until:
		return
	var d := Vector2(enemy.position.x - player.global_position.x, enemy.position.z - player.global_position.z).length()
	if d < 0.62:
		if frightened_active:
			enemy.mode = "eaten"
			enemy.eaten_until = now + 2.2
			combo_count += 1
			var pts := 200 * int(pow(2, mini(combo_count - 1, 3)))
			score += pts
			Sfx.eat_enemy()
			hud.set_score(score)
		else:
			lose_life()


func _check_pickups() -> void:
	var result: Dictionary = maze_view.consume_at(player.global_position, now)
	if result.pellet:
		score += 10
	if result.power:
		score += 50
		frightened_until = now + FRIGHTENED_DURATION
		combo_count = 0
		Sfx.power()
		Sfx.set_siren(true, true)
		for enemy in enemies:
			if enemy.mode == "chase":
				enemy.mode = "frightened"
	if result.fruit:
		score += 150 + level_index * 50
		Sfx.fruit()
	if result.pellet or result.power:
		Sfx.munch()
	if result.pellet or result.power or result.fruit:
		hud.set_score(score)

	var total: int = maze_view.total_pickups()
	var eaten: int = total - maze_view.remaining_pickups()
	if not fruit_spawned and total > 0 and eaten >= int(total * 0.4):
		fruit_spawned = true
		maze_view.spawn_fruit(now)

	if maze_view.remaining_pickups() <= 0 and running:
		if playing_manhattan:
			manhattan_complete_sequence()
		else:
			level_complete_sequence()


## ---------------- high score persistence ----------------

func _load_highscore() -> int:
	if not FileAccess.file_exists(HIGHSCORE_PATH):
		return 0
	var f := FileAccess.open(HIGHSCORE_PATH, FileAccess.READ)
	if f == null:
		return 0
	var v := f.get_as_text().strip_edges()
	f.close()
	return v.to_int()


func _save_highscore(v: int) -> void:
	var f := FileAccess.open(HIGHSCORE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(str(v))
	f.close()
