// Arles pellets: vermilion #FF4A1C (exclusive - the only red-orange of the
// world), read as an object, not as a light (UX W-E): the core goes no
// brighter than ~#FF7A50, the glow share is halved (energy below the glow
// threshold except at the core) and a strong dark contour closes the rim, so
// a pellet stays readable before the yellow windows and lamps (also for
// red-green colour vision). Unshaded, never fogged away.
shader_type spatial;
render_mode unshaded;

uniform vec3 col : source_color = vec3(1.0, 0.29, 0.11);
uniform vec3 core : source_color = vec3(1.0, 0.48, 0.31); // ~#FF7A50 at most
uniform vec3 outline : source_color = vec3(0.23, 0.05, 0.02);
uniform float energy = 1.5;
// share of `energy` that may go over 1 (into the glow); 0.5 = half the old glow
uniform float glow_share = 0.5;

void fragment() {
	float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float e = 1.0 + (energy - 1.0) * glow_share;
	vec3 body = mix(col, core, pow(ndv, 4.0)) * e * (0.72 + 0.28 * ndv);
	// strong dark contour: a wide, hard rim
	ALBEDO = mix(outline, body, smoothstep(0.30, 0.42, ndv));
}
