// Shop fronts under the neon base line (Tokyo): a soft amber band from the
// floor up to ~2.2 m, split into windows; UV.x runs in meters along the
// facade, UV.y from 0 (floor) to 1 (top). Static, no flicker.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;

uniform vec3 glow_color : source_color = vec3(1.0, 0.54, 0.13);
uniform float energy = 0.5;
uniform float seg = 3.2;

float hash1(float n) { return fract(sin(n * 12.9898 + 4.1) * 43758.5453); }

void fragment() {
	float x = UV.x;
	float id = floor(x / seg);
	float cell = fract(x / seg) * seg;
	float divider = step(0.18, cell) * step(cell, seg - 0.18);
	float win = step(0.12, UV.y) * step(UV.y, 0.9);
	float lit = step(0.3, hash1(id));
	float v = smoothstep(0.0, 0.3, UV.y) * smoothstep(1.0, 0.65, UV.y);
	float var_ = 0.55 + 0.45 * hash1(id + 17.0);
	ALBEDO = glow_color * energy * (v * divider * win * var_ * lit + 0.01);
}
