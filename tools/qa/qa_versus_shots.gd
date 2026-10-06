# QA-Screenshots des Versus-Modus (E17, docs/design/multiplayer.md).
#
# Ein Prozess: das echte Spiel hostet, eine zweite VersusSession im selben
# Prozess spielt den Gegner (nur Protokoll, kein zweites Labyrinth) und
# meldet gestellten Fortschritt. Aufruf aus dem Repo-Wurzelverzeichnis:
#   cp tools/qa/qa_versus_shots.gd godot/qa_versus_shots.gd
#   SHOT_DIR=/pfad/zu/shots xvfb-run -a -s "-screen 0 1280x720x24" \
#     godot --rendering-driver opengl3 --path godot --resolution 1280x720 \
#     --script res://qa_versus_shots.gd
#   rm godot/qa_versus_shots.gd
#
# Erzeugt: v1_start (VERSUS-Knopf), v2_lobby_leer, v3_lobby_bereit,
# v4_countdown, v5_rennen (Rennbalken + Gegner auf der Minimap + Ereignis),
# v6_im_ziel, v7_runde_gewonnen (mit Zwischenpause), v8_match_sieg.
extends SceneTree

const Session := preload("res://scripts/versus_session.gd")
const CELL := 2.0

var main: Node
var opp
var out_dir := ""


func _initialize() -> void:
	out_dir = OS.get_environment("SHOT_DIR")
	if out_dir == "":
		out_dir = "user://qa_shots"
	DirAccess.make_dir_recursive_absolute(out_dir)
	main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	_run()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(name: String) -> void:
	await process_frame
	root.get_viewport().get_texture().get_image().save_png(out_dir.path_join(name + ".png"))
	print("QA_SHOT ", name)


func _wait(cond: Callable, n: int = 3000) -> void:
	for i in n:
		if cond.call():
			return
		await process_frame


func _run() -> void:
	await _frames(20)
	await _shot("v1_start")
	var vs = main.versus
	vs.open_lobby()
	vs.ui.name_edit.text = "Alice"
	await _frames(5)
	await _shot("v2_lobby_leer")

	var port := 47990 + randi() % 8
	vs._on_host_requested("Alice", port)
	opp = Session.new()
	opp.my_name = "Bob"
	root.add_child(opp)
	opp.join("127.0.0.1", port)
	await _wait(func(): return vs.session.is_ready() and opp.is_ready())
	await _frames(5)
	await _shot("v3_lobby_bereit")

	vs.ui.start_requested.emit()
	await _wait(func(): return main.running)
	main.invuln_until = 1e9
	await _frames(10)
	await _shot("v4_countdown")
	await _wait(func(): return not main.start_hold, 60000)
	main.invuln_until = 1e9
	# a few pellets for the own bar, the opponent a little ahead
	var mv = main.maze_view
	for i in 40:
		var c: Vector2i = mv.pellet_cells[i]
		main.player.global_position = Vector3(c.y * CELL, main.player.global_position.y, c.x * CELL)
		main._check_pickups()
	# look down the corridor of the last pellet
	main.player.warp_to(main.player.cell(), main._facing_yaw_for_start(main.player.cell()))
	opp.send_progress(0.31, main.start_cell, 2, true)
	opp.send_rabbit("stromausfall", false, 0.4, Vector2i(0, 4), Vector2i(3, 0))
	await _frames(30)
	await _shot("v5_rennen")

	main.level_complete_sequence()
	await _frames(10)
	await _shot("v6_im_ziel")
	opp.report_finish(999.0)
	await _wait(func(): return not vs.session.round_open)
	await _frames(10)
	await _shot("v7_runde_gewonnen")
	# the match: let the bot lose round 2 by dying
	await _wait(func(): return opp.round_index == 1 and opp.round_open and main.running, 20000)
	main.invuln_until = 1e9
	opp.report_died()
	await _wait(func(): return vs.session.match_finished)
	await _frames(200)
	await _wait(func(): return vs.ui.result_menu_btn.visible, 20000)
	await _shot("v8_match_sieg")
	vs.leave()
	opp.close()
	await _frames(5)
	quit()
