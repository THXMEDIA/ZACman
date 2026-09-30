// matrix_rain.gdshader
//
// The Matrix levels' wall material: scrolling random green glyphs baked
// straight into the wall surface (via the box mesh's own UVs), always
// fully green/ASCII — never a "real" lit color, at any distance. This
// replaces the old ascii_post.gdshader screen-space post effect, which
// only turned distant geometry into ASCII and showed the raw blue wall
// material up close (exactly the "blue wall, not ASCII" complaint this
// fixes). See MazeView._make_materials / CityTheme.wall_matrix_rain for
// where this gets applied.
//
// Technique: same 8x8 glyph-bitmap trick as ascii_post.gdshader (glyphs
// encoded as bit patterns, no font/texture asset needed), but sampled in
// each wall face's own UV space instead of screen space, and scrolling
// continuously in -V (i.e. downward, "top to bottom, like a terminal")
// by subtracting TIME*speed from the row coordinate before flooring —
// the standard trick for an endless scrolling procedural texture. Each
// column gets its own random speed/phase (from a hash of its column
// index) so the whole wall doesn't scroll as one flat sheet.
//
// Depth layers (LAYER_COUNT below): rather than one flat sheet of glyphs,
// the wall now composites LAYER_COUNT independent glyph "tapes" — like
// stacking multiple panes of falling code one behind another, closest to
// farthest. Each layer back from the front one is a little finer-grained
// (smaller glyphs, reading as farther away), a little dimmer (atmospheric
// falloff), a little slower, and phase-shifted sideways (its own offset
// into the random tape) so the layers never line up. They're composited
// back-to-front: wherever a nearer layer has no lit glyph (i.e. it's
// showing empty background), the layer behind it shows through instead of
// flat bg_color — the classic "columns of code raining past each other at
// different depths" look from the film this whole word-built-world idea
// nods to, instead of one uniform plane of text.
//
// Floor-fade (floor_fade_frac below): a full-height, uniformly-downward-
// scrolling pattern running edge-to-edge down every wall in a corridor is
// exactly the trigger vection research (illusory self-motion — see e.g.
// https://en.wikipedia.org/wiki/Illusions_of_self-motion and VR-comfort
// guides like Meta's locomotion-comfort docs) describes for "the ground
// feels like it's moving/tilting": a large, high-contrast, coherently-
// moving field right down to the floor line, with the motion cutting off
// abruptly where the (static) floor begins. That abrupt handoff reads as
// the floor rising to meet the falling rain. The fix those sources give is
// a static reference frame right at the trouble spot — here, fading the
// scrolling glyphs out to the (static, non-scrolling) bg_color over the
// bottom slice of each wall gives the eye a calm, motionless strip right
// at floor level instead of live motion running straight into it.

shader_type spatial;
render_mode unshaded, cull_back;

uniform float cols_per_face = 48.0;  // glyph columns across one wall face's width (3x finer than the previous 16)
uniform float rows_per_face = 90.0;  // glyph rows across one wall face's height (3x finer than the previous 30)
uniform float fall_speed = 11.0;     // base rows scrolled per second (lowered from 15 — less optic-flow magnitude, a smaller vection trigger)
uniform float glyph_density = 0.7;   // fraction of cells showing a glyph rather than empty background (lowered from 0.8 — less coherent moving contrast)
uniform vec3 glyph_color = vec3(0.25, 1.0, 0.35);
uniform vec3 bg_color = vec3(0.004, 0.03, 0.012);
uniform float floor_fade_frac = 0.16; // bottom fraction of the wall's own height that fades out to bg_color (a static strip right at floor level)

const int LAYER_COUNT = 5; // "5 rows of code running behind each other" — see header comment above

varying float local_y; // this wall instance's own local mesh Y, -0.5 (floor) .. +0.5 (top) — independent of per-instance height scaling

