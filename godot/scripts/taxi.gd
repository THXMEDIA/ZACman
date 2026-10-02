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
var base_coord := 0.0 # the street's own centerline — world Z (axis=="row") or world X (axis=="col")
var lane_offset := 0.0 # distance off base_coord this vehicle's lane sits at, sign following `dir` (see _apply_lane)
var fixed_coord := 0.0 # base_coord +/- lane_offset — the actual coordinate driven on, recomputed on every direction change
var min_coord := 0.0
var max_coord := 0.0
var pos_along := 0.0
var dir := 1.0
var speed := 3.0
var word_mesh: MeshInstance3D

## Traffic variety: any vehicle is still just its own name driving up and
## down a lane, but the word and color can change — e.g. "VERYLONGLIMOUSINE"
## in chrome/silver reads as a long car simply because the word itself is
## long, with zero extra geometry work.
##
## `lane_offset` (per user request: streets need real traffic lanes, not one
## shared centerline) shifts this vehicle off the street's own centerline —
## to one side if moving one way, the other side if moving the other —
## so opposing traffic uses two visibly separate lanes rather than sharing a
## single line down the middle (and leaves the centerline/sidewalk-adjacent
## space clear for pedestrians — see Main.MANHATTAN_SIDEWALK_OFFSET). The
## lane is tied to `dir`, not fixed at spawn, so a vehicle that reaches the
## end of its street and turns back around switches to the correct lane for
## its new direction instead of driving back on the wrong side.
func setup(p_axis: String, p_fixed_coord: float, p_min: float, p_max: float, p_speed: float, vehicle_word: String = "TAXI", color: Color = Color(1.0, 0.82, 0.05), font_size: int = 30, p_lane_offset: float = 0.0) -> void:
	axis = p_axis
	base_coord = p_fixed_coord
	lane_offset = p_lane_offset
	min_coord = p_min
	max_coord = p_max
	speed = p_speed
	pos_along = lerpf(min_coord, max_coord, randf())
	dir = 1.0 if randf() > 0.5 else -1.0
	_apply_lane()

	word_mesh = WordMeshScript.build(vehicle_word, color, {"font_size": font_size, "depth": 0.22, "emission_energy": 1.0})
	add_child(word_mesh)
	_apply_position()


func update(delta: float) -> void:
	pos_along += dir * speed * delta
	if pos_along > max_coord:
		pos_along = max_coord
		dir = -1.0
		_apply_lane()
	elif pos_along < min_coord:
		pos_along = min_coord
		dir = 1.0
		_apply_lane()
	_apply_position()


func _apply_lane() -> void:
	fixed_coord = base_coord + (lane_offset if dir > 0.0 else -lane_offset)


func _apply_position() -> void:
	if axis == "row":
		position = Vector3(pos_along, 0.5, fixed_coord)
		rotation.y = 0.0 if dir > 0.0 else PI
	else:
		position = Vector3(fixed_coord, 0.5, pos_along)
		rotation.y = PI / 2.0 if dir > 0.0 else -PI / 2.0
