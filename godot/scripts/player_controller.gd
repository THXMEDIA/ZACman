extends CharacterBody3D
## PlayerController — first-person movement with mouse-look, colliding
## against the maze walls via Godot physics (floating motion mode: no
## gravity, no floor snap, matches the web prototype's fixed-height feel).

const CELL := 2.0
## Default eye height (m); every city sets its own via CityTheme.eye_height
## (Main applies it with set_eye_height). Was 0.95 everywhere: too low (Abnahme 06.10.).
const EYE_H := 1.25
const PLAYER_RADIUS := 0.34
## +15 %, then +5 % (Abnahme 06.10.: 4.4 -> 5.06 -> 5.31); Levels.PLAYER_SPEED must stay equal.
const PLAYER_SPEED := 5.31
const MOUSE_SENSITIVITY := 0.0022

## ---- Bewegungs-Paket (ZAP-5, Abnahme 06.10.): Dash + Kehrtwende ----
## Both are triggered by the player alone (keys), never by a Kondition, the
## rabbit or the chat (red line E8e): turn_around() is a cut (yaw + PI, no
## camera sweep, pitch and FOV untouched); the dash only moves the body.
const DASH_SPEED := 18.0 # m/s while dashing
const DASH_TIME := 0.2 # s -> ~3.6 m
const DASH_COOLDOWN := 0.5 # s anti-spam between two dashes
const DASH_AFTERGLOW := 0.15 # s: still ghost-proof after the dash, so you never end inside a ghost
const DASH_MIN_FREE := 1.0 # m of free space in front, else the charge is not spent
const DASH_MAX_CHARGES := 2
const DASH_START_CHARGES := 1
const TURN_COOLDOWN := 0.4 # s -> far below 3 Hz

var camera: Camera3D
## Current eye height of the camera (m), set per city by set_eye_height().
var eye_h := EYE_H
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
## The small lamp the player carries; Main sets its color per city theme
## (CityTheme.player_light_*).
var light: OmniLight3D

## Dash state (see the constants above). Charges come only from game state
## (a ghost eaten, the fruit), never from time.
var dash_charges := DASH_START_CHARGES
var dash_time_left := 0.0
var dash_afterglow_left := 0.0
var dash_cooldown_left := 0.0
var turn_cooldown_left := 0.0
var _dash_dir := Vector3.ZERO
var _last_move_input := Vector2.ZERO # the movement vector of the last physics tick (after the Kondition)
## Counters for tests / the bot measurement.
var dash_count := 0
var turn_count := 0


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
	camera.position = Vector3(0, eye_h, 0)
	camera.fov = 72.0
	camera.near = 0.05
	camera.far = 100.0
	add_child(camera)

	light = OmniLight3D.new()
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


## Sets the eye height: the body (and with it the camera) sits at y = h. Only
## the height changes, never yaw/pitch (red line E8e).
func set_eye_height(h: float) -> void:
	eye_h = h
	if camera != null:
		camera.position = Vector3(0, eye_h, 0)


func warp_to(cell: Vector2i, facing_yaw: float) -> void:
	global_position = Vector3(cell.y * CELL, eye_h, cell.x * CELL)
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
	dash_cooldown_left = maxf(dash_cooldown_left - delta, 0.0)
	turn_cooldown_left = maxf(turn_cooldown_left - delta, 0.0)
	dash_afterglow_left = maxf(dash_afterglow_left - delta, 0.0)
	if not input_enabled or movement_locked:
		velocity = Vector3.ZERO
		dash_time_left = 0.0
		return

	if dash_time_left > 0.0:
		# the dash: fixed direction, fixed speed, a hair of afterglow at the end
		dash_time_left = maxf(dash_time_left - delta, 0.0)
		if dash_time_left <= 0.0:
			dash_afterglow_left = DASH_AFTERGLOW
		velocity = _dash_dir * DASH_SPEED
		move_and_slide()
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
	_last_move_input = v
	velocity = move_dir * PLAYER_SPEED
	move_and_slide()


## True while the dash runs and for a moment after it: normal ghosts do not
## hurt then (frightened ones can still be eaten).
func is_dash_protected() -> bool:
	return dash_time_left > 0.0 or dash_afterglow_left > 0.0


func is_dashing() -> bool:
	return dash_time_left > 0.0


## Back to the start state (level start, lost life).
func reset_dash() -> void:
	dash_charges = DASH_START_CHARGES
	dash_time_left = 0.0
	dash_afterglow_left = 0.0
	dash_cooldown_left = 0.0


## A ghost eaten / the fruit: +1 charge up to the maximum. Returns true if it counted.
func add_dash_charge() -> bool:
	if dash_charges >= DASH_MAX_CHARGES:
		return false
	dash_charges += 1
	return true


## The dash direction in world space: the movement input of the last tick
## (already through a Kondition such as Fear & Loathing, so the dash is no
## free cure for it), without input straight ahead.
func dash_direction() -> Vector3:
	var v := _last_move_input
	if v.length() < 0.1:
		v = Vector2(0.0, 1.0)
	v = v.normalized()
	var dir := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var right := Vector3(sin(yaw + PI / 2.0), 0.0, cos(yaw + PI / 2.0))
	return (dir * v.y + right * v.x).normalized()


## Starts a dash if one is allowed: input on, not locked, a charge, no
## cooldown, and at least DASH_MIN_FREE metres free ahead (no wasted charge
## in front of a wall). Returns true if it started.
func try_dash() -> bool:
	if not input_enabled or movement_locked or dash_time_left > 0.0:
		return false
	if dash_charges <= 0 or dash_cooldown_left > 0.0:
		return false
	var d := dash_direction()
	if collision_mask != 0 and test_move(global_transform, d * DASH_MIN_FREE):
		return false
	_dash_dir = d
	dash_charges -= 1
	dash_time_left = DASH_TIME
	dash_cooldown_left = DASH_COOLDOWN + DASH_TIME
	dash_count += 1
	return true


## 180 degree turn on a key press: a cut, yaw + PI. Pitch, FOV and the
## camera itself are untouched (no sweep -> no apparent motion, E8e).
func turn_around() -> bool:
	if not input_enabled or turn_cooldown_left > 0.0:
		return false
	yaw = wrapf(yaw + PI, -PI, PI)
	rotation.y = yaw
	turn_cooldown_left = TURN_COOLDOWN
	turn_count += 1
	return true


## Tunnel wraparound: called by Main after physics, since it's a teleport,
## not a collision response.
func wrap_tunnel(world_width: float) -> void:
	if global_position.x < -CELL * 0.5:
		global_position.x += world_width
	elif global_position.x > world_width - CELL * 0.5:
		global_position.x -= world_width


