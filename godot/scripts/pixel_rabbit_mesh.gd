extends RefCounted
## PixelRabbitMesh — the white rabbit of the speedrun levels as a small
## voxel figure (cube MultiMesh, same technique as cloud_mesh.gd /
## ghost_mesh.gd), see MazeView._build_rabbit_mesh.
##
## UX-W3 (03.10. review): the old figure was a flat front-facing head with
## ears, which read as a white blob from most angles and nearly vanished edge
## on. It is now a sitting rabbit in 3D — body, head, two long upright ears,
## tail, front paws — voxelised from a few ellipsoids, so its silhouette is a
## rabbit from every side while it slowly turns. Two small dark eye voxels
## per side; everything else rabbit white (#F2F2ED).
##
## "Follow the white rabbit" is a generic, public-domain-old motif (Alice in
## Wonderland and countless unrelated uses since) — this is an original
## blocky figure, not a depiction of any specific copyrighted character.
##
## Static-only utility — call PixelRabbitMeshScript.build(...) directly.

## Ellipsoids in metres (figure facing +X, feet at y = 0):
## [center, radii]. Ears lean back a little (see _in_shape).
const SHAPES := [
	{"name": "body", "c": Vector3(-0.02, 0.24, 0.0), "r": Vector3(0.25, 0.22, 0.17)},
	{"name": "chest", "c": Vector3(0.12, 0.28, 0.0), "r": Vector3(0.13, 0.17, 0.14)},
	{"name": "head", "c": Vector3(0.20, 0.52, 0.0), "r": Vector3(0.14, 0.12, 0.115)},
	{"name": "snout", "c": Vector3(0.31, 0.49, 0.0), "r": Vector3(0.06, 0.06, 0.07)},
	{"name": "ear_l", "c": Vector3(0.15, 0.80, 0.055), "r": Vector3(0.045, 0.21, 0.032)},
	{"name": "ear_r", "c": Vector3(0.15, 0.80, -0.055), "r": Vector3(0.045, 0.21, 0.032)},
	{"name": "tail", "c": Vector3(-0.27, 0.20, 0.0), "r": Vector3(0.07, 0.07, 0.07)},
	{"name": "paw_l", "c": Vector3(0.20, 0.04, 0.07), "r": Vector3(0.08, 0.045, 0.045)},
	{"name": "paw_r", "c": Vector3(0.20, 0.04, -0.07), "r": Vector3(0.08, 0.045, 0.045)},
	{"name": "foot_l", "c": Vector3(-0.08, 0.04, 0.12), "r": Vector3(0.14, 0.045, 0.05)},
	{"name": "foot_r", "c": Vector3(-0.08, 0.04, -0.12), "r": Vector3(0.14, 0.045, 0.05)},
]
## Eyes: on both sides of the head, slightly forward.
const EYES := [Vector3(0.27, 0.55, 0.09), Vector3(0.27, 0.55, -0.09)]
const DEFAULT_VOXEL := 0.05
## Height of the figure (tips of the ears), metres, at voxel_size 0.05.
const HEIGHT := 1.01


static func _in_shape(p: Vector3, s: Dictionary) -> bool:
	var c: Vector3 = s.c
	var q := p
	if String(s.name).begins_with("ear"):
		# ears lean back: the higher, the further toward -X
		q.x += 0.12 * maxf(p.y - 0.62, 0.0)
	var d: Vector3 = (q - c) / s.r
	return d.length_squared() <= 1.0


## Voxel centres of the figure (body) and of the eyes, for `voxel` size.
static func voxels(voxel: float = DEFAULT_VOXEL) -> Dictionary:
	var body: Array = []
	var eyes: Array = []
	var x0 := -0.40
	var x1 := 0.42
	var y0 := 0.0
	var y1 := 1.05
	var z0 := -0.22
	var z1 := 0.22
	var x := x0
	while x <= x1:
		var y := y0 + voxel * 0.5
		while y <= y1:
			var z := z0
			while z <= z1:
				var p := Vector3(x, y, z)
				var inside := false
				for s in SHAPES:
					if _in_shape(p, s):
						inside = true
						break
				if inside:
					var is_eye := false
					for e in EYES:
						if p.distance_to(e) < voxel * 0.9:
							is_eye = true
					if is_eye:
						eyes.append(p)
					else:
						body.append(p)
				z += voxel
			y += voxel
		x += voxel
	return {"body": body, "eyes": eyes}


## Builds the figure: a Node3D with the body MultiMesh ("Body", its material
## is the one MazeView outlines / exempts from fog) and the eye MultiMesh
## ("Eyes"). `options.voxel_size` scales the whole thing, `options.color`
## sets the body colour (default rabbit white).
static func build(options: Dictionary = {}) -> Node3D:
	var voxel_size: float = float(options.get("voxel_size", DEFAULT_VOXEL))
	var color: Color = options.get("color", Color("f2f2ed"))
	var vox := voxels(voxel_size)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 0.85
	mat.roughness = 0.7

	var eye_mat := StandardMaterial3D.new()
	eye_mat.albedo_color = Color(0.06, 0.05, 0.08)
	eye_mat.roughness = 0.4

	var root := Node3D.new()
	root.add_child(_multimesh("Body", vox.body, voxel_size, mat))
	root.add_child(_multimesh("Eyes", vox.eyes, voxel_size * 1.02, eye_mat))
	return root


static func _multimesh(node_name: String, positions: Array, voxel_size: float, mat: Material) -> MultiMeshInstance3D:
	var box := BoxMesh.new()
	box.size = Vector3.ONE * voxel_size
	box.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = box
	mm.instance_count = positions.size()
	for i in positions.size():
		mm.set_instance_transform(i, Transform3D(Basis(), positions[i]))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	return mmi


## The body material of a figure built by build().
static func body_material(figure: Node3D) -> StandardMaterial3D:
	var body: MultiMeshInstance3D = figure.get_node("Body")
	return body.multimesh.mesh.material
