extends Node3D
## Main — game orchestrator: level lifecycle, scoring, lives, input wiring,
## enemy/pickup collision. Direct port of the web prototype's game.js logic
## (see web/index.html) onto Godot nodes; MazeGen supplies the same kind of
## verified-connected maze.

const CELL := 2.0
const FRIGHTENED_DURATION := 7.0
const WORD_MODE_DURATION := 12.0
const FEAR_MODE_DURATION := 10.0
const FEAR_SCORE_MULTIPLIER := 2 # the Fear pickup's reward: double points while it runs
const FEAR_FIRST_LEVEL := 1 # levels already cleared in the run before Fear pickups appear (i.e. from the 2nd level on)
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
const HIGHSCORE_FILE := "kugelschlucker_highscore.txt" # under SavePaths.root (tests redirect it)

const LEVELS := [
	{"rows": 19, "cols": 21, "ghost_speed": 2.0, "ghost_count": 3, "seed_base": 10000},
	{"rows": 21, "cols": 25, "ghost_speed": 2.25, "ghost_count": 4, "seed_base": 20000},
	{"rows": 23, "cols": 27, "ghost_speed": 2.5, "ghost_count": 4, "seed_base": 30000},
	{"rows": 23, "cols": 29, "ghost_speed": 2.75, "ghost_count": 5, "seed_base": 40000},
]

## Past the last defined LEVELS entry, start_level() keeps raising ghost
## speed by `extra * 0.15` per level forever (see start_level's `extra`) —
## flagged by review finding GD-N1 (docs/review/berichte/2026-10-01.md):
## worked out from the actual formula, the fastest ghost hits 4.45 m/s at
## level 13, already past PlayerController.PLAYER_SPEED (4.4), and every
## ghost outruns the player from level 15 on — with the new no-sidestep
## ENEMY_HIT_RADIUS there's then no way to out-walk one at all. Capped at
## ~90% of PLAYER_SPEED, matching the review's own suggested figure
## (worked back from PLAYER_SPEED=4.4 in player_controller.gd — kept as a
## literal here rather than cross-referencing that script's const, to
## avoid coupling an unrelated file's load order to this one). A ghost can
## still be faster than this while frightened/eaten (see enemy.gd's
## per-mode speed multipliers, which apply on top of this cap). Further
## difficulty scaling past the cap (e.g. shorter FRIGHTENED_DURATION per
## level, per the review's own suggestion) is intentionally not done here
## — flagged to the user as a separate balancing decision, not bundled
## into this fix.
const GHOST_SPEED_CAP := 3.96

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

const LevelsScript := preload("res://scripts/levels.gd")
const CityThemesScript := preload("res://scripts/city_themes.gd")
const ConditionsScript := preload("res://scripts/conditions.gd")
const SavePathsScript := preload("res://scripts/save_paths.gd")

## Ghost colors come from the level look (MazeView.ghost_palette(), see
## city_themes.gd GHOST_* — no green, no cyan, never the level's gradient).

var hud
var player: CharacterBody3D
var maze_view: Node3D
var enemy_root: Node3D

var maze # MazeGen.Maze
var level_index := 0 # levels cleared so far in this run (0 = first level of the run)
var current_level: Dictionary = {} # the Levels.POOL entry being played (empty in Manhattan)
var level_id := "" # current_level.id; "" in Manhattan
var played_ids: Array = [] # level ids cleared in this run (see Levels.draw_next)
var level_rng := RandomNumberGenerator.new()
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
## `now` is the game clock: effect timers (Frightened, Word, Fear, invulnerability,
## ghost release, fruit) are all relative to it, and it stands still while the
## game is paused. `real_now` never stops — the Speedrun time is measured on it,
## so pausing does not stop the clock (no pause abuse in a speedrun).
var now := 0.0
var real_now := 0.0
var level_start_real := 0.0
## true once a Twitch chat command took effect during the current level; the
## level's time then goes to the "chat" best time / leaderboard (Levels.MODES).
var level_chat_assisted := false
## Condition picked on the start screen (see hud.condition_selected).
var selected_condition_id := ""
var playing_manhattan := false
var word_mode_until := 0.0

