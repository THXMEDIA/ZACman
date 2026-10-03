extends Node3D
## Main — game orchestrator: level lifecycle, scoring, lives, input wiring,
## enemy/pickup collision. Direct port of the web prototype's game.js logic
## (see web/index.html) onto Godot nodes; MazeGen supplies the same kind of
## verified-connected maze.

const CELL := 2.0
const FRIGHTENED_DURATION := 7.0
## Start intro "Follow the white rabbit. But beware" (spec 2.1): shown for
## this long at every speedrun start; it costs no time — the clock only starts
## with the first movement input after it.
const START_INTRO_S := 2.5
## Rabbit conditions (spec 1.2/2.2): 0.8 s transition wave in and out, tick
## sounds in the last 3 s, Matrix walls fade back in / blink in the last 3 s
## (below 3 Hz).
const CONDITION_TRANSITION_S := 0.8
const CONDITION_WARN_S := 3.0
const MATRIX_BLINK_HZ := 1.5
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
const HIGHSCORE_FILE := "zapmaniac_highscore.txt" # under SavePaths.root (tests redirect it)
## Code-W8: global cooldown (game clock) for each helping chat command. 20 s
## is about three Frightened windows (FRIGHTENED_DURATION 7 s): chat !power
## can never chain Frightened back to back or keep resetting the eat combo,
## covers at most about a third of the level time, and still fires 5–11 times
## in a level of the pool (target times 115–225 s), so the chat stays a
## visible helper. Global, not per user — a per-user cooldown would be
## bypassed by any chat with more than a handful of viewers.
const CHAT_COMMAND_COOLDOWN_S := 20.0

## Once a run has played more levels than the pool has (second round,
## Levels.POOL), start_level() keeps raising ghost speed by `extra * 0.15`
## per level (see start_level's `extra`) —
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
## just something to walk around (Main._check_explorer_obstacles). Both
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
const ConditionLooksScript := preload("res://scripts/condition_looks.gd")
const WhiteRabbitScript := preload("res://scripts/white_rabbit.gd")
const SettingsScript := preload("res://scripts/settings.gd")
const SavePathsScript := preload("res://scripts/save_paths.gd")
const ChatVoteScript := preload("res://scripts/chat_vote.gd")
const ExplorerCitiesScript := preload("res://scripts/explorer_cities.gd")

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
## N6: every random choice Main makes goes through one of these generators,
## never the global randf()/randi(), so tests and tools can make a whole run
## reproducible with seed_randomness(). Normal games randomize them in _ready.
##   level_rng          which level comes next (Levels.draw_next), Manhattan spawns
##   ai_rng             the ghosts' random turns while frightened (Enemy.rng)
##   chaos_rng_source   seeds of the "real randomness" rabbit generators
##                      (Chaos mode, chat-shifted rabbits); null = randomize()
var level_rng := RandomNumberGenerator.new()
var ai_rng := RandomNumberGenerator.new()
var chaos_rng_source: RandomNumberGenerator = null
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
## `now` is the game clock: effect timers (Frightened, conditions, invulnerability,
## ghost release, fruit) are all relative to it, and it stands still while the
## game is paused. `real_now` never stops — the Speedrun time is measured on it,
## so pausing does not stop the clock (no pause abuse in a speedrun).
var now := 0.0
var real_now := 0.0
var level_start_real := 0.0
## true once the Twitch chat had a hand in the current level (a !power/!fruit
## took effect, or the chat shifted the rabbit's good/bad ratio); the level's
## time then goes to the "chat" board, never to woche/chaos (Levels.BOARDS).
var level_chat_assisted := false
## Code-W8 (Entscheidung Studio Head): true once the chat had a hand in ANY
## level of this run; the run's score then never becomes the high score.
var run_chat_assisted := false
## N2: the board the level counts on unless the chat steps in, frozen at the
## level start (woche or chaos) — switching Chaos mode mid-level changes
## nothing for the running level.
var level_board := ""
## The condition the rabbit gave in this level ("" = rabbit left alone);
## stored with the leaderboard entry (GD: Bestenliste-Metadatum).
var level_condition_id := ""
## true while an Explorer city runs (Manhattan, Tokyo — explorer_cities.gd);
## explorer_city_id says which one.
var playing_explorer := false
## Kept for the tests and tools written against Manhattan: true while the
## Explorer city Manhattan runs.
var playing_manhattan: bool:
	get:
		return playing_explorer and explorer_city_id == "manhattan"
## Number of finished games (end_game), for tests (double death, Code).
signal game_over
var games_ended := 0
## Tools (tools/qa/qa_rabbit_balance.gd): force the rabbit's result instead of
## drawing it ("" = draw normally). Never set by the game itself.
var forced_rabbit_condition := ""
var forced_fl_manipulation := ""
## Twitch votes on the rabbit (!gut / !schlecht, spec 2.6), on `real_now`.
var chat_vote = ChatVoteScript.new()
## command -> game-clock time until which it is ignored (Code-W8 cooldown);
## cleared at every run start.
var _chat_cooldown_until := {}
## Bumped by every run start and every way out of a run, so a pending
## level-clear sequence does not continue into a run that is already gone.
var _run_token := 0
var _chat_hud_next_update := 0.0

## ---- Speedrun start hold (spec 2.1) ----
## true from begin_game() until the first movement input after the start
## intro: the world waits (game clock, ghosts, effects stand still), the clock
## shows 0:00.00 and walking is locked while the intro is up. next_level()
## does not hold (no intro between levels).
var start_hold := false
var intro_until_real := 0.0
## Tests / tools: start a speedrun without the intro and the hold (the clock
## then starts with the level, like next_level).
var skip_start_intro := false
## UX-W7: how many start intros this session has shown. From the second one
## on (NEUSTART / NOCHMAL) any key skips it.
var intros_shown := 0
## W3: where the player stood when the hold released (tests: must be the
## exact start position — walking only begins together with the clock).
var hold_release_position := Vector3.ZERO

