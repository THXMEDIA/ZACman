extends RefCounted
## ConditionBase — interface for a "Kondition": a run-wide modifier Main can
## apply for a whole run (distinct from a temporary in-run pickup like the
## Word Mode power-up, though a condition can reuse the same underlying
## mechanisms — Matrix Ghost, below, reuses set_word_mode/set_noclip).
##
## Subclass this and override only the hooks you need; every hook has a
## harmless no-op default. Register the subclass in conditions.gd's
## registry — Main and the rest of the game never need to change to pick up
## a new condition (see this project's "Explorer-Level-Erweiterung,
## Leaderboard & Konditionen" doc for the full plan this is step 2 of).

var id := ""
var display_name := ""


## Called once when the condition is applied for a run (see Main.set_condition).
func on_start(_main) -> void:
	pass


## Called once when the condition is removed (a new condition replacing this
## one, or the run ending).
func on_end(_main) -> void:
	pass


## Per-frame hook, called from Main._process while running and not paused.
func on_process(_delta: float, _main) -> void:
	pass


## Transforms the player's raw (strafe, forward) input vector before it is
## applied to movement, called every physics frame from PlayerController.
## `delta` is physics delta time, for conditions that need their own internal
## clock (see fear_and_loathing.gd). Default: input unchanged.
func modify_input(v: Vector2, _delta: float) -> Vector2:
	return v
