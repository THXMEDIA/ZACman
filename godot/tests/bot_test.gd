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
