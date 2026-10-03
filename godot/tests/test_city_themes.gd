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
	# Speedrun base look "Lagune" (spec 1.1): the old matrix_rain walls and
	# the Mario/cloud sky are gone; Matrix becomes a rabbit condition.
	if normal.wall_shader_path != "res://shaders/pacman_wall.gdshader" or normal.wall_matrix_rain:
		failures += 1
		print("FAIL normal theme's walls should use the pacman_wall shader (not matrix_rain)")
	checks += 1
	if normal.ceil_sky_clouds or normal.floor_shader_path != "res://shaders/pacman_floor.gdshader" or normal.screen_overlay_shader_path != "res://shaders/crt_overlay.gdshader":
		failures += 1
		print("FAIL normal theme should have no sky clouds, the pacman floor shader and the CRT overlay")
	checks += 1
	if not (normal.level_looks.has("lagune") and normal.level_looks.has("riff") and normal.default_level_look == "lagune"):
		failures += 1
		print("FAIL normal theme should offer the level looks lagune/riff, lagune by default")
	checks += 1
	var line_blue := []
	for look_id in normal.level_looks:
		for role in ["top", "base"]:
			var c: Color = normal.level_looks[look_id][role]
			if c.h * 360.0 >= 215.0 and c.h * 360.0 <= 250.0:
				line_blue.append("%s.%s" % [look_id, role])
	if not line_blue.is_empty() or (normal.minimap_wall_color.h * 360.0 >= 215.0 and normal.minimap_wall_color.h * 360.0 <= 250.0):
		failures += 1
		print("FAIL no wall line / minimap color may sit in the blue hue range 215-250 deg: %s" % [line_blue])
	checks += 1
	var lagune_ghosts: Array = normal.level_looks.lagune.ghosts
	var riff_ghosts: Array = normal.level_looks.riff.ghosts
	var riff_has_violet := false
	for g in riff_ghosts:
		if g.role == "streuner":
			riff_has_violet = true
	if lagune_ghosts.size() != 5 or not riff_has_violet or riff_ghosts.size() != 5:
		failures += 1
		print("FAIL Lagune and Riff should both have all five ghost colors incl. the violet Streuner (studio head, 03.10.2026)")
	checks += 1
	if normal.env_bg_color != Color("05070b") or normal.floor_color != Color("0d0f16") or normal.ceil_color != Color("05070b"):
		failures += 1
		print("FAIL room/fog/ceiling should be #05070B and the floor #0D0F16")
	checks += 1
	if normal.wall_word_tall != "" or normal.wall_height_min > 0.0 or normal.wall_vertical_text or normal.pellets_follow_metro_trails:
		failures += 1
		print("FAIL normal theme should keep the old uniform-height, horizontal-word, fill-every-cell behavior")
	checks += 1
	if not normal.ceil_enabled:
		failures += 1
		print("FAIL normal theme should keep its physical ceiling")
	checks += 1
	# Corridors deliberately a bit tighter than one bare CELL now (per user
	# request) — walls are slightly bigger than their own cell footprint
	# instead of the old exact edge-to-edge fit (see city_themes.gd's
	# normal()/CityTheme.wall_footprint_scale).
	if normal.wall_footprint_scale <= 1.0:
		failures += 1
		print("FAIL normal theme's walls should now be slightly bigger than their own cell (narrower corridors), got %f" % normal.wall_footprint_scale)

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
		print("FAIL manhattan theme's wall_palette should cycle through several colors")

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
	checks += 1
	if manhattan.ceil_enabled:
		failures += 1
		print("FAIL manhattan theme should have no physical ceiling (its skyscrapers are taller than the old fixed ceiling height)")
	checks += 1
	if not (manhattan.wall_footprint_scale > 0.0 and manhattan.wall_footprint_scale < 1.0):
		failures += 1
		print("FAIL manhattan theme's buildings should sit back from their cell edges (wall_footprint_scale < 1.0), got %f" % manhattan.wall_footprint_scale)

	# --- manhattan keeps its own look: none of the Speedrun look fields ---
	var defaults = load("res://scripts/city_theme.gd").new()
	checks += 1
	var leaked := []
	for field in ["wall_shader_path", "floor_shader_path", "screen_overlay_shader_path", "pellet_color", "pellet_shape", "pellet_size", "pellet_height", "power_color", "power_shape", "power_diamond", "power_blink_hz", "level_looks", "default_level_look", "minimap_wall_color", "minimap_bg_color", "ghost_frightened_color"]:
		if manhattan.get(field) != defaults.get(field):
			leaked.append(field)
	if not leaked.is_empty():
		failures += 1
		print("FAIL manhattan must keep the default (pre-Speedrun-look) values, changed: %s" % [leaked])

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
