// Kyoto pop-up card (look "Aizuri-Pop-up", docs/design/kyoto-explorer.md):
// one quad per card in a MultiMesh, printed procedurally in woodblock blue.
// INSTANCE_CUSTOM: r = kind / 255 (+100 = backdrop, never folds),
//                  g = width / 100, b = height / 100, a = variation 0..1.
// The quad's base (local y = 0) is the hinge: the card folds back flat onto
// the page with distance to the camera (fold_on = 0 for "Effekte
// reduzieren": everything stands). The camera itself is never touched.
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform vec3 ai1 : source_color = vec3(0.118, 0.227, 0.431);
uniform vec3 ai2 : source_color = vec3(0.247, 0.424, 0.659);
uniform vec3 ai3 : source_color = vec3(0.553, 0.690, 0.839);
uniform vec3 ai4 : source_color = vec3(0.812, 0.878, 0.933);
uniform vec3 paper : source_color = vec3(0.953, 0.933, 0.886);
uniform vec3 sumi : source_color = vec3(0.110, 0.102, 0.118);
uniform vec3 beni : source_color = vec3(0.784, 0.220, 0.294);

uniform float fold_near = 24.0;
uniform float fold_far = 46.0;
uniform float fold_max = 1.5;
uniform float fold_on = 1.0;
// For stills from above (art QA): fold relative to a stand-in player.
uniform vec3 fold_center = vec3(0.0);
uniform float use_fold_center = 0.0;

varying flat float v_kind;
varying flat vec3 v_dim; // width, height, variation
varying float v_fold;

void vertex() {
	float kind = floor(INSTANCE_CUSTOM.r * 255.0 + 0.5);
	v_kind = kind;
	v_dim = vec3(INSTANCE_CUSTOM.g * 100.0, INSTANCE_CUSTOM.b * 100.0, INSTANCE_CUSTOM.a);
	vec3 o = MODEL_MATRIX[3].xyz;
	vec3 cp = use_fold_center > 0.5 ? fold_center : CAMERA_POSITION_WORLD;
	float d = length(o.xz - cp.xz);
	float foldable = kind < 99.5 ? 1.0 : 0.0;
	float k = smoothstep(fold_near, fold_far, d) * fold_on * foldable;
	v_fold = k;
	float a = -k * fold_max;
	float y = VERTEX.y;
	VERTEX.y = y * cos(a);
	VERTEX.z = VERTEX.z + y * sin(a);
}

// ---------- small print helpers (p in metres, x centred, y up) ----------
float h21(vec2 p) { p = fract(p * vec2(234.34, 435.345)); p += dot(p, p + 34.23); return fract(p.x * p.y); }
float vn(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), f.x), mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), f.x), f.y);
}
float rect(vec2 p, vec2 a, vec2 b) { return step(a.x, p.x) * step(p.x, b.x) * step(a.y, p.y) * step(p.y, b.y); }
float crect(vec2 p, float hw, float y0, float y1) { return rect(p, vec2(-hw, y0), vec2(hw, y1)); }
float ell(vec2 p, vec2 c, vec2 r) { vec2 q = (p - c) / r; return step(dot(q, q), 1.0); }
// Roof seen from the front: from y0 (half width hw0) to y1 (hw1); the eave
// line curls up towards the ends (Japanese eave).
float roof(vec2 p, float y0, float y1, float hw0, float hw1, float curl) {
	float t = clamp((p.y - y0) / max(y1 - y0, 0.001), 0.0, 1.0);
	float hw = mix(hw0, hw1, t);
	float yb = y0 + curl * pow(clamp(abs(p.x) / hw0, 0.0, 1.0), 4.0);
	return step(abs(p.x), hw) * step(yb, p.y) * step(p.y, y1);
}
vec4 lay(vec4 c, vec3 col, float m) { return mix(c, vec4(col, 1.0), clamp(m, 0.0, 1.0)); }
// Tiles: rows of rounded tiles printed in two blues.
vec3 tiles(vec2 p, vec3 base, vec3 line) {
	float row = step(0.82, fract(p.y / 0.22));
	float col = step(0.86, fract(p.x / 0.28 + 0.5 * floor(p.y / 0.22)));
	return mix(base, line, max(row, col * 0.7));
}
// Key-block roof: outline in ink, tiles inside.
vec4 key_roof(vec4 c, vec2 p, float y0, float y1, float hw0, float hw1, float curl, vec3 base, vec3 line) {
	float e = 0.07;
	c = lay(c, sumi, roof(p, y0 - e, y1 + e, hw0 + e, hw1 + e, curl));
	c = lay(c, tiles(p, base, line), roof(p, y0, y1, hw0, hw1, curl));
	return c;
}
vec4 key_rect(vec4 c, vec2 p, vec2 a, vec2 b, vec3 fill) {
	float e = 0.06;
	c = lay(c, sumi, rect(p, a - e, b + e));
	c = lay(c, fill, rect(p, a, b));
	return c;
}

