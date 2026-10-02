extends Node3D
## Main — game orchestrator: level lifecycle, scoring, lives, input wiring,
## enemy/pickup collision. Direct port of the web prototype's game.js logic
## (see web/index.html) onto Godot nodes; MazeGen supplies the same kind of
## verified-connected maze.

const CELL := 2.0
const FRIGHTENED_DURATION := 7.0
const WORD_MODE_DURATION := 12.0
const FEAR_MODE_DURATION := 10.0
const FEAR_NOCLIP_FLIP_MIN := 0.4
const FEAR_NOCLIP_FLIP_MAX := 1.1
## Ghost hit-trigger distance (center-to-center; ghosts have no physical
## collider of their own, so this is the only thing standing between a
## ghost and the player in a corridor). The old 0.62 left just enough
## clearance in a one-wide corridor (MazeView.CELL/wall_footprint_scale) for
## the player to hug one wall and slip past a ghost sitting in the corridor
## instead of colliding with it (see review finding GD-N4). Raised well
## past the corridor's own width so that's no longer possible at all, per
## user request ("kein Ausweichen mit Gegner möglich machen, nicht seitlich
## vorbei können") — a ghost in the way now has to be eaten (frightened),
## evaded by backing off into a side passage, or run into.
const ENEMY_HIT_RADIUS := 0.85
const HIGHSCORE_PATH := "user://kugelschlucker_highscore.txt"

const LEVELS := [
	{"rows": 19, "cols": 21, "ghost_speed": 2.0, "ghost_count": 3, "seed_base": 10000},
	{"rows": 21, "cols": 25, "ghost_speed": 2.25, "ghost_count": 4, "seed_base": 20000},
	{"rows": 23, "cols": 27, "ghost_speed": 2.5, "ghost_count": 4, "seed_base": 30000},
	{"rows": 23, "cols": 29, "ghost_speed": 2.75, "ghost_count": 5, "seed_base": 40000},
]

## Manhattan has no ghosts (see manhattan_maze.gd's header) — it's a calm
## explore level. Traffic and pedestrians are its only obstacles: harmless,
## just something to walk around (Main._check_manhattan_obstacles). Both
## are real moving traffic now — more lanes and more variety of each
## (TAXI/CAR/BIKE/VERYLONGLIMOUSINE, MAN/WOMAN/KID/DAD+KID) than the
## original handful of stationary pedestrians + 5 cars.
const MANHATTAN_TAXI_ROW_COUNT := 5
const MANHATTAN_TAXI_COL_COUNT := 4
const MANHATTAN_PEDESTRIAN_COUNT := 16
const MANHATTAN_OBSTACLE_RADIUS := 0.55
## Pedestrians get their own, smaller push-out radius. With the shared
## 0.55 radius, the push zone around a sidewalk pedestrian reached past the
## sidewalk strip into the building face itself, leaving no actual gap for
## the player to walk through next to them — directly contradicting the
## "neben Passanten... vorbei" request. 0.35 keeps a soft bump against
## pedestrians while leaving real room to pass on the building side.
const MANHATTAN_PEDESTRIAN_OBSTACLE_RADIUS := 0.35
## Streets used to put taxis AND pedestrians on the exact same centerline
## (per user request: "mehrspurig für Verkehr und daneben Fußweg" — traffic
## needs real lanes, and pedestrians need a sidewalk clear of them, not one
## shared line down the middle of the street). MANHATTAN_VEHICLE_LANE_OFFSET
## splits traffic into two lanes either side of the centerline (one per
## direction — see Taxi.setup); MANHATTAN_SIDEWALK_OFFSET puts pedestrians
## on a strip further out, near the building edge, clear of both lanes. Both
## stay well inside the canyon between two building faces (see CityTheme.
## wall_footprint_scale in city_themes.gd's manhattan()) — with that scale
## at 0.40, the building face sits 1.6 world units off the street
## centerline, so a 1.1 sidewalk offset leaves ~0.5 clearance to the wall,
## comfortably more than MANHATTAN_PEDESTRIAN_OBSTACLE_RADIUS (0.35).
const MANHATTAN_VEHICLE_LANE_OFFSET := 0.45
const MANHATTAN_SIDEWALK_OFFSET := 1.1
const MANHATTAN_METRO_COUNT := 4
const MANHATTAN_METRO_RADIUS := 0.75
const MANHATTAN_LIMO_COLOR := Color(0.82, 0.86, 0.95) # chrome/silver
const MANHATTAN_TAXI_COLOR := Color(1.0, 0.82, 0.05)
const MANHATTAN_CAR_COLOR := Color(0.55, 0.65, 0.8) # ordinary traffic, muted steel-blue
const MANHATTAN_BIKE_COLOR := Color(0.35, 0.85, 0.45)

