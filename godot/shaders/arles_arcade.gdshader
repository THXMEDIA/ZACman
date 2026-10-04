// Arles amphitheatre: the outer shell with two storeys of arcades cut out of
// the wall in the shader (discard); behind them lies the dark inner vault -
// real depth without single arch geometry. Voussoirs radial, pilasters
// vertical, entablature horizontal; stroke LOD and light pools as elsewhere.
shader_type spatial;

#include "res://shaders/arles_common.gdshaderinc"

uniform vec3 col_a : source_color = vec3(0.7);
uniform vec3 col_b : source_color = vec3(0.6);
uniform vec3 col_c : source_color = vec3(0.9);
uniform vec2 ctr = vec2(68.0, 45.0); // map space
uniform float nbay = 28.0;
uniform float perim = 88.6;
uniform float rad = 14.1;
uniform float emit = 0.0;

varying vec3 wpos; varying vec3 wn;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz + MAP_SHIFT;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float th = atan(wpos.z - ctr.y, wpos.x - ctr.x);
	float u = th / 6.2831853 * nbay; float bw = perim / nbay;
	float xm = (fract(u) - 0.5) * bw;
	float y = wpos.y; float r1 = 0.95;
	float s1 = 4.1; float s2 = 10.3;
	bool open_ = false;
	if (abs(xm) < r1 && y > 0.6 && (y < s1 || xm * xm + (y - s1) * (y - s1) < r1 * r1)) open_ = true;
	if (abs(xm) < r1 && y > 7.1 && (y < s2 || xm * xm + (y - s2) * (y - s2) < r1 * r1)) open_ = true;
	if (open_) discard;
	vec2 uv = vec2(th * rad, y);
	float a = cell_angle(uv, 0.6, 0.0, 0, vec2(0.0));
	float sp = (y < 6.6) ? s1 : s2;
	float rr = length(vec2(xm, y - sp));
	bool vous = y > sp && rr < r1 + 0.42;
	if (vous) a = atan(y - sp, xm);
	bool pil = abs(xm) > bw * 0.5 - 0.30;
	if (pil && !vous) a = 1.5708;
	bool ent = (y > 5.85 && y < 6.75) || y > 12.1;
	if (ent) a = 0.0;
	float lod = stroke_lod(length(wpos - (CAMERA_POSITION_WORLD + MAP_SHIFT)), length(fwidth(uv / 0.09)));
	vec2 dv; float ridge;
	vec3 c = impasto(uv, col_a, col_b, col_c, 0.14, a, 0.6, 0.09, lod, dv, ridge);
	if (vous) c *= 0.82;
	if (pil) c *= 1.08;
	if (ent) c *= (fract(y * 3.0) < 0.25) ? 0.6 : 1.05;
	if (y < 0.6) c *= 0.55;
	vec3 tu = normalize(vec3(-wn.z, 0.0, wn.x)); vec3 tv = vec3(0, 1, 0);
	vec3 n = normalize(wn + normalize(tu * dv.x + tv * dv.y) * ridge * 0.6 * (1.0 - calm * 0.5));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	ALBEDO = c; ROUGHNESS = 0.6; SPECULAR = 0.45;
	EMISSION = c * pools(wpos, wn) + c * emit;
}
