extends Node3D
## Main — game orchestrator: level lifecycle, scoring, lives, input wiring,
## enemy/pickup collision. Direct port of the web prototype's game.js logic
## (see web/index.html) onto Godot nodes; MazeGen supplies the same kind of
## verified-connected maze.

const CELL := 2.0
const FRIGHTENED_DURATION := 7.0
const WORD_MODE_DURATION := 12.0
const HIGHSCORE_PATH := "user://kugelschlucker_highscore.txt"

const LEVELS := [
	{"rows": 19, "cols": 21, "ghost_speed": 2.0, "ghost_count": 3, "seed_base": 10000},
	{"rows": 21, "cols": 25, "ghost_speed": 2.25, "ghost_count": 4, "seed_base": 20000},
	{"rows": 23, "cols": 27, "ghost_speed": 2.5, "ghost_count": 4, "seed_base": 30000},
	{"rows": 23, "cols": 29, "ghost_speed": 2.75, "ghost_count": 5, "seed_base": 40000},
]

## Manhattan has no ghosts (see manhattan_maze.gd's header) — it's a calm
## explore level. Taxis and pedestrians are its only obstacles: harmless,
## just something to walk around (Main._check_manhattan_obstacles).
const MANHATTAN_TAXI_ROW_COUNT := 3
const MANHATTAN_TAXI_COL_COUNT := 2
const MANHATTAN_PEDESTRIAN_COUNT := 10
const MANHATTAN_OBSTACLE_RADIUS := 0.55
const MANHATTAN_METRO_COUNT := 4
const MANHATTAN_METRO_RADIUS := 0.75
const MANHATTAN_LIMO_COLOR := Color(0.82, 0.86, 0.95) # chrome/silver
const MANHATTAN_TAXI_COLOR := Color(1.0, 0.82, 0.05)

## Manhattan's neo-noir cyberpunk ambience — swapped in over the normal
## levels' cooler blue while playing_manhattan (see _apply_manhattan_environment).
const MANHATTAN_BG_COLOR := Color(0.02, 0.006, 0.05)
const MANHATTAN_FOG_COLOR := Color(0.35, 0.02, 0.4)
const MANHATTAN_AMBIENT_COLOR := Color(0.5, 0.08, 0.55)
const NORMAL_BG_COLOR := Color(0.0196, 0.0275, 0.0627)
const NORMAL_FOG_COLOR := Color(0.0196, 0.0275, 0.0627)
const NORMAL_AMBIENT_COLOR := Color(0.165, 0.227, 0.4)

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
var word_mode_until := 0.0

var enemies: Array = [] # Array[Enemy]
var taxis: Array = [] # Array[Taxi] — Manhattan only
var pedestrians: Array = [] # Array[Pedestrian] — Manhattan only (Pedestrian, ManWalkingDog or KidGroup)
var metro_stations: Array = [] # Array[MetroStation] — Manhattan only
var obstacle_root: Node3D
var world_env: WorldEnvironment


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
	obstacle_root = Node3D.new()
	add_child(obstacle_root)

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
	env.ambient_light_color = NORMAL_AMBIENT_COLOR
	env.ambient_light_energy = 0.9
	world_env = WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)


## Toggles the whole scene's ambience between the normal levels' cool blue
## and Manhattan's neon Neo-Noir Cyberpunk palette (magenta fog, violet
## ambient light) — the word_mesh.gd buildings/landmarks provide the neon
## light sources, this just sets the mood they glow into.
func _apply_manhattan_environment(active: bool) -> void:
	if world_env == null or world_env.environment == null:
		return
	var env: Environment = world_env.environment
	if active:
		env.background_color = MANHATTAN_BG_COLOR
		env.fog_light_color = MANHATTAN_FOG_COLOR
		env.fog_density = 0.045
		env.ambient_light_color = MANHATTAN_AMBIENT_COLOR
		env.ambient_light_energy = 0.55
	else:
		env.background_color = NORMAL_BG_COLOR
		env.fog_light_color = NORMAL_FOG_COLOR
		env.fog_density = 0.03
		env.ambient_light_color = NORMAL_AMBIENT_COLOR
		env.ambient_light_energy = 0.9


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
	maze_view.build(maze, start_cell, "normal")
	_apply_manhattan_environment(false)
	fruit_spawned = false
	word_mode_until = 0.0
	player.set_noclip(false)

	player.warp_to(start_cell, PI)
	invuln_until = now + 1.2

	for e in enemies:
		e.queue_free()
	enemies.clear()
	_clear_manhattan_obstacles() # normal levels never have any; defensive
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

	# Pedestrian and metro-station cells are picked before the maze view
	# builds its pellets, and handed in together as reserved cells, so
	# neither a stationary pedestrian nor a metro sign can ever end up
	# parked on top of a pellet the player could never then reach.
	var pedestrian_cells := _pick_manhattan_pedestrian_cells()
	var metro_cells := _pick_manhattan_metro_cells(pedestrian_cells)
	var reserved_cells: Array = pedestrian_cells + metro_cells
	maze_view.build(maze, start_cell, "manhattan", reserved_cells)
	_apply_manhattan_environment(true)
	fruit_spawned = false
	word_mode_until = 0.0
	player.set_noclip(false)

	player.warp_to(start_cell, PI)
	invuln_until = now + 1.2

	for e in enemies:
		e.queue_free()
	enemies.clear() # Manhattan has no ghosts — see this function's header comment

	_spawn_manhattan_obstacles(pedestrian_cells)
	_spawn_metro_stations(metro_cells)

	hud.set_level("MANHATTAN")
	hud.set_score(score)
	hud.set_lives(lives)
	hud.set_best_time(-1.0)
	level_start_time = now


