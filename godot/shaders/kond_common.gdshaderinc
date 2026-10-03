// kond_common.gdshaderinc — building blocks of the rabbit-condition looks
// (spec docs/design/kaninchen-speedrun.md 1.2), taken over from the art-
// direction prototype tools/art/speedrun_proto/konditionen.patch:
// own glyph set "ZAP-Code" (8x8, 1-px strokes — no film glyphs, no katakana),
// hashes, Bayer dither, fwidth-coupled glyphs/lines and the 0.8 s transition
// wave base look -> condition look.
//
// Look ids (uniform int look, see scripts/condition_looks.gd):
//   0 = base (Pac-Man "Lagune")   1 = Matrix "Durchlässiger Code"
//   2 = Fear & Loathing "Kippbild"   3 = Taschenuhr (warm tint)
//   4 = Stromausfall (dimmed lines; the fog comes from the Environment)

const int GLYPH_COUNT = 24;
const int GLYPH_ROWS[192] = int[192](
0,0,0,0,0,0,0,0,
252,8,16,32,64,128,252,0,
48,72,132,252,132,132,132,0,
120,128,128,128,128,128,120,0,
120,140,148,164,196,132,120,0,
32,96,32,32,32,32,112,0,
120,132,4,24,96,128,252,0,
248,4,4,56,4,4,248,0,
136,136,136,252,8,8,8,0,
252,128,248,4,4,132,120,0,
252,4,8,16,32,32,32,0,
120,132,132,124,4,8,112,0,
248,8,8,16,32,32,32,0,
128,128,240,136,136,136,136,0,
32,252,32,32,32,36,24,0,
132,132,72,48,72,132,132,0,
252,132,132,252,128,128,128,0,
32,32,252,32,80,136,132,0,
130,130,68,40,16,16,16,0,
252,32,32,60,32,32,32,0,
192,32,32,56,36,36,56,0,
8,16,32,124,16,32,64,0,
168,0,0,254,16,16,16,0,
48,48,0,252,0,48,48,0
);

// Rabbit white #F2F2ED: the glyphs in the transition wave front.
const vec3 RABBIT_WHITE = vec3(0.95, 0.95, 0.93);

float k_hash1(float n) { return fract(sin(n) * 43758.5453123); }
float k_hash2(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453123); }

// 4x4 Bayer threshold 0..1 from FRAGCOORD (screen-fixed, no temporal noise)
float k_bayer(vec2 fc) {
	ivec2 q = ivec2(mod(fc, 4.0));
	int i = q.x + q.y * 4;
	int m[16] = int[16](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
	return (float(m[i]) + 0.5) / 16.0;
}

// Glyph coverage 0..1. p in glyph cells (y down), gi glyph index, has = 0/1
// whether the cell carries a glyph at all, gfw = glyph texels per screen pixel
// (computed by the caller via fwidth, in uniform control flow). From ~1
// texel/pixel on it blends to the field's mean coverage: no shimmer and no
// block pattern on distance.
float k_glyph(vec2 p, int gi, float gfw, float has) {
	vec2 lf = fract(p);
	bool in_cell = lf.x > 0.12 && lf.x < 0.88 && lf.y > 0.06 && lf.y < 0.94;
	ivec2 l = clamp(ivec2(vec2((lf.x - 0.12) / 0.76 * 8.0, (lf.y - 0.06) / 0.88 * 8.0)), ivec2(0), ivec2(7));
	float bit = in_cell ? float((GLYPH_ROWS[gi * 8 + l.y] >> (7 - l.x)) & 1) : 0.0;
	return mix(bit * has, 0.15, smoothstep(0.5, 1.2, gfw));
}

// Glyph index of a cell; mutates slowly (every ~3-8 s per cell, far below 3 Hz)
int k_glyph_index(vec2 gc, float salt, float rate) {
	float mut = floor(TIME * rate * (0.6 + 0.8 * k_hash2(gc + salt)) + k_hash2(gc.yx + salt) * 10.0);
	return 1 + int(k_hash2(gc + vec2(mut * 3.1, salt)) * float(GLYPH_COUNT - 1));
}

// Antialiased line: 1 inside width w around d = 0, edge over aa (= fwidth(d))
float k_line(float d, float w, float aa) {
	return 1.0 - smoothstep(w - aa, w + aa, abs(d));
}

// Transition wave: threshold per glyph cell from the distance to the camera
// (the wave runs outward from the player) plus a little noise.
float k_trans_threshold(vec2 gc, float dist, float radius) {
	return 0.72 * clamp(dist / radius, 0.0, 1.0) + 0.28 * k_hash2(gc * 1.37 + 5.1);
}

// Warm tint of the Taschenuhr look: a slight pull of every color toward
// amber at its own brightness (turquoise lines get warmer, not greener).
vec3 k_warm(vec3 c) {
	float lum = dot(c, vec3(0.3, 0.5, 0.2));
	return mix(c, lum * vec3(1.3, 0.95, 0.55), 0.38);
}
