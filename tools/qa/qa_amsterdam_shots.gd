# QA-/Art-Screenshots der Explorer-Stadt Amsterdam („Pappmodell 1:100, Abend“).
# Aufruf aus dem Repo-Wurzelverzeichnis:
#   cp tools/qa/qa_amsterdam_shots.gd godot/qa_amsterdam_shots.gd
#   SHOT_DIR=/pfad xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-driver opengl3 \
#     --path godot --resolution 1280x720 --fixed-fps 60 --script res://qa_amsterdam_shots.gd
#   rm godot/qa_amsterdam_shots.gd
#   a1_start.png            Startscreen mit Explorer-Auswahl (vier Städte)
#   a2_spawn.png            erster Blick nach dem Start (Damrak-Kai nach Westen, Westerkerk am Ende)
#   a3_kai_gracht.png       Kaistraße an der Keizersgracht nach Osten (Kaimauer, Bäume, Brücken)
#   a4_magere_brug.png      Prinsengracht-Südkai nach Osten auf die Magere Brug
#   a5_westerkerk.png       Damrak-Kai nach Westen, Blick hoch zum Turm
#   a6_tanzende_haeuser.png Damrak-Kai, Blick über das Wasser nach Norden
#   a7_ausgang.png          Amstel-Ostufer nach Norden: Haltestelle, grüne Tram, Fahne
#   a8_totale.png           Totale über dem Tisch (eigene QA-Kamera): das Modell auf der Schneidematte
#   a9_reduziert.png        wie a3 mit „Effekte reduzieren“
#   a10_kante.png           Kaimauer aus der Nähe (Wellen-Schnittkante)
#   a11_becher.png          von der Magere Brug die Amstel hinauf: Becher hinter der Modellkante
#   a12_minimap.png         Spawn mit Minimap (Wasser, Kugeln, Ausgang)
#   a13_suedkai.png         über die Keizersgracht auf die Nordfassaden (Gegenlicht)
extends SceneTree

var main: Node
var frame := 0
var out_dir := ""
var _steps: Array = []
var _step_i := 0
var _wait_until := 0
var _qa_cam: Camera3D


func _initialize() -> void:
	out_dir = OS.get_environment("SHOT_DIR")
	if out_dir == "":
		out_dir = "user://qa_shots"
	DirAccess.make_dir_recursive_absolute(out_dir)
	seed(4242)
	main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	_plan()


func _shot(name: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join(name))
	print("QA_SHOT ", out_dir.path_join(name))


func _pose(x: float, z: float, yaw: float, pitch: float = 0.0, lift: float = 0.0) -> void:
	main.player.global_position = Vector3(x, main.player.EYE_H + lift, z)
	main.player.yaw = yaw
	main.player.pitch = pitch
	main.player.rotation.y = yaw
	main.player.camera.rotation.x = pitch


func _plan() -> void:
	var E := -PI * 0.5
	var W := PI * 0.5
	var N := 0.0
	var only := OS.get_environment("ONLY")
	_steps.append({"wait": 40, "do": func(): _shot("a1_start.png")})
	_steps.append({"wait": 5, "do": func():
		main.seed_randomness(4242)
		main.begin_explorer_game("amsterdam")})
	_steps.append({"wait": 60, "do": func(): _shot("a2_spawn.png")})
	var poses := [
		["a3_kai_gracht.png", 20.0, 40.6, E, 0.04, 0.0],
		["a4_magere_brug.png", 52.0, 84.0, E, 0.06, 0.0],
		["a5_westerkerk.png", 40.0, 24.0, W, 0.42, 0.0],
		["a6_tanzende_haeuser.png", 46.0, 22.0, N + 0.25, 0.12, 0.0],
		["a7_ausgang.png", 86.0, 82.0, N - 0.12, 0.08, 0.0],
		["a10_kante.png", 47.0, 42.35, -1.92, -0.5, 0.0],
		["a13_suedkai.png", 40.0, 42.0, PI, 0.1, 0.0],
		["a11_becher.png", 76.0, 84.0, N, 0.04, 0.0],
	]
	for p in poses:
		if only != "" and not p[0].begins_with(only):
			continue
		_steps.append({"wait": 2, "do": func(): _pose(p[1], p[2], p[3], p[4], p[5])})
		_steps.append({"wait": 24, "do": func(): _shot(p[0])})
	# the totale: a separate QA camera high over the desk (the game camera is
	# never moved; this is the trailer / photo-mode view)
	if only == "" or "a8".begins_with(only):
		_steps.append({"wait": 2, "do": func():
			_qa_cam = Camera3D.new()
			_qa_cam.fov = 46.0
			_qa_cam.far = 900.0
			root.add_child(_qa_cam)
			_qa_cam.global_position = Vector3(-38.0, 72.0, 150.0)
			_qa_cam.look_at(Vector3(46.0, 0.0, 44.0))
			_qa_cam.make_current()})
		_steps.append({"wait": 24, "do": func():
			_shot("a8_totale.png")
			main.player.camera.make_current()
			_qa_cam.queue_free()})
	_steps.append({"wait": 2, "do": func():
		main.set_reduce_fx(true)
		_pose(20.0, 40.6, E, 0.04)})
	_steps.append({"wait": 24, "do": func(): _shot("a9_reduziert.png")})
	_steps.append({"wait": 2, "do": func():
		main.set_reduce_fx(false)
		var s: Vector2i = main.maze.start_cell
		_pose(s.y * 2.0, s.x * 2.0, W, 0.0)})
	_steps.append({"wait": 24, "do": func(): _shot("a12_minimap.png")})
	_steps.append({"wait": 2, "do": func(): quit()})


func _process(_delta: float) -> bool:
	frame += 1
	if _step_i >= _steps.size() or frame < _wait_until:
		return false
	var s: Dictionary = _steps[_step_i]
	if s.has("armed"):
		s["do"].call()
		_step_i += 1
		if _step_i < _steps.size():
			_wait_until = frame + int(_steps[_step_i].wait)
	else:
		s["armed"] = true
		_wait_until = frame + int(s.wait)
	return false
