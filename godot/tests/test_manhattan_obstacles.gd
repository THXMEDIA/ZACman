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
	if ped.word_mesh == null or not (ped.word_mesh.mesh.text == "MAN" or ped.word_mesh.mesh.text == "WOMAN"):
		failures += 1
		print("FAIL pedestrian should be built from the word MAN or WOMAN, got '%s'" % (ped.word_mesh.mesh.text if ped.word_mesh else "<null>"))

	ped.update(0.1, 0.0)
	var root_pos_after: Vector3 = ped.position
	checks += 1
	if root_pos_after != spawn_pos:
		failures += 1
		print("FAIL a pedestrian with no walk axis must stay fixed (only its word mesh bobs), moved to %s" % root_pos_after)

	ped.free()

	# --- Pedestrian: given a walk axis, it actually walks the lane --------
	var ped_walk = load("res://scripts/pedestrian.gd").new()
	ped_walk.setup(Vector3(0.0, 0.4, 4.0), "col", 0.0, 10.0, 3.0)
	var pos_before: Vector3 = ped_walk.position
	ped_walk.update(0.5, 0.5)
	checks += 1
	if is_equal_approx(ped_walk.position.z, pos_before.z):
		failures += 1
		print("FAIL a pedestrian with a walk axis should move along it, stayed at %s" % ped_walk.position)
	checks += 1
	if not is_equal_approx(ped_walk.position.x, pos_before.x):
		failures += 1
		print("FAIL a 'col' axis pedestrian should keep a fixed X while walking, moved to %s" % ped_walk.position)
	ped_walk.free()

	# --- Taxi variant: VeryLongLimousine (same script, different word) -----
	var limo = load("res://scripts/taxi.gd").new()
	limo.setup("row", 2.0, 0.0, 10.0, 3.0, "VERYLONGLIMOUSINE", Color(0.82, 0.86, 0.95), 18)
	checks += 1
	if limo.word_mesh == null or limo.word_mesh.mesh.text != "VERYLONGLIMOUSINE":
		failures += 1
		print("FAIL limousine variant should be built from the word VERYLONGLIMOUSINE")
	limo.free()

	# --- Taxi variants: CAR and BIKE (same script, different word/color) ---
	var car = load("res://scripts/taxi.gd").new()
	car.setup("row", 2.0, 0.0, 10.0, 3.0, "CAR", Color(0.55, 0.65, 0.8), 26)
	checks += 1
	if car.word_mesh == null or car.word_mesh.mesh.text != "CAR":
		failures += 1
		print("FAIL car variant should be built from the word CAR")
	car.free()

	var bike = load("res://scripts/taxi.gd").new()
	bike.setup("row", 2.0, 0.0, 10.0, 4.5, "BIKE", Color(0.35, 0.85, 0.45), 20)
	checks += 1
	if bike.word_mesh == null or bike.word_mesh.mesh.text != "BIKE":
		failures += 1
		print("FAIL bike variant should be built from the word BIKE")
	bike.free()

	# --- ManWalkingDog: stacked MAN letters + a DOG mesh beside them -------
	var mwd = load("res://scripts/man_walking_dog.gd").new()
	var mwd_pos := Vector3(3.0, 0.4, 5.0)
	mwd.setup(mwd_pos)
	checks += 1
	if mwd.position != mwd_pos:
		failures += 1
		print("FAIL man_walking_dog should spawn exactly at the given position, got %s" % mwd.position)
	checks += 1
	if mwd.man_letters == null or mwd.man_letters.get_child_count() != 3:
		failures += 1
		print("FAIL man_walking_dog should stack 3 letters for MAN")
	else:
		var letters := ""
		for child in mwd.man_letters.get_children():
			letters += child.mesh.text
		checks += 1
		if letters != "MAN":
			failures += 1
			print("FAIL man_walking_dog's stacked letters should spell MAN, got '%s'" % letters)
	checks += 1
	if mwd.dog_mesh == null or mwd.dog_mesh.mesh.text != "DOG":
		failures += 1
		print("FAIL man_walking_dog should have a DOG word mesh")
	mwd.update(0.1, 1.0)
	checks += 1
	if mwd.position != mwd_pos:
		failures += 1
		print("FAIL man_walking_dog root position must stay fixed (only children bob), moved to %s" % mwd.position)
	mwd.free()

	# --- KidGroup: three KID word meshes around a center point -------------
	var kids = load("res://scripts/kid_group.gd").new()
	var kids_pos := Vector3(7.0, 0.4, 2.0)
	kids.setup(kids_pos)
	checks += 1
	if kids.position != kids_pos:
		failures += 1
		print("FAIL kid_group should spawn exactly at the given position, got %s" % kids.position)
	checks += 1
	if kids.kid_meshes.size() != 3:
		failures += 1
		print("FAIL kid_group should have 3 KID meshes, got %d" % kids.kid_meshes.size())
	else:
		var all_kid := true
		for km in kids.kid_meshes:
			if km.mesh.text != "KID":
				all_kid = false
		checks += 1
		if not all_kid:
			failures += 1
			print("FAIL kid_group's meshes should all be the word KID")
	kids.update(0.1, 1.0)
	kids.free()

	# --- DadAndKid: stacked DAD letters + a KID mesh beside them -----------
	var dak = load("res://scripts/dad_and_kid.gd").new()
	var dak_pos := Vector3(1.0, 0.4, 9.0)
	dak.setup(dak_pos)
	checks += 1
	if dak.position != dak_pos:
		failures += 1
		print("FAIL dad_and_kid should spawn exactly at the given position, got %s" % dak.position)
	checks += 1
	if dak.dad_letters == null or dak.dad_letters.get_child_count() != 3:
		failures += 1
		print("FAIL dad_and_kid should stack 3 letters for DAD")
	else:
		var dad_word := ""
		for child in dak.dad_letters.get_children():
			dad_word += child.mesh.text
		checks += 1
		if dad_word != "DAD":
			failures += 1
			print("FAIL dad_and_kid's stacked letters should spell DAD, got '%s'" % dad_word)
	checks += 1
	if dak.kid_mesh == null or dak.kid_mesh.mesh.text != "KID":
		failures += 1
		print("FAIL dad_and_kid should have a KID companion word mesh")
	dak.update(0.1, 1.0)
	checks += 1
	if dak.position != dak_pos:
		failures += 1
		print("FAIL dad_and_kid root position must stay fixed when given no walk axis, moved to %s" % dak.position)
	dak.free()

	# --- Pedestrian scripts given a walk axis actually move (spot-check
	# man_walking_dog/kid_group/dad_and_kid share the same machinery as
	# pedestrian.gd's own walk-axis check above) --------------------------
	var mwd_walk = load("res://scripts/man_walking_dog.gd").new()
	mwd_walk.setup(Vector3(0.0, 0.4, 2.0), "row", 0.0, 10.0, 3.0)
	var mwd_before: Vector3 = mwd_walk.position
	mwd_walk.update(0.5, 0.5)
	checks += 1
	if is_equal_approx(mwd_walk.position.x, mwd_before.x):
		failures += 1
		print("FAIL man_walking_dog with a walk axis should move along it, stayed at %s" % mwd_walk.position)
	mwd_walk.free()

	# --- MetroStation: pulsing SUBWAY sign -----------------------------
	var metro = load("res://scripts/metro_station.gd").new()
	var metro_pos := Vector3(9.0, 0.9, 4.0)
	metro.setup(metro_pos)
	checks += 1
	if metro.position != metro_pos:
		failures += 1
		print("FAIL metro_station should spawn exactly at the given position, got %s" % metro.position)
	checks += 1
	if metro.word_mesh == null or metro.word_mesh.mesh.text != "SUBWAY":
		failures += 1
		print("FAIL metro_station should be built from the word SUBWAY")
	checks += 1
	if metro.light == null:
		failures += 1
		print("FAIL metro_station should have an attached light for the pulsing glow")
	else:
		# Three phases a third of a pulse apart: a sine can't take the same
		# value at all three, whatever the random phase offset (the old
		# initial-vs-one-update compare failed when the offset hit the minimum).
		var energies := []
		for k in 3:
			metro.update(0.1, k * TAU / 3.0 / 3.6)
			energies.append(metro.light.light_energy)
		var energy_a: float = energies[0]
		var spread: float = energies.max() - energies.min()
		checks += 1
		if spread < 0.0001:
			failures += 1
			print("FAIL metro_station light should pulse (energy changed between updates), stayed at %f" % energy_a)
	metro.free()

	print("")
	if failures == 0:
		print("ALL %d MANHATTAN OBSTACLE CHECKS PASSED" % checks)
		quit(0)
	else:
		print("%d/%d MANHATTAN OBSTACLE CHECKS FAILED" % [failures, checks])
		quit(1)
