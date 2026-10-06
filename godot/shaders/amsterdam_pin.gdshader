// Amsterdam pellets: glass-head pins (cobalt #2E6BFF, exclusive to the
// pellets) on a steel needle stuck into the base plate. Unlit like a marker,
// with a dark contour so the head keeps its outline on bright, sunlit kraft
// and in greyscale; the needle (UV2.x = 1) is steel grey. MazeView sets `col`.
shader_type spatial;
render_mode unshaded;

uniform vec3 col : source_color = vec3(0.180, 0.420, 1.0);
uniform vec3 core : source_color = vec3(0.706, 0.804, 1.0);
uniform vec3 key : source_color = vec3(0.035, 0.07, 0.19);
uniform vec3 steel : source_color = vec3(0.62, 0.62, 0.64);

void fragment() {
	float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	if (UV2.x > 0.5) {
		// needle: simple fake shading across the cylinder
		ALBEDO = steel * (0.35 + 0.75 * ndv);
	} else {
		// glass head: deep blue body, light core towards the viewer, a small
		// highlight up left, dark rim
		vec3 c = mix(col * 0.75, col, smoothstep(0.3, 0.8, ndv));
		c = mix(c, core, smoothstep(0.82, 0.99, ndv) * 0.6);
		vec3 wn = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz;
		float hl = smoothstep(0.86, 0.96, dot(wn, normalize(vec3(-0.4, 0.8, 0.3))));
		c = mix(c, vec3(0.95, 0.97, 1.0), hl * 0.8);
		c = mix(key, c, smoothstep(0.14, 0.3, ndv));
		ALBEDO = c;
	}
}
