extends Node3D
## ArenaWorld — what exists only in an Arena round (Versus mode "Arena", ZAP-9,
## docs/design/versus-waffen-v1.md): both players in ONE maze.
##   - the opponent: a glowing figure with a name tag, a solid body (you can
##     not walk through him; a dash passes) that follows his position messages
##   - the split of the pellets (MazeView.arena_split) and the second start cell
##   - the ghosts: the HOST simulates them; each ghost has a home player (even
##     index: host, odd: client) and only switches to the other one when he is
##     clearly nearer (hysteresis); the client only moves puppets along the
##     host's snapshots. Each player
##     decides his own lives (trust-based like the rest of Versus); a ghost that
##     caught somebody goes home for a while, so the other one is not hit by it
##     in the same breath.
## Main calls the hooks (prepare_level, update_ghosts, on_pickups, …) only when
## an Arena round is on; VersusController owns this node.

const CELL := 2.0
const VersusUIScript := preload("res://scripts/versus_ui.gd")
const OPP_COLOR := VersusUIScript.OPP_COLOR
## A ghost that caught a player rests in the house this long.
const GHOST_HOME_S := 3.0
const EATEN_S := 2.2
## After my own power pellet the host's snapshot may still say "no power" for a
## moment (a round trip): it is ignored this long.
const POWER_GRACE_S := 1.0
const BODY_RADIUS := 0.34
const SNAP_DIST := 4.0
## The figure is this much taller than the eye height: at eye level you see his
## visor, not the top of his head (UX W1).
const HEAD_ABOVE_EYE := 0.25
## After eating a ghost locally the host's snapshot may still say "frightened"
## or "chase" for a round trip: the local state wins this long, and I am safe
## from that ghost (code review W1/W2).
const EAT_LOCK_S := 0.6
## Ghost targets: switch to the other player only if he is this many cells
## nearer (air distance), and not again for TARGET_HOLD_S (game design K3).
const TARGET_SWITCH_CELLS := 4.0
const TARGET_HOLD_S := 2.0
## Standoff: after this long in contact he becomes passable for PASS_S (game
## design K4; the value is a guess for the hand test, the owner wanted collision).
const CONTACT_S := 1.5
const PASS_S := 1.0
## A client's 'ghit' only counts if the ghost is this near his reported position.
const HIT_CHECK_DIST := 3.0

var main: Node
var session: Node
var my_start := Vector2i.ZERO
var opp_start := Vector2i.ZERO
var opp_name := "Gegner"

var figure: Node3D
var body: AnimatableBody3D
var body_shape: CollisionShape3D
var name_label: Label3D
var _mi: MeshInstance3D
var _visor: MeshInstance3D
var _light: OmniLight3D
var _capsule: CapsuleMesh
var _shape: CylinderShape3D
## Height of the player's eye above the floor: the figure is as tall as that,
## so he stands as tall as the one who looks through those eyes.
var height := 2.5
var _target := Vector3.ZERO
var _target_yaw := 0.0
var _has_pos := false
var _power_grace_until := 0.0
var _house_cells: Array = []
var _bound: Array = [] # per ghost: 0 = hunts the host, 1 = the client
var _bound_hold: Array = [] # per ghost: no switch before this game time
var _eat_lock: Dictionary = {} # ghost index -> game time
var _contact := 0.0
var _pass_until := 0.0
var _clock := 0.0
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
	mat.emission_energy_multiplier = 0.4
	_capsule = CapsuleMesh.new()
	_capsule.radius = 0.3
	var mi := MeshInstance3D.new()
	mi.mesh = _capsule
	mi.material_override = mat
	_mi = mi
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
	_visor = visor
	figure.add_child(visor)
	var light := OmniLight3D.new()
	light.light_color = OPP_COLOR
	light.omni_range = 3.0
	light.light_energy = 0.35
	_light = light
	figure.add_child(light)
	name_label = Label3D.new()
	name_label.text = opp_name
	name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	name_label.fixed_size = true # the same size on screen at any distance
	name_label.pixel_size = 0.0009
	name_label.font_size = 64
	name_label.modulate = OPP_COLOR
	name_label.outline_size = 14
	figure.add_child(name_label)
	# the solid body: layer 3 (value 4), the player's mask sees it (player_controller)
	body = AnimatableBody3D.new()
	body.collision_layer = 4
	body.collision_mask = 0
	body.sync_to_physics = false # moved from _process: a synced body would be reset by the physics frame
	_shape = CylinderShape3D.new()
	_shape.radius = BODY_RADIUS
	var cs := CollisionShape3D.new()
	cs.shape = _shape
	body_shape = cs
	body.add_child(cs)
	# NOT a child of the figure: a kinematic body only follows its OWN transform
	# changes, never its parent's (the player walked through the opponent)
	add_child(body)
	fit_height(height - HEAD_ABOVE_EYE)


