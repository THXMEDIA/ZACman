extends "res://scripts/conditions/condition_base.gd"
## Taschenuhr (good) — ghosts 50 % slower, base look with a slight warm tint
## and a slow clock tick (Sfx.clock_tick once per second). In the last
## SILENT_LAST_S seconds the clock is silent, so the end ticks every
## condition plays then (Main, Sfx.condition_tick) stay audible (GD review).

const GHOST_SPEED_SCALE := 0.5
const TICK_INTERVAL_S := 1.0
const SILENT_LAST_S := 3.0 # = Main.CONDITION_WARN_S

var _tick_clock := 0.0
## Clock ticks played so far (tests); play_sound false = count only (unit
## tests without the Sfx autoload running).
var ticks_played := 0
var play_sound := true


func _init() -> void:
	id = "taschenuhr"
	display_name = "Taschenuhr"
	look_id = "taschenuhr"
	icon = "taschenuhr"


func subtitle() -> String:
	return "Geister 50 % langsamer"


func ghost_speed_scale() -> float:
	return GHOST_SPEED_SCALE


func on_process(delta: float, _main, remaining: float) -> void:
	_tick_clock += delta
	if _tick_clock >= TICK_INTERVAL_S:
		_tick_clock -= TICK_INTERVAL_S
		if remaining > SILENT_LAST_S:
			ticks_played += 1
			if play_sound:
				Sfx.clock_tick()
