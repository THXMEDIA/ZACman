extends Node
## EtagenSpike — ZAP-7: a second maze floor above the first, to test whether
## look, fog and the player's light carry over two floors (docs/design/
## etagen-spike.md). Throw-away prototype behind F4 (debug builds): it is not
## part of any level, board or save.
##
## Floor 0 is the normal level (ghosts, rabbit, pellets). Floor 1 is a second,
## ghost-free maze of the same size, FLOOR_DY metres higher, with its own
## pellets. They are joined by a few ELEVATOR cells that are open on both
## floors: stepping onto one cuts to the other floor (no ride, no camera
## movement — the player's yaw/pitch are never touched, E8e), then the
## elevator is dead for LOCK_S and until the player has stepped off it.

const MazeViewScript := preload("res://scripts/maze_view.gd")
const LevelsScript := preload("res://scripts/levels.gd")

const FLOOR_DY := 12.0
const LOCK_S := 1.0
const ELEVATOR_COUNT := 3
const CELL := 2.0

var main: Node
var maze_up
var view_up: Node3D
var elev_cells: Array = [] # Array[Vector2i]
var floor_index := 0
var lock_until := 0.0
var armed := true
var _marks: Array = [] # Node3D markers on both floors
var _view_down: Node3D


## Builds floor 1 and the elevators for the running level of `main_node`.
func start(main_node: Node) -> void:
	main = main_node
	_view_down = main.maze_view
	var lv: Dictionary = main.current_level
	var opts: Dictionary = LevelsScript.maze_opts(lv)
	maze_up = MazeGen.generate_maze(main.maze.rows, main.maze.cols, int(lv.seed) + 777, opts)
	view_up = Node3D.new()
	view_up.set_script(MazeViewScript)
	main.add_child(view_up)
	view_up.position = Vector3(0, FLOOR_DY, 0)
	view_up.build(maze_up, main.start_cell, "normal", [], [], int(lv.seed) + 777, "riff")
	view_up.visible = false
	elev_cells = _pick_elevator_cells()
	for c in elev_cells:
		_add_marker(main.maze_view, c)
		_add_marker(view_up, c)
	floor_index = 0
	armed = true
	lock_until = 0.0
	main.hud.set_floor_label("E1")


func active() -> bool:
	return view_up != null and is_instance_valid(view_up)


func teardown() -> void:
	if main != null and main.player != null and floor_index != 0:
		var p = main.player
		p.global_position.y = p.eye_h
	for m in _marks:
		if is_instance_valid(m):
			m.queue_free()
	_marks.clear()
	if view_up != null and is_instance_valid(view_up):
		view_up.queue_free()
	view_up = null
	maze_up = null
	elev_cells.clear()
	floor_index = 0
	if _view_down != null and is_instance_valid(_view_down):
		_view_down.visible = true
	if main != null and main.hud != null:
		main.hud.set_floor_label("")


## Cells that are open on both floors and not in a ghost house, spread out by
## their distance from the start cell (30 %, 60 %, 90 % of the sorted list).
func _pick_elevator_cells() -> Array:
	var cand: Array = []
	var s: Vector2i = main.start_cell
	for r in main.maze.rows:
		for c in main.maze.cols:
			if main.maze.grid[r][c] != 0 or maze_up.grid[r][c] != 0:
				continue
			if _in_house(main.maze, r, c) or _in_house(maze_up, r, c):
				continue
			cand.append(Vector2i(r, c))
	cand.sort_custom(func(a: Vector2i, b: Vector2i): return (a - s).length_squared() < (b - s).length_squared())
	var out: Array = []
	if cand.is_empty():
		return out
	for i in ELEVATOR_COUNT:
		var idx := clampi(int(float(cand.size()) * (0.3 + 0.3 * i)), 0, cand.size() - 1)
		out.append(cand[idx])
	return out


func _in_house(m, r: int, c: int) -> bool:
	return r >= m.house.r0 and r <= m.house.r1 and c >= m.house.c0 and c <= m.house.c1


func _add_marker(parent: Node3D, cell: Vector2i) -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.72, 0.2)
	var root := Node3D.new()
	root.position = Vector3(cell.y * CELL, 0.0, cell.x * CELL)
	var pad := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.75
	pm.bottom_radius = 0.75
	pm.height = 0.05
	pad.mesh = pm
	pad.material_override = mat
	pad.position.y = 0.04
	root.add_child(pad)
	var beam := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.06
	bm.bottom_radius = 0.06
	bm.height = 3.2
	beam.mesh = bm
	beam.material_override = mat
	beam.position.y = 1.7
	root.add_child(beam)
	parent.add_child(root)
	_marks.append(root)


## Once per frame: the elevator check.
func update(now: float) -> void:
	if not active() or elev_cells.is_empty():
		return
	var pc: Vector2i = main.player.cell()
	var on_pad := elev_cells.has(pc)
	if not on_pad:
		armed = true
		return
	if not armed or now < lock_until:
		return
	switch_floor(now)


func switch_floor(now: float) -> void:
	floor_index = 1 - floor_index
	armed = false
	lock_until = now + LOCK_S
	var p = main.player
	p.global_position.y = p.eye_h + (FLOOR_DY if floor_index == 1 else 0.0)
	_view_down.visible = floor_index == 0
	view_up.visible = floor_index == 1
	main.hud.set_floor_label("E%d" % (floor_index + 1))


## Pellets of floor 1 (visual test only, no score).
func consume_up(now: float) -> void:
	var pos: Vector3 = main.player.global_position
	var res: Dictionary = view_up.consume_at(Vector3(pos.x, 0.0, pos.z), now)
	if res.pellet or res.power:
		Sfx.munch()