// 10 glyph shapes, each an 8x8 bit pattern (MSB = leftmost pixel),
// index 0 left as blank/space. Same table as ascii_post.gdshader.
const int GLYPH_ROWS[80] = int[80](
	0,0,0,0,0,0,0,0,
	0,0,0,0,0,24,24,0,
	0,24,24,0,24,24,0,0,
	0,0,0,126,0,0,0,0,
	0,0,126,0,126,0,0,0,
	0,24,24,126,126,24,24,0,
	36,24,126,24,36,0,0,0,
	102,102,255,102,255,102,102,0,
	99,102,60,24,60,102,198,0,
	60,102,110,106,110,96,60,0
);

float hash1(float n) {
	return fract(sin(n) * 43758.5453123);
}

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453123);
}

int glyph_bit(int glyph_index, ivec2 local) {
	int row = GLYPH_ROWS[glyph_index * 8 + local.y];
	return (row >> (7 - local.x)) & 1;
}

void vertex() {
	local_y = VERTEX.y;
}

// One glyph "tape" at a given depth (0 = nearest/front layer, LAYER_COUNT-1
// = farthest/back layer). Farther layers use a finer grid (smaller glyphs,
// reading as more distant), drift a little slower, are phase-shifted
// sideways so they never line up with the layer in front, and are dimmed
// toward bg_color (atmospheric/depth falloff). depth=0 reproduces exactly
// the original single-layer look (same scale/speed/brightness as before).
vec3 sample_layer(vec2 uv, int depth, out bool hit) {
	float d = float(depth);
	float depth_scale = 1.0 + d * 0.35;
	float speed_mul = 1.0 - d * 0.12;
	float phase = d * 37.5;

	float cols = cols_per_face * depth_scale;
	float rows = rows_per_face * depth_scale;

	float col = floor(uv.x * cols + phase);
	float col_seed = hash1(col * 91.7 + 3.1 + d * 17.0);
	// Subtracting TIME*speed before flooring makes a fixed point on the
	// wall sample an ever-advancing sequence of "rows" from an infinite
	// random tape — i.e. the pattern appears to scroll toward +V (down)
	// as time passes. Each column's own seed varies its speed a bit so
	// columns drift out of sync, like real digital rain.
	float scaled_row = uv.y * rows - TIME * fall_speed * speed_mul * (0.6 + col_seed * 0.8) + phase * 4.0;
	float row = floor(scaled_row);

	vec2 cell_key = vec2(col, row) + vec2(d * 53.0, d * 29.0);
	hit = false;
	vec3 color = bg_color;

	if (hash2(cell_key) < glyph_density) {
		int glyph_index = 1 + int(hash2(cell_key + vec2(11.0, 0.0)) * 9.0); // 1..9, never blank
		vec2 local_frac = vec2(fract(uv.x * cols + phase), fract(scaled_row));
		ivec2 local = clamp(ivec2(local_frac * 8.0), ivec2(0), ivec2(7));
		int lit = glyph_bit(glyph_index, local);
		if (lit == 1) {
			hit = true;
			float brightness = 0.55 + 0.45 * hash2(cell_key + vec2(5.0, 0.0));
			float depth_dim = 1.0 - (d / float(LAYER_COUNT)) * 0.75;
			color = glyph_color * brightness * depth_dim;
		}
	}
	return color;
}

void fragment() {
	// Composite back-to-front: start from the farthest layer and let each
	// nearer layer paint over it only where that layer actually has a lit
	// glyph, so gaps in a near layer reveal the layer(s) behind it.
	vec3 color = bg_color;
	bool hit;
	for (int i = LAYER_COUNT - 1; i >= 0; i--) {
		vec3 layer_color = sample_layer(UV, i, hit);
		if (hit) {
			color = layer_color;
		}
	}

	// Fade the scrolling pattern out to the static bg_color over the
	// bottom floor_fade_frac of the wall's height — see the header comment
	// on floor_fade_frac for why (countering the "floor looks like it's
	// rising" illusion).
	float floor_fade = smoothstep(-0.5, -0.5 + floor_fade_frac, local_y);
	color = mix(bg_color, color, floor_fade);

	ALBEDO = color;
	EMISSION = color * 1.5;
}
