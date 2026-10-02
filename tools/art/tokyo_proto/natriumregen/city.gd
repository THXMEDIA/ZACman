# Tokyo/Shibuya-Prototyp fuer ZACman (Art-Direction Phase 1, NICHT Spielcode).
# Baut eine kleine Kreuzungsszene aus Neon-Konturen nach einem Stil-Dictionary
# (style.gd). Compatibility-Renderer: Spiegelungen ueber planaren Spiegel per
# SubViewport (gespiegelte Kamera), Glow ueber WorldEnvironment.
extends Node3D

var style: Dictionary = {}
var cam: Camera3D
var refl_vp: SubViewport
var refl_cam: Camera3D
var floor_mat: ShaderMaterial
var rain_mm: MultiMeshInstance3D
var rain_mat: ShaderMaterial
var rng := RandomNumberGenerator.new()
var batches := {}      # key -> {st, mat}
var pools: Array = []  # [Vector3 pos, float radius, Color col, float intensity]
var rain_lights: Array = [] # [Vector3 pos, Color col, float strength]
var font: SystemFont

const FLOOR_LAYER := 2

const LINE_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform vec3 col = vec3(1.0);
uniform float energy = 2.0;
uniform float fade_h = 60.0;
uniform float top_mul = 0.35;
varying float wy;
void vertex(){ wy = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y; }
void fragment(){
	float f = mix(1.0, top_mul, smoothstep(0.0, fade_h, wy));
	ALBEDO = col * energy * f;
}
"""

const SOLID_SHADER := """
shader_type spatial;
render_mode unshaded;
uniform vec3 col = vec3(0.0);
void fragment(){ ALBEDO = col; }
"""

const ORB_SHADER := """
shader_type spatial;
render_mode unshaded;
uniform vec3 col = vec3(1.0);
uniform vec3 core = vec3(1.0);
uniform float energy = 3.0;
void fragment(){
	float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	ALBEDO = mix(col, core, pow(ndv, 3.0)) * energy * (0.75 + 0.25 * ndv);
}
"""

const HALO_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled;
uniform vec3 col = vec3(1.0);
uniform float energy = 1.0;
uniform float power = 2.2;
void vertex(){
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}
void fragment(){
	float d = length(UV - 0.5) * 2.0;
	float a = pow(max(1.0 - d, 0.0), power);
	ALBEDO = col * energy * a;
	ALPHA = 1.0;
}
"""

const CONE_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled;
uniform vec3 col = vec3(1.0);
uniform float energy = 0.3;
uniform float height = 10.0;
varying float t;
void vertex(){ t = clamp(0.5 - VERTEX.y / height, 0.0, 1.0); }
void fragment(){
	float edge = pow(abs(dot(NORMAL, VIEW)), 1.6);
	float a = pow(1.0 - t, 1.6) * edge;
	ALBEDO = col * energy * a;
	ALPHA = 1.0;
}
"""

const SCREEN_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform vec3 ca = vec3(1.0, 0.2, 0.8);
uniform vec3 cb = vec3(1.0, 0.6, 0.2);
uniform float energy = 2.0;
uniform float seed = 0.0;
uniform float mono = 0.0;
void fragment(){
	vec2 uv = UV;
	float bands = 0.5 + 0.5 * sin(uv.y * 14.0 + seed * 3.0 + sin(uv.x * 5.0 + seed) * 1.8);
	float circ = smoothstep(0.30, 0.27, distance(uv * vec2(1.0, 2.0), vec2(0.5 + 0.15 * sin(seed * 2.0), 1.35)));
	float ring = smoothstep(0.012, 0.0, abs(distance(uv * vec2(1.0, 2.0), vec2(0.5, 0.55)) - 0.28));
	vec3 c = mix(ca, cb, bands);
	c = mix(c, vec3(1.0), circ * 0.55 + ring * 0.8);
	c = mix(c, vec3(dot(c, vec3(0.33))), mono);
	c *= 0.82 + 0.18 * step(0.5, fract(uv.y * 140.0));
	float frame = step(0.02, uv.x) * step(uv.x, 0.98) * step(0.01, uv.y) * step(uv.y, 0.99);
	ALBEDO = c * energy * mix(0.25, 1.0, frame);
}
"""

const SHOP_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;
uniform vec3 col = vec3(1.0, 0.55, 0.15);
uniform float energy = 0.6;
uniform float seg = 5.0;
uniform float width = 20.0;
void fragment(){
	float x = UV.x * width;
	float cell = fract(x / seg) * seg;
	float divider = step(0.35, cell) * step(cell, seg - 0.35);
	float win = step(0.25, UV.y) * step(UV.y, 0.92);
	float lit = step(0.35, fract(sin(floor(x / seg) * 12.9898 + seg) * 43758.5453));
	float v = smoothstep(0.0, 0.25, UV.y) * smoothstep(1.0, 0.7, UV.y);
	float var = 0.6 + 0.4 * fract(sin(floor(x / seg) * 91.7) * 4375.85);
	ALBEDO = col * energy * (v * divider * win * var * lit + 0.012);
	ALPHA = 1.0;
}
"""

const RAIN_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled, skip_vertex_transform;
uniform vec3 col = vec3(0.7, 0.75, 0.85);
uniform float base = 0.05;
uniform float lit = 1.0;
uniform float width = 0.018;
uniform vec4 lpos[12];
uniform vec4 lcol[12];
uniform int ln = 0;
varying vec3 wp;
void vertex(){
	vec3 c = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 ax = MODEL_MATRIX[1].xyz;
	vec3 tocam = CAMERA_POSITION_WORLD - c;
	vec3 side = normalize(cross(normalize(ax), tocam)) * width;
	wp = c + ax * VERTEX.y + side * VERTEX.x * 2.0;
	VERTEX = (VIEW_MATRIX * vec4(wp, 1.0)).xyz;
}
void fragment(){
	vec3 v = normalize(wp - CAMERA_POSITION_WORLD);
	float dist = distance(wp, CAMERA_POSITION_WORLD);
	vec3 acc = col * base;
	for (int i = 0; i < 12; i++) {
		if (i >= ln) break;
		vec3 L = lpos[i].xyz - wp;
		float d = length(L);
		float back = pow(max(dot(normalize(L), v), 0.0), 3.0);
		acc += lcol[i].rgb * lcol[i].a * (0.25 + back * 2.5) / (1.0 + d * d * lpos[i].w);
	}
	float fade = 1.0 - smoothstep(10.0, 38.0, dist);
	float near = smoothstep(1.5, 6.0, dist);
	ALBEDO = acc * lit * fade * near;
	ALPHA = 1.0;
}
"""

