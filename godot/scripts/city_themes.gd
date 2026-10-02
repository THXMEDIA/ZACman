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

	# Corridors a bit tighter/more claustrophobic (per user request): walls
	# a touch bigger than their own CELL footprint (see CityTheme.
	# wall_footprint_scale), encroaching slightly into the neighboring open
	# cell on each side rather than stopping exactly at the cell boundary —
	# a 2.0-wide corridor between two walls becomes ~1.76 wide. MazeView.
	# WALL_H itself (the taller/narrower combo the user asked for) stays a
	# MazeView constant since it's shared by every theme.
	t.wall_footprint_scale = 1.12

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


## Manhattan bonus level: the Alex Gopher "The Child" look this whole
## word-built-world idea is ported from — warm, muted, printed-poster
## colors (ochre, rust, sand, dark brown/olive) against a dark teal-black
## backdrop, deliberately NOT neon (an earlier version of this theme was a
## neon cyberpunk skyline; the reference images call for something closer
## to old film-grain city photography than a nightclub sign). Ordinary
## blocks cycle through that palette as "BUILDING"/"SKYSCRAPER"; blocks
## manhattan_maze.gd's LANDMARKS table names get their real name and a
## brighter (still warm) accent color instead. A calm explorer — no
## power-ups, no ghosts.
static func manhattan() -> Resource:
	var t = CityThemeScript.new()
	t.id = "manhattan"
	t.display_name = "Manhattan"
	t.wall_word = "BUILDING"
	t.wall_font_size = 22
	t.wall_depth_scale = 0.6
	t.wall_emission_energy = 0.85
	t.wall_palette = [
		Color(0.82, 0.62, 0.28), # ochre
		Color(0.55, 0.36, 0.2), # brown
		Color(0.78, 0.42, 0.16), # rust/burnt orange
		Color(0.86, 0.78, 0.56), # sand/cream
		Color(0.4, 0.36, 0.26), # dark olive-brown
	]
	t.wall_alternate_rotation = true
	t.landmark_provider_script = ManhattanMazeScript
	t.landmark_accents = [
		Color(0.95, 0.86, 0.6), # warm cream-gold
		Color(0.88, 0.4, 0.14), # burnt orange-red
		Color(0.72, 0.68, 0.58), # warm stone grey
	]
	t.landmark_font_size = 15
	t.landmark_depth_scale = 0.55
	t.landmark_emission_energy = 1.7

	# Streets wider than the old edge-to-edge blocks: every building sits
	# back from its cell's edges (see CityTheme.wall_footprint_scale), so
	# the visible/walkable gap between two building faces is noticeably
	# more than one bare CELL now. Shrunk further still (0.55 -> 0.48 ->
	# 0.40, per user request: "die Abstände zwischen Gebäuden sind zu eng"
	# and "hier darf man neben Passanten... vorbei") — building faces
	# across a street are now ~3.2 apart (was ~2.9), on top of the
	# explicit vehicle-lane/sidewalk separation below (see Main.
	# MANHATTAN_VEHICLE_LANE_OFFSET / MANHATTAN_SIDEWALK_OFFSET), which is
	# the bigger part of the actual fix — traffic and pedestrians used to
	# share one single centerline lane with no room to pass each other, now
	# vehicles drive two offset lanes down the middle and pedestrians walk a
	# dedicated strip near the building edge, clear of both. The review
	# pass (docs/review/berichte/) found that at 0.48 the sidewalk strip
	# (Main.MANHATTAN_SIDEWALK_OFFSET) left less clearance to the building
	# face than the pedestrian push-out radius — i.e. no actual room to
	# pass — so this went down to 0.40 alongside those two constants.
	t.wall_footprint_scale = 0.40
	# The real culprit behind "Manhattan ist zu eng" (QA screenshot
	# 2026-10-02): the hochkant letters scaled with building height, so a
	# skyscraper's letters were several units wide/deep and hung far out over
	# the 3.2-wide street, even though collision was only 0.8 wide. Fit the
	# lettering to the footprint so the street looks as wide as it is.
	t.wall_word_fit_footprint = true

	# No physical ceiling plane (see CityTheme.ceil_enabled) — real-height
	# skyscrapers need open sky above them, not a flat roof at the old
	# MazeView.WALL_H that would slice through every one of them.
	t.ceil_enabled = false

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

	# Dark warm asphalt/print-poster floor instead of the old glossy magenta-
	# tinted one; ceil_color/ceil_emission_* are unused now (ceil_enabled is
	# false — see above) but left set to something sane in case a future
	# theme change flips it back on.
	t.floor_color = Color(0.05, 0.04, 0.03)
	t.floor_roughness = 0.55
	t.floor_metallic = 0.1
	t.floor_emission_enabled = true
	t.floor_emission_color = Color(0.35, 0.22, 0.1)
	t.floor_emission_energy = 0.06
	t.ceil_color = Color(0.03, 0.045, 0.04)
	t.ceil_emission_enabled = false
	t.ceil_emission_color = Color.BLACK
	t.ceil_emission_energy = 0.0

	# Dark teal-black night sky (image reference: the Brooklyn Bridge shot's
	# backdrop) rather than the old near-black magenta.
	t.env_bg_color = Color(0.02, 0.05, 0.045)
	t.env_fog_color = Color(0.05, 0.09, 0.08)
	t.env_fog_density = 0.03
	t.env_ambient_color = Color(0.4, 0.32, 0.24)
	t.env_ambient_energy = 0.65

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


## The "calm explorer" city themes (see main.gd's start_explorer_level) — not
## the Matrix speedrun levels, which aren't part of that rotation. Add a new city's id
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
