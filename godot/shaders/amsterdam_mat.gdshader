// Amsterdam: the self-healing cutting mat under the model (A0+, 150 x 120 cm =
// 150 x 120 m at 1:100). Neutral slate grey (no green: green is the exit), a
// light 1 cm grid, stronger lines every 5 cm, faint old cuts. No maker, no
// logo, no numbers. Lines are antialiased with fwidth (grazing views).
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec3 base : source_color = vec3(0.204, 0.224, 0.227);
uniform vec3 line : source_color = vec3(0.36, 0.384, 0.38);
uniform vec3 line5 : source_color = vec3(0.5, 0.525, 0.514);

varying vec3 wp;

float h21(vec2 p) { p = fract(p * vec2(234.34, 435.345)); p += dot(p, p + 34.23); return fract(p.x * p.y); }
float vn(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1, 0)), f.x), mix(h21(i + vec2(0, 1)), h21(i + vec2(1, 1)), f.x), f.y);
}

float grid(vec2 p, float step_m, float w) {
	vec2 g = abs(fract(p / step_m + 0.5) - 0.5) * step_m;
	vec2 fw = fwidth(p);
	vec2 l = 1.0 - smoothstep(vec2(w * 0.5), vec2(w * 0.5) + fw * 1.5, g);
	// fade lines that get thinner than a pixel (no moire)
	vec2 fade = 1.0 - smoothstep(vec2(w * 0.6), vec2(w * 3.0), fw);
	return max(l.x * fade.x, l.y * fade.y);
}

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wp.xz;
	vec3 c = base * (0.94 + 0.1 * vn(p * 0.4));
	c = mix(c, line, grid(p, 1.0, 0.07) * 0.8);
	c = mix(c, line5, grid(p, 5.0, 0.12));
	// old cuts: thin lighter scratches in a few directions
	float sc = 0.0;
	for (int i = 0; i < 3; i++) {
		float a = float(i) * 1.1 + 0.4;
		vec2 d = vec2(cos(a), sin(a));
		float t = dot(p, vec2(-d.y, d.x));
		float cell_id = floor(t / 7.0);
		float on = step(0.6, h21(vec2(cell_id, float(i))));
		float dl = abs(fract(t / 7.0) - 0.5) * 7.0;
		float seg = step(0.4, vn(vec2(dot(p, d) * 0.05, cell_id)));
		sc = max(sc, on * seg * (1.0 - smoothstep(0.02, 0.05 + fwidth(t), dl)));
	}
	c = mix(c, c * 1.35, sc * 0.6);
	ALBEDO = c;
	ROUGHNESS = 0.78;
}
