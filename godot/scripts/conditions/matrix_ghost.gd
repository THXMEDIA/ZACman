extends "res://scripts/conditions/condition_base.gd"
## Matrix Ghost — the word-built-world look and noclip-through-walls
## behavior (the same mechanisms the Word Mode pickup uses on normal
## levels), applied as a selectable whole-run condition instead of a
## temporary mid-level pickup effect: wall collision is off and every wall/
## ghost is its word-letterform skin for the entire run.

func _init() -> void:
	id = "matrix_ghost"
	display_name = "Matrix Ghost"


func on_start(main) -> void:
	main.maze_view.set_word_mode(true)
	main.player.set_noclip(true)
	for enemy in main.enemies:
		enemy.set_word_skin(true)


func on_end(main) -> void:
	main.maze_view.set_word_mode(false)
	main.player.set_noclip(false)
	for enemy in main.enemies:
		enemy.set_word_skin(false)
