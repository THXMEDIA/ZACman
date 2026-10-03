// pacman_floor_base.gdshaderinc — Speedrun base look "Lagune" for the floor
// (spec 1.1). Shared by pacman_floor.gdshader and kond_floor.gdshader.
//
// Lit (NOT unshaded) dark floor: the ghosts' OmniLights tint it round
// corners as an early warning. On top, emissive and fwidth-antialiased:
//  - cell grid: a line every CELL meters (2 m) -> sense of speed
//  - junction frames: a chamfered octagon on every cell with >= 3 open
//    neighbors -> branches readable from a distance
// Cell map as a texture (one pixel per cell, R = wall, G = junction).

uniform sampler2D maze_tex : filter_nearest;
uniform vec2 maze_size = vec2(21.0, 19.0);
uniform float cell = 2.0;
uniform vec3 floor_albedo : source_color = vec3(0.035, 0.04, 0.065);
uniform vec3 line_top : source_color = vec3(0.118, 0.949, 0.784);
uniform vec3 line_base : source_color = vec3(0.043, 0.498, 0.659);
uniform float grid_w = 0.06;
uniform float grid_strength = 1.0;
uniform float junction_half = 0.6;    // half edge length of the junction frame (m)
uniform float junction_chamfer = 0.38;
uniform float junction_w = 0.06;
uniform float junction_strength = 0.75;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// fw_d = fwidth(d), taken by the caller in uniform control flow (N3).
float line_aa(float d, float w, float fw_d) {
	float fw = max(fw_d, 1e-5);
	float wc = max(w, fw);
	float a = clamp((wc * 0.5 - abs(d)) / fw + 0.5, 0.0, 1.0);
	return a * clamp(w / fw, 0.0, 1.0);
}

// Base look of one floor fragment: albedo + emission.
void pacman_floor(out vec3 albedo, out vec3 emission) {
	// cell (r, c) is centered at (x = c*cell, z = r*cell)
	vec2 g = vec2(wpos.x, wpos.z) / cell + 0.5;
	ivec2 ci = ivec2(floor(g));
	vec4 m = vec4(1.0, 0.0, 0.0, 1.0);
	if (ci.x >= 0 && ci.y >= 0 && float(ci.x) < maze_size.x && float(ci.y) < maze_size.y) {
		m = texelFetch(maze_tex, ci, 0);
	}
	vec2 local = (fract(g) - 0.5) * cell;   // meters from the cell center

	// N3: every derivative before the (per-cell, non-uniform) junction branch.
	vec2 fw_g = fwidth(g);
	vec2 fw_m = fw_g * cell;                 // d/dx of the distance to a border, in m
	vec2 q = abs(local);
	float d_sq = max(q.x, q.y) - junction_half;
	float d_ch = (q.x + q.y - (2.0 * junction_half - junction_chamfer)) * 0.70710678;
	float d = max(d_sq, d_ch);
	float fw_d = fwidth(d);

	// grid: distance to the nearest cell border
	vec2 db = cell * 0.5 - abs(local);
	float grid = max(line_aa(db.x, grid_w, fw_m.x), line_aa(db.y, grid_w, fw_m.y));
	float fade = clamp(1.0 - max(fw_g.x, fw_g.y) * 6.0, 0.0, 1.0); // fade out far away
	vec3 em = line_base * grid * grid_strength * fade;

	if (m.g > 0.5) {
		float frame = line_aa(d, junction_w, fw_d);
		float inner = (1.0 - smoothstep(-0.02, 0.02, d)) * 0.05;
		em += line_top * (frame * junction_strength + inner);
	}
	albedo = floor_albedo;
	emission = em;
}
