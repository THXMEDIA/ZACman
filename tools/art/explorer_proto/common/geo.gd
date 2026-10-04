# Gemeinsame Geometrie-Helfer fuer die Explorer-Stil-Prototypen (Art Director, Phase 1).
# NICHT Spielcode. Baut Primitive (Boxen, Kugeln, Figuren, Fahrzeuge, Kugelreihen) mit
# beliebigen Materialien; die Stilrichtungen liegen in <richtung>/city.gd.
extends RefCounted
class_name ProtoGeo

static func mat(shader_code: String, params: Dictionary = {}) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = shader_code
	var m := ShaderMaterial.new()
	m.shader = sh
	for k in params:
		m.set_shader_parameter(k, params[k])
	return m

static func clone(m: ShaderMaterial, params: Dictionary) -> ShaderMaterial:
	var c := m.duplicate() as ShaderMaterial
	for k in params:
		c.set_shader_parameter(k, params[k])
	return c

static func box(parent: Node, pos: Vector3, size: Vector3, m: Material, rot_y := 0.0) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	mi.rotation.y = rot_y
	parent.add_child(mi)
	return mi

static func sphere(parent: Node, pos: Vector3, r: float, m: Material, scale := Vector3.ONE, segs := 24) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = r
	mesh.height = r * 2.0
	mesh.radial_segments = segs
	mesh.rings = int(segs / 2)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	mi.scale = scale
	parent.add_child(mi)
	return mi

static func cylinder(parent: Node, pos: Vector3, r_top: float, r_bot: float, h: float, m: Material, segs := 16) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = r_top
	mesh.bottom_radius = r_bot
	mesh.height = h
	mesh.radial_segments = segs
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi

static func quad(parent: Node, pos: Vector3, size: Vector2, m: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var mesh := QuadMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi

static func plane(parent: Node, pos: Vector3, size: Vector2, m: Material, subdiv := 1) -> MeshInstance3D:
	var mesh := PlaneMesh.new()
	mesh.size = size
	mesh.subdivide_width = subdiv
	mesh.subdivide_depth = subdiv
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi

# Passant: Kapsel-Koerper + Kugelkopf, ~1,7 m hoch, Fuesse auf pos.y.
static func figure(parent: Node, pos: Vector3, body_m: Material, head_m: Material, rot_y := 0.0, h := 1.7) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	n.rotation.y = rot_y
	parent.add_child(n)
	var body := CapsuleMesh.new()
	body.radius = 0.19 * h / 1.7
	body.height = 1.15 * h / 1.7
	var b := MeshInstance3D.new()
	b.mesh = body
	b.material_override = body_m
	b.position = Vector3(0, 0.78 * h / 1.7, 0)
	n.add_child(b)
	sphere(n, Vector3(0, 1.52 * h / 1.7, 0), 0.13 * h / 1.7, head_m, Vector3.ONE, 16)
	return n

# Fahrzeug als Primitive: Karosserie + Kabine + 4 Raeder.
static func car(parent: Node, pos: Vector3, rot_y: float, body_m: Material, wheel_m: Material, glass_m: Material, len := 4.2, wid := 1.8) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	n.rotation.y = rot_y
	parent.add_child(n)
	box(n, Vector3(0, 0.55, 0), Vector3(wid, 0.6, len), body_m)
	box(n, Vector3(0, 1.1, -0.2), Vector3(wid * 0.9, 0.55, len * 0.5), glass_m)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var w := cylinder(n, Vector3(sx * wid * 0.5, 0.33, sz * len * 0.33), 0.33, 0.33, 0.22, wheel_m, 14)
			w.rotation.z = PI / 2.0
	return n

# Kugelreihe als MultiMesh (eine Instanz pro Kugel), wie im Spiel.
static func pellets(parent: Node, points: Array, r: float, m: Material) -> MultiMeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = r
	mesh.height = r * 2.0
	mesh.radial_segments = 18
	mesh.rings = 9
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = points.size()
	for i in points.size():
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, points[i]))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = m
	parent.add_child(mmi)
	return mmi

static func pellet_line(a: Vector3, b: Vector3, step := 2.0) -> Array:
	var out := []
	var n := int(floor(a.distance_to(b) / step))
	for i in n + 1:
		out.append(a.lerp(b, float(i) / max(n, 1)))
	return out

# Billboard-Quad (Halo, Stern, Schriftzug) – richtet sich im Shader zur Kamera aus.
const BILLBOARD_VERTEX := """
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz),0,0,0), vec4(0,length(MODEL_MATRIX[1].xyz),0,0), vec4(0,0,1,0), vec4(0,0,0,1));
"""

# Inverted-Hull-Kontur: Kopie des Meshes, nach aussen geschoben, Rueckseiten sichtbar.
# mode 0: Box (von der Mitte weg), mode 1: entlang der Normale (Kugeln, Kapseln, Zylinder).
const HULL_SHADER := """
shader_type spatial;
render_mode unshaded, cull_front, fog_disabled;
uniform vec3 col : source_color = vec3(0.0);
uniform float width = 0.03;
uniform float px = 1.0; // 1 = Breite in Metern, 0 = Breite wird mit der Entfernung groesser (Bildschirm-konstant)
uniform int mode = 0;
void vertex(){
	vec3 dir = (mode == 0) ? sign(VERTEX) : NORMAL;
	vec3 wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float dist = length(wpos - CAMERA_POSITION_WORLD);
	float w = mix(width * (0.4 + dist * 0.06), width, px);
	vec3 scl = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	VERTEX += dir * w / scl;
}
void fragment(){ ALBEDO = col; }
"""

static func hull(mi: MeshInstance3D, col: Color, width: float, mode: int, px := 0.0, shader := HULL_SHADER) -> MeshInstance3D:
	var h := MeshInstance3D.new()
	h.mesh = mi.mesh
	h.material_override = mat(shader, {"col": col, "width": width, "mode": mode, "px": px})
	h.set_meta("nohull", true)
	mi.add_child(h)
	return h

static func hull_all(root: Node, col: Color, width: float, px := 0.0, skip: Array = [], shader := HULL_SHADER) -> void:
	for c in root.get_children():
		if c is MeshInstance3D and not (c in skip) and not c.has_meta("nohull"):
			var mode := 0 if c.mesh is BoxMesh else 1
			hull(c, col, width, mode, px, shader)
		hull_all(c, col, width, px, skip, shader)
