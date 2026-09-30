extends RefCounted
## CityThemes — the registry of CityTheme instances. Adding a new Explorer
## level (a new real-world city, in its own art style) means writing one
## more `static func` here (plus, if it wants real landmark names, a small
## landmark-table script like manhattan_maze.gd's) — MazeView and Main never
## need to change.

const ManhattanMazeScript := preload("res://scripts/manhattan_maze.gd")
const CityThemeScript := preload("res://scripts/city_theme.gd")

## Matrix-ASCII levels' word-built-world skin (the Word Mode power-up look).
## Flat Matrix green, matching the ASCII look it's switching out of.
static func normal() -> Resource:
	var t = CityThemeScript.new()
	t.id = "normal"
	t.display_name = "Matrix"
	t.wall_word = "WALL"
	t.wall_font_size = 30
	t.wall_depth_scale = 0.6
	t.wall_emission_energy = 1.1
	t.wall_palette = [Color(0.25, 1.0, 0.35)]
	t.wall_alternate_rotation = true
	t.wall_matrix_rain = true
	t.landmark_provider_script = null

	# Brown dirt ground + a bright blue "sky" ceiling with blocky white
	# clouds (see ceil_sky_clouds / cloud_mesh.gd) — a deliberate Super-
	# Mario/Minecraft mashup against the green Matrix-code walls, per the
	# user's request.
	t.floor_color = Color(0.36, 0.22, 0.1)
	t.floor_roughness = 0.85
	t.ceil_color = Color(0.35, 0.65, 1.0)
	t.ceil_emission_enabled = true
	t.ceil_emission_color = Color(0.35, 0.65, 1.0)
	t.ceil_emission_energy = 0.35
	t.ceil_sky_clouds = true

	t.env_bg_color = Color(0.35, 0.65, 1.0)
	t.env_fog_color = Color(0.35, 0.65, 1.0)
	t.env_fog_density = 0.015
	t.env_ambient_color = Color(0.55, 0.7, 0.85)
	t.env_ambient_energy = 1.1

	t.has_power_ups = true
	t.permanently_word_built = false
	return t


