// Arles exit: the green door (panels with a frame) and the green shutters of
// the Yellow House, mint green #3AF5C8 (exclusive). Vertical strokes; the
// 0.5 Hz pulse comes in as "pulse" from arles_exit.gd (constant with
// "Effekte reduzieren").
shader_type spatial;
render_mode unshaded;

uniform vec3 col : source_color = vec3(0.23, 0.96, 0.78);
uniform vec3 dark : source_color = vec3(0.03, 0.16, 0.12);
uniform float energy = 1.6;
uniform float pulse = 1.0;
uniform float panels = 1.0; // 1: door panels with a frame, 0: shutter slats

float hash21(vec2 p) { p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1, 0)), f.x), mix(hash21(i + vec2(0, 1)), hash21(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	float s = 0.9 + 0.2 * step(0.5, fract(UV.x * 14.0 + vnoise(UV * vec2(6.0, 2.0)) * 0.6));
	vec3 c = col * energy * pulse * s;
	if (panels > 0.5) {
		float fr = step(0.06, UV.x) * step(UV.x, 0.94) * step(0.04, UV.y);
		float mid_ = 1.0 - step(abs(UV.x - 0.5), 0.02);
		c = mix(dark, c, fr * mid_);
	} else {
		c *= 0.55 + 0.45 * step(0.35, fract(UV.y * 10.0));
	}
	ALBEDO = c;
}