func _clear_manhattan_obstacles() -> void:
	for t in taxis:
		t.queue_free()
	taxis.clear()
	for p in pedestrians:
		p.queue_free()
	pedestrians.clear()
	for m in metro_stations:
		m.queue_free()
	metro_stations.clear()


## Picks stationary pedestrian cells ahead of pellet placement (see
## maze_view.gd's `build`/`_build_pellets` reserved_cells parameter) so a
## pedestrian can never end up parked on a pellet the player could never
## reach. Pure cell selection, no node spawning — spawning happens in
## _spawn_manhattan_obstacles once maze_view has already excluded these.
func _pick_manhattan_pedestrian_cells() -> Array:
	var open_cells: Array = MazeGen.cells_in_room(maze, false)
	open_cells.shuffle()
	var picked := []
	for cell in open_cells:
		if picked.size() >= MANHATTAN_PEDESTRIAN_COUNT:
			break
		if cell == start_cell:
			continue
		picked.append(cell)
	return picked


## Metro-station cells, picked the same way as pedestrian cells and
## excluding any cell pedestrian picking already claimed, so the two never
## collide and neither ever lands on a pellet.
func _pick_manhattan_metro_cells(pedestrian_cells: Array) -> Array:
	var open_cells: Array = MazeGen.cells_in_room(maze, false)
	open_cells.shuffle()
	var picked := []
	for cell in open_cells:
		if picked.size() >= MANHATTAN_METRO_COUNT:
			break
		if cell == start_cell or cell in pedestrian_cells:
			continue
		picked.append(cell)
	return picked


## Taxis (and the occasional VeryLongLimousine — same entity, a longer word
## in chrome) run the full length of a handful of streets/avenues;
## pedestrians stand at the cells `_pick_manhattan_pedestrian_cells` already
## reserved for them, each one randomly a lone PERSON, a ManWalkingDog, or a
## KidGroup, for a varied street scene. Both are built fresh per Manhattan
## run, same as enemies are per level.
func _spawn_manhattan_obstacles(pedestrian_cells: Array) -> void:
	_clear_manhattan_obstacles()

	var row_choices := []
	var r := 1
	while r < maze.rows - 1:
		row_choices.append(r)
		r += 2
	var col_choices := []
	var c := 1
	while c < maze.cols - 1:
		col_choices.append(c)
		c += 2
	row_choices.shuffle()
	col_choices.shuffle()

	var min_x: float = 1 * CELL
	var max_x: float = (maze.cols - 2) * CELL
	var min_z: float = 1 * CELL
	var max_z: float = (maze.rows - 2) * CELL

	for i in mini(MANHATTAN_TAXI_ROW_COUNT, row_choices.size()):
		var taxi := Node3D.new()
		taxi.set_script(load("res://scripts/taxi.gd"))
		obstacle_root.add_child(taxi)
		var is_limo := randf() < 0.3
		if is_limo:
			taxi.setup("row", row_choices[i] * CELL, min_x, max_x, 1.8 + randf() * 0.6, "VERYLONGLIMOUSINE", MANHATTAN_LIMO_COLOR, 18)
		else:
			taxi.setup("row", row_choices[i] * CELL, min_x, max_x, 2.6 + randf() * 1.0, "TAXI", MANHATTAN_TAXI_COLOR, 30)
		taxis.append(taxi)
	for i in mini(MANHATTAN_TAXI_COL_COUNT, col_choices.size()):
		var taxi2 := Node3D.new()
		taxi2.set_script(load("res://scripts/taxi.gd"))
		obstacle_root.add_child(taxi2)
		var is_limo2 := randf() < 0.3
		if is_limo2:
			taxi2.setup("col", col_choices[i] * CELL, min_z, max_z, 1.8 + randf() * 0.6, "VERYLONGLIMOUSINE", MANHATTAN_LIMO_COLOR, 18)
		else:
			taxi2.setup("col", col_choices[i] * CELL, min_z, max_z, 2.6 + randf() * 1.0, "TAXI", MANHATTAN_TAXI_COLOR, 30)
		taxis.append(taxi2)

	var pedestrian_scripts := [
		"res://scripts/pedestrian.gd",
		"res://scripts/man_walking_dog.gd",
		"res://scripts/kid_group.gd",
	]
	for cell in pedestrian_cells:
		var script_path: String = pedestrian_scripts[randi() % pedestrian_scripts.size()]
		var ped := Node3D.new()
		ped.set_script(load(script_path))
		obstacle_root.add_child(ped)
		ped.setup(Vector3(cell.y * CELL, 0.4, cell.x * CELL))
		pedestrians.append(ped)


