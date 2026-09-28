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


func _ready() -> void:
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	up_direction = Vector3.UP
	collision_layer = 1
	collision_mask = 2

	var shape := CapsuleShape3D.new()
	shape.radius = PLAYER_RADIUS
	shape.height = 0.4
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
		yaw -= event.relative.x * MOUSE_SENSITIVITY
		pitch = clampf(pitch - event.relative.y * MOUSE_SENSITIVITY, -1.1, 1.1)
		rotation.y = yaw
		camera.rotation.x = pitch


func _physics_process(_delta: float) -> void:
	if not input_enabled:
		velocity = Vector3.ZERO
		return

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
	fwd += move_input.y
	strafe += move_input.x
	var v := Vector2(strafe, fwd)
	if v.length() > 1.0:
		v = v.normalized()

	var dir_x := sin(yaw)
	var dir_z := cos(yaw)
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
