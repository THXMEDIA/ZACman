# QA-Screenshots zu den Review-Fixes vom 03.10.2026 (Komfort, Menüs,
# Titelkarte, Kaninchen, verängstigte Geister, Bestenliste, reduzierte Looks).
#
# Aufruf aus dem Repo-Wurzelverzeichnis, wie die anderen QA-Skripte; die
# Auflösung 1152x720 ist die, bei der der Komfort-Block ohne Scrollen
# sichtbar sein muss:
#   cp tools/qa/qa_review_fix_shots.gd godot/qa_review_fix_shots.gd
#   SHOT_DIR=/pfad/zu/shots xvfb-run -a -s "-screen 0 1152x720x24" \
#     godot --rendering-driver opengl3 --fixed-fps 30 --path godot --resolution 1152x720 \
#     --script res://qa_review_fix_shots.gd
#   rm godot/qa_review_fix_shots.gd
#
# Erzeugt: r01_startscreen, r02_pause, r03_pause_rueckfrage, r04_gameover,
# r05_titelkarte, r06_start_hinweis, r07_kaninchen_nah, r08_geister_veraengstigt,
# r09_bestenliste, r10_matrix_reduziert, r11_kippbild_reduziert.
# Eigener Speicherordner (user://qa_review_saves, wird am Ende gelöscht),
# echte Spielstände und Einstellungen bleiben unberührt. Woche fest 2026-W40.
# --fixed-fps 30: jeder Frame zählt 1/30 s Spielzeit, unabhängig davon, wie
# langsam das Software-Rendering ist (sonst laufen Konditionen vor dem Bild ab).
# Software-Rendering: Farben und Glanz sind nur eine Näherung.
extends SceneTree

const SavePaths := preload("res://scripts/save_paths.gd")
const Conditions := preload("res://scripts/conditions.gd")
const QA_ROOT := "user://qa_review_saves"

var main: Node
var out_dir := ""


func _initialize() -> void:
	out_dir = OS.get_environment("SHOT_DIR")
	if out_dir == "":
		out_dir = "user://qa_shots"
	DirAccess.make_dir_recursive_absolute(out_dir)
	SavePaths.use_root(QA_ROOT)
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


func _yaw_for(d: Vector2i) -> float:
	if d.x == -1:
		return 0.0
	if d.x == 1:
		return PI
	if d.y == 1:
		return -PI / 2.0
	return PI / 2.0


func _seed_boards(leaderboard: Node, speedrun: Node) -> void:
	speedrun.reset_all()
	leaderboard.reset_all()
	var rows := [
		[112.9, "2026-W40", "matrix", "2026-10-01"],
		[118.4, "2026-W40", "", "2026-09-30"],
		[121.7, "2026-W40", "fear_and_loathing", "2026-10-02"],
		[109.6, "2026-W39", "taschenuhr", "2026-09-24"],
		[125.0, "2026-W39", "stromausfall", "2026-09-26"],
		[131.2, "2026-W38", "", "2026-09-17"],
		[127.5, "", "?", ""],
	]
	for r in rows:
		leaderboard.date_override = r[3] if r[3] != "" else "x"
		leaderboard.submit_time("klassik-1", "woche", r[0], "Player", "solo", r[1], r[2])
		speedrun.record_level_time("klassik-1", r[0], "woche", "solo", r[1])
	leaderboard.date_override = ""


