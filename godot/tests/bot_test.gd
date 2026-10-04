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
const ConditionsScript := preload("res://scripts/conditions.gd")
const WhiteRabbitScript := preload("res://scripts/white_rabbit.gd")
const FearScript := preload("res://scripts/conditions/fear_and_loathing.gd")
const SettingsScript := preload("res://scripts/settings.gd")
const WOCHE := "woche"

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
	# Most scenarios start a level and act at once; the start intro / hold
	# has its own checks in _run_intro_checks().
	main.skip_start_intro = true
	# A fixed week, so the rabbit results do not depend on the test date.
	main.rabbit_week_override = Vector2i(2026, 40)
	# N6: every random choice of Main (level draw, ghost turns, Chaos and
	# chat rabbits) from seeded generators — the checks below that compare
	# several random results are deterministic now.
	main.seed_randomness(4242)

	await _run_checks()
	await _run_look_checks()
	await _run_rabbit_checks()
	await _run_condition_checks()
	await _run_intro_checks()
	await _run_board_checks()
	await _run_chat_vote_checks()
	await _run_review_fix_checks()

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

	# ---- start screen offers Speedrun vs Explorer-level right away,
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

	# ---- start screen: no condition choice any more (the rabbit decides),
	# neutral SPEEDRUN button, no "Matrix" wording ----
	_check("start screen: no condition selector", not ("condition_option" in main.hud) and not main.hud.has_signal("condition_selected"))
	var start_texts := _texts_under(main.hud.start_panel)
	_check("start screen: speedrun button is called SPEEDRUN", start_texts.has("SPEEDRUN"), str(start_texts))
	var matrix_words := false
	for t in start_texts:
		if t.find("MATRIX") != -1 or t.find("Matrix") != -1:
			matrix_words = true
	_check("start screen: no MATRIX-LEVEL / Matrix Ghost wording", not matrix_words)
	_check("start screen + pause: 'Effekte reduzieren' switch", main.hud.reduce_fx_start != null and main.hud.reduce_fx_pause != null)

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
	# The Matrix look is a rabbit condition now (kond_wall); more look
	# checks in _run_look_checks() and _run_condition_checks(). ----
	var wall_shader: Shader = main.maze_view.wall_material.shader
	_check("speedrun wall: pacman_wall shader in use", wall_shader.resource_path == "res://shaders/pacman_wall.gdshader")
	var wall_base := FileAccess.get_file_as_string("res://shaders/pacman_wall_base.gdshaderinc")
	_check("speedrun wall: base look shared via pacman_wall_base include", wall_shader.code.find("pacman_wall_base.gdshaderinc") != -1)
	_check("speedrun wall: old psychedelic effect removed", wall_base.find("psychedelic") == -1 and wall_shader.code.find("psychedelic") == -1 and not ("set_psychedelic" in main.maze_view))
	_check("speedrun wall: lines antialiased via fwidth", wall_base.find("fwidth(") != -1)
	_check("speedrun wall: half_w derived from cell", wall_base.find("cell * 0.5") != -1)
	_check("speedrun wall: base dashes every 0.5 m", wall_base.find("uniform float dash_len = 0.5;") != -1)
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
	_check("fast clear records a klassik-1 best time on the week board", Speedrun.best_for("klassik-1", WOCHE) >= 0.0 and Speedrun.best_for("klassik-1", WOCHE) < 10.0, "best=%s" % Speedrun.best_for("klassik-1", WOCHE))
	_check("fast clear lands on the klassik-1 solo leaderboard (board woche)", Leaderboard.get_top("klassik-1", WOCHE).size() == 1)
	_check("fast clear leaves the chat and chaos boards empty", Leaderboard.get_top("klassik-1", "chat").size() == 0 and Leaderboard.get_top("klassik-1", "chaos").size() == 0)
	_check("board key: level|brett|modus, no condition", Leaderboard.board_key("klassik-1", main.board_id(), main.run_mode()) == "klassik-1|woche|solo")
	_check("week board: the best time names its ISO week", Speedrun.best_entry("klassik-1", WOCHE).get("week", "") == "2026-W40" and Leaderboard.get_top("klassik-1", WOCHE)[0].week == "2026-W40")
	_check("week board: HUD best time shows the week", main.hud.best_label.text.ends_with("KW 40"), main.hud.best_label.text)
	_check("week board: HUD board badge shows the week", main.hud.board_chip.visible and main.hud.board_label.text == "WOCHE · KW 40", main.hud.board_label.text)
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

	main.hud.restart_pressed.emit() # NEUSTART in Manhattan restarts Manhattan, not a speedrun level
	await get_tree().process_frame
	_check("manhattan: NEUSTART restarts the Explorer level", main.running == true and main.playing_manhattan == true)
	_check("manhattan: no rabbit and no condition", main.maze_view.rabbit_node == null and main.active_condition == null and main.player.active_condition == null)

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
	# level_chat_assisted and break the "chat board" check right after
	# this block.
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
	_check("twitch !power/!fruit put this level on the chat board", main.level_chat_assisted == true and main.board_id() == "chat" and main.run_mode() == "solo")
	var cleared_level_id: String = main.level_id
	var week_best_before: float = Speedrun.best_for(cleared_level_id, WOCHE)
	var week_board_count_before: int = Leaderboard.get_top(cleared_level_id, WOCHE, 50).size()
	main.level_complete_sequence()
	_check("chat-assisted clear: weekly best time NOT touched", Speedrun.best_for(cleared_level_id, WOCHE) == week_best_before, "before=%s after=%s" % [week_best_before, Speedrun.best_for(cleared_level_id, WOCHE)])
	_check("chat-assisted clear: weekly leaderboard NOT updated", Leaderboard.get_top(cleared_level_id, WOCHE, 50).size() == week_board_count_before)
	_check("chat-assisted clear: recorded on the chat board instead", Speedrun.best_for(cleared_level_id, "chat") >= 0.0)
	_check("chat-assisted clear: banner names the chat board", main.hud.levelclear_sub.text.find("Chat-Bestenliste") != -1, main.hud.levelclear_sub.text)
	await get_tree().create_timer(2.4).timeout # let the banner/level-advance sequence finish before the next scenario

	# ---- noclip can no longer lock the player out of the maze ----
	main.begin_game("klassik-1")
	await get_tree().process_frame
	main.start_condition(ConditionsScript.get_condition("matrix"))
	main.player.global_position = Vector3(main.player.global_position.x, main.player.global_position.y, -7.0)
	main._keep_noclip_player_in_maze()
	_check("noclip: player is clamped to the maze rows", main.player.global_position.z >= 0.0)
	var wall_cell := Vector2i(-1, -1)
	for r in range(2, main.maze.rows - 2, 2):
		for c in range(2, main.maze.cols - 2, 2):
			if main.maze.grid[r][c] == 1 and wall_cell.x < 0:
				wall_cell = Vector2i(r, c)
	main.player.global_position = Vector3(wall_cell.y * main.CELL, main.player.global_position.y, wall_cell.x * main.CELL)
	main._end_condition(false)
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
	_check("chat: a plain level starts on the weekly board", main.board_id() == WOCHE and main.level_chat_assisted == false)
	Twitch.chat_command.emit("viewer", "power", "")
	await get_tree().process_frame
	_check("chat: a !power that took effect moves the level to the chat board", main.board_id() == "chat")
	_check("chat: the HUD shows the CHAT badge", main.hud.board_label.text == "CHAT" and main.hud.board_chip.visible)
	main.level_start_real = main.real_now - 5.0
	for cell in main.maze_view.pellet_cells:
		main.player.global_position = Vector3(cell.y * main.CELL, main.player.global_position.y, cell.x * main.CELL)
		await get_tree().process_frame
	for i in main.maze_view.power_cells.size():
		var cnode = main.maze_view.power_nodes[i]
		main.player.global_position = Vector3(cnode.position.x, main.player.global_position.y, cnode.position.z)
		await get_tree().process_frame
	_check("chat: the time lands on the chat leaderboard", Leaderboard.get_top("klassik-1", "chat").size() == 1)
	_check("chat: the weekly and chaos leaderboards stay empty", Leaderboard.get_top("klassik-1", WOCHE).size() == 0 and Leaderboard.get_top("klassik-1", "chaos").size() == 0)
	_check("chat: the weekly best time stays empty", Speedrun.best_for("klassik-1", WOCHE) == -1.0 and Speedrun.best_for("klassik-1", "chat") >= 0.0)
	_check("chat: a chat run does not earn the target-time badge", not Speedrun.is_bonus_unlocked())
	await get_tree().create_timer(2.0).timeout
	_check("chat: the next level starts clean (weekly board again)", main.board_id() == WOCHE)

	# ---- a run with a rabbit condition stays on the week board (the
	# condition is no longer part of the key, spec 2.5) ----
	main.begin_game("klassik-1")
	await get_tree().process_frame
	main.start_condition(ConditionsScript.get_condition("taschenuhr"))
	main.level_start_real = main.real_now - 5.0
	for cell in main.maze_view.pellet_cells:
		main.player.global_position = Vector3(cell.y * main.CELL, main.player.global_position.y, cell.x * main.CELL)
		await get_tree().process_frame
	for i in main.maze_view.power_cells.size():
		var cnode2 = main.maze_view.power_nodes[i]
		main.player.global_position = Vector3(cnode2.position.x, main.player.global_position.y, cnode2.position.z)
		await get_tree().process_frame
	_check("condition run: the time lands on the week board", Leaderboard.get_top("klassik-1", WOCHE, 5).size() == 1)
	_check("condition run: no condition board is written", Leaderboard._boards.keys().all(func(k): return load("res://scripts/levels.gd").is_valid_board_key(k)), str(Leaderboard._boards.keys()))
	_check("condition run: the level clear ended the condition", main.active_condition == null)
	await get_tree().create_timer(2.0).timeout
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

	# ---- Manhattan is permanently word-built, has no white rabbit,
	# and its taxis/pedestrians block the player without costing a life ----
	main.begin_manhattan_game()
	await get_tree().process_frame
	_check("manhattan: permanently word-built (no power-up needed)", main.maze_view.word_mode_active == true)
	_check("manhattan: no white rabbit", main.maze_view.rabbit_node == null and main.maze_view.rabbit_cell == Vector2i(-1, -1))
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
	main.skip_start_intro = false # the metro exit is a speedrun start: intro + hold
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
	_check("manhattan: the metro exit shows the start intro (begin_game)", main.start_hold == true)
	main.skip_start_intro = true
	main.begin_game()
	await get_tree().process_frame

	# ---- Tokyo Explorer city (docs/design/tokyo-explorer.md, M1): chosen on
	# the start screen, calm like Manhattan, its own neon look; the subway
	# exit leads into a speedrun and the speedrun must not keep Tokyo's
	# glow / SSR / volumetrics (theme reset) ----
	_check("start screen: explorer choice Manhattan / Tokyo", main.hud.manhattan_btn.visible and main.hud.tokyo_btn != null and main.hud.tokyo_btn.visible and main.hud.tokyo_btn.text == "TOKYO")
	var speedrun_far: float = main.player.camera.far
	var speedrun_light: Color = main.player.light.light_color
	main.hud.explorer_pressed.emit("tokyo")
	await get_tree().process_frame
	var tokyo_theme = load("res://scripts/city_themes.gd").get_theme("tokyo")
	_check("tokyo: the TOKYO button starts the Tokyo explorer city", main.running and main.playing_explorer and main.explorer_city_id == "tokyo" and not main.playing_manhattan)
	_check("tokyo: HUD level chip says TOKYO", main.hud.level_label.text == "TOKYO", main.hud.level_label.text)
	_check("tokyo: no ghosts, no power pellets, no rabbit", main.enemies.is_empty() and main.maze_view.power_cells.is_empty() and main.maze_view.rabbit_node == null)
	_check("tokyo: timer / score / lives chips are hidden", main.hud.timer_label.get_parent().get_parent().visible == false and main.hud.score_label.get_parent().get_parent().visible == false)
	_check("tokyo: the neon line city is built", main.maze_view.scenery_root != null and main.maze_view.city_theme.id == "tokyo")
	_check("tokyo: exactly one subway exit (地下鉄), in the station facade", main.metro_stations.size() == 1 and main.metro_stations[0].get_script().resource_path.ends_with("tokyo_metro_station.gd"))
	_check("tokyo: pellets lead the way", main.maze_view.pellet_cells.size() > 40, "got %d" % main.maze_view.pellet_cells.size())
	_check("tokyo: level seed from the city registry", main.maze_view.scenery_seed == 7310)
	# ---- Tokyo M2: rain, traffic, passers-by, scramble (tokyo_life.gd) ----
	var tk_life = main.tokyo_life
	_check("tokyo M2: the moving city runs (rain, cars, people)", tk_life != null and tk_life.rain_mmi != null and tk_life.car_count() >= 12 and tk_life.walker_count() >= 125)
	_check("tokyo M2: seeded with the city's level seed", tk_life != null and tk_life.seed_value == 7310)
	var tk_car_p: Vector3 = tk_life.car_position(0)
	var tk_car_f: Vector3 = tk_life.car_fwd[0]
	var tk_side := Vector3(-tk_car_f.z, 0, tk_car_f.x)
	main.player.global_position = Vector3(tk_car_p.x, main.player.global_position.y, tk_car_p.z) + tk_side * 0.4
	main._check_explorer_obstacles()
	var tk_car_d := Vector2(main.player.global_position.x - tk_car_p.x, main.player.global_position.z - tk_car_p.z).length()
	_check("tokyo M2: a car is an obstacle (pushed out like Manhattan)", tk_car_d >= tk_life.CAR_RADIUS - 0.01, "%.2f" % tk_car_d)
	var tk_wi := -1
	for i in tk_life.walker_count():
		if tk_life.walker_visible(i):
			tk_wi = i
			break
	var tk_wp: Vector3 = tk_life.walker_position(tk_wi)
	main.player.global_position = Vector3(tk_wp.x + 0.1, main.player.global_position.y, tk_wp.z)
	var tk_score_before: int = main.score
	var tk_lives_before: int = main.lives
	main._check_explorer_obstacles()
	_check("tokyo M2: passers-by are harmless (soft push, no score, no life lost)", main.score == tk_score_before and main.lives == tk_lives_before and Vector2(main.player.global_position.x - tk_wp.x, main.player.global_position.z - tk_wp.z).length() >= main.MANHATTAN_PEDESTRIAN_OBSTACLE_RADIUS - 0.01)
	main.set_reduce_rain(true)
	_check("tokyo M2: 'Regen reduzieren' stored, switches in sync, applied to the rain", SettingsScript.load_settings().reduce_rain and main.hud.reduce_rain_start.button_pressed and main.hud.reduce_rain_pause.button_pressed and tk_life.rain_visible_count() < 8000)
	main.set_reduce_rain(false)
	main.set_reduce_fx(true)
	_check("tokyo M2: 'Effekte reduzieren' dampens the rain as well", tk_life.rain_visible_count() < 8000 and tk_life.rain_visible_count() > int(8000 * 0.35))
	main.set_reduce_fx(false)
	_check("tokyo M2: both off -> full rain, settings stored", tk_life.rain_visible_count() == 8000 and not SettingsScript.load_settings().reduce_rain)
	_check("tokyo M2: the crossing tone exists (synthetic, short)", Sfx.has_method("crossing_signal") and Sfx.crossing_streams().size() == 2 and Sfx.crossing_streams()[0].get_length() < 0.2)
	var tk_walk_tone := [0]
	tk_life.walk_started.connect(func(): tk_walk_tone[0] += 1)
	tk_life.advance(tk_life.WALK_START - tk_life.cycle_time + 0.1)
	_check("tokyo M2: All Walk is announced (walk_started)", tk_walk_tone[0] == 1 and tk_life.is_walk_phase())
	main.player.global_position = Vector3(main.start_cell.y * main.CELL, main.player.global_position.y, main.start_cell.x * main.CELL)
	var tenv: Environment = main.world_env.environment
	var ssr_expected: bool = RenderingServer.get_rendering_device() != null # SSR only in Forward+ (QA K2)
	_check("tokyo: glow on, SSR only where Forward+ has it, filmic tonemap", tenv.glow_enabled and tenv.ssr_enabled == ssr_expected and tenv.tonemap_mode == Environment.TONE_MAPPER_FILMIC and not tenv.volumetric_fog_enabled)
	_check("tokyo: warm player lamp, far plane for the skyline", main.player.light.light_color.is_equal_approx(tokyo_theme.player_light_color) and is_equal_approx(main.player.camera.far, tokyo_theme.camera_far))
	_check("tokyo: player starts on the southern avenue looking north", main.player.cell() == main.start_cell and is_equal_approx(main.player.yaw, 0.0))
	# Collision sits exactly at the neon base line: walk west on the sidewalk
	# (cell row 30, col 20) into the facade of the block at x = 39 m.
	main.player.global_position = Vector3(40.6, main.player.global_position.y, 60.0)
	main.player.yaw = PI / 2.0
	main.player.move_input = Vector2(0, 1)
	for i in 30:
		await get_tree().physics_frame
	main.player.move_input = Vector2.ZERO
	var stop_x: float = main.player.global_position.x
	_check("tokyo: the player stops exactly at the facade (base line = collision)", absf(stop_x - (39.0 + main.player.PLAYER_RADIUS)) < 0.03, "x=%.3f" % stop_x)
	var tokyo_score: int = main.score
	var tokyo_left: int = main.maze_view.remaining_pickups()
	for cell in main.maze_view.pellet_cells.slice(0, 5):
		main.player.global_position = Vector3(cell.y * main.CELL, main.player.global_position.y, cell.x * main.CELL)
		await get_tree().process_frame
		await get_tree().process_frame
	_check("tokyo: pellets are eaten but give no score", main.maze_view.remaining_pickups() <= tokyo_left - 5 and main.score == tokyo_score, "left %d -> %d, score %d -> %d" % [tokyo_left, main.maze_view.remaining_pickups(), tokyo_score, main.score])
	main.hud.restart_pressed.emit() # NEUSTART restarts Tokyo, not Manhattan or a speedrun
	await get_tree().process_frame
	_check("tokyo: NEUSTART restarts Tokyo", main.running and main.explorer_city_id == "tokyo" and main.playing_explorer)
	var tmetro = main.metro_stations[0]
	main.skip_start_intro = false
	main.player.global_position = Vector3(tmetro.position.x, main.player.global_position.y, tmetro.position.z - 0.5)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(1.6).timeout
	_check("tokyo: the subway exit ends the Tokyo run", main.playing_explorer == false)
	_check("tokyo: the subway exit starts a speedrun level", main.running and main.level_id != "")
	var renv: Environment = main.world_env.environment
	_check("theme reset Tokyo -> speedrun: glow off", renv.glow_enabled == false)
	_check("theme reset Tokyo -> speedrun: SSR off", renv.ssr_enabled == false)
	_check("theme reset Tokyo -> speedrun: volumetric fog off", renv.volumetric_fog_enabled == false)
	_check("theme reset Tokyo -> speedrun: linear tonemap, exposure 1", renv.tonemap_mode == Environment.TONE_MAPPER_LINEAR and is_equal_approx(renv.tonemap_exposure, 1.0) and is_equal_approx(renv.tonemap_white, 1.0))
	_check("theme reset Tokyo -> speedrun: background, fog, sky affect of the speedrun", renv.background_color.is_equal_approx(normal_theme.env_bg_color) and is_equal_approx(renv.fog_density, normal_theme.env_fog_density) and is_equal_approx(renv.fog_sky_affect, 1.0))
	_check("theme reset Tokyo -> speedrun: player lamp and far plane restored", main.player.light.light_color.is_equal_approx(speedrun_light) and is_equal_approx(main.player.camera.far, speedrun_far))
	_check("theme reset Tokyo -> speedrun: the speedrun look is built (no neon city)", main.maze_view.scenery_root == null and main.maze_view.city_theme.id == "normal")
	_check("theme reset Tokyo -> speedrun: no rain, traffic or passers-by left", main.tokyo_life == null)
	main.skip_start_intro = true
	main.begin_game()
	await get_tree().process_frame

	# ---- QA W1/W3 (04.10.): the start screen lists every registered city,
	# and HAUPTMENÜ from a city leaves no frozen city behind the panel ----
	var reg_ids: Array = load("res://scripts/explorer_cities.gd").EXPLORER_IDS
	var btn_ok: bool = main.hud.explorer_buttons.size() == reg_ids.size()
	for cid in reg_ids:
		btn_ok = btn_ok and main.hud.explorer_buttons.has(cid)
	_check("start screen: one explorer button per registered city", btn_ok, str(main.hud.explorer_buttons.keys()))
	_check("explorer ids: one list (CityThemes == ExplorerCities)", load("res://scripts/city_themes.gd").EXPLORER_IDS == reg_ids)
	main.hud.explorer_pressed.emit("tokyo")
	await get_tree().process_frame
	_check("tokyo: exit banner does not say LEVEL GESCHAFFT", main._explorer_city().get("exit_title", "") != "LEVEL GESCHAFFT!")
	main.go_to_main_menu()
	await get_tree().process_frame
	_check("main menu from Tokyo: city life cleared", main.tokyo_life == null and main.metro_stations.is_empty() and main.taxis.is_empty() and main.pedestrians.is_empty())
	_check("main menu from Tokyo: maze hidden behind the start screen", main.maze_view.visible == false)
	_check("main menu from Tokyo: no SSR outside Forward+", main.world_env.environment.ssr_enabled == false)
	main.skip_start_intro = true
	main.begin_game()
	await get_tree().process_frame
	_check("speedrun after main menu: maze visible again", main.maze_view.visible == true)

	# ---- Konditionen: only the rabbit starts one; none at level start ----
	_check("conditions: none active at level start", main.active_condition == null and main.player.active_condition == null)
	main.start_condition(ConditionsScript.get_condition("matrix"))
	await get_tree().process_frame
	_check("conditions: matrix turns on player noclip", main.player.collision_mask == 0)
	_check("music layer: a good condition starts the good layer", Sfx.condition_layer_state() == "good" and Sfx.condition_layer_audible())
	_check("conditions: the player's condition IS Main's (one source)", main.player.active_condition == main.active_condition and main.active_condition.id == "matrix")

	# ---- GD-K2/Code-K1: noclip softlock fix. While noclip is on, walk the
	# player outside the maze bounds, then replace the condition (noclip
	# off): the player must be relocated into a real open cell ----
	main.player.global_position = Vector3(main.player.global_position.x, main.player.global_position.y, -999.0)
	main.start_condition(ConditionsScript.get_condition("fear_and_loathing"))
	await get_tree().process_frame
	_check("conditions: a new rabbit replaces the running condition (no stacking)", main.active_condition.id == "fear_and_loathing" and main.player.active_condition == main.active_condition)
	_check("music layer: a bad condition swaps to the bad layer", Sfx.condition_layer_state() == "bad")
	_check("conditions: replacing matrix turns noclip off", main.player.collision_mask == 2)
	var relocated_cell: Vector2i = main.player.cell()
	_check("noclip softlock fix: player relocated into the maze bounds", relocated_cell.x >= 0 and relocated_cell.x < main.maze.rows)
	_check("noclip softlock fix: player relocated into an open cell, not a wall", MazeGen.is_open(main.maze, relocated_cell.x, relocated_cell.y), "cell=%s" % relocated_cell)
	main._end_condition(false)
	_check("conditions: ending clears it everywhere", main.active_condition == null and main.player.active_condition == null)
	_check("music layer: ending the condition fades the layer out", Sfx.condition_layer_state() == "" and Sfx.condition_layer_audible())
	for i in 70:
		await get_tree().process_frame
	_check("music layer: ... and it is silent after the ramp", not Sfx.condition_layer_audible())

	Speedrun.reset_all()


