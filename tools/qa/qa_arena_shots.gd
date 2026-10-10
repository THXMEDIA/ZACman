# QA-Screenshots des Arena-Modus (ZAP-9: beide Spieler in einem Labyrinth).
#
# Ein Prozess: das echte Spiel hostet, eine zweite VersusSession im selben
# Prozess spielt den Gegner (nur Protokoll: Position, gefressene Kugeln).
# Aufruf aus dem Repo-Wurzelverzeichnis:
#   cp tools/qa/qa_arena_shots.gd godot/qa_arena_shots.gd
#   SHOT_DIR=/pfad/zu/shots xvfb-run -a -s "-screen 0 1280x720x24" \
#     godot --rendering-driver opengl3 --path godot --resolution 1280x720 \
#     --script res://qa_arena_shots.gd
#   rm godot/qa_arena_shots.gd
#
# Erzeugt: a1_lobby (Modus-Schalter), a2_countdown, a3_gegner_im_blick
# (Gegnerfigur voraus, orange Gegner-Kugeln, eigene Kugeln in Theme-Farbe),
# a4_kugeln_weg (Gegner hat Kugeln gefressen, sie fehlen), a5_nah (Gegner
# direkt vor dem Spieler, Kollision), a6_spiegelrennen (Lobby mit Modus Spiegelrennen).
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


func _ahead(dist: float) -> Vector3:
	var p: Vector3 = main.player.global_position
	var yaw: float = main.player.yaw
	return p + Vector3(-sin(yaw), 0.0, -cos(yaw)) * dist


## Bob's position goes out every frame (a real game sends it ~15 times a second).
func _send_pos(p: Vector3, yaw: float, frames: int) -> void:
	for i in frames:
		opp.send_pos(p.x, p.z, yaw, true)
		await process_frame


func _run() -> void:
	await _frames(20)
	var vs = main.versus
	vs.open_lobby()
	vs.ui.name_edit.text = "Alice"
	await _frames(5)
	await _shot("a1_lobby")

	var port := 47990 + randi() % 8
	vs._on_host_requested("Alice", port)
	opp = Session.new()
	opp.my_name = "Bob"
	root.add_child(opp)
	opp.join("127.0.0.1", port)
	await _wait(func(): return vs.session.is_ready() and opp.is_ready())
	await _frames(5)
	vs.ui.start_requested.emit()
	await _wait(func(): return main.running)
	main.invuln_until = 1e9
	await _frames(10)
	await _shot("a2_countdown")
	await _wait(func(): return not main.start_hold, 60000)
	main.invuln_until = 1e9
	await _frames(10)

	# Bob stands a few metres ahead, looking back at the player
	var bp := _ahead(5.0)
	await _send_pos(bp, main.player.yaw + PI, 40)
	await _shot("a3_gegner_im_blick")

	# Bob directly in front: the player runs into him and stops (solid body)
	var near := _ahead(1.6)
	await _send_pos(near, main.player.yaw + PI, 20)
	main.player.move_input = Vector2(0, 1)
	await _send_pos(near, main.player.yaw + PI, 40)
	main.player.move_input = Vector2.ZERO
	await _shot("a5_nah")
	print("A5 distance player-Bob: ", Vector2(main.player.global_position.x - near.x, main.player.global_position.z - near.z).length())

	# Bob ate some of HIS pellets: they are gone in the host's maze; Bob moves
	# off to the side, the player walks on to look at the pellet field
	var mv = main.maze_view
	var n := 0
	for i in mv.pellet_cells.size():
		if mv.pellet_owner[i] != mv.arena_side and mv.pellet_owner[i] >= 0 and mv.pellet_alive[i] and n < 25:
			opp.send_eat(mv.pellet_cells[i])
			n += 1
			await process_frame
	var far := _ahead(12.0)
	await _send_pos(far, main.player.yaw, 10)
	main.player.dash_charges = 1
	main.player.try_dash() # the dash passes the opponent
	await _frames(30)
	main.player.move_input = Vector2(0, 1)
	await _send_pos(far, main.player.yaw, 60)
	main.player.move_input = Vector2.ZERO
	await _shot("a4_kugeln_weg")

	vs.leave()
	opp.close()
	await _frames(5)
	vs.open_lobby()
	vs.ui.set_mode("race")
	await _frames(5)
	await _shot("a6_spiegelrennen")
	vs.leave()
	await _frames(5)
	quit()
