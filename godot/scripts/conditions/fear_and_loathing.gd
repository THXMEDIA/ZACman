extends "res://scripts/conditions/condition_base.gd"
## Fear & Loathing — a "drug level" run modifier: the player's steering
## input gets continuously noisy and, on an unpredictable timer, flips
## (strafe/forward both invert) for a while before flipping back — so the
## same maze plays very differently each time this condition is active.
## Self-contained (keeps its own internal clock via `delta`), so it needs no
## reference to Main to do its job — only modify_input is overridden.

const FLIP_MIN_INTERVAL := 2.5
const FLIP_MAX_INTERVAL := 6.0
const NOISE_AMOUNT := 0.35

var _clock := 0.0
var _next_flip_at := 0.0
var _inverted := false


func _init() -> void:
	id = "fear_and_loathing"
	display_name = "Fear & Loathing"


func on_start(_main) -> void:
	_clock = 0.0
	_inverted = false
	_next_flip_at = randf_range(FLIP_MIN_INTERVAL, FLIP_MAX_INTERVAL)


func modify_input(v: Vector2, delta: float) -> Vector2:
	_clock += delta
	if _clock >= _next_flip_at:
		_inverted = not _inverted
		_next_flip_at = _clock + randf_range(FLIP_MIN_INTERVAL, FLIP_MAX_INTERVAL)

	var noisy := Vector2(
		v.x + sin(_clock * 11.3) * NOISE_AMOUNT,
		v.y + cos(_clock * 9.7) * NOISE_AMOUNT
	)
	if _inverted:
		noisy = -noisy
	return noisy