// ---------- the cards ----------
vec4 machiya(vec2 p, float w, float h, float s, bool shop) {
	vec4 c = vec4(0.0);
	float hw = w * 0.5 - 0.3;
	float g1 = 2.6;
	float roof_h = 1.1;
	float top = h - roof_h;
	// body
	c = key_rect(c, p, vec2(-hw, 0.0), vec2(hw, top), paper);
	// ground floor: wood with koshi lattice
	c = lay(c, ai3, crect(p, hw, 0.0, g1));
	float slats = step(fract(p.x / 0.13), 0.42);
	c = lay(c, ai1, crect(p, hw, 0.15, g1 - 0.15) * slats);
	c = lay(c, ai1, crect(p, hw, g1 - 0.15, g1)); // lintel
	// door with noren
	float dx = (s - 0.5) * (hw - 1.0);
	c = lay(c, ai1, rect(p, vec2(dx - 0.75, 0.0), vec2(dx + 0.75, g1 - 0.15)));
	vec3 noren = shop ? (s > 0.55 ? beni : ai2) : ai1;
	float nmask = rect(p, vec2(dx - 0.7, 1.35), vec2(dx + 0.7, g1 - 0.2)) * step(0.06, abs(fract((p.x - dx + 0.7) / 0.467) - 0.5) * 2.0);
	c = lay(c, noren, nmask);
	// own mark on the curtain: an outlined lozenge (hishi), not a disc
	vec2 mq = abs(p - vec2(dx, 1.85));
	float lz = mq.x * 1.25 + mq.y;
	float mark = step(0.13, lz) * step(lz, 0.2);
	c = lay(c, paper, mark * nmask * step(0.35, s));
	if (!shop) {
		// inu-yarai: curved bamboo fence along the base, left and right of the door
		float fx = abs(p.x - dx);
		float fence = step(0.85, fx) * step(abs(p.x), hw) * step(p.y, 0.75 - 0.12 * pow(fx / max(hw, 0.1), 2.0));
		vec3 fc = mix(ai2, ai1, step(0.7, fract(p.x / 0.08)));
		c = lay(c, fc, fence);
		// paper lantern (chochin): ribs in blue, vermilion caps
		vec2 lc = vec2(dx + 1.05, 2.0);
		c = lay(c, sumi, ell(p, lc, vec2(0.24, 0.34)));
		c = lay(c, paper, ell(p, lc, vec2(0.2, 0.3)));
		c = lay(c, ai3, ell(p, lc, vec2(0.2, 0.3)) * step(0.75, fract((p.y - lc.y) / 0.075)));
		c = lay(c, beni, rect(p, lc + vec2(-0.13, 0.24), lc + vec2(0.13, 0.36)) + rect(p, lc + vec2(-0.13, -0.36), lc + vec2(0.13, -0.24)));
		c = lay(c, beni, step(abs(p.x - lc.x + 0.03 * sin(p.y * 30.0)), 0.035) * step(abs(p.y - lc.y), 0.15));
	}
	// first-floor eave
	c = key_roof(c, p, g1, g1 + 0.55, hw + 0.28, hw + 0.05, 0.08, ai2, ai1);
	// upper floor(s): plaster with mushiko-mado / lattice windows
	float y0 = g1 + 0.55;
	int floors = shop && h > 7.4 ? 2 : 1;
	float fh = (top - y0) / float(floors);
	for (int i = 0; i < floors; i++) {
		float fy = y0 + float(i) * fh;
		float wy0 = fy + fh * 0.25;
		float wy1 = fy + fh * 0.78;
		float ww = hw * 0.62;
		c = key_rect(c, p, vec2(-ww, wy0), vec2(ww, wy1), ai1);
		float bars = step(0.5, fract(p.x / (shop ? 0.3 : 0.17)));
		if (shop) {
			bars = max(bars, step(0.8, fract((p.y - wy0) / 0.32)));
		}
		c = lay(c, ai4, rect(p, vec2(-ww, wy0), vec2(ww, wy1)) * bars);
		if (i < floors - 1) {
			c = lay(c, ai1, crect(p, hw, fy + fh - 0.08, fy + fh + 0.08));
		}
	}
	// main roof
	c = key_roof(c, p, top, h - 0.05, hw + 0.3, hw - 0.15, 0.1, ai1, ai2);
	return c;
}

