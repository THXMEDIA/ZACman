// Shared parts of the Arles brush shaders (docs/design/arles-explorer.md,
// art: direction B v2 "Sternennacht, echte Orte stilisiert"). Ported from the
// art director's prototype (tools/art/explorer_proto/arles_v2/shaders.gd).
//  - impasto: short visible strokes with a direction that follows the form,
//    a relief ridge across the stroke (the few real lamps give gloss)
//  - stroke LOD (technical condition): between lod_near and lod_far, and
//    wherever a stroke gets thinner than ~3 pixels, the impasto turns into
//    large soft dabs of low frequency (not a flat mean colour)
//  - painted light pools: the gas lamps without a real light light walls and
//    floor in the shader; per 4 m tile only the nearest 8 lamps are looked at
//    (tile list baked by arles_scenery.gd: tile_tex holds lamp indices + 1)
//  - MAP_SHIFT: the scenery is built in map space (world + (1, 0, 1)), the
//    prototype's coordinates; every shader works in map space.

const vec3 MAP_SHIFT = vec3(1.0, 0.0, 1.0);

uniform float lod_on = 1.0;
uniform float lod_near = 14.0;
uniform float lod_far = 28.0;
uniform float calm = 0.0;            // "Effekte reduzieren": calmer brush
// Slow sway of the brush strokes along their flow (Abnahme 06.10.): every stroke
// row slides along its own length by at most flow_amp * stroke length (5 %,
// a few cm), the phase runs across the rows as a slow wave (flow_hz = 0.08 Hz,
// far below the 3 Hz limit). One impasto evaluation, no second layer, no
// ghosting. It fades out with the stroke LOD (far dabs never move: no edge
// flicker) and stops with moving = 0 ("Effekte reduzieren"). The sky has its
// own drift (arles_sky.gdshader).
uniform float moving = 1.0;
uniform float flow_amp = 0.05;       // share of the stroke length
uniform float flow_hz = 0.08;        // wave frequency (Hz)
uniform float flow_gain = 1.0;       // per material (floor: half, water: 0)
uniform sampler2D lamp_tex : filter_nearest;   // x = lamp index: xyz map position, w strength
uniform sampler2D tile_tex : filter_nearest;   // 2 texels per tile: 8 lamp indices + 1 (0 = none)
uniform vec4 tile_grid = vec4(-16.0, -16.0, 4.0, 0.0); // origin x/z (map), tile size, unused
uniform vec2 tile_count = vec2(32.0, 30.0);
uniform vec3 lamp_col = vec3(1.0, 0.76, 0.40);
uniform float pool_gain = 1.0;

float hash21(vec2 p) { p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i), b = hash21(i + vec2(1, 0)), c = hash21(i + vec2(0, 1)), d = hash21(i + vec2(1, 1));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float stroke_lod(float dist, float pix) {
	float l = max(smoothstep(lod_near, lod_far, dist), smoothstep(0.30, 0.75, pix));
	return clamp(max(l * lod_on, calm * 0.45), 0.0, 1.0);
}

// Brightness amplitude of the strokes close to the camera (UX W-F): within
// NEAR_AMP_M the light/dark swing of the strokes is capped a little (to 80 %),
// with "Effekte reduzieren" (calm) by half; 1 = full swing further away.
const float NEAR_AMP_M = 6.0;
float near_amp(float dist) {
	float k = smoothstep(NEAR_AMP_M * 0.5, NEAR_AMP_M, dist);
	return mix(mix(0.8, 0.5, calm), 1.0, k);
}

vec3 pool_one(float idx, vec3 p, vec3 n) {
	if (idx < 0.5) return vec3(0.0);
	vec4 l = texelFetch(lamp_tex, ivec2(int(idx + 0.5) - 1, 0), 0);
	vec3 d = l.xyz - p; float dd = dot(d, d);
	float ndl = clamp(dot(n, d * inversesqrt(dd + 0.0001)) * 0.65 + 0.35, 0.0, 1.0);
	return vec3(l.w * ndl / (1.0 + dd * 0.10) * smoothstep(225.0, 25.0, dd));
}

vec3 pools(vec3 p, vec3 n) {
	vec2 t = floor((p.xz - tile_grid.xy) / tile_grid.z);
	if (t.x < 0.0 || t.y < 0.0 || t.x >= tile_count.x || t.y >= tile_count.y) return vec3(0.0);
	vec3 acc = vec3(0.0);
	for (int k = 0; k < 2; k++) {
		vec4 ids = texelFetch(tile_tex, ivec2(int(t.x) * 2 + k, int(t.y)), 0) * 255.0;
		acc += pool_one(ids.x, p, n) + pool_one(ids.y, p, n) + pool_one(ids.z, p, n) + pool_one(ids.w, p, n);
	}
	return acc * lamp_col * pool_gain;
}

float cell_angle(vec2 uv, float len, float base, int mode, vec2 ctr) {
	float cs = len * 2.6;
	vec2 mc = floor(uv / cs + vec2(0.0, 0.5 * mod(floor(uv.x / cs), 2.0)));
	vec2 mcc = (mc + 0.5) * cs;
	float a = base;
	if (mode == 1) a = atan(mcc.y - ctr.y, mcc.x - ctr.x) + 1.5708;
	if (mode == 2) a = atan(mcc.y - ctr.y, mcc.x - ctr.x);
	return a + (hash21(mc + 0.37) - 0.5) * 0.55;
}

// Colour of one impasto stroke field; ridge (relief across the stroke) and
// the stroke-normal direction for the normal.
// `amp` scales the stroke-to-stroke brightness swing around the local mean
// (near_amp: calmer close to the camera).
vec3 impasto(vec2 uv, vec3 ca, vec3 cb, vec3 cc, float accent, float a, float len, float wid, float lod, float amp, out vec2 dv, out float ridge) {
	vec2 d = vec2(cos(a), sin(a)); vec2 pd = vec2(-d.y, d.x);
	float s = dot(uv, d); float t = dot(uv, pd);
	float row = floor(t / wid);
	float rl = len * (0.6 + 0.8 * hash21(vec2(row, 7.7)));
	float off = hash21(vec2(row, 3.1)) * rl;
	// slow sway along the stroke (see flow_amp); the far dabs below use the plain s
	float sway = flow_amp * flow_gain * moving * (1.0 - lod) * len * sin(TIME * flow_hz * 6.2831853 + row * 0.55 + hash21(vec2(row, 5.5)) * 1.3);
	float ss = s + sway;
	float cell = floor((ss + off) / rl);
	float h = hash21(vec2(row, cell));
	float h2 = hash21(vec2(cell, row) + 9.0);
	float ft = fract(t / wid); float fs = fract((ss + off) / rl);
	float body = smoothstep(0.0, 0.10, fs) * smoothstep(1.0, 0.90, fs);
	vec3 c = mix(ca, cb, h);
	c = mix(c, cc, step(1.0 - accent, h2));
	c *= mix(0.80, 1.10, h2);
	c = mix(c * 0.55, c, body);
	vec3 mean = (mix(ca, cb, 0.5) * (1.0 - accent) + cc * accent) * 0.92;
	c = mix(mean, c, amp);
	dv = pd; ridge = (ft - 0.5) * 2.0 * (1.0 - lod) * amp;

	// far away: large soft dabs of low frequency, no flat mean, no flicker
	vec3 far = mean * (0.72 + 0.56 * vnoise(vec2(s / (len * 5.0), t / (wid * 16.0))));
	return mix(c, far, lod);
}