const CityThemesScript := preload("res://scripts/city_themes.gd")
const ConditionsScript := preload("res://scripts/conditions.gd")

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

## Fear & Loathing pickup (normal levels only — see maze_view.gd's
## fear_powerup_cell): temporarily layers the Fear & Loathing condition's
## control-scrambling on top of whatever whole-run condition (if any) is
## already selected, turns the wall shader psychedelic, and randomly flips
## the player's wall collision on and off — see _activate_fear_powerup.
var fear_mode_until := 0.0
var _fear_condition_instance = null
var _fear_saved_active_condition = null
var _fear_prev_noclip := false
var _fear_next_noclip_toggle_at := 0.0

## Testbuild mode (see hud.gd's TESTBUILD button / _on_test_build_pressed
## below): plays a normal Matrix level exactly like start_pressed does, just
## with the HUD's DEBUG chip switched on (FPS, player position, cell).
var debug_mode := false

## Which registered CityTheme (see city_themes.gd's EXPLORER_IDS) the
## current/last Explorer run was played on. Only "manhattan" resolves to
## real content today (see start_explorer_level) — this exists so the
## leaderboard board key and the post-run "next choice" panel are already
## written generically for when a second Explorer city exists.
var explorer_city_id := "manhattan"

## The selected "Kondition" for the current run (see scripts/conditions.gd's
## registry) — a whole-run modifier like Matrix Ghost (no wall collision) or
## Fear & Loathing (noisy/inverted controls), independent of and additional
## to the per-level Word Mode pickup above. null/"" = no condition, plays
## unmodified. Persists across start_level()/start_manhattan_level() calls
## until set_condition() is called again — there is no selection UI yet
## (see this project's "Explorer-Level-Erweiterung, Leaderboard &
## Konditionen" doc), so nothing currently changes it from the default.
var current_condition = null
var condition_id := ""

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
	var normal_theme = CityThemesScript.get_theme("normal")
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = normal_theme.env_bg_color
	env.fog_enabled = true
	env.fog_light_color = normal_theme.env_fog_color
	env.fog_density = normal_theme.env_fog_density
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = normal_theme.env_ambient_color
	env.ambient_light_energy = normal_theme.env_ambient_energy
	world_env = WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)


