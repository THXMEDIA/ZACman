extends "res://scripts/conditions/condition_base.gd"
## Matrix (good) — "Durchlässiger Code": walls without collision for the
## duration, look kond_wall look 1. Noclip goes through Main's single noclip
## derivation (Main._noclip_wanted), and when the condition ends Main puts the
## player safely into the nearest open cell with the capsule fully free
## (Main._rescue_player_from_wall, wall_footprint_scale taken into account).
## In the last 3 s the walls fade back in / blink (Main, below 3 Hz).

func _init() -> void:
	id = "matrix"
	display_name = "Matrix"
	look_id = "matrix"
	icon = "matrix"


func subtitle() -> String:
	return "Durch Wände gehen"


func wants_noclip() -> bool:
	return true
