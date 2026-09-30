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

shader_type spatial;
render_mode unshaded, cull_back;

uniform float cols_per_face = 5.0;   // glyph columns across one wall face's width
uniform float rows_per_face = 19.0;  // glyph rows across one wall face's height (WALL_H)
uniform float fall_speed = 3.2;      // base rows scrolled per second
uniform float glyph_density = 0.8;   // fraction of cells showing a glyph rather than empty background
uniform vec3 glyph_color = vec3(0.25, 1.0, 0.35);
uniform vec3 bg_color = vec3(0.004, 0.03, 0.012);

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

void fragment() {
	float col = floor(UV.x * cols_per_face);
	float col_seed = hash1(col * 91.7 + 3.1);
	// Subtracting TIME*speed before flooring makes a fixed point on the
	// wall sample an ever-advancing sequence of "rows" from an infinite
	// random tape — i.e. the pattern appears to scroll toward +V (down)
	// as time passes. Each column's own seed varies its speed a bit so
	// columns drift out of sync, like real digital rain.
	float scaled_row = UV.y * rows_per_face - TIME * fall_speed * (0.6 + col_seed * 0.8);
	float row = floor(scaled_row);

	vec2 cell_key = vec2(col, row);
	vec3 color = bg_color;

	if (hash2(cell_key) < glyph_density) {
		int glyph_index = 1 + int(hash2(cell_key + vec2(11.0, 0.0)) * 9.0); // 1..9, never blank
		vec2 local_frac = vec2(fract(UV.x * cols_per_face), fract(scaled_row));
		ivec2 local = clamp(ivec2(local_frac * 8.0), ivec2(0), ivec2(7));
		int lit = glyph_bit(glyph_index, local);
		float brightness = 0.55 + 0.45 * hash2(cell_key + vec2(5.0, 0.0));
		color = mix(bg_color, glyph_color * brightness, float(lit));
	}

	ALBEDO = color;
	EMISSION = color * 1.5;
}