## Swaps the whole scene's ambience to match a CityTheme's environment
## fields (background/fog/ambient light) — e.g. the normal levels' cool
## blue vs. Manhattan's neon Neo-Noir Cyberpunk palette (magenta fog,
## violet ambient light). The word_mesh.gd buildings/landmarks provide the
## neon light sources themselves; this just sets the mood they glow into.
## A future Explorer level (Tokyo, Paris, Rio, ...) needs no new code here
## — just its own CityTheme in city_themes.gd.
func _apply_theme_environment(theme_id: String) -> void:
	if world_env == null or world_env.environment == null:
		return
	var ct = CityThemesScript.get_theme(theme_id)
	var env: Environment = world_env.environment
	env.background_color = ct.env_bg_color
	env.fog_light_color = ct.env_fog_color
	env.fog_density = ct.env_fog_density
	env.ambient_light_color = ct.env_ambient_color
	env.ambient_light_energy = ct.env_ambient_energy


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
	hud.test_build_pressed.connect(_on_test_build_pressed)
	hud.explorer_choice_pressed.connect(_on_explorer_choice_pressed)
	hud.explorer_menu_pressed.connect(_on_explorer_menu_pressed)
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
	_apply_theme_environment("normal")
	fruit_spawned = false
	word_mode_until = 0.0
	fear_mode_until = 0.0
	_fear_condition_instance = null
	player.active_condition = current_condition # in case a Fear & Loathing pickup was interrupted by a restart, mid-effect
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
	set_condition("") # a fresh normal run never carries over a leftover Explorer-run condition
	hud.hide_all_panels()
	start_level(0)
	running = true
	paused = false
	player.input_enabled = true
	Sfx.set_siren(true, false)
	Sfx.play_arcade_music()
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

	# Metro-station cells are picked before the maze view builds its
	# pellets and handed in as reserved cells, so a metro sign can never
	# end up parked on top of a pellet the player could never then reach.
	# Pedestrians now walk the streets like traffic (see _spawn_manhattan_
	# obstacles), so they no longer need a reserved home cell of their own.
	var metro_cells := _pick_manhattan_metro_cells()
	var reserved_cells: Array = metro_cells
	maze_view.build(maze, start_cell, "manhattan", reserved_cells, metro_cells)
	_apply_theme_environment("manhattan")
	fruit_spawned = false
	word_mode_until = 0.0
	fear_mode_until = 0.0
	_fear_condition_instance = null
	player.active_condition = current_condition # in case a Fear & Loathing pickup was interrupted by a restart, mid-effect
	player.set_noclip(false)

	player.warp_to(start_cell, PI)
	invuln_until = now + 1.2

	for e in enemies:
		e.queue_free()
	enemies.clear() # Manhattan has no ghosts — see this function's header comment

	_spawn_manhattan_obstacles()
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


## Metro-station cells, picked ahead of pellet placement (see maze_view.gd's
## `build`/`_build_pellets` reserved_cells parameter) so a metro sign can
## never end up parked on a pellet the player could never then reach.
func _pick_manhattan_metro_cells() -> Array:
	var open_cells: Array = MazeGen.cells_in_room(maze, false)
	open_cells.shuffle()
	var picked := []
	for cell in open_cells:
		if picked.size() >= MANHATTAN_METRO_COUNT:
			break
		if cell == start_cell:
			continue
		picked.append(cell)
	return picked


## A weighted pool of Manhattan street traffic: TAXI and CAR are the common
## sights, BIKE a lighter/faster one, VERYLONGLIMOUSINE a rare chrome
## stretch — each entry names its word, color, font size and a speed range
## (bikes fastest, limos slowest/stateliest). Picked per-taxi-node so both
## the row and column streets get a genuine mix rather than "always a taxi,
## occasionally a limo".
func _manhattan_vehicle_pool() -> Array:
	return [
		{"weight": 4, "word": "TAXI", "color": MANHATTAN_TAXI_COLOR, "font_size": 30, "speed_min": 2.6, "speed_max": 3.6},
		{"weight": 4, "word": "CAR", "color": MANHATTAN_CAR_COLOR, "font_size": 26, "speed_min": 2.2, "speed_max": 3.2},
		{"weight": 2, "word": "BIKE", "color": MANHATTAN_BIKE_COLOR, "font_size": 20, "speed_min": 3.6, "speed_max": 5.0},
		{"weight": 1, "word": "VERYLONGLIMOUSINE", "color": MANHATTAN_LIMO_COLOR, "font_size": 18, "speed_min": 1.8, "speed_max": 2.4},
	]


func _pick_weighted_vehicle(pool: Array) -> Dictionary:
	var total := 0
	for v in pool:
		total += int(v["weight"])
	var roll := randi() % total
	for v in pool:
		roll -= int(v["weight"])
		if roll < 0:
			return v
	return pool[0]


