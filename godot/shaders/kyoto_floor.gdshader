// Kyoto page floor: washi paper; the streets are printed in pale blue with a
// bokashi towards the curbs and stone paving; the curb (boundary between a
// street cell and a block cell) is an ink line — exactly the collision edge.
shader_type spatial;
render_mode unshaded;

uniform float cell = 2.0;
uniform sampler2D maze_tex : filter_nearest, repeat_disable;
uniform vec2 maze_size = vec2(49.0, 45.0);
uniform vec3 floor_albedo : source_color = vec3(0.953, 0.933, 0.886);
uniform vec3 ai1 : source_color = vec3(0.118, 0.227, 0.431);
uniform vec3 ai3 : source_color = vec3(0.553, 0.690, 0.839);
uniform vec3 ai4 : source_color = vec3(0.812, 0.878, 0.933);

varying vec3 wp;

float h21(vec2 p) { p = fract(p * vec2(234.34, 435.345)); p += dot(p, p + 34.23); return fract(p.x * p.y); }
float vn(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), f.x), mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), f.x), f.y);
}

float wall_at(vec2 c) {
	if (c.x < 0.0 || c.y < 0.0 || c.x >= maze_size.x || c.y >= maze_size.y) return 1.0;
	return texture(maze_tex, (c + 0.5) / maze_size).r;
}

void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }

void fragment() {
	// cell coords: col = x / cell, row = z / cell (cell centres at integers)
	vec2 g = wp.xz / cell + 0.5;
	vec2 c = floor(g);
	vec2 f = fract(g);
	float here = wall_at(c);
	vec3 col = floor_albedo * (0.985 + 0.02 * vn(wp.xz * vec2(5.0, 1.3)));
	if (here < 0.5) {
		// distance (m) to the nearest block edge among the four neighbours
		float d = 9.0;
		if (wall_at(c + vec2(-1.0, 0.0)) > 0.5) d = min(d, f.x * cell);
		if (wall_at(c + vec2(1.0, 0.0)) > 0.5) d = min(d, (1.0 - f.x) * cell);
		if (wall_at(c + vec2(0.0, -1.0)) > 0.5) d = min(d, f.y * cell);
		if (wall_at(c + vec2(0.0, 1.0)) > 0.5) d = min(d, (1.0 - f.y) * cell);
		vec3 street = mix(ai4, ai3, (1.0 - smoothstep(0.0, 1.6, d)) * 0.55);
		// stone paving (ishidatami), offset rows
		vec2 st = wp.xz / vec2(0.9, 0.6);
		st.x += 0.5 * floor(st.y);
		float joint = max(step(0.93, fract(st.x)), step(0.9, fract(st.y)));
		street = mix(street, ai3, joint * 0.35);
		col = mix(col, street, 0.92);
		// curb ink line
		col = mix(col, ai1, 1.0 - smoothstep(0.04, 0.09, d));
	}
	ALBEDO = col;
}
