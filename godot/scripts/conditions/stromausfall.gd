extends "res://scripts/conditions/condition_base.gd"
## Stromausfall (bad) — dense fog (sight ~2 cells, see condition_looks.gd),
## minimap off. Pellets, power pellets and ghosts stay self-luminous: Main
## exempts their materials from the fog while this look is active.

func _init() -> void:
	id = "stromausfall"
	display_name = "Stromausfall"
	look_id = "stromausfall"
	icon = "stromausfall"


func subtitle() -> String:
	return "Sicht 2 Felder, Karte aus"


func minimap_visible() -> bool:
	return false
