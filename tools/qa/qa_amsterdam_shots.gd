# QA-/Art-Screenshots der Explorer-Stadt Amsterdam („Pappmodell 1:100, Abend“).
# Aufruf aus dem Repo-Wurzelverzeichnis:
#   cp tools/qa/qa_amsterdam_shots.gd godot/qa_amsterdam_shots.gd
#   SHOT_DIR=/pfad xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-driver opengl3 \
#     --path godot --resolution 1280x720 --fixed-fps 60 --script res://qa_amsterdam_shots.gd
#   rm godot/qa_amsterdam_shots.gd
# ONLY=a6,a8 rendert nur diese Bilder (a1 und a2 immer). Rendern unter llvmpipe: ~1 min pro Bild.
#   a1_start.png            Startscreen mit Explorer-Auswahl (fünf Städte)
#   a1b_start_fokus.png     Startscreen, Fokus auf AMSTERDAM: Beschreibungszeile wechselt
#   a2_spawn.png            erster Blick nach dem Start (Damrak-Kai nach Westen, Westerkerk am Ende)
#   a3_kai_gracht.png       Kaistraße an der Keizersgracht nach Osten (Kaimauer, Bäume, Brücken)
#   a4_magere_brug.png      Prinsengracht-Südkai nach Osten auf die Magere Brug
#   a5_westerkerk.png       Damrak-Kai nach Westen, Blick hoch zum Turm
#   a6_tanzende_haeuser.png Damrak-Kai, Blick über das Wasser nach Norden
#   a7_ausgang.png          Amstel-Ostufer nach Norden: Haltestelle, grüne Tram, Fahne
#   a8_totale.png           Totale über dem Tisch (eigene QA-Kamera): das Modell auf der Schneidematte
#   a9_reduziert.png        wie a3 mit „Effekte reduzieren“
#   a10_kante.png           Kaimauer aus der Nähe (Wellen-Schnittkante)
#   a11_raum.png            von der Magere Brug die Amstel hinauf: der Raum hinter dem Modell (ohne Blendfleck)
#   a12_minimap.png         Spawn mit Minimap (Wasser, Kugeln, Ausgang-Ring, weißer Pfeil)
#   a13_suedkai.png         über die Keizersgracht auf die Nordfassaden (Gegenlicht)
#   a14_westermarkt_becher.png  Westermarkt nach Süden: Straße endet an der Schnittkante, Becher mit Bleistift
#   a15_tram_tuer.png       Bahnsteig: offene Tram-Tür mit Innenlicht und grünem Bodenfleck
#   a16_hinweis_reduziert.png   Start mit „Effekte reduzieren“: Ziel-Hinweis oben mittig
#   a17_passanten.png       Pappfiguren (Passanten) am Kai, aus der Straßenmitte
#   a18_rad.png             Radfahrer (Pappfigur auf dem Rad) beim Vorbeifahren
#   a17_passanten.png       Pappfiguren (Passanten) am Kai, aus der Straßenmitte
#   a18_rad.png             Radfahrer (Pappfigur auf dem Rad) beim Vorbeifahren
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
	_steps.append({"wait": 2, "do": func(): main.hud.explorer_buttons["amsterdam"].grab_focus()})
	_steps.append({"wait": 6, "do": func():
		_shot("a1b_start_fokus.png")
		main.hud.explorer_buttons["amsterdam"].release_focus()})
	_steps.append({"wait": 5, "do": func():
		main.seed_randomness(4242)
		main.begin_explorer_game("amsterdam")})
	_steps.append({"wait": 60, "do": func(): _shot("a2_spawn.png")})
	var poses := [
		["a3_kai_gracht.png", 20.0, 40.6, E, 0.04, 0.0],
		["a4_magere_brug.png", 52.0, 84.0, E, 0.06, 0.0],
		["a5_westerkerk.png", 40.0, 24.0, W, 0.42, 0.0],
		["a6_tanzende_haeuser.png", 44.0, 26.6, N + 0.3, 0.3, 0.0],
		["a7_ausgang.png", 86.0, 82.0, N - 0.12, 0.08, 0.0],
		["a10_kante.png", 47.0, 42.35, -1.92, -0.5, 0.0],
		["a13_suedkai.png", 40.0, 42.0, PI, 0.1, 0.0],
		["a11_raum.png", 76.0, 84.0, N, 0.04, 0.0],
		["a14_westermarkt_becher.png", 16.0, 66.0, PI, 0.12, 0.0],
		["a15_tram_tuer.png", 84.6, 68.6, -0.85, -0.08, 0.0],
	]
	for p in poses:
		if not _wanted(only, p[0]):
			continue
		_steps.append({"wait": 2, "do": func(): _pose(p[1], p[2], p[3], p[4], p[5])})
		_steps.append({"wait": 24, "do": func(): _shot(p[0])})
	# the totale: a separate QA camera high over the desk (the game camera is
	# never moved; this is the trailer / photo-mode view)
	if _wanted(only, "a8_totale.png"):
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
	if _wanted(only, "a9_reduziert.png"):
		_steps.append({"wait": 2, "do": func():
			main.set_reduce_fx(true)
			_pose(20.0, 40.6, E, 0.04)})
		_steps.append({"wait": 24, "do": func():
			_shot("a9_reduziert.png")
			main.set_reduce_fx(false)})
	if _wanted(only, "a12_minimap.png"):
		_steps.append({"wait": 2, "do": func():
			var s: Vector2i = main.maze.start_cell
			_pose(s.y * 2.0, s.x * 2.0, W, 0.0)})
		_steps.append({"wait": 24, "do": func(): _shot("a12_minimap.png")})
	if _wanted(only, "a16_hinweis_reduziert.png"):
		_steps.append({"wait": 2, "do": func():
			main.set_reduce_fx(true)
			main.begin_explorer_game("amsterdam")})
		_steps.append({"wait": 30, "do": func():
			_shot("a16_hinweis_reduziert.png")
			main.set_reduce_fx(false)})
	# card people and bicycles (amsterdam_life.gd): the camera stands on the
	# middle of the street (the pin line) and looks at a figure
	if _wanted(only, "a17_passanten.png"):
		_steps.append({"wait": 2, "do": func():
			main.amsterdam_life.advance(23.0)
			_face_figure(false)})
		_steps.append({"wait": 24, "do": func(): _shot("a17_passanten.png")})
	if _wanted(only, "a18_rad.png"):
		_steps.append({"wait": 2, "do": func():
			main.amsterdam_life.advance(11.0)
			_face_figure(true)})
		_steps.append({"wait": 24, "do": func(): _shot("a18_rad.png")})
	_steps.append({"wait": 2, "do": func(): quit()})


