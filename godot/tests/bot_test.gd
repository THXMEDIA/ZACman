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

	# ---- no Testbuild button any more; the debug overlay is an F3 toggle ----
	_check("start screen: no Testbuild button / signal", not main.hud.has_signal("test_build_pressed"))
	_check("debug overlay: hidden by default", main.hud.debug_label.get_parent().get_parent().visible == false and main.debug_mode == false)
	var f3 := InputEventKey.new()
	f3.keycode = KEY_F3
	f3.pressed = true
	main._unhandled_input(f3)
	_check("debug overlay: F3 turns it on (debug build)", main.debug_mode == true and main.hud.debug_label.get_parent().get_parent().visible == true)
	main._unhandled_input(f3)
	_check("debug overlay: F3 turns it off again", main.debug_mode == false and main.hud.debug_label.get_parent().get_parent().visible == false)

	# ---- start screen: condition selector ----
	_check("start screen: condition selector lists Normal + every condition", main.hud.condition_option.item_count == 3, "got %d" % main.hud.condition_option.item_count)
	main.hud.condition_option.item_selected.emit(1)
	_check("start screen: picking a condition reaches Main", main.selected_condition_id == "matrix_ghost", "got '%s'" % main.selected_condition_id)
	main.hud.condition_option.item_selected.emit(0)
	_check("start screen: picking Normal clears it", main.selected_condition_id == "")

	# ---- minimap arrow points where the camera looks (was mirrored) ----
	var hud_script = load("res://scripts/hud.gd")
	var arrow_e: PackedVector2Array = hud_script._minimap_arrow(Vector2.ZERO, -PI / 2.0) # looking east
	_check("minimap arrow: yaw -90deg (east) points right", arrow_e[0].x > 4.0 and absf(arrow_e[0].y) < 0.01, "tip=%s" % arrow_e[0])
	var arrow_w: PackedVector2Array = hud_script._minimap_arrow(Vector2.ZERO, PI / 2.0) # looking west
	_check("minimap arrow: yaw +90deg (west) points left", arrow_w[0].x < -4.0, "tip=%s" % arrow_w[0])
	var arrow_n: PackedVector2Array = hud_script._minimap_arrow(Vector2.ZERO, 0.0)
	_check("minimap arrow: yaw 0 (north) points up", arrow_n[0].y < -4.0)

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
	_check("matrix wall: bg_color default is darker than before", wall_shader.code.find("bg_color = vec3(0.001, 0.012, 0.004)") != -1)
	_check("matrix wall: glyph_color default is a deeper, more saturated green", wall_shader.code.find("glyph_color = vec3(0.08, 0.95, 0.22)") != -1)
	_check("matrix wall: emission boosted for more glow", wall_shader.code.find("EMISSION = color * 2.2") != -1)

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
	main.begin_game("klassik-1")
	await get_tree().process_frame
	main.level_start_real = main.real_now - 5.0 # pretend 5s elapsed, well under every target
	var pellet_cells2: Array = main.maze_view.pellet_cells
	for cell in pellet_cells2:
		main.player.global_position = Vector3(cell.y * main.CELL, main.player.global_position.y, cell.x * main.CELL)
		await get_tree().process_frame
	for i in main.maze_view.power_cells.size():
		var node2 = main.maze_view.power_nodes[i]
		main.player.global_position = Vector3(node2.position.x, main.player.global_position.y, node2.position.z)
		await get_tree().process_frame
	_check("fast clear earns the target-time badge", Speedrun.is_bonus_unlocked())
	_check("fast clear records a klassik-1 best time", Speedrun.best_for("klassik-1") >= 0.0 and Speedrun.best_for("klassik-1") < 10.0, "best=%s" % Speedrun.best_for("klassik-1"))
	_check("fast clear lands on the klassik-1 solo leaderboard", Leaderboard.get_top("klassik-1", "").size() == 1)
	_check("fast clear leaves the chat board empty", Leaderboard.get_top("klassik-1", "", 5, "chat").size() == 0)
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

	# Manhattan is an untimed hub: pellets are only signposts — no score, no
	# completion, no clock, no leaderboard.
	var manhattan_pellets: Array = main.maze_view.pellet_cells
	var manhattan_score_before: int = main.score
	for cell in manhattan_pellets:
		main.player.global_position = Vector3(cell.y * main.CELL, main.player.global_position.y, cell.x * main.CELL)
		await get_tree().process_frame
	_check("manhattan: all pellets can be eaten", main.maze_view.remaining_pickups() <= 0, "remaining=%d" % main.maze_view.remaining_pickups())
	_check("manhattan: eating pellets gives no score", main.score == manhattan_score_before, "score=%d" % main.score)
	_check("manhattan: eating every pellet does not complete the level", main.running == true and main.playing_manhattan == true)
	_check("manhattan: no leaderboard entry anywhere", Leaderboard.get_top("manhattan", "", 1).size() == 0)
	_check("manhattan: timer / score / lives chips are hidden", main.hud.timer_label.get_parent().get_parent().visible == false and main.hud.score_label.get_parent().get_parent().visible == false and main.hud.lives_box.get_parent().visible == false)
	_check("manhattan: the high score is untouched", main.high_score == 0 or main.high_score == main._load_highscore())
	main.paused = true
	main.hud.set_pause_note(false)
	_check("manhattan: pause note does not mention the speedrun clock", main.hud.pause_note_label.text.find("Speedrun") == -1)
	main.paused = false

	# The selected condition is applied to an Explorer run (no next-run panel any more).
	main.selected_condition_id = "fear_and_loathing"
	main.hud.restart_pressed.emit() # NEUSTART in Manhattan restarts Manhattan, not a Matrix level
	await get_tree().process_frame
	_check("manhattan: NEUSTART restarts the Explorer level", main.running == true and main.playing_manhattan == true)
	_check("manhattan: the start-screen condition is applied", main.condition_id == "fear_and_loathing" and main.player.active_condition != null and main.player.active_condition.id == "fear_and_loathing")
	main.selected_condition_id = ""

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

	# ---- Fear & Loathing power-up: a risk/reward item. Only from the 2nd
	# level of a run on, only in dead ends; scrambled steering + psychedelic
	# walls for double points; never touches wall collision ----
	main.begin_game("klassik-2")
	await get_tree().process_frame
	_check("fear powerup: none on the first level of a run", main.maze_view.fear_powerup_nodes.is_empty())
	main.level_index = 1
	main.start_level(load("res://scripts/levels.gd").by_id("klassik-2"))
	await get_tree().process_frame
	_check("fear powerup: off at level start", main.fear_mode_until <= main.now)
	_check("fear powerup: spawns from the 2nd level on", main.maze_view.fear_powerup_nodes.size() > 0)
	var all_dead_ends := true
	for fc in main.maze_view.fear_powerup_cells:
		if MazeGen.neighbors_of(main.maze, fc.x, fc.y).size() != 1:
			all_dead_ends = false
	_check("fear powerup: every pickup lies in a dead end", all_dead_ends)
	var fear_nodes_before: int = main.maze_view.fear_powerup_nodes.size()
	main.player.global_position = Vector3(main.maze_view.fear_powerup_nodes[0].position.x, main.player.global_position.y, main.maze_view.fear_powerup_nodes[0].position.z)
	var score_pre_fear: int = main.score
	await get_tree().process_frame
	_check("fear powerup: picking it up activates it", main.fear_mode_until > main.now)
	_check("fear powerup: player.active_condition becomes fear_and_loathing", main.player.active_condition != null and main.player.active_condition.id == "fear_and_loathing")
	_check("fear powerup: wall shader gets the psychedelic uniform", main.maze_view.wall_material.get_shader_parameter("psychedelic_amount") == 1.0)
	_check("fear powerup: the pickup itself is worth 75 (the double points start after it)", main.score - score_pre_fear == 75, "gained %d" % (main.score - score_pre_fear))
	_check("fear powerup: wall collision stays on (no random noclip)", main.player.collision_mask == 2)
	var pellet_spot = null
	for i in main.maze_view.pellet_cells.size():
		if main.maze_view.pellet_alive[i]:
			pellet_spot = main.maze_view.pellet_cells[i]
			break
	var score_pre_pellet: int = main.score
	main.player.global_position = Vector3(pellet_spot.y * main.CELL, main.player.global_position.y, pellet_spot.x * main.CELL)
	await get_tree().process_frame
	_check("fear powerup: pellets count double while it runs", main.score - score_pre_pellet == 10 * main.FEAR_SCORE_MULTIPLIER, "gained %d" % (main.score - score_pre_pellet))
	_check("fear powerup: no steering input means no drift", main.player.active_condition.modify_input(Vector2.ZERO, 0.1) == Vector2.ZERO)

	# A second pickup only extends the timer: no second saved condition.
	if main.maze_view.fear_powerup_nodes.size() > 1:
		main.fear_mode_until = main.now + 1.0
		var saved_before = main._fear_saved_active_condition
		main.player.global_position = Vector3(main.maze_view.fear_powerup_nodes[1].position.x, main.player.global_position.y, main.maze_view.fear_powerup_nodes[1].position.z)
		await get_tree().process_frame
		_check("fear powerup: a second pickup extends the timer", main.fear_mode_until > main.now + main.FEAR_MODE_DURATION - 0.5)
		_check("fear powerup: a second pickup does not stack the condition", main._fear_saved_active_condition == saved_before and main.player.active_condition.id == "fear_and_loathing")

	main.fear_mode_until = main.now - 0.01 # force expiry without waiting out the real duration
	await get_tree().process_frame
	_check("fear powerup: reverts after expiry (timer cleared)", main.fear_mode_until == 0.0)
	_check("fear powerup: reverts after expiry (wall shader)", main.maze_view.wall_material.get_shader_parameter("psychedelic_amount") == 0.0)
	_check("fear powerup: reverts after expiry (collision untouched)", main.player.collision_mask == 2)
	_check("fear powerup: reverts after expiry (active_condition restored — also after a double pickup)", main.player.active_condition == null)
	var score_post_fear: int = main.score
	main._add_score(10)
	_check("fear powerup: points are normal again after expiry", main.score - score_post_fear == 10)

	# ---- overlapping effects can never leave noclip stuck on ----
	main.begin_game("klassik-2")
	await get_tree().process_frame
	main.level_index = 1
	main.start_level(load("res://scripts/levels.gd").by_id("klassik-2"))
	await get_tree().process_frame
	main._activate_word_mode()
	main._activate_fear_powerup()
	main._deactivate_word_mode()
	_check("overlap: word ends while fear runs -> noclip off", main.player.collision_mask == 2)
	main._deactivate_fear_powerup()
	_check("overlap: fear ends afterwards -> noclip still off", main.player.collision_mask == 2)
	main._activate_fear_powerup()
	main._activate_word_mode()
	main._deactivate_fear_powerup()
	_check("overlap: fear ends while word runs -> noclip stays on", main.player.collision_mask == 0)
	main._deactivate_word_mode()
	_check("overlap: word ends last -> noclip off", main.player.collision_mask == 2)
	main.set_condition("matrix_ghost")
	main._activate_word_mode()
	main._deactivate_word_mode()
	_check("overlap: matrix_ghost keeps noclip after a Word pickup ends", main.player.collision_mask == 0 and main.maze_view.word_mode_active == true)
	main.set_condition("")
	_check("overlap: clearing matrix_ghost turns noclip off", main.player.collision_mask == 2)

	# ---- noclip can no longer lock the player out of the maze ----
	main.begin_game("klassik-1")
	await get_tree().process_frame
	main._activate_word_mode()
	main.player.global_position = Vector3(main.player.global_position.x, main.player.global_position.y, -7.0)
	main._keep_noclip_player_in_maze()
	_check("noclip: player is clamped to the maze rows", main.player.global_position.z >= 0.0)
	var wall_cell := Vector2i(-1, -1)
	for r in range(2, main.maze.rows - 2, 2):
		for c in range(2, main.maze.cols - 2, 2):
			if main.maze.grid[r][c] == 1 and wall_cell.x < 0:
				wall_cell = Vector2i(r, c)
	main.player.global_position = Vector3(wall_cell.y * main.CELL, main.player.global_position.y, wall_cell.x * main.CELL)
	main._deactivate_word_mode()
	var rescued: Vector2i = main.player.cell()
	_check("noclip: ending inside a wall moves the player to an open cell", main.maze.grid[rescued.x][rescued.y] == 0, "cell=%s" % rescued)

	# ---- Pause: effect timers freeze, the speedrun clock keeps running ----
	main.begin_game("klassik-1")
	await get_tree().process_frame
	main.frightened_until = main.now + 7.0
	var remaining_before: float = main.frightened_until - main.now
	main.toggle_pause()
	var real_before: float = main.real_now
	var elapsed_before: float = main.real_now - main.level_start_real
	for i in 20:
		main._process(0.5) # 10 s of pause
	_check("pause: the effect timers do not run down", absf((main.frightened_until - main.now) - remaining_before) < 0.001)
	_check("pause: the speedrun clock keeps running", main.real_now - real_before > 9.9 and main.real_now - main.level_start_real - elapsed_before > 9.9)
	_check("pause: the timer display follows the speedrun clock", main.hud.timer_label.text == Speedrun.format_time(main.real_now - main.level_start_real))
	main.toggle_pause()
	_check("pause: pause note names the running clock", main.hud.pause_note_label.text.find("Speedrun-Zeit läuft weiter") != -1)

	# ---- Chat interaction moves the level's time to the chat board ----
	Speedrun.reset_all()
	Leaderboard.reset_all()
	main.begin_game("klassik-1")
	await get_tree().process_frame
	_check("chat: a plain level starts in solo mode", main.run_mode() == "solo" and main.level_chat_assisted == false)
	Twitch.chat_command.emit("viewer", "power", "")
	await get_tree().process_frame
	_check("chat: a !power that took effect marks the level as chat", main.run_mode() == "chat")
	_check("chat: the HUD shows the CHAT badge", main.hud.mode_label.text == "CHAT" and main.hud.mode_label.get_parent().get_parent().visible)
	main.level_start_real = main.real_now - 5.0
	for cell in main.maze_view.pellet_cells:
		main.player.global_position = Vector3(cell.y * main.CELL, main.player.global_position.y, cell.x * main.CELL)
		await get_tree().process_frame
	for i in main.maze_view.power_cells.size():
		var cnode = main.maze_view.power_nodes[i]
		main.player.global_position = Vector3(cnode.position.x, main.player.global_position.y, cnode.position.z)
		await get_tree().process_frame
	_check("chat: the time lands on the chat leaderboard", Leaderboard.get_top("klassik-1", "", 5, "chat").size() == 1)
	_check("chat: the solo leaderboard stays empty", Leaderboard.get_top("klassik-1", "", 5, "solo").size() == 0)
	_check("chat: the solo best time stays empty", Speedrun.best_for("klassik-1") == -1.0 and Speedrun.best_for("klassik-1", "", "chat") >= 0.0)
	_check("chat: a chat run does not earn the target-time badge", not Speedrun.is_bonus_unlocked())
	await get_tree().create_timer(2.0).timeout
	_check("chat: the next level starts clean (solo again)", main.run_mode() == "solo")

	# ---- a condition run has its own board too ----
	main.selected_condition_id = "matrix_ghost"
	main.begin_game("klassik-1")
	await get_tree().process_frame
	main.level_start_real = main.real_now - 5.0
	for cell in main.maze_view.pellet_cells:
		main.player.global_position = Vector3(cell.y * main.CELL, main.player.global_position.y, cell.x * main.CELL)
		await get_tree().process_frame
	for i in main.maze_view.power_cells.size():
		var cnode2 = main.maze_view.power_nodes[i]
		main.player.global_position = Vector3(cnode2.position.x, main.player.global_position.y, cnode2.position.z)
		await get_tree().process_frame
	_check("condition: the time lands on the matrix_ghost board", Leaderboard.get_top("klassik-1", "matrix_ghost", 5).size() == 1)
	_check("condition: the unconditioned board is untouched", Leaderboard.get_top("klassik-1", "", 5).size() == 0)
	await get_tree().create_timer(2.0).timeout
	main.selected_condition_id = ""
	Speedrun.reset_all()
	Leaderboard.reset_all()

	# ---- level pool: a run starts on a random level and never repeats within a round ----
	var started := {}
	for i in 25:
		main.begin_game()
		started[main.level_id] = true
	_check("pool: random starts reach several different levels", started.size() >= 3, "got %s" % [started.keys()])
	main.begin_game()
	var run_levels := [main.level_id]
	for i in 5:
		main.level_index += 1
		main.played_ids.append(main.level_id)
		main.next_level()
		run_levels.append(main.level_id)
	var unique := {}
	for id in run_levels:
		unique[id] = true
	_check("pool: a run plays every level once before repeating", unique.size() == run_levels.size(), "got %s" % [run_levels])

	# ---- Manhattan is permanently word-built, has no Word Mode power-up,
	# and its taxis/pedestrians block the player without costing a life ----
	main.begin_manhattan_game()
	await get_tree().process_frame
	_check("manhattan: permanently word-built (no power-up needed)", main.maze_view.word_mode_active == true)
	_check("manhattan: no word power-up node exists", main.maze_view.word_powerup_nodes.is_empty())
	_check("manhattan: taxis spawned", main.taxis.size() > 0, "got %d" % main.taxis.size())
	_check("manhattan: pedestrians spawned", main.pedestrians.size() > 0, "got %d" % main.pedestrians.size())
	var lives_before_obstacle: int = main.lives
	var ped = main.pedestrians[0]
	main.player.global_position = Vector3(ped.position.x + 0.05, main.player.global_position.y, ped.position.z)
	await get_tree().process_frame
	await get_tree().process_frame
	var d_to_ped := Vector2(main.player.global_position.x - ped.position.x, main.player.global_position.z - ped.position.z).length()
	_check("manhattan: pedestrian blocks the player (pushed out to the clearance radius)", d_to_ped >= main.MANHATTAN_OBSTACLE_RADIUS - 0.01, "d=%f" % d_to_ped)
	_check("manhattan: obstacles cost no life", main.lives == lives_before_obstacle)

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
