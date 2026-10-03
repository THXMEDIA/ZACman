# QA-Screenshots für Etappe 3 (Bretter, Chaos-Modus, Twitch-Chat-Gewichtung;
# Spezifikation docs/design/kaninchen-speedrun.md 2.5 / 2.6).
#
# Aufruf aus dem Repo-Wurzelverzeichnis, wie qa_screenshots.gd:
#   cp tools/qa/qa_etappe3_shots.gd godot/qa_etappe3_shots.gd
#   SHOT_DIR=/pfad/zu/shots xvfb-run -a -s "-screen 0 1280x720x24" \
#     godot --rendering-driver opengl3 --path godot --resolution 1280x720 \
#     --script res://qa_etappe3_shots.gd
#   rm godot/qa_etappe3_shots.gd
#
# Erzeugt: e01_startscreen_chaos, e02_hud_chaos, e03_chat_balken,
# e04_titelkarte_chat, e05_bestenliste_woche, e06_bestenliste_chaos.
# Läuft in einem eigenen Speicherordner (user://qa_etappe3_saves, wird am
# Ende gelöscht) und füllt die Bretter mit Beispielzeiten — echte Spielstände
# und Einstellungen bleiben unberührt. Die Woche ist fest 2026-W40.
# Software-Rendering: Farben und Glanz sind nur eine Näherung.
extends SceneTree

const SavePaths := preload("res://scripts/save_paths.gd")
const QA_ROOT := "user://qa_etappe3_saves"

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


func _seed_boards(speedrun: Node, leaderboard: Node) -> void:
	speedrun.reset_all()
	leaderboard.reset_all()
	var week_times := [[118.4, "2026-W38"], [112.9, "2026-W39"], [121.7, "2026-W40"], [109.6, "2026-W39"], [125.0, "2026-W40"], [131.2, "2025-W51"]]
	for wt in week_times:
		speedrun.record_level_time("klassik-1", wt[0], "woche", "solo", wt[1])
		leaderboard.submit_time("klassik-1", "woche", wt[0], "Player", "solo", wt[1])
	for t in [104.3, 117.8, 99.1]:
		speedrun.record_level_time("klassik-1", t, "chaos")
		leaderboard.submit_time("klassik-1", "chaos", t, "Player")
	leaderboard.submit_time("klassik-1", "chat", 96.5, "Player")


func _run() -> void:
	await _frames(5)
	var speedrun: Node = root.get_node("Speedrun")
	var leaderboard: Node = root.get_node("Leaderboard")
	var twitch: Node = root.get_node("Twitch")
	speedrun.reload()
	leaderboard.reload()
	_seed_boards(speedrun, leaderboard)
	main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	await _frames(10)
	main.rabbit_week_override = Vector2i(2026, 40)
	main.hud.current_week = Vector2i(2026, 40)
	main.skip_start_intro = true

	# 1. start screen with the Chaos switch on
	main.set_chaos_mode(true)
	await _frames(5)
	await _shot("e01_startscreen_chaos")

	# 2. HUD in Chaos mode
	main.begin_game("klassik-1")
	_calm()
	await _frames(30)
	await _shot("e02_hud_chaos")
	main.set_chaos_mode(false)

	# 3. chat mode: the rabbit share chip (7 gut / 3 schlecht -> 72 %)
	twitch.enabled = true
	main.begin_game("klassik-2")
	_calm()
	for i in 7:
		twitch.chat_command.emit("fan%d" % i, "gut", "")
	for i in 3:
		twitch.chat_command.emit("troll%d" % i, "schlecht", "")
	await _frames(30)
	await _shot("e03_chat_balken")

	# 4. pick the rabbit up: title card "Chat 72 % → ..."
	var rn = main.maze_view.rabbit_node
	main.player.global_position = Vector3(rn.position.x, main.player.global_position.y, rn.position.z)
	await _frames(3)
	var cell: Vector2i = main.player.cell()
	main.player.warp_to(cell, main._facing_yaw_for_start(cell))
	await _frames(40)
	await _shot("e04_titelkarte_chat")
	main._end_condition(false)
	twitch.enabled = false
	main.chat_vote.clear()

	# 5./6. Bestenliste: weekly board with weeks, chaos board
	main.end_game()
	main.hud.show_leaderboard("woche", "klassik-1")
	await _frames(5)
	await _shot("e05_bestenliste_woche")
	main.hud._set_lb_board("chaos")
	await _frames(5)
	await _shot("e06_bestenliste_chaos")

	# clean up the QA save folder
	var dir := DirAccess.open(QA_ROOT)
	if dir != null:
		for f in dir.get_files():
			dir.remove(f)
	DirAccess.remove_absolute(QA_ROOT)
	SavePaths.reset_root()
	quit()