## Taxis/cars/bikes/limos run the full length of a handful of streets/
## avenues; pedestrians (a mix of lone MAN/WOMAN walkers, a ManWalkingDog,
## a KidGroup, or a DadAndKid) now walk those same streets too instead of
## standing still, each assigned its own row or column lane. Both are built
## fresh per Manhattan run, same as enemies are per level.
func _spawn_manhattan_obstacles() -> void:
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

	var vehicle_pool := _manhattan_vehicle_pool()

	for i in mini(MANHATTAN_TAXI_ROW_COUNT, row_choices.size()):
		var taxi := Node3D.new()
		taxi.set_script(load("res://scripts/taxi.gd"))
		obstacle_root.add_child(taxi)
		var v := _pick_weighted_vehicle(vehicle_pool)
		var speed: float = v["speed_min"] + randf() * (v["speed_max"] - v["speed_min"])
		taxi.setup("row", row_choices[i] * CELL, min_x, max_x, speed, v["word"], v["color"], v["font_size"], MANHATTAN_VEHICLE_LANE_OFFSET)
		taxis.append(taxi)
	for i in mini(MANHATTAN_TAXI_COL_COUNT, col_choices.size()):
		var taxi2 := Node3D.new()
		taxi2.set_script(load("res://scripts/taxi.gd"))
		obstacle_root.add_child(taxi2)
		var v2 := _pick_weighted_vehicle(vehicle_pool)
		var speed2: float = v2["speed_min"] + randf() * (v2["speed_max"] - v2["speed_min"])
		taxi2.setup("col", col_choices[i] * CELL, min_z, max_z, speed2, v2["word"], v2["color"], v2["font_size"], MANHATTAN_VEHICLE_LANE_OFFSET)
		taxis.append(taxi2)

	var pedestrian_scripts := [
		"res://scripts/pedestrian.gd",
		"res://scripts/man_walking_dog.gd",
		"res://scripts/kid_group.gd",
		"res://scripts/dad_and_kid.gd",
	]
	for i in MANHATTAN_PEDESTRIAN_COUNT:
		var script_path: String = pedestrian_scripts[randi() % pedestrian_scripts.size()]
		var ped := Node3D.new()
		ped.set_script(load(script_path))
		obstacle_root.add_child(ped)
		var speed := 0.8 + randf() * 0.7
		var side := 1.0 if randf() > 0.5 else -1.0 # which building edge's sidewalk, so both sides of a street get walked
		if row_choices.is_empty() or (not col_choices.is_empty() and randf() > 0.5):
			var col: int = col_choices[randi() % col_choices.size()]
			ped.setup(Vector3(col * CELL + side * MANHATTAN_SIDEWALK_OFFSET, 0.4, min_z), "col", min_z, max_z, speed)
		else:
			var row: int = row_choices[randi() % row_choices.size()]
			ped.setup(Vector3(min_x, 0.4, row * CELL + side * MANHATTAN_SIDEWALK_OFFSET), "row", min_x, max_x, speed)
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
		_push_player_away_from(t.position, MANHATTAN_OBSTACLE_RADIUS)
	for p in pedestrians:
		_push_player_away_from(p.position, MANHATTAN_PEDESTRIAN_OBSTACLE_RADIUS)


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


## Soft-blocks the player out to `radius` from an obstacle — an "obstacle
## you can't walk through" without needing a real physics body on a
## continuously-moving node. Never touches lives/score: Manhattan obstacles
## are harmless by design (see this file's Manhattan header). Taxis and
## pedestrians pass their own radius (MANHATTAN_OBSTACLE_RADIUS /
## MANHATTAN_PEDESTRIAN_OBSTACLE_RADIUS) so the pedestrian push zone can be
## smaller, leaving real sidewalk room to pass next to them.
func _push_player_away_from(obstacle_pos: Vector3, radius: float) -> void:
	var away := Vector2(player.global_position.x - obstacle_pos.x, player.global_position.z - obstacle_pos.z)
	var d := away.length()
	if d <= 0.0001:
		player.global_position.x += radius
	elif d < radius:
		var push := away.normalized() * (radius - d)
		player.global_position.x += push.x
		player.global_position.z += push.y


## Always a fresh, unmodified Explorer run — the start-screen button. Runs
## started from the post-run "next choice" panel go through
## _start_explorer_run directly so they can carry a chosen condition.
func begin_manhattan_game() -> void:
	_start_explorer_run("manhattan", "")


## Starts (or restarts) an Explorer-level run with the given city and
## condition. Shared by begin_manhattan_game (always city="manhattan",
## condition="") and _on_explorer_choice_pressed (the post-run panel, which
## can carry a condition over or switch it — see _explorer_next_choices).
func _start_explorer_run(city_id: String, cond_id: String) -> void:
	Sfx.stop_all()
	score = 0
	lives = 3
	playing_manhattan = true
	set_condition(cond_id)
	hud.hide_all_panels()
	start_explorer_level(city_id)
	running = true
	paused = false
	player.input_enabled = true
	Sfx.set_siren(true, false)
	Sfx.play_explorer_music()
	if not OS.has_feature("web"):
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


