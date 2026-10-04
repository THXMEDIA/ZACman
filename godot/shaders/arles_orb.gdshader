// Arles pellets: vermilion #FF4A1C (exclusive - the only red-orange of the
// world) with a light core and a dark contour at the rim, so a pellet stays
// readable before the yellow windows and lamps (also for red-green colour
// vision). Unshaded, never fogged away.
shader_type spatial;
render_mode unshaded;

uniform vec3 col : source_color = vec3(1.0, 0.29, 0.11);
uniform vec3 core : source_color = vec3(1.0, 0.69, 0.53);
uniform vec3 outline : source_color = vec3(0.23, 0.05, 0.02);
uniform float energy = 1.5;

void fragment() {
	float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	vec3 body = mix(col, core, pow(ndv, 4.0)) * energy * (0.75 + 0.25 * ndv);
	ALBEDO = mix(outline, body, smoothstep(0.20, 0.36, ndv));
}
