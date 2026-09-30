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
	if not manhattan.permanently_word_built:
		failures += 1
		print("FAIL manhattan theme should be permanently word-built")
	checks += 1
	if manhattan.wall_palette.size() < 2:
		failures += 1
		print("FAIL manhattan theme's wall_palette should cycle through several neon colors")

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
