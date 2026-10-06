// Arles: the passers-by (arles_life.gd), ALL in one MultiMesh. Evening figures
// in coat and hat painted with the same impasto brush as the city (strokes
// anchored in the figure's own space, so they walk along with it and never
// swim over the body). The gait is animated here, not on the CPU: the feet
// step, the coat hem and the arms swing, the body bobs a little.
// INSTANCE_CUSTOM: x = gait phase (0..1), y = stride frequency (Hz; 0 =
// standing), z = coat index + hat colour / 10, w = hat type (0 hat with brim,
// 1 flat cap, 2 bare head with hair).
// Mesh UV.x = material (0 coat, 1 skin, 2 hat, 3 hair, 4 shoe), UV.y = part
// (0 body, 1 foot L, 2 foot R, 3 arm L, 4 arm R, 5 hat brim, 6 hat crown,
// 7 hair). Stride <= 1 Hz, far below the 3 Hz flicker limit; moving = 0
// ("Effekte reduzieren") stops the gait (the figures stand still anyway).
shader_type spatial;

#include "res://shaders/arles_common.gdshaderinc"

uniform vec3 coat_a[6]; uniform vec3 coat_b[6]; uniform vec3 coat_c[6];
uniform vec3 hat_col[3];
uniform vec3 skin_a = vec3(0.7, 0.35, 0.13);
uniform vec3 skin_b = vec3(0.58, 0.30, 0.15);
uniform vec3 skin_c = vec3(0.87, 0.52, 0.22);
uniform vec3 hair_col = vec3(0.02, 0.016, 0.05);
uniform vec3 shoe_col = vec3(0.012, 0.010, 0.03);
uniform float emit = 0.22;
uniform float shoulder_y = 1.38;
uniform float hat_base_y = 1.70;
uniform float foot_swing = 0.15;
uniform float arm_swing = 0.32;

varying vec3 wpos;
varying vec3 wn;
varying vec3 lpos;
varying vec3 lnorm;
varying vec4 inst;

vec3 swing(vec3 v, float pivot_y, float a) {
	float y = v.y - pivot_y;
	float c = cos(a);
	float s = sin(a);
	return vec3(v.x, pivot_y + y * c - v.z * s, y * s + v.z * c);
}

void vertex() {
	lpos = VERTEX;
	lnorm = NORMAL;
	inst = INSTANCE_CUSTOM;
	float freq = INSTANCE_CUSTOM.y * moving;
	float ang = (TIME * freq + INSTANCE_CUSTOM.x) * 6.2831853;
	float g = sin(ang) * step(0.01, freq);
	float cg = cos(ang) * step(0.01, freq);
	float part = UV.y;
	float htype = INSTANCE_CUSTOM.w;
	vec3 v = VERTEX;
	float h = v.y;
	if (part < 0.5) {
		// the coat hem swings with the legs under it, the body leans a little
		v.z -= g * 0.06 * sign(v.x) * smoothstep(0.85, 0.20, h);
		v.x += g * 0.015 * h;
	} else if (part < 1.5) {
		v.z -= g * foot_swing;
		v.y += max(cg, 0.0) * 0.05;
	} else if (part < 2.5) {
		v.z += g * foot_swing;
		v.y += max(-cg, 0.0) * 0.05;
	} else if (part < 3.5) {
		v = swing(v, shoulder_y, -g * arm_swing);
	} else if (part < 4.5) {
		v = swing(v, shoulder_y, g * arm_swing);
	} else if (part < 5.5) {
		// brim: only on the hat (type 0)
		v = mix(vec3(0.0, 1.6, 0.0), v, step(htype, 0.5));
	} else if (part < 6.5) {
		// crown: tall hat (0), low flat cap (1), none (2)
		float k = htype < 0.5 ? 1.0 : (htype < 1.5 ? 0.55 : 0.0);
		v.y = hat_base_y + (v.y - hat_base_y) * k;
		v.xz *= (k <= 0.0) ? 0.0 : 1.0;
	}
	v.y += abs(g) * 0.015;
	VERTEX = v;
	wpos = (MODEL_MATRIX * vec4(v, 1.0)).xyz + MAP_SHIFT;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	int mi = int(UV.x + 0.5);
	int coat = clamp(int(floor(inst.z + 0.01)), 0, 5);
	int hc = clamp(int(fract(inst.z + 0.01) * 10.0), 0, 2);
	vec3 ca; vec3 cb; vec3 cc;
	float len = 0.28; float wid = 0.055; float acc = 0.18; float ang0 = 1.5708; float em = emit;
	if (mi == 0) { ca = coat_a[coat]; cb = coat_b[coat]; cc = coat_c[coat]; }
	else if (mi == 1) { ca = skin_a; cb = skin_b; cc = skin_c; len = 0.14; acc = 0.12; ang0 = 0.0; em = emit * 0.7; }
	else if (mi == 2) { ca = hat_col[hc]; cb = ca * 0.8; cc = ca * 1.35; len = 0.2; acc = 0.12; em = emit * 0.5; }
	else if (mi == 3) { ca = hair_col; cb = hair_col * 0.7; cc = hair_col * 2.2; len = 0.15; acc = 0.2; ang0 = 0.5; em = emit * 0.4; }
	else { ca = shoe_col; cb = shoe_col * 0.7; cc = shoe_col * 2.0; len = 0.12; acc = 0.1; em = 0.0; }
	vec3 nn = wn;
	vec3 al = abs(lnorm);
	vec2 uv; vec3 tu; vec3 tv;
	// strokes live in the figure's own space (triplanar), not in the world
	if (al.y > 0.6) { uv = lpos.xz; tu = vec3(1, 0, 0); tv = vec3(0, 0, 1); }
	else if (al.x > al.z) { uv = lpos.zy; tu = vec3(0, 0, 1); tv = vec3(0, 1, 0); }
	else { uv = lpos.xy; tu = vec3(1, 0, 0); tv = vec3(0, 1, 0); }
	float pix = length(fwidth(lpos)) / wid;
	float dist = length(wpos - (CAMERA_POSITION_WORLD + MAP_SHIFT));
	float lod = stroke_lod(dist, pix);
	float a = ang0 + (hash21(vec2(inst.x * 31.0, float(mi))) - 0.5) * 0.3;
	vec2 dv; float ridge;
	vec3 c = impasto(uv, ca, cb, cc, acc, a, len, wid, lod, near_amp(dist), dv, ridge);
	c *= 0.92 + 0.16 * hash21(vec2(inst.x * 17.0, 3.0));
	vec3 wtan = normalize((MODEL_MATRIX * vec4(tu * dv.x + tv * dv.y, 0.0)).xyz);
	vec3 n = normalize(nn + wtan * ridge * 0.5 * (1.0 - calm * 0.5));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	ALBEDO = c; ROUGHNESS = 0.6; SPECULAR = 0.4;
	EMISSION = c * em + c * pools(wpos, nn);
}
