extends RefCounted
## CloudMesh — builds a small blocky white "pixel cloud" (a MultiMesh of
## cube voxels, same technique as ghost_mesh.gd) for the Mario/Minecraft-
## style voxel sky scattered just below the ceiling on themes with
## CityTheme.ceil_sky_clouds set (see MazeView._build_sky_clouds).
##
## Static-only utility (no autoload, no instance state) — call
## CloudMeshScript.build(...) directly on the preloaded script.

## Classic "three-lobe" 8-bit cloud silhouette, top row first.
const PIXEL_ROWS := [
	".##...##.",
	"#########",
	"#########",
	".#######.",
]
const COLS := 9
const ROWS := 4
const DEPTH_VOXELS := 3


## Builds one cloud. `options.voxel_size` scales the whole cloud;
## `options.color` overrides the default white.
static func build(options: Dictionary = {}) -> MultiMeshInstance3D:
	var voxel_size: float = float(options.get("voxel_size", 0.12))
	var color: Color = options.get("color", Color(0.98, 0.98, 1.0))

	var box := BoxMesh.new()
	box.size = Vector3.ONE * voxel_size

	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 0.5
	mat.roughness = 0.8
	box.material = mat

	var total_w := COLS * voxel_size
	var total_h := ROWS * voxel_size
	var total_d := DEPTH_VOXELS * voxel_size

	var positions: Array = []
	for row in ROWS:
		var line: String = PIXEL_ROWS[row]
		for col in COLS:
			if line[col] != "#":
				continue
			var x := -total_w * 0.5 + col * voxel_size + voxel_size * 0.5
			var y := total_h * 0.5 - row * voxel_size - voxel_size * 0.5
			for layer in DEPTH_VOXELS:
				var z := -total_d * 0.5 + layer * voxel_size + voxel_size * 0.5
				positions.append(Vector3(x, y, z))

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = box
	mm.instance_count = positions.size()
	for i in positions.size():
		mm.set_instance_transform(i, Transform3D(Basis(), positions[i]))

	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	return mmi