## ---- Rabbit condition (spec 2.2-2.5) ----
## THE active condition — the single source of truth (Code-W1 came from a
## second, parallel "pickup condition"). null = none. Everything that depends
## on it (noclip, ghost speed, minimap, look, HUD card) is derived from it.
var active_condition = null
var condition_started_at := 0.0 # game clock (`now`)
var condition_until := 0.0 # game clock (`now`)
var _last_tick_second := -1
## Object style currently applied (outline, fog exemption) — two plain bools,
## compared without building an array every frame (W2).
var _style_outline := false
var _style_ignore_fog := false
## W2: no allocation per frame while a condition runs. The look's data is
## looked up once at start_condition, the base environment is cached when a
## theme environment is applied, and shader uniforms / the environment are
## only touched when their value changes.
var _active_look: Dictionary = {}
var _env_base_bg := Color()
var _env_base_fog := Color()
var _env_base_fog_density := 0.0
var _env_base_ambient := Color()
var _env_base_ambient_energy := 0.0
var _vis_t := -1.0
var _vis_flip := -1.0
var _vis_solid := -1.0
## Resource counters (tests, W2): how often the environment was blended and
## a look uniform was written since the last condition start.
var env_blend_count := 0
var look_param_count := 0
## The "Kaninchen der Woche" generator of the current level (re-created at
## every level start from level id + ISO week, so a restart never re-rolls).
var rabbit_rng: RandomNumberGenerator = null
var rabbit_week := Vector2i(0, 0)
## Tests: force a week instead of the player's current local ISO week.
var rabbit_week_override := Vector2i(0, 0)

## "Effekte reduzieren" (spec 1.2), persisted via Settings.
var reduce_fx := false
## Chaos mode (spec 2.5, start screen switch, persisted via Settings): real
## randomness for every rabbit, own board "chaos".
var chaos_mode := false
## Comfort (UX-K1, persisted via Settings): field of view and mouse
## sensitivity (factor on PlayerController.MOUSE_SENSITIVITY).
var fov := 72.0
var mouse_sens := 1.0

## Debug overlay (FPS, player position, cell): toggled with F3, debug builds only.
var debug_mode := false

## Which Explorer city (explorer_cities.gd: "manhattan", "tokyo") the
## current/last Explorer run was played on (see start_explorer_level).
var explorer_city_id := "manhattan"

var enemies: Array = [] # Array[Enemy]
var taxis: Array = [] # Array[Taxi] — Manhattan only
var pedestrians: Array = [] # Array[Pedestrian] — Manhattan only (Pedestrian, ManWalkingDog or KidGroup)
var metro_stations: Array = [] # Array[MetroStation] — Manhattan only
var obstacle_root: Node3D
var world_env: WorldEnvironment


func _ready() -> void:
	level_rng.randomize()
	ai_rng.randomize()
	high_score = _load_highscore()
	var settings := SettingsScript.load_settings()
	reduce_fx = settings.reduce_fx
	chaos_mode = settings.chaos
	fov = settings.fov
	mouse_sens = settings.mouse_sens
	_build_environment()
	_build_player()
	_apply_comfort()
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
	hud.set_reduce_fx(reduce_fx)
	hud.set_chaos_mode(chaos_mode)
	hud.set_comfort(fov, mouse_sens)
	hud.set_game_hud_visible(false)
	hud.show_only(hud.start_panel)


## N6: makes every random choice of Main reproducible (tests, tools): level
## draw, the ghosts' frightened turns and the "real randomness" rabbits.
func seed_randomness(s: int) -> void:
	level_rng.seed = s
	ai_rng.seed = s + 1
	chaos_rng_source = RandomNumberGenerator.new()
	chaos_rng_source.seed = s + 2


## A generator with "real randomness" for Chaos mode and chat-shifted
## rabbits: a random seed — or, when a test injected chaos_rng_source, the
## next seed from it (N6: tests stay deterministic).
func _new_chaos_rng() -> RandomNumberGenerator:
	if chaos_rng_source == null:
		return WhiteRabbitScript.chaos_rng()
	var r := RandomNumberGenerator.new()
	r.seed = chaos_rng_source.randi()
	return r


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
	_apply_theme_environment("normal")


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
	env.fog_sky_affect = ct.env_fog_sky_affect
	env.ambient_light_color = ct.env_ambient_color
	env.ambient_light_energy = ct.env_ambient_energy
	# Post-processing is set from the theme on EVERY switch (also back to the
	# speedrun), so Tokyo's glow, SSR or volumetric fog can never stay on in
	# the next level (docs/design/tokyo-explorer.md, technical condition).
	env.glow_enabled = ct.env_glow_enabled
	env.glow_intensity = ct.env_glow_intensity
	env.glow_strength = ct.env_glow_strength
	env.glow_bloom = ct.env_glow_bloom
	env.glow_hdr_threshold = ct.env_glow_hdr_threshold
	for i in ct.env_glow_levels.size():
		env.set_glow_level(i, ct.env_glow_levels[i])
	env.ssr_enabled = ct.env_ssr_enabled
	env.ssr_max_steps = ct.env_ssr_max_steps
	env.ssr_fade_in = ct.env_ssr_fade_in
	env.ssr_fade_out = ct.env_ssr_fade_out
	env.ssr_depth_tolerance = ct.env_ssr_depth_tolerance
	env.volumetric_fog_enabled = ct.env_volumetric_fog_enabled
	env.tonemap_mode = ct.env_tonemap_mode
	env.tonemap_exposure = ct.env_tonemap_exposure
	env.tonemap_white = ct.env_tonemap_white
	if player != null and player.camera != null:
		player.camera.far = ct.camera_far
		if player.light != null:
			player.light.light_color = ct.player_light_color
			player.light.light_energy = ct.player_light_energy
			player.light.omni_range = ct.player_light_range
	# W2: the base a condition look blends from, cached once here (at the
	# level start) instead of building the theme again every frame.
	_env_base_bg = ct.env_bg_color
	_env_base_fog = ct.env_fog_color
	_env_base_fog_density = ct.env_fog_density
	_env_base_ambient = ct.env_ambient_color
	_env_base_ambient_energy = ct.env_ambient_energy


func _build_player() -> void:
	player = CharacterBody3D.new()
	player.set_script(load("res://scripts/player_controller.gd"))
	add_child(player)
	player.input_enabled = false


## UX-K1: field of view and mouse sensitivity from the settings. Set once by
## the player (never animated — no FOV pulsing, red line E8e).
func _apply_comfort() -> void:
	if player == null:
		return
	player.camera.fov = fov
	player.mouse_sensitivity_scale = mouse_sens


func set_fov(v: float) -> void:
	fov = clampf(v, SettingsScript.FOV_MIN, SettingsScript.FOV_MAX)
	_apply_comfort()
	_save_settings()
	hud.set_comfort(fov, mouse_sens)


func set_mouse_sens(v: float) -> void:
	mouse_sens = clampf(v, SettingsScript.SENS_MIN, SettingsScript.SENS_MAX)
	_apply_comfort()
	_save_settings()
	hud.set_comfort(fov, mouse_sens)


