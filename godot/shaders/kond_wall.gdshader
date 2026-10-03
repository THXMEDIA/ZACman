// kond_wall.gdshader — the rabbit-condition looks for the speedrun walls
// (spec docs/design/kaninchen-speedrun.md 1.2, from the art-direction
// prototype tools/art/speedrun_proto/konditionen.patch).
//
// ONE material for all condition looks, switched only through uniforms
// (look, transition, flip, reduce_fx). MazeView swaps it onto the SAME wall
// MultiMesh via the Look-API while a condition runs (no second wall set) and
// back to pacman_wall.gdshader afterwards. Look 0 is the exact base look
// (pacman_wall_base.gdshaderinc), so the swap itself is invisible: Main then
// tweens `transition` 0 -> 1 in 0.8 s (wave from the player, lines decay to
// glyphs in rabbit white) and 1 -> 0 at the end.
//
// Glyphs lie in world coordinates (not per box UV): same glyph size on every
// wall, seamless columns across block borders.

shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, specular_disabled;

#include "res://shaders/pacman_wall_base.gdshaderinc"
#include "res://shaders/kond_common.gdshaderinc"

uniform int look = 0;
uniform float transition : hint_range(0.0, 1.0) = 0.0; // 0 = base, 1 = condition look
uniform float flip : hint_range(0.0, 1.0) = 0.0;       // F&L: 1 = steering manipulation acting ("gekippt")
uniform float reduce_fx : hint_range(0.0, 1.0) = 0.0;  // option "Effekte reduzieren"
uniform float matrix_solid : hint_range(0.0, 1.0) = 0.0; // Matrix: last 3 s, walls fade back in
uniform vec2 glyph_cell = vec2(0.16, 0.15);            // glyph cell in m (w x h)
uniform float wall_top = 4.4;
uniform float transition_radius = 18.0;

// Matrix "Durchlässiger Code"
uniform vec3 mx_bg : source_color = vec3(0.0, 0.012, 0.004);       // #000301
uniform vec3 mx_dim : source_color = vec3(0.0, 0.10, 0.035);       // #001A09
uniform vec3 mx_glyph : source_color = vec3(0.0, 0.85, 0.30);      // #00D94D
uniform vec3 mx_head : source_color = vec3(0.80, 1.0, 0.86);       // #CCFFDB
uniform vec3 mx_edge : source_color = vec3(0.0, 0.55, 0.22);       // #008C38
uniform float mx_fall_speed = 8.0;
uniform float mx_active_cols = 0.6;
uniform float mx_near_density = 0.08; // share of drawn pixels right in front of the camera
uniform float mx_mid_density = 0.72;  // ... at corridor width (grid glass)
uniform float mx_far_density = 0.94;  // ... far away (maze stays readable)
// Fear & Loathing "Kippbild": two palettes of similar brightness
uniform vec3 fc_a_low : source_color = vec3(0.17, 0.04, 0.24);     // #2B0A3D
uniform vec3 fc_a_mid : source_color = vec3(0.70, 0.09, 0.36);     // #B3175C
uniform vec3 fc_a_high : source_color = vec3(0.95, 0.42, 0.20);    // #F26B33
uniform vec3 fc_b_low : source_color = vec3(0.03, 0.18, 0.20);     // #072E33
uniform vec3 fc_b_mid : source_color = vec3(0.06, 0.55, 0.52);     // #0F8C85
uniform vec3 fc_b_high : source_color = vec3(0.30, 0.80, 0.95);    // #4DCCF2

vec3 sunset(float h, vec3 lo, vec3 mi, vec3 hi) {
	return h < 0.5 ? mix(lo, mi, h * 2.0) : mix(mi, hi, h * 2.0 - 1.0);
}