## Dispatches to the right Explorer-level builder for `city_id`. Only
## Manhattan exists today (see city_themes.gd's EXPLORER_IDS) — a future
## city gets its own maze/obstacle builder and a real branch here, the same
## way start_manhattan_level() itself works.
func start_explorer_level(city_id: String) -> void:
	explorer_city_id = city_id
	start_manhattan_level()


func manhattan_complete_sequence() -> void:
	running = false
	Sfx.set_siren(false, false)
	Sfx.level_clear()
	if score > high_score:
		high_score = score
		_save_highscore(high_score)
	var elapsed := now - level_start_time
	hud.show_levelclear(true, "Manhattan bezwungen! Punkte " + str(score))
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	await get_tree().create_timer(2.2).timeout
	hud.show_levelclear(false)
	playing_manhattan = false
	_apply_theme_environment("normal")
	Sfx.stop_all()
	hud.set_start_highscore(high_score)
	hud.set_bonus_unlocked(Speedrun.is_bonus_unlocked())

	# Leaderboard is scoped to (city, condition) — a Matrix-Ghost run isn't
	# comparable to an unmodified one — and the post-run panel offers the
	# 4 next-run combinations (same/other city × same/other condition) so
	# every completed Explorer run naturally invites another, differently-
	# flavored one instead of dropping straight back to the main menu.
	var submit_result := Leaderboard.submit_time(explorer_city_id, condition_id, elapsed)
	var top_entries := Leaderboard.get_top(explorer_city_id, condition_id, 5)
	var city_name: String = CityThemesScript.get_theme(explorer_city_id).display_name
	hud.show_explorer_next(_explorer_next_choices(), top_entries, submit_result, elapsed, "%s GESCHAFFT!" % city_name.to_upper())

	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	player.input_enabled = false


## The 4 post-run choices: same/other city crossed with same/other
## condition. "Other city" currently falls back to the same city (only
## Manhattan is registered — see city_themes.gd's EXPLORER_IDS), so two of
## these can be identical until a second Explorer city exists; that's
## expected, not a bug (see this project's Explorer-Level-Erweiterung doc).
func _explorer_next_choices() -> Array:
	var same_city := explorer_city_id
	var other_city: String = CityThemesScript.other_explorer_id(explorer_city_id)
	var same_cond := condition_id
	var other_cond: String = ConditionsScript.other_condition_id(condition_id)

	var combos := [
		{"city_id": same_city, "condition_id": other_cond, "label": "GLEICHE STADT · ANDERE KONDITION"},
		{"city_id": other_city, "condition_id": same_cond, "label": "ANDERE STADT · GLEICHE KONDITION"},
		{"city_id": same_city, "condition_id": same_cond, "label": "NOCHMAL · BEIDES GLEICH"},
		{"city_id": other_city, "condition_id": other_cond, "label": "BEIDES ANDERS"},
	]
	for c in combos:
		var city_display: String = CityThemesScript.get_theme(c.city_id).display_name
		var cond_display: String = ConditionsScript.display_name_for(c.condition_id)
		c["sub"] = "%s · %s" % [city_display, cond_display]
	return combos


func _on_manhattan_pressed() -> void:
	debug_mode = false
	hud.set_debug_overlay(false)
	begin_manhattan_game()


func _on_explorer_choice_pressed(city_id: String, cond_id: String) -> void:
	_start_explorer_run(city_id, cond_id)


func _on_explorer_menu_pressed() -> void:
	hud.show_only(hud.start_panel)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	player.input_enabled = false


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
	_apply_theme_environment("normal")
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func level_complete_sequence() -> void:
	running = false
	Sfx.set_siren(false, false)
	Sfx.level_clear()

	var elapsed := now - level_start_time
	var result := Speedrun.record_level_time(level_index, elapsed)
	Leaderboard.submit_time("normal-%d" % level_index, condition_id, elapsed)
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
	debug_mode = false
	hud.set_debug_overlay(false)
	begin_game()


