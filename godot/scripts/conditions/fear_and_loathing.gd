extends "res://scripts/conditions/condition_base.gd"
## Fear & Loathing (bad) — exactly ONE steering manipulation per pickup,
## drawn with the rabbit's random generator (spec 2.4), announced with its
## symbol on the title card:
##   SWAP   A/D swapped (strafe input mirrored)
##   DRIFT  25 % sideways pull, only while a movement input is held
##   DELAY  150 ms delay on WASD (fixed ring buffer)
## Look "Kippbild": "gekippt" (flip) = the manipulation is acting on the
## current input right now (a movement input is held), smoothed over 0.4 s.
##
## Red line (E8e): mouse / view direction / camera are never touched — this
## only ever sees the movement vector. No movement without input (also the
## delay stops at once when the keys are released), no screen shake, no FOV
## pulse, no time dilation. Speed never exceeds PLAYER_SPEED: the result is
## clamped to length 1 (PlayerController scales by PLAYER_SPEED).

const SWAP := "swap"
const DRIFT := "drift"
const DELAY := "delay"
const MANIPULATIONS := [SWAP, DRIFT, DELAY]
const DRIFT_SHARE := 0.25
const DELAY_S := 0.15
const LOOK_FLIP_SECONDS := 0.4

var manipulation := SWAP
var drift_side := 1.0 # +1 pulls right, -1 left (drawn with the rabbit RNG)

var _ring: Array = [] # fixed ring buffer of input vectors (DELAY)
var _ring_pos := 0
var _acting := false
var _flip := 0.0


func _init() -> void:
	id = "fear_and_loathing"
	display_name = "Fear & Loathing"
	look_id = "kippbild"
	icon = "fl_swap"
	_alloc_ring()


func roll(rng: RandomNumberGenerator) -> void:
	set_manipulation(MANIPULATIONS[rng.randi_range(0, MANIPULATIONS.size() - 1)])
	drift_side = 1.0 if rng.randf() < 0.5 else -1.0


func set_manipulation(kind: String) -> void:
	manipulation = kind
	icon = "fl_" + kind
	_alloc_ring()


func subtitle() -> String:
	match manipulation:
		SWAP:
			return "A/D vertauscht"
		DRIFT:
			return "Drift zur Seite"
		DELAY:
			return "Steuerung verzögert"
	return ""


## Ring size = 150 ms worth of physics ticks; allocated once, never grows.
func _alloc_ring() -> void:
	var ticks := maxi(1, int(round(DELAY_S * Engine.physics_ticks_per_second)))
	_ring.resize(ticks)
	_ring.fill(Vector2.ZERO)
	_ring_pos = 0


func modify_input(v: Vector2, _delta: float) -> Vector2:
	var has_input := v.length() > 0.001
	_acting = has_input
	var out := v
	match manipulation:
		SWAP:
			out = Vector2(-v.x, v.y)
			_acting = absf(v.x) > 0.001
		DRIFT:
			if has_input:
				var dir := v.normalized()
				var side := Vector2(dir.y, -dir.x) * drift_side # perpendicular in (strafe, forward)
				out = v + side * DRIFT_SHARE * v.length()
		DELAY:
			var delayed: Vector2 = _ring[_ring_pos] # written DELAY_S ago
			_ring[_ring_pos] = v
			_ring_pos = (_ring_pos + 1) % _ring.size()
			out = delayed if has_input else Vector2.ZERO
	if out.length() > 1.0:
		out = out.normalized()
	return out


func on_process(delta: float, _main, _remaining: float) -> void:
	_flip = move_toward(_flip, 1.0 if _acting else 0.0, delta / LOOK_FLIP_SECONDS)


func look_flip() -> float:
	return _flip
