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

	# --- normal (Speedrun): no landmarks, has power-ups, never word-built ---
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
	# Speedrun base look "Lagune" (spec 1.1); Matrix is a rabbit condition
	# look on the shared kond_wall/kond_floor shaders (spec 1.2).
	if normal.wall_shader_path != "res://shaders/pacman_wall.gdshader" or "wall_matrix_rain" in normal:
		failures += 1
		print("FAIL normal theme's walls should use the pacman_wall shader (matrix_rain is gone)")
	checks += 1
	if normal.cond_wall_shader_path != "res://shaders/kond_wall.gdshader" or normal.cond_floor_shader_path != "res://shaders/kond_floor.gdshader":
		failures += 1
		print("FAIL normal theme should name the condition-look shaders kond_wall/kond_floor")
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
	if manhattan.wall_shader_path != "" or manhattan.cond_wall_shader_path != "":
		failures += 1
		print("FAIL manhattan theme should have no wall shader and no condition looks (it's always word-built anyway)")
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

	# --- other_explorer_id: the other registered explorer city (Manhattan <->
	# Tokyo); falls back to the same id for an unknown/only city ---
	checks += 1
	if CityThemes.EXPLORER_IDS.find("manhattan") < 0 or CityThemes.EXPLORER_IDS.find("tokyo") < 0:
		failures += 1
		print("FAIL EXPLORER_IDS should list 'manhattan' and 'tokyo'")
	checks += 1
	if CityThemes.other_explorer_id("manhattan") != "tokyo" or CityThemes.other_explorer_id("tokyo") != "manhattan":
		failures += 1
		print("FAIL other_explorer_id should switch between manhattan and tokyo, got '%s' / '%s'" % [CityThemes.other_explorer_id("manhattan"), CityThemes.other_explorer_id("tokyo")])
	# every explorer city has its theme and its Main registry entry
	for eid in CityThemes.EXPLORER_IDS:
		checks += 1
		var ec: Dictionary = load("res://scripts/explorer_cities.gd").get_city(eid)
		if ec.is_empty() or CityThemes.get_theme(ec.theme).id != eid:
			failures += 1
			print("FAIL explorer city '%s' has no registry entry or theme" % eid)
	# --- theme switch resets post-processing: the speedrun and Manhattan keep
	# a fresh Environment's values, only Tokyo turns glow/SSR on ---
	for tid in ["normal", "manhattan"]:
		var tt = CityThemes.get_theme(tid)
		var fresh := Environment.new()
		checks += 1
		if tt.env_glow_enabled or tt.env_ssr_enabled or tt.env_volumetric_fog_enabled or tt.env_tonemap_mode != fresh.tonemap_mode \
				or not is_equal_approx(tt.env_tonemap_exposure, fresh.tonemap_exposure) or not is_equal_approx(tt.env_tonemap_white, fresh.tonemap_white) \
				or not is_equal_approx(tt.env_fog_sky_affect, fresh.fog_sky_affect) or not is_equal_approx(tt.camera_far, 100.0):
			failures += 1
			print("FAIL theme '%s' must keep the default post-processing (no glow/SSR/volumetrics, linear tonemap)" % tid)
		for gi in 7:
			checks += 1
			if not is_equal_approx(tt.env_glow_levels[gi], fresh.get_glow_level(gi)):
				failures += 1
				print("FAIL theme '%s' glow level %d differs from the Environment default" % [tid, gi])

	# --- UX-W2 (03.10. review): frightened ghosts in a clearly separate colour
	# — not near-white, not in the blue band 215-250 deg (too close to the
	# original), and perceptually far (OKLab) from every ghost colour, the
	# pellets, rabbit white, Matrix green/head and both Kippbild palettes, the
	# wall lines and level gradients ---
	var fr: Color = CityThemes.GHOST_FRIGHTENED
	checks += 1
	if fr.h * 360.0 >= 215.0 and fr.h * 360.0 <= 250.0:
		failures += 1
		print("FAIL frightened colour must not sit in the blue band 215-250 deg (h=%.1f)" % (fr.h * 360.0))
	checks += 1
	if fr.s < 0.6 or fr.v < 0.6:
		failures += 1
		print("FAIL frightened colour must be saturated and bright, not near-white (s=%.2f v=%.2f)" % [fr.s, fr.v])
	checks += 1
	if not normal.ghost_frightened_color.is_equal_approx(fr) or not normal.minimap_frightened_color.is_equal_approx(fr):
		failures += 1
		print("FAIL the theme must use GHOST_FRIGHTENED for ghosts and minimap")
	# must never be confused with (game objects): large distance
	var critical := {
		"jaeger": CityThemes.GHOST_JAEGER.color, "abfaenger": CityThemes.GHOST_ABFAENGER.color,
		"streuner": CityThemes.GHOST_STREUNER.color, "lauerer": CityThemes.GHOST_LAUERER.color,
		"nachzuegler": CityThemes.GHOST_NACHZUEGLER.color, "pellet": CityThemes.LOOK_PELLET,
		"rabbit white": Color("f2f2ed"), "matrix green": Color("00d94d"), "matrix head": Color("4dff88"),
	}
	# must stay apart from (surroundings): clear distance
	var surroundings := {
		"top edge": CityThemes.LOOK_LINE_TOP, "lagune": CityThemes.LOOK_BASE_LAGUNE, "riff": CityThemes.LOOK_BASE_RIFF,
		"kippbild a low": Color("2b0a3d"), "kippbild a mid": Color("b3175c"), "kippbild a high": Color("f26b33"),
		"kippbild b low": Color("072e33"), "kippbild b mid": Color("0f8c85"), "kippbild b high": Color("4dccf2"),
	}
	for k in critical:
		checks += 1
		var d := _oklab_distance(fr, critical[k])
		if d < 0.2:
			failures += 1
			print("FAIL frightened colour too close to %s (OKLab %.3f < 0.2)" % [k, d])
	for k in surroundings:
		checks += 1
		var d2 := _oklab_distance(fr, surroundings[k])
		if d2 < 0.1:
			failures += 1
			print("FAIL frightened colour too close to %s (OKLab %.3f < 0.1)" % [k, d2])
	# the kond_wall shader's Matrix head is the green used above, not near-white
	checks += 1
	var kw: String = (load("res://shaders/kond_wall.gdshader") as Shader).code
	if kw.find("mx_head : source_color = vec3(0.30, 1.0, 0.53)") == -1:
		failures += 1
		print("FAIL Matrix glyph heads should be green #4DFF88 in kond_wall.gdshader")

	print("")
	if failures == 0:
		print("ALL %d CITY THEME CHECKS PASSED" % checks)
		quit(0)
	else:
		print("%d/%d CITY THEME CHECKS FAILED" % [failures, checks])
		quit(1)



## Perceptual distance of two sRGB colours in OKLab (Björn Ottosson).
static func _oklab(c: Color) -> Vector3:
	var lin := func(x: float) -> float: return x / 12.92 if x <= 0.04045 else pow((x + 0.055) / 1.055, 2.4)
	var r: float = lin.call(c.r)
	var g: float = lin.call(c.g)
	var b: float = lin.call(c.b)
	var l := pow(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b, 1.0 / 3.0)
	var m := pow(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b, 1.0 / 3.0)
	var s := pow(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b, 1.0 / 3.0)
	return Vector3(0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
		1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
		0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)


static func _oklab_distance(a: Color, b: Color) -> float:
	return _oklab(a).distance_to(_oklab(b))
