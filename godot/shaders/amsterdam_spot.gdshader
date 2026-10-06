// Amsterdam exit: the bright green spot on the platform in front of the
// tram's open door (light falling out of the car). Soft ellipse, unshaded,
// blended over the plate; no texture.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec3 col : source_color = vec3(0.6, 0.9, 0.8);
uniform float strength = 0.85;

void fragment() {
	vec2 q = (UV - 0.5) * 2.0;
	float r = length(q * vec2(1.0, 1.15));
	float a = (1.0 - smoothstep(0.35, 1.0, r)) * strength;
	ALBEDO = col;
	ALPHA = a;
}
