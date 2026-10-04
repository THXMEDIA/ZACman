// Arles: lamps, stars, the moon (and the green star of the exit) as halo discs
// in ONE MultiMesh (technical condition). Camera-facing quads; INSTANCE_CUSTOM:
// x seed, y rings, z energy, w type (0 lamp, 1 star, 2 moon, 3 exit star).
// Core -> chrome yellow -> GOLD rim (not orange). Halos fade out right in
// front of the camera (no full-screen flash). The exit star pulses through
// the "pulse" uniform (arles_exit.gd, 0.5 Hz; constant with reduced effects).
shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled, depth_draw_never;

uniform vec3 core : source_color = vec3(1.0, 0.95, 0.69);
uniform vec3 yellow : source_color = vec3(0.98, 0.80, 0.27);
uniform vec3 rim : source_color = vec3(0.83, 0.63, 0.23);
uniform vec3 g_core : source_color = vec3(0.88, 1.0, 0.96);
uniform vec3 g_mid : source_color = vec3(0.23, 0.96, 0.78);
uniform vec3 g_rim : source_color = vec3(0.05, 0.48, 0.40);
uniform float pulse = 1.0;
uniform float soft = 0.4;

varying vec4 cu;
varying float fade;

float hash21(vec2 p) { p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1, 0)), f.x), mix(hash21(i + vec2(0, 1)), hash21(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	cu = INSTANCE_CUSTOM;
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0, 0, 0), vec4(0, length(MODEL_MATRIX[1].xyz), 0, 0), vec4(0, 0, 1, 0), vec4(0, 0, 0, 1));
	float d = distance(MODEL_MATRIX[3].xyz, CAMERA_POSITION_WORLD);
	fade = smoothstep(2.5, 7.0, d);
}

void fragment() {
	vec2 p = UV - 0.5; float r = length(p) * 2.0; float ang = atan(p.y, p.x);
	float seed = cu.x; float rings = cu.y; float energy = cu.z; int typ = int(cu.w + 0.5);
	vec3 k0 = core; vec3 k1 = yellow; vec3 k2 = rim;
	if (typ == 3) { k0 = g_core; k1 = g_mid; k2 = g_rim; energy *= pulse; }
	float rn = fract(r * rings + (vnoise(vec2(ang * 2.0 + seed, r * 3.0)) - 0.5) * 0.5);
	vec3 c = mix(k0, k1, smoothstep(0.0, 0.35, r));
	c = mix(c, k2, smoothstep(0.45, 1.0, r));
	float str = 0.85 + 0.3 * step(0.5, fract(ang * 7.0 + r * 2.0 + seed));
	c *= mix(0.78, 1.15, smoothstep(0.25, 0.75, rn));
	float a = smoothstep(1.0, 0.86, r + (vnoise(vec2(ang * 4.0, seed)) - 0.5) * 0.15);
	a *= mix(1.0, (typ == 0) ? soft : 0.75, smoothstep(0.35, 1.0, r));
	ALBEDO = c * str * energy; ALPHA = a * fade;
}
