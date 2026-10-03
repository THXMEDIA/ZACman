extends RefCounted
## CityThemes — the registry of CityTheme instances. Adding a new Explorer
## level (a new real-world city, in its own art style) means writing one
## more `static func` here (plus, if it wants real landmark names, a small
## landmark-table script like manhattan_maze.gd's) — MazeView and Main never
## need to change.

const ManhattanMazeScript := preload("res://scripts/manhattan_maze.gd")
const CityThemeScript := preload("res://scripts/city_theme.gd")
const TokyoMazeScript := preload("res://scripts/tokyo_maze.gd")
const TokyoWetScript := preload("res://scripts/tokyo_wet.gd")
const TokyoSceneryScript := preload("res://scripts/tokyo_scenery.gd")
const TokyoStyle := preload("res://scripts/tokyo_style.gd")

## ---- Speedrun base look "Lagune" (docs/design/kaninchen-speedrun.md 1.1) ----
## Every wall has the same turquoise glowing top edge; the gradient down to
## the base changes per level (look "lagune" or "riff", Levels.POOL[].look).
## No line color may sit in the blue hue range 215-250 deg (legal distance
## to the arcade original; tests/bot_test.gd and test_city_themes.gd check it).
const LOOK_LINE_TOP := Color("1ef2c8") # turquoise top edge, all levels
const LOOK_BASE_LAGUNE := Color("0b7fa8") # gradient to the base, Klassik I/III, Offen
const LOOK_BASE_RIFF := Color("1fbf5a") # gradient to the base, Klassik II/IV, Durchbruch
const LOOK_WALL_BODY := Color("06141c") # dark wall mass
const LOOK_ROOM := Color("05070b") # background, fog and ceiling
const LOOK_FLOOR := Color("0d0f16") # lit floor (not unshaded: ghost light shows round corners)
const LOOK_AMBIENT := Color(0.45, 0.55, 0.6)
const LOOK_FOG_DENSITY := 0.022
const LOOK_MINIMAP_WALL := Color("128f7c") # deliberately not blue
const LOOK_PELLET := Color("fff0c8") # cream cubes
const LOOK_PELLET_EMISSION := Color("ffd98a")
const LOOK_POWER_EMISSION := Color("ffd27a")
const LOOK_POWER_BLINK_HZ := 2.0 # below 3 Hz (photosensitivity)

## Ghost colors (spec 1.1). Danger = warm and saturated; no green (clashes
## with the Matrix condition), no cyan, never the gradient color of the level.
const GHOST_JAEGER := {"role": "jaeger", "color": Color("ff3049"), "glow": Color("ff6a7a")}
const GHOST_ABFAENGER := {"role": "abfaenger", "color": Color("e2ff3a"), "glow": Color("efff8a")}
const GHOST_STREUNER := {"role": "streuner", "color": Color("a65cff"), "glow": Color("c79bff")} # all levels (studio head, 03.10.2026)
const GHOST_LAUERER := {"role": "lauerer", "color": Color("ffa41f"), "glow": Color("ffc56e")}
const GHOST_NACHZUEGLER := {"role": "nachzuegler", "color": Color("ff36c8"), "glow": Color("ff85dd")}
## Frightened ghosts (UX-W2, 03.10. review): cerulean #14A7CC instead of the
## old near-white mint #BDFCEF, which was easy to mistake for the pellets
## (#FFF0C8) and the rabbit white (#F2F2ED). Chosen by a search over hue /
## saturation / value for the largest perceptual distance (OKLab) to every
## colour a frightened ghost must never be confused with — the five ghost
## colours, pellets, rabbit white, Matrix green and head — while keeping a
## clear distance (>= 0.1 OKLab) to the walls (top edge #1EF2C8, Lagune/Riff
## gradients) and both Kippbild palettes, and staying out of the blue band
## 215–250° (too close to the original's frightened blue): hue 192° (cold,
## the only cold colour among the ghost states), closest critical colour the
## Streuner violet at ΔE 0.24. tests/test_city_themes.gd checks all of it.
const GHOST_FRIGHTENED := Color("14a7cc")


