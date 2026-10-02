# Rendert die Prototyp-Ansichten. Aufruf:
#   SHOT_DIR=... SHOT_NAME=richtung xvfb-run -a -s "-screen 0 1280x720x24" \
#     godot --rendering-driver opengl3 --path <proj> --resolution 1280x720 --script res://shot.gd
extends SceneTree

const CityScript := preload("res://city.gd")
const StyleScript := preload("res://style.gd")

var city: Node3D
var frame := 0
var views := []
var vi := 0
var out_dir := ""
var name_ := ""

func _initialize() -> void:
	out_dir = OS.get_environment("SHOT_DIR")
	name_ = OS.get_environment("SHOT_NAME")
	var only := OS.get_environment("SHOT_ONLY")
	city = CityScript.new()
	city.style = StyleScript.style()
	root.add_child(city)
	var all := [
		["totale", Vector3(-5, 17, 36), Vector3(3, 2, -24), 66.0],
		["strasse", Vector3(-1.2, 1.7, 30), Vector3(1.0, 2.6, -10), 70.0],
		["kreuzung", Vector3(21, 1.7, 11.2), Vector3(-6, 3.0, -14), 72.0],
		["capsule", Vector3(-2.0, 1.75, 23), Vector3(0.8, 5.0, -20), 64.0],
		["capsulecam", Vector3(-0.6, 1.25, 29), Vector3(0.6, 5.2, -30), 56.0],
	]
	for v in all:
		if only == "" or only.find(v[0]) >= 0:
			views.append(v)

func _process(_d: float) -> bool:
	frame += 1
	if vi >= views.size():
		quit()
		return false
	var v = views[vi]
	if frame % 14 == 2:
		city.set_view(v[1], v[2], v[3])
	elif frame % 14 == 13:
		var img := root.get_viewport().get_texture().get_image()
		var p := out_dir.path_join("%s_%s.png" % [name_, v[0]])
		img.save_png(p)
		print("SHOT ", p)
		vi += 1
	return false
