extends Node3D
## Pedestrian — the word MAN or WOMAN, walking back and forth along one
## sidewalk lane exactly like a Taxi drives its lane (see taxi.gd), just
## much slower — a small idle bob rides on top of the walking motion.
## Blocks the player exactly like a taxi does (see
## Main._check_manhattan_obstacles) but never costs a life.
##
## setup() keeps its original single-Vector3 signature working (spawns
## stationary at that exact position, bob only — see test_manhattan_
## obstacles.gd) and only starts walking a lane when a non-empty walk_axis
## is also passed, so any existing caller/test is unaffected.

const WordMeshScript := preload("res://scripts/word_mesh.gd")

var _bob_seed := 0.0
var word_mesh: MeshInstance3D

var _walk_axis := "" # "" = stationary; "row" (fixed Z, walks X) or "col" (fixed X, walks Z)
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

	var word := "MAN" if randf() > 0.5 else "WOMAN"
	word_mesh = WordMeshScript.build(word, Color(0.75, 0.85, 1.0), {"font_size": 22, "depth": 0.16, "emission_energy": 0.6})
	add_child(word_mesh)
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

	var bob := sin(now * 2.0 + _bob_seed) * 0.03
	word_mesh.position.y = bob


func _apply_walk_position() -> void:
	if _walk_axis == "row":
		position = Vector3(_pos_along, _base_y, _fixed_coord)
		word_mesh.rotation.y = 0.0 if _walk_dir > 0.0 else PI
	elif _walk_axis == "col":
		position = Vector3(_fixed_coord, _base_y, _pos_along)
		word_mesh.rotation.y = PI / 2.0 if _walk_dir > 0.0 else -PI / 2.0
