extends Node
## Headless bot simulation for the actual Main scene (not a mock): runs the
## real Godot physics/script pipeline in --headless mode, drives the player
## via the Input singleton and direct state pokes (same spirit as the
## Node-based harness that validated the web version), and asserts on the
## real Main node's state. Run with:
##   godot --headless --path . res://tests/BotTest.tscn
## Exits with code 0 if every check passes, 1 otherwise.

const SaveIsolation := preload("res://tests/save_isolation.gd")
const LevelsScript := preload("res://scripts/levels.gd")

var main
var failures := 0
var checks := 0
var _real_saves := {}


func _ready() -> void:
	# QA-W6: Speedrun/Leaderboard/high score go to their own test folder for
	# the whole simulation. The autoloads already read the real files at
	# startup (read only), so they reload from the test folder here, before
	# Main exists.
	_real_saves = SaveIsolation.begin()
	Speedrun.reload()
	Leaderboard.reload()
	var main_scene: PackedScene = load("res://scenes/Main.tscn")
	main = main_scene.instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame

	await _run_checks()
	await _run_look_checks()

	_check("test isolation: Speedrun saves under the test folder", Speedrun.save_path().begins_with(SaveIsolation.SavePathsScript.TEST_ROOT), Speedrun.save_path())
	_check("test isolation: Leaderboard saves under the test folder", Leaderboard.save_path().begins_with(SaveIsolation.SavePathsScript.TEST_ROOT), Leaderboard.save_path())
	_check("test isolation: real save files unchanged after the simulation", SaveIsolation.end(_real_saves))

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

	# ---- GD-W10: the player must start facing an open corridor, not a wall
	# in their face (see Main._facing_yaw_for_start) ----
	var start_yaw: float = main.player.yaw
	var start_dc: int = roundi(-sin(start_yaw))
	var start_dr: int = roundi(-cos(start_yaw))
	_check("level start: player faces an open neighbor cell, not a wall", MazeGen.is_open(main.maze, main.start_cell.x + start_dr, main.start_cell.y + start_dc), "start_cell=%s yaw=%f dr=%d dc=%d" % [main.start_cell, start_yaw, start_dr, start_dc])

	# ---- Speedrun base look "Lagune" (spec 1.1): wall/floor shaders.
	# Replaces the old matrix_rain checks; the Matrix look becomes a rabbit
	# condition in Etappe 2. More look checks in _run_look_checks(). ----
	var wall_shader: Shader = main.maze_view.wall_material.shader
	_check("speedrun wall: pacman_wall shader in use", wall_shader.resource_path == "res://shaders/pacman_wall.gdshader")
	_check("speedrun wall: psychedelic_amount uniform kept (Fear & Loathing until Etappe 2)", wall_shader.code.find("uniform float psychedelic_amount") != -1)
	_check("speedrun wall: lines antialiased via fwidth", wall_shader.code.find("fwidth(") != -1)
	_check("speedrun wall: half_w derived from cell", wall_shader.code.find("cell * 0.5") != -1)
	_check("speedrun wall: base dashes every 0.5 m", wall_shader.code.find("uniform float dash_len = 0.5;") != -1)
	var floor_mat = main.maze_view.floor_mesh.material_override
	_check("speedrun floor: pacman_floor shader in use", floor_mat is ShaderMaterial and floor_mat.shader.resource_path == "res://shaders/pacman_floor.gdshader")
	_check("speedrun floor: lit, not unshaded (ghost light visible)", floor_mat is ShaderMaterial and _shader_render_mode(floor_mat.shader).find("unshaded") == -1)
	_check("speedrun look: no wall line color in the blue hue range 215-250 deg", _theme_line_colors_not_blue(main.maze_view.city_theme))
	_check("speedrun wall: corridors narrowed via a bigger-than-CELL wall footprint", main.maze_view.city_theme.wall_footprint_scale > 1.0)
	_check("speedrun wall: taller than the previous WALL_H", main.maze_view.WALL_H > 3.8)

	# ---- Background music: an original synthesized "arcade" loop starts a
	# normal run (see Sfx.play_arcade_music / audio_synth.gd) ----
	_check("music: arcade track starts on a normal run", Sfx.music_state() == "arcade")
	var all_house := true
	for e in main.enemies:
		if e.mode != "house":
			all_house = false
	_check("begin_game: enemies start in house", all_house)

	# ---- no sky clouds in the Speedrun look (spec 1.1); should a theme
	# bring them back, they must still float well above the wall tops ----
	var mv: Node = main.maze_view
	_check("sky clouds: none in the Speedrun look", mv.sky_cloud_nodes.size() == 0, "got %d" % mv.sky_cloud_nodes.size())
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

	# ---- ghost speed growth is capped, not unbounded (regression test for
	# review finding GD-N1 — see Main.GHOST_SPEED_CAP) ----
	var LevelsForSpeedTest = load("res://scripts/levels.gd")
	main.level_index = LevelsForSpeedTest.POOL.size() - 1 # extra == 0: speed here must be untouched by the cap
	main.start_level(LevelsForSpeedTest.by_id("klassik-4")) # the fastest-tuned level (ghost_speed 2.75, 5 ghosts)
	await get_tree().process_frame
	var fastest_at_level4: float = 0.0
	for e in main.enemies:
		fastest_at_level4 = maxf(fastest_at_level4, e.base_speed)
	_check("ghost speed cap doesn't affect the tuned early levels", is_equal_approx(fastest_at_level4, 2.95), "fastest=%f" % fastest_at_level4)

	main.level_index = 40 # far past the pool — the old formula would put this around 2.75+0.35+37*0.15 ≈ 8.65 m/s
	main.start_level(LevelsForSpeedTest.by_id("klassik-1"))
	await get_tree().process_frame
	var fastest_at_level41: float = 0.0
	for e in main.enemies:
		fastest_at_level41 = maxf(fastest_at_level41, e.base_speed)
	_check("ghost speed never exceeds GHOST_SPEED_CAP, however high the level", fastest_at_level41 <= main.GHOST_SPEED_CAP + 0.001, "fastest=%f cap=%f" % [fastest_at_level41, main.GHOST_SPEED_CAP])
	_check("GHOST_SPEED_CAP stays below the player's own speed", main.GHOST_SPEED_CAP < main.player.PLAYER_SPEED, "cap=%f player_speed=%f" % [main.GHOST_SPEED_CAP, main.player.PLAYER_SPEED])

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
	# Leaderboard.reset_all() too, not just Speedrun's: begin_game() above (no
	# forced id) draws a random level, which could by chance already have
	# been klassik-1 and left an entry on its board, contaminating the
	# exact-size-1 check below.
	Speedrun.reset_all()
	Leaderboard.reset_all()
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

	# ---- GD-W6/UX-W7/Code-W3: pause freezes every effect timer (the "now"
	# clock itself stops advancing), but the speedrun time still "costs"
	# the paused duration — it's charged back in separately at completion
	# (per the user's own decision, "Pause kostet Zeit"). `real_now` is the
	# always-advancing speedrun clock (never frozen, even by pause); `now`
	# is the effect clock that pause freezes — see Main's real_now doc
	# comment. Reuses the still-running game from the twitch-command checks
	# above rather than calling begin_game() again, which would reset
	# twitch_assisted and break the "marks this run as assisted" check
	# right after this block.
	var now_before_pause: float = main.now
	var real_now_before_pause: float = main.real_now
	main.paused = true
	await get_tree().create_timer(0.3).timeout
	_check("pause: the game clock (now) freezes while paused", main.now == now_before_pause, "before=%f after=%f" % [now_before_pause, main.now])
	_check("pause: the speedrun clock (real_now) keeps advancing while paused", main.real_now > real_now_before_pause + 0.1, "got %f" % main.real_now)
	main.paused = false
	await get_tree().process_frame
	await get_tree().process_frame
	var expected_timer_text := Speedrun.format_time(main.real_now - main.level_start_real)
	_check("pause: the paused duration is charged to the displayed/recorded time", main.hud.timer_label.text == expected_timer_text, "got=%s want=%s real_now=%f level_start_real=%f" % [main.hud.timer_label.text, expected_timer_text, main.real_now, main.level_start_real])

	# ---- GD-K3/Code-W7: a run any handled Twitch command touched is flagged
	# and recorded on its own "chat" leaderboard/best-time board, never mixed
	# into the solo one, so a viewer can't trivialize or falsify a clean
	# (solo) time ----
	_check("twitch !power/!fruit mark this run as chat-assisted", main.level_chat_assisted == true and main.run_mode() == "chat")
	var cleared_level_id: String = main.level_id
	var solo_best_before: float = Speedrun.best_for(cleared_level_id, main.condition_id, "solo")
	var solo_board_count_before: int = Leaderboard.get_top(cleared_level_id, main.condition_id, 50, "solo").size()
	main.level_complete_sequence()
	_check("chat-assisted clear: solo best time NOT touched", Speedrun.best_for(cleared_level_id, main.condition_id, "solo") == solo_best_before, "before=%s after=%s" % [solo_best_before, Speedrun.best_for(cleared_level_id, main.condition_id, "solo")])
	_check("chat-assisted clear: solo leaderboard NOT updated", Leaderboard.get_top(cleared_level_id, main.condition_id, 50, "solo").size() == solo_board_count_before)
	_check("chat-assisted clear: recorded on its own chat board instead", Speedrun.best_for(cleared_level_id, main.condition_id, "chat") >= 0.0)
	_check("chat-assisted clear: banner names the chat board", main.hud.levelclear_sub.text.find(load("res://scripts/levels.gd").MODE_LABELS["chat"]) != -1, main.hud.levelclear_sub.text)
	await get_tree().create_timer(2.4).timeout # let the banner/level-advance sequence finish before the next scenario

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

	# ---- Code-W1 follow-up: Word Mode and the Fear & Loathing pickup can be
	# picked up while overlapping (one ends mid-flight of the other). Noclip
	# is derived from the sources that want it (see Main._noclip_wanted), so
	# this proves overlapping effects can't leave it stuck on or clobber the
	# other's active_condition ----
	main._activate_word_mode()
	main._activate_fear_powerup()
	await get_tree().process_frame
	_check("overlap: word+fear both active, noclip still on (word mode)", main.player.collision_mask == 0)
	main.word_mode_until = main.now - 0.01 # word mode expires first
	await get_tree().process_frame
	_check("overlap: word mode expiry while fear still active restores normal collision (fear never needed noclip)", main.player.collision_mask == 2)
	_check("overlap: active_condition is still the fear condition, not cleared by word mode ending", main.player.active_condition != null and main.player.active_condition.id == "fear_and_loathing")
	main.fear_mode_until = main.now - 0.01 # now let fear expire too
	await get_tree().process_frame
	_check("overlap: after both expire, active_condition is null (no whole-run condition was selected)", main.player.active_condition == null)
	_check("overlap: after both expire, collision stays normal", main.player.collision_mask == 2)

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

	# Manhattan is an untimed hub: stepping close enough to a metro station's
	# sign is the only exit, and it starts a normal (scored, timed) speedrun
	# on a random level of the pool — see _check_metro_entry/_enter_metro.
	var metro = main.metro_stations[0]
	main.player.global_position = Vector3(metro.position.x, main.player.global_position.y, metro.position.z)
	await get_tree().process_frame
	await get_tree().process_frame
	# _enter_metro shows a brief "SUBWAY" banner (create_timer(1.4)) before
	# calling begin_game() — give it time to finish rather than checking
	# mid-transition.
	await get_tree().create_timer(1.6).timeout
	_check("manhattan: entering a metro station ends the Manhattan run", main.playing_manhattan == false)
	_check("manhattan: entering a metro station starts a normal speedrun level", main.running == true and main.level_id != "")
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

	# ---- GD-K2/Code-K1: noclip softlock fix. While noclip is on (matrix_ghost
	# above), walk the player somewhere a normal player could never be — well
	# outside the maze bounds — then switch away from matrix_ghost (noclip
	# off). Main._refresh_noclip must call _rescue_player_from_wall and
	# relocate the player into a real open cell instead of leaving them
	# stuck outside the maze/embedded in a wall with collision suddenly on ----
	main.player.global_position = Vector3(main.player.global_position.x, main.player.global_position.y, -999.0)
	main.set_condition("fear_and_loathing")
	await get_tree().process_frame
	_check("conditions: switching condition reverts the previous one (word mode off)", main.maze_view.word_mode_active == false)
	_check("conditions: switching condition reverts the previous one (noclip off)", main.player.collision_mask == 2)
	var relocated_cell: Vector2i = main.player.cell()
	_check("noclip softlock fix: player relocated into the maze bounds", relocated_cell.x >= 0 and relocated_cell.x < main.maze.rows)
	_check("noclip softlock fix: player relocated into an open cell, not a wall", MazeGen.is_open(main.maze, relocated_cell.x, relocated_cell.y), "cell=%s" % relocated_cell)
	_check("conditions: fear_and_loathing wires itself onto the player", main.player.active_condition != null and main.player.active_condition.id == "fear_and_loathing")

	main.set_condition("")
	await get_tree().process_frame
	_check("conditions: clearing the condition removes it from the player", main.current_condition == null and main.player.active_condition == null)

	Speedrun.reset_all()