## Manhattan bonus level: Neo-Noir Cyberpunk skyline. Ordinary blocks cycle
## through a neon palette as "BUILDING"; blocks manhattan_maze.gd's
## LANDMARKS table names get their real name and a brighter accent color
## instead. A calm explorer — no power-ups, no ghosts.
static func manhattan() -> Resource:
	var t = CityThemeScript.new()
	t.id = "manhattan"
	t.display_name = "Manhattan"
	t.wall_word = "BUILDING"
	t.wall_font_size = 22
	t.wall_depth_scale = 0.6
	t.wall_emission_energy = 1.1
	t.wall_palette = [
		Color(1.0, 0.05, 0.75), # magenta
		Color(0.0, 0.95, 1.0), # cyan
		Color(0.6, 0.05, 1.0), # violet
		Color(1.0, 0.8, 0.0), # neon amber
		Color(0.05, 1.0, 0.45), # neon green
	]
	t.wall_alternate_rotation = true
	t.landmark_provider_script = ManhattanMazeScript
	t.landmark_accents = [
		Color(1.0, 0.85, 0.25), # neon gold
		Color(1.0, 0.05, 0.55), # hot pink
		Color(0.15, 0.85, 1.0), # electric blue
	]
	t.landmark_font_size = 15
	t.landmark_depth_scale = 0.55
	t.landmark_emission_energy = 2.4

	# Real skyscrapers, actually skyscraper-sized: every ordinary block is
	# either a regular "BUILDING" or (skyscraper_chance_pct odds) a much
	# taller "SKYSCRAPER", each written hochkant (wall_vertical_text) — one
	# letter per row, stacked floor to roof (see word_mesh.gd's
	# build_vertical_stack) — instead of the old uniform MazeView.WALL_H box
	# every block used before. Heights are real-world building heights
	# (roof height, not antenna, where the two differ), scaled at a fixed
	# 1 game unit = 5 real meters (SCALE = 0.2) so relative proportions
	# between buildings stay right: Empire State Building really is ~1.7x
	# the Chrysler Building here, same as in Midtown. Sources: public
	# reference figures for these specific landmarks (Wikipedia et al.), not
	# a live survey — flavor-accurate, not blueprint-accurate, consistent
	# with this file's/manhattan_maze.gd's existing "flavor data" approach.
	const METERS_TO_UNITS := 0.2
	t.wall_word_tall = "SKYSCRAPER"
	t.skyscraper_chance_pct = 22
	t.wall_height_min = 30.0 * METERS_TO_UNITS # ~ a modest 6-10 story building
	t.wall_height_max = 55.0 * METERS_TO_UNITS
	t.wall_height_tall_min = 150.0 * METERS_TO_UNITS # a "real" skyscraper starts around here
	t.wall_height_tall_max = 320.0 * METERS_TO_UNITS
	t.wall_vertical_text = true
	t.landmark_default_height = 80.0 * METERS_TO_UNITS
	t.landmark_heights = {
		"EMPIRE STATE BUILDING": 381.0 * METERS_TO_UNITS, # roof; 443m to the antenna tip
		"CHRYSLER BUILDING": 319.0 * METERS_TO_UNITS,
		"ROCKEFELLER CENTER": 259.0 * METERS_TO_UNITS, # 30 Rock
		"TRUMP TOWER": 202.0 * METERS_TO_UNITS,
		"THE PLAZA": 76.0 * METERS_TO_UNITS, # ~19-story hotel
		"ST PATRICK'S CATHEDRAL": 100.0 * METERS_TO_UNITS, # spires
		"TIMES SQUARE": 110.0 * METERS_TO_UNITS, # One Times Square, standing in for the district
		"CARNEGIE HALL": 53.0 * METERS_TO_UNITS,
		"MACY'S": 50.0 * METERS_TO_UNITS, # Herald Square flagship, ~9 floors
		"PORT AUTHORITY": 40.0 * METERS_TO_UNITS,
		"GRAND CENTRAL": 45.0 * METERS_TO_UNITS,
		"RADIO CITY": 40.0 * METERS_TO_UNITS,
		"MOMA": 40.0 * METERS_TO_UNITS,
		"TIFFANY & CO": 40.0 * METERS_TO_UNITS, # 727 Fifth Ave flagship
		"NY PUBLIC LIBRARY": 30.0 * METERS_TO_UNITS, # low Beaux-Arts building, deliberately short here
		"JAVITS CENTER": 30.0 * METERS_TO_UNITS, # wide and low, not tall
		"BRYANT PARK": 8.0 * METERS_TO_UNITS, # a park, not a building — kept low on purpose
	}

	t.floor_color = Color(0.015, 0.01, 0.03)
	t.floor_roughness = 0.25
	t.floor_metallic = 0.35
	t.floor_emission_enabled = true
	t.floor_emission_color = Color(0.35, 0.02, 0.3)
	t.floor_emission_energy = 0.12
	t.ceil_color = Color(0.03, 0.01, 0.07)
	t.ceil_emission_enabled = true
	t.ceil_emission_color = Color(0.05, 0.02, 0.25)
	t.ceil_emission_energy = 0.1

	t.env_bg_color = Color(0.02, 0.006, 0.05)
	t.env_fog_color = Color(0.35, 0.02, 0.4)
	t.env_fog_density = 0.045
	t.env_ambient_color = Color(0.5, 0.08, 0.55)
	t.env_ambient_energy = 0.55

	t.has_power_ups = false
	t.permanently_word_built = true
	t.pellets_follow_metro_trails = true
	return t


static func get_theme(id: String) -> Resource:
	match id:
		"manhattan":
			return manhattan()
		_:
			return normal()


## The "calm explorer" city themes selectable from the post-run "pick a
## city" choice (see main.gd's _explorer_next_choices) — not the Matrix
## speedrun levels, which aren't part of that rotation. Add a new city's id
## here once it has its own static func above.
const EXPLORER_IDS := ["manhattan"]


## A different registered explorer city id than `current_id`, for the
## post-run "andere Stadt" choice — falls back to `current_id` itself when
## it's the only explorer city registered yet (today: just Manhattan). See
## this project's "Explorer-Level-Erweiterung, Leaderboard & Konditionen"
## doc — more cities are the next content step, not an architecture change.
static func other_explorer_id(current_id: String) -> String:
	for id in EXPLORER_IDS:
		if id != current_id:
			return id
	return current_id
