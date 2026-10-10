extends Node3D
## ArenaWorld — what exists only in an Arena round (Versus mode "Arena", ZAP-9,
## docs/design/versus-waffen-v1.md): both players in ONE maze.
##   - the opponent: a glowing figure with a name tag, a solid body (you can
##     not walk through him; a dash passes) that follows his position messages
##   - the split of the pellets (MazeView.arena_split) and the second start cell
##   - the ghosts: the HOST simulates them and hunts whoever is nearer; the
##     client only moves puppets along the host's snapshots. Each player
##     decides his own lives (trust-based like the rest of Versus); a ghost that
##     caught somebody goes home for a while, so the other one is not hit by it
##     in the same breath.
## Main calls the hooks (prepare_level, update_ghosts, on_pickups, …) only when
## an Arena round is on; VersusController owns this node.

const CELL := 2.0
const OPP_COLOR := Color("ff9f1c")
## A ghost that caught a player rests in the house this long.
const GHOST_HOME_S := 3.0
const EATEN_S := 2.2
## After my own power pellet the host's snapshot may still say "no power" for a
## moment (a round trip): it is ignored this long.
const POWER_GRACE_S := 1.0
const BODY_RADIUS := 0.34
const SNAP_DIST := 4.0

var main: Node
var session: Node
var my_start := Vector2i.ZERO
var opp_start := Vector2i.ZERO
var opp_name := "Gegner"

var figure: Node3D
var body: AnimatableBody3D
var name_label: Label3D
var _target := Vector3.ZERO
var _target_yaw := 0.0
var _has_pos := false
var _power_grace_until := 0.0
## Counters for tests.
var snapshots_applied := 0
var hits_sent := 0


func setup(main_node: Node, session_node: Node) -> void:
	main = main_node
	session = session_node
	session.opponent_pos.connect(on_opponent_pos)
	session.opponent_ate.connect(on_opponent_ate)
	session.ghosts_received.connect(on_ghosts_received)
	session.ghost_event.connect(on_ghost_event)
	_build_figure()


func _build_figure() -> void:
	figure = Node3D.new()
	figure.name = "Gegner"
	add_child(figure)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = OPP_COLOR
	mat.emission_enabled = true
	mat.emission = OPP_COLOR
	mat.emission_energy_multiplier = 0.9
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.3
	capsule.height = 1.5
	var mi := MeshInstance3D.new()
	mi.mesh = capsule
	mi.material_override = mat
	mi.position = Vector3(0, 0.8, 0)
	figure.add_child(mi)
	# a visor on the front (-Z, where the player looks at yaw 0) shows his facing
	var visor := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.42, 0.12, 0.2)
	visor.mesh = box
	var vmat := StandardMaterial3D.new()
	vmat.albedo_color = Color(0.05, 0.05, 0.08)
	vmat.emission_enabled = true
	vmat.emission = Color(1, 1, 1)
	vmat.emission_energy_multiplier = 0.6
	visor.material_override = vmat
	visor.position = Vector3(0, 1.3, -0.26)
	figure.add_child(visor)
	var light := OmniLight3D.new()
	light.light_color = OPP_COLOR
	light.omni_range = 3.0
	light.light_energy = 0.6
	light.position = Vector3(0, 1.0, 0)
	figure.add_child(light)
	name_label = Label3D.new()
	name_label.text = opp_name
	name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	name_label.pixel_size = 0.008
	name_label.font_size = 56
	name_label.modulate = OPP_COLOR
	name_label.outline_size = 12
	name_label.position = Vector3(0, 2.05, 0)
	figure.add_child(name_label)
	# the solid body: layer 3 (value 4), the player's mask sees it (player_controller)
	body = AnimatableBody3D.new()
	body.collision_layer = 4
	body.collision_mask = 0
	var shape := CylinderShape3D.new()
	shape.radius = BODY_RADIUS
	shape.height = 2.0
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	body.position = Vector3(0, 1.0, 0)
	figure.add_child(body)


## ---- level setup (Main.start_level) ----------------------------------------------

## Called by Main right after the maze is built: splits the pellets, picks the
## two start cells (host = the level's usual one) and returns mine.
func prepare_level() -> Vector2i:
	var maze_view = main.maze_view
	var a: Vector2i = main.start_cell
	var b: Vector2i = maze_view.arena_second_start(main.maze, a)
	my_start = a if session.is_host else b
	opp_start = b if session.is_host else a
	maze_view.arena_split(0 if session.is_host else 1, OPP_COLOR, [b])
	opp_name = session.opp_name
	name_label.text = opp_name
	place_opponent(opp_start)
	return my_start


func place_opponent(cell: Vector2i) -> void:
	_target = Vector3(cell.y * CELL, 0.0, cell.x * CELL)
	_target_yaw = 0.0
	_has_pos = false
	figure.position = _target
	figure.visible = true


func set_active(on: bool) -> void:
	figure.visible = on
	body.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
	body.collision_layer = 4 if on else 0
	main.player.set_opponent_solid(on)


## ---- the opponent -------------------------------------------------------------------

func on_opponent_pos(x: float, z: float, yaw: float) -> void:
	_target = Vector3(x, 0.0, z)
	_target_yaw = yaw
	if not _has_pos:
		_has_pos = true
		figure.position = _target


func opponent_cell() -> Vector2i:
	return Vector2i(int(round(_target.z / CELL)), int(round(_target.x / CELL)))


func on_opponent_ate(cell: Vector2i) -> void:
	main.maze_view.arena_opp_ate(cell)