## ---------------- Speedrun look "Lagune", look API, Manhattan unchanged ----------------

const CityThemesScript := preload("res://scripts/city_themes.gd")
const CityThemeScript := preload("res://scripts/city_theme.gd")


func _shader_render_mode(shader: Shader) -> String:
	for line in shader.code.split("\n"):
		if line.begins_with("render_mode"):
			return line
	return ""


func _is_blue_hue(c: Color) -> bool:
	var hdeg := c.h * 360.0
	return c.s > 0.05 and hdeg >= 215.0 and hdeg <= 250.0


## Every wall line color of every level look plus the minimap wall color.
func _theme_line_colors_not_blue(ct) -> bool:
	for look_id in ct.level_looks:
		for role in ["top", "base"]:
			if _is_blue_hue(ct.level_looks[look_id][role]):
				return false
	return not _is_blue_hue(ct.minimap_wall_color)


func _has_tunnel_vista(mv) -> bool:
	for ch in mv.get_children():
		if ch is MeshInstance3D and ch.mesh is QuadMesh and ch.mesh.material is ShaderMaterial and ch.mesh.material.shader.resource_path.ends_with("mario_vista.gdshader"):
			return true
	return false


func _ghost_colors_ok(ghosts: Array, look: Dictionary) -> String:
	for e in ghosts:
		var c: Color = e.palette_color
		var hdeg := c.h * 360.0
		if c.s > 0.3 and hdeg >= 75.0 and hdeg <= 165.0:
			return "green ghost %s" % c.to_html(false)
		if c.s > 0.3 and hdeg > 165.0 and hdeg <= 205.0:
			return "cyan ghost %s" % c.to_html(false)
		if c.is_equal_approx(look.base) or c.is_equal_approx(look.top):
			return "ghost in the level's gradient color %s" % c.to_html(false)
	return ""


