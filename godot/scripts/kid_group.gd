extends Node3D
## KidGroup — a composite Manhattan obstacle: a small cluster of children,
## represented as three "KID" word meshes at small random offsets and a
## smaller scale than an adult Pedestrian. Same interface as Pedestrian/
## ManWalkingDog (position + update(delta, now)).
##
## setup()'s original single-Vector3 signature still spawns it stationary
## (bob only); an optional walk_axis makes the whole group walk a sidewalk
## lane back and forth exactly like Pedestrian/Taxi do.

const WordMeshScript := preload("res://scripts/word_mesh.gd")

const KID_COUNT := 3
const KID_COLOR := Color(1.0, 0.55, 0.75)

var _bob_seed := 0.0
var kid_meshes: Array = []

var _walk_axis := ""
var _fixed_coord := 0.0
var _min_coord := 0.0
var _max_coord := 0.0
var _pos_along := 0.0
var _walk_dir := 1.0
var _walk_speed := 0.0
var _base_y := 0.0


func setup(cell_world_pos: Vector3, walk_axis: String = "", walk_min: float = 0.0, walk_max: float = 0.0, walk_speed: float = 0.0) -> void:
	_bob_seed = randf() * 10.0
	_base_y = cell_world_pos.y
	_walk_axis = walk_axis
	_min_coord = walk_min
	_max_coord = walk_max
	_walk_speed = walk_speed
	_walk_dir = 1.0 if randf() > 0.5 else -1.0
	if _walk_axis == "row":
		_fixed_coord = cell_world_pos.z
		_pos_along = lerpf(_min_coord, _max_coord, randf())
	elif _walk_axis == "col":
		_fixed_coord = cell_world_pos.x
		_pos_along = lerpf(_min_coord, _max_coord, randf())
	position = cell_world_pos

	kid_meshes.clear()
	for i in KID_COUNT:
		var km: MeshInstance3D = WordMeshScript.build("KID", KID_COLOR, {"font_size": 14, "depth": 0.1, "emission_energy": 0.7})
		var angle: float = (TAU / KID_COUNT) * i + randf() * 0.5
		var radius := 0.28
		km.position = Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		km.rotation.y = randf() * TAU
		add_child(km)
		kid_meshes.append(km)
	_apply_walk_position()


func update(delta: float, now: float) -> void:
	if _walk_axis != "":
		_pos_along += _walk_dir * _walk_speed * delta
		if _pos_along > _max_coord:
			_pos_along = _max_coord
			_walk_dir = -1.0
		elif _pos_along < _min_coord:
			_pos_along = _min_coord
			_walk_dir = 1.0
		_apply_walk_position()

	for i in kid_meshes.size():
		var km: MeshInstance3D = kid_meshes[i]
		km.position.y = sin(now * 3.5 + _bob_seed + i * 1.3) * 0.05


func _apply_walk_position() -> void:
	if _walk_axis == "row":
		position = Vector3(_pos_along, _base_y, _fixed_coord)
	elif _walk_axis == "col":
		position = Vector3(_fixed_coord, _base_y, _pos_along)
