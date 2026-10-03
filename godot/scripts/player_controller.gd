extends CharacterBody3D
## PlayerController — first-person movement with mouse-look, colliding
## against the maze walls via Godot physics (floating motion mode: no
## gravity, no floor snap, matches the web prototype's fixed-height feel).

const CELL := 2.0
const EYE_H := 0.95
const PLAYER_RADIUS := 0.34
const PLAYER_SPEED := 4.4
const MOUSE_SENSITIVITY := 0.0022

var camera: Camera3D
var yaw := 0.0
var pitch := 0.0
var input_enabled := true
var move_input := Vector2.ZERO # x = strafe, y = forward, set externally by touch/AI bots
## The running Kondition (scripts/conditions/condition_base.gd) or null. Only
## Main.start_condition/_end_condition set it — it always mirrors
## Main.active_condition, the single source of the active state. Only the
## movement vector goes through it; mouse look never does (red line E8e).
var active_condition = null
## true during the speedrun start intro and the wait for the first step:
## mouse look works, walking does not (the clock and the legs start together,
## see Main._update_start_hold).
var movement_locked := false
## UX-K1: the player's mouse sensitivity, a factor on MOUSE_SENSITIVITY
## (Settings "mouse_sens", 0.3-3.0).
var mouse_sensitivity_scale := 1.0


func _ready() -> void:
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	up_direction = Vector3.UP
	collision_layer = 1
	collision_mask = 2

	# Order matters here (confirmed in-engine, see review finding Code-N8):
	# Godot's CapsuleShape3D enforces height >= 2*radius by silently
	# clamping whichever is set SECOND. Setting radius (0.34) first and
	# height (0.4) second — the old order — clamped the radius down to
	# height/2 = 0.2 without any warning, so the player's real collision
	# footprint was less than 2/3 of the documented PLAYER_RADIUS the rest
	# of the codebase's corridor-width math assumes. Setting height first
	# lets radius keep its real, intended value; height then auto-adjusts
	# up to 2*radius (0.68) instead, which is harmless since the capsule
	# lies flat (see cs.rotation.x below) — what matters is the horizontal
	# footprint, not this vertical extent.
	var shape := CapsuleShape3D.new()
	shape.height = 0.4
	shape.radius = PLAYER_RADIUS
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.rotation.x = PI / 2.0
	add_child(cs)

	camera = Camera3D.new()
	camera.position = Vector3(0, EYE_H, 0)
	camera.fov = 72.0
	camera.near = 0.05
	camera.far = 100.0
	add_child(camera)

	var light := OmniLight3D.new()
	light.light_color = Color(0.56, 0.83, 1.0)
	light.omni_range = 7.0
	light.light_energy = 1.1
	camera.add_child(light)
	light.position = Vector3(0, 0, 0)


## Noclip (Matrix condition): while active the player passes straight
## through walls (collision_mask 0 = collide with nothing). Restored to the
## normal walls layer (2) when it ends; Main derives it (_refresh_noclip).
func set_noclip(active: bool) -> void:
	collision_mask = 0 if active else 2


func warp_to(cell: Vector2i, facing_yaw: float) -> void:
	global_position = Vector3(cell.y * CELL, EYE_H, cell.x * CELL)
	yaw = facing_yaw
	rotation.y = yaw
	pitch = 0.0
	camera.rotation.x = 0.0


func cell() -> Vector2i:
	return Vector2i(int(round(global_position.z / CELL)), int(round(global_position.x / CELL)))


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		var sens := MOUSE_SENSITIVITY * mouse_sensitivity_scale
		yaw -= event.relative.x * sens
		pitch = clampf(pitch - event.relative.y * sens, -1.1, 1.1)
		rotation.y = yaw
		camera.rotation.x = pitch


## The raw movement input (keys + move_input), before any condition.
func raw_move_input() -> Vector2:
	var fwd := 0.0
	var strafe := 0.0
	if Input.is_action_pressed("move_forward"):
		fwd += 1.0
	if Input.is_action_pressed("move_back"):
		fwd -= 1.0
	if Input.is_action_pressed("move_right"):
		strafe += 1.0
	if Input.is_action_pressed("move_left"):
		strafe -= 1.0
	return Vector2(strafe + move_input.x, fwd + move_input.y)


func has_move_input() -> bool:
	return raw_move_input().length() > 0.001


func _physics_process(delta: float) -> void:
	if not input_enabled or movement_locked:
		velocity = Vector3.ZERO
		return

	var v := raw_move_input()
	if active_condition != null:
		v = active_condition.modify_input(v, delta)
	# never faster than PLAYER_SPEED, whatever a condition did to the input
	if v.length() > 1.0:
		v = v.normalized()

	# Camera forward at yaw=0 is -Z (Godot's default camera look direction),
	# not +Z — these need the minus sign to actually match it. Without it,
	# "forward" moved the player toward +Z, i.e. behind where the camera was
	# looking, so W/S felt swapped (right/left were unaffected: the strafe
	# vector below already matched the camera's real right-hand direction).
	var dir_x := -sin(yaw)
	var dir_z := -cos(yaw)
	var right_x := sin(yaw + PI / 2.0)
	var right_z := cos(yaw + PI / 2.0)
	var move_dir := Vector3(dir_x * v.y + right_x * v.x, 0.0, dir_z * v.y + right_z * v.x)
	velocity = move_dir * PLAYER_SPEED
	move_and_slide()


## Tunnel wraparound: called by Main after physics, since it's a teleport,
## not a collision response.
func wrap_tunnel(world_width: float) -> void:
	if global_position.x < -CELL * 0.5:
		global_position.x += world_width
	elif global_position.x > world_width - CELL * 0.5:
		global_position.x -= world_width


