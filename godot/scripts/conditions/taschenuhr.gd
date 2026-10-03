extends "res://scripts/conditions/condition_base.gd"
## Taschenuhr (good) — ghosts 50 % slower, base look with a slight warm tint
## and a slow clock tick (Main plays Sfx.clock_tick once per second).

const GHOST_SPEED_SCALE := 0.5
const TICK_INTERVAL_S := 1.0

var _tick_clock := 0.0


func _init() -> void:
	id = "taschenuhr"
	display_name = "Taschenuhr"
	look_id = "taschenuhr"
	icon = "taschenuhr"


func subtitle() -> String:
	return "Geister 50 % langsamer"


func ghost_speed_scale() -> float:
	return GHOST_SPEED_SCALE


func on_process(delta: float, _main, _remaining: float) -> void:
	_tick_clock += delta
	if _tick_clock >= TICK_INTERVAL_S:
		_tick_clock -= TICK_INTERVAL_S
		Sfx.clock_tick()
