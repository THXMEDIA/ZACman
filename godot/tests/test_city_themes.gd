extends SceneTree
## Headless test: res://scripts/city_theme.gd and city_themes.gd — the
## Explorer-level visual/gameplay bundle that replaced maze_view.gd's raw
## "normal"/"manhattan" theme-string branching. Run with
##   godot --headless --path . --script res://tests/test_city_themes.gd
## Exits with code 0 on success, 1 on any failure.

func _initialize() -> void:
	var CityThemes = load("res://scripts/city_themes.gd")
	var failures := 0
	var checks := 0

	# --- normal: Matrix-green "WALL" blocks, no landmarks, has power-ups ---
	var normal = CityThemes.get_theme("normal")
	checks += 1
	if normal.id != "normal":
		failures += 1
		print("FAIL normal theme id should be 'normal', got '%s'" % normal.id)
	checks += 1
	if normal.wall_word != "WALL":
		failures += 1
		print("FAIL normal theme wall_word should be WALL, got '%s'" % normal.wall_word)
	checks += 1
	if normal.landmark_provider_script != null:
		failures += 1
		print("FAIL normal theme should have no landmark provider")
	checks += 1
	if not normal.has_power_ups:
		failures += 1
		print("FAIL normal theme should have power-ups")
	checks += 1
	if normal.permanently_word_built:
		failures += 1
		print("FAIL normal theme should not be permanently word-built")
	checks += 1
	if not normal.wall_matrix_rain:
		failures += 1
		print("FAIL normal theme's walls should use the matrix_rain shader")
	checks += 1
	if not normal.ceil_sky_clouds:
		failures += 1
		print("FAIL normal theme should have the voxel-cloud sky ceiling enabled")
	checks += 1
	if normal.wall_word_tall != "" or normal.wall_height_min > 0.0 or normal.wall_vertical_text or normal.pellets_follow_metro_trails:
		failures += 1
		print("FAIL normal theme should keep the old uniform-height, horizontal-word, fill-every-cell behavior")

	# --- manhattan: BUILDING blocks, real landmark provider, no power-ups ---
	var manhattan = CityThemes.get_theme("manhattan")
	checks += 1
	if manhattan.id != "manhattan":
		failures += 1
		print("FAIL manhattan theme id should be 'manhattan', got '%s'" % manhattan.id)
	checks += 1
	if manhattan.wall_word != "BUILDING":
		failures += 1
		print("FAIL manhattan theme wall_word should be BUILDING, got '%s'" % manhattan.wall_word)
	checks += 1
	if manhattan.landmark_provider_script == null:
		failures += 1
		print("FAIL manhattan theme should have a landmark provider (manhattan_maze.gd)")
	else:
		checks += 1
		if manhattan.landmark_provider_script.landmark_at(0, 0) != "":
			failures += 1
			print("FAIL manhattan theme's landmark provider should resolve through to manhattan_maze.gd (corner should be '')")
	checks += 1
	if manhattan.has_power_ups:
		failures += 1
		print("FAIL manhattan theme should have no power-ups (calm explorer)")
	checks += 1
	if manhattan.wall_matrix_rain:
		failures += 1
		print("FAIL manhattan theme's boxy walls should not use the matrix_rain shader (it's always word-built anyway)")
	checks += 1
	if manhattan.ceil_sky_clouds:
		failures += 1
		print("FAIL manhattan theme should keep its own neon skyline ceiling, not the voxel-cloud sky")
	checks += 1
	if not manhattan.permanently_word_built:
		failures += 1
		print("FAIL manhattan theme should be permanently word-built")
	checks += 1
	if manhattan.wall_palette.size() < 2:
		failures += 1
		print("FAIL manhattan theme's wall_palette should cycle through several neon colors")

	# --- manhattan: real skyscrapers, hochkant, pellets as metro signposts ---
	checks += 1
	if manhattan.wall_word_tall != "SKYSCRAPER":
		failures += 1
		print("FAIL manhattan theme's tall word should be SKYSCRAPER, got '%s'" % manhattan.wall_word_tall)
	checks += 1
	if manhattan.skyscraper_chance_pct <= 0 or manhattan.skyscraper_chance_pct >= 100:
		failures += 1
		print("FAIL manhattan theme's skyscraper_chance_pct should be a real minority odds, got %d" % manhattan.skyscraper_chance_pct)
	checks += 1
	if not manhattan.wall_vertical_text:
		failures += 1
		print("FAIL manhattan theme should build its wall words hochkant (wall_vertical_text)")
	checks += 1
	if not (manhattan.wall_height_min > 0.0 and manhattan.wall_height_max > manhattan.wall_height_min):
		failures += 1
		print("FAIL manhattan theme's regular-building height range should be a real positive range (min=%f max=%f)" % [manhattan.wall_height_min, manhattan.wall_height_max])
	checks += 1
	if not (manhattan.wall_height_tall_min > manhattan.wall_height_max and manhattan.wall_height_tall_max > manhattan.wall_height_tall_min):
		failures += 1
		print("FAIL manhattan theme's skyscraper height range should sit clearly above the regular-building range")
	checks += 1
	if not manhattan.pellets_follow_metro_trails:
		failures += 1
		print("FAIL manhattan theme's pellets should follow metro trails, not fill every open cell")

	# Every hand-authored landmark (manhattan_maze.gd's LANDMARKS) needs a
	# real height here, or it would silently fall back to a flat default —
	# and that height should be a real, positive, sane building height, not
	# a leftover placeholder.
	var landmark_names_missing := []
	var ManhattanMaze = load("res://scripts/manhattan_maze.gd")
	for entry in ManhattanMaze.LANDMARKS:
		var h = manhattan.landmark_heights.get(entry[0], -1.0)
		if h <= 0.0:
			landmark_names_missing.append(entry[0])
	checks += 1
	if not landmark_names_missing.is_empty():
		failures += 1
		print("FAIL manhattan theme is missing a real landmark_heights entry for: %s" % str(landmark_names_missing))

	# The Empire State Building should tower over the Chrysler Building over
	# the NY Public Library — real relative proportions, not arbitrary.
	checks += 1
	var esb: float = manhattan.landmark_heights.get("EMPIRE STATE BUILDING", 0.0)
	var chrysler: float = manhattan.landmark_heights.get("CHRYSLER BUILDING", 0.0)
	var nypl: float = manhattan.landmark_heights.get("NY PUBLIC LIBRARY", 0.0)
	if not (esb > chrysler and chrysler > nypl and esb > manhattan.wall_height_tall_max):
		failures += 1
		print("FAIL landmark heights should keep real relative order: ESB=%f > Chrysler=%f > NYPL=%f, ESB should also exceed the tallest generic skyscraper=%f" % [esb, chrysler, nypl, manhattan.wall_height_tall_max])

	# --- unknown ids fall back to "normal" (a safe default, never a crash) ---
	checks += 1
	var fallback = CityThemes.get_theme("some_future_city_not_registered_yet")
	if fallback.id != "normal":
		failures += 1
		print("FAIL an unregistered theme id should fall back to 'normal', got '%s'" % fallback.id)

	# --- normal and manhattan are visually distinct (sanity check the two
	# themes aren't accidentally sharing a mutated instance) ---
	checks += 1
	if normal.env_bg_color.is_equal_approx(manhattan.env_bg_color):
		failures += 1
		print("FAIL normal and manhattan themes should have different background colors")

	# --- other_explorer_id: falls back to the same id when it's the only
	# registered explorer city (today: just Manhattan) ---
	checks += 1
	if CityThemes.EXPLORER_IDS.find("manhattan") < 0:
		failures += 1
		print("FAIL EXPLORER_IDS should list 'manhattan'")
	checks += 1
	if CityThemes.other_explorer_id("manhattan") != "manhattan":
		failures += 1
		print("FAIL other_explorer_id should fall back to the same id with only 1 explorer city registered, got '%s'" % CityThemes.other_explorer_id("manhattan"))

	print("")
	if failures == 0:
		print("ALL %d CITY THEME CHECKS PASSED" % checks)
		quit(0)
	else:
		print("%d/%d CITY THEME CHECKS FAILED" % [failures, checks])
		quit(1)