func _build_hud() -> void:
	hud = CanvasLayer.new()
	hud.set_script(load("res://scripts/hud.gd"))
	add_child(hud)
	hud.start_pressed.connect(_on_start_pressed)
	hud.resume_pressed.connect(_on_resume_pressed)
	hud.restart_pressed.connect(_on_restart_pressed)
	hud.explorer_pressed.connect(_on_explorer_pressed)
	hud.menu_pressed.connect(go_to_main_menu)
	hud.quit_pressed.connect(_on_quit_pressed)
	hud.reduce_fx_toggled.connect(_on_reduce_fx_toggled)
	hud.fov_changed.connect(set_fov)
	hud.mouse_sens_changed.connect(set_mouse_sens)
	hud.chaos_toggled.connect(set_chaos_mode)
	hud.twitch_toggled.connect(_on_twitch_toggled)
	Twitch.chat_command.connect(_on_twitch_command)
	Twitch.connection_state_changed.connect(_on_twitch_connection_changed)


## ---------------- level lifecycle ----------------

## Starts one level of the pool (a Levels.POOL entry). Which one is decided by
## the caller: begin_game() draws the first, next_level() the following.
func start_level(level: Dictionary) -> void:
	_end_condition(false) # a condition never survives into the next level/attempt
	current_level = level
	level_id = level.id
	maze = MazeGen.generate_maze(level.rows, level.cols, level.seed, LevelsScript.maze_opts(level))
	start_cell = LevelsScript.start_cell(MazeGen, maze)
	level_chat_assisted = false
	level_condition_id = ""
	level_board = LevelsScript.BOARD_CHAOS if chaos_mode else LevelsScript.BOARD_WEEK # N2: frozen for this level
	rabbit_rng = _make_rabbit_rng(level_id)

	# The rabbit's position follows the level seed (deterministic per level).
	maze_view.build(maze, start_cell, "normal", [], [], level.seed, level.get("look", ""))
	hud.set_explorer_hud(false)
	hud.set_minimap_visible(true)
	hud.set_game_hud_visible(true)
	_apply_theme_environment("normal")
	_style_outline = false
	_style_ignore_fog = false
	fruit_spawned = false
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
	_clear_explorer_obstacles() # normal levels never have any; defensive
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
		enemy.rng = ai_rng # N6
		enemy.setup(pal.color, pal.glow, minf(level.ghost_speed + i * 0.05 + extra * 0.15, GHOST_SPEED_CAP)) # GD-N1: capped so ghosts never outrun the player past the tuned levels
		var cell: Vector2i = house_cells[i % house_cells.size()]
		enemy.place_in_house(cell)
		enemy.release_at = now + 1.5 + i * 1.4
		enemies.append(enemy)

	hud.set_level(level_index + 1)
	hud.set_score(score)
	hud.set_lives(lives)
	_refresh_board_hud()
	level_start_real = real_now


## `forced_level_id` ("" = random) lets tests and a future level picker start
## on a specific level; normal runs start on a random level of the pool.
func begin_game(forced_level_id: String = "") -> void:
	Sfx.stop_all()
	score = 0
	lives = 3
	playing_explorer = false
	level_index = 0
	played_ids.clear()
	_chat_cooldown_until.clear()
	run_chat_assisted = false
	_run_token += 1
	hud.hide_all_panels()
	# N4: an unknown level id is refused (Levels.by_id returns {}), the run
	# then starts on a random level of the pool instead of silently on the first.
	var level: Dictionary = {}
	if forced_level_id != "":
		level = LevelsScript.by_id(forced_level_id)
		if level.is_empty():
			push_warning("begin_game: unknown level id '%s' — starting a random level" % forced_level_id)
	if level.is_empty():
		level = LevelsScript.draw_next([], "", level_rng)
	start_level(level)
	running = true
	paused = false
	player.input_enabled = true
	_begin_start_hold()
	Sfx.set_siren(true, false)
	Sfx.play_arcade_music()
	if not OS.has_feature("web"):
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


## ---------------- Explorer cities (Manhattan, Tokyo) ----------------
## Untimed hub levels: no clock, no score, no high score, no completion, no
## ghosts, no rabbit. The pellets are only signposts that lead to the subway,
## and the subway is the exit into a speedrun (see _enter_metro). Reuses
## MazeView and the pause against the city's hand-built grid (its maze
## script) instead of a MazeGen.generate_maze() result. What differs per
## city (theme, grid, metro placement, traffic, level seed) comes from
## explorer_cities.gd — this code has no city names in it.
func start_explorer_level(city_id: String) -> void:
	var city := ExplorerCitiesScript.get_city(city_id)
	if city.is_empty():
		push_warning("start_explorer_level: unknown city '%s' — Manhattan instead" % city_id)
		city_id = "manhattan"
		city = ExplorerCitiesScript.get_city(city_id)
	explorer_city_id = city_id
	_end_condition(false)
	var mm = load(city.maze_script).new()
	maze = mm.generate()
	if mm is Node:
		mm.free()

	start_cell = maze.start_cell
	current_level = {}
	level_id = ""

	# Metro-station cells are picked before the maze view builds its
	# pellets and handed in as reserved cells, so a metro sign can never
	# end up parked on top of a pellet the player could never then reach.
	# Pedestrians walk the streets like traffic (see _spawn_manhattan_
	# obstacles), so they no longer need a reserved home cell of their own.
	var metro_cells: Array
	if city.metro == "maze":
		metro_cells = load(city.maze_script).metro_cells()
	else:
		metro_cells = _pick_random_metro_cells(int(city.metro_count))
	var reserved_cells: Array = metro_cells
	maze_view.build(maze, start_cell, city.theme, reserved_cells, metro_cells, -1, "", int(city.seed))
	_apply_theme_environment(city.theme)
	fruit_spawned = false
	frightened_until = 0.0
	combo_count = 0
	# Warp before refreshing noclip, not after — see start_level()'s matching comment.
	player.warp_to(start_cell, _facing_yaw_for_start(start_cell)) # GD-W10
	_refresh_noclip()
	invuln_until = now + 1.2

	for e in enemies:
		e.queue_free()
	enemies.clear() # Explorer cities have no ghosts — see this function's header comment

	_clear_explorer_obstacles()
	if city.traffic == "manhattan":
		_spawn_manhattan_obstacles()
	_spawn_metro_stations(metro_cells, city.metro_script)

	hud.set_level(city.label)
	hud.set_game_hud_visible(true)
	hud.set_explorer_hud(true) # no timer / score / lives / best time here
	hud.set_minimap_visible(true)


## Manhattan, kept as a name for the tests and tools written against it.
func start_manhattan_level() -> void:
	start_explorer_level("manhattan")


## The registry entry of the running (or last) Explorer city.
func _explorer_city() -> Dictionary:
	return ExplorerCitiesScript.get_city(explorer_city_id)


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


