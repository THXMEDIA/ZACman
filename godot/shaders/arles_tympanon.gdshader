// Saint-Trophime: the tympanum only as a relief hint (a mandorla in the
// middle, four fields around it) - deliberately no figures.
shader_type spatial;

uniform vec3 stone : source_color = vec3(0.72, 0.64, 0.50);
uniform vec3 shade : source_color = vec3(0.30, 0.26, 0.36);
uniform float emit = 0.1;

float hash21(vec2 p) { p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1, 0)), f.x), mix(hash21(i + vec2(0, 1)), hash21(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	vec2 p = vec2(UV.x - 0.5, 1.0 - UV.y);
	p.x *= 2.0;
	float r = length(p);
	if (r > 1.0 || p.y < 0.0) discard;
	float m = length(vec2(p.x / 0.32, (p.y - 0.48) / 0.46));
	float relief = smoothstep(1.0, 0.92, m);
	float fields = step(0.22, abs(p.x)) * step(0.18, p.y) * step(r, 0.88);
	float rings = step(0.5, fract(r * 9.0));
	vec3 c = mix(shade, stone, 0.55 + 0.25 * rings * (1.0 - relief));
	c = mix(c, stone * 1.1, relief * (0.7 + 0.3 * vnoise(p * 30.0)));
	c = mix(c, stone * 0.9, fields * 0.6 * step(0.5, vnoise(p * 14.0)));
	ALBEDO = c; ROUGHNESS = 0.8;
	EMISSION = c * emit;
}
