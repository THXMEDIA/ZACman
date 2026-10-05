// Amsterdam: every board of the cardboard model (facades, piers, sills,
// window crosses, side walls, roofs, bridges, the tower, the tram) is one
// instance of a unit box in a MultiMesh. The shader rebuilds the face size in
// metres from the instance scale: the thinnest axis is the board thickness,
// faces that contain it are cut edges (liner - flute - liner, open cavities),
// the broad faces show the kraft scan, washboard ribs, worn edges and tape.
// INSTANCE_CUSTOM = (seed, brightness 0..1, paint 0 kraft / 0.5 white /
// 1 exit green, flags/8: 1 = tape strip, 2 = solid dark (window interior)).
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

#include "res://shaders/amsterdam_common.gdshaderinc"

uniform sampler2D tape_alb : source_color, filter_linear_mipmap, repeat_enable;
uniform vec3 white_paint : source_color = vec3(0.914, 0.894, 0.847);
uniform vec3 exit_paint : source_color = vec3(0.0, 0.722, 0.580);
uniform float exit_emit = 0.0;
uniform float rib_amp = 0.22;

varying vec3 lp;
varying vec3 ln;
varying vec3 bs;
varying vec4 cu;
varying float vdist;

void vertex() {
	bs = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	cu = INSTANCE_CUSTOM;
	lp = VERTEX * bs;
	ln = NORMAL;
	vdist = length((MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz - CAMERA_POSITION_WORLD);
}

void fragment() {
	float seed = cu.x * 91.7 + 0.37;
	float flags = floor(cu.w * 8.0 + 0.5);
	bool solid = mod(floor(flags / 2.0), 2.0) > 0.5;
	bool tape_on = mod(flags, 2.0) > 0.5;
	vec3 an = abs(ln);
	vec2 q; vec2 hs; vec3 au; vec3 av;
	if (an.y > 0.5) { q = vec2(lp.x, lp.z * sign(ln.y)); hs = bs.xz * 0.5; au = vec3(1, 0, 0); av = vec3(0, 0, sign(ln.y)); }
	else if (an.x > 0.5) { q = vec2(-lp.z * sign(ln.x), lp.y); hs = bs.zy * 0.5; au = vec3(0, 0, -sign(ln.x)); av = vec3(0, 1, 0); }
	else { q = vec2(lp.x * sign(ln.z), lp.y); hs = bs.xy * 0.5; au = vec3(sign(ln.z), 0, 0); av = vec3(0, 1, 0); }
	float far = 1.0 - smoothstep(far_flat * 0.5, far_flat, vdist);
	float bri = mix(0.82, 1.08, cu.y);
	vec3 thin = (bs.x <= bs.y && bs.x <= bs.z) ? vec3(1, 0, 0) : ((bs.y <= bs.z) ? vec3(0, 1, 0) : vec3(0, 0, 1));
	bool edge = abs(dot(ln, thin)) < 0.5 && min(bs.x, min(bs.y, bs.z)) > 0.2;
	vec3 c; vec2 nxy; float r;
	vec2 off = vec2(h11(seed) * 97.0, h11(seed * 3.0) * 53.0);
	// Texture reads in these branches use implicit derivatives on purpose
	// (code W5): solid / edge / tape depend on the instance (flat custom
	// data) and the box face (constant normal), so all pixels of a 2x2 quad
	// - which never span two triangles - take the same branch.
	if (solid) {
		// the dark room behind a window: unlit cardboard in deep shadow
		kraft_face(q + off, 0.0, c, nxy, r);
		c *= 0.045;
		nxy = vec2(0.0);
		r = 1.0;
	} else if (edge) {
		bool tu = abs(dot(au, thin)) > 0.5;
		float v = (tu ? q.x / hs.x : q.y / hs.y) * 0.5 + 0.5;
		float u = tu ? q.y : q.x;
		float paper = flute_mask(u, v, far);
		kraft_face(vec2(u, v * 0.4) + off, far, c, nxy, r);
		c *= bri;
		float w = 0.5 + 0.32 * sin(u * 6.2831853 / pitch);
		float occ = smoothstep(0.0, 0.32, abs(v - w));
		c = mix(c * 0.12 * (1.6 - occ), c * vec3(1.10, 1.07, 1.02), paper);
		float slope = cos(u * 6.2831853 / pitch) * paper * far;
		if (tu) nxy = vec2(nxy.x, nxy.y - slope * 0.5); else nxy = vec2(nxy.x - slope * 0.5, nxy.y);
		r = 0.93;
		AO = mix(0.45, 1.0, paper);
		AO_LIGHT_AFFECT = 0.5;
	} else {
		kraft_face(q + off, far, c, nxy, r);
		c *= bri * vec3(1.0 + 0.04 * (h11(seed * 3.1) - 0.5), 1.0, 1.0 - 0.05 * (h11(seed * 5.3) - 0.5));
		// washboard: the flutes inside show through the liner
		float ribs = sin(q.x * 6.2831853 / pitch);
		c *= 1.0 - 0.03 * ribs * far;
		nxy.x += cos(q.x * 6.2831853 / pitch) * rib_amp * far;
		// worn, slightly lighter cut corners and a dark joint line
		vec2 ed = hs - abs(q);
		float e = min(ed.x, ed.y);
		float wear = (1.0 - smoothstep(0.0, 0.05 + 0.05 * vn(q * 6.0 + seed), e)) * (0.5 + 0.5 * vn(q * 3.0 + seed));
		c = mix(c, c * vec3(1.15, 1.12, 1.08) + 0.02, wear * 0.7);
		AO = mix(0.7, 1.0, smoothstep(0.0, 0.25, e));
		AO_LIGHT_AFFECT = 0.3;
		// tape over a board joint, near one end of the board
		if (tape_on) {
			float tw = 0.95;
			float tx = hs.x - 1.3 - 2.0 * h11(seed * 4.1);
			float tm = (1.0 - smoothstep(tw - 0.04, tw, abs(q.x - tx))) * step(abs(q.y), hs.y - 0.05);
			vec3 tc = texture(tape_alb, vec2(q.y / 4.0, (q.x - tx) / (2.0 * tw) + 0.5)).rgb;
			c = mix(c, c * 0.35 + tc * 0.75, tm * 0.85);
			r = mix(r, 0.3, tm);
			SPECULAR = mix(0.4, 0.75, tm);
		}
	}
	float paint = cu.z;
	if (paint > 0.25 && !solid) {
		// the exit green is painted a little darker and glows a little
		// (exit_emit), so the low warm sun does not bleach it (QA K2)
		vec3 pc = paint > 0.75 ? exit_paint * 0.72 : white_paint;

		float brush = vn(q * vec2(0.4, 2.2) + seed) * 0.6 + vn(q * vec2(1.8, 7.0)) * 0.4;
		float m = smoothstep(0.08, 0.2, brush + 0.5);
		c = mix(c, pc * (0.92 + 0.1 * brush) * (0.95 + 0.1 * dot(c, vec3(0.6))), m * (edge ? 0.55 : 1.0));
		r = mix(r, 0.55, m);
		if (paint > 0.75) EMISSION = exit_paint * exit_emit * m;
	}
	vec3 ln2 = normalize(ln + au * nxy.x + av * nxy.y);
	vec3 wn = normalize(mat3(MODEL_MATRIX) * (ln2 / bs * min(bs.x, min(bs.y, bs.z))));
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
	ALBEDO = c;
	ROUGHNESS = r;
}