vec4 temple_wall(vec2 p, float w, float h) {
	vec4 c = vec4(0.0);
	float hw = w * 0.5 + 0.01;
	float stones = max(step(0.88, fract(p.y / 0.35)), step(0.93, fract(p.x / 0.62 + 0.5 * floor(p.y / 0.35))));
	c = lay(c, mix(ai3, ai2, stones), crect(p, hw, 0.0, 0.7));
	c = lay(c, paper, crect(p, hw, 0.7, h - 0.85));
	// the five lines (suji-bei) of Kyoto's temple walls
	for (int i = 0; i < 5; i++) {
		float ly = h - 1.35 - float(i) * 0.22;
		c = lay(c, ai1, crect(p, hw, ly - 0.035, ly + 0.035));
	}
	c = lay(c, sumi, crect(p, hw, h - 0.92, h - 0.85));
	c = lay(c, tiles(p, ai1, ai2), roof(p, h - 0.85, h, hw, hw, 0.0));
	return c;
}

vec4 pine(vec2 p, float w, float h, float s) {
	vec4 c = vec4(0.0);
	float bend = 0.35 * sin(p.y / h * 2.6 + s * 6.0);
	c = lay(c, sumi, step(abs(p.x - bend), 0.2) * step(p.y, h * 0.8));
	c = lay(c, ai1, step(abs(p.x - bend), 0.13) * step(p.y, h * 0.8));
	for (int i = 0; i < 3; i++) {
		float fi = float(i);
		vec2 ctr = vec2((fi - 1.0) * 0.18 * w * (s > 0.5 ? 1.0 : -1.0), h * (0.5 + 0.17 * fi));
		vec2 r = vec2(w * (0.46 - 0.11 * fi), h * 0.1);
		c = lay(c, sumi, ell(p, ctr, r + 0.07));
		vec3 needles = mix(ai2, ai1, step(0.7, fract((p.y - ctr.y) / 0.16)));
		c = lay(c, needles, ell(p, ctr, r));
		c = lay(c, ai3, ell(p, ctr + vec2(0.0, r.y * 0.45), r * vec2(0.8, 0.35)));
	}
	return c;
}

vec4 roofs(vec2 p, float w, float h, float s) {
	vec4 c = vec4(0.0);
	float hw = w * 0.5;
	c = lay(c, ai2, crect(p, hw - 0.3, 0.0, h - 2.2));
	c = lay(c, ai3, crect(p, hw - 0.4, 0.0, h - 2.3));
	c = lay(c, tiles(p, ai2, ai1), roof(p, h - 2.3, h - 0.25, hw, hw * (s > 0.5 ? 0.35 : 0.8), 0.15));
	c = lay(c, ai1, roof(p, h - 0.25, h, hw * (s > 0.5 ? 0.35 : 0.8), hw * (s > 0.5 ? 0.3 : 0.78), 0.0));
	return c;
}

