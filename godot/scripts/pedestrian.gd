extends Node3D
## Pedestrian — a stationary Manhattan obstacle: the word PERSON. Blocks
## the player exactly like a taxi does (see Main._check_manhattan_obstacles)
## but never costs a life; a small idle bob is its only motion.

const WordMeshScript := preload("res://scripts/word_mesh.gd")

var _bob_seed := 0.0
var word_mesh: MeshInstance3D


func setup(cell_world_pos: Vector3) -> void:
	position = cell_world_pos
	_bob_seed = randf() * 10.0
	word_mesh = WordMeshScript.build("PERSON", Color(0.75, 0.85, 1.0), {"font_size": 22, "depth": 0.16, "emission_energy": 0.6})
	add_child(word_mesh)


func update(_delta: float, now: float) -> void:
	var bob := sin(now * 2.0 + _bob_seed) * 0.03
	word_mesh.position.y = bob
