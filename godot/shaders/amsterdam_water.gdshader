// Amsterdam: the canals are dark lacquered card (a sheet of glossy foil on the
// canal bed) 0.85 m below the street. Very low roughness and a clear coat, so
// the sky, the evening sun and (Forward+) the houses mirror in it; a slight,
// static unevenness of the lacquer breaks the mirror. No animation.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec3 lacquer : source_color = vec3(0.102, 0.071, 0.043);
uniform sampler2D tape_nrm : hint_normal, filter_linear_mipmap, repeat_enable;

varying vec3 wp;

float h21(vec2 p) { p = fract(p * vec2(234.34, 435.345)); p += dot(p, p + 34.23); return fract(p.x * p.y); }
float vn(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1, 0)), f.x), mix(h21(i + vec2(0, 1)), h21(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wp.xz;
	// brush strokes of the lacquer along the canal + the foil's slight waviness
	float a = vn(p * vec2(0.18, 0.9)) - 0.5;
	float b = vn(p * vec2(0.9, 0.2) + 7.3) - 0.5;
	vec3 tn = texture(tape_nrm, p / vec2(5.0, 1.3)).rgb * 2.0 - 1.0;
	vec2 nxy = vec2(a, b) * 0.12 + tn.xy * 0.05;
	NORMAL_MAP = vec3(nxy * 0.5 + 0.5, 1.0);
	ALBEDO = lacquer * (0.9 + 0.2 * vn(p * 0.05));
	// dark lacquer: the mirror stays dark-amber, the sun's glint stays sharp
	ROUGHNESS = 0.16;
	SPECULAR = 0.35;
	CLEARCOAT = 0.55;
	CLEARCOAT_ROUGHNESS = 0.04;
}
