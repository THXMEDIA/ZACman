// Arles: the Rhône at night: dark horizontal strokes, and the gas lamps of the
// quay, the far bank and the iron bridge mirrored as long columns broken into
// strokes (core yellow, rim gold - not orange: distance to the vermilion
// pellets). TIME only for a slight tremble; it stands with "Effekte
// reduzieren" (shimmer = 0).
shader_type spatial;
render_mode unshaded, fog_disabled;

#include "res://shaders/arles_common.gdshaderinc"

uniform vec4 refl[40];
uniform int nrefl = 0;
uniform vec3 deep : source_color = vec3(0.04, 0.07, 0.22);
uniform vec3 mid : source_color = vec3(0.10, 0.18, 0.45);
uniform vec3 hi : source_color = vec3(0.30, 0.45, 0.75);
uniform vec3 r_core : source_color = vec3(1.0, 0.86, 0.45);
uniform vec3 r_rim : source_color = vec3(0.83, 0.63, 0.23);
uniform float shimmer = 1.0;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz + MAP_SHIFT;
}

void fragment() {
	float t = TIME * 0.6 * shimmer;
	vec3 cam = CAMERA_POSITION_WORLD + MAP_SHIFT;
	vec3 V = normalize(wpos - cam);
	vec3 R = vec3(V.x, -V.y, V.z);
	float azr = atan(R.x, R.z); float elr = asin(clamp(R.y, -1.0, 1.0));
	vec2 uv = wpos.xz * vec2(1.0, 0.35);
	float lod = stroke_lod(length(wpos - cam), length(fwidth(uv / 0.10)));
	vec2 dv; float ridge;
	vec3 c = impasto(uv, deep, mid, hi, 0.08, (vnoise(wpos.xz * 0.05) - 0.5) * 0.4, 0.9, 0.10, lod * 0.8, near_amp(length(wpos - cam)), dv, ridge);
	c *= 0.75;
	vec3 add = vec3(0.0);
	for (int i = 0; i < nrefl; i++) {
		vec3 d = refl[i].xyz - wpos;
		float azd = atan(d.x, d.z); float eld = atan(d.y, length(d.xz));
		float da = azr - azd; da = da - 6.2831853 * floor((da + 3.14159265) / 6.2831853);
		float de = elr - eld;
		// code H4: far off this lamp's column (azimuth, beyond the wide
		// gaussian plus the tremble) or outside its length: skip before the
		// noise and the exponentials
		if (abs(da) > 0.2 || de > 0.42 || de < -0.05) continue;
		da += (vnoise(vec2(wpos.z * 0.9 + float(i) * 3.1, wpos.x * 2.5 + t)) - 0.5) * 0.016;
		float col = exp(-pow(da / 0.016, 2.0));
		float wide = exp(-pow(da / 0.045, 2.0)) * 0.30;
		float len_ = smoothstep(0.42, 0.0, de) * smoothstep(-0.05, 0.0, de);
		float dash = 0.45 + 0.55 * step(0.42, vnoise(vec2(elr * 90.0, float(i) * 5.7 + t * 0.4)));
		add += mix(r_rim, r_core, clamp(col * 1.3, 0.0, 1.0)) * (col + wide) * len_ * dash * refl[i].w;
	}
	ALBEDO = c + add;
}
