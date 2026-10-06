// Light cones of the Tokyo line city (lamps, headlight beams in the rain,
// subway) as ONE MultiMesh (tokyo_figures.gd cone_mesh, tokyo_life.gd).
// INSTANCE_CUSTOM: rgb = color * energy, a = pulse in Hz (0 = steady).
// Bright near the source, soft at the silhouette, gone right at the camera.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

uniform float gain = 3.0;

varying vec3 v_col;

void vertex() {
	float hz = INSTANCE_CUSTOM.a;
	float pulse = hz > 0.0 ? 0.8 + 0.2 * sin(TIME * 6.2831853 * hz) : 1.0;
	v_col = INSTANCE_CUSTOM.rgb * pulse;
}

void fragment() {
	float t = UV.y;
	float edge = pow(clamp(abs(dot(normalize(NORMAL), VIEW)), 0.0, 1.0), 1.5);
	float near = smoothstep(0.8, 3.0, length(VERTEX));
	// max(): UV.y can overshoot 1.0 by rounding at the base ring; pow(negative, x)
	// is NaN on real GPUs and blend_add turns that into black arcs on the street.
	float a = pow(max(1.0 - t, 0.0), 1.6) * edge * near;
	a = clamp(a, 0.0, 4.0);
	ALBEDO = v_col * a * gain;
}
