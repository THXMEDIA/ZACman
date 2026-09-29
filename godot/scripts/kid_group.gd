extends Node3D
## KidGroup — a composite stationary Manhattan obstacle: a small cluster of
## children, represented as three "KID" word meshes at small random offsets
## and a smaller scale than an adult Pedestrian. Same interface as
## Pedestrian/ManWalkingDog (position + update(delta, now)).

const WordMeshScript := preload("res://scripts/word_mesh.gd")

const KID_COUNT := 3
const KID_COLOR := Color(1.0, 0.55, 0.75)

var _bob_seed := 0.0
var kid_meshes: Array = []


func setup(cell_world_pos: Vector3) -> void:
	position = cell_world_pos
	_bob_seed = randf() * 10.0

	kid_meshes.clear()
	for i in KID_COUNT:
		var km: MeshInstance3D = WordMeshScript.build("KID", KID_COLOR, {"font_size": 14, "depth": 0.1, "emission_energy": 0.7})
		var angle: float = (TAU / KID_COUNT) * i + randf() * 0.5
		var radius := 0.28
		km.position = Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		km.rotation.y = randf() * TAU
		add_child(km)
		kid_meshes.append(km)


func update(_delta: float, now: float) -> void:
	for i in kid_meshes.size():
		var km: MeshInstance3D = kid_meshes[i]
		km.position.y = sin(now * 3.5 + _bob_seed + i * 1.3) * 0.05
