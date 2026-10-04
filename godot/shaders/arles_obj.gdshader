// Arles: every single object (landmarks, lamps, props, figures, trees,
// cypresses, quay, the far city) merged into ONE mesh. UV2.x carries the brush
// material index (ArlesStyle.MATS, sorted by name); the material table comes
// in as uniform arrays. Triplanar impasto from the map-space position, stroke
// LOD, painted light pools. Two-sided: the cavea of the arena shows its seats
// from inside and its vaults from outside ("back" materials).
shader_type spatial;
render_mode cull_disabled;

#include "res://shaders/arles_common.gdshaderinc"

uniform vec3 mat_a[48];
uniform vec3 mat_b[48];
uniform vec3 mat_c[48];
uniform vec4 mat_p[48]; // len, wid, angle, accent
uniform vec4 mat_q[48]; // emit, mode, bump, band
uniform vec4 mat_r[48]; // ctr.x, ctr.y, back, rough
uniform vec3 mat_e[48]; // band colour / back colour

varying vec3 wpos;
varying vec3 wn;
varying float mid;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz + MAP_SHIFT;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	mid = UV2.x;
}

void fragment() {
	int m = clamp(int(mid + 0.5), 0, 47);
	vec4 P = mat_p[m]; vec4 Q = mat_q[m]; vec4 R = mat_r[m];
	vec3 nn = FRONT_FACING ? wn : -wn;
	vec3 an = abs(nn); vec2 uv; vec3 tu; vec3 tv;
	if (an.y > 0.6) { uv = wpos.xz; tu = vec3(1, 0, 0); tv = vec3(0, 0, 1); }
	else if (an.x > an.z) { uv = wpos.zy; tu = vec3(0, 0, 1); tv = vec3(0, 1, 0); }
	else { uv = wpos.xy; tu = vec3(1, 0, 0); tv = vec3(0, 1, 0); }
	float a = cell_angle(uv, P.x, P.z, int(Q.y + 0.5), R.xy);
	float lod = stroke_lod(length(wpos - (CAMERA_POSITION_WORLD + MAP_SHIFT)), length(fwidth(uv / P.y)));
	vec3 ca = mat_a[m]; vec3 cb = mat_b[m];
	if (Q.w > 0.0 && mod(floor(wpos.y / Q.w), 2.0) > 0.5) { ca = mat_e[m]; cb = mat_e[m] * 0.82; }
	if (R.z > 0.5 && FRONT_FACING) { ca = mat_e[m]; cb = mat_e[m] * 0.8; }
	vec2 dv; float ridge;
	vec3 c = impasto(uv, ca, cb, mat_c[m], P.w, a, P.x, P.y, lod, dv, ridge);
	vec3 wtan = normalize(tu * dv.x + tv * dv.y);
	vec3 n = normalize(nn + wtan * ridge * Q.z * (1.0 - calm * 0.5));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	ALBEDO = c; ROUGHNESS = R.w; SPECULAR = 0.5;
	EMISSION = c * Q.x + c * pools(wpos, nn);
}