## Fear & Loathing pickup (normal levels from the 2nd level of a run on, lying
## in dead ends — see maze_view.gd): a risk/reward item. For FEAR_MODE_DURATION
## seconds the steering is noisy/inverted (only while the player steers) and the
## walls turn psychedelic; in return all points count double. A second pickup
## only extends the timer. See _activate_fear_powerup.
var fear_mode_until := 0.0
var _fear_condition_instance = null
var _fear_saved_active_condition = null

## Debug overlay (FPS, player position, cell): toggled with F3, debug builds only.
var debug_mode := false

## Which registered CityTheme (see city_themes.gd's EXPLORER_IDS) the
## current/last Explorer run was played on. Only "manhattan" resolves to
## real content today (see start_explorer_level).
var explorer_city_id := "manhattan"

## The selected "Kondition" for the current run (see scripts/conditions.gd's
## registry) — a whole-run modifier like Matrix Ghost (no wall collision) or
## Fear & Loathing (noisy/inverted controls), independent of and additional
## to the per-level Word Mode pickup above. null/"" = no condition, plays
## unmodified. Set from `selected_condition_id` (start-screen selector) at the start of
## every run.
var current_condition = null
var condition_id := ""

var enemies: Array = [] # Array[Enemy]
var taxis: Array = [] # Array[Taxi] — Manhattan only
var pedestrians: Array = [] # Array[Pedestrian] — Manhattan only (Pedestrian, ManWalkingDog or KidGroup)
var metro_stations: Array = [] # Array[MetroStation] — Manhattan only
var obstacle_root: Node3D
var world_env: WorldEnvironment


func _ready() -> void:
	level_rng.randomize()
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
	hud.condition_selected.connect(_on_condition_selected)
	hud.twitch_toggled.connect(_on_twitch_toggled)
	Twitch.chat_command.connect(_on_twitch_command)
	Twitch.connection_state_changed.connect(_on_twitch_connection_changed)


## ---------------- level lifecycle ----------------

## Starts one level of the pool (a Levels.POOL entry). Which one is decided by
## the caller: begin_game() draws the first, next_level() the following.
func start_level(level: Dictionary) -> void:
	current_level = level
	level_id = level.id
	maze = MazeGen.generate_maze(level.rows, level.cols, level.seed, LevelsScript.maze_opts(level))
	start_cell = LevelsScript.start_cell(MazeGen, maze)
	level_chat_assisted = false

	maze_view.build(maze, start_cell, "normal", [], [], level_index >= FEAR_FIRST_LEVEL, level.get("look", ""))
	hud.set_explorer_hud(false)
	_apply_theme_environment("normal")
	fruit_spawned = false
	word_mode_until = 0.0
	fear_mode_until = 0.0
	_fear_condition_instance = null
	player.active_condition = current_condition # in case a Fear & Loathing pickup was interrupted by a restart, mid-effect
	frightened_until = 0.0 # Code-W4: a power-pellet window must never survive into the next level/attempt
	combo_count = 0
	# Warp to the fresh start_cell BEFORE refreshing noclip, not after —
	# _refresh_noclip() can relocate the player via _rescue_player_from_wall()
	# if collision just turned on, and running that against the PREVIOUS
	# level's position/maze risked an unnecessary extra teleport right
	# before warp_to overwrote it anyway.
	player.warp_to(start_cell, _facing_yaw_for_start(start_cell)) # GD-W10: look down the longest open corridor instead of a fixed direction
	_refresh_noclip()
	invuln_until = now + 1.2

	for e in enemies:
		e.queue_free()
	enemies.clear()
	_clear_manhattan_obstacles() # normal levels never have any; defensive
	var house_cells := []
	for r in range(maze.house.r0 + 1, maze.house.r1):
		for c in range(maze.house.c0 + 1, maze.house.c1):
			house_cells.append(Vector2i(r, c))

	var extra := maxi(0, level_index - (LevelsScript.POOL.size() - 1)) # only after more levels than the pool has
	var ghost_count: int = level.ghost_count + mini(extra, 3)
	for i in ghost_count:
		var enemy := Node3D.new()
		enemy.set_script(load("res://scripts/enemy.gd"))
		enemy_root.add_child(enemy)
		var ghost_colors: Array = maze_view.ghost_palette()
		var pal: Dictionary = ghost_colors[i % ghost_colors.size()]
		enemy.frightened_color = maze_view.city_theme.ghost_frightened_color
		enemy.frightened_emission = maze_view.city_theme.ghost_frightened_emission
		enemy.emission_energy = maze_view.city_theme.ghost_emission_energy
		enemy.setup(pal.color, pal.glow, minf(level.ghost_speed + i * 0.05 + extra * 0.15, GHOST_SPEED_CAP)) # GD-N1: capped so ghosts never outrun the player past the tuned levels
		var cell: Vector2i = house_cells[i % house_cells.size()]
		enemy.place_in_house(cell)
		enemy.release_at = now + 1.5 + i * 1.4
		enemies.append(enemy)

	hud.set_level(level_index + 1)
	hud.set_score(score)
	hud.set_lives(lives)
	hud.set_best_time(Speedrun.best_for(level_id, condition_id, "solo"))
	level_start_real = real_now