vec4 theater(vec2 p, float w, float h) {
	vec4 c = vec4(0.0);
	float hw = 4.9;
	c = key_rect(c, p, vec2(-hw, 0.0), vec2(hw, 9.5), ai4);
	// ground floor: dark with three bright entrances
	c = lay(c, ai1, crect(p, hw, 0.0, 3.0));
	for (int i = -1; i <= 1; i++) {
		c = lay(c, ai4, rect(p, vec2(float(i) * 3.0 - 0.9, 0.0), vec2(float(i) * 3.0 + 0.9, 2.4)));
	}
	// lantern row
	for (int i = 0; i < 12; i++) {
		vec2 lc = vec2(-hw + 0.45 + float(i) * (2.0 * hw - 0.9) / 11.0, 3.35);
		c = lay(c, sumi, ell(p, lc, vec2(0.24, 0.3)));
		c = lay(c, beni, ell(p, lc, vec2(0.2, 0.26)));
		c = lay(c, paper, rect(p, lc - vec2(0.2, 0.04), lc + vec2(0.2, 0.04)));
	}
	// signboards (plain, no names): framed paper with ink strokes
	for (int i = 0; i < 8; i++) {
		float bx = -hw + 0.35 + float(i) * (2.0 * hw - 0.7) / 8.0;
		vec2 a = vec2(bx + 0.06, 4.0);
		vec2 b = vec2(bx + (2.0 * hw - 0.7) / 8.0 - 0.06, 6.6);
		c = key_rect(c, p, a, b, paper);
		float stroke = step(abs(p.x - (a.x + b.x) * 0.5 + 0.12 * sin(p.y * 5.0 + float(i))), 0.06) * rect(p, a + vec2(0.0, 0.3), b - vec2(0.0, 0.3));
		c = lay(c, ai1, stroke);
	}
	c = key_roof(c, p, 6.6, 7.2, hw + 0.4, hw + 0.1, 0.1, ai2, ai1);
	// karahafu: the curved gable over the centre
	float x = p.x / 2.7;
	float yb = 7.4 + 1.3 * (1.0 - x * x) + 0.35 * pow(abs(x), 6.0);
	float band = step(abs(x), 1.0) * step(yb, p.y) * step(p.y, yb + 0.55);
	c = lay(c, paper, step(abs(x), 0.95) * step(7.2, p.y) * step(p.y, yb));
	c = lay(c, sumi, step(abs(x), 1.03) * step(yb - 0.07, p.y) * step(p.y, yb + 0.62));
	c = lay(c, tiles(p, ai1, ai2), band);
	// upper roof and the drum tower (yagura) with a striped curtain
	c = key_roof(c, p, 9.5, 11.3, hw + 0.45, 3.6, 0.25, ai1, ai2);
	vec3 maku = mix(beni, paper, step(0.5, fract(p.x / 0.36)));
	c = key_rect(c, p, vec2(-0.95, 11.3), vec2(0.95, 12.6), maku);
	c = key_roof(c, p, 12.6, 13.0, 1.25, 0.9, 0.05, ai1, ai2);
	return c;
}

vec4 gate(vec2 p, float w, float h) {
	vec4 c = vec4(0.0);
	// stone stairs
	float st = step(0.8, fract(p.y / 0.2));
	c = lay(c, sumi, roof(p, -0.05, 1.65, 5.3, 4.7, 0.0));
	c = lay(c, mix(ai3, ai2, st), roof(p, 0.0, 1.6, 5.2, 4.6, 0.0));
	// lower storey: plaster panels, guardian niches, vermilion posts; the
	// centre passage is open (you look through the gate)
	float inner = step(1.6, p.y) * step(p.y, 6.0);
	c = lay(c, sumi, crect(p, 4.5, 1.55, 6.05) * step(1.6, abs(p.x)));
	c = lay(c, paper, crect(p, 4.4, 1.6, 6.0) * step(1.6, abs(p.x)));
	c = lay(c, ai1, rect(p, vec2(2.15, 2.4), vec2(3.6, 5.0)) + rect(p, vec2(-3.6, 2.4), vec2(-2.15, 5.0)));
	float lat = step(0.55, fract(p.x / 0.18)) * (rect(p, vec2(2.15, 2.4), vec2(3.6, 5.0)) + rect(p, vec2(-3.6, 2.4), vec2(-2.15, 5.0)));
	c = lay(c, ai3, lat);
	for (int i = 0; i < 4; i++) {
		float px = (i < 2 ? -1.0 : 1.0) * (i == 0 || i == 3 ? 4.15 : 1.55);
		c = lay(c, sumi, rect(p, vec2(px - 0.3, 1.6), vec2(px + 0.3, 6.0)));
		c = lay(c, beni, rect(p, vec2(px - 0.24, 1.6), vec2(px + 0.24, 6.0)));
	}
	c = lay(c, beni, crect(p, 4.6, 5.55, 6.0) * inner);
	c = lay(c, sumi, crect(p, 4.6, 5.5, 5.56));
	// middle roof
	c = key_roof(c, p, 6.0, 7.1, 5.5, 4.8, 0.35, ai1, ai2);
	// upper storey
	c = key_rect(c, p, vec2(-3.8, 7.1), vec2(3.8, 9.6), paper);
	c = lay(c, beni, crect(p, 3.8, 7.1, 7.55));
	c = lay(c, ai1, crect(p, 3.8, 7.1, 7.55) * step(0.6, fract(p.x / 0.3)));
	for (int i = 0; i < 4; i++) {
		float px = -3.55 + float(i) * 2.366;
		c = lay(c, beni, rect(p, vec2(px - 0.2, 7.55), vec2(px + 0.2, 9.6)));
	}
	c = lay(c, ai2, rect(p, vec2(-2.9, 7.9), vec2(-1.4, 9.2)) + rect(p, vec2(1.4, 7.9), vec2(2.9, 9.2)));
	c = lay(c, beni, crect(p, 3.8, 9.3, 9.6));
	// top roof + ridge with end ornaments
	c = key_roof(c, p, 9.6, 12.3, 5.4, 1.6, 0.55, ai1, ai2);
	c = lay(c, sumi, crect(p, 1.95, 12.25, 12.75));
	c = lay(c, sumi, ell(p, vec2(-1.95, 12.75), vec2(0.28, 0.38)) + ell(p, vec2(1.95, 12.75), vec2(0.28, 0.38)));
	return c;
}

