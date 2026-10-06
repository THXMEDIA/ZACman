// Kyoto pellets: gold leaf with a printed ink rim, so a pellet keeps its
// outline on pale paper and in greyscale (UX review W1), unlit like the city.
shader_type spatial;
render_mode unshaded;

uniform vec3 col : source_color = vec3(1.0, 0.78, 0.08);
uniform vec3 core : source_color = vec3(1.0, 0.95, 0.72);
uniform vec3 key : source_color = vec3(0.11, 0.10, 0.12);

void fragment() {
	float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	vec3 c = mix(col, core, smoothstep(0.7, 0.97, ndv));
	c = mix(key, c, smoothstep(0.16, 0.28, ndv));
	ALBEDO = c;
}
