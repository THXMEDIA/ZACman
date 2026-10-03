# QA-Screenshots der Explorer-Städte (Manhattan, Tokyo) für ZAPmaniac.
#
# Deterministisch: fester Zufall (Main.seed_randomness + seed()) und feste
# Bildrate, damit Manhattan-Bilder vor und nach einer Änderung Pixel für Pixel
# verglichen werden können. Aufruf aus dem Repo-Wurzelverzeichnis:
#   cp tools/qa/qa_explorer_shots.gd godot/qa_explorer_shots.gd
#   SHOT_DIR=/pfad/zu/shots SHOT_SET=all xvfb-run -a -s "-screen 0 1280x720x24" \
#     godot --rendering-driver opengl3 --path godot --resolution 1280x720 \
#     --fixed-fps 60 --script res://qa_explorer_shots.gd
#   rm godot/qa_explorer_shots.gd
#
# SHOT_SET=manhattan erzeugt nur die Manhattan-Vergleichsbilder (läuft auch auf
# Ständen ohne Tokyo). SHOT_SET=all zusätzlich (Tokyo M2: Regen, Verkehr,
# Passanten, Scramble; die Ampelphase wird per TokyoLife.advance angesteuert):
#   t1_start.png                 Startscreen mit Explorer-Auswahl
#   t2_kreuzung_verkehr.png      Totale über die Kreuzung, Ost-West-Verkehr fließt
#   t3_strasse_regen.png         Straßenblick in Augenhöhe Richtung Bahnhof,
#                                Nord-Süd-Verkehr, Regen, nasser Boden
#   t4_ubahn.png                 U-Bahn-Eingang (地下鉄) mit Lichtkegel
#   t5_gasse.png                 Seitengasse mit Ladenschildern
#   t6_kreuzung_scramble.png     Totale im „All Walk“: Autos halten, Welle quert
#   t7_strasse_regen_reduziert.png  wie t3 mit „Regen reduzieren“
#   t8_scramble_augenhoehe.png   Scramble aus Augenhöhe am Kreuzungsrand
# Manhattan: m1_manhattan.png (Start), m2_manhattan_blick.png (fester Blick).
# Software-Rendering (Compatibility): keine SSR (der Boden zeigt die
# Spiegelung ohne SSR aus tokyo_floor_reflect.gdshader), Glow angenähert.
extends SceneTree

var main: Node
var frame := 0
var out_dir := ""
var shot_set := "all"
var _steps: Array = []
var _step_i := 0
var _wait_until := 0


func _initialize() -> void:
	out_dir = OS.get_environment("SHOT_DIR")
	if out_dir == "":
		out_dir = "user://qa_shots"
	shot_set = OS.get_environment("SHOT_SET")
	if shot_set == "":
		shot_set = "all"
	DirAccess.make_dir_recursive_absolute(out_dir)
	seed(4242)
	main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	_plan()


func _shot(name: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	var path := out_dir.path_join(name)
	img.save_png(path)
	print("QA_SHOT ", path)


## Places the player camera: position on the floor plan (x, z), eye height
## offset (0 = normal eye height), yaw (0 = north) and pitch.
func _pose(x: float, z: float, yaw: float, pitch: float = 0.0, lift: float = 0.0) -> void:
	main.player.global_position = Vector3(x, main.player.EYE_H + lift, z)
	main.player.yaw = yaw
	main.player.pitch = pitch
	main.player.rotation.y = yaw
	main.player.camera.rotation.x = pitch


## Fast-forwards Tokyo's scramble cycle to `cycle` seconds (TokyoLife).
func _life_to(cycle: float) -> void:
	var life = main.get("tokyo_life")
	if life == null:
		return
	life.advance(fposmod(cycle - life.cycle_time, life.CYCLE))


func _plan() -> void:
	_steps = []
	if shot_set == "all":
		_steps.append({"wait": 40, "do": func(): _shot("t1_start.png")})
	_steps.append({"wait": 10, "do": func():
		main.seed_randomness(4242)
		main.begin_manhattan_game()})
	_steps.append({"wait": 90, "do": func(): _shot("m1_manhattan.png")})
	_steps.append({"wait": 2, "do": func(): _pose(22.0, 2.0, -PI * 0.5, 0.0)})
	_steps.append({"wait": 30, "do": func(): _shot("m2_manhattan_blick.png")})
	if shot_set == "all":
		_steps.append({"wait": 5, "do": func():
			main.go_to_main_menu()
			main.seed_randomness(4242)
			main.reduce_rain = false
			main.begin_explorer_game("tokyo")})
		# east-west traffic flowing (cycle 42 s)
		_steps.append({"wait": 5, "do": func():
			_life_to(42.0)
			_pose(52.2, 52.2, PI * 0.25, -0.36, 7.0)})
		_steps.append({"wait": 30, "do": func(): _shot("t2_kreuzung_verkehr.png")})
		# north-south traffic towards the camera and away (cycle 12 s)
		_steps.append({"wait": 2, "do": func():
			_life_to(12.0)
			_pose(46.0, 67.0, 0.0, 0.04)})
		_steps.append({"wait": 30, "do": func(): _shot("t3_strasse_regen.png")})
		_steps.append({"wait": 2, "do": func(): main.set_reduce_rain(true)})
		_steps.append({"wait": 20, "do": func(): _shot("t7_strasse_regen_reduziert.png")})
		_steps.append({"wait": 2, "do": func():
			main.set_reduce_rain(false)
			_pose(48.0, 16.0, 0.12, 0.10)})
		_steps.append({"wait": 30, "do": func(): _shot("t4_ubahn.png")})
		_steps.append({"wait": 2, "do": func(): _pose(18.0, 34.0, 0.0, 0.06)})
		_steps.append({"wait": 30, "do": func(): _shot("t5_gasse.png")})
		# All Walk, 7 s in (cycle 67 s)
		_steps.append({"wait": 2, "do": func():
			_life_to(67.0)
			_pose(52.2, 52.2, PI * 0.25, -0.36, 7.0)})
		_steps.append({"wait": 20, "do": func(): _shot("t6_kreuzung_scramble.png")})
		_steps.append({"wait": 2, "do": func(): _pose(46.0, 58.5, 0.0, -0.02)})
		_steps.append({"wait": 20, "do": func(): _shot("t8_scramble_augenhoehe.png")})
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