## The Speedrun levels: Pac-Man base look "Lagune" (wall/floor shaders, CRT
## overlay, cream pickups, "Schild mit Visier" ghosts) plus the rabbit-
## condition looks (kond_wall/kond_floor, spec 1.2). The word-built-world
## fields are only kept as theme data; the Speedrun is never word-built
## (Word Mode is gone, MazeView builds the word skin only for permanently
## word-built themes like Manhattan).
static func normal() -> Resource:
	var t = CityThemeScript.new()
	t.id = "normal"
	t.display_name = "Speedrun"
	t.wall_word = "WALL"
	t.wall_font_size = 30
	t.wall_depth_scale = 0.6
	t.wall_emission_energy = 1.1
	t.wall_palette = [Color(0.25, 1.0, 0.35)]
	t.wall_alternate_rotation = true
	t.landmark_provider_script = null

	# Corridors a bit tighter/more claustrophobic (per user request): walls
	# a touch bigger than their own CELL footprint (see CityTheme.
	# wall_footprint_scale), encroaching slightly into the neighboring open
	# cell on each side rather than stopping exactly at the cell boundary —
	# a 2.0-wide corridor between two walls becomes ~1.76 wide. MazeView.
	# WALL_H itself (the taller/narrower combo the user asked for) stays a
	# MazeView constant since it's shared by every theme.
	t.wall_footprint_scale = 1.12

	# Dark channels, glowing edges; no sky, no clouds, no Mario vista (those
	# are tied to ceil_sky_clouds), a plain dark ceiling at wall height.
	t.wall_shader_path = "res://shaders/pacman_wall.gdshader"
	t.floor_shader_path = "res://shaders/pacman_floor.gdshader"
	t.cond_wall_shader_path = "res://shaders/kond_wall.gdshader"
	t.cond_floor_shader_path = "res://shaders/kond_floor.gdshader"
	t.screen_overlay_shader_path = "res://shaders/crt_overlay.gdshader"
	t.floor_color = LOOK_FLOOR
	t.floor_roughness = 0.9
	t.ceil_color = LOOK_ROOM
	t.ceil_emission_enabled = false
	t.ceil_sky_clouds = false

	var lagune := {"top": LOOK_LINE_TOP, "base": LOOK_BASE_LAGUNE, "body": LOOK_WALL_BODY,
		"ghosts": [GHOST_JAEGER, GHOST_ABFAENGER, GHOST_STREUNER, GHOST_LAUERER, GHOST_NACHZUEGLER]}
	# Riff: the violet Streuner stays too (decision of the studio head,
	# 03.10.2026: the Riff gradient is green, no clash), so Klassik IV has
	# five distinguishable ghost colors instead of repeating the Jaeger.
	var riff := {"top": LOOK_LINE_TOP, "base": LOOK_BASE_RIFF, "body": LOOK_WALL_BODY,
		"ghosts": [GHOST_JAEGER, GHOST_ABFAENGER, GHOST_STREUNER, GHOST_LAUERER, GHOST_NACHZUEGLER]}
	t.level_looks = {"lagune": lagune, "riff": riff}
	t.default_level_look = "lagune"
	t.ghost_palette = lagune.ghosts
	t.ghost_emission_energy = 1.4
	t.ghost_frightened_color = GHOST_FRIGHTENED
	t.ghost_frightened_emission = GHOST_FRIGHTENED * 0.55
	t.minimap_wall_color = LOOK_MINIMAP_WALL
	t.minimap_bg_color = Color(0.0, 0.0, 0.0, 0.9)
	t.minimap_frightened_color = GHOST_FRIGHTENED

	t.env_bg_color = LOOK_ROOM
	t.env_fog_color = LOOK_ROOM
	t.env_fog_density = LOOK_FOG_DENSITY
	t.env_ambient_color = LOOK_AMBIENT
	t.env_ambient_energy = 0.9

	# Pickups: small bright cream cubes in a row at ~0.4 m; the power pellet
	# is the same hue, bigger, stood on its tip (diamond) and blinking slowly.
	t.pellet_color = LOOK_PELLET
	t.pellet_emission = LOOK_PELLET_EMISSION
	t.pellet_energy = 0.9
	t.pellet_shape = "cube"
	t.pellet_size = 0.075
	t.pellet_height = 0.42
	t.power_color = LOOK_PELLET
	t.power_emission = LOOK_POWER_EMISSION
	t.power_energy = 1.4
	t.power_shape = "cube"
	t.power_size = 0.2
	t.power_diamond = true
	t.power_blink_hz = LOOK_POWER_BLINK_HZ

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