## `forced_level_id` ("" = random) lets tests and a future level picker start
## on a specific level; normal runs start on a random level of the pool.
func begin_game(forced_level_id: String = "") -> void:
	Sfx.stop_all()
	score = 0
	lives = 3
	playing_manhattan = false
	level_index = 0
	played_ids.clear()
	set_condition(selected_condition_id)
	hud.hide_all_panels()
	if forced_level_id != "":
		start_level(LevelsScript.by_id(forced_level_id))
	else:
		start_level(LevelsScript.draw_next([], "", level_rng))
	running = true
	paused = false
	player.input_enabled = true
	Sfx.set_siren(true, false)
	Sfx.play_arcade_music()
	if not OS.has_feature("web"):
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


## ---------------- Manhattan bonus level ----------------
## An untimed hub level: no clock, no score, no high score, no completion.
## The pellets are only signposts that lead to the SUBWAY signs, and a SUBWAY
## sign is the exit into a speedrun (see _enter_metro). Reuses MazeView and the
## pause against a hand-built real-Midtown-grid Maze instead of a
## MazeGen.generate_maze() result.
func start_manhattan_level() -> void:
	var mm = load("res://scripts/manhattan_maze.gd").new()
	maze = mm.generate()
	mm.free()

	start_cell = maze.start_cell
	current_level = {}
	level_id = ""

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
	player.active_condition = current_condition
	frightened_until = 0.0
	combo_count = 0
	# Warp before refreshing noclip, not after — see start_level()'s matching comment.
	player.warp_to(start_cell, _facing_yaw_for_start(start_cell)) # GD-W10
	_refresh_noclip()
	invuln_until = now + 1.2

	for e in enemies:
		e.queue_free()
	enemies.clear() # Manhattan has no ghosts — see this function's header comment

	_spawn_manhattan_obstacles()
	_spawn_metro_stations(metro_cells)

	hud.set_level("MANHATTAN")
	hud.set_explorer_hud(true) # no timer / score / lives / best time here


## ---------------- start facing / noclip-end safety ----------------