vec4 pagoda(vec2 p, float w, float h) {
	vec4 c = vec4(0.0);
	float stones = max(step(0.85, fract(p.y / 0.33)), step(0.92, fract(p.x / 0.7)));
	c = lay(c, sumi, crect(p, 4.1, 0.0, 1.05));
	c = lay(c, mix(ai3, ai2, stones), crect(p, 4.0, 0.0, 1.0));
	float y = 1.0;
	for (int i = 0; i < 5; i++) {
		float s = 1.0 - 0.085 * float(i);
		float bh = 1.75 * s;
		float bw = 2.3 * s;
		// body: dark wood frame, paper panels, a door in the middle
		c = key_rect(c, p, vec2(-bw, y), vec2(bw, y + bh), ai2);
		c = lay(c, paper, rect(p, vec2(-bw + 0.25, y + 0.3), vec2(-0.55 * s, y + bh - 0.35)) + rect(p, vec2(0.55 * s, y + 0.3), vec2(bw - 0.25, y + bh - 0.35)));
		c = lay(c, ai1, rect(p, vec2(-0.45 * s, y + 0.15), vec2(0.45 * s, y + bh - 0.25)));
		// bracket band and eave
		c = lay(c, ai1, crect(p, bw + 0.35, y + bh - 0.05, y + bh + 0.3) * step(0.45, fract(p.x / 0.25)));
		float ry = y + bh + 0.25;
		float rh = 1.35 * s;
		c = key_roof(c, p, ry, ry + rh, 4.6 * s, 2.0 * s, 0.55 * s, ai1, ai2);
		y = ry + rh - 0.15;
	}
	// spire (sorin): rod, nine rings, flame top — printed in ink blue
	float top = h - 0.4;
	c = lay(c, sumi, crect(p, 0.16, y, top));
	c = lay(c, ai1, crect(p, 0.1, y, top));
	for (int i = 0; i < 9; i++) {
		float ry = y + 0.8 + float(i) * (top - y - 2.2) / 9.0;
		c = lay(c, ai1, crect(p, 0.42, ry, ry + 0.12));
	}
	c = lay(c, ai1, ell(p, vec2(0.0, top - 0.6), vec2(0.35, 0.55)));
	c = lay(c, ai3, ell(p, vec2(0.0, top - 0.6), vec2(0.18, 0.3)));
	return c;
}

