extends RefCounted
## PsychedelicHeadMesh — an original, non-representational "gonzo trip"
## mascot for the Fear & Loathing pickup (see
## MazeView._build_fear_powerup_mesh): an abstract, kaleidoscope-colored
## head — a plain skull sphere, two oversized mismatched cartoon eyes, and
## a ring of small orbiting color spheres whose hues MazeView._process
## cycles over time for the "tripping" look.
##
## Deliberately an original shape built from primitives (same technique as
## word_mesh.gd/cloud_mesh.gd elsewhere in this project) — not a likeness
## of any real person or a depiction of any specific film's character
## design, which this project does not reproduce.
##
## Static-only utility (no autoload, no instance state) — call
## PsychedelicHeadMeshScript.build() directly on the preloaded script. The
## returned node's orbiting spheres are named "aura0".."auraN" so callers
## can find and re-color them each frame (see MazeView._process).

const AURA_COUNT := 6


static func build() -> Node3D:
	var root := Node3D.new()
	root.name = "PsychedelicHead"

	var skull := _sphere("skull", 0.26, Color(0.92, 0.88, 0.95))
	root.add_child(skull)

	var eye_l := _sphere("eye_l", 0.095, Color(1.0, 0.9, 0.2))
	eye_l.position = Vector3(-0.11, 0.03, 0.21)
	root.add_child(eye_l)

	var eye_r := _sphere("eye_r", 0.08, Color(0.2, 0.9, 1.0))
	eye_r.position = Vector3(0.11, 0.045, 0.21)
	root.add_child(eye_r)

	for i in AURA_COUNT:
		var a := float(i) / float(AURA_COUNT) * TAU
		var orb := _sphere("aura%d" % i, 0.045, Color.from_hsv(a / TAU, 0.9, 1.0))
		orb.position = Vector3(cos(a) * 0.42, sin(a * 1.7) * 0.12, sin(a) * 0.42)
		root.add_child(orb)

	return root


static func _sphere(node_name: String, radius: float, color: Color) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 1.4
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.material_override = mat
	return mi