## Review finding GD-W10: the start cell sits in the bottom-most room row,
## and the old fixed `warp_to(start_cell, PI)` faced the camera straight at
## the (1-unit-away) outer wall there, every single run — "jedes Matrix-
## Level beginnt mit Blick auf die Außenwand". Picks the start cell's open
## neighbor with the longest straight corridor behind it instead, so the
## player always spawns looking down a real passage.
func _facing_yaw_for_start(cell: Vector2i) -> float:
	# yaw convention matches player_controller.gd's _physics_process
	# (dir_x = -sin(yaw), dir_z = -cos(yaw)): yaw=0 faces -Z/north (row-1),
	# PI faces +Z/south (row+1), -PI/2 faces +X/east (col+1), PI/2 faces
	# -X/west (col-1).
	var dirs := [
		{"dr": -1, "dc": 0, "yaw": 0.0},
		{"dr": 1, "dc": 0, "yaw": PI},
		{"dr": 0, "dc": 1, "yaw": -PI / 2.0},
		{"dr": 0, "dc": -1, "yaw": PI / 2.0},
	]
	var best_yaw := PI # fallback: old default, only used if the start cell is somehow fully enclosed
	var best_len := -1
	for d in dirs:
		if not MazeGen.is_open(maze, cell.x + d.dr, cell.y + d.dc):
			continue
		var length := 0
		var rr: int = cell.x
		var cc: int = cell.y
		# Code-review follow-up: MazeGen.is_open() does NOT wrap the column
		# index — it CLAMPS any out-of-range column to the nearest edge
		# column (0 or cols-1) and only returns false for an out-of-range
		# row. An east/west scan that just kept calling is_open() past the
		# grid edge would therefore keep re-reading that single edge column
		# forever if it happens to be open (which it reliably is on the
		# tunnel row — e.g. Manhattan's start sits exactly on it), making
		# the scan hit the old hard step cap on every such start instead of
		# measuring a real corridor. Stop explicitly at the grid boundary
		# instead of trusting is_open()'s clamp to signal "no further cell".
		var max_steps: int = maze.rows + maze.cols # still kept as a final safety net
		while length < max_steps:
			var nr: int = rr + d.dr
			var nc: int = cc + d.dc
			if nr < 0 or nr >= maze.rows or nc < 0 or nc >= maze.cols:
				break
			if not MazeGen.is_open(maze, nr, nc):
				break
			length += 1
			rr = nr
			cc = nc
		if length > best_len:
			best_len = length
			best_yaw = d.yaw
	return best_yaw


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
## and scores the Manhattan run (see _check_metro_entry).
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


## Proximity check: stepping close enough to a metro station's sign is the
## exit: it starts a speedrun on a random level of the pool (see _enter_metro).
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
	hud.show_levelclear(true, "SUBWAY — los zum Speedrun!")
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


## Starts (or restarts) the Explorer level with the condition picked on the
## start screen. `city_id` is generic for a future second Explorer city (see
## city_themes.gd's EXPLORER_IDS); only Manhattan exists today.
func begin_manhattan_game(city_id: String = "manhattan") -> void:
	Sfx.stop_all()
	score = 0
	lives = 3
	playing_manhattan = true
	set_condition(selected_condition_id)
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
## Manhattan exists today.
func start_explorer_level(city_id: String) -> void:
	explorer_city_id = city_id
	start_manhattan_level()


func _on_manhattan_pressed() -> void:
	begin_manhattan_game()


func _on_condition_selected(id: String) -> void:
	selected_condition_id = id


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
## (early power pellet, early fruit), never take away input or end the run.
## A command that takes effect moves the level's time to the "chat" best time
## and leaderboard (Levels.MODES), so it can never touch the solo records.
func _on_twitch_command(_user: String, command: String, _args: String) -> void:
	if not (running and not paused) or playing_manhattan:
		return
	# GD-K3/Code-W7: any chat command that actually did something marks the
	# run currently being timed as assisted — see level_complete_sequence /
	# manhattan_complete_sequence, which then skip writing the time to
	# Speedrun.best_times / Leaderboard so a viewer's (or the streamer's own
	# phone's) !power can't trivialize or falsify a recorded run.
	match command:
		"power":
			_mark_chat_assisted()
			frightened_until = now + FRIGHTENED_DURATION
			combo_count = 0
			Sfx.power()
			Sfx.set_siren(true, true)
			for enemy in enemies:
				if enemy.mode == "chase":
					enemy.mode = "frightened"
		"fruit":
			if not fruit_spawned:
				_mark_chat_assisted()
				fruit_spawned = true
				maze_view.spawn_fruit(now)


func _mark_chat_assisted() -> void:
	if level_chat_assisted:
		return
	level_chat_assisted = true
	hud.set_best_time(Speedrun.best_for(level_id, condition_id, "chat"))
	hud.set_mode_badge("CHAT")