## Testbuild: identical to a normal Matrix-level start, just with the HUD's
## DEBUG chip (FPS / position / cell, updated each frame in _process) turned
## on — a quick way to check a build without a separate game mode.
func _on_test_build_pressed() -> void:
	debug_mode = true
	hud.set_debug_overlay(true)
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

	if debug_mode:
		hud.update_debug_overlay(Engine.get_frames_per_second(), player.global_position, player_cell)

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

	# Pickups are checked before the obstacle push so a taxi/pedestrian that
	# happens to be passing over the player's exact cell this frame can
	# never transiently block a pellet the player has already reached —
	# obstacles just slide the player back out afterward, same as always.
	_check_pickups()

	if playing_manhattan:
		_check_manhattan_obstacles()
		_check_metro_entry()

	if word_mode_until > 0.0 and now >= word_mode_until:
		_deactivate_word_mode()

	if fear_mode_until > 0.0:
		if now >= fear_mode_until:
			_deactivate_fear_powerup()
		elif now >= _fear_next_noclip_toggle_at:
			player.set_noclip(randf() > 0.5)
			_fear_next_noclip_toggle_at = now + randf_range(FEAR_NOCLIP_FLIP_MIN, FEAR_NOCLIP_FLIP_MAX)

	if current_condition != null:
		current_condition.on_process(delta, self)

	hud.set_timer(now - level_start_time)
	hud.set_power_timer(frightened_until - now, FRIGHTENED_DURATION)
	if now >= frightened_until and Sfx.siren_state() == "frightened":
		Sfx.set_siren(true, false)
	hud.update_minimap(maze, player, enemies, frightened_active, maze_view)


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
	if d < ENEMY_HIT_RADIUS:
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
	if result.fear_powerup:
		score += 75
		_activate_fear_powerup()
	if result.pellet or result.power:
		Sfx.munch()
	if result.pellet or result.power or result.fruit or result.word_powerup or result.fear_powerup:
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


## ---------------- Fear & Loathing power-up (normal levels only) ----------------
## A rarer, temporary sibling to the Word Mode pickup above: for
## FEAR_MODE_DURATION seconds, the player's steering gets the same
## noisy/periodically-inverted treatment as the whole-run Fear & Loathing
## Kondition (scripts/conditions/fear_and_loathing.gd, reused directly
## rather than duplicated), the matrix_rain wall shader dissolves into a
## psychedelic color-cycling wobble (see set_psychedelic), and wall
## collision randomly flips on and off every FEAR_NOCLIP_FLIP_MIN..MAX
## seconds (_process below) — an "LSD trip" the player has to ride out
## rather than a clean buff. Whatever whole-run condition (if any) was
## already active is swapped back in unchanged once this ends.
func _activate_fear_powerup() -> void:
	fear_mode_until = now + FEAR_MODE_DURATION
	_fear_saved_active_condition = player.active_condition
	_fear_condition_instance = ConditionsScript.get_condition("fear_and_loathing")
	_fear_condition_instance.on_start(self)
	player.active_condition = _fear_condition_instance
	_fear_prev_noclip = player.collision_mask == 0
	_fear_next_noclip_toggle_at = now + randf_range(FEAR_NOCLIP_FLIP_MIN, FEAR_NOCLIP_FLIP_MAX)
	maze_view.set_psychedelic(true)
	Sfx.power()


func _deactivate_fear_powerup() -> void:
	fear_mode_until = 0.0
	player.active_condition = _fear_saved_active_condition
	_fear_condition_instance = null
	player.set_noclip(_fear_prev_noclip)
	maze_view.set_psychedelic(false)


## ---------------- Konditionen (whole-run modifiers) ----------------
## See scripts/conditions.gd's registry and scripts/conditions/condition_base.gd.
## Selects (or clears, with "") the condition applied for the current and
## future runs until changed again. Safe to call whether or not a level is
## currently running/built.
func set_condition(id: String) -> void:
	if current_condition != null:
		current_condition.on_end(self)
	condition_id = id
	current_condition = ConditionsScript.get_condition(id)
	player.active_condition = current_condition
	if current_condition != null:
		current_condition.on_start(self)


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