func _process(delta: float) -> void:
	if figure == null or not figure.visible:
		return
	var d := Vector2(figure.position.x - _target.x, figure.position.z - _target.z).length()
	if d > SNAP_DIST:
		figure.position = _target
	else:
		figure.position = figure.position.lerp(_target, 1.0 - exp(-delta * 14.0))
	figure.rotation.y = lerp_angle(figure.rotation.y, _target_yaw, 1.0 - exp(-delta * 14.0))


## Every frame of my running round (VersusController.tick): my position out.
func send_my_position() -> void:
	var p: Vector3 = main.player.global_position
	session.send_pos(p.x, p.z, main.player.yaw)


## ---- ghosts ---------------------------------------------------------------------------

## The player the ghost hunts: whoever is nearer (air distance, cells).
func target_for(e, my_cell: Vector2i) -> Vector2i:
	var opp := opponent_cell()
	var g := Vector2(e.target_c, e.target_r)
	var d_me := g.distance_squared_to(Vector2(my_cell.y, my_cell.x))
	var d_opp := g.distance_squared_to(Vector2(opp.y, opp.x))
	return my_cell if d_me <= d_opp else opp


## The ghost speed factor of both players' rabbit conditions together.
func ghost_scale() -> float:
	var mine: float = main.active_condition.ghost_speed_scale() if main.active_condition != null else 1.0
	return clampf(mine * session.opp_gscale, 0.2, 3.0)


## Main._process in an Arena round: the host simulates the ghosts, the client
## moves puppets; both check whether a ghost caught THEIR player.
func update_ghosts(delta: float, frightened_active: bool) -> void:
	var ww: float = main.maze.cols * CELL
	var my_cell: Vector2i = main.player.cell()
	var gs := ghost_scale()
	for idx in main.enemies.size():
		var e = main.enemies[idx]
		if session.is_host:
			e.speed_scale = gs
			e.update(delta, main.maze, target_for(e, my_cell), frightened_active, main.now, ww)
			if e.mode == "eaten" and main.now >= e.eaten_until:
				e.send_to_house(_house_cell(idx), main.now, 3.0)
		else:
			e.speed_scale = _client_speed
			e.puppet_update(delta, main.now, ww)
		_check_hit(e, idx, frightened_active)
		if not main.running:
			return


var _client_speed := 1.0


func _house_cell(idx: int) -> Vector2i:
	var m = main.maze
	var cells: Array = []
	for r in range(m.house.r0 + 1, m.house.r1):
		for c in range(m.house.c0 + 1, m.house.c1):
			cells.append(Vector2i(r, c))
	return cells[idx % cells.size()]


func _check_hit(e, idx: int, frightened_active: bool) -> void:
	if e.mode == "eaten" or e.mode == "house":
		return
	if main.now <= main.invuln_until:
		return
	var d := Vector2(e.position.x - main.player.global_position.x, e.position.z - main.player.global_position.z).length()
	if d >= main.ENEMY_HIT_RADIUS:
		return
	if frightened_active or e.mode == "frightened":
		e.mode = "eaten"
		e.eaten_until = main.now + EATEN_S
		if e.puppet:
			e.apply_look()
		main.combo_count += 1
		main.player.add_dash_charge()
		Sfx.eat_enemy()
		if not session.is_host:
			session.send_ghost_event("ate", idx)
	elif main.player.is_dash_protected():
		return
	else:
		hits_sent += 1
		if session.is_host:
			e.send_to_house(_house_cell(idx), main.now, GHOST_HOME_S)
		else:
			session.send_ghost_event("hit", idx) # the invulnerability after the hit covers the round trip
		main.lose_life()


## Host: the snapshots to the client (VersusController.tick).
func send_ghost_state() -> void:
	if not session.is_host:
		return
	var list: Array = []
	for e in main.enemies:
		list.append(e.snapshot())
	var f: float = maxf(main.frightened_until - main.now, 0.0)
	session.send_ghosts(list, f, ghost_scale())


## Client: the host's ghosts arrived.
func on_ghosts_received(list: Array, frightened: float, gscale: float) -> void:
	if session.is_host or main.enemies.is_empty():
		return
	for i in mini(list.size(), main.enemies.size()):
		var e = main.enemies[i]
		# a ghost I just sent home or just ate keeps that until the host agrees
		e.apply_snapshot(list[i])
	_client_speed = gscale
	snapshots_applied += 1
	if frightened > 0.0 or main.now >= _power_grace_until:
		main.frightened_until = main.now + frightened


## Host: the client's ghost events.
func on_ghost_event(kind: String, index: int) -> void:
	if not session.is_host:
		return
	match kind:
		"hit":
			if index < main.enemies.size():
				main.enemies[index].send_to_house(_house_cell(index), main.now, GHOST_HOME_S)
		"ate":
			if index < main.enemies.size():
				var e = main.enemies[index]
				if e.mode == "frightened":
					e.mode = "eaten"
					e.eaten_until = main.now + EATEN_S
		"power":
			main.frightened_until = main.now + main.FRIGHTENED_DURATION
			for e in main.enemies:
				if e.mode == "chase":
					e.mode = "frightened"


## Main._check_pickups in an Arena round: what I ate goes to the opponent; a
## power pellet opens the ghosts' window (on the host directly, the client asks).
func on_pickups(result: Dictionary) -> void:
	for cell in result.cells:
		session.send_eat(cell)
	if result.power and not session.is_host:
		_power_grace_until = main.now + POWER_GRACE_S
		session.send_ghost_event("power", 0, ghost_scale())
