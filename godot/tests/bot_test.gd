extends Node
## Headless bot simulation for the actual Main scene (not a mock): runs the
## real Godot physics/script pipeline in --headless mode, drives the player
## via the Input singleton and direct state pokes (same spirit as the
## Node-based harness that validated the web version), and asserts on the
## real Main node's state. Run with:
##   godot --headless --path . res://tests/BotTest.tscn
## Exits with code 0 if every check passes, 1 otherwise.

var main
var failures := 0
var checks := 0


func _ready() -> void:
	var main_scene: PackedScene = load("res://scenes/Main.tscn")
	main = main_scene.instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame

	await _run_checks()

	print("")
	if failures == 0:
		print("ALL %d GODOT SIMULATION CHECKS PASSED" % checks)
		get_tree().quit(0)
	else:
		print("%d/%d GODOT SIMULATION CHECKS FAILED" % [failures, checks])
		get_tree().quit(1)


func _check(name: String, cond: bool, detail := "") -> void:
	checks += 1
	if cond:
		print("OK    ", name)
	else:
		failures += 1
		print("FAIL  ", name, (" -> " + detail) if detail != "" else "")


func _release_all_move_keys() -> void:
	for a in ["move_forward", "move_back", "move_left", "move_right"]:
		Input.action_release(a)


func _pin_enemy_at(enemy, cell: Vector2i) -> void:
	enemy.r = cell.x
	enemy.c = cell.y
	enemy.from_r = cell.x
	enemy.from_c = cell.y
	enemy.target_r = cell.x
	enemy.target_c = cell.y
	enemy.t = 0.0