const FLOOR_SHADER := """
shader_type spatial;
render_mode unshaded;
uniform sampler2D refl_tex : filter_linear, repeat_disable;
uniform vec3 asphalt_col = vec3(0.05);
uniform vec3 walk_col = vec3(0.07);
uniform vec3 paint_col = vec3(0.4);
uniform vec3 spill_col = vec3(1.0, 0.5, 0.1);
uniform float spill = 0.4;
uniform float puddle_amount = 0.5;
uniform float refl_strength = 1.0;
uniform float streak = 0.06;
uniform float ripple = 0.004;
uniform float asphalt_wet = 0.5;
uniform float glass = 0.0;
uniform vec4 pool_pos[32];
uniform vec4 pool_col[32];
uniform int pool_n = 0;
varying vec3 wpos;
void vertex(){ wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
float hash(vec2 p){ return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p){
	vec2 i = floor(p); vec2 f = fract(p); vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
float fbm(vec2 p){ float a = 0.5; float s = 0.0; for (int i = 0; i < 4; i++){ s += a * vnoise(p); p *= 2.03; a *= 0.5; } return s; }
float stripes(float t, float period, float duty){ return step(fract(t / period), duty); }
void fragment(){
	vec2 p = wpos.xz;
	float ax = abs(p.x); float az = abs(p.y);
	bool road = (ax < 9.0) || (az < 9.0);
	vec3 base = road ? asphalt_col : walk_col;
	float paint = 0.0;
	if (road) {
		if (az > 9.6 && az < 13.0 && ax < 8.6) paint = stripes(p.x + 0.25, 1.0, 0.5);
		if (ax > 9.6 && ax < 13.0 && az < 8.6) paint = stripes(p.y + 0.25, 1.0, 0.5);
		if (ax < 8.8 && az < 8.8) {
			float d1 = (p.x + p.y) * 0.7071; float d2 = (p.x - p.y) * 0.7071;
			if (abs(d2) < 1.7) paint = max(paint, stripes(d1, 1.0, 0.5));
			if (abs(d1) < 1.7) paint = max(paint, stripes(d2, 1.0, 0.5));
		}
		if (ax < 0.1 && az > 14.0) paint = max(paint, stripes(p.y, 6.0, 0.5));
		if (az < 0.1 && ax > 14.0) paint = max(paint, stripes(p.x, 6.0, 0.5));
		if (az > 13.3 && az < 13.6 && ax < 8.8) paint = 1.0;
		if (ax > 13.3 && ax < 13.6 && az < 8.8) paint = 1.0;
	} else {
		float tile = step(0.05, fract(p.x / 1.2)) * step(0.05, fract(p.y / 1.2));
		base *= mix(0.7, 1.0, tile);
	}
	float n = fbm(p * 0.2);
	float n2 = fbm(p * 1.9 + 13.0);
	float thr = 0.66 - puddle_amount * 0.3;
	float puddle = smoothstep(thr, thr + 0.03, n + (n2 - 0.5) * 0.1);
	puddle = max(puddle, glass);
	paint *= 1.0 - puddle * 0.75;
	vec2 suv = vec2(SCREEN_UV.x, 1.0 - SCREEN_UV.y);
	vec2 rip = (vec2(vnoise(p * 4.5), vnoise(p * 4.5 + 5.2)) - 0.5) * ripple;
	vec3 blur = vec3(0.0);
	for (int i = 0; i < 14; i++) {
		float t = (float(i) / 13.0 - 0.3) * streak;
		blur += texture(refl_tex, suv + rip + vec2((hash(p + float(i)) - 0.5) * streak * 0.08, t)).rgb;
	}
	blur /= 14.0;
	vec3 sharp = texture(refl_tex, suv + rip * 0.12).rgb;
	float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fres = 0.18 + 0.82 * pow(1.0 - ndv, 3.0);
	float wet = mix(asphalt_wet * (road ? 1.0 : 0.6), 1.0, puddle) * (1.0 - paint * 0.6);
	vec3 refl = mix(blur * 1.15, sharp, puddle) * fres * wet * refl_strength;
	vec3 lp = vec3(0.0);
	for (int i = 0; i < 32; i++) {
		if (i >= pool_n) break;
		vec2 dd = p - pool_pos[i].xz;
		float r = pool_pos[i].w;
		lp += pool_col[i].rgb * pool_col[i].a * exp(-dot(dd, dd) / (r * r));
	}
	float dshop = length(max(vec2(13.0 - ax, 13.0 - az), vec2(0.0)));
	float sp = road ? 0.0 : exp(-dshop * 0.55) * spill;
	vec3 albedo = mix(base, paint_col, paint) * (1.0 - puddle * 0.65);
	vec3 lit = albedo * (vec3(1.0) + lp * 3.0 + spill_col * sp * 3.0);
	lit += (lp + spill_col * sp) * 0.06 * (1.0 - puddle);
	ALBEDO = lit + refl;
}
"""

# ---------------------------------------------------------------- helpers

func S(k: String, d = null):
	return style.get(k, d)

func _ready() -> void:
	rng.seed = 4711
	font = SystemFont.new()
	font.font_names = PackedStringArray(["Noto Sans CJK JP", "IPAGothic"])
	font.font_weight = 700
	_setup_env()
	_setup_cameras()
	_build_floor()
	_build_city()
	_build_traffic()
	_build_people()
	_build_orbs_and_metro()
	_finalize_batches()
	_build_rain()
	_apply_pools()

func _process(_d: float) -> void:
	update_reflection()

func update_reflection() -> void:
	if cam == null or refl_cam == null:
		return
	var p := cam.global_position
	var f := -cam.global_transform.basis.z
	var pm := Vector3(p.x, -p.y, p.z)
	var fm := Vector3(f.x, -f.y, f.z)
	refl_cam.fov = cam.fov
	refl_cam.near = cam.near
	refl_cam.far = cam.far
	refl_cam.look_at_from_position(pm, pm + fm, Vector3.UP)

func set_view(pos: Vector3, target: Vector3, fov: float) -> void:
	cam.fov = fov
	cam.look_at_from_position(pos, target, Vector3.UP)
	update_reflection()
	_place_rain(pos)

