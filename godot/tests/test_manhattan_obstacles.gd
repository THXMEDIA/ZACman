extends SceneTree
## Headless test: res://scripts/taxi.gd and res://scripts/pedestrian.gd —
## the Manhattan bonus level's harmless moving/stationary obstacles. Run
## with
##   godot --headless --path . --script res://tests/test_manhattan_obstacles.gd
## Exits with code 0 on success, 1 on any failure.

func _initialize() -> void:
	var failures := 0
	var checks := 0

	# --- Taxi: drives along a fixed axis, bounces at both ends ----------
	var taxi = load("res://scripts/taxi.gd").new()
	taxi.setup("row", 4.0, 0.0, 10.0, 5.0)

	checks += 1
	if taxi.position.z != 4.0:
		failures += 1
		print("FAIL taxi on a 'row' axis should keep a fixed Z, got %f" % taxi.position.z)

	# Force it to the max end, then push one more update — it must clamp
	# and reverse direction rather than driving off the lane.
	taxi.pos_along = 10.0
	taxi.dir = 1.0
	taxi.update(0.1)
	checks += 1
	if taxi.pos_along > 10.0:
		failures += 1
		print("FAIL taxi should clamp at max_coord, got pos_along=%f" % taxi.pos_along)
	checks += 1
	if taxi.dir != -1.0:
		failures += 1
		print("FAIL taxi should reverse direction at max_coord, dir=%f" % taxi.dir)

	taxi.pos_along = 0.0
	taxi.dir = -1.0
	taxi.update(0.1)
	checks += 1
	if taxi.pos_along < 0.0:
		failures += 1
		print("FAIL taxi should clamp at min_coord, got pos_along=%f" % taxi.pos_along)
	checks += 1
	if taxi.dir != 1.0:
		failures += 1
		print("FAIL taxi should reverse direction at min_coord, dir=%f" % taxi.dir)

	# A 'col' axis taxi keeps a fixed X and moves along Z instead.
	var taxi_col = load("res://scripts/taxi.gd").new()
	taxi_col.setup("col", 6.0, 0.0, 10.0, 4.0)
	checks += 1
	if taxi_col.position.x != 6.0:
		failures += 1
		print("FAIL taxi on a 'col' axis should keep a fixed X, got %f" % taxi_col.position.x)

	checks += 1
	if taxi.word_mesh == null or taxi.word_mesh.mesh.text != "TAXI":
		failures += 1
		print("FAIL taxi should be built from the word TAXI")

	taxi.free()
	taxi_col.free()

	# --- Pedestrian: stationary root, only the word mesh bobs -----------
	var ped = load("res://scripts/pedestrian.gd").new()
	var spawn_pos := Vector3(4.0, 0.4, 8.0)
	ped.setup(spawn_pos)

	checks += 1
	if ped.position != spawn_pos:
		failures += 1
		print("FAIL pedestrian should spawn exactly at the given position, got %s" % ped.position)

	checks += 1
	if ped.word_mesh == null or ped.word_mesh.mesh.text != "PERSON":
		failures += 1
		print("FAIL pedestrian should be built from the word PERSON")

	ped.update(0.1, 0.0)
	var root_pos_after: Vector3 = ped.position
	checks += 1
	if root_pos_after != spawn_pos:
		failures += 1
		print("FAIL pedestrian root position must stay fixed (only its word mesh bobs), moved to %s" % root_pos_after)

	ped.free()

	print("")
	if failures == 0:
		print("ALL %d MANHATTAN OBSTACLE CHECKS PASSED" % checks)
		quit(0)
	else:
		print("%d/%d MANHATTAN OBSTACLE CHECKS FAILED" % [failures, checks])
		quit(1)
