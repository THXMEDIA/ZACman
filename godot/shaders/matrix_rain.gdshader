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
// Darker base + a more saturated, more luminous glow than before: the flat
// mid-green (0.25, 1.0, 0.35) read as a fairly bright, slightly washed-out
// green at every brightness level. glyph_color is now deeper and more
// saturated (less blue/less desaturation), bg_color is pulled further
// toward near-black, and EMISSION below is boosted — net effect is a wall
// that reads as darker overall (more contrast, more black space between
// glyphs) while the lit glyphs themselves glow harder/more neon.
uniform vec3 glyph_color = vec3(0.08, 0.95, 0.22);
uniform vec3 bg_color = vec3(0.001, 0.012, 0.004);
uniform float floor_fade_frac = 0.16; // bottom fraction of the wall's own height that fades out to bg_color (a static strip right at floor level)

const int LAYER_COUNT = 5; // "5 rows of code running behind each other" — see header comment above

// Fear & Loathing pickup (see MazeView.set_psychedelic / Main.
// _activate_fear_powerup): 0.0 = the normal green code wall (default);
// driven up to 1.0 from GDScript for the pickup's duration, warping the UV
// with a slow wobble and cycling every glyph through a shifting rainbow
// instead of flat green — an "LSD trip" look the wall temporarily
// dissolves into and back out of, purely cosmetic (never affects the
// actual collision, which Main handles separately by randomly toggling
// noclip while this is active).
uniform float psychedelic_amount = 0.0;

varying float local_y; // this wall instance's own local mesh Y, -0.5 (floor) .. +0.5 (top) — independent of per-instance height scaling

// 31 glyph shapes, each an 8x8 bit pattern (MSB = leftmost pixel), index 0
// left as blank/space. Up from the original 10 ("viel mehr Varianz in die
// verwendeten Zeichen") — the extra 21 are procedurally generated (a few
// random vertical "strokes" plus the occasional horizontal tick, rejecting
// anything too sparse or too dense to read as a character), a script-
// generated equivalent of hand-authoring another couple dozen 8x8 pixel
// glyphs by eye. See scratchpad/gen_glyphs.py in the session history for
// the generator (not checked into the repo — this table is the output).
const int GLYPH_COUNT = 31;
const int GLYPH_ROWS[248] = int[248](
	0,0,0,0,0,0,0,0,
	2,2,6,6,6,6,6,14,
	207,192,192,128,192,220,224,64,
	45,57,41,9,13,13,9,1,
	0,16,19,17,25,17,13,0,
	4,6,6,7,7,7,6,6,
	3,99,65,227,195,193,227,129,
	0,0,194,194,207,11,11,3,
	0,0,2,66,66,98,67,0,
	0,32,56,32,34,35,15,0,
	6,6,103,254,70,70,6,15,
	228,7,102,70,64,64,96,0,
	62,4,68,71,71,6,4,4,
	4,4,4,174,164,36,55,32,
	0,3,3,2,14,10,14,0,
	0,48,48,96,252,224,224,224,
	0,0,3,98,226,255,240,216,
	0,0,158,128,208,208,144,24,
	0,0,2,35,34,32,32,0,
	0,0,4,126,100,64,111,0,
	96,64,72,104,72,104,76,108,
	10,43,42,14,2,0,252,0,
	62,13,45,45,45,37,36,0,
	126,0,0,6,15,12,12,6,
	0,3,79,114,16,16,0,0,
	0,0,64,224,160,160,254,0,
	2,3,3,103,71,70,98,2,
	0,0,0,63,51,50,18,16,
	0,96,98,123,58,0,0,0,
	128,196,158,196,134,134,4,6,
	0,48,49,35,48,63,48,48
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
		int glyph_index = 1 + int(hash2(cell_key + vec2(11.0, 0.0)) * float(GLYPH_COUNT - 1)); // 1..GLYPH_COUNT-1, never blank
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
	vec2 uv = UV;
	if (psychedelic_amount > 0.001) {
		// Slow, sinuous UV wobble — the wall's letterforms swim and bend
		// instead of sitting on a rigid grid.
		float warp_x = sin(uv.y * 18.0 + TIME * 2.3) * 0.03 + sin(uv.x * 25.0 - TIME * 3.1) * 0.02;
		float warp_y = sin(uv.x * 14.0 + TIME * 1.7) * 0.025;
		uv.x += warp_x * psychedelic_amount;
		uv.y += warp_y * psychedelic_amount;
	}

	// Composite back-to-front: start from the farthest layer and let each
	// nearer layer paint over it only where that layer actually has a lit
	// glyph, so gaps in a near layer reveal the layer(s) behind it.
	vec3 color = bg_color;
	bool hit;
	for (int i = LAYER_COUNT - 1; i >= 0; i--) {
		vec3 layer_color = sample_layer(uv, i, hit);
		if (hit) {
			color = layer_color;
		}
	}

	if (psychedelic_amount > 0.001) {
		// Trade the flat green for a slowly drifting rainbow, keeping each
		// pixel's own brightness so the glyph shapes still read through the
		// color-cycling — the "LSD trip" look, purely cosmetic.
		const float TAU_VAL = 6.283185;
		float hue = fract(TIME * 0.15 + uv.x * 0.6 + uv.y * 0.4);
		float lum = max(color.r, max(color.g, color.b));
		vec3 rainbow = vec3(
			0.5 + 0.5 * sin(hue * TAU_VAL),
			0.5 + 0.5 * sin(hue * TAU_VAL + 2.094),
			0.5 + 0.5 * sin(hue * TAU_VAL + 4.189)
		) * max(lum, 0.15);
		color = mix(color, rainbow, psychedelic_amount);
	}

	// Fade the scrolling pattern out to the static bg_color over the
	// bottom floor_fade_frac of the wall's height — see the header comment
	// on floor_fade_frac for why (countering the "floor looks like it's
	// rising" illusion).
	float floor_fade = smoothstep(-0.5, -0.5 + floor_fade_frac, local_y);
	color = mix(bg_color, color, floor_fade);

	ALBEDO = color;
	// Boosted from 1.5x — a darker base (bg_color/glyph_color above) with a
	// stronger emission multiplier is what actually reads as "darker AND
	// more luminous": the unlit background sits closer to true black while
	// the lit glyphs glow harder against it, instead of everything just
	// getting dimmer together.
	EMISSION = color * 2.2;
}
