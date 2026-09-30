extends RefCounted
## PixelRabbitMesh — builds a small blocky white pixel-art rabbit (a
## MultiMesh of cube voxels, same technique as cloud_mesh.gd/ghost_mesh.gd)
## for the WORD power-up's pickup visual (see
## MazeView._build_word_powerup_mesh). "Follow the white rabbit" is a
## generic, public-domain-old motif (Alice in Wonderland, and countless
## unrelated uses since) — this is an original blocky silhouette of
## Claude's own design, not a depiction of any specific copyrighted
## character or artwork.
##
## Static-only utility (no autoload, no instance state) — call
## PixelRabbitMeshScript.build(...) directly on the preloaded script.

## A simple front-facing sitting-rabbit-head silhouette: two long ears,
## a round face, with two small gaps standing in for eyes. Top row first.
const PIXEL_ROWS := [
	"..##..##..",
	"..##..##..",
	"..##..##..",
	"..##..##..",
	".########.",
	"##########",
	"##.####.##",
	"##########",
	".########.",
	"..######..",
]
const COLS := 10
const ROWS := 10
const DEPTH_VOXELS := 2


## Builds one rabbit. `options.voxel_size` scales the whole thing;
## `options.color` overrides the default white.
static func build(options: Dictionary = {}) -> MultiMeshInstance3D:
	var voxel_size: float = float(options.get("voxel_size", 0.09))
	var color: Color = options.get("color", Color(0.97, 0.97, 1.0))

	var box := BoxMesh.new()
	box.size = Vector3.ONE * voxel_size

	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 0.6
	mat.roughness = 0.7
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
