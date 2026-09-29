extends Node3D
## ManWalkingDog — a composite stationary Manhattan obstacle: a man and his
## dog. The man is the word "MAN" stacked vertically letter-by-letter (top
## to bottom, like a little totem), the dog is the word "DOG" laid out
## normally on the ground right beside him. Same interface as Pedestrian
## (position + update(delta, now)) so Main can treat every obstacle kind
## identically in _check_manhattan_obstacles / the pedestrians array.

const WordMeshScript := preload("res://scripts/word_mesh.gd")

var _bob_seed := 0.0
var man_letters: Node3D
var dog_mesh: MeshInstance3D


func setup(cell_world_pos: Vector3) -> void:
	position = cell_world_pos
	_bob_seed = randf() * 10.0

	# The man: each letter of "MAN" stacked top-to-bottom, sent down as its
	# own small extruded block so it reads as a standing figure rather than
	# a flat word lying on the ground.
	man_letters = Node3D.new()
	add_child(man_letters)
	var letters := "MAN"
	var letter_h := 0.34
	for i in letters.length():
		var lw: MeshInstance3D = WordMeshScript.build(letters[i], Color(0.8, 0.9, 1.0), {"font_size": 20, "depth": 0.14, "emission_energy": 0.6})
		lw.position = Vector3(0.0, (letters.length() - 1 - i) * letter_h, 0.0)
		man_letters.add_child(lw)

	# The dog: low to the ground, just beside the man.
	dog_mesh = WordMeshScript.build("DOG", Color(0.95, 0.75, 0.4), {"font_size": 16, "depth": 0.12, "emission_energy": 0.5})
	dog_mesh.position = Vector3(0.55, 0.05, 0.0)
	dog_mesh.rotation.y = PI / 2.0
	add_child(dog_mesh)


func update(_delta: float, now: float) -> void:
	var bob := sin(now * 2.0 + _bob_seed) * 0.03
	man_letters.position.y = bob
	dog_mesh.position.y = 0.05 + sin(now * 3.2 + _bob_seed) * 0.02
