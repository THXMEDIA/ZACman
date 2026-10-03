extends RefCounted
## ConditionBase — interface of a "Kondition": a time-limited effect that only
## the white rabbit triggers (spec docs/design/kaninchen-speedrun.md 2.2/2.3).
##
## A condition only describes WHAT it changes; Main owns the single active
## condition (Main.active_condition), its timer, the look transition, the HUD
## card and the sounds. Conditions never touch scene nodes in on_start — the
## level may not be built yet (that was the cause of review finding Code-W1).
## Main reads the derived state below every frame instead (noclip, ghost
## speed, minimap, look), so nothing can get stuck when it ends.
##
## New condition = one script under scripts/conditions/ plus one registry
## entry in scripts/conditions.gd (is_good, duration_s, weight).

var id := ""
var display_name := ""
## Filled in from the registry by Conditions.get_condition():
var is_good := true
var duration_s := 10.0
var weight := 1.0
## Look of this condition (scripts/condition_looks.gd id), "" = no look change.
var look_id := ""
## HUD symbol kind for the title card (see hud.gd _draw_condition_icon).
var icon := ""


## Draws any per-pickup choice from the rabbit's random generator (spec 2.4:
## the same generator as the rabbit, never the global randf()). Called once
## by Main right after the condition was picked. Default: nothing to draw.
func roll(_rng: RandomNumberGenerator) -> void:
	pass


## Optional second line of the title card (e.g. the F&L manipulation).
func subtitle() -> String:
	return ""


## Called once when the condition starts / ends (Main.start_condition /
## Main.end_condition). Must not rely on level nodes.
func on_start(_main) -> void:
	pass


func on_end(_main) -> void:
	pass


## Per-frame hook while the game runs (not while paused). `remaining` =
## seconds left on the game clock.
func on_process(_delta: float, _main, _remaining: float) -> void:
	pass


## Transforms the player's raw (strafe, forward) input before it is applied
## to movement, every physics frame (PlayerController). Only movement — the
## mouse/view/camera is never routed through a condition (red line E8e).
func modify_input(v: Vector2, _delta: float) -> Vector2:
	return v


## Derived state, read by Main every frame.
func wants_noclip() -> bool:
	return false


func ghost_speed_scale() -> float:
	return 1.0


func minimap_visible() -> bool:
	return true


## 0..1, how far the look is "tipped" (F&L Kippbild). Default: never.
func look_flip() -> float:
	return 0.0