func _run_look_checks() -> void:
	var lagune_base: Color = CityThemesScript.LOOK_BASE_LAGUNE
	var riff_base: Color = CityThemesScript.LOOK_BASE_RIFF
	var violet: Color = CityThemesScript.GHOST_STREUNER.color

	# ---- Klassik I: look "lagune" ----
	main.begin_game("klassik-1")
	await get_tree().process_frame
	var mv = main.maze_view
	var ct = mv.city_theme
	_check("look klassik-1: level look is lagune", mv.level_look_id == "lagune", mv.level_look_id)
	_check("look klassik-1: wall gradient #0B7FA8", Color(mv.wall_material.get_shader_parameter("line_base")).is_equal_approx(lagune_base))
	_check("look klassik-1: top edge #1EF2C8", Color(mv.wall_material.get_shader_parameter("line_top")).is_equal_approx(Color("1ef2c8")))
	_check("look klassik-1: wall mass #06141C", Color(mv.wall_material.get_shader_parameter("body_color")).is_equal_approx(Color("06141c")))
	_check("look klassik-1: floor albedo #0D0F16", Color(mv.floor_mesh.material_override.get_shader_parameter("floor_albedo")).is_equal_approx(Color("0d0f16")))
	_check("look: background and fog #05070B", main.world_env.environment.background_color.is_equal_approx(Color("05070b")) and main.world_env.environment.fog_light_color.is_equal_approx(Color("05070b")))
	_check("look: no sky clouds, no Mario vista in the tunnel", mv.sky_cloud_nodes.is_empty() and not _has_tunnel_vista(mv) and not ct.ceil_sky_clouds)
	_check("look: wall instances carry the neighbor mask", mv.normal_wall_mmi.multimesh.use_custom_data)
	var overlay = mv.screen_overlay
	var overlay_ok: bool = overlay != null and overlay.layer < main.hud.layer and overlay.get_child(0).material.shader.resource_path == "res://shaders/crt_overlay.gdshader"
	_check("look: CRT overlay below the HUD", overlay_ok)
	if overlay_ok:
		var crt: Shader = overlay.get_child(0).material.shader
		_check("look: CRT overlay has 270 lines per image height, no TIME (no flicker)", crt.code.find("line_count = 270.0") != -1 and crt.code.find("TIME") == -1)
	_check("look: pellets are cream cubes at ~0.4 m", mv.pellet_meshes.size() > 0 and mv.pellet_meshes[0].mesh is BoxMesh and absf(mv.pellet_meshes[0].position.y - 0.42) < 0.01 and ct.pellet_color.is_equal_approx(Color("fff0c8")))
	_check("look: power pellet is a diamond blinking below 3 Hz", mv.power_nodes.size() > 0 and mv.power_nodes[0].mesh is BoxMesh and absf(mv.power_nodes[0].rotation.x) > 0.1 and ct.power_blink_hz > 0.0 and ct.power_blink_hz < 3.0)
	_check("look: minimap walls #128F7C", ct.minimap_wall_color.is_equal_approx(Color("128f7c")))
	_check("look: no wall line in the blue hue range 215-250 deg (all looks + minimap)", _theme_line_colors_not_blue(ct))
	var k1_err := _ghost_colors_ok(main.enemies, mv.level_look)
	_check("look klassik-1: no green, cyan or gradient-colored ghost", k1_err == "", k1_err)
	var has_violet := false
	for e in main.enemies:
		if e.palette_color.is_equal_approx(violet):
			has_violet = true
	_check("look klassik-1: Streuner is violet in a Lagune level", has_violet)
	_check("look: frightened ghosts #BDFCEF", main.enemies[0].frightened_color.is_equal_approx(Color("bdfcef")))

	# ---- Look API (prepared for Etappe 2): swap materials on the same instances ----
	var wall_mmi = mv.normal_wall_mmi
	var floor_node = mv.floor_mesh
	var base_wall = wall_mmi.material_override
	var base_floor = floor_node.material_override
	var children_before: int = mv.get_child_count()
	var collision_before: int = mv.walls_body.get_child_count()
	_check("look API: base look registered and active", mv.has_look(mv.LOOK_BASE) and mv.current_look == mv.LOOK_BASE and base_wall == mv.wall_material)
	var test_wall := ShaderMaterial.new()
	test_wall.shader = base_wall.shader
	var test_floor := StandardMaterial3D.new()
	mv.register_look("test_condition", test_wall, test_floor)
	var switched: bool = mv.set_look("test_condition")
	_check("look API: switch to another look swaps materials in place", switched and mv.normal_wall_mmi == wall_mmi and mv.floor_mesh == floor_node and wall_mmi.material_override == test_wall and floor_node.material_override == test_floor and mv.wall_material == test_wall and mv.current_look == "test_condition")
	_check("look API: no second wall set, collision untouched", mv.get_child_count() == children_before and mv.walls_body.get_child_count() == collision_before)
	mv.set_look_param("psychedelic_amount", 0.5)
	_check("look API: set_look_param reaches the current look's shader", is_equal_approx(float(test_wall.get_shader_parameter("psychedelic_amount")), 0.5))
	mv.register_look("wall_only", test_wall, null)
	mv.set_look("wall_only")
	_check("look API: a null floor material keeps the base floor", floor_node.material_override == base_floor and wall_mmi.material_override == test_wall)
	var back: bool = mv.set_look(mv.LOOK_BASE)
	_check("look API: back to the base look restores the original materials", back and wall_mmi.material_override == base_wall and floor_node.material_override == base_floor and mv.wall_material == base_wall)
	_check("look API: unknown look id is refused", mv.set_look("does_not_exist") == false and mv.current_look == mv.LOOK_BASE)
	main.begin_game("klassik-1")
	await get_tree().process_frame
	_check("look API: a rebuild starts on the base look again", main.maze_view.current_look == main.maze_view.LOOK_BASE and not main.maze_view.has_look("test_condition"))

	# ---- Klassik II: look "riff" ----
	main.begin_game("klassik-2")
	await get_tree().process_frame
	mv = main.maze_view
	_check("look klassik-2: level look is riff", mv.level_look_id == "riff", mv.level_look_id)
	_check("look klassik-2: wall gradient #1FBF5A", Color(mv.wall_material.get_shader_parameter("line_base")).is_equal_approx(riff_base))
	var k2_err := _ghost_colors_ok(main.enemies, mv.level_look)
	_check("look klassik-2: no green, cyan or gradient-colored ghost", k2_err == "", k2_err)
	var violet_in_riff := false
	for e in main.enemies:
		if e.palette_color.is_equal_approx(violet):
			violet_in_riff = true
	_check("look klassik-2: violet Streuner in a Riff level too (studio head 03.10.)", violet_in_riff)
	main.begin_game("klassik-4")
	await get_tree().process_frame
	var k4_colors := {}
	for e in main.enemies:
		k4_colors[e.palette_color.to_html(false)] = true
	_check("look klassik-4: five ghosts, five distinguishable colors", main.enemies.size() == 5 and k4_colors.size() == 5, str(k4_colors.keys()))
	var looks_ok := true
	for lv in LevelsScript.POOL:
		if not ct.level_looks.has(lv.get("look", "")):
			looks_ok = false
	_check("look: every pool level names a known look", looks_ok)

	# ---- Manhattan keeps its own look (nothing of the Speedrun look leaks in) ----
	main.begin_manhattan_game()
	await get_tree().process_frame
	mv = main.maze_view
	var man = CityThemesScript.get_theme("manhattan")
	var defaults = CityThemeScript.new()
	_check("manhattan unchanged: no CRT overlay", mv.screen_overlay == null)
	_check("manhattan unchanged: plain StandardMaterial3D walls and floor", mv.normal_wall_mmi.material_override is StandardMaterial3D and mv.floor_mesh.material_override is StandardMaterial3D and not mv.normal_wall_mmi.multimesh.use_custom_data)
	_check("manhattan unchanged: floor color", mv.floor_mesh.material_override.albedo_color.is_equal_approx(man.floor_color))
	_check("manhattan unchanged: no level look", mv.level_look_id == "" and mv.level_look.is_empty())
	_check("manhattan unchanged: environment", main.world_env.environment.background_color.is_equal_approx(man.env_bg_color) and main.world_env.environment.fog_light_color.is_equal_approx(man.env_fog_color))
	_check("manhattan unchanged: pellets are the original spheres at 0.32 m", mv.pellet_meshes.size() > 0 and mv.pellet_meshes[0].mesh is SphereMesh and is_equal_approx(mv.pellet_meshes[0].mesh.radius, 0.11) and is_equal_approx(mv.pellet_meshes[0].position.y, 0.32))
	_check("manhattan unchanged: original minimap and pickup colors", man.minimap_wall_color == defaults.minimap_wall_color and man.minimap_bg_color == defaults.minimap_bg_color and man.pellet_color == defaults.pellet_color)
