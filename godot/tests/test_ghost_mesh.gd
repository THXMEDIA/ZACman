extends SceneTree
## Headless test: res://scripts/ghost_mesh.gd — the blocky pixel-art ghost
## that replaced the enemies' plain sphere mesh. Pure-logic checks (voxel
## count, sizing), no scene needed. Run with
##   godot --headless --path . --script res://tests/test_ghost_mesh.gd
## Exits with code 0 on success, 1 on any failure.

func _initialize() -> void:
	var GhostMesh = load("res://scripts/ghost_mesh.gd")
	var failures := 0
	var checks := 0

	# --- pixel grid shape: 8 rows x 7 columns, as documented -------------
	checks += 1
	if GhostMesh.PIXEL_ROWS.size() != GhostMesh.ROWS:
		failures += 1
		print("FAIL PIXEL_ROWS should have ROWS (%d) entries, got %d" % [GhostMesh.ROWS, GhostMesh.PIXEL_ROWS.size()])
	checks += 1
	var all_rows_right_width := true
	for line in GhostMesh.PIXEL_ROWS:
		if line.length() != GhostMesh.COLS:
			all_rows_right_width = false
	if not all_rows_right_width:
		failures += 1
		print("FAIL every PIXEL_ROWS entry should be COLS (%d) characters wide" % GhostMesh.COLS)

	# --- build(): one voxel instance per '#' pixel, times DEPTH_VOXELS ---
	var expected_pixels := 0
	for line in GhostMesh.PIXEL_ROWS:
		for i in line.length():
			if line[i] == "#":
				expected_pixels += 1
	var expected_instances: int = expected_pixels * GhostMesh.DEPTH_VOXELS

	var mat := StandardMaterial3D.new()
	var ghost: MultiMeshInstance3D = GhostMesh.build(mat)
	checks += 1
	if ghost == null or ghost.multimesh == null:
		failures += 1
		print("FAIL build() should return a MultiMeshInstance3D with a multimesh set")
	else:
		checks += 1
		if ghost.multimesh.instance_count != expected_instances:
			failures += 1
			print("FAIL expected %d voxel instances (one per '#' pixel x %d deep), got %d" % [expected_instances, GhostMesh.DEPTH_VOXELS, ghost.multimesh.instance_count])
		checks += 1
		if ghost.multimesh.mesh == null or ghost.multimesh.mesh.material != mat:
			failures += 1
			print("FAIL the given material should end up on the multimesh's box mesh (so callers can recolor it live)")

	# --- the ghost is roughly centered on its own origin (no lopsided offset) ---
	checks += 1
	var min_pos := Vector3.INF
	var max_pos := -Vector3.INF
	for i in ghost.multimesh.instance_count:
		var p: Vector3 = ghost.multimesh.get_instance_transform(i).origin
		min_pos = min_pos.min(p)
		max_pos = max_pos.max(p)
	var center := (min_pos + max_pos) * 0.5
	if absf(center.x) > 0.02 or absf(center.z) > 0.02:
		failures += 1
		print("FAIL ghost voxels should be centered on X/Z (footprint center ~%s)" % [center])

	print("")
	if failures == 0:
		print("ALL %d GHOST MESH CHECKS PASSED" % checks)
		quit(0)
	else:
		print("%d/%d GHOST MESH CHECKS FAILED" % [failures, checks])
		quit(1)
