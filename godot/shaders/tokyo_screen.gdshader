// Video screen of the Tokyo line city — the only flat light sources (style
// rule: magenta only on screens and the tower accent). Slow drift (< 0.1 Hz),
// no flicker; scanlines are static.
shader_type spatial;
render_mode unshaded, cull_back;

uniform vec3 color_a : source_color = vec3(1.0, 0.18, 0.53);
uniform float energy = 1.7;
uniform vec3 color_b : source_color = vec3(1.0, 0.6, 0.18);
uniform float seed = 0.0;
uniform float drift_hz = 0.06;

void fragment() {
	vec2 uv = UV;
	float t = TIME * drift_hz * 6.2831;
	float bands = 0.5 + 0.5 * sin(uv.y * 9.0 + seed * 3.0 + sin(uv.x * 4.0 + seed) * 1.6 + t);
	float circ = smoothstep(0.30, 0.27, distance(uv * vec2(1.0, 2.0), vec2(0.5 + 0.12 * sin(seed * 2.0 + t * 0.5), 1.3)));
	vec3 c = mix(color_a, color_b, bands * 0.8);
	c = mix(c, vec3(1.0, 0.92, 0.85), circ * 0.45);
	c *= 0.84 + 0.16 * step(0.5, fract(uv.y * 120.0));
	float frame = step(0.02, uv.x) * step(uv.x, 0.98) * step(0.012, uv.y) * step(uv.y, 0.988);
	ALBEDO = c * energy * mix(0.2, 1.0, frame);
}