## Every Label/Button text under `node` (for wording checks).
func _texts_under(node: Node) -> Array:
	var out := []
	for ch in node.get_children():
		if ch is Label or ch is Button:
			out.append(ch.text)
		out.append_array(_texts_under(ch))
	return out


## ---------------- Speedrun look	Speedrun.reset_all()


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
	_check("look: pellets are cream cubes at ~0.4 m", mv.pellet_cells.size() > 0 and mv.pellet_mesh() is BoxMesh and absf(mv.pellet_position(0).y - 0.42) < 0.01 and ct.pellet_color.is_equal_approx(Color("fff0c8")))
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
	_check("look: frightened ghosts cerulean #14A7CC (UX-W2)", main.enemies[0].frightened_color.is_equal_approx(Color("14a7cc")))

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
	mv.set_look_param("edge_w", 0.5)
	_check("look API: set_look_param reaches the current look's shader", is_equal_approx(float(test_wall.get_shader_parameter("edge_w")), 0.5))
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
	_check("manhattan unchanged: pellets are the original spheres at 0.32 m", mv.pellet_cells.size() > 0 and mv.pellet_mesh() is SphereMesh and is_equal_approx(mv.pellet_mesh().radius, 0.11) and is_equal_approx(mv.pellet_position(0).y, 0.32))
	_check("manhattan unchanged: original minimap and pickup colors", man.minimap_wall_color == defaults.minimap_wall_color and man.minimap_bg_color == defaults.minimap_bg_color and man.pellet_color == defaults.pellet_color)


