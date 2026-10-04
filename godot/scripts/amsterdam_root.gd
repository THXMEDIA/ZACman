extends Node3D
## Root node of the Amsterdam cardboard model (amsterdam_scenery.gd builds
## it). The city itself has no animation, so "Effekte reduzieren" has nothing
## to stop here (the exit pulse is stopped in amsterdam_exit.gd); the flag is
## kept so Main and the tests can ask. Holds the evening lights for the tests.

var panel_count := 0
var cut_count := 0
var tree_count := 0
var sun: DirectionalLight3D = null
var lamp: SpotLight3D = null
var bounce: DirectionalLight3D = null
var _reduce_fx := false


func set_reduce_fx(on: bool) -> void:
	_reduce_fx = on


func fx_reduced() -> bool:
	return _reduce_fx


## Nothing in the model moves (water, trees, flags in the city are still).
func animated_nodes() -> Array:
	return []