## Sizes the figure, his name tag and his body to the eye height `eye` (m):
## his visor sits at eye level, his head a little above.
func fit_height(eye: float) -> void:
	var h := eye + HEAD_ABOVE_EYE
	height = h
	_capsule.height = h
	_mi.position = Vector3(0, h * 0.5, 0)
	_visor.position = Vector3(0, eye, -0.27)
	_light.position = Vector3(0, h * 0.5, 0)
	name_label.position = Vector3(0, h + 0.4, 0)
	_shape.height = h + 0.2


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
	name_label.text = opp_name.to_upper() # like the race bar (UX N1)
	_client_speed = 1.0
	_eat_lock.clear()
	_contact = 0.0
	_pass_until = 0.0
	_house_cells.clear()
	var m = main.maze
	for r in range(m.house.r0 + 1, m.house.r1):
		for c in range(m.house.c0 + 1, m.house.c1):
			_house_cells.append(Vector2i(r, c))
	_bound.clear()
	_bound_hold.clear()
	fit_height(main.player.eye_h + main.player.camera.position.y) # where his eyes are
	place_opponent(opp_start)
	return my_start


func place_opponent(cell: Vector2i) -> void:
	_target = Vector3(cell.y * CELL, 0.0, cell.x * CELL)
	_target_yaw = 0.0
	_has_pos = false
	figure.position = _target
	figure.visible = true
	_sync_body()


func set_active(on: bool) -> void:
	figure.visible = on
	# not process_mode DISABLED: a disabled body keeps a stale physics transform
	# when it is enabled again (found in the screenshot test: the player walked
	# through the opponent), so only its layer and shape are switched
	body.collision_layer = 4 if on else 0
	body_shape.set_deferred("disabled", not on)
	main.player.set_opponent_solid(on)


## ---- the opponent -------------------------------------------------------------------

func on_opponent_pos(x: float, z: float, yaw: float) -> void:
	# only positions inside this maze (code review W3: a position far outside
	# would keep every ghost on me)
	if main.maze == null or x < -CELL or x > main.maze.cols * CELL or z < -CELL or z > main.maze.rows * CELL:
		return
	_target = Vector3(x, 0.0, z)
	_target_yaw = yaw
	if not _has_pos:
		_has_pos = true
		figure.position = _target
		_sync_body()


func opponent_cell() -> Vector2i:
	return Vector2i(int(round(_target.z / CELL)), int(round(_target.x / CELL)))


func opponent_yaw() -> float:
	return _target_yaw


## His pickup vanishes here. A power pellet of HIS opens the ghosts' window on
## the host — from the `eat` itself, so there is nothing extra to forge
## (code review W3).
func on_opponent_ate(cell: Vector2i) -> void:
	var kind: String = main.maze_view.arena_opp_ate_kind(cell)
	if kind == "power" and session.is_host and main.running:
		_open_power_window()
		_announce("%s: POWER · Geister fliehen" % opp_name)


func _open_power_window() -> void:
	main.frightened_until = main.now + main.FRIGHTENED_DURATION
	main.combo_count = 0
	for e in main.enemies:
		if e.mode == "chase":
			e.mode = "frightened"
	Sfx.set_siren(true, true)


func _announce(text: String) -> void:
	var vs = main.versus
	if vs != null and vs.ui != null:
		vs.ui.show_event(text.to_upper(), OPP_COLOR, 2.0)


func _sync_body() -> void:
	body.position = figure.position + Vector3(0, height * 0.5, 0)


func _process(delta: float) -> void:
	_clock += delta
	if figure == null or not figure.visible:
		return
	var d := Vector2(figure.position.x - _target.x, figure.position.z - _target.z).length()
	if d > SNAP_DIST:
		figure.position = _target
	else:
		figure.position = figure.position.lerp(_target, 1.0 - exp(-delta * 14.0))
	figure.rotation.y = lerp_angle(figure.rotation.y, _target_yaw, 1.0 - exp(-delta * 14.0))
	_sync_body()
	# the name tag steps aside when he is close (it would cover the view)
	var cam: Camera3D = main.player.camera if main != null and main.player != null else null
	if cam != null:
		var dist := cam.global_position.distance_to(figure.global_position + Vector3(0, height * 0.5, 0))
		name_label.modulate.a = clampf((dist - 2.0) / 2.0, 0.0, 1.0)
	_update_passable(delta)