## ---------------- White rabbit (spec 2.2, 2.5) ----------------

func _rabbit_count(mv) -> int:
	var n := 0
	for ch in mv.get_children():
		if ch.name.begins_with("WhiteRabbit"):
			n += 1
	return n


## Teleports onto the rabbit and lets one frame run: the pickup.
func _take_rabbit() -> void:
	var rn = main.maze_view.rabbit_node
	main.player.global_position = Vector3(rn.position.x, main.player.global_position.y, rn.position.z)
	main.invuln_until = main.now + 999.0
	await get_tree().process_frame


func _condition_signature() -> String:
	var c = main.active_condition
	if c == null:
		return "none"
	if c.id == "fear_and_loathing":
		return "%s/%s/%s" % [c.id, c.manipulation, c.drift_side]
	return c.id


func _run_rabbit_checks() -> void:
	for lv in LevelsScript.POOL:
		main.begin_game(lv.id)
		await get_tree().process_frame
		var mv = main.maze_view
		var cell: Vector2i = mv.rabbit_cell
		_check("rabbit %s: exactly one in the level" % lv.id, _rabbit_count(mv) == 1 and mv.rabbit_alive and cell.x >= 0, "count=%d" % _rabbit_count(mv))
		_check("rabbit %s: sits in a dead end" % lv.id, MazeGen.neighbors_of(main.maze, cell.x, cell.y).size() == 1)
		var dist: Array = MazeGen.bfs(main.maze, main.start_cell.x, main.start_cell.y)
		var max_d := 0
		for rc in MazeGen.cells_in_room(main.maze, false):
			max_d = maxi(max_d, dist[rc.x][rc.y])
		_check("rabbit %s: BFS distance >= 40 %% of the maximum" % lv.id, dist[cell.x][cell.y] >= 0.4 * max_d, "d=%d max=%d" % [dist[cell.x][cell.y], max_d])
		var rooms: int = MazeGen.cells_in_room(main.maze, false).size()
		_check("rabbit %s: replaces no required pellet (not a pickup, not counted)" % lv.id, not mv.pellet_cells.has(cell) and not mv.power_cells.has(cell) and mv.total_pickups() == rooms - 2, "pickups=%d rooms=%d" % [mv.total_pickups(), rooms])
		var first_cell: Vector2i = cell
		main.begin_game(lv.id)
		await get_tree().process_frame
		_check("rabbit %s: same place on every start (level seed)" % lv.id, main.maze_view.rabbit_cell == first_cell)
	_check("rabbit: on the minimap from the level start (drawn from maze_view.rabbit_*)", main.hud.minimap_maze_view == null or main.hud.minimap_maze_view.rabbit_alive)

	# ---- pickup: starts a condition, title card, voluntary ----
	main.begin_game("klassik-1")
	await get_tree().process_frame
	_check("rabbit: no condition before the pickup", main.active_condition == null and not main.hud.condition_card.visible)
	var pickups_before: int = main.maze_view.remaining_pickups()
	await _take_rabbit()
	_check("rabbit: pickup starts a condition", main.active_condition != null and not main.maze_view.rabbit_alive)
	_check("rabbit: pickup leaves the required pickups untouched", main.maze_view.remaining_pickups() == pickups_before)
	var c = main.active_condition
	_check("rabbit: title card shows name and bar", main.hud.condition_card.visible and main.hud.condition_name_label.text == c.display_name.to_upper() and main.hud.condition_bar.value > 0.9)
	var want_col: Color = main.hud.COND_GOOD if c.is_good else main.hud.COND_BAD
	_check("rabbit: title card green for good, magenta for bad", main.hud.condition_color == want_col)
	_check("rabbit: duration good 10 s / bad 8 s", is_equal_approx(main.condition_until - main.condition_started_at, 10.0 if c.is_good else 8.0))

	# ---- Kaninchen der Woche: same week + level -> same result; restart never re-rolls ----
	var sig_a := _condition_signature()
	main.begin_game("klassik-1")
	await get_tree().process_frame
	await _take_rabbit()
	_check("week: a restart gives the same rabbit result", _condition_signature() == sig_a, "%s vs %s" % [sig_a, _condition_signature()])
	var seen := {}
	for w in range(1, 21):
		main.rabbit_week_override = Vector2i(2026, w)
		main.begin_game("klassik-1")
		await get_tree().process_frame
		await _take_rabbit()
		seen[_condition_signature()] = true
	_check("week: another week can give another result", seen.size() >= 2, str(seen.keys()))
	main.rabbit_week_override = Vector2i(2026, 40)
	main._end_condition(false)


## ---------------- Conditions (spec 1.2, 2.3, 2.4) ----------------

## Is the player's capsule free of every wall (real physics query)?
func _capsule_free() -> bool:
	var q := PhysicsShapeQueryParameters3D.new()
	var cs: CollisionShape3D = null
	for ch in main.player.get_children():
		if ch is CollisionShape3D:
			cs = ch
	q.shape = cs.shape
	q.transform = cs.global_transform
	q.collision_mask = 2
	return main.player.get_world_3d().direct_space_state.intersect_shape(q, 4).is_empty()


