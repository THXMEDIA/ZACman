# QA-Screenshots der Kaninchen-Mechanik (Etappe 2, Spezifikation
# docs/design/kaninchen-speedrun.md 1.2 / 2.1 / 2.2).
#
# Aufruf aus dem Repo-Wurzelverzeichnis, wie qa_screenshots.gd:
#   cp tools/qa/qa_kaninchen_shots.gd godot/qa_kaninchen_shots.gd
#   SHOT_DIR=/pfad/zu/shots xvfb-run -a -s "-screen 0 1280x720x24" \
#     godot --rendering-driver opengl3 --path godot --resolution 1280x720 \
#     --script res://qa_kaninchen_shots.gd
#   rm godot/qa_kaninchen_shots.gd
#
# Erzeugt: k01_start_intro, k02_kaninchen, k03_titelkarte, k04_basis,
# k05_matrix, k06_fl_normal, k07_fl_gekippt, k08_stromausfall,
# k09_taschenuhr, k10_matrix_ende (letzte 3 s). Software-Rendering: Farben und
# Glanz sind nur eine Näherung.
extends SceneTree

const Conditions := preload("res://scripts/conditions.gd")

var main: Node
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
	var img := root.get_viewport().get_texture().get_image()
	var path := out_dir.path_join(name + ".png")
	img.save_png(path)
	print("QA_SHOT ", path)


## Ghosts stay home and can not hurt: calm pictures.
func _calm() -> void:
	main.invuln_until = 1e9
	for e in main.enemies:
		e.release_at = 1e9


func _yaw_for(dr: int, dc: int) -> float:
	if dr == -1:
		return 0.0
	if dr == 1:
		return PI
	if dc == 1:
		return -PI / 2.0
	return PI / 2.0


func _condition(id: String):
	var c = Conditions.get_condition(id)
	main.start_condition(c)
	return c


func _run() -> void:
	await _frames(10)
	main.rabbit_week_override = Vector2i(2026, 40)
	main.begin_game("klassik-1")
	_calm()
	await _frames(20)
	await _shot("k01_start_intro")
	main.intro_until_real = main.real_now
	await _frames(5)
	main.start_hold = false
	main.player.movement_locked = false
	_calm()

	# rabbit: stand two cells in front of its dead end, looking at it
	var mv = main.maze_view
	var r: Vector2i = mv.rabbit_cell
	var n: Vector2i = root.get_node("MazeGen").neighbors_of(main.maze, r.x, r.y)[0]
	var d := n - r
	var p := r + d * 2
	main.player.warp_to(p, _yaw_for(-d.x, -d.y))
	await _frames(30)
	await _shot("k02_kaninchen")

	# base look for comparison, back at the start
	main.player.warp_to(main.start_cell, main._facing_yaw_for_start(main.start_cell))
	await _frames(10)
	await _shot("k04_basis")

	_condition("matrix")
	await _frames(4)
	await _shot("k03_titelkarte")
	await _wait_game(1.0)
	await _shot("k05_matrix")
	main.condition_until = main.now + 2.0
	await _wait_game(0.15)
	await _shot("k10_matrix_ende")
	main._end_condition(false)

	var fl = _condition("fear_and_loathing")
	fl.set_manipulation("swap")
	main.hud.show_condition_card(fl)
	main.player.movement_locked = true # the look only; no walking for the picture
	await _wait_game(1.0)
	await _shot("k06_fl_normal")
	for i in 40:
		fl._acting = true
		await process_frame
	await _shot("k07_fl_gekippt")
	main.player.movement_locked = false
	main._end_condition(false)

	_condition("stromausfall")
	await _wait_game(1.0)
	await _shot("k08_stromausfall")
	main._end_condition(false)

	_condition("taschenuhr")
	await _wait_game(1.0)
	await _shot("k09_taschenuhr")
	main._end_condition(false)
	quit()


## Waits until the game clock moved on by `seconds` (frames at real speed).
func _wait_game(seconds: float) -> void:
	var until: float = main.now + seconds
	while main.now < until:
		await process_frame
