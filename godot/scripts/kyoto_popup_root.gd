extends Node3D
## Root node of the Kyoto pop-up city (kyoto_scenery.gd builds it). Main
## forwards the "Effekte reduzieren" setting here: with it on, every card
## stands (no folding at all) and the falling petals are hidden. On level start the book opens: every card lies
## flat and they stand up near to far within INTRO_S (start_intro, game-design
## review W1) — the camera is never touched; skipped with reduced effects.

const Style := preload("res://scripts/kyoto_style.gd")
const INTRO_S := 1.8

var card_material: ShaderMaterial = null
var card_count := 0
var tree_count := 0
var petal_count := 0
var petals: MultiMeshInstance3D = null # falling blossom petals (own draw call)
var _fold := true
var _intro_t := -1.0 # < 0: no intro running


func set_reduce_fx(on: bool) -> void:
	_fold = not on
	if petals != null:
		petals.visible = not on # no falling petals with reduced effects
	if on:
		_end_intro()
	if card_material != null:
		card_material.set_shader_parameter("fold_on", 1.0 if _fold else 0.0)


func fold_enabled() -> bool:
	return _fold


func intro_running() -> bool:
	return _intro_t >= 0.0


func start_intro() -> void:
	if not _fold or card_material == null:
		return
	_intro_t = 0.0
	_apply_intro(0.0)


func _process(delta: float) -> void:
	if _intro_t < 0.0:
		return
	_intro_t += delta
	if _intro_t >= INTRO_S:
		_end_intro()
	else:
		_apply_intro(_intro_t / INTRO_S)


func _apply_intro(t: float) -> void:
	# ease-out: the near cards rise quickly, the far ones follow
	var e := 1.0 - pow(1.0 - t, 2.0)
	card_material.set_shader_parameter("fold_near", Style.FOLD_NEAR * e)
	card_material.set_shader_parameter("fold_far", maxf(0.5, Style.FOLD_FAR * e))


func _end_intro() -> void:
	_intro_t = -1.0
	if card_material != null:
		card_material.set_shader_parameter("fold_near", Style.FOLD_NEAR)
		card_material.set_shader_parameter("fold_far", Style.FOLD_FAR)
