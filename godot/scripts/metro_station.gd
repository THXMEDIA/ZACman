extends Node3D
## MetroStation — a glowing, pulsating "SUBWAY" sign marking a metro-station
## entrance in the Manhattan bonus level. Stationary; Main checks player
## proximity each frame (see Main._check_metro_entry) and, when the player
## steps onto one, ends the Manhattan run and drops them back into the
## normal speedrun progression.

const WordMeshScript := preload("res://scripts/word_mesh.gd")

const SIGN_COLOR := Color(0.1, 1.0, 0.85) # neon teal — reads distinctly from the landmark/building neon palette
const PULSE_SPEED := 3.6
const PULSE_BASE := 1.4
const PULSE_AMPLITUDE := 1.1

var word_mesh: MeshInstance3D
var light: OmniLight3D
var _seed := 0.0


func setup(cell_world_pos: Vector3) -> void:
	position = cell_world_pos
	_seed = randf() * 10.0

	word_mesh = WordMeshScript.build("SUBWAY", SIGN_COLOR, {"font_size": 20, "depth": 0.18, "emission_energy": PULSE_BASE})
	word_mesh.position = Vector3(0.0, 0.15, 0.0)
	add_child(word_mesh)

	light = OmniLight3D.new()
	light.light_color = SIGN_COLOR
	light.omni_range = 3.0
	light.light_energy = PULSE_BASE
	word_mesh.add_child(light)


func update(_delta: float, now: float) -> void:
	var pulse: float = PULSE_BASE + sin(now * PULSE_SPEED + _seed) * PULSE_AMPLITUDE * 0.5 + PULSE_AMPLITUDE * 0.5
	word_mesh.mesh.material.emission_energy_multiplier = pulse
	light.light_energy = pulse
