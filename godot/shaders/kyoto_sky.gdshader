// Kyoto sky: woodblock bokashi from prussian blue at the top to paper at the
// horizon (the sky band of an ukiyo-e print).
shader_type spatial;
render_mode unshaded, cull_front, fog_disabled, depth_draw_never;

uniform vec3 top : source_color = vec3(0.118, 0.227, 0.431);
uniform vec3 mid : source_color = vec3(0.247, 0.424, 0.659);
uniform vec3 hor : source_color = vec3(0.953, 0.933, 0.886);

varying vec3 d;

void vertex() { d = normalize(VERTEX); }

void fragment() {
	float t = clamp(d.y * 2.0, 0.0, 1.0);
	vec3 c = mix(hor, mid, smoothstep(0.08, 0.5, t));
	c = mix(c, top, smoothstep(0.55, 1.0, t));
	ALBEDO = c;
}
