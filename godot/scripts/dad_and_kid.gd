extends Node3D
## DadAndKid — a composite Manhattan obstacle: a dad and his kid, walking
## together. The dad is the word "DAD" stacked vertically letter-by-letter
## (top to bottom, like ManWalkingDog's "MAN" totem), the kid is a single
## smaller "KID" word right beside him. Same interface as Pedestrian/
## ManWalkingDog/KidGroup (position + update(delta, now)).
##
## setup()'s single-Vector3 signature spawns it stationary (bob only); an
## optional walk_axis makes it walk a sidewalk lane back and forth exactly
## like the other obstacles — see pedestrian.gd's header for why this stays
## backward-compatible with any caller that only passes a position.

const WordMeshScript := preload("res://scripts/word_mesh.gd")

var _bob_seed := 0.0
var dad_letters: Node3D
var kid_mesh: MeshInstance3D

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

	# The dad: each letter of "DAD" stacked top-to-bottom, same totem
	# technique as ManWalkingDog's "MAN".
	dad_letters = Node3D.new()
	add_child(dad_letters)
	var letters := "DAD"
	var letter_h := 0.34
	for i in letters.length():
		var lw: MeshInstance3D = WordMeshScript.build(letters[i], Color(0.55, 0.75, 1.0), {"font_size": 20, "depth": 0.14, "emission_energy": 0.6})
		lw.position = Vector3(0.0, (letters.length() - 1 - i) * letter_h, 0.0)
		dad_letters.add_child(lw)

	# The kid: smaller, right beside him, holding pace.
	kid_mesh = WordMeshScript.build("KID", Color(1.0, 0.55, 0.75), {"font_size": 15, "depth": 0.11, "emission_energy": 0.7})
	kid_mesh.position = Vector3(0.5, 0.0, 0.0)
	kid_mesh.rotation.y = PI / 2.0
	add_child(kid_mesh)
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
	dad_letters.position.y = bob
	kid_mesh.position.y = sin(now * 3.5 + _bob_seed) * 0.05


func _apply_walk_position() -> void:
	if _walk_axis == "row":
		position = Vector3(_pos_along, _base_y, _fixed_coord)
		rotation.y = 0.0 if _walk_dir > 0.0 else PI
	elif _walk_axis == "col":
		position = Vector3(_fixed_coord, _base_y, _pos_along)
		rotation.y = PI / 2.0 if _walk_dir > 0.0 else -PI / 2.0