## The mode of the current level's records: "chat" once a chat command took
## effect, otherwise "solo" (pvp / coop are reserved for multiplayer).
func run_mode() -> String:
	return "chat" if level_chat_assisted else "solo"


func next_level() -> void:
	# invuln_until is set by start_level() itself a few lines in (review
	# finding Code-W4: an earlier `invuln_until = now + 0.5` here was dead
	# code, always immediately overwritten).
	level_index += 1
	start_level(LevelsScript.draw_next(played_ids, level_id, level_rng))


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

	var elapsed := real_now - level_start_real
	var mode := run_mode()
	var cleared_id := level_id
	var cleared_name: String = current_level.name
	var result := Speedrun.record_level_time(cleared_id, elapsed, condition_id, mode)
	Leaderboard.submit_time(cleared_id, condition_id, elapsed, Leaderboard.DEFAULT_PLAYER_NAME, mode)
	played_ids.append(cleared_id)
	var subtitle := "%s  ·  Zeit %s" % [cleared_name, Speedrun.format_time(elapsed)]
	if mode != "solo":
		subtitle += "  ·  %s-Bestenliste" % LevelsScript.MODE_LABELS[mode]
	if result.newly_unlocked_bonus:
		subtitle += "  ·  ZIELZEIT GESCHAFFT!"
		Sfx.eat_enemy()
		hud.set_bonus_unlocked(true)
	elif result.is_new_best:
		subtitle += "  ·  neue Bestzeit!"
	elif result.beat_target:
		subtitle += "  ·  unter Zielzeit " + Speedrun.format_time(result.target)
	hud.set_best_time(Speedrun.best_for(cleared_id, condition_id, mode))

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
	if playing_manhattan:
		begin_manhattan_game()
	else:
		begin_game()


func toggle_pause() -> void:
	if not running:
		return
	paused = not paused
	if paused:
		hud.set_pause_note(not playing_manhattan)
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
	if OS.is_debug_build() and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F3:
		debug_mode = not debug_mode
		hud.set_debug_overlay(debug_mode)
	if running and not paused and event is InputEventMouseButton and event.pressed:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _process(delta: float) -> void:
	real_now += delta
	if running:
		# The speedrun clock keeps running in the pause (see `real_now`).
		hud.set_timer(real_now - level_start_real)
	if not (running and not paused):
		return
	now += delta

	player.wrap_tunnel(maze.cols * CELL)
	_keep_noclip_player_in_maze() # GD-K2/Code-K1: a noclipping player must not be able to walk out through the unbounded north/south outer wall

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

	if fear_mode_until > 0.0 and now >= fear_mode_until:
		_deactivate_fear_powerup()

	if current_condition != null:
		current_condition.on_process(delta, self)

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
			_add_score(pts)
			Sfx.eat_enemy()
			hud.set_score(score)
		else:
			lose_life()


## All points go through here: the Fear pickup doubles them while it runs.
func _add_score(points: int) -> void:
	if fear_mode_until > 0.0:
		points *= FEAR_SCORE_MULTIPLIER
	score += points


func _check_pickups() -> void:
	var result: Dictionary = maze_view.consume_at(player.global_position, now)

	# Manhattan: the pellets are signposts to the SUBWAY signs, nothing more —
	# no score, no fruit, no completion.
	if playing_manhattan:
		if result.pellet or result.power:
			Sfx.munch()
		return

	if result.pellet:
		_add_score(10)
	if result.power:
		_add_score(50)
		frightened_until = now + FRIGHTENED_DURATION
		combo_count = 0
		Sfx.power()
		Sfx.set_siren(true, true)
		for enemy in enemies:
			if enemy.mode == "chase":
				enemy.mode = "frightened"
	if result.fruit:
		_add_score(150 + level_index * 50)
		Sfx.fruit()
	if result.word_powerup:
		_add_score(75)
		_activate_word_mode()
	if result.fear_powerup:
		_add_score(75)
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

	# Manhattan is an untimed hub with no completion condition at all (see
	# start_manhattan_level's header comment) — only a metro station ends a
	# visit there (_check_metro_entry/_enter_metro). Collecting every pellet
	# must never trigger level_complete_sequence(), which assumes a normal
	# Levels.POOL level (current_level/level_id would be empty/invalid).
	if not playing_manhattan and maze_view.remaining_pickups() <= 0 and running:
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
	_refresh_noclip()
	for enemy in enemies:
		enemy.set_word_skin(true)
	Sfx.power()


