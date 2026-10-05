# QA-/Art-Screenshots der Explorer-Stadt Arles („Sternennacht, echte Orte stilisiert“, tiefe Nacht).
# Aufruf aus dem Repo-Wurzelverzeichnis:
#   cp tools/qa/qa_arles_shots.gd godot/qa_arles_shots.gd
#   SHOT_DIR=/pfad xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-driver opengl3 \
#     --path godot --resolution 1280x720 --fixed-fps 60 --script res://qa_arles_shots.gd
#   rm godot/qa_arles_shots.gd
# ONLY=r3,r8 rendert nur diese Bilder (r1 und r2 immer). ARLES_SKY_SAVE=/pfad/himmel.png speichert
# den gebackenen Himmel. Ansichten wie im Prototyp arles_v2 (Kartenkoordinaten = Welt + (1, 0, 1)).
#   r1_start.png            Startscreen mit Explorer-Auswahl (fünf Städte)
#   r2_spawn.png            erster Blick nach dem Start (Rue de la Calade nach Westen)
#   r3_strasse.png          Rue de l'Hôtel de Ville nach Norden auf die Caféterrasse
#   r4_forum.png            Place du Forum: Caféterrasse, Säulen, Statue
#   r5_arenes.png           Rond-point des Arènes: Arena mit Arkaden
#   r6_trophime.png         Place de la République: Portal von Saint-Trophime
#   r7_theatre.png          Rue de la Calade nach Osten: Théâtre antique
#   r8_kai.png              Kai an der Rhône: Spiegelungen
#   r9_ausgang.png          Place Lamartine: Gelbes Haus, grüne Tür, grüner Stern
#   r10_totale.png          Totale von der Rhône (eigene QA-Kamera, Spielkamera unberührt)
#   r11_reduziert.png       wie r3 mit „Effekte reduzieren“
#   r12_minimap.png         Spawn mit Minimap (Kai, Kugeln, Ausgang-Ring, weißer Pfeil)
#   r13_cafe_route.png      der Weg an der Caféterrasse entlang nach Westen (Säulen voraus)
#   r14_kugeln.png          Kugeln aus der Nähe (Objekt statt Licht, dunkle Kontur)
#   r15_abstecher.png       Rond-point: Abstecher gepunktet, Arena
extends SceneTree

const SHIFT := Vector3(1.0, 0.0, 1.0)

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


## Stand at map position `pos` and look at map point `look` (player yaw and
## pitch only - the camera itself is never touched).
func _look(pos: Vector3, look: Vector3) -> void:
	var p := pos - SHIFT
	var d := look - pos
	main.player.global_position = Vector3(p.x, main.player.EYE_H, p.z)
	var yaw := atan2(-d.x, -d.z)
	var pitch := atan2(d.y - 0.2, Vector2(d.x, d.z).length())
	main.player.yaw = yaw
	main.player.pitch = pitch
	main.player.rotation.y = yaw
	main.player.camera.rotation.x = pitch


func _plan() -> void:
	var only := OS.get_environment("ONLY")
	_steps.append({"wait": 40, "do": func(): _shot("r1_start.png")})
	_steps.append({"wait": 5, "do": func():
		main.seed_randomness(4242)
		main.begin_explorer_game("arles")})
	_steps.append({"wait": 60, "do": func(): _shot("r2_spawn.png")})
	var views := [
		["r3_strasse.png", Vector3(27.0, 1.7, 63.0), Vector3(27.0, 3.6, 28.0)],
		["r4_forum.png", Vector3(19.0, 1.7, 47.0), Vector3(28.5, 3.6, 30.0)],
		["r5_arenes.png", Vector3(49.5, 1.7, 26.5), Vector3(64.0, 7.5, 39.0)],
		["r6_trophime.png", Vector3(22.5, 1.7, 65.0), Vector3(29.0, 6.5, 76.0)],
		["r7_theatre.png", Vector3(62.5, 1.7, 70.6), Vector3(71.0, 6.8, 71.0)],
		["r8_kai.png", Vector3(3.2, 1.7, 56.0), Vector3(-10.0, 0.6, 24.0)],
		["r9_ausgang.png", Vector3(15.5, 1.7, 15.0), Vector3(15.0, 6.5, 0.0)],
		["r13_cafe_route.png", Vector3(30.0, 1.7, 35.6), Vector3(14.0, 2.4, 33.0)],
		["r14_kugeln.png", Vector3(27.0, 1.7, 49.0), Vector3(27.0, 0.3, 40.0)],
		["r15_abstecher.png", Vector3(51.0, 1.7, 62.5), Vector3(51.0, 1.0, 30.0)],
	]
	for v in views:
		if not _wanted(only, v[0]):
			continue
		_steps.append({"wait": 2, "do": func(): _look(v[1], v[2])})
		_steps.append({"wait": 24, "do": func(): _shot(v[0])})
	if _wanted(only, "r10_totale.png"):
		_steps.append({"wait": 2, "do": func():
			_qa_cam = Camera3D.new()
			_qa_cam.fov = 64.0
			_qa_cam.far = 900.0
			root.add_child(_qa_cam)
			_qa_cam.global_position = Vector3(-46.0, 30.0, 46.0) - SHIFT
			_qa_cam.look_at(Vector3(50.0, 9.0, 40.0) - SHIFT)
			_qa_cam.make_current()})
		_steps.append({"wait": 24, "do": func():
			_shot("r10_totale.png")
			main.player.camera.make_current()
			_qa_cam.queue_free()})
	if _wanted(only, "r11_reduziert.png"):
		_steps.append({"wait": 2, "do": func():
			main.set_reduce_fx(true)
			_look(Vector3(27.0, 1.7, 63.0), Vector3(27.0, 3.6, 28.0))})
		_steps.append({"wait": 24, "do": func():
			_shot("r11_reduziert.png")
			main.set_reduce_fx(false)})
	if _wanted(only, "r12_minimap.png"):
		_steps.append({"wait": 2, "do": func():
			var s: Vector2i = main.maze.start_cell
			_look(Vector3(s.y * 2.0 + 1.0, 1.7, s.x * 2.0 + 1.0), Vector3(s.y * 2.0 - 20.0, 1.9, s.x * 2.0 + 1.0))})
		_steps.append({"wait": 24, "do": func(): _shot("r12_minimap.png")})
	_steps.append({"wait": 2, "do": func(): quit()})


## ONLY=r3,r8 renders just those (r1 and r2 always).
func _wanted(only: String, name: String) -> bool:
	if only == "":
		return true
	for o in only.split(","):
		if o != "" and name.begins_with(o + "_"):
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