## Glowing "SUBWAY" signs at the reserved metro cells; entering one ends
## the Manhattan run and drops the player back into the normal speedrun
## progression (see _check_metro_entry / _enter_metro).
func _spawn_metro_stations(metro_cells: Array) -> void:
	for cell in metro_cells:
		var station := Node3D.new()
		station.set_script(load("res://scripts/metro_station.gd"))
		obstacle_root.add_child(station)
		station.setup(Vector3(cell.y * CELL, 0.9, cell.x * CELL))
		metro_stations.append(station)


func _check_manhattan_obstacles() -> void:
	for t in taxis:
		_push_player_away_from(t.position)
	for p in pedestrians:
		_push_player_away_from(p.position)


## Proximity check: stepping close enough to a metro station's sign ends
## the Manhattan bonus run early and drops the player back into the normal
## speedrun progression (a fresh run from level 1 — "kehrt man zurück ins
## normale Speedrun Level").
func _check_metro_entry() -> void:
	for m in metro_stations:
		var d := Vector2(player.global_position.x - m.position.x, player.global_position.z - m.position.z).length()
		if d < MANHATTAN_METRO_RADIUS:
			_enter_metro()
			return


func _enter_metro() -> void:
	running = false
	Sfx.set_siren(false, false)
	Sfx.level_clear()
	if score > high_score:
		high_score = score
		_save_highscore(high_score)
	hud.show_levelclear(true, "SUBWAY — zurück zum Speedrun!")
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	await get_tree().create_timer(1.4).timeout
	hud.show_levelclear(false)
	playing_manhattan = false
	begin_game()


## Soft-blocks the player out to MANHATTAN_OBSTACLE_RADIUS from an obstacle
## — an "obstacle you can't walk through" without needing a real physics
## body on a continuously-moving node. Never touches lives/score: Manhattan
## obstacles are harmless by design (see this file's Manhattan header).
func _push_player_away_from(obstacle_pos: Vector3) -> void:
	var away := Vector2(player.global_position.x - obstacle_pos.x, player.global_position.z - obstacle_pos.z)
	var d := away.length()
	if d <= 0.0001:
		player.global_position.x += MANHATTAN_OBSTACLE_RADIUS
	elif d < MANHATTAN_OBSTACLE_RADIUS:
		var push := away.normalized() * (MANHATTAN_OBSTACLE_RADIUS - d)
		player.global_position.x += push.x
		player.global_position.z += push.y


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
	_apply_manhattan_environment(false)
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
	_apply_manhattan_environment(false)
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

	if playing_manhattan:
		for t in taxis:
			t.update(delta)
		for p in pedestrians:
			p.update(delta, now)
		for m in metro_stations:
			m.update(delta, now)
		_check_manhattan_obstacles()
		_check_metro_entry()

	_check_pickups()

	if word_mode_until > 0.0 and now >= word_mode_until:
		_deactivate_word_mode()

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
	if result.word_powerup:
		score += 75
		_activate_word_mode()
	if result.pellet or result.power:
		Sfx.munch()
	if result.pellet or result.power or result.fruit or result.word_powerup:
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


## ---------------- Word Mode power-up (normal levels only) ----------------
## Reskins the level into the word-built-world look (walls become "WALL"
## letterforms, ghosts become "GHOST" letterforms — same as Manhattan's
## permanent look) and drops player-wall collision for WORD_MODE_DURATION
## seconds. Manhattan never spawns this pickup (see maze_view.gd), so this
## only ever fires during a normal level.
func _activate_word_mode() -> void:
	word_mode_until = now + WORD_MODE_DURATION
	maze_view.set_word_mode(true)
	player.set_noclip(true)
	for enemy in enemies:
		enemy.set_word_skin(true)
	Sfx.power()


func _deactivate_word_mode() -> void:
	word_mode_until = 0.0
	maze_view.set_word_mode(false)
	player.set_noclip(false)
	for enemy in enemies:
		enemy.set_word_skin(false)


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