vec4 kiyomizu(vec2 p, float w, float h, float s) {
	vec4 c = vec4(0.0);
	// the pillar framework under the stage (kakezukuri)
	c = lay(c, ai3, crect(p, 8.9, 0.0, 8.2));
	c = lay(c, ai4, crect(p, 8.9, 0.0, 8.2) * smoothstep(8.2, 1.0, p.y) * 0.5);
	float posts = step(abs(fract((p.x + 8.4) / 1.4 + 0.5) - 0.5) * 1.4, 0.17);
	float beams = step(abs(fract((p.y - 1.2) / 1.6 + 0.5) - 0.5) * 1.6, 0.09) * step(1.0, p.y);
	c = lay(c, ai1, crect(p, 8.9, 0.0, 8.2) * max(posts, beams));
	// stage deck and railing
	c = lay(c, sumi, crect(p, 9.1, 8.15, 8.85));
	c = lay(c, ai2, crect(p, 9.0, 8.2, 8.8) * (1.0 - step(0.85, fract(p.x / 0.4)) * 0.5));
	c = lay(c, ai1, crect(p, 9.0, 9.35, 9.5));
	c = lay(c, ai1, crect(p, 9.0, 8.8, 9.5) * step(0.85, fract(p.x / 0.9)));
	// hall: lattice shutters (shitomido)
	c = key_rect(c, p, vec2(-6.6, 8.8), vec2(6.6, 11.9), paper);
	float grid = max(step(0.82, fract(p.x / 0.32)), step(0.82, fract(p.y / 0.32)));
	c = lay(c, ai2, rect(p, vec2(-6.2, 9.6), vec2(6.2, 11.6)) * grid);
	for (int i = 0; i < 7; i++) {
		float px = -6.4 + float(i) * 2.133;
		c = lay(c, ai1, rect(p, vec2(px - 0.13, 8.8), vec2(px + 0.13, 11.9)));
	}
	// great hip roof of cypress bark: fine vertical striations
	float e = 0.08;
	c = lay(c, sumi, roof(p, 11.8 - e, 16.3 + e, 8.8 + e, 3.0 + e, 0.65));
	vec3 bark = mix(ai1, ai2, step(0.7, fract(p.x / 0.12)) * 0.6);
	c = lay(c, bark, roof(p, 11.8, 16.3, 8.8, 3.0, 0.65));
	c = lay(c, sumi, crect(p, 3.4, 16.2, 16.55));
	// maples on both sides: blue masses with vermilion leaves
	for (int i = 0; i < 6; i++) {
		float fi = float(i);
		float side = i < 3 ? -1.0 : 1.0;
		vec2 ctr = vec2(side * (7.5 + mod(fi, 3.0) * 0.9), 1.6 + mod(fi, 3.0) * 2.6);
		vec2 r = vec2(1.9, 1.5);
		c = lay(c, sumi, ell(p, ctr, r + 0.07));
		c = lay(c, ai2, ell(p, ctr, r));
		float leaf = step(0.72, vn(p * 3.1 + fi * 7.0)) * ell(p, ctr, r * 0.92);
		c = lay(c, beni, leaf);
	}
	return c;
}

vec4 temple_gate(vec2 p, float w, float h) {
	vec4 c = temple_wall(p, w, 3.9) * step(1.75, abs(p.x));
	c = key_rect(c, p, vec2(-1.75, 0.0), vec2(1.75, 4.6), ai1);
	c = lay(c, ai2, rect(p, vec2(-1.35, 0.0), vec2(-0.03, 4.1)) + rect(p, vec2(0.03, 0.0), vec2(1.35, 4.1)));
	float studs = step(length(fract(p / vec2(0.45, 0.5)) - 0.5), 0.13) * crect(p, 1.3, 0.2, 4.0);
	c = lay(c, ai4, studs);
	c = key_roof(c, p, 4.6, 7.6, 3.1, 0.9, 0.45, ai1, ai2);
	c = lay(c, sumi, crect(p, 1.15, 7.55, 7.95));
	return c;
}

vec4 shrine(vec2 p, float w, float h) {
	vec4 c = vec4(0.0);
	c = lay(c, sumi, crect(p, 2.75, 0.0, 0.65));
	c = lay(c, ai3, crect(p, 2.7, 0.0, 0.6));
	c = key_rect(c, p, vec2(-2.4, 0.6), vec2(2.4, 4.0), paper);
	c = lay(c, ai3, rect(p, vec2(-2.0, 1.2), vec2(2.0, 3.3)) * step(0.5, fract(p.x / 0.2)));
	for (int i = 0; i < 4; i++) {
		float px = -2.2 + float(i) * 1.466;
		c = lay(c, beni, rect(p, vec2(px - 0.17, 0.6), vec2(px + 0.17, 4.0)));
	}
	c = lay(c, beni, crect(p, 2.4, 3.6, 4.0));
	// rope with paper streamers
	c = lay(c, paper, crect(p, 2.2, 3.35, 3.55));
	c = lay(c, paper, step(abs(fract(p.x / 1.1) - 0.5), 0.08) * crect(p, 2.0, 2.75, 3.35));
	c = lay(c, ai1, crect(p, 0.8, 0.6, 1.3));
	c = key_roof(c, p, 4.0, 6.5, 3.2, 1.0, 0.3, ai1, ai2);
	// crossed rafter ends (chigi) on the ridge
	vec2 q = p - vec2(0.0, 6.5);
	float chigi = (step(abs(q.x - q.y * 0.7), 0.1) + step(abs(q.x + q.y * 0.7), 0.1)) * step(0.0, q.y) * step(q.y, 1.0) * step(abs(q.x), 1.1);
	c = lay(c, sumi, chigi);
	return c;
}

