extends Node3D
## Root node of the Kyoto pop-up city (kyoto_scenery.gd builds it). Main
## forwards the "Effekte reduzieren" setting here: with it on, every card
## stands (no folding at all).

var card_material: ShaderMaterial = null
var card_count := 0
var _fold := true


func set_reduce_fx(on: bool) -> void:
	_fold = not on
	if card_material != null:
		card_material.set_shader_parameter("fold_on", 1.0 if _fold else 0.0)


func fold_enabled() -> bool:
	return _fold
