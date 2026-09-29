extends Node3D
## Taxi — an ambient, harmless Manhattan obstacle: the word TAXI itself,
## driving back and forth along one avenue or street. Manhattan has no
## ghosts (see manhattan_maze.gd / Main.start_manhattan_level — the level
## is "a calm explorer"), so taxis and pedestrians (pedestrian.gd) are its
## only moving/blocking dressing: Main pushes the player out from under
## them (see Main._check_manhattan_obstacles) but never costs a life for
## touching one.

const WordMeshScript := preload("res://scripts/word_mesh.gd")

var axis := "row" # "row": runs along a fixed street (east-west); "col": along a fixed avenue (north-south)
var fixed_coord := 0.0 # world Z (axis=="row") or world X (axis=="col") that stays constant
var min_coord := 0.0
var max_coord := 0.0
var pos_along := 0.0
var dir := 1.0
var speed := 3.0
var word_mesh: MeshInstance3D


func setup(p_axis: String, p_fixed_coord: float, p_min: float, p_max: float, p_speed: float) -> void:
	axis = p_axis
	fixed_coord = p_fixed_coord
	min_coord = p_min
	max_coord = p_max
	speed = p_speed
	pos_along = lerpf(min_coord, max_coord, randf())
	dir = 1.0 if randf() > 0.5 else -1.0

	word_mesh = WordMeshScript.build("TAXI", Color(1.0, 0.82, 0.05), {"font_size": 30, "depth": 0.22, "emission_energy": 1.0})
	add_child(word_mesh)
	_apply_position()


func update(delta: float) -> void:
	pos_along += dir * speed * delta
	if pos_along > max_coord:
		pos_along = max_coord
		dir = -1.0
	elif pos_along < min_coord:
		pos_along = min_coord
		dir = 1.0
	_apply_position()


func _apply_position() -> void:
	if axis == "row":
		position = Vector3(pos_along, 0.5, fixed_coord)
		rotation.y = 0.0 if dir > 0.0 else PI
	else:
		position = Vector3(fixed_coord, 0.5, pos_along)
		rotation.y = PI / 2.0 if dir > 0.0 else -PI / 2.0
