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
	# ---- begin_game starts cleanly ----
	main.begin_game()
	await get_tree().process_frame
	_check("begin_game: running", main.running == true)
	_check("begin_game: maze built", main.maze != null)
	_check("begin_game: lives == 3", main.lives == 3, "got %d" % main.lives)
	_check("begin_game: enemies spawned", main.enemies.size() >= 3, "got %d" % main.enemies.size())
	var all_house := true
	for e in main.enemies:
		if e.mode != "house":
			all_house = false
	_check("begin_game: enemies start in house", all_house)

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
	_check("manhattan: start panel shown again", main.hud.start_panel.visible == true)

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
	main.player.global_position = Vector3(main.maze_view.word_powerup_node.position.x, main.player.global_position.y, main.maze_view.word_powerup_node.position.z)
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

	# ---- Manhattan is permanently word-built, has no Word Mode power-up,
	# and its taxis/pedestrians block the player without costing a life ----
	main.begin_manhattan_game()
	await get_tree().process_frame
	_check("manhattan: permanently word-built (no power-up needed)", main.maze_view.word_mode_active == true)
	_check("manhattan: no word power-up node exists", main.maze_view.word_powerup_node == null)
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
	var landmark_found := false
	for child in main.maze_view.word_wall_root.get_children():
		if child is MeshInstance3D and child.mesh is TextMesh:
			for entry in load("res://scripts/manhattan_maze.gd").LANDMARKS:
				if child.mesh.text == entry[0]:
					landmark_found = true
	_check("manhattan: a real landmark name appears among the rendered walls", landmark_found)
	_check("manhattan: neon environment applied", main.world_env.environment.background_color.is_equal_approx(main.MANHATTAN_BG_COLOR))
	_check("manhattan: metro stations spawned", main.metro_stations.size() > 0, "got %d" % main.metro_stations.size())

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
	_check("manhattan: normal environment restored after metro exit", main.world_env.environment.background_color.is_equal_approx(main.NORMAL_BG_COLOR))

	Speedrun.reset_all()
