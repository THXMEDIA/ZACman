extends RefCounted
## GhostMesh — builds a small blocky "pixel-art" ghost (MultiMesh of cube
## voxels forming a classic Pac-Man-ghost silhouette: rounded dome top,
## rectangular body, zig-zag skirt) instead of the plain smooth sphere the
## enemies used to be. Chunky/blocky by design — the same retro-pixel
## aesthetic as ascii_post.gdshader's Matrix look and word_mesh.gd's
## letterform objects, just applied to the enemies (per the user's "wie bei
## Space Invaders" request: blocky pixel sprites, not rounded 3D shapes).
##
## Static-only utility (no autoload, no instance state) — call
## GhostMeshScript.build(...) directly on the preloaded script.

## Ghost silhouette as an 8-row x 7-column pixel grid, top row first —
## dome top, solid body, then a 4-point zig-zag skirt at the bottom.
const PIXEL_ROWS := [
	".#####.",
	"#######",
	"#######",
	"#######",
	"#######",
	"#######",
	"#######",
	"#.#.#.#",
]
const COLS := 7
const ROWS := 8
const DEPTH_VOXELS := 2 # a couple of voxels deep so it reads as a solid from any angle, not a flat sprite


## Builds one ghost, voxels using `material` (so callers keep controlling
## color/emission the same way they already do for a StandardMaterial3D —
## e.g. Enemy's frightened/eaten recolor just mutates the material in place,
## no rebuild needed). `options.voxel_size` scales the whole ghost.
static func build(material: StandardMaterial3D, options: Dictionary = {}) -> MultiMeshInstance3D:
	var voxel_size: float = float(options.get("voxel_size", 0.095))

	var box := BoxMesh.new()
	box.size = Vector3.ONE * voxel_size
	box.material = material

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