func _deactivate_word_mode() -> void:
	word_mode_until = 0.0
	maze_view.set_word_mode(current_condition != null and current_condition.id == "matrix_ghost")
	for enemy in enemies:
		enemy.set_word_skin(current_condition != null and current_condition.id == "matrix_ghost")
	_refresh_noclip()


## Noclip is derived from the sources that want it (Word Mode, the Matrix
## Ghost condition) instead of being saved and restored, so overlapping
## effects can never leave it stuck on. When it turns off, a player who ended
## up inside a wall is moved to the nearest open cell.
func _noclip_wanted() -> bool:
	if word_mode_until > 0.0:
		return true
	return current_condition != null and current_condition.id == "matrix_ghost"


func _refresh_noclip() -> void:
	var wanted := _noclip_wanted()
	var was := player.collision_mask == 0
	player.set_noclip(wanted)
	if was and not wanted and maze != null:
		_rescue_player_from_wall()


## While noclipping the player may cross walls, but not leave the maze rows
## (the X axis wraps through the tunnel, see wrap_tunnel).
func _keep_noclip_player_in_maze() -> void:
	if player.collision_mask != 0 or maze == null:
		return
	player.global_position.z = clampf(player.global_position.z, 0.0, (maze.rows - 1) * CELL)


func _rescue_player_from_wall() -> void:
	var cell: Vector2i = player.cell()
	if cell.x >= 0 and cell.x < maze.rows and cell.y >= 0 and cell.y < maze.cols and maze.grid[cell.x][cell.y] == 0:
		return
	var best := Vector2i(-1, -1)
	var best_d := INF
	for r in maze.rows:
		for c in maze.cols:
			if maze.grid[r][c] != 0:
				continue
			var d := Vector2(c * CELL - player.global_position.x, r * CELL - player.global_position.z).length()
			if d < best_d:
				best_d = d
				best = Vector2i(r, c)
	if best.x >= 0:
		player.global_position = Vector3(best.y * CELL, player.global_position.y, best.x * CELL)


## ---------------- Fear & Loathing power-up (normal levels only) ----------------
## Risk and reward: FEAR_MODE_DURATION seconds of the Fear & Loathing
## condition's scrambled steering (scripts/conditions/fear_and_loathing.gd,
## reused directly — it only distorts while the player steers) and psychedelic
## walls, for double points (_add_score). Wall collision is NOT touched.
## Whatever whole-run condition (if any) was active is swapped back in
## unchanged afterwards. A second pickup while it runs only extends it.
func _activate_fear_powerup() -> void:
	fear_mode_until = now + FEAR_MODE_DURATION
	Sfx.fear_start()
	if _fear_condition_instance != null:
		return # already running: the timer above was the extension
	_fear_saved_active_condition = player.active_condition
	_fear_condition_instance = ConditionsScript.get_condition("fear_and_loathing")
	_fear_condition_instance.on_start(self)
	player.active_condition = _fear_condition_instance
	maze_view.set_psychedelic(true)


func _deactivate_fear_powerup() -> void:
	fear_mode_until = 0.0
	player.active_condition = _fear_saved_active_condition
	_fear_condition_instance = null
	maze_view.set_psychedelic(false)
	Sfx.fear_end()


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
	_refresh_noclip()


## ---------------- high score persistence ----------------

func _load_highscore() -> int:
	var path: String = SavePathsScript.path(HIGHSCORE_FILE)
	if not FileAccess.file_exists(path):
		return 0
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return 0
	var v := f.get_as_text().strip_edges()
	f.close()
	return v.to_int()


func _save_highscore(v: int) -> void:
	SavePathsScript.write_atomic(SavePathsScript.path(HIGHSCORE_FILE), str(v))