vec4 torii(vec2 p, float w, float h) {
	vec4 c = vec4(0.0);
	for (int i = 0; i < 2; i++) {
		float px = i == 0 ? -2.85 : 2.85;
		c = lay(c, sumi, rect(p, vec2(px - 0.22, 0.0), vec2(px + 0.22, 4.4)));
		c = lay(c, beni, rect(p, vec2(px - 0.17, 0.45), vec2(px + 0.17, 4.4)));
	}
	c = lay(c, sumi, rect(p, vec2(-3.15, 3.5), vec2(3.15, 3.9)));
	c = lay(c, beni, rect(p, vec2(-3.1, 3.55), vec2(3.1, 3.85)));
	c = lay(c, beni, crect(p, 0.13, 3.85, 4.35));
	c = lay(c, sumi, crect(p, 3.05, 4.3, 4.5));
	c = lay(c, beni, crect(p, 3.0, 4.33, 4.47));
	float x = clamp(abs(p.x) / 3.35, 0.0, 1.0);
	float kb = 4.5 + 0.22 * pow(x, 3.0);
	float kt = 4.86 + 0.32 * pow(x, 3.0);
	c = lay(c, sumi, step(abs(p.x), 3.35) * step(kb, p.y) * step(p.y, kt));
	return c;
}

vec4 tower(vec2 p, float w, float h) {
	vec4 c = vec4(0.0);
	vec3 line = ai2;
	// base building with window bands
	c = lay(c, line, crect(p, 5.1, 0.0, 14.1));
	c = lay(c, mix(paper, ai3, step(0.6, fract(p.y / 1.4))), crect(p, 5.0, 0.0, 14.0));
	// shaft, deck, needle
	float t = clamp((p.y - 14.0) / 36.0, 0.0, 1.0);
	float hw = mix(1.35, 0.95, t);
	c = lay(c, line, step(abs(p.x), hw + 0.08) * step(14.0, p.y) * step(p.y, 50.0));
	c = lay(c, paper, step(abs(p.x), hw) * step(14.0, p.y) * step(p.y, 50.0));
	c = lay(c, line, ell(p, vec2(0.0, 52.5), vec2(2.25, 2.8)));
	c = lay(c, paper, ell(p, vec2(0.0, 52.5), vec2(2.15, 2.7)));
	c = lay(c, ai3, crect(p, 2.1, 52.0, 53.2));
	float t2 = clamp((p.y - 55.0) / 9.0, 0.0, 1.0);
	float hw2 = mix(0.75, 0.3, t2);
	c = lay(c, paper, step(abs(p.x), hw2) * step(55.0, p.y) * step(p.y, 64.0));
	c = lay(c, beni, step(abs(p.x), hw2) * (step(56.2, p.y) * step(p.y, 57.4) + step(59.8, p.y) * step(p.y, 61.0)));
	c = lay(c, line, crect(p, 0.1, 64.0, h - 0.2));
	return c;
}

vec4 mountains(vec2 p, float w, float h, float s) {
	float far = step(0.5, s);
	float ridge = h * (0.55 + 0.22 * sin(p.x * 0.031 + s * 9.0) + 0.1 * sin(p.x * 0.093 + 1.3 + s * 4.0) + 0.05 * vn(vec2(p.x * 0.25, s * 10.0)));
	float m = step(p.y, ridge);
	vec3 top = mix(ai2, ai3, far);
	vec3 bottom = mix(ai3, ai4, far);
	vec3 col = mix(bottom, top, smoothstep(ridge - 9.0, ridge, p.y));
	// tree texture: little ink dots near the ridge
	float dots = step(0.86, vn(p * 1.6)) * smoothstep(ridge - 6.0, ridge - 1.0, p.y) * (1.0 - far);
	col = mix(col, ai1, dots * 0.8);
	col = mix(col, mix(ai1, ai2, far), step(ridge - 0.12, p.y));
	return vec4(col, m);
}

vec4 mist(vec2 p, float w, float h) {
	float r = h * 0.5;
	vec2 q = vec2(max(abs(p.x) - (w * 0.5 - r), 0.0), p.y - r);
	float d = length(q);
	float m = step(d, r);
	vec3 col = mix(ai4, paper, smoothstep(0.0, h, p.y));
	col = mix(col, ai3, step(r - 0.12, d));
	return vec4(col, m);
}