func _run() -> void:
	await _frames(5)
	var speedrun: Node = root.get_node("Speedrun")
	var leaderboard: Node = root.get_node("Leaderboard")
	speedrun.reload()
	leaderboard.reload()
	_seed_boards(leaderboard, speedrun)
	main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	await _frames(10)
	main.rabbit_week_override = Vector2i(2026, 40)
	main.hud.current_week = Vector2i(2026, 40)
	main.seed_randomness(7)

	# 1. start screen at 1152x720: comfort block under the title, options
	# above SPEEDRUN, no game HUD
	await _frames(5)
	await _shot("r01_startscreen")

	# 2./3. pause with comfort block; HAUPTMENÜ asks first in a speedrun
	main.skip_start_intro = true
	main.begin_game("klassik-1")
	_calm()
	await _frames(20)
	main.toggle_pause()
	await _frames(5)
	await _shot("r02_pause")
	main.hud.menu_btn.pressed.emit()
	await _frames(3)
	await _shot("r03_pause_rueckfrage")
	main.hud.cancel_menu_confirm()
	main.toggle_pause()

	# 4. game over: NOCHMAL / HAUPTMENÜ / BESTENLISTE
	main.score = 1830
	main.end_game()
	await _frames(5)
	await _shot("r04_gameover")

	# 5. title card: F&L delay with a chat line, 7 s left
	main.begin_game("klassik-2")
	_calm()
	await _frames(10)
	var fl = Conditions.get_condition("fear_and_loathing")
	fl.set_manipulation("delay")
	main.start_condition(fl, "Chat 46 % → FEAR & LOATHING")
	main.player.movement_locked = true
	await _frames(70)
	await _shot("r05_titelkarte")
	main._end_condition(false)
	main.player.movement_locked = false

	# 6. after the intro: "Die Uhr startet mit deinem ersten Schritt"
	main.skip_start_intro = false
	main.begin_game("klassik-1")
	_calm()
	await _frames(5)
	main.intro_until_real = main.real_now
	await _frames(10)
	await _shot("r06_start_hinweis")
	main.start_hold = false
	main.player.movement_locked = false
	main.hud.show_clock_hint(false)
	main.skip_start_intro = true

	# 7. the rabbit up close: 1.5 cells in front of its dead end
	var mv = main.maze_view
	var r: Vector2i = mv.rabbit_cell
	var n: Vector2i = root.get_node("MazeGen").neighbors_of(main.maze, r.x, r.y)[0]
	var d: Vector2i = n - r
	var p := r + d * 2
	main.player.warp_to(p, _yaw_for(-d))
	main.player.global_position += Vector3(-d.y, 0, -d.x) * 0.9 # a bit closer
	await _frames(40)
	await _shot("r07_kaninchen_nah")

	# 8. frightened ghosts in the corridor in front of the player
	main.player.warp_to(main.start_cell, main._facing_yaw_for_start(main.start_cell))
	main.frightened_until = main.now + 999.0
	for e in main.enemies:
		e.release_at = 0.0
		e.mode = "chase"
	await _frames(3)
	main.paused = true # freeze the world without the pause panel
	var yaw: float = main.player.yaw
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	var side := Vector3(cos(yaw), 0, -sin(yaw))
	for i in main.enemies.size():
		var e = main.enemies[i]
		e.position = main.player.global_position + fwd * (2.6 + i * 1.6) + side * (0.35 if i % 2 == 0 else -0.35)
		e.position.y = 0.55
	await _frames(10)
	await _shot("r08_geister_veraengstigt")
	main.paused = false
	main.frightened_until = 0.0

	# 9. Bestenliste: weekly board, condition tags and dates, Allzeit
	main.end_game()
	main.hud.show_leaderboard("woche", "klassik-1")
	await _frames(5)
	await _shot("r09_bestenliste")

	# 10. Matrix with "Effekte reduzieren": walls stay permeable
	main.set_reduce_fx(true)
	main.begin_game("klassik-1")
	_calm()
	await _frames(10)
	main.start_condition(Conditions.get_condition("matrix"))
	main.player.movement_locked = true
	await _frames(90)
	await _shot("r10_matrix_reduziert")
	main._end_condition(false)

	# 11. Kippbild with "Effekte reduzieren": no tipping, thin frame
	var fl2 = Conditions.get_condition("fear_and_loathing")
	fl2.set_manipulation("swap")
	main.start_condition(fl2)
	await _frames(60)
	for i in 40:
		fl2._acting = true
		await process_frame
	await _shot("r11_kippbild_reduziert")
	main._end_condition(false)
	main.set_reduce_fx(false)

	var dir := DirAccess.open(QA_ROOT)
	if dir != null:
		for f in dir.get_files():
			dir.remove(f)
	DirAccess.remove_absolute(QA_ROOT)
	SavePaths.reset_root()
	quit()