func _clear_explorer_obstacles() -> void:
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
## `count` random open room cells (Manhattan: MANHATTAN_METRO_COUNT).
func _pick_random_metro_cells(count: int = MANHATTAN_METRO_COUNT) -> Array:
	var open_cells: Array = MazeGen.cells_in_room(maze, false)
	_shuffle(open_cells)
	var picked := []
	for cell in open_cells:
		if picked.size() >= count:
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


## Fisher-Yates on level_rng (N6: Array.shuffle() would use the global generator).
func _shuffle(a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := level_rng.randi_range(0, i)
		var tmp = a[i]
		a[i] = a[j]
		a[j] = tmp


func _pick_weighted_vehicle(pool: Array) -> Dictionary:
	var total := 0
	for v in pool:
		total += int(v["weight"])
	var roll := level_rng.randi() % total
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
	_clear_explorer_obstacles()

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
	_shuffle(row_choices)
	_shuffle(col_choices)

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
		var speed: float = v["speed_min"] + level_rng.randf() * (v["speed_max"] - v["speed_min"])
		taxi.setup("row", row_choices[i] * CELL, min_x, max_x, speed, v["word"], v["color"], v["font_size"], MANHATTAN_VEHICLE_LANE_OFFSET)
		taxis.append(taxi)
	for i in mini(MANHATTAN_TAXI_COL_COUNT, col_choices.size()):
		var taxi2 := Node3D.new()
		taxi2.set_script(load("res://scripts/taxi.gd"))
		obstacle_root.add_child(taxi2)
		var v2 := _pick_weighted_vehicle(vehicle_pool)
		var speed2: float = v2["speed_min"] + level_rng.randf() * (v2["speed_max"] - v2["speed_min"])
		taxi2.setup("col", col_choices[i] * CELL, min_z, max_z, speed2, v2["word"], v2["color"], v2["font_size"], MANHATTAN_VEHICLE_LANE_OFFSET)
		taxis.append(taxi2)

	var pedestrian_scripts := [
		"res://scripts/pedestrian.gd",
		"res://scripts/man_walking_dog.gd",
		"res://scripts/kid_group.gd",
		"res://scripts/dad_and_kid.gd",
	]
	for i in MANHATTAN_PEDESTRIAN_COUNT:
		var script_path: String = pedestrian_scripts[level_rng.randi() % pedestrian_scripts.size()]
		var ped := Node3D.new()
		ped.set_script(load(script_path))
		obstacle_root.add_child(ped)
		var speed := 0.8 + level_rng.randf() * 0.7
		var side := 1.0 if level_rng.randf() > 0.5 else -1.0 # which building edge's sidewalk, so both sides of a street get walked
		if row_choices.is_empty() or (not col_choices.is_empty() and level_rng.randf() > 0.5):
			var col: int = col_choices[level_rng.randi() % col_choices.size()]
			ped.setup(Vector3(col * CELL + side * MANHATTAN_SIDEWALK_OFFSET, 0.4, min_z), "col", min_z, max_z, speed)
		else:
			var row: int = row_choices[level_rng.randi() % row_choices.size()]
			ped.setup(Vector3(min_x, 0.4, row * CELL + side * MANHATTAN_SIDEWALK_OFFSET), "row", min_x, max_x, speed)
		pedestrians.append(ped)


## The subway signs at the reserved metro cells (Manhattan: glowing
## "SUBWAY", Tokyo: the green 地下鉄 exit); entering one ends the Explorer
## run and starts a speedrun (see _check_metro_entry).
func _spawn_metro_stations(metro_cells: Array, script_path: String = "res://scripts/metro_station.gd") -> void:
	for cell in metro_cells:
		var station := Node3D.new()
		station.set_script(load(script_path))
		obstacle_root.add_child(station)
		station.setup(Vector3(cell.y * CELL, 0.9, cell.x * CELL))
		metro_stations.append(station)


func _check_explorer_obstacles() -> void:
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
	hud.show_levelclear(true, _explorer_city().get("exit_text", "SUBWAY — los zum Speedrun!"))
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	var token := _run_token
	await get_tree().create_timer(1.4).timeout
	if token != _run_token:
		return
	hud.show_levelclear(false)
	playing_explorer = false
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


## Starts (or restarts) an Explorer city (explorer_cities.gd: "manhattan",
## "tokyo"). Explorer levels have no rabbit and no conditions.
func begin_explorer_game(city_id: String = "manhattan") -> void:
	Sfx.stop_all()
	_run_token += 1
	score = 0
	lives = 3
	start_hold = false
	player.movement_locked = false
	hud.show_start_intro(false)
	hud.show_clock_hint(false)
	hud.hide_all_panels()
	playing_explorer = true
	start_explorer_level(city_id)
	running = true
	paused = false
	player.input_enabled = true
	Sfx.set_siren(true, false)
	Sfx.play_explorer_music()
	if not OS.has_feature("web"):
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


## Manhattan (or `city_id`), kept as a name for the tests and tools written
## against it.
func begin_manhattan_game(city_id: String = "manhattan") -> void:
	begin_explorer_game(city_id)


func _on_explorer_pressed(city_id: String) -> void:
	begin_explorer_game(city_id)


func _on_reduce_fx_toggled(on: bool) -> void:
	set_reduce_fx(on)


## "Effekte reduzieren": stored right away and applied to a running look.
func set_reduce_fx(on: bool) -> void:
	reduce_fx = on
	_save_settings()
	hud.set_reduce_fx(on)
	if maze_view != null and maze_view.normal_wall_mmi != null:
		maze_view.set_look_param("reduce_fx", 1.0 if on else 0.0)
	_vis_flip = -1.0 # re-evaluate the Kippbild frame next frame
	if not on:
		hud.set_flip_frame(0.0)


## Chaos mode (start screen switch): stored right away; takes effect with the
## next level start (a running level keeps the generator and board it began
## with — the switch is only on the start screen anyway).
func set_chaos_mode(on: bool) -> void:
	chaos_mode = on
	_save_settings()
	hud.set_chaos_mode(on)


func _save_settings() -> void:
	SettingsScript.save_settings({"reduce_fx": reduce_fx, "chaos": chaos_mode, "fov": fov, "mouse_sens": mouse_sens})


## ---------------- speedrun start: intro and hold (spec 2.1) ----------------

func _begin_start_hold() -> void:
	if skip_start_intro:
		start_hold = false
		player.movement_locked = false
		hud.show_start_intro(false)
		hud.show_clock_hint(false)
		return
	start_hold = true
	intro_until_real = real_now + START_INTRO_S
	level_start_real = real_now
	player.movement_locked = true
	intros_shown += 1
	hud.show_start_intro(true, intros_shown > 1)
	hud.show_clock_hint(false)


## UX-W7: from the second start of the session on, any key skips the intro.
func intro_skippable() -> bool:
	return start_hold and intros_shown > 1 and real_now < intro_until_real


func skip_intro() -> void:
	if intro_skippable():
		intro_until_real = real_now


## While holding: the intro runs out, then a small line "Die Uhr startet mit
## deinem ersten Schritt" stays until the first movement input. That input
## releases the world AND the legs together with the clock (W3): walking stays
## locked until the very frame the clock starts, so the player stands exactly
## on the start position when the time begins (intro and waiting cost no time).
func _update_start_hold() -> void:
	level_start_real = real_now
	if real_now < intro_until_real:
		return
	if hud.is_start_intro_visible():
		hud.show_start_intro(false)
		hud.show_clock_hint(true)
	if not paused and player.has_move_input():
		start_hold = false
		hold_release_position = player.global_position
		player.movement_locked = false
		hud.show_clock_hint(false)


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
		chat_vote.clear()
		hud.set_twitch_status("Aus — für ernsthafte Speedruns ausgeschaltet lassen.")


func _on_twitch_connection_changed(is_connected: bool) -> void:
	_update_chat_hud(true)
	if is_connected:
		hud.set_twitch_status("Verbunden mit #%s — !power, !fruit, !gut und !schlecht sind aktiv." % Twitch.channel)
	elif Twitch.enabled:
		hud.set_twitch_status("Verbindung getrennt.")


## Viewer chat commands, opt-in only (see Twitch.enabled / the start-screen
## toggle). !power / !fruit can only help the player (early power pellet,
## early fruit), never take away input or end the run; each has a global
## cooldown (CHAT_COMMAND_COOLDOWN_S). !gut / !schlecht are votes on the next
## rabbit (spec 2.6) and are counted at any time, also between levels.
## A helping command that takes effect moves the level's time to the "chat"
## board (_mark_chat_assisted), so it can never touch woche/chaos records.
func _on_twitch_command(user: String, command: String, _args: String) -> void:
	if command == "gut" or command == "schlecht":
		chat_vote.vote(user, command == "gut", real_now)
		_update_chat_hud(true)
		return
	if not (running and not paused) or playing_explorer or start_hold:
		return
	if now < float(_chat_cooldown_until.get(command, -1.0)):
		return
	match command:
		"power":
			_chat_cooldown_until[command] = now + CHAT_COMMAND_COOLDOWN_S
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
				_chat_cooldown_until[command] = now + CHAT_COMMAND_COOLDOWN_S
				_mark_chat_assisted()
				fruit_spawned = true
				maze_view.spawn_fruit(now)


## The chat had a hand in this level: from now on its time counts on the
## "chat" board (spec 2.6), never on woche/chaos.
func _mark_chat_assisted() -> void:
	run_chat_assisted = true
	if level_chat_assisted:
		return
	level_chat_assisted = true
	_refresh_board_hud()


## The mode of the current level's records. Always "solo" until multiplayer
## exists (pvp / coop are reserved); chat help is a board, not a mode.
func run_mode() -> String:
	return "solo"


## The board of the current level's records (spec 2.5): "chat" as soon as the
## chat had a hand in the level, otherwise "chaos" in Chaos mode, otherwise
## the weekly rabbit board. The condition is not part of the key.
func board_id() -> String:
	if level_chat_assisted:
		return LevelsScript.BOARD_CHAT
	if level_board != "":
		return level_board # N2: frozen at the level start
	return LevelsScript.BOARD_CHAOS if chaos_mode else LevelsScript.BOARD_WEEK


## The ISO week of the current level's rabbits as stored with a time
## ("2026-W40"); "" off the weekly board.
func board_week_label() -> String:
	if board_id() != LevelsScript.BOARD_WEEK:
		return ""
	return WhiteRabbitScript.week_label(rabbit_week)


## HUD: board badge ("KW 40" / "CHAOS" / "CHAT") and the best time of the
## board the level currently counts on (with its week on the weekly board).
func _refresh_board_hud() -> void:
	if level_id == "":
		return
	var board := board_id()
	hud.current_week = rabbit_week
	hud.set_board_badge(board, WhiteRabbitScript.week_display(WhiteRabbitScript.week_label(rabbit_week), rabbit_week))
	var best: Dictionary = Speedrun.best_entry(level_id, board, run_mode())
	var week_text := ""
	if board == LevelsScript.BOARD_WEEK and not best.is_empty():
		week_text = WhiteRabbitScript.week_display(best.get("week", ""), rabbit_week)
	hud.set_best_time(float(best.get("time", -1.0)), week_text)


func next_level() -> void:
	# invuln_until is set by start_level() itself a few lines in (review
	# finding Code-W4: an earlier `invuln_until = now + 0.5` here was dead
	# code, always immediately overwritten).
	level_index += 1
	start_level(LevelsScript.draw_next(played_ids, level_id, level_rng))


## W1 (Entscheidung Studio Head): death ends the running condition — no
## Matrix noclip, slowed ghosts, fog or steering manipulation survives a lost
## life. The condition ends first (collision back on), then the player is put
## onto the open start cell, looking down the longest corridor (Code-W7).
## A second ghost touching in the same frame can not cost another life: the
## first hit makes the player invulnerable, and on the last life the game is
## already over (running false), so end_game runs exactly once.
func lose_life() -> void:
	if not running:
		return
	lives -= 1
	Sfx.death()
	hud.set_lives(lives)
	if lives <= 0:
		end_game()
		return
	_end_condition(false)
	player.warp_to(start_cell, _facing_yaw_for_start(start_cell))
	_refresh_noclip()
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
	paused = false
	_run_token += 1
	_end_condition(false)
	start_hold = false
	player.movement_locked = false
	player.input_enabled = false
	hud.show_start_intro(false)
	hud.show_clock_hint(false)
	Sfx.stop_all()
	# Code-W8 Teil 1 (Entscheidung Studio Head): a run the chat helped never
	# becomes the high score.
	var chat_blocked := run_chat_assisted and score > high_score
	if score > high_score and not run_chat_assisted:
		high_score = score
		_save_highscore(high_score)
	var level_display = _explorer_city().get("label", "EXPLORER") if playing_explorer else level_index + 1
	hud.set_game_hud_visible(false)
	hud.show_gameover(score, level_display, high_score, chat_blocked)
	hud.set_bonus_unlocked(Speedrun.is_bonus_unlocked())
	hud.set_start_highscore(high_score)
	playing_explorer = false
	_apply_theme_environment("normal")
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	games_ended += 1
	game_over.emit()


## UX-K2: back to the start screen from the pause or the game over. A run
## that is still going is abandoned without a game over: no high score, no
## board entry.
func go_to_main_menu() -> void:
	running = false
	paused = false
	_run_token += 1
	_end_condition(false)
	start_hold = false
	player.movement_locked = false
	player.input_enabled = false
	hud.show_start_intro(false)
	hud.show_clock_hint(false)
	hud.show_levelclear(false)
	Sfx.stop_all()
	playing_explorer = false
	_apply_theme_environment("normal")
	hud.set_game_hud_visible(false)
	hud.set_start_highscore(high_score)
	hud.set_bonus_unlocked(Speedrun.is_bonus_unlocked())
	hud.show_only(hud.start_panel)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _on_quit_pressed() -> void:
	get_tree().quit()


func level_complete_sequence() -> void:
	running = false
	_end_condition(false)
	Sfx.set_siren(false, false)
	Sfx.level_clear()

	var elapsed := real_now - level_start_real
	var mode := run_mode()
	var board := board_id()
	var week := board_week_label()
	var cleared_id := level_id
	var cleared_name: String = current_level.name
	var result := Speedrun.record_level_time(cleared_id, elapsed, board, mode, week)
	Leaderboard.submit_time(cleared_id, board, elapsed, Leaderboard.DEFAULT_PLAYER_NAME, mode, week, level_condition_id)
	played_ids.append(cleared_id)
	var subtitle := "%s  ·  Zeit %s" % [cleared_name, Speedrun.format_time(elapsed)]
	if board != LevelsScript.BOARD_WEEK:
		subtitle += "  ·  %s-Bestenliste" % LevelsScript.BOARD_LABELS[board]
	if result.newly_unlocked_bonus:
		subtitle += "  ·  ZIELZEIT GESCHAFFT!"
		Sfx.eat_enemy()
		hud.set_bonus_unlocked(true)
	elif result.is_new_best:
		subtitle += "  ·  neue Bestzeit!"
	elif result.beat_target:
		subtitle += "  ·  unter Zielzeit " + Speedrun.format_time(result.target)
	_refresh_board_hud()

	hud.show_levelclear(true, subtitle)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	var token := _run_token
	await get_tree().create_timer(1.7).timeout
	if token != _run_token:
		return # the player went to the menu or a new run started meanwhile
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
	if playing_explorer:
		begin_explorer_game(explorer_city_id)
	else:
		begin_game()


func toggle_pause() -> void:
	if not running:
		return
	paused = not paused
	if paused:
		# QA 03.10. W1: the start intro must never cover the pause menu. Pausing
		# during the intro ends it (the clock is held anyway until the first step).
		if start_hold:
			intro_until_real = real_now
			hud.show_start_intro(false)
			hud.show_clock_hint(false)
		hud.set_pause_note(not playing_explorer)
		hud.set_reduce_fx(reduce_fx)
		hud.set_comfort(fov, mouse_sens)
		hud.set_menu_confirm(not playing_explorer) # UX-K2: abandoning a speedrun asks once
		hud.show_only(hud.pause_panel)
		Sfx.set_siren(false, false)
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		player.input_enabled = false
	else:
		hud.hide_all_panels()
		if start_hold:
			hud.show_clock_hint(true)
		Sfx.set_siren(true, now < frightened_until)
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		player.input_enabled = true


## ---------------- main loop ----------------

func _unhandled_input(event: InputEvent) -> void:
	# UX-W7: from the second start of the session, any key skips the intro.
	if intro_skippable() and event is InputEventKey and event.pressed and not event.echo and not event.is_action_pressed("pause_toggle"):
		skip_intro()
	if event.is_action_pressed("pause_toggle"):
		# UX-K2: Esc closes the Bestenliste (back to where it was opened from).
		if hud.leaderboard_panel.visible:
			hud.close_leaderboard()
		elif hud.is_menu_confirm_open():
			hud.cancel_menu_confirm()
		else:
			toggle_pause()
	if OS.is_debug_build() and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F3:
		debug_mode = not debug_mode
		hud.set_debug_overlay(debug_mode)
	if running and not paused and event is InputEventMouseButton and event.pressed:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _process(delta: float) -> void:
	real_now += delta
	if running and start_hold:
		_update_start_hold()
	if running:
		# The speedrun clock keeps running in the pause (see `real_now`); it
		# stands at 0 while the start hold lasts (level_start_real follows).
		hud.set_timer(real_now - level_start_real)
	_update_chat_hud()
	if not (running and not paused) or start_hold:
		if running and maze != null:
			hud.update_minimap(maze, player, enemies, now < frightened_until, maze_view)
		return
	now += delta

	player.wrap_tunnel(maze.cols * CELL)
	_keep_noclip_player_in_maze() # GD-K2/Code-K1: a noclipping player must not be able to walk out through the unbounded north/south outer wall

	var frightened_active := now < frightened_until
	var player_cell: Vector2i = player.cell()
	var world_width: float = maze.cols * CELL

	if debug_mode:
		hud.update_debug_overlay(Engine.get_frames_per_second(), player.global_position, player_cell)

	var ghost_scale: float = active_condition.ghost_speed_scale() if active_condition != null else 1.0
	for enemy in enemies:
		enemy.speed_scale = ghost_scale
		enemy.update(delta, maze, player_cell, frightened_active, now, world_width)
		_check_enemy_collision(enemy, frightened_active)
		if not running:
			return # the last life is gone: game over exactly once, nothing else this frame

	if playing_explorer:
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

	if playing_explorer:
		_check_explorer_obstacles()
		_check_metro_entry()

	_update_condition(delta)

	hud.set_power_timer(frightened_until - now, FRIGHTENED_DURATION)
	if now >= frightened_until and Sfx.siren_state() == "frightened":
		Sfx.set_siren(true, false)
	hud.set_minimap_visible(active_condition == null or active_condition.minimap_visible())
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


## All points go through here.
func _add_score(points: int) -> void:
	score += points


func _check_pickups() -> void:
	var result: Dictionary = maze_view.consume_at(player.global_position, now)

	# Explorer cities: the pellets are signposts to the subway, nothing more —
	# no score, no fruit, no completion.
	if playing_explorer:
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
	if result.rabbit:
		_on_rabbit_picked()
	if result.pellet or result.power:
		Sfx.munch()
	if result.pellet or result.power or result.fruit:
		hud.set_score(score)

	var total: int = maze_view.total_pickups()
	var eaten: int = total - maze_view.remaining_pickups()
	if not fruit_spawned and total > 0 and eaten >= int(total * 0.4):
		fruit_spawned = true
		maze_view.spawn_fruit(now)

	# Manhattan is an untimed hub with no completion condition at all (see
	# start_explorer_level's header comment) — only a metro station ends a
	# visit there (_check_metro_entry/_enter_metro). Collecting every pellet
	# must never trigger level_complete_sequence(), which assumes a normal
	# Levels.POOL level (current_level/level_id would be empty/invalid).
	if not playing_explorer and maze_view.remaining_pickups() <= 0 and running:
		level_complete_sequence()


## ---------------- noclip (Matrix condition) ----------------

## Noclip is derived from the one active condition instead of being saved and
## restored, so it can never be left stuck on. When it turns off, a player
## whose capsule overlaps a wall is moved to the nearest free cell.
func _noclip_wanted() -> bool:
	return active_condition != null and active_condition.wants_noclip()


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


## Code-N3: checking only the player's cell is not enough — with
## wall_footprint_scale 1.12 a wall reaches 0.12 m into the open cell next
## to it, so a player at the edge of an open cell can still overlap it. The
## capsule is "blocked" if its circle (PLAYER_RADIUS) touches any wall box
## around it, or it is outside the maze rows.
func capsule_blocked_at(pos: Vector3) -> bool:
	var r := int(round(pos.z / CELL))
	var c := int(round(pos.x / CELL))
	if r < 0 or r >= maze.rows:
		return true
	var half: float = CELL * maze_view.city_theme.wall_footprint_scale * 0.5
	var reach: float = player.PLAYER_RADIUS + 0.02
	for dr in [-1, 0, 1]:
		for dc in [-1, 0, 1]:
			var rr: int = r + dr
			var cc: int = c + dc
			if rr < 0 or rr >= maze.rows:
				continue
			var cw := posmod(cc, maze.cols)
			if maze.grid[rr][cw] != 1:
				continue
			var dx := maxf(absf(pos.x - cc * CELL) - half, 0.0)
			var dz := maxf(absf(pos.z - rr * CELL) - half, 0.0)
			if Vector2(dx, dz).length() < reach:
				return true
	return false


## N1: the inside of the ghost house (the cells between its walls) is open
## in the grid but no place to end a Matrix run — the ghosts are released from
## there and the door is the only way out.
func in_ghost_house(pos: Vector3) -> bool:
	if maze == null:
		return false
	var r := int(round(pos.z / CELL))
	var c := int(round(pos.x / CELL))
	return r >= maze.house.r0 and r <= maze.house.r1 and c >= maze.house.c0 and c <= maze.house.c1


func _rescue_player_from_wall() -> void:
	if not capsule_blocked_at(player.global_position) and not in_ghost_house(player.global_position):
		return
	var best := Vector2i(-1, -1)
	var best_d := INF
	for r in maze.rows:
		for c in maze.cols:
			if maze.grid[r][c] != 0:
				continue
			if r >= maze.house.r0 and r <= maze.house.r1 and c >= maze.house.c0 and c <= maze.house.c1:
				continue # never into the ghost house (N1: nor onto its walls' cells)
			var pos := Vector3(c * CELL, player.global_position.y, r * CELL)
			if capsule_blocked_at(pos):
				continue
			var d := Vector2(pos.x - player.global_position.x, pos.z - player.global_position.z).length()
			if d < best_d:
				best_d = d
				best = Vector2i(r, c)
	if best.x >= 0:
		player.global_position = Vector3(best.y * CELL, player.global_position.y, best.x * CELL)


## ---------------- white rabbit and conditions (spec 2.2-2.5) ----------------

## The rabbit generator of a level: "Kaninchen der Woche" (level id + ISO
## week, local time — see white_rabbit.gd), or in Chaos mode a generator with
## a random seed (real randomness, still only through pick_condition).
func _make_rabbit_rng(lid: String) -> RandomNumberGenerator:
	rabbit_week = rabbit_week_override if rabbit_week_override.x > 0 else WhiteRabbitScript.current_iso_week()
	if chaos_mode:
		return _new_chaos_rng()
	return WhiteRabbitScript.week_rng(lid, rabbit_week)


## Share of good conditions for the next rabbit: the chat's share while
## Twitch is on (spec 2.6 — 60 % until 3 different viewers voted), otherwise
## the base 60 %.
func _rabbit_p_good() -> float:
	if Twitch.enabled:
		return chat_vote.p_good(real_now)
	return ConditionsScript.P_GOOD_BASE


## Did the chat shift the ratio for a rabbit picked up now (>= 3 voters and a
## share other than 60 %)?
func _chat_shifts_rabbit() -> bool:
	return Twitch.enabled and chat_vote.shifted(real_now)


## The rabbit was picked up. Normally its result comes from the level's
## generator (Kaninchen der Woche, or Chaos). If the chat shifted the ratio,
## a generator with real randomness draws with the chat's weighting instead,
## the level moves to the "chat" board and the title card says
## "Chat 72 % → MATRIX" (spec 2.6). Always through pick_condition.
func _on_rabbit_picked() -> void:
	if rabbit_rng == null:
		rabbit_rng = _make_rabbit_rng(level_id)
	var p := _rabbit_p_good()
	var rng: RandomNumberGenerator = rabbit_rng
	var chat_line := ""
	var chat_shifted := _chat_shifts_rabbit()
	if chat_shifted:
		rng = _new_chaos_rng()
		_mark_chat_assisted()
	var id: String = ConditionsScript.pick_condition(rng, p)
	if forced_rabbit_condition != "":
		id = forced_rabbit_condition # tools only (rabbit balance measurement)
	var c = ConditionsScript.get_condition(id)
	if c == null:
		return
	c.roll(rng)
	if forced_fl_manipulation != "" and c.has_method("set_manipulation"):
		c.set_manipulation(forced_fl_manipulation)
	level_condition_id = c.id
	if chat_shifted:
		chat_line = "Chat %d %% → %s" % [ChatVoteScript.percent(p), c.display_name.to_upper()]
	start_condition(c, chat_line)


## HUD chat chip — only in a running speedrun level while the Twitch chat is
## really connected (N5). While the chat has not shifted the ratio it says
## where the rabbit comes from ("Kaninchen: Woche", "Kaninchen: Chaos"),
## once shifted "Kaninchen: 70 % gut". Votes expire, so it is refreshed a few
## times a second.
func _update_chat_hud(force: bool = false) -> void:
	if not force and real_now < _chat_hud_next_update:
		return
	_chat_hud_next_update = real_now + 0.25
	var show_it: bool = Twitch.enabled and Twitch.is_connected_to_chat() and running and not playing_explorer and level_id != ""
	hud.set_chat_share_visible(show_it)
	if show_it:
		var source := "Chaos" if level_board == LevelsScript.BOARD_CHAOS else "Woche"
		hud.set_chat_share(_rabbit_p_good(), chat_vote.voters(real_now), ChatVoteScript.MIN_VOTERS, _chat_shifts_rabbit(), source)


## Starts `c` as THE active condition. A running one is replaced, never
## stacked (spec 2.2). The look is switched here, after the level is built —
## never from the condition's on_start (Code-W1).
func start_condition(c, chat_line: String = "") -> void:
	if active_condition != null:
		_end_condition(false)
	active_condition = c
	player.active_condition = c
	condition_started_at = now
	condition_until = now + c.duration_s
	_last_tick_second = -1
	_active_look = ConditionLooksScript.get_look(c.look_id) if c.look_id != "" else {}
	_vis_t = -1.0
	_vis_flip = -1.0
	_vis_solid = -1.0
	env_blend_count = 0
	look_param_count = 0
	c.on_start(self)
	if c.look_id != "" and maze_view.has_look(c.look_id):
		maze_view.set_look(c.look_id)
		maze_view.set_look_param("reduce_fx", 1.0 if reduce_fx else 0.0)
	hud.show_condition_card(c, chat_line)
	if c.is_good:
		Sfx.rabbit_good()
	else:
		Sfx.rabbit_bad()
	Sfx.start_condition_layer(c.is_good)
	_refresh_noclip()
	_apply_condition_visuals(0.0, c.duration_s)


func condition_remaining() -> float:
	return maxf(condition_until - now, 0.0) if active_condition != null else 0.0


func _update_condition(delta: float) -> void:
	if active_condition == null:
		return
	var remaining := condition_until - now
	if remaining <= 0.0:
		_end_condition(true)
		return
	active_condition.on_process(delta, self, remaining)
	var t_in := clampf((now - condition_started_at) / CONDITION_TRANSITION_S, 0.0, 1.0)
	var t_out := clampf(remaining / CONDITION_TRANSITION_S, 0.0, 1.0)
	_apply_condition_visuals(minf(t_in, t_out), remaining)
	if remaining <= CONDITION_WARN_S:
		var sec := int(ceil(remaining))
		if sec != _last_tick_second:
			_last_tick_second = sec
			Sfx.condition_tick()
	hud.update_condition_card(remaining, active_condition.duration_s)


## Look transition `t` (0 = base, 1 = condition look): shader uniforms on the
## shared condition material, environment blend, object style.
## W2: nothing here allocates. The look data was looked up at
## start_condition, the base environment is cached, and every uniform / the
## environment is only written when its value actually changed — between the
## transitions (t = 1) a running condition writes nothing at all, except the
## Kippbild's flip while it moves and the Matrix fade in the last 3 s.
func _apply_condition_visuals(t: float, remaining: float) -> void:
	var c = active_condition
	if c.look_id == "":
		return
	var flip: float = c.look_flip()
	if maze_view.current_look == c.look_id:
		if t != _vis_t:
			_set_look_uniform("transition", t)
		# UX-K1: with "Effekte reduzieren" the world does not tip — a thin HUD
		# frame and the title card's symbol show the manipulation instead.
		var shader_flip := 0.0 if reduce_fx else flip
		if shader_flip != _vis_flip:
			_set_look_uniform("flip", shader_flip)
			_vis_flip = shader_flip
		hud.set_flip_frame(flip if reduce_fx else 0.0)
		var solid := _matrix_solid(c, remaining)
		if solid != _vis_solid:
			_set_look_uniform("matrix_solid", solid)
			_vis_solid = solid
	if _active_look.is_empty():
		_vis_t = t
		return
	if t != _vis_t:
		_blend_environment(_active_look.env, t)
		_set_object_style(_active_look.outline and t >= 0.5, _active_look.objects_ignore_fog and t > 0.0)
	_vis_t = t


func _set_look_uniform(param: String, value) -> void:
	look_param_count += 1
	maze_view.set_look_param(param, value)


## Matrix, last 3 s: the walls fade back in and blink (MATRIX_BLINK_HZ, below
## 3 Hz) — with "Effekte reduzieren" only a steady fade.
func _matrix_solid(c, remaining: float) -> float:
	if not c.wants_noclip() or remaining > CONDITION_WARN_S:
		return 0.0
	var phase := CONDITION_WARN_S - remaining
	var ramp := clampf(phase / (CONDITION_WARN_S - CONDITION_TRANSITION_S), 0.0, 1.0)
	if reduce_fx:
		return ramp
	var pulse := 0.5 - 0.5 * cos(TAU * MATRIX_BLINK_HZ * phase)
	return lerpf(pulse, 1.0, ramp)


## Blends from the cached base environment (_apply_theme_environment) to the
## look's target — no theme is built here (W2).
func _blend_environment(env_target: Dictionary, t: float) -> void:
	if world_env == null or world_env.environment == null:
		return
	env_blend_count += 1
	var env: Environment = world_env.environment
	env.background_color = _env_base_bg.lerp(env_target.bg, t)
	env.fog_light_color = _env_base_fog.lerp(env_target.fog, t)
	env.fog_density = lerpf(_env_base_fog_density, env_target.fog_density, t)
	env.ambient_light_color = _env_base_ambient.lerp(env_target.ambient, t)
	env.ambient_light_energy = lerpf(_env_base_ambient_energy, env_target.ambient_energy, t)


func _set_object_style(outline: bool, ignore_fog: bool) -> void:
	if outline == _style_outline and ignore_fog == _style_ignore_fog:
		return
	_style_outline = outline
	_style_ignore_fog = ignore_fog
	maze_view.set_object_style(outline, ignore_fog)
	var ol: Material = ConditionLooksScript.outline_material() if outline else null
	for e in enemies:
		e.set_condition_style(ol, ignore_fog)


## Ends the active condition (no-op without one): back to the base look and
## environment, ghosts at normal speed, minimap on, HUD card off, noclip off
## with the safe-cell rescue.
func _end_condition(play_sound: bool) -> void:
	if active_condition == null:
		return
	var c = active_condition
	active_condition = null
	player.active_condition = null
	c.on_end(self)
	Sfx.stop_condition_layer()
	if maze_view.normal_wall_mmi != null and maze_view.current_look != maze_view.LOOK_BASE:
		maze_view.set_look(maze_view.LOOK_BASE)
	if not playing_explorer:
		_apply_theme_environment("normal")
	if maze_view.pellet_material != null:
		_set_object_style(false, false)
	for e in enemies:
		e.speed_scale = 1.0
	hud.hide_condition_card()
	hud.set_flip_frame(0.0)
	hud.set_minimap_visible(true)
	_active_look = {}
	_refresh_noclip()
	if play_sound:
		Sfx.condition_end()


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
	if not v.is_valid_int() or v.to_int() < 0:
		# W4: keep the broken file before the next save overwrites it.
		SavePathsScript.backup_corrupt(path)
		return 0
	return v.to_int()


func _save_highscore(v: int) -> void:
	SavePathsScript.write_atomic(SavePathsScript.path(HIGHSCORE_FILE), str(v))
