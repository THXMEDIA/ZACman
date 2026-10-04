# Rendert die Prototyp-Ansichten einer Richtung. Aufruf (siehe render.sh):
#   SHOT_DIR=... SHOT_NAME=richtung xvfb-run -a -s "-screen 0 1280x720x24" \
#     godot --rendering-driver opengl3 --path <proj> --resolution 1280x720 --script res://shot.gd
# Die Kamerapositionen liefert city.gd ueber views() -> [[name, pos, look_at, fov], ...].
extends SceneTree

const CityScript := preload("res://city.gd")

var city: Node3D
var frame := 0
var views := []
var vi := 0
var out_dir := ""
var name_ := ""
var WAIT := 18 # Frames je Ansicht (Shader-Kompilierung, TIME-Animationen laufen weiter); SHOT_WAIT ueberschreibt

func _initialize() -> void:
	out_dir = OS.get_environment("SHOT_DIR")
	name_ = OS.get_environment("SHOT_NAME")
	if OS.get_environment("SHOT_WAIT") != "":
		WAIT = int(OS.get_environment("SHOT_WAIT"))
	var only := OS.get_environment("SHOT_ONLY")
	city = CityScript.new()
	root.add_child(city)
	for v in city.views():
		if only == "" or only.find(v[0]) >= 0:
			views.append(v)

func _process(_d: float) -> bool:
	frame += 1
	if OS.get_environment("SHOT_DEBUG") != "":
		print("frame ", frame, " t=", Time.get_ticks_msec())
	if vi >= views.size():
		quit()
		return false
	var v = views[vi]
	if frame % WAIT == 2:
		city.set_view(v[1], v[2], v[3])
	elif frame % WAIT == WAIT - 1:
		var img := root.get_viewport().get_texture().get_image()
		var p := out_dir.path_join("%s.png" % v[0])
		img.save_png(p)
		print("SHOT ", p)
		vi += 1
	return false