func _mat(shader_code: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = shader_code
	m.shader = sh
	return m

func _v3(c: Color) -> Vector3:
	return Vector3(c.r, c.g, c.b)

func line_mat(col: Color, energy: float, fade := true) -> ShaderMaterial:
	var m := _mat(LINE_SHADER)
	m.set_shader_parameter("col", _v3(col))
	m.set_shader_parameter("energy", energy)
	m.set_shader_parameter("fade_h", S("fade_h", 60.0))
	m.set_shader_parameter("top_mul", S("top_mul", 0.35) if fade else 1.0)
	return m

func _batch(key: String, col: Color, energy: float, fade := true) -> SurfaceTool:
	if not batches.has(key):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		batches[key] = {"st": st, "mat": line_mat(col, energy, fade)}
	return batches[key]["st"]

const CUBE_FACES := [
	[Vector3(-1,-1, 1), Vector3( 1,-1, 1), Vector3( 1, 1, 1), Vector3(-1, 1, 1)],
	[Vector3( 1,-1,-1), Vector3(-1,-1,-1), Vector3(-1, 1,-1), Vector3( 1, 1,-1)],
	[Vector3( 1,-1, 1), Vector3( 1,-1,-1), Vector3( 1, 1,-1), Vector3( 1, 1, 1)],
	[Vector3(-1,-1,-1), Vector3(-1,-1, 1), Vector3(-1, 1, 1), Vector3(-1, 1,-1)],
	[Vector3(-1, 1, 1), Vector3( 1, 1, 1), Vector3( 1, 1,-1), Vector3(-1, 1,-1)],
	[Vector3(-1,-1,-1), Vector3( 1,-1,-1), Vector3( 1,-1, 1), Vector3(-1,-1, 1)],
]

func _add_box(st: SurfaceTool, t: Transform3D) -> void:
	for f in CUBE_FACES:
		var q := []
		for v in f:
			q.append(t * (v * 0.5))
		st.add_vertex(q[0]); st.add_vertex(q[1]); st.add_vertex(q[2])
		st.add_vertex(q[0]); st.add_vertex(q[2]); st.add_vertex(q[3])

## Eine Neonroehre von a nach b.
func line(a: Vector3, b: Vector3, key: String, col: Color, energy: float, thick: float, fade := true) -> void:
	var d := b - a
	var L := d.length()
	if L < 0.001:
		return
	var y := d / L
	var x := y.cross(Vector3.UP)
	if x.length() < 0.01:
		x = y.cross(Vector3.RIGHT)
	x = x.normalized()
	var z := x.cross(y).normalized()
	var t := Transform3D(Basis(x * thick, y * (L + thick), z * thick), (a + b) * 0.5)
	_add_box(_batch(key, col, energy, fade), t)

func ring(center: Vector3, ax1: Vector3, ax2: Vector3, r: float, segs: int, key: String, col: Color, energy: float, thick: float, a0 := 0.0, a1 := TAU) -> void:
	var prev := center + (ax1 * cos(a0) + ax2 * sin(a0)) * r
	for i in range(1, segs + 1):
		var a := a0 + (a1 - a0) * float(i) / segs
		var p := center + (ax1 * cos(a) + ax2 * sin(a)) * r
		line(prev, p, key, col, energy, thick)
		prev = p

func _finalize_batches() -> void:
	for k in batches.keys():
		var b: Dictionary = batches[k]
		var st: SurfaceTool = b["st"]
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = b["mat"]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)

