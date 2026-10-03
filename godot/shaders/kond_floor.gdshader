// kond_floor.gdshader — the rabbit-condition looks for the speedrun floor
// (spec 1.2, from tools/art/speedrun_proto/konditionen.patch). Same uniforms
// as kond_wall (look, transition, flip, reduce_fx); look 0 is the exact base
// floor (pacman_floor_base.gdshaderinc).
//
// Deliberately NOT unshaded: the ghost lights fall on the floor and announce
// a ghost round the corner. Color comes mostly as emission, ALBEDO carries
// the light.

shader_type spatial;
render_mode specular_disabled;

#include "res://shaders/pacman_floor_base.gdshaderinc"
#include "res://shaders/kond_common.gdshaderinc"

uniform int look = 0;
uniform float transition : hint_range(0.0, 1.0) = 0.0;
uniform float flip : hint_range(0.0, 1.0) = 0.0;
uniform float reduce_fx : hint_range(0.0, 1.0) = 0.0;
uniform float matrix_solid : hint_range(0.0, 1.0) = 0.0;
uniform vec2 glyph_cell = vec2(0.16, 0.15);
uniform float transition_radius = 18.0;

uniform vec3 mx_glyph : source_color = vec3(0.0, 0.16, 0.06);       // #002910
uniform vec3 mx_grid : source_color = vec3(0.0, 0.20, 0.075);       // #003313
uniform vec3 mx_bg : source_color = vec3(0.0, 0.010, 0.004);
uniform vec3 fc_carpet_a1 : source_color = vec3(0.24, 0.05, 0.10);  // #3D0D1A carpet wine red
uniform vec3 fc_carpet_a2 : source_color = vec3(0.05, 0.20, 0.19);  // #0D3330 carpet petrol
uniform vec3 fc_carpet_a3 : source_color = vec3(0.50, 0.20, 0.32);  // #803352 carpet old rose

void fragment() {
	vec3 base_alb;
	vec3 base_em;
	pacman_floor(base_alb, base_em);

	vec2 p = wpos.xz / glyph_cell;
	vec2 dp = fwidth(p);
	float gfw = max(dp.x, dp.y) * 8.0;
	float dist = length(wpos - CAMERA_POSITION_WORLD);
	// cell grid (CELL = 2 m, cell centers on even meters)
	vec2 gq = (wpos.xz + 1.0) / 2.0;
	vec2 g = abs(fract(gq) - 0.5);
	float gd = 0.5 - max(g.x, g.y);
	float gaa = max(fwidth(gd), 1e-4);
	float grid_fade = 1.0 - smoothstep(0.02, 0.08, max(fwidth(gq).x, fwidth(gq).y)); // far: line off instead of moiré
	// carpet derivatives, also in uniform control flow
	vec2 t = wpos.xz;
	vec2 f = fract(t) - 0.5;
	float dia = abs(f.x) + abs(f.y);
	float caa = max(fwidth(dia), 1e-4);
	vec2 q = wpos.xz / 0.25;
	vec2 dq = fwidth(q);
	float qfw = max(dq.x, dq.y) * 8.0;

	vec3 c_alb = base_alb;
	vec3 c_em = base_em;

	if (look == 1) {
		// Matrix: resting glyph field (25 cm glyphs) + cell grid, fully static
		vec2 qc = floor(q);
		float has = step(k_hash2(qc), 0.35);
		int gi = 1 + int(k_hash2(qc + 7.0) * 8.0);
		vec3 col = mix(mx_bg, mx_glyph * (0.5 + 0.5 * k_hash2(qc + 3.0)), k_glyph(q, gi, qfw, has));
		col = max(col, mx_grid * k_line(gd, 0.012, gaa) * grid_fade);
		c_alb = col * 0.6 + vec3(0.02);
		c_em = col * 1.1;
	} else if (look == 2) {
		// F&L: casino carpet (own diamond pattern, static). Tips into the
		// complement with flip like the walls; brightness stays the same.
		float ring = k_line(dia - 0.32, 0.035, caa);
		float dot_c = 1.0 - smoothstep(0.09 - caa, 0.09 + caa, length(f));
		vec2 f2 = fract(t + 0.5) - 0.5;
		float small = 1.0 - smoothstep(0.05 - caa, 0.05 + caa, length(f2));
		vec3 b3 = vec3(0.16, 0.42, 0.45);
		float vflip = smoothstep(0.0, 1.0, flip * (1.0 - reduce_fx)); // reduced: the floor does not tip either
		vec3 c1 = mix(fc_carpet_a1, fc_carpet_a2, vflip);
		vec3 c2 = mix(fc_carpet_a2, fc_carpet_a1, vflip);
		vec3 c3 = mix(fc_carpet_a3, b3, vflip);
		vec3 col = mix(c1, c2, step(0.32, dia));
		col = mix(col, c3, max(ring, max(dot_c, small)));
		col *= 0.8;
		c_alb = col * 0.6 + vec3(0.02);
		c_em = col * 1.1;
	} else if (look == 3) {
		c_alb = k_warm(base_alb);
		c_em = k_warm(base_em);
	} else if (look == 4) {
		c_alb = base_alb * 0.6;
		c_em = base_em * 0.22;
	}

	float th = k_trans_threshold(floor(p), dist, transition_radius);
	float mask = step(th, transition * 1.0001);
	// transition glyphs only while a transition runs (N3: uniform branch)
	float fl = 0.0;
	if (transition > 0.001 && transition < 0.999 && look != 0) {
		float front = 1.0 - smoothstep(0.0, 0.045, abs(transition - th));
		fl = k_glyph(p, k_glyph_index(floor(p), 9.1, 2.0), gfw, 1.0) * front * (1.0 - 0.6 * reduce_fx);
	}
	vec3 out_alb = mix(base_alb, c_alb, mask);
	vec3 out_em = mix(base_em, c_em, mask);
	out_alb = mix(out_alb, RABBIT_WHITE * 0.3, fl);
	out_em = mix(out_em, RABBIT_WHITE * 0.7, fl);

	ALBEDO = out_alb;
	EMISSION = out_em;
	ROUGHNESS = 1.0;
}
