extends "res://scripts/conditions/condition_base.gd"
## Matrix Ghost — the word-built-world look and noclip-through-walls
## behavior (the same mechanisms the Word Mode pickup uses on normal
## levels), applied as a selectable whole-run condition instead of a
## temporary mid-level pickup effect: wall collision is off and every wall/
## ghost is its word-letterform skin for the entire run.

func _init() -> void:
	id = "matrix_ghost"
	display_name = "Matrix Ghost"


## Noclip itself is intentionally NOT set here (see review finding Code-W2):
## this used to call main.player.set_noclip(true) directly, but
## start_manhattan_level() — called right after set_condition() in
## Main._start_explorer_run — unconditionally reset collision back on a few
## lines later, silently undoing it. Main._refresh_player_modifiers() now
## derives noclip from current_condition.id == "matrix_ghost" every time
## anything relevant changes, including at the end of level/run setup, so
## it can no longer be clobbered by setup order.
func on_start(main) -> void:
	main.maze_view.set_word_mode(true)
	for enemy in main.enemies:
		enemy.set_word_skin(true)


func on_end(main) -> void:
	main.maze_view.set_word_mode(false)
	for enemy in main.enemies:
		enemy.set_word_skin(false)
