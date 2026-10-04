# QA-/Art-Screenshots der Explorer-Stadt Kyoto („Aizuri-Pop-up“).
# Aufruf aus dem Repo-Wurzelverzeichnis:
#   cp tools/qa/qa_kyoto_shots.gd godot/qa_kyoto_shots.gd
#   SHOT_DIR=/pfad xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-driver opengl3 \
#     --path godot --resolution 1280x720 --fixed-fps 60 --script res://qa_kyoto_shots.gd
#   rm godot/qa_kyoto_shots.gd
#   k1_start.png          Startscreen mit Explorer-Auswahl (drei Städte)
#   k2_spawn.png          erster Blick nach dem Start (Shijo-dori, Theater im Rücken)
#   k3_shijo_tor.png      Shijo-dori nach Osten, Schreintor am Ende
#   k4_hanamikoji.png     Hanamikoji nach Süden, Tempeltor am Ende
#   k5_pagode.png         Yasaka-dori nach Osten auf die Pagode
#   k6_torii.png          Torii-Gasse nach Westen
#   k7_kiyomizu_ausgang.png  Ninenzaka (Süd) nach Süden: Kiyomizu-Bühne, Lesebändchen, Ausgang
#   k2_spawn.png zeigt das Aufklappen (Intro, ~1 s nach dem Start)
#   k8_totale.png         erhöhte Totale (Falten relativ zu einem gedachten Spieler)
#   k9_reduziert.png      wie k3 mit „Effekte reduzieren“ (alles steht)
#   k10_theater.png       Shijo-dori nach Westen auf das Theater
#   k11-k15               Regressionsblicke: Torii-Rand, Pagode vom Hanamikoji,
#                         Ninenzaka Nord, Sannenzaka (Band), Start mit Blick aufs Tor
extends SceneTree

var main: Node
var frame := 0
var out_dir := ""
var _steps: Array = []
var _step_i := 0
var _wait_until := 0


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


func _fold_center(on: bool, p: Vector3 = Vector3.ZERO) -> void:
	var sr = main.maze_view.scenery_root
	sr.card_material.set_shader_parameter("use_fold_center", 1.0 if on else 0.0)
	sr.card_material.set_shader_parameter("fold_center", p)


func _plan() -> void:
	var E := -PI * 0.5
	var W := PI * 0.5
	var S := PI
	_steps.append({"wait": 40, "do": func(): _shot("k1_start.png")})
	_steps.append({"wait": 5, "do": func():
		main.seed_randomness(4242)
		main.begin_explorer_game("kyoto")})
	_steps.append({"wait": 60, "do": func(): _shot("k2_spawn.png")})
	_steps.append({"wait": 2, "do": func(): _pose(60.0, 20.0, E, 0.06)})
	_steps.append({"wait": 20, "do": func(): _shot("k3_shijo_tor.png")})
	_steps.append({"wait": 2, "do": func(): _pose(46.0, 30.0, S, 0.04)})
	_steps.append({"wait": 20, "do": func(): _shot("k4_hanamikoji.png")})
	_steps.append({"wait": 2, "do": func(): _pose(52.0, 62.0, E, 0.12)})
	_steps.append({"wait": 20, "do": func(): _shot("k5_pagode.png")})
	_steps.append({"wait": 2, "do": func(): _pose(40.0, 78.0, W, 0.03)})
	_steps.append({"wait": 20, "do": func(): _shot("k6_torii.png")})
	_steps.append({"wait": 2, "do": func(): _pose(88.0, 73.0, S, 0.1)})
	_steps.append({"wait": 20, "do": func(): _shot("k7_kiyomizu_ausgang.png")})
	_steps.append({"wait": 2, "do": func():
		_fold_center(true, Vector3(46.0, 1.0, 26.0))
		_pose(14.0, -10.0, deg_to_rad(-135.0), -0.5, 26.0)})
	_steps.append({"wait": 20, "do": func(): _shot("k8_totale.png")})
	_steps.append({"wait": 2, "do": func():
		_fold_center(false)
		main.set_reduce_fx(true)
		_pose(60.0, 20.0, E, 0.06)})
	_steps.append({"wait": 20, "do": func(): _shot("k9_reduziert.png")})
	_steps.append({"wait": 2, "do": func():
		main.set_reduce_fx(false)
		_pose(40.0, 20.0, W, 0.08)})
	_steps.append({"wait": 20, "do": func(): _shot("k10_theater.png")})
	# regression views from QA (04.10.): torii edge, pagoda from Yasaka-dori
	# entrance, Ninenzaka north, Sannenzaka east (ribbon)
	_steps.append({"wait": 2, "do": func(): _pose(30.0, 79.6, W, 0.02)})
	_steps.append({"wait": 20, "do": func(): _shot("k11_torii_rand.png")})
	_steps.append({"wait": 2, "do": func(): _pose(46.0, 62.0, E, 0.12)})
	_steps.append({"wait": 20, "do": func(): _shot("k12_pagode_von_hanamikoji.png")})
	_steps.append({"wait": 2, "do": func(): _pose(88.0, 30.0, S, 0.1)})
	_steps.append({"wait": 20, "do": func(): _shot("k13_ninenzaka_nord.png")})
	_steps.append({"wait": 2, "do": func(): _pose(56.0, 74.0, E, 0.1)})
	_steps.append({"wait": 20, "do": func(): _shot("k14_sannenzaka_band.png")})
	_steps.append({"wait": 2, "do": func(): _pose(8.0, 20.0, E, 0.04)})
	_steps.append({"wait": 20, "do": func(): _shot("k15_start_fern.png")})
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
