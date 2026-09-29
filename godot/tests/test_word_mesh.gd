extends SceneTree
## Headless test: res://scripts/word_mesh.gd (the "letters ARE the object"
## mesh builder used by walls/ghosts/taxis/pedestrians/the Word Mode
## power-up). Run with
##   godot --headless --path . --script res://tests/test_word_mesh.gd
## Exits with code 0 on success, 1 on any failure.

func _initialize() -> void:
	var wm = load("res://scripts/word_mesh.gd")
	var failures := 0
	var checks := 0

	var mi = wm.build("WALL", Color(0.25, 1.0, 0.35))
	checks += 1
	if not (mi is MeshInstance3D):
		failures += 1
		print("FAIL build() should return a MeshInstance3D")

	checks += 1
	if mi.mesh == null or not (mi.mesh is TextMesh):
		failures += 1
		print("FAIL build() mesh should be a TextMesh")

	checks += 1
	if mi.mesh.text != "WALL":
		failures += 1
		print("FAIL TextMesh.text should be 'WALL', got '%s'" % mi.mesh.text)

	checks += 1
	if mi.mesh.get_surface_count() != 1:
		failures += 1
		print("FAIL TextMesh should produce geometry (surface_count=%d)" % mi.mesh.get_surface_count())

	checks += 1
	var mat = mi.mesh.material
	if mat == null or not (mat is StandardMaterial3D):
		failures += 1
		print("FAIL TextMesh.material should be a StandardMaterial3D")
	elif mat.albedo_color != Color(0.25, 1.0, 0.35):
		failures += 1
		print("FAIL material albedo_color should match the requested color, got %s" % mat.albedo_color)

	# Different words should produce different geometry (different AABB
	# width at minimum) — this is what makes "TAXI" visibly not "GHOST".
	var mi_taxi = wm.build("TAXI", Color(1.0, 0.8, 0.0))
	var mi_ghost = wm.build("GHOST", Color(1.0, 1.0, 1.0))
	checks += 1
	if mi_taxi.mesh.get_aabb().size.x == mi_ghost.mesh.get_aabb().size.x:
		failures += 1
		print("FAIL TAXI and GHOST word meshes should differ in width")

	# measure_width should agree with an actually-built mesh's own AABB.
	checks += 1
	var measured: float = wm.measure_width("WALL")
	var built_width: float = mi.mesh.get_aabb().size.x
	if absf(measured - built_width) > 0.001:
		failures += 1
		print("FAIL measure_width mismatch: measured=%f built=%f" % [measured, built_width])

	# Custom options (font_size/depth/emission_energy) should actually apply.
	var mi_big = wm.build("TAXI", Color(1, 1, 0), {"font_size": 96, "depth": 0.6, "emission_energy": 2.5})
	checks += 1
	# depth is stored as float32 internally, so compare with tolerance
	# rather than exact equality against the double literal above.
	if mi_big.mesh.font_size != 96 or absf(mi_big.mesh.depth - 0.6) > 0.0001:
		failures += 1
		print("FAIL custom font_size/depth options were not applied (font_size=%d depth=%f)" % [mi_big.mesh.font_size, mi_big.mesh.depth])
	checks += 1
	if mi_big.mesh.material.emission_energy_multiplier != 2.5:
		failures += 1
		print("FAIL custom emission_energy option was not applied")

	print("")
	if failures == 0:
		print("ALL %d WORD MESH CHECKS PASSED" % checks)
		quit(0)
	else:
		print("%d/%d WORD MESH CHECKS FAILED" % [failures, checks])
		quit(1)