## Overlap (a dash ended inside him, both respawned onto each other), my
## respawn invulnerability or a standoff of CONTACT_S make him passable for a
## moment, so nobody is pushed without input (E8e) or locked in (K4).
func _update_passable(delta: float) -> void:
	var pl = main.player if main != null else null
	if pl == null or not pl.opponent_solid:
		return
	var d := Vector2(pl.global_position.x - figure.position.x, pl.global_position.z - figure.position.z).length()
	var touching := d < BODY_RADIUS * 2.0 + 0.08
	_contact = _contact + delta if touching else 0.0
	if _contact >= CONTACT_S:
		_contact = 0.0
		_pass_until = _clock + PASS_S
	var overlapping := d < BODY_RADIUS * 2.0 - 0.06
	pl.opponent_passable = overlapping or _clock < _pass_until or main.now <= main.invuln_until


## Every frame of my running round (VersusController.tick): my position out.
func send_my_position() -> void:
	var p: Vector3 = main.player.global_position
	session.send_pos(p.x, p.z, main.player.yaw)


## ---- ghosts ---------------------------------------------------------------------------

## The player ghost `idx` hunts: its home player (even index: host, odd:
## client), or the other one when he is TARGET_SWITCH_CELLS nearer (air
## distance); after a switch it holds TARGET_HOLD_S (game design K3).
func target_for(e, idx: int, my_cell: Vector2i) -> Vector2i:
	while _bound.size() <= idx:
		_bound.append(_bound.size() & 1)
		_bound_hold.append(0.0)
	var opp := opponent_cell()
	var cells := [my_cell, opp] # 0 = host (me), 1 = client
	var g := Vector2(e.target_c, e.target_r)
	var cur: int = _bound[idx]
	var other: int = 1 - cur
	var d_cur := g.distance_to(Vector2(cells[cur].y, cells[cur].x))
	var d_other := g.distance_to(Vector2(cells[other].y, cells[other].x))
	if main.now >= _bound_hold[idx] and d_other + TARGET_SWITCH_CELLS <= d_cur:
		_bound[idx] = other
		_bound_hold[idx] = main.now + TARGET_HOLD_S
	return cells[_bound[idx]]


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
			e.update(delta, main.maze, target_for(e, idx, my_cell), frightened_active, main.now, ww)
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
	return _house_cells[idx % _house_cells.size()]


func _check_hit(e, idx: int, frightened_active: bool) -> void:
	if e.mode == "eaten" or e.mode == "house":
		return
	if main.now <= main.invuln_until:
		return
	var d := Vector2(e.position.x - main.player.global_position.x, e.position.z - main.player.global_position.z).length()
	if d >= main.ENEMY_HIT_RADIUS:
		return
	if frightened_active or e.mode == "frightened":
		if _eat_lock.get(idx, -1.0) > main.now:
			return # eaten a moment ago, the host has not answered yet
		e.mode = "eaten"
		e.eaten_until = main.now + EATEN_S
		_eat_lock[idx] = main.now + EAT_LOCK_S
		main.invuln_until = maxf(main.invuln_until, main.now + EAT_LOCK_S)
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
	if not session.is_host or not session.ghosts_due():
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
		# a ghost I just ate stays eaten until the host agrees (code review W1)
		if _eat_lock.get(i, -1.0) > main.now and int(list[i][5]) < 3:
			continue
		main.enemies[i].apply_snapshot(list[i])
	_client_speed = gscale
	snapshots_applied += 1
	var was_open: bool = main.now < main.frightened_until
	# my own fresh window is not cut short by a snapshot from before the host
	# heard of it (code review W5)
	var host_until: float = main.now + frightened
	if main.now >= _power_grace_until or host_until > main.frightened_until:
		main.frightened_until = host_until
	if not was_open and main.now < main.frightened_until and main.now >= _power_grace_until:
		Sfx.set_siren(true, true)
		_announce("%s: POWER · Geister fliehen" % opp_name)


## Host: the client's ghost events. A "hit" only counts near his position, an
## "ate" only for a frightened ghost; "power" carries only his ghost speed
## factor — the window opens with the `eat` of his power cell.
func on_ghost_event(kind: String, index: int) -> void:
	if not session.is_host or index >= main.enemies.size():
		return
	var e = main.enemies[index]
	match kind:
		"hit":
			var d := Vector2(e.position.x - _target.x, e.position.z - _target.z).length()
			if d <= HIT_CHECK_DIST:
				e.send_to_house(_house_cell(index), main.now, GHOST_HOME_S)
		"ate":
			if e.mode == "frightened":
				e.mode = "eaten"
				e.eaten_until = main.now + EATEN_S


## Main._check_pickups in an Arena round: what I ate goes to the opponent; a
## power pellet opens the ghosts' window (on the host directly, the client asks).
func on_pickups(result: Dictionary) -> void:
	for cell in result.cells:
		session.send_eat(cell)
	if result.power and not session.is_host:
		_power_grace_until = main.now + POWER_GRACE_S
		session.send_ghost_event("power", 0, ghost_scale())