func solid_box(center: Vector3, size: Vector3, col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var m := _mat(SOLID_SHADER)
	m.set_shader_parameter("col", _v3(col))
	mi.material_override = m
	mi.position = center
	add_child(mi)
	return mi

func halo(pos: Vector3, size: float, col: Color, energy: float, power := 2.2) -> void:
	var hs: float = S("halo_scale", 1.0)
	if hs <= 0.0:
		return
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(size, size) * hs
	mi.mesh = q
	var m := _mat(HALO_SHADER)
	m.set_shader_parameter("col", _v3(col))
	m.set_shader_parameter("energy", energy * S("halo_energy", 1.0))
	m.set_shader_parameter("power", power)
	mi.material_override = m
	mi.position = pos
	add_child(mi)

func cone(from: Vector3, to: Vector3, r0: float, r1: float, col: Color, energy: float) -> void:
	var d := to - from
	var h := d.length()
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r0
	cm.bottom_radius = r1
	cm.height = h
	cm.cap_top = false
	cm.cap_bottom = false
	cm.radial_segments = 24
	mi.mesh = cm
	var m := _mat(CONE_SHADER)
	m.set_shader_parameter("col", _v3(col))
	m.set_shader_parameter("energy", energy * S("cone_energy", 1.0))
	m.set_shader_parameter("height", h)
	mi.material_override = m
	# Zylinder-Achse +Y zeigt von unten (bottom) nach oben (top): top=from
	var y := -d.normalized()
	var x := y.cross(Vector3.UP)
	if x.length() < 0.01:
		x = y.cross(Vector3.RIGHT)
	x = x.normalized()
	var z := x.cross(y)
	mi.transform = Transform3D(Basis(x, y, z), (from + to) * 0.5)
	add_child(mi)

func pool(pos: Vector3, radius: float, col: Color, intensity: float) -> void:
	pools.append([pos, radius, col, intensity])

func rain_light(pos: Vector3, col: Color, strength: float, falloff := 0.004) -> void:
	rain_lights.append([pos, col, strength, falloff])

func label(text: String, pos: Vector3, rot_y: float, size_px: float, col: Color, energy: float) -> void:
	var l := Label3D.new()
	l.text = text
	l.font = font
	l.font_size = 128
	l.outline_size = 0
	l.pixel_size = size_px / 128.0
	l.modulate = Color(col.r * energy, col.g * energy, col.b * energy, 1.0)
	l.shaded = false
	l.double_sided = true
	l.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	l.line_spacing = -20
	l.position = pos
	l.rotation.y = rot_y
	add_child(l)

# ---------------------------------------------------------------- setup

func _setup_env() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = S("bg", Color.BLACK)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.BLACK
	env.fog_enabled = true
	env.fog_light_color = S("fog_col", Color.BLACK)
	env.fog_density = S("fog_density", 0.01)
	env.fog_sky_affect = 1.0
	env.glow_enabled = true
	env.glow_intensity = S("glow_intensity", 0.9)
	env.glow_strength = S("glow_strength", 1.0)
	env.glow_bloom = S("glow_bloom", 0.0)
	env.glow_hdr_threshold = S("glow_threshold", 0.9)
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	for i in 7:
		env.set_glow_level(i, 0.0)
	env.set_glow_level(1, 1.0)
	env.set_glow_level(3, S("glow_wide", 0.8))
	env.set_glow_level(5, S("glow_wide", 0.8) * 0.8)
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = S("exposure", 1.0)
	env.tonemap_white = S("white", 6.0)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

func _setup_cameras() -> void:
	cam = Camera3D.new()
	cam.near = 0.05
	cam.far = 600.0
	cam.cull_mask = 0xFFFFF
	add_child(cam)
	cam.make_current()
	refl_vp = SubViewport.new()
	refl_vp.size = Vector2i(1280, 720)
	refl_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	refl_vp.msaa_3d = Viewport.MSAA_2X
	add_child(refl_vp)
	refl_cam = Camera3D.new()
	refl_cam.cull_mask = 0xFFFFF & ~(1 << (FLOOR_LAYER - 1))
	refl_cam.near = 0.05
	refl_cam.far = 600.0
	refl_vp.add_child(refl_cam)
	refl_cam.current = true

func _build_floor() -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(500, 500)
	mi.mesh = pm
	floor_mat = _mat(FLOOR_SHADER)
	floor_mat.set_shader_parameter("refl_tex", refl_vp.get_texture())
	for k in ["asphalt_col", "walk_col", "paint_col", "spill_col"]:
		floor_mat.set_shader_parameter(k, _v3(S(k, Color(0.05, 0.05, 0.05))))
	for k in ["spill", "puddle_amount", "refl_strength", "streak", "ripple", "asphalt_wet", "glass"]:
		if style.has(k):
			floor_mat.set_shader_parameter(k, style[k])
	mi.material_override = floor_mat
	mi.layers = 1 << (FLOOR_LAYER - 1)
	add_child(mi)

func _apply_pools() -> void:
	var pp := PackedColorArray()
	var pc := PackedColorArray()
	for p in pools:
		if pp.size() >= 32:
			break
		var v: Vector3 = p[0]
		pp.append(Color(v.x, v.y, v.z, p[1]))
		var c: Color = p[2]
		pc.append(Color(c.r, c.g, c.b, p[3]))
	floor_mat.set_shader_parameter("pool_pos", pp)
	floor_mat.set_shader_parameter("pool_col", pc)
	floor_mat.set_shader_parameter("pool_n", pp.size())

# ---------------------------------------------------------------- city

func world_col(i: int) -> Color:
	var cols: Array = S("world_cols", [Color.WHITE])
	return cols[i % cols.size()]

## Gebaeude: schwarze Masse + Neonkanten + Etagenbaender.
func block(x0: float, x1: float, z0: float, z1: float, h: float, ci := 0, opts := {}) -> void:
	var mass: Color = S("mass_col", Color.BLACK)
	solid_box(Vector3((x0 + x1) * 0.5, h * 0.5, (z0 + z1) * 0.5), Vector3(x1 - x0 - 0.1, h, z1 - z0 - 0.1), mass)
	var col: Color = opts.get("col", world_col(ci))
	var e: float = opts.get("energy", S("line_energy", 2.0))
	var th: float = opts.get("thick", S("line_thick", 0.14))
	var key := "w%d_%s" % [ci, str(opts.get("tag", ""))]
	var o := 0.06
	var X0 := x0 - o; var X1 := x1 + o; var Z0 := z0 - o; var Z1 := z1 + o
	var corners := [Vector3(X0, 0, Z0), Vector3(X1, 0, Z0), Vector3(X1, 0, Z1), Vector3(X0, 0, Z1)]
	var base_y: float = opts.get("base_y", 0.0)
	for i in 4:
		var a: Vector3 = corners[i]
		var b: Vector3 = corners[(i + 1) % 4]
		line(a + Vector3(0, base_y, 0), a + Vector3(0, h, 0), key, col, e, th)
		line(a + Vector3(0, h, 0), b + Vector3(0, h, 0), key, col, e, th)
	# Etagenbaender / Fensterbaender
	var step: float = opts.get("floor_step", S("floor_step", 4.0))
	var prob: float = opts.get("floor_prob", S("floor_prob", 0.5))
	var fth: float = th * S("floor_thick_mul", 0.5)
	if step > 0.0:
		var y := base_y + step
		if base_y < 1.0:
			y = 6.0
		while y < h - 1.0:
			if rng.randf() < prob:
				for i in 4:
					var a: Vector3 = corners[i]
					var b: Vector3 = corners[(i + 1) % 4]
					line(a + Vector3(0, y, 0), b + Vector3(0, y, 0), key + "f", col, e * S("floor_energy_mul", 0.6), fth)
			y += step
	# Senkrechte Pfosten (Fassadenraster)
	var mprob: float = opts.get("mullion_prob", S("mullion_prob", 0.0))
	var mstep: float = S("mullion_step", 3.0)
	if mprob > 0.0:
		for i in 4:
			var a: Vector3 = corners[i]
			var b: Vector3 = corners[(i + 1) % 4]
			var L := a.distance_to(b)
			var n := int(L / mstep)
			for k in range(1, n):
				if rng.randf() < mprob:
					var p := a.lerp(b, float(k) / n)
					line(p + Vector3(0, max(base_y, 2.6), 0), p + Vector3(0, h * rng.randf_range(0.5, 1.0), 0), key + "m", col, e * 0.45, fth * 0.8)
	if opts.get("sockel", true):
		_sockel(x0, x1, z0, z1)

## Ladenfront-Glow bis ~2 m + durchgehende Sockellinie an den Strassenseiten.
func _sockel(x0: float, x1: float, z0: float, z1: float) -> void:
	var sc: Color = S("sockel_col", Color(1, 0.55, 0.15))
	var se: float = S("sockel_energy", 2.5)
	var o := 0.12
	var faces := [
		[Vector3(x0 - o, 0, z0 - o), Vector3(x1 + o, 0, z0 - o)],
		[Vector3(x1 + o, 0, z0 - o), Vector3(x1 + o, 0, z1 + o)],
		[Vector3(x1 + o, 0, z1 + o), Vector3(x0 - o, 0, z1 + o)],
		[Vector3(x0 - o, 0, z1 + o), Vector3(x0 - o, 0, z0 - o)],
	]
	for f in faces:
		var a: Vector3 = f[0]
		var b: Vector3 = f[1]
		line(a + Vector3(0, 2.3, 0), b + Vector3(0, 2.3, 0), "sockel", sc, se, S("sockel_thick", 0.09), false)
		var shop_e: float = S("shop_energy", 0.5)
		if shop_e > 0.0:
			var mi := MeshInstance3D.new()
			var q := QuadMesh.new()
			var L := a.distance_to(b)
			q.size = Vector2(L, 2.2)
			mi.mesh = q
			var m := _mat(SHOP_SHADER)
			m.set_shader_parameter("col", _v3(S("shop_col", sc)))
			m.set_shader_parameter("energy", shop_e)
			m.set_shader_parameter("width", L)
			m.set_shader_parameter("seg", rng.randf_range(4.0, 7.0))
			mi.material_override = m
			var mid := (a + b) * 0.5 + Vector3(0, 1.1, 0)
			var dir := (b - a).normalized()
			mi.transform = Transform3D(Basis(dir, Vector3.UP, dir.cross(Vector3.UP)), mid)
			add_child(mi)

func round_tower(c: Vector3, r: float, h: float, ci: int) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r - 0.08
	cm.bottom_radius = r - 0.08
	cm.height = h
	cm.radial_segments = 40
	mi.mesh = cm
	var m := _mat(SOLID_SHADER)
	m.set_shader_parameter("col", _v3(S("mass_col", Color.BLACK)))
	mi.material_override = m
	mi.position = c + Vector3(0, h * 0.5, 0)
	add_child(mi)
	var col := world_col(ci)
	var e: float = S("line_energy", 2.0)
	var th: float = S("line_thick", 0.14)
	ring(c + Vector3(0, h, 0), Vector3.RIGHT, Vector3.BACK, r, 40, "rt", col, e, th)
	var y := 6.0
	while y < h - 1.0:
		if rng.randf() < S("floor_prob", 0.5):
			ring(c + Vector3(0, y, 0), Vector3.RIGHT, Vector3.BACK, r, 40, "rtf", col, e * S("floor_energy_mul", 0.6), th * 0.5)
		y += S("floor_step", 4.0)
	for i in 10:
		var a := TAU * i / 10.0
		var p := c + Vector3(cos(a), 0, sin(a)) * r
		line(p + Vector3(0, 6, 0), p + Vector3(0, h, 0), "rt", col, e * 0.7, th * 0.7)
	# umlaufendes Leuchtband (Akzent)
	var acc: Color = S("accent", col)
	var bandy := h - 7.0
	for k in 3:
		ring(c + Vector3(0, bandy + k * 0.45, 0), Vector3.RIGHT, Vector3.BACK, r + 0.12, 48, "band", acc, S("accent_energy", 3.0), 0.16)
	rain_light(c + Vector3(0, bandy, r), acc, 2.0)

func screen(center: Vector3, size: Vector2, rot_y: float, seed: float, text: String, energy_mul := 1.0) -> void:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = size
	mi.mesh = q
	var m := _mat(SCREEN_SHADER)
	m.set_shader_parameter("ca", _v3(S("screen_a", Color(1, 0.2, 0.8))))
	m.set_shader_parameter("cb", _v3(S("screen_b", Color(1, 0.6, 0.2))))
	m.set_shader_parameter("energy", S("screen_energy", 1.6) * energy_mul)
	m.set_shader_parameter("seed", seed)
	m.set_shader_parameter("mono", S("screen_mono", 0.0))
	mi.material_override = m
	mi.position = center
	mi.rotation.y = rot_y
	add_child(mi)
	var fwd := Vector3(sin(rot_y), 0, cos(rot_y))
	if text != "":
		label(text, center + fwd * 0.08, rot_y, size.x * 0.32, Color(1, 1, 1), S("screen_text_energy", 2.2) * energy_mul)
	var sc: Color = S("screen_light", S("screen_a", Color(1, 0.3, 0.8)))
	halo(center + fwd * 0.5, max(size.x, size.y) * 1.6, sc, S("screen_halo", 0.25) * energy_mul, 1.8)
	var ground := Vector3(center.x, 0, center.z) + fwd * (size.y * 0.5 + 3.0)
	pool(ground, size.x * 1.4, sc, 0.35 * energy_mul)
	rain_light(center + fwd * 1.0, sc, 3.0 * energy_mul, 0.002)

func vsign(pos: Vector3, rot_y: float, text: String, h: float, ci: int) -> void:
	# senkrechtes Ladenschild: Rahmen als Roehre + Schriftzeichen
	var fwd := Vector3(sin(rot_y), 0, cos(rot_y))
	var right := Vector3(cos(rot_y), 0, -sin(rot_y))
	var w := 1.4
	var col: Color = S("sign_col", world_col(ci))
	var e: float = S("sign_energy", 2.5)
	solid_box(pos + Vector3(0, h * 0.5, 0) - fwd * 0.15, Vector3(w, h, 0.25).rotated(Vector3.UP, 0) if abs(fwd.z) > 0.5 else Vector3(0.25, h, w), S("mass_col", Color.BLACK))
	var c := [pos - right * w * 0.5, pos + right * w * 0.5, pos + right * w * 0.5 + Vector3(0, h, 0), pos - right * w * 0.5 + Vector3(0, h, 0)]
	for i in 4:
		line(c[i], c[(i + 1) % 4], "sign", col, e, 0.07, false)
	var chars := ""
	for ch in text:
		chars += ch + "\n"
	label(chars.strip_edges(), pos + Vector3(0, h * 0.5, 0) + fwd * 0.02, rot_y, w * 0.75, col, e * 0.9)
	rain_light(pos + Vector3(0, h * 0.5, 0) + fwd, col, 1.0)

func _build_city() -> void:
	var fh: float = S("floor_step", 4.0)
	# SE-Ecke
	block(13, 34, 13, 36, 22, 0)
	block(13, 30, 38, 56, 16, 1)
	# SW-Ecke
	block(-34, -13, 13, 34, 18, 1)
	block(-30, -13, 36, 52, 26, 0)
	# NE: "Nordturm" mit grossem Vertikal-Screen
	block(13, 34, -34, -13, 24, 0)
	block(16, 31, -32, -16, 62, 0, {"sockel": false, "base_y": 24.0})
	screen(Vector3(21.5, 15.5, -12.85), Vector2(9.0, 15.0), 0.0, 1.3, "カ\nラ\nオ\nケ")
	# NW: "Rundturm" auf Sockelbau
	block(-34, -13, -36, -13, 7, 1)
	round_tower(Vector3(-23, 7, -24.5), 8.5, 30, 0)
	# Zwischenreihe vor dem Bahnhof
	block(13, 30, -46, -37, 12, 1)
	block(-30, -13, -46, -38, 10, 0)
	# Arme Ost/West
	block(36, 62, 13, 30, 20, 0)
	block(36, 60, -30, -13, 30, 1)
	block(-62, -36, 13, 30, 14, 0)
	block(-60, -36, -30, -13, 24, 1)
	# Bahnhofsfront (Ausgang in den Speedrun) am Nordende
	block(-40, 40, -64, -48, 13, 2, {"floor_prob": 0.0, "mullion_prob": 0.0, "sockel": false})
	# Erhoehter Steg ueber die Nord-Achse
	var sc: Color = world_col(S("steg_ci", 0))
	solid_box(Vector3(0, 6.6, -40), Vector3(26, 0.5, 3.2), S("mass_col", Color.BLACK))
	for zz in [-41.65, -38.35]:
		line(Vector3(-13, 6.4, zz), Vector3(13, 6.4, zz), "steg", sc, S("line_energy", 2.0) * 1.2, 0.12)
		line(Vector3(-13, 7.7, zz), Vector3(13, 7.7, zz), "steg", sc, S("line_energy", 2.0) * 0.8, 0.07)
		var x := -13.0
		while x <= 13.0:
			line(Vector3(x, 6.4, zz), Vector3(x, 7.7, zz), "steg", sc, S("line_energy", 2.0) * 0.4, 0.04)
			x += 1.6
	# Skydeck-Turm: hohe Kontur hinten
	block(22, 36, -118, -104, 150, 0, {"sockel": false, "floor_step": 12.0, "floor_prob": 0.6, "thick": 0.5})
	line(Vector3(29, 150, -111), Vector3(29, 172, -111), "w0_", world_col(0), S("line_energy", 2.0), 0.5)
	halo(Vector3(29, 172, -111), 10.0, S("beacon_col", Color(1, 0.2, 0.2)), 1.5)
	# Hintergrund-Lichtgeruest
	var n: int = S("bg_count", 70)
	for i in n:
		var a := rng.randf_range(-PI, PI)
		var d := rng.randf_range(75, 190)
		var cx := sin(a) * d
		var cz := cos(a) * d
		if cz > 40 and abs(cx) < 40:
			continue
		var w := rng.randf_range(10, 22)
		var dd := rng.randf_range(10, 22)
		var h := rng.randf_range(15, 70) * (1.0 + d / 200.0)
		block(cx - w * 0.5, cx + w * 0.5, cz - dd * 0.5, cz + dd * 0.5, h, (i % 2) + (1 if S("bg_dim_ci", false) else 0), {"sockel": false, "thick": 0.32, "energy": S("line_energy", 2.0) * S("bg_energy_mul", 0.7), "tag": "bg", "floor_step": fh * 2.0})
	# Ladenschilder (keine Marken; Allgemeinwoerter)
	vsign(Vector3(13.6, 3.2, 20.0), -PI / 2, "薬", 3.0, 1)
	vsign(Vector3(-13.6, 3.0, 17.0), PI / 2, "ラーメン", 6.5, 1)
	vsign(Vector3(-13.6, 3.0, -20.0), PI / 2, "居酒屋", 5.5, 2)
	screen(Vector3(-18.0, 10.0, 12.9), Vector2(8.0, 4.5), PI, 4.2, "", 0.7)
	screen(Vector3(12.9, 13.0, 26.0), Vector2(7.0, 4.0), -PI / 2, 2.7, "", 0.6)
	# Bordsteinkante
	var cc: Color = S("curb_col", Color(0.7, 0.75, 0.85))
	var ce: float = S("curb_energy", 0.8)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			line(Vector3(9.0 * sx, 0.12, 13.6 * sz), Vector3(9.0 * sx, 0.12, 48.0 * sz), "curb", cc, ce, 0.06, false)
			line(Vector3(13.6 * sx, 0.12, 9.0 * sz), Vector3(64.0 * sx, 0.12, 9.0 * sz), "curb", cc, ce, 0.06, false)
			ring(Vector3(13.0 * sx, 0.12, 13.0 * sz), Vector3(-sx, 0, 0), Vector3(0, 0, -sz), 4.0, 6, "curb", cc, ce, 0.06, 0.0, PI / 2)
	# Strassenlaternen (Natrium) entlang der Achsen
	var lc: Color = S("lamp_col", Color(1, 0.6, 0.25))
	for zz in [24.0, 40.0, -26.0]:
		for sx in [-1.0, 1.0]:
			_lamp(Vector3(9.6 * sx, 0, zz), -sx, lc)
	for xx in [24.0, -24.0, 44.0, -44.0]:
		_lamp(Vector3(xx, 0, 9.6), 0.0, lc, true)
	# Treffpunkt: sitzende Katze (generisch)
	_cat(Vector3(-11.2, 0, -11.2), lc)

func _lamp(p: Vector3, arm: float, col: Color, along_x := false) -> void:
	var lamp_line: Color = S("lamp_pole_col", Color(0.3, 0.32, 0.36))
	line(p, p + Vector3(0, 7.5, 0), "pole", lamp_line, S("pole_energy", 0.25), 0.07, false)
	var head := p + Vector3(arm * 1.6, 7.4, 0) if not along_x else p + Vector3(0, 7.4, -1.6)
	line(p + Vector3(0, 7.5, 0), head, "pole", lamp_line, S("pole_energy", 0.25), 0.07, false)
	line(head - Vector3(0.3, 0, 0), head + Vector3(0.3, 0, 0), "lamp", col, S("lamp_energy", 4.0), 0.12, false)
	halo(head, 3.0, col, S("lamp_halo", 0.5))
	pool(Vector3(head.x, 0, head.z), 5.0, col, S("lamp_pool", 0.25))
	rain_light(head, col, S("lamp_rain", 1.5), 0.02)

func _cat(p: Vector3, col: Color) -> void:
	var c: Color = S("cat_col", world_col(0))
	var e: float = S("line_energy", 2.0) * 0.6
	# Sockel
	var w := 0.8
	for y in [0.0, 0.9]:
		line(p + Vector3(-w, y, -w), p + Vector3(w, y, -w), "cat", c, e, 0.04)
		line(p + Vector3(w, y, -w), p + Vector3(w, y, w), "cat", c, e, 0.04)
		line(p + Vector3(w, y, w), p + Vector3(-w, y, w), "cat", c, e, 0.04)
		line(p + Vector3(-w, y, w), p + Vector3(-w, y, -w), "cat", c, e, 0.04)
	var b := p + Vector3(0, 0.9, 0)
	var fwd := Vector3(0.7071, 0, 0.7071)
	var side := Vector3(0.7071, 0, -0.7071)
	ring(b + Vector3(0, 0.45, 0), side, Vector3.UP, 0.42, 14, "cat", c, e * 1.3, 0.035, -PI * 0.5, PI * 0.5)
	line(b + side * 0.0 + Vector3(0, 0.03, 0), b + side * 0.0 + Vector3(0, 0.03, 0), "cat", c, e, 0.03)
	var hd := b + Vector3(0, 1.05, 0) + side * 0.15
	ring(hd, side, Vector3.UP, 0.2, 12, "cat", c, e * 1.3, 0.035)
	line(hd + Vector3(0, 0.13, 0) + side * -0.12, hd + Vector3(0, 0.34, 0) + side * -0.1, "cat", c, e * 1.3, 0.035)
	line(hd + Vector3(0, 0.34, 0) + side * -0.1, hd + Vector3(0, 0.18, 0) + side * 0.02, "cat", c, e * 1.3, 0.035)
	line(hd + Vector3(0, 0.13, 0) + side * 0.12, hd + Vector3(0, 0.34, 0) + side * 0.14, "cat", c, e * 1.3, 0.035)
	line(hd + Vector3(0, 0.34, 0) + side * 0.14, hd + Vector3(0, 0.17, 0) + side * 0.26, "cat", c, e * 1.3, 0.035)
	ring(b + Vector3(0, 0.25, 0) - side * 0.55, side, Vector3.UP, 0.25, 8, "cat", c, e * 1.3, 0.035, PI * 0.5, PI * 1.5)

# ---------------------------------------------------------------- traffic

func car(pos: Vector3, dir: Vector3) -> void:
	var f := dir.normalized()
	var r := f.cross(Vector3.UP).normalized()
	var u := Vector3.UP
	var bc: Color = S("car_col", Color(0.6, 0.65, 0.75))
	var be: float = S("car_energy", 0.8)
	var th := 0.045
	var P := func(fr: float, rr: float, uu: float) -> Vector3: return pos + f * fr + r * rr + u * uu
	# Karosserie
	var hl := 2.2; var hw := 0.9
	for uu in [0.35, 0.95]:
		line(P.call(hl, -hw, uu), P.call(hl, hw, uu), "car", bc, be, th)
		line(P.call(-hl, -hw, uu), P.call(-hl, hw, uu), "car", bc, be, th)
		line(P.call(hl, -hw, uu), P.call(-hl, -hw, uu), "car", bc, be, th)
		line(P.call(hl, hw, uu), P.call(-hl, hw, uu), "car", bc, be, th)
	for fr in [hl, -hl]:
		for rr in [-hw, hw]:
			line(P.call(fr, rr, 0.35), P.call(fr, rr, 0.95), "car", bc, be, th)
	# Kabine
	for rr in [-0.82, 0.82]:
		line(P.call(1.0, rr, 0.95), P.call(0.35, rr, 1.45), "car", bc, be, th)
		line(P.call(0.35, rr, 1.45), P.call(-1.1, rr, 1.45), "car", bc, be, th)
		line(P.call(-1.1, rr, 1.45), P.call(-1.6, rr, 0.95), "car", bc, be, th)
	line(P.call(0.35, -0.82, 1.45), P.call(0.35, 0.82, 1.45), "car", bc, be, th)
	line(P.call(-1.1, -0.82, 1.45), P.call(-1.1, 0.82, 1.45), "car", bc, be, th)
	# Raeder
	for fr in [1.4, -1.4]:
		for rr in [-0.92, 0.92]:
			ring(P.call(fr, rr, 0.33), f, u, 0.32, 10, "car", bc, be, th)
	# Scheinwerfer weiss vorn
	var hc: Color = S("head_col", Color(1, 1, 1))
	var tc: Color = S("tail_col", Color(1, 0.1, 0.08))
	for rr in [-0.62, 0.62]:
		line(P.call(hl + 0.03, rr - 0.18, 0.72), P.call(hl + 0.03, rr + 0.18, 0.72), "head", hc, S("head_energy", 6.0), 0.12, false)
		halo(P.call(hl + 0.2, rr, 0.72), 2.2, hc, 0.9, 2.6)
		cone(P.call(hl + 0.1, rr, 0.72), P.call(hl + 22.0, rr * 3.0, 0.0), 0.1, 3.0, hc, S("beam_energy", 0.10))
		line(P.call(-hl - 0.03, rr - 0.22, 0.85), P.call(-hl - 0.03, rr + 0.22, 0.85), "tail", tc, S("tail_energy", 5.0), 0.11, false)
		halo(P.call(-hl - 0.2, rr, 0.85), 1.6, tc, 0.8, 2.6)
		rain_light(P.call(hl + 0.5, rr, 0.72), hc, 3.0, 0.02)
		rain_light(P.call(-hl - 0.3, rr, 0.85), tc, 1.2, 0.05)
	for k in 4:
		pool(P.call(hl + 3.0 + k * 4.0, 0, 0), 1.8 + k * 0.8, hc, 0.5 - k * 0.09)
	pool(P.call(-hl - 1.2, 0, 0), 1.6, tc, 0.35)

func _build_traffic() -> void:
	car(Vector3(4.6, 0, 19.0), Vector3(0, 0, 1))
	car(Vector3(-4.6, 0, 2.0), Vector3(0, 0, -1))
	car(Vector3(-17.0, 0, 4.6), Vector3(1, 0, 0))
	car(Vector3(-4.6, 0, -26.0), Vector3(0, 0, -1))
	car(Vector3(4.6, 0, -33.0), Vector3(0, 0, 1))
	car(Vector3(30.0, 0, -4.6), Vector3(-1, 0, 0))

# ---------------------------------------------------------------- people

func person(p: Vector3, ang: float, umbrella: bool) -> void:
	var f := Vector3(sin(ang), 0, cos(ang))
	var r := f.cross(Vector3.UP).normalized()
	var u := Vector3.UP
	var c: Color = S("ped_col", Color(0.6, 0.65, 0.7))
	var e: float = S("ped_energy", 1.0) * rng.randf_range(0.8, 1.1)
	var th: float = S("ped_thick", 0.035)
	var k := "ped"
	var s := rng.randf_range(0.15, 0.35)
	var hip := p + u * 0.92
	line(hip + r * 0.1, p + r * 0.12 + f * s, k, c, e, th)
	line(hip - r * 0.1, p - r * 0.12 - f * s, k, c, e, th)
	line(hip + r * 0.12, p + u * 1.43 + r * 0.2, k, c, e, th)
	line(hip - r * 0.12, p + u * 1.43 - r * 0.2, k, c, e, th)
	line(hip + r * 0.12, hip - r * 0.12, k, c, e, th)
	line(p + u * 1.45 + r * 0.22, p + u * 1.45 - r * 0.22, k, c, e, th)
	ring(p + u * 1.64, r, u, 0.11, 12, k, c, e, th)
	if umbrella:
		var hand := p + u * 1.15 + f * 0.25 + r * 0.05
		line(p + u * 1.45 + r * 0.22, hand, k, c, e, th)
		line(p + u * 1.45 - r * 0.22, p + u * 0.95 - r * 0.3 - f * s * 0.5, k, c, e, th)
		var apex := p + u * 2.18 + f * 0.12
		var rc := p + u * 1.92 + f * 0.12
		var ur := rng.randf_range(0.5, 0.62)
		var uc: Color = S("umb_col", c)
		var ue: float = e * S("umb_mul", 1.0)
		ring(rc, r, f, ur, 20, k + "u", uc, ue, th)
		for i in 6:
			var a := TAU * i / 6.0
			line(apex, rc + (r * cos(a) + f * sin(a)) * ur, k + "u", uc, ue, th * 0.8)
		line(apex, hand, k, c, e, th * 0.8)
	else:
		line(p + u * 1.45 + r * 0.22, p + u * 0.95 + r * 0.3 + f * s * 0.5, k, c, e, th)
		line(p + u * 1.45 - r * 0.22, p + u * 0.95 - r * 0.3 - f * s * 0.5, k, c, e, th)

func _build_people() -> void:
	var up: float = S("umbrella_prob", 0.65)
	var n: int = S("ped_count", 70)
	for i in n:
		var p: Vector3
		var ang: float
		var t := rng.randf()
		if t < 0.45:
			# Diagonalen der Scramble-Kreuzung
			var d := rng.randf_range(-11, 11)
			var off := rng.randf_range(-1.6, 1.6)
			if rng.randf() < 0.5:
				p = Vector3(d * 0.7071 + off * 0.7071, 0, d * 0.7071 - off * 0.7071)
				ang = PI * 0.25 + (PI if rng.randf() < 0.5 else 0.0)
			else:
				p = Vector3(d * 0.7071 + off * 0.7071, 0, -d * 0.7071 + off * 0.7071)
				ang = -PI * 0.25 + (PI if rng.randf() < 0.5 else 0.0)
		elif t < 0.8:
			# Zebrastreifen der Arme
			var arm := rng.randi() % 4
			var a2 := rng.randf_range(-8.5, 8.5)
			var b2 := rng.randf_range(9.8, 12.8) * (1 if arm < 2 else -1)
			if arm % 2 == 0:
				p = Vector3(a2, 0, b2)
				ang = PI * 0.5 * (1 if rng.randf() < 0.5 else -1)
			else:
				p = Vector3(b2, 0, a2)
				ang = 0.0 if rng.randf() < 0.5 else PI
		else:
			# Wartende auf den Ecken
			var sx := 1.0 if rng.randf() < 0.5 else -1.0
			var sz := 1.0 if rng.randf() < 0.5 else -1.0
			p = Vector3(sx * rng.randf_range(9.5, 13.0), 0, sz * rng.randf_range(9.5, 13.0))
			ang = rng.randf_range(-PI, PI)
		ang += rng.randf_range(-0.3, 0.3)
		if p.distance_to(Vector3(13, 0, 15)) < 2.5:
			continue
		person(p, ang, rng.randf() < up)

# ---------------------------------------------------------------- orbs + metro

func _build_orbs_and_metro() -> void:
	var oc: Color = S("orb_col", Color(1.0, 0.9, 0.6))
	var oe: float = S("orb_energy", 3.0)
	var om := _mat(ORB_SHADER)
	om.set_shader_parameter("col", _v3(oc))
	om.set_shader_parameter("core", _v3(S("orb_core", Color(1, 1, 0.95))))
	om.set_shader_parameter("energy", oe)
	var sm := SphereMesh.new()
	sm.radius = 0.2
	sm.height = 0.4
	var z := 24.0
	while z > -44.0:
		var x := 0.0
		var mi := MeshInstance3D.new()
		mi.mesh = sm
		mi.material_override = om
		mi.position = Vector3(x, S("orb_y", 1.3), z)
		add_child(mi)
		halo(mi.position, 1.3, oc, S("orb_halo", 0.35), 2.0)
		pool(Vector3(x, 0, z), 0.7, oc, 0.0)
		z -= 2.4
	# U-Bahn-Eingang: einziges Element mit gefuellter Flaeche
	var mc: Color = S("metro_col", Color(0.2, 1.0, 0.5))
	var me: float = S("metro_energy", 3.0)
	var ez := -47.85
	var portal := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(5.0, 3.2)
	portal.mesh = q
	var pm := _mat(SOLID_SHADER)
	pm.set_shader_parameter("col", _v3(mc) * me)
	portal.material_override = pm
	portal.position = Vector3(0, 1.6, ez)
	add_child(portal)
	# Vordach + Rahmen
	var fc: Color = mc
	for pts in [[Vector3(-3.2, 0, ez + 0.05), Vector3(-3.2, 4.0, ez + 0.05)], [Vector3(3.2, 0, ez + 0.05), Vector3(3.2, 4.0, ez + 0.05)], [Vector3(-3.6, 4.0, ez + 0.05), Vector3(3.6, 4.0, ez + 0.05)], [Vector3(-3.6, 4.0, ez + 0.05), Vector3(-3.6, 4.0, ez + 2.5)], [Vector3(3.6, 4.0, ez + 0.05), Vector3(3.6, 4.0, ez + 2.5)], [Vector3(-3.6, 4.0, ez + 2.5), Vector3(3.6, 4.0, ez + 2.5)]]:
		line(pts[0], pts[1], "metro", fc, me * 1.4, 0.12, false)
	# Stufenlinien nach unten (Treppe ins Innere angedeutet)
	label("地下鉄 ↓", Vector3(0, 4.7, ez + 0.1), 0.0, 3.0, mc, me * 1.2)
	halo(Vector3(0, 1.8, ez + 0.6), 9.0, mc, S("metro_halo", 0.6), 1.6)
	cone(Vector3(0, 6.0, ez + 1.0), Vector3(0, 0.0, ez + 9.0), 0.4, 5.5, mc, S("metro_cone", 0.18))
	pool(Vector3(0, 0, ez + 4.0), 5.0, mc, S("metro_pool", 0.8))
	pool(Vector3(0, 0, ez + 10.0), 4.0, mc, S("metro_pool", 0.8) * 0.4)
	rain_light(Vector3(0, 2.0, ez + 2.0), mc, 3.0, 0.01)

# ---------------------------------------------------------------- rain

func _build_rain() -> void:
	var n: int = S("rain_count", 9000)
	if n <= 0:
		return
	rain_mm = MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var q := QuadMesh.new()
	q.size = Vector2(1.0, 1.0)
	mm.mesh = q
	mm.instance_count = n
	rain_mm.multimesh = mm
	rain_mat = _mat(RAIN_SHADER)
	rain_mat.set_shader_parameter("col", _v3(S("rain_col", Color(0.7, 0.75, 0.85))))
	rain_mat.set_shader_parameter("base", S("rain_base", 0.06))
	rain_mat.set_shader_parameter("lit", S("rain_lit", 1.0))
	rain_mat.set_shader_parameter("width", S("rain_width", 0.012))
	var lp := PackedColorArray()
	var lc := PackedColorArray()
	# Die staerksten Lichter zuerst (max 12)
	rain_lights.sort_custom(func(a, b): return a[2] > b[2])
	for l in rain_lights:
		if lp.size() >= 12:
			break
		var v: Vector3 = l[0]
		lp.append(Color(v.x, v.y, v.z, l[3]))
		var c: Color = l[1]
		lc.append(Color(c.r, c.g, c.b, l[2]))
	rain_mat.set_shader_parameter("lpos", lp)
	rain_mat.set_shader_parameter("lcol", lc)
	rain_mat.set_shader_parameter("ln", lp.size())
	rain_mm.material_override = rain_mat
	rain_mm.custom_aabb = AABB(Vector3(-1000, -100, -1000), Vector3(2000, 400, 2000))
	add_child(rain_mm)

func _place_rain(center: Vector3) -> void:
	if rain_mm == null:
		return
	var mm := rain_mm.multimesh
	var r2 := RandomNumberGenerator.new()
	r2.seed = 99
	var slant: float = S("rain_slant", 0.2)
	var L: float = S("rain_len", 0.7)
	var basis := Basis(Vector3.RIGHT, Vector3(slant, -1.0, slant * 0.4).normalized() * L, Vector3.BACK)
	for i in mm.instance_count:
		var p := center + Vector3(r2.randf_range(-35, 35), r2.randf_range(-1.0, 22.0), r2.randf_range(-35, 35))
		if p.y < 0.2:
			p.y = r2.randf_range(0.3, 4.0)
		mm.set_instance_transform(i, Transform3D(basis, p))