## Stand on the centre line of the street that holds `target`, 3.5 m along it
## from the target, and look at it.
func _look_from_street(target: Vector3, back: float) -> void:
	var rects: Array = load("res://scripts/amsterdam_life.gd").lane_rects()
	var best := Vector3(target.x, 0.0, target.z + 3.0)
	var best_d := 1e9
	for r in rects:
		var ew: bool = r.axis == "ew"
		var along: float = target.x if ew else target.z
		var across: float = target.z if ew else target.x
		if along < r.a0 or along > r.a1 or absf(across - r.centre) > r.hw:
			continue
		var d := absf(across - r.centre)
		if d < best_d:
			best_d = d
			var a2: float = clampf(along - 3.5 - back, r.a0 + 1.0, r.a1 - 1.0)
			best = Vector3(a2, 0.0, r.centre) if ew else Vector3(r.centre, 0.0, a2)
	var dx := target.x - best.x
	var dz := target.z - best.z
	_pose(best.x, best.z, atan2(-dx, -dz), -0.04)


func _face_figure(rider: bool) -> void:
	var life = main.amsterdam_life
	var n: int = life.rider_count() if rider else life.walker_count()
	var start: Vector2 = life.start_pos()
	for i in n:
		var p: Vector3 = life.rider_position(i) if rider else life.walker_position(i)
		if not rider and not life.walker_moving(i):
			continue
		if Vector2(p.x, p.z).distance_to(start) < 12.0 or Vector2(p.x, p.z).distance_to(life.exit_pos()) < 12.0:
			continue
		_look_from_street(p, 0.0)
		return
	_look_from_street(life.walker_position(0), 0.0)



## ONLY=a6,a8 renders just those (a1 and a2 always).
func _wanted(only: String, name: String) -> bool:
	if only == "":
		return true
	for o in only.split(","):
		if o != "" and name.begins_with(o):
			return true
	return false


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
