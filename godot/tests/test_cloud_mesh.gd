extends SceneTree
## Headless test: res://scripts/cloud_mesh.gd — the blocky white "pixel
## cloud" voxel cluster used for the Mario/Minecraft-style sky ceiling
## (CityTheme.ceil_sky_clouds). Pure-logic checks, no scene needed. Run
## with
##   godot --headless --path . --script res://tests/test_cloud_mesh.gd
## Exits with code 0 on success, 1 on any failure.

func _initialize() -> void:
	var CloudMesh = load("res://scripts/cloud_mesh.gd")
	var failures := 0
	var checks := 0

	# --- pixel grid shape: ROWS entries, each COLS characters wide -------
	checks += 1
	if CloudMesh.PIXEL_ROWS.size() != CloudMesh.ROWS:
		failures += 1
		print("FAIL PIXEL_ROWS should have ROWS (%d) entries, got %d" % [CloudMesh.ROWS, CloudMesh.PIXEL_ROWS.size()])
	checks += 1
	var all_rows_right_width := true
	for line in CloudMesh.PIXEL_ROWS:
		if line.length() != CloudMesh.COLS:
			all_rows_right_width = false
	if not all_rows_right_width:
		failures += 1
		print("FAIL every PIXEL_ROWS entry should be COLS (%d) characters wide" % CloudMesh.COLS)

	# --- build(): one voxel instance per '#' pixel, times DEPTH_VOXELS ---
	var expected_pixels := 0
	for line in CloudMesh.PIXEL_ROWS:
		for i in line.length():
			if line[i] == "#":
				expected_pixels += 1
	var expected_instances: int = expected_pixels * CloudMesh.DEPTH_VOXELS

	var cloud: MultiMeshInstance3D = CloudMesh.build()
	checks += 1
	if cloud == null or cloud.multimesh == null:
		failures += 1
		print("FAIL build() should return a MultiMeshInstance3D with a multimesh set")
	else:
		checks += 1
		if cloud.multimesh.instance_count != expected_instances:
			failures += 1
			print("FAIL expected %d voxel instances (one per '#' pixel x %d deep), got %d" % [expected_instances, CloudMesh.DEPTH_VOXELS, cloud.multimesh.instance_count])

	# --- default color is white-ish; an override is honored --------------
	checks += 1
	var default_mat: StandardMaterial3D = cloud.multimesh.mesh.material
	if default_mat.albedo_color.get_luminance() < 0.8:
		failures += 1
		print("FAIL default cloud color should be a bright white, got %s" % default_mat.albedo_color)

	var pink := Color(1.0, 0.2, 0.6)
	var custom_cloud: MultiMeshInstance3D = CloudMesh.build({"color": pink})
	checks += 1
	var custom_mat: StandardMaterial3D = custom_cloud.multimesh.mesh.material
	if not custom_mat.albedo_color.is_equal_approx(pink):
		failures += 1
		print("FAIL a color override in options should be used, got %s" % custom_mat.albedo_color)

	print("")
	if failures == 0:
		print("ALL %d CLOUD MESH CHECKS PASSED" % checks)
		quit(0)
	else:
		print("%d/%d CLOUD MESH CHECKS FAILED" % [failures, checks])
		quit(1)