## Tokyo Explorer city, look "Natriumregen" (direction A, approved by the
## owner 03.10.2026; spec docs/design/tokyo-explorer.md): the city is only
## light and lines — black unlit masses (the wall MultiMesh with
## tokyo_mass.gdshader), neon contours from tokyo_scenery.gd, a wet dark
## floor, glow. Palette and roles in tokyo_style.gd. Milestone M1: simple
## wet floor (roughness) and a calm night sky; rain, puddle SSR fine-tuning,
## the scramble and passers-by follow in M2.
static func tokyo() -> Resource:
	var t = CityThemeScript.new()
	t.id = "tokyo"
	t.display_name = "Tokyo"
	t.wall_word = ""
	# Whole cells: the building outline is the cell boundary, so the
	# collision is exactly where the neon base line is drawn.
	t.wall_footprint_scale = 1.0
	t.wall_alternate_rotation = false
	t.landmark_provider_script = TokyoMazeScript
	t.landmark_heights = TokyoMazeScript.building_heights()
	t.landmark_default_height = 12.0
	t.wall_shader_path = "res://shaders/tokyo_mass.gdshader"
	t.scenery_builder_script = TokyoSceneryScript
	t.pellet_trail_provider_script = TokyoMazeScript

	t.floor_color = TokyoStyle.ASPHALT
	t.floor_roughness = 0.24 # only for a floor without the shader below
	t.floor_metallic = 0.0
	# M2: wet floor shader — baked puddle mask, roughness mask for SSR,
	# light pools and reflection streaks (tokyo_floor.gdshader, tokyo_wet.gd).
	t.floor_shader_path = "res://shaders/tokyo_floor.gdshader"
	t.floor_setup_script = TokyoWetScript
	t.ceil_enabled = false

	t.env_bg_color = TokyoStyle.SKY
	t.env_fog_color = TokyoStyle.FOG
	t.env_fog_density = 0.012
	t.env_fog_sky_affect = 0.3 # calm, nearly black night sky
	t.env_ambient_color = Color("0b0806")
	t.env_ambient_energy = 0.3
	t.env_glow_enabled = true
	t.env_glow_intensity = 0.9
	t.env_glow_strength = 1.0
	t.env_glow_bloom = 0.0
	t.env_glow_hdr_threshold = 0.85
	t.env_glow_levels = [0.0, 1.0, 0.0, 0.8, 0.0, 0.64, 0.0]
	t.env_ssr_enabled = true
	t.env_ssr_max_steps = 48
	t.env_ssr_fade_in = 0.15
	t.env_ssr_fade_out = 2.0
	t.env_ssr_depth_tolerance = 0.2
	t.env_volumetric_fog_enabled = false
	t.env_tonemap_mode = 2 # Environment.TONE_MAPPER_FILMIC
	t.env_tonemap_exposure = 1.0
	t.env_tonemap_white = 6.0
	t.player_light_color = TokyoStyle.AMBER
	t.player_light_energy = 0.3
	t.player_light_range = 5.0
	t.camera_far = 260.0 # the sky-deck tower and the skyline beyond the map

	# Pickups: warm white-gold orbs, exclusive to the pellets.
	t.pellet_color = TokyoStyle.PELLET_CORE
	t.pellet_emission = TokyoStyle.PELLET
	t.pellet_energy = 1.8
	t.pellet_shape = "sphere"
	t.pellet_size = 0.11
	t.pellet_height = 0.55

	t.minimap_bg_color = Color(0.0, 0.0, 0.0, 0.85)
	t.minimap_wall_color = Color("4a2c10")

	t.has_power_ups = false
	t.permanently_word_built = false
	t.pellets_follow_metro_trails = true
	return t


static func get_theme(id: String) -> Resource:
	match id:
		"manhattan":
			return manhattan()
		"tokyo":
			return tokyo()
		_:
			return normal()


## The "calm explorer" city themes (see main.gd's start_explorer_level and
## explorer_cities.gd) — not the speedrun levels, which aren't part of that
## rotation. Add a new city's id here once it has its own static func above.
const EXPLORER_IDS := ["manhattan", "tokyo"]


## A different registered explorer city id than `current_id`, for the
## post-run "andere Stadt" choice — falls back to `current_id` itself when
## it's the only explorer city registered. See this project's "Explorer-
## Level-Erweiterung, Leaderboard & Konditionen" doc — more cities are the
## next content step, not an architecture change.
static func other_explorer_id(current_id: String) -> String:
	for id in EXPLORER_IDS:
		if id != current_id:
			return id
	return current_id