func _run_condition_checks() -> void:
	# ---- a condition ends after its duration (game clock) ----
	main.begin_game("klassik-1")
	await get_tree().process_frame
	main.invuln_until = main.now + 999.0
	main.start_condition(ConditionsScript.get_condition("taschenuhr"))
	for i in 19:
		main._process(0.5)
	_check("duration: a good condition still runs after 9.5 s", main.active_condition != null)
	main._process(0.6)
	_check("duration: ... and is over after 10 s (card off)", main.active_condition == null and not main.hud.condition_card.visible)
	main.start_condition(ConditionsScript.get_condition("stromausfall"))
	for i in 15:
		main._process(0.5)
	_check("duration: a bad condition still runs after 7.5 s", main.active_condition != null)
	main._process(0.6)
	_check("duration: ... and is over after 8 s", main.active_condition == null)

	# ---- Matrix: noclip, look via the Look API, end -> safe open cell ----
	main.begin_game("klassik-1")
	await get_tree().process_frame
	var mv = main.maze_view
	var wall_mmi = mv.normal_wall_mmi
	var children_before: int = mv.get_child_count()
	main.invuln_until = main.now + 999.0
	main.start_condition(ConditionsScript.get_condition("matrix"))
	_check("matrix: noclip on", main.player.collision_mask == 0)
	_check("matrix: look 'matrix' on the same wall MultiMesh (kond_wall)", mv.current_look == "matrix" and mv.normal_wall_mmi == wall_mmi and wall_mmi.material_override == mv.cond_wall_material and int(mv.cond_wall_material.get_shader_parameter("look")) == 1)
	_check("matrix: no second wall set", mv.get_child_count() == children_before)
	main._process(0.4)
	var tr: float = mv.cond_wall_material.get_shader_parameter("transition")
	_check("matrix: transition wave runs over 0.8 s", tr > 0.4 and tr < 0.6, "t=%f" % tr)
	main._process(0.5)
	_check("matrix: transition complete", is_equal_approx(float(mv.cond_wall_material.get_shader_parameter("transition")), 1.0))
	# last 3 s: walls fade in / blink
	var solid_max := 0.0
	var solid_min := 1.0
	var t := 0.0
	while main.active_condition != null and main.condition_until - main.now > 0.9:
		main._process(0.05)
		t += 0.05
		if main.condition_until - main.now < 2.9 and main.condition_until - main.now > 1.0:
			var sv: float = mv.cond_wall_material.get_shader_parameter("matrix_solid")
			solid_max = maxf(solid_max, sv)
			solid_min = minf(solid_min, sv)
	_check("matrix: last 3 s the walls blink back in", solid_max > 0.8 and solid_min < 0.5, "min=%f max=%f" % [solid_min, solid_max])
	# end inside a wall
	var wall_cell := Vector2i(-1, -1)
	for r in range(2, main.maze.rows - 2, 2):
		for cc in range(2, main.maze.cols - 2, 2):
			if main.maze.grid[r][cc] == 1 and wall_cell.x < 0:
				wall_cell = Vector2i(r, cc)
	main.player.global_position = Vector3(wall_cell.y * main.CELL + 0.3, main.player.global_position.y, wall_cell.x * main.CELL)
	main._process(1.0)
	await get_tree().physics_frame
	var pc: Vector2i = main.player.cell()
	_check("matrix end: collision on again", main.player.collision_mask == 2 and main.active_condition == null)
	_check("matrix end: player in an open cell", main.maze.grid[pc.x][pc.y] == 0, "cell=%s" % pc)
	_check("matrix end: capsule completely free", _capsule_free())
	_check("matrix end: back to the base look", mv.current_look == mv.LOOK_BASE and wall_mmi.material_override == mv.wall_material)
	# Code-N3: an open cell, but pushed against its wall neighbor (wall_footprint_scale)
	main.start_condition(ConditionsScript.get_condition("matrix"))
	var edge_spot := Vector3.ZERO
	var found := false
	for r in range(1, main.maze.rows - 1, 2):
		for cc in range(1, main.maze.cols - 1, 2):
			if found or main.maze.grid[r][cc] != 0:
				continue
			if main.maze.grid[r][cc + 1] == 1:
				edge_spot = Vector3(cc * main.CELL + 0.75, main.player.global_position.y, r * main.CELL)
				found = true
	main.player.global_position = edge_spot
	_check("Code-N3 setup: capsule overlaps the neighbor wall", main.capsule_blocked_at(edge_spot))
	main._end_condition(false)
	await get_tree().physics_frame
	_check("Code-N3: rescue moves a capsule that only overlaps a wall edge", _capsule_free() and not main.capsule_blocked_at(main.player.global_position))

	# ---- Fear & Loathing: steering only, never the view ----
	var fl = FearScript.new()
	var kinds := {}
	for i in 60:
		var rng := RandomNumberGenerator.new()
		rng.seed = i * 7919
		fl.roll(rng)
		kinds[fl.manipulation] = true
	_check("F&L: the rabbit RNG draws each of the three manipulations", kinds.size() == 3, str(kinds.keys()))
	var no_move := true
	for kind in FearScript.MANIPULATIONS:
		var f = FearScript.new()
		f.set_manipulation(kind)
		for i in 40:
			if f.modify_input(Vector2.ZERO, 1.0 / 60.0) != Vector2.ZERO:
				no_move = false
		# input, then release: never movement without input
		for i in 20:
			f.modify_input(Vector2(0, 1), 1.0 / 60.0)
		if f.modify_input(Vector2.ZERO, 1.0 / 60.0) != Vector2.ZERO:
			no_move = false
	_check("F&L: no input -> no movement (all manipulations, also right after releasing)", no_move)
	var fs = FearScript.new()
	fs.set_manipulation(FearScript.SWAP)
	_check("F&L swap: A/D and W/S mirrored (E10)", fs.modify_input(Vector2(1, 0), 0.016) == Vector2(-1, 0) and fs.modify_input(Vector2(0, 1), 0.016) == Vector2(0, -1))
	var fd = FearScript.new()
	fd.set_manipulation(FearScript.DRIFT)
	var dv: Vector2 = fd.modify_input(Vector2(0, 1), 0.016)
	_check("F&L drift: sideways pull while walking, never faster", absf(dv.x) > 0.1 and dv.length() <= 1.0001, str(dv))
	var fdl = FearScript.new()
	fdl.set_manipulation(FearScript.DELAY)
	var ticks := int(round(0.15 * Engine.physics_ticks_per_second))
	var early := true
	for i in ticks:
		if fdl.modify_input(Vector2(0, 1), 1.0 / 60.0) != Vector2.ZERO:
			early = false
	_check("F&L delay: 150 ms before the input arrives", early and fdl.modify_input(Vector2(0, 1), 1.0 / 60.0) == Vector2(0, 1) and fdl._ring.size() == ticks)

	main.begin_game("klassik-1")
	await get_tree().process_frame
	main.invuln_until = main.now + 999.0
	var fear = ConditionsScript.get_condition("fear_and_loathing")
	fear.set_manipulation(FearScript.DRIFT)
	main.start_condition(fear)
	main.player.yaw = 0.7
	main.player.rotation.y = 0.7
	main.player.pitch = 0.2
	main.player.camera.rotation.x = 0.2
	var fov_before: float = main.player.camera.fov
	var pos_before: Vector3 = main.player.global_position
	for i in 20:
		await get_tree().physics_frame
	_check("F&L: no movement while standing still", main.player.global_position.distance_to(pos_before) < 0.001)
	Input.action_press("move_forward")
	var flip_max := 0.0
	for i in 40:
		await get_tree().physics_frame
		await get_tree().process_frame
		flip_max = maxf(flip_max, float(main.maze_view.cond_wall_material.get_shader_parameter("flip")))
	_release_all_move_keys()
	_check("F&L: view/camera never touched (yaw, pitch, camera, FOV)", is_equal_approx(main.player.yaw, 0.7) and is_equal_approx(main.player.rotation.y, 0.7) and is_equal_approx(main.player.pitch, 0.2) and is_equal_approx(main.player.camera.rotation.x, 0.2) and is_equal_approx(main.player.camera.fov, fov_before) and main.player.camera.position == Vector3(0, main.player.EYE_H, 0))
	_check("F&L: Kippbild tips while the manipulation acts", flip_max > 0.5, "flip=%f" % flip_max)
	_check("F&L: title card shows the manipulation symbol", main.hud.condition_icon_kind == "fl_drift" and main.hud.condition_sub_label.text != "")
	main._end_condition(false)

	# ---- Taschenuhr halves the ghost speed ----
	main.begin_game("klassik-1")
	await get_tree().process_frame
	main.invuln_until = main.now + 999.0
	var en = main.enemies[0]
	var far_cell: Vector2i = main.maze_view.power_cells[0]
	en.mode = "chase"
	_pin_enemy_at(en, far_cell)
	main._process(0.1)
	var t_normal: float = en.t
	_pin_enemy_at(en, far_cell)
	main.start_condition(ConditionsScript.get_condition("taschenuhr"))
	main._process(0.1)
	var t_slow: float = en.t
	_check("Taschenuhr: ghosts move at half speed", absf(t_slow - t_normal * 0.5) < 0.01 and en.speed_scale == 0.5, "normal=%f slow=%f" % [t_normal, t_slow])
	main._end_condition(false)
	main._process(0.01)
	_check("Taschenuhr: ghost speed back to normal afterwards", en.speed_scale == 1.0)

	# ---- Stromausfall: minimap off and on again, objects keep glowing ----
	main.start_condition(ConditionsScript.get_condition("stromausfall"))
	main._process(0.9)
	_check("Stromausfall: minimap off", main.hud.minimap.visible == false)
	_check("Stromausfall: dense fog (sight ~2 cells)", main.world_env.environment.fog_density > 0.3)
	_check("Stromausfall: pellets, power pellets and ghosts glow through the fog", main.maze_view.pellet_material.disable_fog and main.maze_view.power_material.disable_fog and main.enemies[0].body_material.disable_fog)
	for i in 20:
		main._process(0.5)
	_check("Stromausfall: minimap on again after the end", main.active_condition == null and main.hud.minimap.visible == true)
	_check("Stromausfall: fog and objects back to normal", main.world_env.environment.fog_density < 0.05 and not main.maze_view.pellet_material.disable_fog and not main.enemies[0].body_material.disable_fog)

	# ---- objects keep color/shape; black outline in the condition looks ----
	main.start_condition(ConditionsScript.get_condition("matrix"))
	main._process(0.9)
	_check("looks: black outline on pellets and ghosts, colors unchanged", main.maze_view.pellet_material.next_pass != null and main.enemies[0].body_material.next_pass != null and main.maze_view.pellet_material.albedo_color.is_equal_approx(main.maze_view.city_theme.pellet_color))

	# ---- "Effekte reduzieren": calmer look, same gameplay ----
	main.set_reduce_fx(true)
	_check("reduce fx: stored and both switches in sync", SettingsScript.load_settings().reduce_fx and main.hud.reduce_fx_start.button_pressed and main.hud.reduce_fx_pause.button_pressed)
	_check("reduce fx: reaches the look", is_equal_approx(float(main.maze_view.cond_wall_material.get_shader_parameter("reduce_fx")), 1.0))
	_check("reduce fx: the gameplay effect stays (noclip still on)", main.player.collision_mask == 0)
	_check("reduce fx: Matrix end fades in without blinking", main._matrix_solid(main.active_condition, 2.0) <= main._matrix_solid(main.active_condition, 1.5))
	main.set_reduce_fx(false)
	main._end_condition(false)