func _run_checks() -> void:
	Leaderboard.reset_all()

	# ---- start screen offers Matrix-level vs Explorer-level right away,
	# not gated behind the speedrun bonus unlock (see hud.gd's
	# _build_start_panel / set_bonus_unlocked) ----
	_check("start screen: Explorer-level button visible without unlocking anything", main.hud.manhattan_btn.visible == true)

	# ---- Testbuild button: normal Matrix level + DEBUG chip in the HUD ----
	_check("debug overlay: hidden before Testbuild is chosen", main.hud.debug_label.get_parent().get_parent().visible == false)
	_check("debug_mode: off before Testbuild is chosen", main.debug_mode == false)
	main._on_test_build_pressed()
	await get_tree().process_frame
	_check("debug_mode: on after Testbuild pressed", main.debug_mode == true)
	_check("debug overlay: visible after Testbuild is chosen", main.hud.debug_label.get_parent().get_parent().visible == true)
	_check("debug overlay: running a normal Matrix level (maze built)", main.maze != null)
	main._process(0.016)
	_check("debug overlay: text populated after a frame", main.hud.debug_label.text != "--" and main.hud.debug_label.text != "")
	# switching back to a normal start turns the overlay off again
	main._on_start_pressed()
	await get_tree().process_frame
	_check("debug_mode: off again after a normal Matrix-level start", main.debug_mode == false)
	_check("debug overlay: hidden again after a normal Matrix-level start", main.hud.debug_label.get_parent().get_parent().visible == false)

	# ---- begin_game starts cleanly ----
	main.begin_game()
	await get_tree().process_frame
	_check("begin_game: running", main.running == true)
	_check("begin_game: maze built", main.maze != null)
	_check("begin_game: lives == 3", main.lives == 3, "got %d" % main.lives)
	_check("begin_game: enemies spawned", main.enemies.size() >= 3, "got %d" % main.enemies.size())

	# ---- Matrix wall shader: much more glyph variance, and the new
	# darker-but-more-luminous color tuning ----
	var wall_shader: Shader = main.maze_view.wall_material.shader
	_check("matrix wall: glyph table has far more than the original 10 shapes", wall_shader.code.find("GLYPH_COUNT = 31") != -1)
	# Uniforms aren't overridden per-material here (no set_shader_parameter
	# call — see MazeView._make_materials), so get_shader_parameter() would
	# just return the "no override" nil rather than the shader's own default;
	# check the darker/more-saturated defaults straight in the shader source
	# instead.
	_check("matrix wall: bg_color default is darker than before", wall_shader.code.find("bg_color = vec3(0.0004, 0.006, 0.002)") != -1)
	_check("matrix wall: glyph_color default is a deeper, more saturated green", wall_shader.code.find("glyph_color = vec3(0.05, 0.92, 0.18)") != -1)
	_check("matrix wall: emission boosted for more glow", wall_shader.code.find("EMISSION = color * 2.6") != -1)
	_check("matrix wall: corridors narrowed via a bigger-than-CELL wall footprint", main.maze_view.city_theme.wall_footprint_scale > 1.0)
	_check("matrix wall: taller than the previous WALL_H", main.maze_view.WALL_H > 3.8)

	# ---- Background music: an original synthesized "arcade" loop starts a
	# normal run (see Sfx.play_arcade_music / audio_synth.gd) ----
	_check("music: arcade track starts on a normal run", Sfx.music_state() == "arcade")
	var all_house := true
	for e in main.enemies:
		if e.mode != "house":
			all_house = false
	_check("begin_game: enemies start in house", all_house)

	# ---- sky clouds float well above the wall tops, not right at them ----
	var mv: Node = main.maze_view
	_check("sky clouds: at least one spawned on a normal level", mv.sky_cloud_nodes.size() > 0, "got %d" % mv.sky_cloud_nodes.size())
	var lowest_cloud_y := INF
	for cloud in mv.sky_cloud_nodes:
		lowest_cloud_y = minf(lowest_cloud_y, cloud.position.y)
	_check("sky clouds: every cloud keeps the minimum clearance above the wall tops", lowest_cloud_y >= mv.WALL_H + mv.CLOUD_MIN_WALL_CLEARANCE - 0.001, "lowest cloud y=%f, WALL_H=%f, min clearance=%f" % [lowest_cloud_y, mv.WALL_H, mv.CLOUD_MIN_WALL_CLEARANCE])

	# ---- bot random walk: no crash, no NaN, over many real frames ----
	var actions := ["move_forward", "move_back", "move_left", "move_right"]
	var current := "move_forward"
	var change_counter := 0
	var walk_ok := true
	var walk_detail := ""
	for i in 600:
		if change_counter <= 0:
			_release_all_move_keys()
			current = actions[randi() % actions.size()]
			change_counter = 20 + randi() % 40
		Input.action_press(current)
		change_counter -= 1
		await get_tree().process_frame
		var p: Vector3 = main.player.global_position
		if is_nan(p.x) or is_nan(p.z):
			walk_ok = false
			walk_detail = "player position NaN at frame %d" % i
			break
		for e in main.enemies:
			if is_nan(e.position.x) or is_nan(e.position.z):
				walk_ok = false
				walk_detail = "enemy position NaN at frame %d" % i
				break
		if not walk_ok:
			break
		if not main.running:
			break
	_release_all_move_keys()
	_check("random walk: 600 frames, no NaN/crash", walk_ok, walk_detail)

	# ---- tunnel wraparound ----
	main.begin_game()
	await get_tree().process_frame
	var world_width: float = main.maze.cols * main.CELL
	main.player.global_position = Vector3(-main.CELL * 5.0, main.player.global_position.y, main.maze.tunnel_row * main.CELL)
	main.player.yaw = 0.0
	await get_tree().process_frame
	var wrapped_x: float = main.player.global_position.x
	_check("tunnel wraparound keeps player in bounds", wrapped_x > -main.CELL and wrapped_x < world_width, "x=%f" % wrapped_x)

	# ---- enemy releases from house ----
	main.begin_game()
	await get_tree().process_frame
	for e in main.enemies:
		e.release_at = 0.0
	await get_tree().process_frame
	await get_tree().process_frame
	var any_released := false
	for e in main.enemies:
		if e.mode != "house":
			any_released = true
	_check("enemies release from house after timer", any_released)

	# ---- power pellet -> eat enemy ----
	main.begin_game()
	await get_tree().process_frame
	var score_before: int = main.score
	var pcell: Vector2i = main.player.cell()
	var target = main.enemies[0]
	target.mode = "chase"
	_pin_enemy_at(target, pcell)
	main.frightened_until = main.now + 9999.0
	main.invuln_until = 0.0
	main.combo_count = 0
	await get_tree().process_frame
	_check("frightened enemy gets eaten", target.mode == "eaten", "mode=%s" % target.mode)
	_check("eating an enemy increases score", main.score > score_before, "before=%d after=%d" % [score_before, main.score])

	# ---- non-frightened collision costs a life ----
	main.begin_game()
	await get_tree().process_frame
	var lives_before: int = main.lives
	var en2 = main.enemies[0]
	en2.mode = "chase"
	_pin_enemy_at(en2, main.player.cell())
	main.frightened_until = 0.0
	main.invuln_until = 0.0
	await get_tree().process_frame
	_check("collision costs a life", main.lives == lives_before - 1, "before=%d after=%d" % [lives_before, main.lives])

	# ---- can no longer squeeze past a ghost sideways in a corridor (per
	# user request — see Main.ENEMY_HIT_RADIUS) ----
	main.begin_game()
	await get_tree().process_frame
	var squeeze_cell: Vector2i = main.player.cell()
	var en_squeeze = main.enemies[0]
	en_squeeze.mode = "chase"
	main.frightened_until = 0.0
	main.invuln_until = main.now + 999.0 # hold off collision while enemy/player get positioned
	_pin_enemy_at(en_squeeze, squeeze_cell)
	await get_tree().process_frame # let enemy.update() actually move it onto the pinned cell
	# 0.7 off to one side would have been outside the old 0.62 hit radius
	# (i.e. the old "squeeze past" gap) but is well inside the new one.
	main.player.global_position = Vector3(en_squeeze.position.x + 0.7, main.player.global_position.y, en_squeeze.position.z)
	var lives_before_squeeze: int = main.lives
	main.invuln_until = 0.0
	await get_tree().process_frame
	_check("can't squeeze past a ghost sideways anymore", main.lives == lives_before_squeeze - 1, "before=%d after=%d" % [lives_before_squeeze, main.lives])

	# ---- losing the last life ends the game ----
	main.begin_game()
	await get_tree().process_frame
	main.lives = 1
	var en3 = main.enemies[0]
	en3.mode = "chase"
	_pin_enemy_at(en3, main.player.cell())
	main.frightened_until = 0.0
	main.invuln_until = 0.0
	await get_tree().process_frame
	_check("losing the last life ends the game", main.running == false)

	# ---- eating every pellet advances the level ----
	main.begin_game()
	await get_tree().process_frame
	var level_before: int = main.level_index
	var pellet_cells: Array = main.maze_view.pellet_cells
	for cell in pellet_cells:
		main.player.global_position = Vector3(cell.y * main.CELL, main.player.global_position.y, cell.x * main.CELL)
		await get_tree().process_frame
	for i in main.maze_view.power_cells.size():
		var node = main.maze_view.power_nodes[i]
		main.player.global_position = Vector3(node.position.x, main.player.global_position.y, node.position.z)
		await get_tree().process_frame
	_check("all pickups consumed", main.maze_view.remaining_pickups() <= 0, "remaining=%d" % main.maze_view.remaining_pickups())
	_check("running pauses during level-clear banner", main.running == false)
	await get_tree().create_timer(2.0).timeout
	_check("level advances after the clear banner", main.level_index == level_before + 1, "before=%d after=%d" % [level_before, main.level_index])
	_check("next level has fresh pellets", main.maze_view.remaining_pickups() > 0)

	# ---- speedrun: a fast clear beats the level-0 target and unlocks the bonus ----
	Speedrun.reset_all()
	main.begin_game()
	await get_tree().process_frame
	main.level_start_time = main.now - 5.0 # pretend 5s elapsed, well under the level-0 target
	var pellet_cells2: Array = main.maze_view.pellet_cells
	for cell in pellet_cells2:
		main.player.global_position = Vector3(cell.y * main.CELL, main.player.global_position.y, cell.x * main.CELL)
		await get_tree().process_frame
	for i in main.maze_view.power_cells.size():
		var node2 = main.maze_view.power_nodes[i]
		main.player.global_position = Vector3(node2.position.x, main.player.global_position.y, node2.position.z)
		await get_tree().process_frame
	_check("fast clear unlocks the Manhattan bonus", Speedrun.is_bonus_unlocked())
	_check("fast clear records a level-0 best time", Speedrun.best_for(0) >= 0.0 and Speedrun.best_for(0) < 10.0, "best=%s" % Speedrun.best_for(0))
	await get_tree().create_timer(2.0).timeout # let the level-clear banner finish so begin_game() below isn't fighting an in-flight await

	# ---- Manhattan bonus level: reuses the normal systems against the real-Midtown grid ----
	main.begin_manhattan_game()
	await get_tree().process_frame
	_check("manhattan: running", main.running == true)
	_check("manhattan: playing_manhattan flag set", main.playing_manhattan == true)
	_check("manhattan: maze built", main.maze != null and main.maze.rows > 0)
	_check("manhattan: no ghosts (calm explore level)", main.enemies.size() == 0, "got %d" % main.enemies.size())
	_check("music: explorer track starts on a Manhattan run", Sfx.music_state() == "explorer")
	_check("manhattan: no power pellets either", main.maze_view.power_cells.size() == 0, "got %d" % main.maze_view.power_cells.size())
	_check("manhattan: player warped to start_cell", main.player.cell() == main.start_cell, "got %s want %s" % [main.player.cell(), main.start_cell])

	var manhattan_pellets: Array = main.maze_view.pellet_cells
	for cell in manhattan_pellets:
		main.player.global_position = Vector3(cell.y * main.CELL, main.player.global_position.y, cell.x * main.CELL)
		await get_tree().process_frame
	for i in main.maze_view.power_cells.size():
		var node3 = main.maze_view.power_nodes[i]
		main.player.global_position = Vector3(node3.position.x, main.player.global_position.y, node3.position.z)
		await get_tree().process_frame
	_check("manhattan: all pickups consumed", main.maze_view.remaining_pickups() <= 0, "remaining=%d" % main.maze_view.remaining_pickups())
	_check("manhattan: clearing it returns to the start screen (not next_level)", main.running == false)
	await get_tree().create_timer(2.4).timeout
	_check("manhattan: playing_manhattan flag cleared after completion", main.playing_manhattan == false)
	_check("manhattan: explorer next-run panel shown after completion", main.hud.explorer_next_panel.visible == true)
	_check("manhattan: leaderboard recorded this run", Leaderboard.get_top("manhattan", "", 1).size() == 1)

	# "ZURÜCK ZUM MENÜ" on the next-run panel returns to the start screen.
	main.hud.explorer_menu_pressed.emit()
	await get_tree().process_frame
	_check("manhattan: back-to-menu returns to the start panel", main.hud.start_panel.visible == true)

	# Picking one of the 4 next-run choices (same/other city × same/other
	# condition — see Main._explorer_next_choices) starts a fresh Explorer
	# run with that combination's condition wired onto the player.
	main.hud.explorer_choice_pressed.emit("manhattan", "fear_and_loathing")
	await get_tree().process_frame
	_check("manhattan: choosing a next-run combo starts a new Explorer run", main.running == true and main.playing_manhattan == true)
	_check("manhattan: choosing a next-run combo applies its condition", main.condition_id == "fear_and_loathing" and main.player.active_condition != null and main.player.active_condition.id == "fear_and_loathing")

	# ---- Twitch chat commands (opt-in gameplay effects), driven end-to-end
	# through the real chat_command signal rather than calling Main's
	# handler directly, so this also proves the signal wiring itself ----
	main.begin_game()
	await get_tree().process_frame
	main.frightened_until = 0.0
	Twitch.chat_command.emit("someviewer", "power", "")
	await get_tree().process_frame
	_check("twitch !power grants frightened mode", main.frightened_until > main.now)

	main.fruit_spawned = false
	Twitch.chat_command.emit("someviewer", "fruit", "")
	await get_tree().process_frame
	_check("twitch !fruit spawns the bonus fruit", main.fruit_spawned == true)

	main.paused = true
	var frightened_before_pause: float = main.frightened_until
	Twitch.chat_command.emit("someviewer", "power", "")
	await get_tree().process_frame
	_check("twitch commands are ignored while paused", main.frightened_until == frightened_before_pause)
	main.paused = false

	# ---- Word Mode power-up: reskins walls/ghosts as letterforms and lets
	# the player walk through walls for its duration, then reverts ----
	main.begin_game()
	await get_tree().process_frame
	_check("word mode: off at level start", main.maze_view.word_mode_active == false)
	_check("word mode: player has normal wall collision at level start", main.player.collision_mask == 2)
	_check("word mode: more than one WORD pickup spawns", main.maze_view.word_powerup_nodes.size() > 1, "got %d" % main.maze_view.word_powerup_nodes.size())
	main.player.global_position = Vector3(main.maze_view.word_powerup_nodes[0].position.x, main.player.global_position.y, main.maze_view.word_powerup_nodes[0].position.z)
	await get_tree().process_frame
	_check("word mode: picking up WORD activates it", main.word_mode_until > main.now)
	_check("word mode: maze_view switches to word-built walls", main.maze_view.word_mode_active == true)
	_check("word mode: player noclips through walls", main.player.collision_mask == 0)
	var any_ghost_skinned := false
	for e in main.enemies:
		if e.word_skin_active:
			any_ghost_skinned = true
	_check("word mode: enemies reskin to GHOST letterforms", any_ghost_skinned)

	main.word_mode_until = main.now - 0.01 # force expiry without waiting out the real duration
	await get_tree().process_frame
	_check("word mode: reverts after expiry (maze_view)", main.maze_view.word_mode_active == false)
	_check("word mode: reverts after expiry (player collision restored)", main.player.collision_mask == 2)
	var any_still_skinned := false
	for e in main.enemies:
		if e.word_skin_active:
			any_still_skinned = true
	_check("word mode: reverts after expiry (enemies)", not any_still_skinned)

	# ---- Fear & Loathing power-up: scrambles input, turns the wall shader
	# psychedelic, and flips collision randomly for its duration, then
	# reverts everything (including whatever whole-run condition was active
	# before it) ----
	main.begin_game()
	await get_tree().process_frame
	_check("fear powerup: off at level start", main.fear_mode_until <= main.now)
	_check("fear powerup: pickup node exists", main.maze_view.fear_powerup_nodes.size() > 0)
	_check("fear powerup: more than one Fear & Loathing pickup spawns", main.maze_view.fear_powerup_nodes.size() > 1, "got %d" % main.maze_view.fear_powerup_nodes.size())
	main.player.global_position = Vector3(main.maze_view.fear_powerup_nodes[0].position.x, main.player.global_position.y, main.maze_view.fear_powerup_nodes[0].position.z)
	await get_tree().process_frame
	_check("fear powerup: picking it up activates it", main.fear_mode_until > main.now)
	_check("fear powerup: player.active_condition becomes fear_and_loathing", main.player.active_condition != null and main.player.active_condition.id == "fear_and_loathing")
	_check("fear powerup: wall shader gets the psychedelic uniform", main.maze_view.wall_material.get_shader_parameter("psychedelic_amount") == 1.0)

	main._fear_next_noclip_toggle_at = main.now - 0.01 # force a toggle without waiting out the real interval
	await get_tree().process_frame
	# The flip itself is random (50/50), so check the deterministic part: the
	# toggle actually ran and scheduled its next one in the future, and left
	# collision_mask at a valid value (0 = noclip or 2 = normal walls).
	_check("fear powerup: collision toggle schedules its next flip", main._fear_next_noclip_toggle_at > main.now)
	_check("fear powerup: collision_mask stays a valid value after a random flip", main.player.collision_mask == 0 or main.player.collision_mask == 2)

	main.fear_mode_until = main.now - 0.01 # force expiry without waiting out the real duration
	await get_tree().process_frame
	_check("fear powerup: reverts after expiry (timer cleared)", main.fear_mode_until == 0.0)
	_check("fear powerup: reverts after expiry (wall shader)", main.maze_view.wall_material.get_shader_parameter("psychedelic_amount") == 0.0)
	_check("fear powerup: reverts after expiry (collision restored)", main.player.collision_mask == 2)
	_check("fear powerup: reverts after expiry (active_condition restored)", main.player.active_condition == null)

	# ---- Manhattan is permanently word-built, has no Word Mode power-up,
	# and its taxis/pedestrians block the player without costing a life ----
	main.begin_manhattan_game()
	await get_tree().process_frame
	_check("manhattan: permanently word-built (no power-up needed)", main.maze_view.word_mode_active == true)
	_check("manhattan: no word power-up node exists", main.maze_view.word_powerup_nodes.is_empty())
	_check("manhattan: taxis spawned", main.taxis.size() > 0, "got %d" % main.taxis.size())
	_check("manhattan: pedestrians spawned", main.pedestrians.size() > 0, "got %d" % main.pedestrians.size())
	# Per user request, traffic and pedestrians no longer share one bare
	# street centerline: taxis drive an offset lane, pedestrians walk an
	# offset sidewalk strip (see Main.MANHATTAN_VEHICLE_LANE_OFFSET/
	# MANHATTAN_SIDEWALK_OFFSET). A centerline position is always an exact
	# multiple of CELL (2.0), so fixed_coord mod CELL is the offset applied
	# — either the constant itself (offset added on the positive side) or
	# CELL minus it (added on the negative side, which fposmod wraps back
	# into [0, CELL)) — checked against the real constants directly rather
	# than a magic-threshold fractional-part test. (This can't just take
	# the smaller of the two distances to a CELL multiple: once an offset
	# exceeds half of CELL — true for MANHATTAN_SIDEWALK_OFFSET — the
	# nearest multiple is genuinely the neighboring street, not the
	# originating one, so both the offset and CELL-offset are legitimate
	# readings and both must be accepted.)
	var taxi_frac: float = fposmod(main.taxis[0].fixed_coord, main.CELL)
	_check("manhattan: taxis drive an offset lane, not the bare centerline", is_equal_approx(taxi_frac, main.MANHATTAN_VEHICLE_LANE_OFFSET) or is_equal_approx(taxi_frac, main.CELL - main.MANHATTAN_VEHICLE_LANE_OFFSET), "frac=%f expected=%f" % [taxi_frac, main.MANHATTAN_VEHICLE_LANE_OFFSET])
	var ped_frac: float = fposmod(main.pedestrians[0]._fixed_coord, main.CELL)
	_check("manhattan: pedestrians walk an offset sidewalk, not the bare centerline", is_equal_approx(ped_frac, main.MANHATTAN_SIDEWALK_OFFSET) or is_equal_approx(ped_frac, main.CELL - main.MANHATTAN_SIDEWALK_OFFSET), "frac=%f expected=%f" % [ped_frac, main.MANHATTAN_SIDEWALK_OFFSET])

	# ---- regression test: a taxi that reaches the end of its street and
	# reverses must switch to the lane matching its NEW direction, not keep
	# driving in the lane assigned at spawn (the lane-flip bug caught
	# independently by the game-designer and code-reviewer review passes) ----
	var taxi_lf = main.taxis[0]
	taxi_lf.dir = 1.0
	taxi_lf._apply_lane()
	var fixed_at_positive_dir: float = taxi_lf.fixed_coord
	taxi_lf.pos_along = taxi_lf.max_coord + 1.0 # force it past the end of its street
	taxi_lf.update(0.0)
	_check("manhattan: taxi reverses direction at the end of its street", taxi_lf.dir < 0.0, "dir=%f" % taxi_lf.dir)
	_check("manhattan: taxi switches lanes after reversing, not stuck in its old lane", not is_equal_approx(taxi_lf.fixed_coord, fixed_at_positive_dir), "fixed=%f (was %f)" % [taxi_lf.fixed_coord, fixed_at_positive_dir])
	_check("manhattan: taxi's new lane matches its new direction", is_equal_approx(taxi_lf.fixed_coord, taxi_lf.base_coord - taxi_lf.lane_offset), "fixed=%f base=%f lane_offset=%f" % [taxi_lf.fixed_coord, taxi_lf.base_coord, taxi_lf.lane_offset])

	var lives_before_obstacle: int = main.lives
	var ped = main.pedestrians[0]
	main.player.global_position = Vector3(ped.position.x + 0.05, main.player.global_position.y, ped.position.z)
	await get_tree().process_frame
	await get_tree().process_frame
	var d_to_ped := Vector2(main.player.global_position.x - ped.position.x, main.player.global_position.z - ped.position.z).length()
	_check("manhattan: pedestrian blocks the player (pushed out to the clearance radius)", d_to_ped >= main.MANHATTAN_PEDESTRIAN_OBSTACLE_RADIUS - 0.01, "d=%f" % d_to_ped)
	_check("manhattan: obstacles cost no life", main.lives == lives_before_obstacle)

	# ---- the sidewalk must leave real room to pass a pedestrian without
	# being shoved into the building face — the bug the critical review
	# finding was about (wall_footprint_scale 0.48 + sidewalk offset 1.15
	# left less clearance to the wall than the push-out radius itself) ----
	var building_face_offset: float = main.CELL - main.CELL * main.maze_view.city_theme.wall_footprint_scale * 0.5
	var sidewalk_to_wall_clearance: float = building_face_offset - main.MANHATTAN_SIDEWALK_OFFSET
	_check("manhattan: sidewalk clearance to the building face exceeds the pedestrian push radius", sidewalk_to_wall_clearance > main.MANHATTAN_PEDESTRIAN_OBSTACLE_RADIUS, "clearance=%f radius=%f" % [sidewalk_to_wall_clearance, main.MANHATTAN_PEDESTRIAN_OBSTACLE_RADIUS])

	# ---- Manhattan's Neo-Noir Cyberpunk dressing: real landmark names in
	# the walls, a neon environment tint, and metro stations that return the
	# player to the normal speedrun ----
	# Manhattan's buildings are now real-height, "hochkant" vertical letter
	# totems (see word_mesh.gd's build_vertical_stack / CityTheme.
	# wall_vertical_text) rather than one MeshInstance3D holding the whole
	# word — so a landmark shows up as a Node3D whose children spell it out
	# one letter each, in order. Accept either shape here so this check
	# still passes for a theme that keeps the single-word look.
	var landmark_found := false
	for child in main.maze_view.word_wall_root.get_children():
		var word := ""
		if child is MeshInstance3D and child.mesh is TextMesh:
			word = child.mesh.text
		elif child is Node3D and child.get_child_count() > 0:
			var letters := ""
			var all_single_letters := true
			for gc in child.get_children():
				if gc is MeshInstance3D and gc.mesh is TextMesh:
					letters += gc.mesh.text
				else:
					all_single_letters = false
			if all_single_letters:
				word = letters
		if word == "":
			continue
		for entry in load("res://scripts/manhattan_maze.gd").LANDMARKS:
			var clean_name: String = entry[0].replace(" ", "").replace("'", "")
			if word == entry[0] or word == clean_name:
				landmark_found = true
	_check("manhattan: a real landmark name appears among the rendered walls", landmark_found)
	var manhattan_theme = load("res://scripts/city_themes.gd").get_theme("manhattan")
	_check("manhattan: neon environment applied", main.world_env.environment.background_color.is_equal_approx(manhattan_theme.env_bg_color))
	_check("manhattan: metro stations spawned", main.metro_stations.size() > 0, "got %d" % main.metro_stations.size())

	# ---- Real skyscraper heights: not every building is the same height
	# any more (collision shapes carry the real per-block height) ----
	var wall_heights := {}
	for cs in main.maze_view.walls_body.get_children():
		if cs is CollisionShape3D and cs.shape is BoxShape3D:
			wall_heights[cs.shape.size.y] = true
	_check("manhattan: buildings have varied heights, not one uniform block", wall_heights.size() > 3, "got %d distinct heights" % wall_heights.size())
	# Vector3 components are 32-bit floats internally, so a height read back
	# off a CollisionShape3D loses a little precision vs. the 64-bit double
	# in landmark_heights — compare with a small tolerance, not exact ==.
	var esb_h: float = manhattan_theme.landmark_heights.get("EMPIRE STATE BUILDING", 0.0)
	var esb_h_found := false
	for h in wall_heights.keys():
		if absf(h - esb_h) < 0.01:
			esb_h_found = true
	_check("manhattan: Empire State Building is the tallest thing standing", esb_h_found, "expected a wall block at height %f" % esb_h)

	# ---- Pellets are sparse wayfinding trails to a metro, not a floor fill
	# of every open cell (see CityTheme.pellets_follow_metro_trails) ----
	var open_non_reserved: int = MazeGen.cells_in_room(main.maze, false).size()
	_check("manhattan: pellets form a sparse trail, not one per open cell", main.maze_view.pellet_cells.size() < open_non_reserved, "pellets=%d open_cells=%d" % [main.maze_view.pellet_cells.size(), open_non_reserved])
	_check("manhattan: there are still enough pellets to form a real trail", main.maze_view.pellet_cells.size() > 5, "got %d" % main.maze_view.pellet_cells.size())

	var metro = main.metro_stations[0]
	main.player.global_position = Vector3(metro.position.x, main.player.global_position.y, metro.position.z)
	await get_tree().process_frame
	await get_tree().process_frame
	# _enter_metro shows a brief banner before actually returning control
	# (see main.gd) — give its await get_tree().create_timer(1.4) time to
	# finish rather than checking mid-transition.
	await get_tree().create_timer(1.6).timeout
	_check("manhattan: entering a metro station ends the Manhattan run", main.playing_manhattan == false)
	_check("manhattan: entering a metro station returns to the normal speedrun", main.running == true and main.level_index == 0)
	var normal_theme = load("res://scripts/city_themes.gd").get_theme("normal")
	_check("manhattan: normal environment restored after metro exit", main.world_env.environment.background_color.is_equal_approx(normal_theme.env_bg_color))

	# ---- Konditionen: selectable whole-run modifiers (see scripts/conditions.gd) ----
	_check("conditions: no condition selected by default", main.current_condition == null and main.player.active_condition == null)

	main.set_condition("matrix_ghost")
	await get_tree().process_frame
	_check("conditions: matrix_ghost sets condition_id", main.condition_id == "matrix_ghost")
	_check("conditions: matrix_ghost turns on word-built walls", main.maze_view.word_mode_active == true)
	_check("conditions: matrix_ghost turns on player noclip", main.player.collision_mask == 0)
	_check("conditions: matrix_ghost wires itself onto the player", main.player.active_condition != null and main.player.active_condition.id == "matrix_ghost")

	main.set_condition("fear_and_loathing")
	await get_tree().process_frame
	_check("conditions: switching condition reverts the previous one (word mode off)", main.maze_view.word_mode_active == false)
	_check("conditions: switching condition reverts the previous one (noclip off)", main.player.collision_mask == 2)
	_check("conditions: fear_and_loathing wires itself onto the player", main.player.active_condition != null and main.player.active_condition.id == "fear_and_loathing")

	main.set_condition("")
	await get_tree().process_frame
	_check("conditions: clearing the condition removes it from the player", main.current_condition == null and main.player.active_condition == null)

	Speedrun.reset_all()
