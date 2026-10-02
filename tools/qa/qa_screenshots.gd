# QA-Screenshots für ZACman (vom qa-playtester-Agenten genutzt).
#
# Aufruf aus dem Repo-Wurzelverzeichnis mit virtuellem Bildschirm. Godot kann
# Skripte nur innerhalb des Projektordners laden, deshalb vorübergehend kopieren:
#   cp tools/qa/qa_screenshots.gd godot/qa_screenshots.gd
#   SHOT_DIR=/pfad/zu/shots xvfb-run -a -s "-screen 0 1280x720x24" \
#     godot --rendering-driver opengl3 --path godot --resolution 1280x720 \
#     --script res://qa_screenshots.gd
#   rm godot/qa_screenshots.gd
#
# Erzeugt: 01_start.png (Startmenü), 02_matrix.png (Matrix-Level kurz nach Start),
# 03_pause.png (Pause), 04_manhattan.png (Explorer-Level Manhattan).
# Software-Rendering: Grafikqualität und Ton sind nicht repräsentativ.
extends SceneTree

var main: Node
var frame := 0
var out_dir := ""

func _initialize() -> void:
	out_dir = OS.get_environment("SHOT_DIR")
	if out_dir == "":
		out_dir = "user://qa_shots"
	DirAccess.make_dir_recursive_absolute(out_dir)
	main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)

func _shot(name: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	var path := out_dir.path_join(name)
	img.save_png(path)
	print("QA_SHOT ", path)

func _process(_delta: float) -> bool:
	frame += 1
	match frame:
		60:
			_shot("01_start.png")
			main.begin_game()
		180:
			_shot("02_matrix.png")
			main.toggle_pause()
		220:
			_shot("03_pause.png")
			main.toggle_pause()
			main.begin_manhattan_game()
		360:
			_shot("04_manhattan.png")
		370:
			quit()
	return false