## ---------------- Start intro (spec 2.1) ----------------

func _intro_centered() -> String:
	var panel: Control = main.hud.start_intro_panel
	var vis: Rect2 = panel.get_viewport().get_visible_rect()
	var c := panel.get_global_rect().get_center()
	var want := vis.position + vis.size * 0.5
	if c.distance_to(want) > 2.0 or panel.size.x < 50.0:
		return "center %s, want %s (panel size %s)" % [c, want, panel.size]
	return ""


func _run_intro_checks() -> void:
	main.skip_start_intro = false
	main.begin_game("klassik-1")
	await get_tree().process_frame
	await get_tree().process_frame
	_check("intro: shown at the speedrun start", main.hud.is_start_intro_visible() and main.start_hold)
	var texts := _texts_under(main.hud.start_intro_panel)
	_check("intro: 'Follow the white rabbit. But beware'", texts.has("Follow the white rabbit.") and texts.has("But beware"), str(texts))
	_check("intro: own panel with background, not the level-clear banner", main.hud.start_intro_panel is PanelContainer and main.hud.start_intro_panel.get_theme_stylebox("panel").bg_color.a > 0.5 and not main.hud.levelclear_panel.visible)
	var err := _intro_centered()
	_check("intro: centered at 1280x800", err == "", err)
	for res in [Vector2i(1920, 1080), Vector2i(1024, 576)]:
		get_tree().root.size = res
		await get_tree().process_frame
		await get_tree().process_frame
		err = _intro_centered()
		_check("intro: centered at %dx%d" % [res.x, res.y], err == "", err)
	get_tree().root.size = Vector2i(1280, 800)
	await get_tree().process_frame
	# the level-clear banner is centered now too (QA-W2)
	main.hud.show_levelclear(true, "Test")
	await get_tree().process_frame
	var lp: Control = main.hud.levelclear_panel.get_child(0)
	var vr: Rect2 = lp.get_viewport().get_visible_rect()
	_check("level-clear banner: centered with background (QA-W2)", lp.get_global_rect().get_center().distance_to(vr.size * 0.5) < 2.0)
	main.hud.show_levelclear(false)

	var now_before: float = main.now
	Input.action_press("move_forward")
	var pos_before: Vector3 = main.player.global_position
	for i in 10:
		await get_tree().physics_frame
	_check("intro: walking locked while the intro is up", main.player.global_position.distance_to(pos_before) < 0.001)
	_release_all_move_keys()
	main.intro_until_real = main.real_now # let the 2.5 s run out
	for i in 20:
		await get_tree().process_frame
	_check("intro: gone after its time", not main.hud.is_start_intro_visible())
	_check("hold: clock stands at 0 until the first movement input", main.start_hold and main.hud.timer_label.text == "0:00.00", main.hud.timer_label.text)
	_check("hold: the world waits (game clock frozen)", main.now == now_before)
	Input.action_press("move_forward")
	for i in 20:
		await get_tree().process_frame
	_release_all_move_keys()
	_check("hold: the first movement input starts the clock", not main.start_hold and main.real_now - main.level_start_real > 0.0 and main.hud.timer_label.text != "0:00.00")
	_check("hold: the game clock runs again", main.now > now_before)
	# QA 03.10. W1: pausing during the intro must not leave the intro over the pause menu
	main.skip_start_intro = false
	main.begin_game("klassik-1")
	await get_tree().process_frame
	await get_tree().process_frame
	_check("intro: up before the pause test", main.hud.is_start_intro_visible())
	main.toggle_pause()
	await get_tree().process_frame
	_check("pause during intro: intro hidden, pause menu visible", main.paused and main.hud.pause_panel.visible and not main.hud.is_start_intro_visible())
	_check("pause during intro: intro never blocks clicks", main.hud.start_intro.mouse_filter == Control.MOUSE_FILTER_IGNORE and main.hud.start_intro_panel.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	main.toggle_pause()
	await get_tree().process_frame
	_check("pause during intro: after resume the clock still waits for the first step", main.start_hold and not main.hud.is_start_intro_visible())
	Input.action_press("move_forward")
	for i in 20:
		await get_tree().process_frame
	_release_all_move_keys()
	main.level_index += 1
	main.next_level()
	_check("next_level: no intro between levels", not main.start_hold and not main.hud.is_start_intro_visible())
	main.skip_start_intro = true


## ---------------- Boards, Chaos mode, Bestenliste (spec 2.5, Etappe 3) ----------------

## Eats every pellet and power pellet of the current level within a few
## frames, pretending 5 s passed (well under every target time).
func _clear_level_fast() -> void:
	main.invuln_until = main.now + 999.0
	main.level_start_real = main.real_now - 5.0
	for cell in main.maze_view.pellet_cells:
		main.player.global_position = Vector3(cell.y * main.CELL, main.player.global_position.y, cell.x * main.CELL)
		await get_tree().process_frame
	for i in main.maze_view.power_cells.size():
		var n = main.maze_view.power_nodes[i]
		main.player.global_position = Vector3(n.position.x, main.player.global_position.y, n.position.z)
		await get_tree().process_frame


func _run_board_checks() -> void:
	Speedrun.reset_all()
	Leaderboard.reset_all()
	main.hud.show_only(main.hud.start_panel)
	_check("chaos: switch on the start screen, off by default", main.hud.chaos_start != null and main.hud.chaos_start.is_visible_in_tree() and not main.hud.chaos_start.button_pressed and not main.chaos_mode)
	main.hud.chaos_start.button_pressed = true # through the real toggle signal
	_check("chaos: the switch turns Chaos mode on and is stored", main.chaos_mode and SettingsScript.load_settings().chaos)
	_check("chaos: storing it keeps the other setting", SettingsScript.load_settings().reduce_fx == main.reduce_fx)

	main.begin_game("klassik-1")
	await get_tree().process_frame
	_check("chaos: the level counts on the chaos board", main.board_id() == "chaos" and main.board_week_label() == "")
	_check("chaos: HUD badge CHAOS", main.hud.board_chip.visible and main.hud.board_label.text == "CHAOS", main.hud.board_label.text)
	var sigs := {}
	for i in 16:
		main.begin_game("klassik-1")
		await get_tree().process_frame
		await _take_rabbit()
		sigs[_condition_signature()] = true
	_check("chaos: real randomness — a restart can give another rabbit result", sigs.size() >= 2, str(sigs.keys()))
	main._end_condition(false)
	main.begin_game("klassik-1")
	await get_tree().process_frame
	await _clear_level_fast()
	_check("chaos: the time lands on the chaos board only", Leaderboard.get_top("klassik-1", "chaos").size() == 1 and Leaderboard.get_top("klassik-1", WOCHE).size() == 0 and Leaderboard.get_top("klassik-1", "chat").size() == 0)
	_check("chaos: no week stored, no target-time badge", Speedrun.best_entry("klassik-1", "chaos").get("week", "x") == "" and not Speedrun.is_bonus_unlocked())
	await get_tree().create_timer(2.0).timeout

	# chat beats chaos: a chat-touched level never lands on woche/chaos
	main.begin_game("klassik-2")
	await get_tree().process_frame
	Twitch.chat_command.emit("viewer", "power", "")
	await get_tree().process_frame
	_check("chaos + chat: the level moves to the chat board", main.board_id() == "chat" and main.hud.board_label.text == "CHAT")
	await _clear_level_fast()
	_check("chaos + chat: time on the chat board, not on chaos", Leaderboard.get_top("klassik-2", "chat").size() == 1 and Leaderboard.get_top("klassik-2", "chaos").size() == 0)
	await get_tree().create_timer(2.0).timeout
	main.set_chaos_mode(false)
	_check("chaos: switching off is stored too", not SettingsScript.load_settings().chaos and not main.hud.chaos_start.button_pressed)

	# weekly board: badge also with a Matrix rabbit (studio head decision)
	main.begin_game("klassik-1")
	await get_tree().process_frame
	main.start_condition(ConditionsScript.get_condition("matrix"))
	await _clear_level_fast()
	_check("badge: a weekly solo run with Matrix earns the target-time badge", Speedrun.is_bonus_unlocked() and Speedrun.best_entry("klassik-1", WOCHE).get("week", "") == "2026-W40")
	await get_tree().create_timer(2.0).timeout

	# Bestenliste on the start screen
	main.end_game()
	main.hud.show_only(main.hud.start_panel)
	main.hud.show_leaderboard(WOCHE, "klassik-1")
	await get_tree().process_frame
	var lines: Array = main.hud.leaderboard_lines()
	_check("bestenliste: panel open, weekly board of klassik-1", main.hud.leaderboard_panel.visible and not main.hud.start_panel.visible and main.hud.lb_level_label.text == "Klassik I")
	_check("bestenliste: every weekly time names its calendar week", lines.size() == 1 and lines[0].find("KW 40") != -1, str(lines))
	_check("bestenliste: header names the all-time best with its week and this week's best", main.hud.lb_info_label.text.find("Allzeit-Bestzeit") != -1 and main.hud.lb_info_label.text.find("KW 40") != -1 and main.hud.lb_info_label.text.find("Diese Woche") != -1, main.hud.lb_info_label.text)
	main.hud._set_lb_board("chaos")
	var chaos_lines: Array = main.hud.leaderboard_lines()
	_check("bestenliste: chaos tab shows the chaos board, without week", chaos_lines.size() == 1 and chaos_lines[0].find("KW") == -1 and main.hud.lb_tabs["chaos"].button_pressed, str(chaos_lines))
	main.hud._set_lb_board("chat")
	main.hud._step_lb_level(1)
	_check("bestenliste: level switcher and chat tab", main.hud.lb_level_label.text == "Klassik II" and main.hud.leaderboard_lines().size() == 1)
	main.hud.show_only(main.hud.start_panel)
	_check("bestenliste: back to the start screen", main.hud.start_panel.visible and not main.hud.leaderboard_panel.visible)


## ---------------- Twitch chat: rabbit vote and cooldown (spec 2.6, Code-W8) ----------------

func _votes(good: int, bad: int) -> void:
	for i in good:
		Twitch.chat_command.emit("fan%d" % i, "gut", "")
	for i in bad:
		Twitch.chat_command.emit("troll%d" % i, "schlecht", "")


func _run_chat_vote_checks() -> void:
	Speedrun.reset_all()
	Leaderboard.reset_all()
	main.chat_vote.clear()
	Twitch.enabled = true # chat mode without a real connection (no network here)
	Twitch._connected = true # N5: the chip needs a connected chat; pretend it is

	main.begin_game("klassik-1")
	await get_tree().process_frame
	main._update_chat_hud(true)
	_check("chat bar: shown in chat mode; unshifted it names the rabbit's source", main.hud.chat_chip.visible and main.hud.chat_share_label.text.begins_with("Kaninchen: Woche"), main.hud.chat_share_label.text)
	_votes(7, 3)
	_check("chat bar: 7 gut / 3 schlecht -> 'Kaninchen: 70 % gut' (p = 0.6 + 0.3 d - 0.1 d^2)", main.hud.chat_share_label.text == "Kaninchen: 70 % gut", main.hud.chat_share_label.text)
	_check("chat: votes alone do not touch the board", main.board_id() == WOCHE)
	await _take_rabbit()
	var c = main.active_condition
	_check("chat shift: the rabbit pickup moves the level to the chat board", main.board_id() == "chat" and main.level_chat_assisted)
	_check("chat shift: title card 'Chat 70 % → <KONDITION>'", c != null and main.hud.condition_chat_label.visible and main.hud.condition_chat_label.text == "Chat 70 %% → %s" % c.display_name.to_upper(), main.hud.condition_chat_label.text)
	await _clear_level_fast()
	_check("chat run: lands on the chat board, never on woche/chaos", Leaderboard.get_top("klassik-1", "chat").size() == 1 and Leaderboard.get_top("klassik-1", WOCHE).size() == 0 and Leaderboard.get_top("klassik-1", "chaos").size() == 0 and Speedrun.best_for("klassik-1", WOCHE) == -1.0)
	await get_tree().create_timer(2.0).timeout

	main.set_chaos_mode(true)
	main.begin_game("klassik-2")
	await get_tree().process_frame
	await _take_rabbit()
	_check("chat shift in Chaos mode: chat board, not chaos", main.board_id() == "chat")
	await _clear_level_fast()
	_check("chat shift in Chaos mode: time on chat, nothing on chaos/woche", Leaderboard.get_top("klassik-2", "chat").size() == 1 and Leaderboard.get_top("klassik-2", "chaos").size() == 0 and Leaderboard.get_top("klassik-2", WOCHE).size() == 0)
	await get_tree().create_timer(2.0).timeout
	main.set_chaos_mode(false)

	# many shifted rabbits: the chat's weighting with real randomness
	main.chat_vote.clear()
	_votes(10, 0) # 80 % gut
	var good_n := 0
	var seen := {}
	for i in 30:
		main.begin_game("klassik-3")
		await get_tree().process_frame
		await _take_rabbit()
		if main.active_condition.is_good:
			good_n += 1
		seen[_condition_signature()] = true
	_check("chat shift: drawn with real randomness (several results)", seen.size() >= 2, str(seen.keys()))
	_check("chat shift: 80 % gut weighting shows (>= 15 of 30 good)", good_n >= 15, "good=%d" % good_n)
	main._end_condition(false)

	# not shifted: under 3 voters, or a tie -> Kaninchen der Woche, weekly board
	Twitch.enabled = false
	main.begin_game("klassik-1")
	await get_tree().process_frame
	await _take_rabbit()
	var week_sig := _condition_signature()
	Twitch.enabled = true
	main.chat_vote.clear()
	_votes(2, 0)
	main.begin_game("klassik-1")
	await get_tree().process_frame
	await _take_rabbit()
	_check("2 voters: not shifted -> week result, weekly board, no chat line", _condition_signature() == week_sig and main.board_id() == WOCHE and not main.hud.condition_chat_label.visible)
	main.chat_vote.clear()
	_votes(2, 2)
	main.begin_game("klassik-1")
	await get_tree().process_frame
	await _take_rabbit()
	_check("tie 2:2 (60 %): not shifted -> week result, weekly board", _condition_signature() == week_sig and main.board_id() == WOCHE)
	main._end_condition(false)

	# Code-W8: global cooldown for !power / !fruit
	main.begin_game("klassik-1")
	await get_tree().process_frame
	main.frightened_until = 0.0
	Twitch.chat_command.emit("v0", "power", "")
	var first_ok: bool = main.frightened_until > main.now
	main.frightened_until = 0.0
	for i in 19:
		Twitch.chat_command.emit("v%d" % (i + 1), "power", "")
	_check("cooldown: 20x !power at once -> one effect", first_ok and main.frightened_until == 0.0)
	main.now += main.CHAT_COMMAND_COOLDOWN_S - 0.5
	Twitch.chat_command.emit("v1", "power", "")
	_check("cooldown: still blocked shortly before 20 s", main.frightened_until == 0.0)
	main.now += 0.6
	Twitch.chat_command.emit("v1", "power", "")
	_check("cooldown: !power works again after 20 s", main.frightened_until > main.now)
	main.fruit_spawned = false
	Twitch.chat_command.emit("v2", "fruit", "")
	var fruit_first: bool = main.fruit_spawned
	main.fruit_spawned = false
	Twitch.chat_command.emit("v3", "fruit", "")
	_check("cooldown: !fruit has its own 20 s cooldown", fruit_first and not main.fruit_spawned)
	main.begin_game("klassik-1")
	await get_tree().process_frame
	main.frightened_until = 0.0
	Twitch.chat_command.emit("v4", "power", "")
	_check("cooldown: a new run starts without cooldown", main.frightened_until > main.now)

	main.begin_manhattan_game()
	await get_tree().process_frame
	main._update_chat_hud(true)
	_check("chat bar: hidden in Manhattan", not main.hud.chat_chip.visible)
	Twitch.enabled = false
	Twitch._connected = false
	main.chat_vote.clear()
	main.end_game()


## ---------------- Review fixes 03.10. (Code, GD, UX) ----------------

func _texts_of(node: Node) -> Array:
	return _texts_under(node)


func _start_pos() -> Vector3:
	return Vector3(main.start_cell.y * main.CELL, main.player.EYE_H, main.start_cell.x * main.CELL)


func _esc() -> void:
	var e := InputEventKey.new()
	e.keycode = KEY_ESCAPE
	e.pressed = true
	main._unhandled_input(e)


func _wall_cell_near_start() -> Vector2i:
	for r in range(2, main.maze.rows - 2, 2):
		for cc in range(2, main.maze.cols - 2, 2):
			if main.maze.grid[r][cc] == 1:
				return Vector2i(r, cc)
	return Vector2i(-1, -1)


func _run_review_fix_checks() -> void:
	Speedrun.reset_all()
	Leaderboard.reset_all()
	main.set_chaos_mode(false)

	# ---- W1: death ends the running condition (all four) + Code-W7 ----
	for id in ConditionsScript.ids():
		main.begin_game("klassik-1")
		await get_tree().process_frame
		main.invuln_until = 0.0
		main.start_condition(ConditionsScript.get_condition(id))
		main._process(0.5)
		if id == "matrix":
			var wc := _wall_cell_near_start()
			main.player.global_position = Vector3(wc.y * main.CELL, main.player.global_position.y, wc.x * main.CELL)
		var lives_before: int = main.lives
		main.lose_life()
		await get_tree().physics_frame
		var pc: Vector2i = main.player.cell()
		_check("W1 %s: death ends the condition (main + player)" % id, main.active_condition == null and main.player.active_condition == null and not main.hud.condition_card.visible and main.lives == lives_before - 1)
		_check("W1 %s: collision on, player in an open cell, capsule free" % id, main.player.collision_mask == 2 and main.maze.grid[pc.x][pc.y] == 0 and _capsule_free())
		_check("W1 %s: base look, normal ghosts, minimap, fog" % id, main.maze_view.current_look == main.maze_view.LOOK_BASE and main.enemies[0].speed_scale == 1.0 and main.hud.minimap.visible and main.world_env.environment.fog_density < 0.05)
		_check("Code-W7 %s: respawn looks down the longest corridor" % id, is_equal_approx(main.player.yaw, main._facing_yaw_for_start(main.start_cell)) and main.player.global_position.distance_to(_start_pos()) < 0.001)

	# ---- double death in one frame on the last life: end_game exactly once ----
	main.begin_game("klassik-1")
	await get_tree().process_frame
	main.lives = 1
	main.invuln_until = -1.0
	main.frightened_until = 0.0
	for i in 2:
		var en = main.enemies[i]
		en.mode = "chase"
		en.release_at = 0.0
		_pin_enemy_at(en, main.start_cell)
		en.position = Vector3(main.start_cell.y * main.CELL, en.position.y, main.start_cell.x * main.CELL)
	main.player.global_position = _start_pos()
	var ended_before: int = main.games_ended
	var emitted := [0]
	var cb := func(): emitted[0] += 1
	main.game_over.connect(cb)
	main._process(1.0 / 60.0)
	main.game_over.disconnect(cb)
	_check("double death: two ghosts in one frame on the last life -> one game over", main.games_ended == ended_before + 1 and emitted[0] == 1 and main.lives == 0 and main.hud.gameover_panel.visible, "ended=%d emitted=%d lives=%d" % [main.games_ended - ended_before, emitted[0], main.lives])
	main.lose_life()
	_check("double death: a late lose_life after the game over changes nothing", main.lives == 0 and main.games_ended == ended_before + 1)

	# ---- Code-W8 part 1: no high score after chat help ----
	main.high_score = 100
	main._save_highscore(100)
	main.begin_game("klassik-1")
	await get_tree().process_frame
	Twitch.chat_command.emit("helper", "power", "")
	main.score = 5000
	main.end_game()
	_check("Code-W8: a chat-helped run never becomes the high score", main.high_score == 100 and main._load_highscore() == 100 and main.hud.gameover_note_label.visible)
	main.begin_game("klassik-1")
	await get_tree().process_frame
	main.score = 5000
	main.end_game()
	_check("Code-W8: a run without chat help still sets it", main.high_score == 5000 and main._load_highscore() == 5000 and not main.hud.gameover_note_label.visible)
	# W4 for the high score: an unreadable file is kept before it is overwritten
	var hs_path: String = SettingsScript.SavePathsScript.path(main.HIGHSCORE_FILE)
	var hf := FileAccess.open(hs_path, FileAccess.WRITE)
	hf.store_string("viel")
	hf.close()
	_check("W4: an unreadable high score loads as 0 ...", main._load_highscore() == 0)
	var hs_backups: Array = SettingsScript.SavePathsScript.corrupt_backups(hs_path)
	_check("W4: ... and is kept as .corrupt-<time>", hs_backups.size() == 1)
	for b in hs_backups:
		DirAccess.remove_absolute(b)
	main._save_highscore(main.high_score)

	# ---- N1: Matrix ending inside the ghost house -> out of the house ----
	main.begin_game("klassik-1")
	await get_tree().process_frame
	main.invuln_until = main.now + 999.0
	main.start_condition(ConditionsScript.get_condition("matrix"))
	var hc := Vector2i(main.maze.house.r0 + 1, main.maze.house.c0 + 1)
	main.player.global_position = Vector3(hc.y * main.CELL, main.player.global_position.y, hc.x * main.CELL)
	_check("N1 setup: player inside the ghost house", main.in_ghost_house(main.player.global_position))
	main._end_condition(false)
	await get_tree().physics_frame
	_check("N1: Matrix end puts the player out of the ghost house, capsule free", not main.in_ghost_house(main.player.global_position) and _capsule_free())

	# ---- N2: the board is frozen at the level start ----
	main.begin_game("klassik-1")
	await get_tree().process_frame
	main.set_chaos_mode(true)
	_check("N2: switching Chaos on mid-level keeps the level on its board", main.board_id() == WOCHE)
	main.begin_game("klassik-1")
	await get_tree().process_frame
	_check("N2: ... the next level start takes the new board", main.board_id() == "chaos")
	main.set_chaos_mode(false)

	# ---- N4: unknown level id ----
	main.begin_game("gibt-es-nicht")
	await get_tree().process_frame
	_check("N4: begin_game with an unknown id starts a real pool level", LevelsScript.index_of(main.level_id) >= 0 and main.running)

	# ---- N5: chat chip only with a connected chat ----
	Twitch.enabled = true
	Twitch._connected = false
	main._update_chat_hud(true)
	_check("N5: Twitch on but not connected -> no chat chip", not main.hud.chat_chip.visible)
	Twitch._connected = true
	main._update_chat_hud(true)
	_check("N5: connected -> chip, 'Kaninchen: Woche' without a shift", main.hud.chat_chip.visible and main.hud.chat_share_label.text.begins_with("Kaninchen: Woche"), main.hud.chat_share_label.text)
	main.set_chaos_mode(true)
	main.begin_game("klassik-1")
	await get_tree().process_frame
	main._update_chat_hud(true)
	_check("GD: in Chaos mode the unshifted chip says 'Kaninchen: Chaos'", main.hud.chat_share_label.text.begins_with("Kaninchen: Chaos"), main.hud.chat_share_label.text)
	main.set_chaos_mode(false)
	Twitch._connected = false
	Twitch.enabled = false
	main.chat_vote.clear()

	# ---- W2: no work per frame while a condition runs (resource counters) ----
	for id in ["matrix", "taschenuhr", "stromausfall", "fear_and_loathing"]:
		main.begin_game("klassik-1")
		await get_tree().process_frame
		main.invuln_until = main.now + 999.0
		var wc2 = ConditionsScript.get_condition(id)
		if "play_sound" in wc2:
			wc2.play_sound = false # the 1-Hz clock tick starts an audio playback object; this check is about per-frame work
		main.start_condition(wc2)
		for i in 6:
			main._process(0.2) # through the 0.8-s transition
		var blends: int = main.env_blend_count
		var params: int = main.look_param_count
		var objs := Performance.get_monitor(Performance.OBJECT_COUNT)
		for i in 60:
			main._process(1.0 / 60.0)
		var objs_after := Performance.get_monitor(Performance.OBJECT_COUNT)
		_check("W2 %s: no environment blend and no uniform write per frame between the transitions" % id, main.env_blend_count == blends and main.look_param_count == params, "blends +%d, params +%d" % [main.env_blend_count - blends, main.look_param_count - params])
		_check("W2 %s: no object created per frame" % id, objs_after <= objs, "objects %d -> %d" % [objs, objs_after])
		main._end_condition(false)
	_check("W2: _blend_environment no longer builds a theme (cached base)", not (main.get_script().source_code.contains("var base = CityThemesScript.get_theme(\"normal\")")))

	# ---- W3: walking starts together with the clock ----
	main.skip_start_intro = false
	main.begin_game("klassik-1")
	await get_tree().process_frame
	main.intro_until_real = main.real_now
	for i in 4:
		await get_tree().process_frame
	_check("UX-W7: after the intro the hint 'Die Uhr startet mit deinem ersten Schritt' stays", not main.hud.is_start_intro_visible() and main.hud.is_clock_hint_visible() and main.hud.clock_hint_label.text == "Die Uhr startet mit deinem ersten Schritt")
	_check("W3: legs still locked while the clock waits", main.player.movement_locked and main.start_hold)
	Input.action_press("move_forward")
	var guard := 0
	while main.start_hold and guard < 60:
		await get_tree().process_frame
		guard += 1
	_check("W3: at the clock start the player stands exactly on the start position", not main.start_hold and main.hold_release_position.distance_to(_start_pos()) < 0.0001, "%s vs %s" % [main.hold_release_position, _start_pos()])
	for i in 10:
		await get_tree().physics_frame
	_release_all_move_keys()
	_check("W3: ... and walks from there once the clock runs", main.player.global_position.distance_to(_start_pos()) > 0.05 and not main.hud.is_clock_hint_visible())

	# ---- UX-W7: from the second start of a session any key skips the intro ----
	main.intros_shown = 0
	main.begin_game("klassik-1")
	await get_tree().process_frame
	_check("UX-W7: the first intro of a session is not skippable", not main.intro_skippable() and not main.hud.start_intro_skip_label.visible)
	var key := InputEventKey.new()
	key.keycode = KEY_SPACE
	key.pressed = true
	main._unhandled_input(key)
	await get_tree().process_frame
	_check("UX-W7: ... a key does not skip it", main.hud.is_start_intro_visible())
	main.begin_game("klassik-1") # NEUSTART
	await get_tree().process_frame
	_check("UX-W7: second start: skippable, with a hint", main.intro_skippable() and main.hud.start_intro_skip_label.visible)
	main._unhandled_input(key)
	await get_tree().process_frame
	await get_tree().process_frame
	_check("UX-W7: any key skips it; the clock still waits for the first step", not main.hud.is_start_intro_visible() and main.start_hold and main.hud.is_clock_hint_visible())
	main.skip_start_intro = true

	# ---- GD: the condition is stored with every leaderboard entry ----
	Leaderboard.reset_all()
	main.begin_game("klassik-1")
	await get_tree().process_frame
	main.forced_rabbit_condition = "matrix"
	await _take_rabbit()
	main.forced_rabbit_condition = ""
	await _clear_level_fast()
	await get_tree().create_timer(2.0).timeout
	main.begin_game("klassik-1")
	await get_tree().process_frame
	await _clear_level_fast()
	await get_tree().create_timer(2.0).timeout
	var conds := {}
	for e in Leaderboard.get_top("klassik-1", WOCHE):
		conds[e.cond] = true
	_check("GD: leaderboard entries carry the condition taken ('matrix') or '' without rabbit", conds.has("matrix") and conds.has(""), str(Leaderboard.get_top("klassik-1", WOCHE)))

	# ---- UX-W6: Bestenliste ----
	main.go_to_main_menu()
	main.hud.current_week = Vector2i(2026, 40)
	Leaderboard.date_override = "2026-09-20" # an older week (KW 38)
	Leaderboard.submit_time("klassik-1", WOCHE, 99.0, "Player", "solo", "2026-W38", "stromausfall")
	Leaderboard.date_override = ""
	main.hud.show_leaderboard(WOCHE, "klassik-1")
	main.hud._set_lb_range("all")
	await get_tree().process_frame
	var all_lines: Array = main.hud.leaderboard_lines()
	var h_all: float = main.hud.leaderboard_panel.size.y
	_check("UX-W6: Allzeit shows every entry with condition tag and date column", all_lines.size() == 3 and all_lines[2].find("STROM") != -1 and all_lines[2].find("KW 38") != -1 and all_lines[2].find("20.09.") != -1, str(all_lines))
	_check("UX-W6: tags MTX and OHNE for the condition / no rabbit", "\n".join(all_lines).find("MTX") != -1 and "\n".join(all_lines).find("OHNE") != -1, str(all_lines))
	_check("UX-W6: no player name column any more", "\n".join(all_lines).find("Player") == -1)
	main.hud._set_lb_range("week")
	await get_tree().process_frame
	var week_lines: Array = main.hud.leaderboard_lines()
	_check("UX-W6: 'Diese Woche' filters to the current week", week_lines.size() == 2 and "\n".join(week_lines).find("STROM") == -1, str(week_lines))
	_check("UX-W6: the active range tab is pressed, in the accent color with an underline", main.hud.lb_range_tabs["week"].button_pressed and not main.hud.lb_range_tabs["all"].button_pressed and main.hud.lb_range_tabs["week"].get_theme_stylebox("pressed").border_width_bottom == 3)
	main.hud._set_lb_board("chat")
	await get_tree().process_frame
	_check("UX-W6: fixed height — an empty board is as tall as a full one", is_equal_approx(main.hud.leaderboard_panel.size.y, h_all) and main.hud.lb_rows_box.custom_minimum_size.y >= main.hud.LB_ROW_H * 10, "%f vs %f" % [main.hud.leaderboard_panel.size.y, h_all])
	main.hud._set_lb_board(WOCHE)
	main.hud._set_lb_range("all")
	_esc()
	_check("UX-K2: Esc closes the Bestenliste (back to the start screen)", main.hud.start_panel.visible and not main.hud.leaderboard_panel.visible)

	# ---- UX-K2: menus ----
	var start_texts := _texts_of(main.hud.start_panel)
	_check("UX-K2: start screen has BEENDEN", start_texts.has("BEENDEN"))
	main.begin_game("klassik-1")
	await get_tree().process_frame
	main.toggle_pause()
	var pause_texts := _texts_of(main.hud.pause_panel)
	_check("UX-K2: pause offers WEITER / NEUSTART / HAUPTMENÜ", pause_texts.has("WEITER") and pause_texts.has("NEUSTART") and pause_texts.has("HAUPTMENÜ"))
	main.hud.menu_btn.pressed.emit()
	_check("UX-K2: HAUPTMENÜ in a speedrun asks first", main.hud.is_menu_confirm_open() and main.running)
	_esc()
	_check("UX-K2: Esc cancels the question, the pause stays", not main.hud.is_menu_confirm_open() and main.paused and main.hud.pause_panel.visible)
	main.hud.menu_btn.pressed.emit()
	main.hud.menu_pressed.emit() # "JA, ZUM MENÜ"
	await get_tree().process_frame
	_check("UX-K2: confirmed -> start screen, run over, no game HUD", main.hud.start_panel.visible and not main.running and not main.paused and not main.hud.is_game_hud_visible())
	main.begin_game("klassik-1")
	await get_tree().process_frame
	_check("UX-W5: the game HUD is visible while a game runs", main.hud.is_game_hud_visible())
	main.end_game()
	var go_texts := _texts_of(main.hud.gameover_panel)
	_check("UX-K2: game over offers NOCHMAL / HAUPTMENÜ / BESTENLISTE", go_texts.has("NOCHMAL") and go_texts.has("HAUPTMENÜ") and go_texts.has("BESTENLISTE"))
	_check("UX-W5: no game HUD over the game over", not main.hud.is_game_hud_visible())
	main.hud.show_leaderboard("", "", main.hud.gameover_panel)
	_esc()
	_check("UX-K2: Bestenliste from the game over returns there on Esc", main.hud.gameover_panel.visible and not main.hud.leaderboard_panel.visible)
	main.go_to_main_menu()

	# ---- UX-K1 / W5: comfort block and start-screen order ----
	var box: VBoxContainer = main.hud._panel_box(main.hud.start_panel)
	_check("UX-K1: the comfort block sits right under the title", box.get_child(1) == main.hud.comfort_start_block and _texts_of(main.hud.comfort_start_block).has("KOMFORT"))
	var speedrun_idx := -1
	for i in box.get_child_count():
		var ch = box.get_child(i)
		if ch is Button and ch.text == "SPEEDRUN":
			speedrun_idx = i
		elif ch is HBoxContainer: # QA N6 (Versus): SPEEDRUN and VERSUS share a row
			for b in ch.get_children():
				if b is Button and b.text == "SPEEDRUN":
					speedrun_idx = i
	_check("UX-W5: options (Chaos, comfort) above the SPEEDRUN button", main.hud.chaos_start.get_index() < speedrun_idx and main.hud.comfort_start_block.get_index() < speedrun_idx)
	var small := []
	for l in _labels_under(main.hud.start_panel):
		if l.autowrap_mode != TextServer.AUTOWRAP_OFF and l.get_theme_font_size("font_size") < 14:
			small.append(l.text.left(20))
	_check("UX-W5: explanation texts at least 14 px", small.is_empty(), str(small))
	get_tree().root.size = Vector2i(1152, 720)
	await get_tree().process_frame
	await get_tree().process_frame
	var scroll: ScrollContainer = main.hud.start_panel.get_child(0)
	var visible_bottom := scroll.get_global_rect().end.y
	var block_bottom: float = main.hud.comfort_start_block.get_global_rect().end.y
	_check("UX-K1: comfort block fully visible without scrolling at 1152x720", scroll.scroll_vertical == 0 and block_bottom <= visible_bottom, "block bottom %f, visible %f" % [block_bottom, visible_bottom])
	get_tree().root.size = Vector2i(1280, 800)
	await get_tree().process_frame
	main.hud.fov_sliders[0].value = 90.0
	_check("UX-K1: FOV slider sets the camera, is stored and synced", is_equal_approx(main.player.camera.fov, 90.0) and is_equal_approx(SettingsScript.load_settings().fov, 90.0) and is_equal_approx(main.hud.fov_sliders[1].value, 90.0))
	main.hud.sens_sliders[1].value = 1.5
	_check("UX-K1: mouse sensitivity slider (pause) works and is stored", is_equal_approx(main.player.mouse_sensitivity_scale, 1.5) and is_equal_approx(SettingsScript.load_settings().mouse_sens, 1.5) and is_equal_approx(main.hud.sens_sliders[0].value, 1.5))
	_check("UX-K1: FOV range 60-100, default 72", main.hud.fov_sliders[0].min_value == 60.0 and main.hud.fov_sliders[0].max_value == 100.0 and SettingsScript.FOV_DEFAULT == 72.0)
	main.set_fov(72.0)
	main.set_mouse_sens(1.0)
	_check("UX-K1: the pause carries the comfort block too", main.hud.comfort_pause_block != null and main.hud.comfort_pause_block.get_parent() == main.hud.pause_panel.get_child(0))

	# ---- UX-K1: Kippbild with "Effekte reduzieren": no tipping, thin frame ----
	main.set_reduce_fx(true)
	main.begin_game("klassik-1")
	await get_tree().process_frame
	main.invuln_until = main.now + 999.0
	var fear = ConditionsScript.get_condition("fear_and_loathing")
	fear.set_manipulation(FearScript.SWAP)
	main.start_condition(fear)
	Input.action_press("move_right")
	var max_shader_flip := 0.0
	var max_frame := 0.0
	for i in 40:
		await get_tree().physics_frame
		await get_tree().process_frame
		max_shader_flip = maxf(max_shader_flip, float(main.maze_view.cond_wall_material.get_shader_parameter("flip")))
		max_frame = maxf(max_frame, main.hud.flip_frame_alpha)
	_release_all_move_keys()
	_check("UX-K1: reduced Kippbild — the world does not tip", max_shader_flip == 0.0 and fear.look_flip() > 0.5, "shader flip %f" % max_shader_flip)
	_check("UX-K1: reduced Kippbild — a thin frame (~6 px) shows it instead", max_frame > 0.5 and main.hud.FLIP_FRAME_PX == 6.0 and main.hud.flip_frame.visible)
	main._end_condition(false)
	_check("UX-K1: the frame goes with the condition", not main.hud.flip_frame.visible)
	main.set_reduce_fx(false)
	var kw: String = (load("res://shaders/kond_wall.gdshader") as Shader).code
	_check("UX-K1: flow direction cross-fades instead of step()", kw.find("step(0.5, flip)") == -1 and kw.find("mix(stripe_dn, stripe_up, vflip)") != -1)
	_check("UX-W4: reduced Matrix density max 0.8, near 0.3, walls stay permeable", kw.find("uniform float mx_reduce_near = 0.3;") != -1 and kw.find("uniform float mx_reduce_max = 0.8;") != -1 and kw.find("max(reduce_fx, matrix_solid)") == -1)
	_check("N3: transition glyphs only while a transition runs", kw.find("if (transition > 0.001 && transition < 0.999 && look != 0)") != -1)

	# ---- UX-W1: title card ----
	main.begin_game("klassik-1")
	await get_tree().process_frame
	var fl2 = ConditionsScript.get_condition("fear_and_loathing")
	fl2.set_manipulation(FearScript.DELAY)
	main.start_condition(fl2, "Chat 46 % → FEAR & LOATHING")
	var hud = main.hud
	_check("UX-W1: second line 15 px white, chat line 12 px", hud.condition_sub_label.get_theme_font_size("font_size") == 15 and hud.condition_sub_label.get_theme_color("font_color") == Color(1, 1, 1) and hud.condition_chat_label.get_theme_font_size("font_size") == 12)
	_check("UX-W1: right column 'SCHLECHT ▼' and '8 s'", hud.condition_kind_label.text == "SCHLECHT ▼" and hud.condition_secs_label.text == "8 s", "%s / %s" % [hud.condition_kind_label.text, hud.condition_secs_label.text])
	hud.update_condition_card(6.2, 8.0)
	_check("UX-W1: seconds count down ('7 s'), no pulse before the last 3 s", hud.condition_secs_label.text == "7 s" and is_equal_approx(hud.condition_bar.modulate.a, 1.0))
	hud.update_condition_card(2.5, 8.0)
	var a_half: float = hud.condition_bar.modulate.a
	hud.update_condition_card(2.0, 8.0)
	var a_full: float = hud.condition_bar.modulate.a
	_check("UX-W1: last 3 s the bar pulses at 1 Hz", a_half < 0.5 and a_full > 0.95 and hud.condition_secs_label.text == "2 s", "%f / %f" % [a_half, a_full])
	main._end_condition(false)
	var good_c = ConditionsScript.get_condition("taschenuhr")
	main.start_condition(good_c)
	_check("UX-W1: good conditions say 'GUT ▲'", hud.condition_kind_label.text == "GUT ▲")
	main._end_condition(false)

	# ---- UX-W3: the rabbit reads as a rabbit ----
	var mv = main.maze_view
	var fig: Node3D = mv.rabbit_figure
	var vox: Dictionary = load("res://scripts/pixel_rabbit_mesh.gd").voxels()
	var top_y := 0.0
	for p in vox.body:
		top_y = maxf(top_y, p.y)
	_check("UX-W3: 3D figure with body and eyes, ears reach ~1 m", fig != null and fig.has_node("Body") and fig.has_node("Eyes") and top_y > 0.9 and vox.eyes.size() >= 2)
	var spot = mv.rabbit_node.get_node_or_null("LightCone")
	_check("UX-W3: a weak light cone on the floor (spot from above + glow disk)", spot is SpotLight3D and spot.global_transform.basis.z.y > 0.99 and mv.rabbit_node.has_node("FloorGlow"))
	_check("UX-W3: floats above the floor, turns below 0.5 Hz", fig.position.y > 0.1 and mv.RABBIT_TURN_RAD_S / TAU < 0.5 and mv.RABBIT_BOB_HZ < 0.5)
	var bm: StandardMaterial3D = mv.rabbit_material
	_check("UX-W3: rabbit white #F2F2ED", bm != null and bm.albedo_color.is_equal_approx(Color("f2f2ed")))
	main.end_game()
	main.go_to_main_menu()


func _labels_under(node: Node) -> Array:
	var out := []
	for ch in node.get_children():
		if ch is Label:
			out.append(ch)
		out.append_array(_labels_under(ch))
	return out