vec4 figure(vec2 p, float w, float h, float s) {
	vec4 c = vec4(0.0);
	bool maiko = s > 0.5;
	float t = clamp(p.y / 1.35, 0.0, 1.0);
	float rw = mix(maiko ? 0.42 : 0.36, 0.19, t);
	float robe = step(abs(p.x), rw) * step(p.y, 1.35);
	c = lay(c, sumi, step(abs(p.x), rw + 0.05) * step(p.y, 1.39));
	if (maiko) {
		vec3 kimono = mix(beni, paper, step(0.8, vn(p * 9.0)) * 0.8);
		c = lay(c, kimono, robe);
		c = lay(c, ai1, robe * step(0.78, p.y) * step(p.y, 0.98));
		c = lay(c, ai1, rect(p, vec2(rw * 0.6, 0.15), vec2(rw * 0.6 + 0.12, 0.9))); // dangling obi
		c = lay(c, sumi, ell(p, vec2(0.0, 1.47), vec2(0.15, 0.15)));
		c = lay(c, paper, ell(p, vec2(0.0, 1.47), vec2(0.12, 0.12)));
		c = lay(c, sumi, ell(p, vec2(0.0, 1.6), vec2(0.19, 0.14)));
		c = lay(c, beni, ell(p, vec2(0.13, 1.62), vec2(0.05, 0.05)));
	} else {
		c = lay(c, ai1, robe);
		c = lay(c, ai3, robe * step(0.92, fract(p.x / 0.2)));
		c = lay(c, sumi, ell(p, vec2(0.0, 1.47), vec2(0.15, 0.15)));
		c = lay(c, paper, ell(p, vec2(0.0, 1.47), vec2(0.12, 0.12)));
		// umbrella (wagasa)
		c = lay(c, sumi, crect(p, 0.03, 1.3, 1.95));
		float dome = step(1.62, p.y) * step(p.y, 1.62 + 0.38 * sqrt(max(0.0, 1.0 - pow(p.x / 0.68, 2.0))));
		c = lay(c, sumi, dome * step(abs(p.x), 0.7));
		float dome_in = step(1.66, p.y) * step(p.y, 1.62 + 0.34 * sqrt(max(0.0, 1.0 - pow(p.x / 0.62, 2.0))));
		vec3 ribs = mix(ai2, ai3, step(0.85, fract(atan(p.x, p.y - 1.62) * 4.0)));
		c = lay(c, ribs, dome_in * step(abs(p.x), 0.62));
	}
	return c;
}

void fragment() {
	float kind = v_kind > 99.5 ? v_kind - 100.0 : v_kind;
	float w = v_dim.x;
	float h = v_dim.y;
	float s = v_dim.z;
	vec2 p = vec2((UV.x - 0.5) * w, (1.0 - UV.y) * h);
	vec4 c;
	if (kind < 0.5) c = machiya(p, w, h, s, false);
	else if (kind < 1.5) c = machiya(p, w, h, s, true);
	else if (kind < 2.5) c = temple_wall(p, w, h);
	else if (kind < 3.5) c = pine(p, w, h, s);
	else if (kind < 4.5) c = roofs(p, w, h, s);
	else if (kind < 10.5) c = theater(p, w, h);
	else if (kind < 11.5) c = gate(p, w, h);
	else if (kind < 12.5) c = pagoda(p, w, h);
	else if (kind < 13.5) c = kiyomizu(p, w, h, s);
	else if (kind < 14.5) c = temple_gate(p, w, h);
	else if (kind < 15.5) c = shrine(p, w, h);
	else if (kind < 16.5) c = torii(p, w, h);
	else if (kind < 17.5) c = tower(p, w, h);
	else if (kind < 18.5) c = mountains(p, w, h, s);
	else if (kind < 19.5) c = mist(p, w, h);
	else c = figure(p, w, h, s);
	if (c.a < 0.5) {
		discard;
	}
	// washi grain, and the back of the card is unprinted paper
	vec3 col = c.rgb * (0.975 + 0.035 * vn(p * vec2(9.0, 2.5)));
	if (!FRONT_FACING) {
		col = mix(paper, c.rgb, 0.1) * 0.93;
	}
	col *= mix(1.0, 0.95, v_fold); // lying cards a touch darker (page shadow)
	ALBEDO = col;
}
