extends SceneTree
## Headless test: res://scripts/conditions.gd and its condition scripts —
## the "Konditionen" run-modifier system (Matrix Ghost, Fear & Loathing).
## Pure-logic checks, no Main/scene needed (matrix_ghost's on_start/on_end
## need a Main-shaped object — a tiny fake stands in for one here). Run with
##   godot --headless --path . --script res://tests/test_conditions.gd
## Exits with code 0 on success, 1 on any failure.

## A minimal stand-in for Main, just shaped enough for matrix_ghost.gd's
## on_start/on_end to call into (maze_view.set_word_mode, player.set_noclip,
## enemies[].set_word_skin) without spinning up the real scene.
class FakeMazeView:
	var word_mode_active := false
	func set_word_mode(active: bool) -> void:
		word_mode_active = active

class FakePlayer:
	var noclip_active := false
	func set_noclip(active: bool) -> void:
		noclip_active = active

class FakeEnemy:
	var word_skin_active := false
	func set_word_skin(active: bool) -> void:
		word_skin_active = active

class FakeMain:
	var maze_view := FakeMazeView.new()
	var player := FakePlayer.new()
	var enemies: Array = []


func _initialize() -> void:
	var Conditions = load("res://scripts/conditions.gd")
	var failures := 0
	var checks := 0

	# --- Registry: known ids resolve, unknown/empty id means "no condition" ---
	checks += 1
	if Conditions.get_condition("matrix_ghost") == null:
		failures += 1
		print("FAIL Conditions.get_condition('matrix_ghost') should return an instance")

	checks += 1
	if Conditions.get_condition("fear_and_loathing") == null:
		failures += 1
		print("FAIL Conditions.get_condition('fear_and_loathing') should return an instance")

	checks += 1
	if Conditions.get_condition("") != null:
		failures += 1
		print("FAIL Conditions.get_condition('') should mean 'no condition' (null)")

	checks += 1
	if Conditions.get_condition("not_a_real_condition") != null:
		failures += 1
		print("FAIL Conditions.get_condition() with an unknown id should return null")

	checks += 1
	if Conditions.IDS.size() < 2:
		failures += 1
		print("FAIL Conditions.IDS should list at least the 2 built-in conditions")

	# --- Matrix Ghost: toggles maze_view/player/enemies on start, reverts on end ---
	var fake_main := FakeMain.new()
	fake_main.enemies = [FakeEnemy.new(), FakeEnemy.new()]
	var ghost = Conditions.get_condition("matrix_ghost")

	ghost.on_start(fake_main)
	checks += 1
	if not fake_main.maze_view.word_mode_active:
		failures += 1
		print("FAIL matrix_ghost.on_start should turn on maze_view word mode")
	# Noclip is deliberately NOT asserted here (and matrix_ghost.gd no longer
	# touches player.set_noclip at all — see review finding Code-W2): the
	# old on_start/on_end calls to main.player.set_noclip() got silently
	# clobbered whenever start_manhattan_level() ran right after
	# set_condition(), since that unconditionally reset collision back on a
	# few lines later. Noclip is now derived centrally by
	# Main._refresh_player_modifiers() (from current_condition.id ==
	# "matrix_ghost"), called at every point that could affect it — a real
	# Main instance, not this fake, so that path is covered end-to-end by
	# bot_test.gd's "matrix ghost condition actually sets noclip through the
	# real start path" check instead of here.
	checks += 1
	if fake_main.player.noclip_active:
		failures += 1
		print("FAIL matrix_ghost.on_start should no longer touch player noclip directly (see Code-W2)")
	checks += 1
	var all_reskinned := true
	for e in fake_main.enemies:
		if not e.word_skin_active:
			all_reskinned = false
	if not all_reskinned:
		failures += 1
		print("FAIL matrix_ghost.on_start should reskin every enemy")

	ghost.on_end(fake_main)
	checks += 1
	if fake_main.maze_view.word_mode_active:
		failures += 1
		print("FAIL matrix_ghost.on_end should revert maze_view word mode")
	checks += 1
	var any_still_reskinned := false
	for e in fake_main.enemies:
		if e.word_skin_active:
			any_still_reskinned = true
	if any_still_reskinned:
		failures += 1
		print("FAIL matrix_ghost.on_end should revert every enemy's reskin")

	# --- Fear & Loathing: perturbs input, and periodically inverts it -------
	var drug = Conditions.get_condition("fear_and_loathing")
	drug.on_start(fake_main)
	var straight_forward := Vector2(0.0, 1.0)
	var any_perturbed := false
	var saw_inversion := false
	var t := 0.0
	while t < 20.0:
		var result: Vector2 = drug.modify_input(straight_forward, 0.05)
		if result != straight_forward:
			any_perturbed = true
		if result.y < 0.0: # forward became backward: an inversion window
			saw_inversion = true
		t += 0.05

	checks += 1
	if not any_perturbed:
		failures += 1
		print("FAIL fear_and_loathing.modify_input should perturb a straight input at some point")
	checks += 1
	if not saw_inversion:
		failures += 1
		print("FAIL fear_and_loathing.modify_input should invert the input at least once within 20s")

	# --- A condition with no override (condition_base itself) is a no-op ---
	var base_condition = load("res://scripts/conditions/condition_base.gd").new()
	checks += 1
	if base_condition.modify_input(Vector2(0.3, 0.7), 0.1) != Vector2(0.3, 0.7):
		failures += 1
		print("FAIL condition_base's default modify_input should pass input through unchanged")

	# --- other_condition_id: always picks a different selectable id, and
	# "no condition" ("") is itself a selectable option ---
	checks += 1
	if not ("" in Conditions.SELECTABLE_IDS):
		failures += 1
		print("FAIL SELECTABLE_IDS should include '' (no condition) as an option")
	checks += 1
	var saw_wrong_repeat := false
	for i in 30: # run several times since the pick is randomized
		for current_id in Conditions.SELECTABLE_IDS:
			if Conditions.other_condition_id(current_id) == current_id:
				saw_wrong_repeat = true
	if saw_wrong_repeat:
		failures += 1
		print("FAIL other_condition_id should never return the same id it was given")

	print("")
	if failures == 0:
		print("ALL %d CONDITIONS CHECKS PASSED" % checks)
		quit(0)
	else:
		print("%d/%d CONDITIONS CHECKS FAILED" % [failures, checks])
		quit(1)