void fragment() {
	vec3 cam = CAMERA_POSITION_WORLD;
	vec3 base_alb;
	vec3 base_em;
	pacman_wall(cam, base_alb, base_em);

	vec3 n = normalize(wnorm);
	bool vert = abs(n.y) < 0.5;
	vec3 tng = vert ? normalize(cross(vec3(0.0, 1.0, 0.0), n)) : vec3(1.0, 0.0, 0.0);
	float u_m = vert ? dot(wpos, tng) : wpos.x;          // horizontal, m
	float v_m = vert ? (wall_top - wpos.y) : wpos.z;     // top to bottom, m
	vec2 p = vec2(u_m, v_m) / glyph_cell;
	vec2 face_salt = floor(n.xz * 3.0 + 3.5) * 17.0;

	// derivatives in uniform control flow
	vec2 dp = fwidth(p);
	float gfw = max(dp.x, dp.y) * 8.0;
	vec2 gcell = floor(p);
	float dist = length(wpos - cam);

	float rel_y = wpos.y - center.y;
	float d_top = half_h - rel_y;        // distance to the top edge (m)
	float d_bot = half_h + rel_y;        // distance to the bottom edge (m)
	float aa_top = max(fwidth(d_top), 1e-4);
	float aa_bot = max(fwidth(d_bot), 1e-4);

	vec3 c_alb = base_alb;
	vec3 c_em = base_em;
	float density = 1.0;  // share of drawn pixels (Matrix: permeable walls)
	float inrain = 0.0;   // 1 = pixel belongs to a glowing rain trail (always solid)

	if (look == 1) {
		// MATRIX — permeable code: standing glyph columns, travelling write heads;
		// background only partly drawn via the Bayer pattern: through the wall
		// you see the next corridor.
		float colseed = k_hash1(gcell.x * 91.7 + face_salt.x + face_salt.y * 0.37);
		int gi = k_glyph_index(gcell + face_salt, 1.3, 0.22);
		float has = step(k_hash2(gcell * 1.7 + face_salt), 0.72);
		float lit = k_glyph(p, gi, gfw, has);
		vec3 col = mix(mx_bg, mx_dim, lit * 0.9);
		float rows_h = wall_top / glyph_cell.y;
		if (colseed < mx_active_cols) {
			float span = rows_h * 1.8;
			float speed = mx_fall_speed * (0.65 + 0.7 * k_hash1(colseed * 77.0)) * mix(1.0, 0.35, reduce_fx);
			float head = floor(fract(TIME * speed / span + colseed * 5.0) * span) - rows_h * 0.3;
			float trail = mix(8.0, 22.0, k_hash1(colseed * 33.0));
			float d = head - gcell.y;
			if (d >= 0.0 && d < trail) {
				float k = 1.0 - d / trail;
				vec3 c = (d < 1.0) ? mx_head : mx_glyph * (0.25 + 0.75 * k * k);
				col = mix(col, c, lit);
				inrain = lit;
			}
		}
		// construct edge on top: the only continuous line, shows the wall height
		col = max(col, mx_edge * k_line(d_top - 0.03, 0.02, aa_top) * (1.0 + matrix_solid));
		// lower strip calm (floor anchor)
		float calm = smoothstep(0.0, 0.9, d_bot);
		col = mix(mix(mx_bg, mx_dim, lit * 0.9), col, calm);
		// near (< ~1.2 m) the wall opens almost fully, corridor distance grid
		// glass, far almost dense -> maze structure stays readable
		density = mix(mx_near_density, mx_mid_density, smoothstep(0.45, 1.3, dist));
		density = mix(density, mx_far_density, smoothstep(2.5, 8.0, dist));
		density = mix(density, 1.0, max(reduce_fx, matrix_solid));
		if (!FRONT_FACING) {
			// inside a wall: back faces as dimmed code -> "I am inside the program"
			col *= 0.45;
			density *= mix(0.5, 1.0, matrix_solid);
		}
		// last 3 s: the walls fade back in (solid dark mass under the code)
		col = mix(col, max(col, base_em * 0.35 + mx_dim), matrix_solid * 0.6);
		c_alb = col * 0.35;
		c_em = col * 1.35;
	} else if (look == 2) {
		// FEAR & LOATHING "Kippbild": desert neon in melting stripes. While the
		// steering manipulation acts (flip = 1) the palette tips into its
		// complement and the stripes flow upward instead of downward. Same
		// brightness in both states -> no flash, but an unmistakable signal.
		float dir = mix(1.0, -1.0, step(0.5, flip));
		float colw = 0.22;                          // drip columns 22 cm
		float dcol = floor(u_m / colw);
		float drip = (0.10 * sin(u_m * 2.3) + 0.06 * sin(u_m * 5.9 + 1.7) + 0.16 * k_hash1(dcol * 13.7 + face_salt.x)) * (1.0 - 0.6 * reduce_fx);
		float heat = sin(u_m * 1.3 + TIME * 0.5) * 0.18 * (1.0 - 0.7 * reduce_fx);
		float s = (wpos.y + drip + heat) * 1.1 + TIME * 0.12 * dir * (1.0 - 0.7 * reduce_fx);   // calm flow (~0.1 stripes/s)
		float band = fract(s);
		float aa = max(fwidth(s), 1e-4);
		float stripe = smoothstep(0.5 - aa, 0.5 + aa, band) * (1.0 - smoothstep(1.0 - aa, 1.0, band));
		float h = clamp(wpos.y / wall_top, 0.0, 1.0);
		vec3 pa = sunset(h, fc_a_low, fc_a_mid, fc_a_high);
		vec3 pb = sunset(h, fc_b_low, fc_b_mid, fc_b_high);
		vec3 pal = mix(pa, pb, flip);
		vec3 col = mix(pal * 0.42, pal * 0.76, stripe);
		// dark skirting: the floor edge always stays readable
		col *= mix(0.35, 1.0, smoothstep(0.0, 0.35, d_bot));
		c_alb = col * 0.35;
		c_em = col * 1.1;
	} else if (look == 3) {
		// TASCHENUHR: base look, slightly warm tint
		c_alb = k_warm(base_alb);
		c_em = k_warm(base_em);
	} else if (look == 4) {
		// STROMAUSFALL: base look with the neon nearly off (fog does the rest)
		c_alb = base_alb * 0.6;
		c_em = base_em * 0.22;
	}

	// ---------------- transition base -> condition ----------------
	float th = k_trans_threshold(floor(p), dist, transition_radius);
	float mask = step(th, transition * 1.0001);
	float front = (1.0 - smoothstep(0.0, 0.045, abs(transition - th))) * step(0.001, transition) * step(transition, 0.999) * float(look != 0);
	// in the front the lines decay into glyphs in rabbit white
	float fl = k_glyph(p, k_glyph_index(floor(p), 9.1, 2.0), gfw, 1.0) * front * (1.0 - 0.6 * reduce_fx);

	vec3 out_alb = mix(base_alb, c_alb, mask);
	vec3 out_em = mix(base_em, c_em, mask);
	out_alb = mix(out_alb, RABBIT_WHITE * 0.3, fl);
	out_em = mix(out_em, RABBIT_WHITE * 1.25, fl);

	// Matrix permeability (only where the condition look already applies)
	if (look == 1 && mask > 0.5 && fl < 0.5) {
		// rain trails stay solid, except right in front of the camera
		float keep = inrain > 0.5 ? mix(0.4, 1.0, smoothstep(0.4, 1.2, dist)) : density;
		if (k_bayer(FRAGCOORD.xy) > keep) {
			discard;
		}
	}

	ALBEDO = out_alb;
	EMISSION = out_em;
	ROUGHNESS = 0.9;
}
