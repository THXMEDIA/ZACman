# Gemeinsame Bausteine fuer "fotorealistische Wellpappe" (Richtungen I-K, Art Director,
# Nachtrag 04.10.2026). NICHT Spielcode. Texturen kommen aus tools/pappe_pbr.py (prozedural,
# keine Scans) und liegen im Prototyp unter res://prints/.
#
# Prinzip: Ein Karton ist eine skalierte Einheits-Box in einer MultiMesh. Der Shader rechnet die
# Flaechenkoordinaten in Metern aus der Skalierung zurueck und malt daraus alles, was einen echten
# Umzugskarton ausmacht: Kraftliner (Albedo/Normal/Rauheit), Wellen-Abzeichnung, gerundete und
# abgestossene Kanten, leichte Woelbung der Flaechen, Laschenfuge oben, Klebeband mit Glanz und
# Falten, Herstellerlasche, Griffloecher mit sichtbarer Welle in der Schnittkante, Druck/Marker.
# Pro Karton: INSTANCE_CUSTOM = (seed, klebeband 0/1, druck-index/16 (0 = keiner), helligkeit).
extends RefCounted
class_name Pappe

static var tex := {}

static func load_textures() -> void:
	if tex.size() > 0:
		return
	for n in ["liner_albedo", "liner_normal", "liner_rough", "crumple_albedo", "crumple_normal", "tape_normal", "prints"]:
		var img := Image.load_from_file(ProjectSettings.globalize_path("res://prints/%s.png" % n))
		img.generate_mipmaps()
		tex[n] = ImageTexture.create_from_image(img)

const COMMON := """
uniform sampler2D alb_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D nrm_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rgh_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tape_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D prn_tex : hint_default_black, filter_linear_mipmap, repeat_disable;
uniform float tile_m = 0.512;
uniform vec3 tint : source_color = vec3(1.0);
uniform float far_flat = 30.0;   // ab hier Normalen ausblenden (Moire-Schutz)
float h11(float p){ return fract(sin(p * 127.1) * 43758.5453); }
float h21(vec2 p){ p = fract(p * vec2(234.34, 435.345)); p += dot(p, p + 34.23); return fract(p.x * p.y); }
float vn(vec2 p){ vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1, 0)), f.x), mix(h21(i + vec2(0, 1)), h21(i + vec2(1, 1)), f.x), f.y); }
"""

# ---------------------------------------------------------------- Karton
const BOX_SHADER := """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
#COMMON
uniform float tape_prob = 1.0;
uniform float hole_prob = 0.35;
uniform vec3 tape_col : source_color = vec3(0.93, 0.80, 0.62);
uniform vec3 ink_col : source_color = vec3(0.05, 0.045, 0.04);
uniform float paint = 0.0;                 // >0: Karton ist gestrichen (Ausgang)
uniform vec3 paint_col : source_color = vec3(0.1, 0.6, 0.25);
uniform float paint_emit = 0.0;
uniform float edge_ao = 0.55;
uniform float bulge = 0.009;
uniform float panel = 0.0;          // 1: Platte (Modellbau) – duennste Achse = Pappstaerke, Kanten zeigen die Welle
uniform float edge_pitch = 0.008;   // Wellenteilung an Schnittkanten (Weltmass)
uniform float rib_pitch = 0.0;      // >0: Waschbrett-Abzeichnung der Welle auf den Flaechen (Weltmass)
uniform float rib_amp = 0.12;
varying vec3 lp; varying vec3 ln; varying vec3 bs; varying vec4 cu; varying float vdist;
void vertex(){
	bs = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	cu = INSTANCE_CUSTOM;
	// Karton ist nie exakt: Flaechen bauchen aus (Deckel sacken eher ein), Kanten bleiben
	vec3 t = VERTEX * 2.0; vec3 a = abs(NORMAL);
	float f = (a.y > 0.5) ? (1.0 - t.x * t.x) * (1.0 - t.z * t.z) : ((a.x > 0.5) ? (1.0 - t.y * t.y) * (1.0 - t.z * t.z) : (1.0 - t.x * t.x) * (1.0 - t.y * t.y));
	float hs_ = fract(sin(cu.x * 91.7 * 12.9898) * 43758.5453);
	float amt = bulge * (0.3 + hs_) * min(1.0, min(bs.x, min(bs.y, bs.z)) * 2.5);
	if (NORMAL.y > 0.5 && hs_ > 0.55) amt = -amt * 1.4;
	VERTEX += NORMAL * amt * f / bs;
	lp = VERTEX * bs; ln = NORMAL;
	vdist = length((MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz - CAMERA_POSITION_WORLD);
}
void fragment(){
	float seed = cu.x * 91.7 + 0.37;
	vec3 an = abs(ln);
	vec2 q; vec2 hs; vec3 au; vec3 av; int face;
	if (an.y > 0.5) { q = vec2(lp.x, lp.z * sign(ln.y)); hs = bs.xz * 0.5; au = vec3(1, 0, 0); av = vec3(0, 0, sign(ln.y)); face = 1; }
	else if (an.x > 0.5) { q = vec2(-lp.z * sign(ln.x), lp.y); hs = bs.zy * 0.5; au = vec3(0, 0, -sign(ln.x)); av = vec3(0, 1, 0); face = 0; }
	else { q = vec2(lp.x * sign(ln.z), lp.y); hs = bs.xy * 0.5; au = vec3(sign(ln.z), 0, 0); av = vec3(0, 1, 0); face = 2; }
	bool top = (face == 1 && ln.y > 0.0);
	bool edge_done = false;
	// Platten-Modus: Schnittkanten (Flaechen, die die Dicke-Achse enthalten) zeigen Liner-Welle-Liner
	if (panel > 0.5) {
		vec3 thin = (bs.x <= bs.y && bs.x <= bs.z) ? vec3(1, 0, 0) : ((bs.y <= bs.z) ? vec3(0, 1, 0) : vec3(0, 0, 1));
		if (abs(dot(ln, thin)) < 0.5) {
			bool tu = abs(dot(au, thin)) > 0.5;
			float tv = (tu ? q.x / hs.x : q.y / hs.y) * 0.5 + 0.5;
			float L = tu ? q.y : q.x;
			float lin = 0.10;
			float w = 0.5 + (0.5 - lin - 0.07) * sin(L * 6.2831 / edge_pitch);
			float dd = abs(tv - w);
			float flute = 1.0 - smoothstep(0.035, 0.065, dd);
			float inl = step(tv, lin) + step(1.0 - lin, tv);
			float paper = clamp(flute + inl, 0.0, 1.0);
			vec3 k = texture(alb_tex, vec2(L, tv * 0.05) / tile_m).rgb * tint * mix(0.86, 1.08, cu.w);
			float occ = smoothstep(0.0, 0.32, dd);
			vec3 col = mix(k * 0.10 * (1.7 - occ), k * vec3(1.10, 1.07, 1.02) * (0.9 + 0.15 * vn(vec2(L * 180.0 / edge_pitch, tv * 5.0))), paper);
			float slope = cos(L * 6.2831 / edge_pitch) * (1.0 - inl) * paper;
			vec3 wn0 = normalize(mat3(MODEL_MATRIX) * ((ln - (tu ? av : au) * slope * 0.6) / bs * min(bs.x, min(bs.y, bs.z))));
			NORMAL = normalize((VIEW_MATRIX * vec4(wn0, 0.0)).xyz);
			ALBEDO = col;
			ROUGHNESS = 0.93;
			AO = mix(0.5, 1.0, paper);
			AO_LIGHT_AFFECT = 0.6 * (1.0 - paper);
			edge_done = true;
		}
	}
	if (!edge_done) {
	// Wellenrichtung: auf Seiten senkrecht, oben quer zur Fuge
	vec2 uv = vec2(q.x, -q.y) / tile_m + vec2(h11(seed + float(face)), h11(seed * 1.7 + float(face)));
	vec3 c = texture(alb_tex, uv).rgb;
	vec3 nm = texture(nrm_tex, uv).rgb * 2.0 - 1.0;
	float r = texture(rgh_tex, uv).r;
	float ink = 0.0;
	// Helligkeit/Farbton je Karton (Charge, Alter, Feuchte)
	float bri = mix(0.80, 1.10, cu.w);
	if (rib_pitch > 0.0) {
		float rb = sin(q.x * 6.2831 / rib_pitch);
		c *= 1.0 - 0.035 * rb;
		nm.x += cos(q.x * 6.2831 / rib_pitch) * rib_amp;
	}
	c *= tint * bri * vec3(1.0 + 0.04 * (h11(seed * 3.1) - 0.5), 1.0, 1.0 - 0.06 * (h11(seed * 5.3) - 0.5));
	// Woelbung (Karton baucht aus) -> Glanzverlauf
	vec2 nrmq = q / max(hs, vec2(0.01));
	vec2 tilt = nrmq * 0.035 * (0.6 + h11(seed * 2.3));
	// Kanten: Radius ~5 mm, abgestossen, aufgehellt (gebrochene Fasern), dunkle Fuge daneben
	vec2 ed = hs - abs(q);
	float e = min(ed.x, ed.y);
	float bev = 0.005;
	vec2 bv = vec2(1.0 - smoothstep(0.0, bev, ed.x), 1.0 - smoothstep(0.0, bev, ed.y)) * sign(q);
	tilt += bv * 0.9;
	float wear = (1.0 - smoothstep(0.0, 0.004 + 0.006 * vn(q * 40.0 + seed), e)) * (0.5 + 0.5 * vn(q * 25.0 + seed));
	c = mix(c, c * vec3(1.16, 1.14, 1.10) + 0.03, wear * 0.8);
	r = mix(r, 0.95, wear);
	float ao = mix(edge_ao, 1.0, smoothstep(0.0, 0.03, e));
	if (face != 1) ao *= mix(0.78, 1.0, smoothstep(-hs.y, -hs.y + 0.12, q.y));
	// Herstellerlasche (geklebte Naht) an einer senkrechten Kante
	if (face != 1 && h11(seed * 7.7 + float(face)) < 0.25) {
		float jx = hs.x - 0.035 - q.x;
		float step_line = 1.0 - smoothstep(0.0, 0.0012, abs(jx));
		c *= 1.0 - 0.45 * step_line;
		if (jx < 0.0) { c *= 0.94; tilt.x += 0.05; }
	}
	// Laschenfuge oben (Klappen treffen sich in der Mitte, Fuge laeuft entlang der laengeren Seite)
	bool seam_x = (face == 1) ? (h11(seed * 1.3) < 0.5) : true;
	if (face != 1) seam_x = h11(seed * 1.3) < 0.5;
	float qs = seam_x ? q.y : q.x;
	float ql = seam_x ? q.x : q.y;
	if (face == 1) {
		float gap = 0.0015 + 0.002 * vn(vec2(ql * 6.0, seed));
		float slit = 1.0 - smoothstep(gap, gap + 0.0012, abs(qs));
		c = mix(c, c * 0.08, slit); ao *= 1.0 - 0.5 * slit;
		float lip = 1.0 - smoothstep(0.0, 0.005, abs(abs(qs) - gap));
		if (seam_x) tilt.y -= sign(qs) * lip * 0.6; else tilt.x -= sign(qs) * lip * 0.6;
	}
	// Klebeband: ueber der Fuge und 5-7 cm die Stirnseiten hinunter
	float tape = 0.0; vec2 tq = vec2(0.0);
	if (cu.y > 0.5) {
		float tw = 0.024;
		if (face == 1) {
			float torn = 0.003 * vn(vec2(ql * 90.0, seed));
			tape = (1.0 - smoothstep(tw - 0.0008, tw, abs(qs) + torn));
			tq = seam_x ? vec2(q.x, q.y) : vec2(q.y, q.x);
		} else {
			bool end_face = seam_x ? (face == 0) : (face == 2);
			if (end_face) {
				float len = 0.05 + 0.03 * h11(seed + float(face) * 3.0);
				float torn = 0.006 * vn(vec2(q.x * 120.0, seed));
				tape = (1.0 - smoothstep(tw - 0.0008, tw, abs(q.x))) * step(hs.y - len - torn, q.y);
				tq = vec2(q.y, q.x);
			}
		}
	}
	// Griffloch (Ovale auf den Stirnseiten) mit sichtbarer Welle in der Schnittkante
	float hole = 0.0; float rim = 0.0;
	if (face == 0 && h11(seed * 9.1) < hole_prob && hs.y > 0.14) {
		vec2 hc = vec2(0.0, hs.y - 0.085);
		vec2 d = (q - hc) / vec2(0.06, 0.017);
		float rr = length(d);
		hole = 1.0 - smoothstep(0.96, 1.0, rr);
		rim = smoothstep(0.96, 1.0, rr) * (1.0 - smoothstep(1.0, 1.22, rr));
	}
	// Druck / Marker
	float pi = floor(cu.z * 16.0 + 0.5);
	if (pi > 0.5 && face != 1) {
		bool pf = (h11(seed * 4.4) < 0.5) ? (face == 2 && ln.z > 0.0) : (face == 2 && ln.z < 0.0) || (face == 0 && ln.x > 0.0);
		if (pf) {
			float ps = clamp(min(hs.x, hs.y) * 1.25, 0.12, 0.34);
			vec2 pc = vec2((h11(seed * 6.6) - 0.5) * max(hs.x - ps * 0.5, 0.0), (h11(seed * 8.2) - 0.3) * max(hs.y - ps * 0.5, 0.0));
			float ang = (h11(seed * 2.9) - 0.5) * 0.25;
			vec2 pq = q - pc; pq = mat2(vec2(cos(ang), sin(ang)), vec2(-sin(ang), cos(ang))) * pq;
			vec2 puv = pq / ps + 0.5;
			if (puv.x > 0.0 && puv.x < 1.0 && puv.y > 0.0 && puv.y < 1.0) {
				float cell = pi - 1.0;
				vec2 cuv = (vec2(mod(cell, 4.0), floor(cell / 4.0)) + vec2(puv.x, 1.0 - puv.y)) / 4.0;
				ink = texture(prn_tex, cuv).r * (0.80 + 0.15 * vn(q * 12.0));
			}
		}
	}
	c = mix(c, ink_col, ink);
	r = mix(r, 0.62, ink);
	if (paint > 0.0) {
		float brush = vn(q * vec2(4.0, 22.0) + seed) * 0.6 + vn(q * vec2(18.0, 70.0)) * 0.4;
		float m = smoothstep(0.08, 0.2, brush + paint - 0.6);
		c = mix(c, paint_col * (0.9 + 0.12 * brush) * (0.95 + 0.1 * texture(alb_tex, uv).g), m);
		r = mix(r, 0.5, m);
		EMISSION = paint_col * paint_emit * m;
	}
	float spec = 0.4;
	vec3 nfin = nm;
	if (tape > 0.0) {
		vec3 tn = texture(tape_tex, tq * vec2(1.6, 6.0)).rgb * 2.0 - 1.0;
		vec3 under = c;
		c = mix(c, under * tape_col * 1.04 + vec3(0.015, 0.01, 0.0), tape * 0.7);
		float lift = 1.0 - smoothstep(0.0, 0.002, abs(abs(seam_x ? q.y : q.x) - 0.023));
		r = mix(r, 0.16 + 0.12 * vn(tq * 30.0), tape);
		spec = mix(spec, 0.75, tape);
		nfin = mix(nm, normalize(vec3(tn.xy * 0.8, 1.0)), tape);
	}
	if (hole > 0.0) { c = mix(c, vec3(0.012, 0.008, 0.005), hole); r = mix(r, 1.0, hole); nfin = mix(nfin, vec3(0, 0, 1), hole); ao *= 1.0 - 0.6 * hole; }
	if (rim > 0.0) {
		float fl = 0.5 + 0.5 * sin(atan(q.y - (hs.y - 0.085), q.x) * 22.0);
		c = mix(c, mix(c * 0.35, c * 1.12, fl), rim);
	}
	float far = 1.0 - smoothstep(far_flat * 0.5, far_flat, vdist);
	vec3 ln2 = normalize(ln + au * (nfin.x * far + tilt.x * 0.25) + av * (nfin.y * far + tilt.y * 0.25));
	vec3 wn = normalize(mat3(MODEL_MATRIX) * (ln2 / bs * min(bs.x, min(bs.y, bs.z))));
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
	ALBEDO = c;
	ROUGHNESS = r;
	SPECULAR = spec;
	AO = ao;
	AO_LIGHT_AFFECT = 0.25;
	}
}
"""

# ---------------------------------------------------------------- Bodenplatten (Pappe in Bahnen)
const FLOOR_SHADER := """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
#COMMON
uniform vec2 sheet = vec2(1.2, 2.4);
uniform float seam_dark = 0.5;
uniform float tape_seams = 0.3;
uniform vec3 tape_col : source_color = vec3(0.80, 0.58, 0.30);
uniform float scuff = 1.0;
uniform float lane_half = 0.0;   // >0: Strasse entlang z mit Waenden bei |x| = lane_half
varying vec3 wp; varying float vdist;
void vertex(){ wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; vdist = length(wp - CAMERA_POSITION_WORLD); }
void fragment(){
	vec2 p = wp.xz;
	vec2 cell = floor(p / sheet);
	vec2 f = p / sheet - cell;
	float s = h21(cell + 3.1);
	bool rot = s > 0.5;
	vec2 uv = (rot ? p.yx : p) / tile_m + vec2(h21(cell), h21(cell + 7.0));
	vec3 c = texture(alb_tex, uv).rgb * tint * mix(0.9, 1.06, h21(cell + 11.0));
	vec3 nm = texture(nrm_tex, uv).rgb * 2.0 - 1.0;
	if (rot) nm.xy = nm.yx;
	float r = texture(rgh_tex, uv).r;
	vec2 dE = min(f, 1.0 - f) * sheet;
	float e = min(dE.x, dE.y);
	float seam = 1.0 - smoothstep(0.0008, 0.0025, e);
	c *= 1.0 - seam_dark * seam;
	// Klebebandstreifen auf manchen Stossfugen
	float tp = 0.0;
	if (h21(cell + 21.0) < tape_seams) {
		tp = 1.0 - smoothstep(0.022, 0.024, dE.x);
	}
	c = mix(c, c * tape_col * 1.05, tp * 0.85);
	r = mix(r, 0.18, tp);
	// Laufspuren / Abrieb: grosse, weiche Flecken, glaenzender und dunkler
	float sc = vn(p * 0.6) * 0.6 + vn(p * 2.3) * 0.4;
	float scm = smoothstep(0.55, 0.85, sc) * scuff;
	c *= 1.0 - 0.10 * scm;
	r = mix(r, 0.55, scm * 0.6);
	if (lane_half > 0.0) { float dw = lane_half - abs(wp.x); if (dw > -0.05) c *= mix(0.55, 1.0, smoothstep(0.0, 0.45, dw)); }
	float far = 1.0 - smoothstep(far_flat * 0.5, far_flat, vdist);
	NORMAL_MAP = vec3(nm.xy * far, 1.0) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 1.0;
	ALBEDO = c;
	ROUGHNESS = r;
	SPECULAR = mix(0.35, 0.7, tp);
}
"""

# ---------------------------------------------------------------- Packpapier (zerknittert, transluzent)
# Auf einer unterteilten PlaneMesh (lokal XZ, Normale +Y; im Knoten aufgerichtet). Grosse Falten im
# Vertex-Shader (Vorhangwellen + Knitter), Feinknitter per Normalmap, Licht von hinten scheint durch.
const PAPER_SHADER := """
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;
uniform sampler2D alb_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D nrm_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 tint : source_color = vec3(1.0);
uniform vec2 size = vec2(1.6, 2.0);
uniform float folds = 9.0;          // Anzahl Vorhangfalten
uniform float fold_depth = 0.07;
uniform float crumple = 0.05;
uniform float seed = 0.0;
uniform float translucency = 0.85;
uniform vec3 glow : source_color = vec3(0.0);   // Eigenleuchten (Lampe direkt dahinter, nur bei Schirmen)
uniform float tile_m = 0.6;
float h21(vec2 p){ p = fract(p * vec2(234.34, 435.345)); p += dot(p, p + 34.23); return fract(p.x * p.y); }
float vn(vec2 p){ vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1, 0)), f.x), mix(h21(i + vec2(0, 1)), h21(i + vec2(1, 1)), f.x), f.y); }
float ridge(float v){ return 1.0 - abs(v * 2.0 - 1.0); }
float disp(vec2 p){
	float x = p.x / size.x;
	float wave = sin(x * folds * 6.2831 + vn(vec2(p.x * 1.3, p.y * 0.5) + seed) * 5.0) * (0.45 + 0.6 * vn(vec2(p.x * 3.0, seed)))
		+ 0.35 * sin(x * folds * 2.7 * 6.2831 + vn(vec2(p.x * 4.0, p.y * 1.5) + seed * 1.3) * 4.0);
	float bunch = 0.6 + 0.4 * smoothstep(0.0, 1.0, p.y / size.y);
	float cr = 0.6 * ridge(vn(p * 3.5 + seed)) + 0.3 * ridge(vn(p * 9.0 + seed * 2.0)) + 0.18 * ridge(vn(p * 23.0 + seed * 3.0));
	return wave * fold_depth * bunch + (cr - 0.55) * crumple * 1.8;
}
varying vec2 pp;
void vertex(){
	pp = VERTEX.xz + size * 0.5;
	float d0 = disp(pp);
	float e = 0.02;
	float dx = (disp(pp + vec2(e, 0.0)) - d0) / e;
	float dz = (disp(pp + vec2(0.0, e)) - d0) / e;
	VERTEX.y += d0;
	NORMAL = normalize(vec3(-dx, 1.0, -dz));
}
void fragment(){
	vec2 uv = pp / tile_m + seed;
	vec3 c = texture(alb_tex, uv).rgb * tint;
	vec3 nm = texture(nrm_tex, uv).rgb;
	NORMAL_MAP = nm;
	NORMAL_MAP_DEPTH = 2.2;
	ALBEDO = c;
	ROUGHNESS = 0.72;
	SPECULAR = 0.35;
	BACKLIGHT = c * translucency * (0.75 + 0.5 * texture(alb_tex, uv * 1.7).r);
	float thin = pow(clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 0.8);
	EMISSION = glow * c * (0.55 + 0.6 * thin) * (0.8 + 0.4 * texture(alb_tex, uv * 0.7).r);
}
"""

# ---------------------------------------------------------------- Papprolle (Huelse mit Wickelnaht)
const TUBE_SHADER := """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
#COMMON
uniform float radius = 0.1;
uniform float pitch = 0.09;
varying vec3 lp; varying vec3 ln; varying float sy;
void vertex(){ sy = length(MODEL_MATRIX[1].xyz); lp = VERTEX * vec3(length(MODEL_MATRIX[0].xyz), sy, length(MODEL_MATRIX[2].xyz)); ln = NORMAL; }
void fragment(){
	float a = atan(lp.z, lp.x);
	float circ = radius * 6.2831;
	vec2 q = vec2(a / 6.2831 * circ, lp.y);
	vec3 c = texture(alb_tex, q / tile_m).rgb * tint;
	vec3 nm = texture(nrm_tex, q / tile_m).rgb;
	// spiralfoermige Wickelnaht
	float sp = fract((q.y + q.x * 0.35) / pitch);
	float seam = 1.0 - smoothstep(0.0, 0.004 / pitch, min(sp, 1.0 - sp));
	c *= 1.0 - 0.35 * seam;
	if (abs(ln.y) > 0.5) {
		// Stirnseite: konzentrische Papierlagen
		float rr = length(lp.xz);
		float wall = smoothstep(radius - 0.012, radius - 0.011, rr);
		float rings = 0.5 + 0.5 * sin(rr * 2400.0);
		c = mix(vec3(0.02), texture(alb_tex, lp.xz).rgb * tint * (0.85 + 0.25 * rings), wall);
	}
	NORMAL_MAP = nm;
	ALBEDO = c;
	ROUGHNESS = 0.82;
}
"""

# ---------------------------------------------------------------- Schnittkante (Wellpappe im Querschnitt)
# Fuer extrudierte Ausschnitte (geo.gd extrude): UV.x = Umfang in m, UV.y = 0..1 ueber die Dicke.
const EDGE_SHADER := """
shader_type spatial;
render_mode diffuse_burley;
#COMMON
uniform float thick = 0.006;     // Plattenstaerke (Weltmass, bei Miniatur gross)
uniform float pitch = 0.008;
uniform float liner = 0.12;
void fragment(){
	float u = UV.x; float v = UV.y;
	float w = 0.5 + (0.5 - liner - 0.06) * sin(u * 6.2831 / pitch);
	float d = abs(v - w);
	float flute = 1.0 - smoothstep(0.035, 0.07, d);
	float inl = step(v, liner) + step(1.0 - liner, v);
	float paper = clamp(flute + inl, 0.0, 1.0);
	vec3 k = texture(alb_tex, vec2(u, v * thick) / tile_m * 3.0).rgb * tint;
	float occ = smoothstep(0.0, 0.3, d);
	vec3 voidc = k * 0.12 * (1.6 - occ);
	vec3 c = mix(voidc, k * vec3(1.1, 1.07, 1.02), paper);
	// Schnitt ist leicht ausgefranst
	c *= 0.9 + 0.15 * vn(vec2(u * 900.0, v * 6.0));
	ALBEDO = c;
	ROUGHNESS = 0.92;
	// Hohlraeume liegen tiefer: Normal kippt zur Wellenflanke
	NORMAL_MAP = vec3(0.5 + (1.0 - paper) * 0.0, 0.5 + 0.25 * (w - v) * (1.0 - inl), 1.0);
}
"""

# ---------------------------------------------------------------- Glasmurmel (Kugel)
const MARBLE_SHADER := """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, fog_disabled;
uniform vec3 col : source_color = vec3(0.10, 0.32, 1.0);
uniform vec3 core : source_color = vec3(0.70, 0.86, 1.0);
uniform float energy = 2.2;
uniform float pulse = 0.0;
varying vec3 vn_;
void vertex(){ vn_ = NORMAL; }
void fragment(){
	float fr = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.2);
	float inner = pow(clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.5);
	// Glas: dunkle, satte Huelle, heller Kern, eingeschlossene Farbschliere
	float swirl = 0.5 + 0.5 * sin(vn_.x * 9.0 + vn_.y * 5.0 + vn_.z * 7.0);
	ALBEDO = col * 0.25;
	ROUGHNESS = 0.04;
	SPECULAR = 0.9;
	CLEARCOAT = 1.0;
	CLEARCOAT_ROUGHNESS = 0.02;
	float p = 1.0 + pulse * 0.25 * sin(TIME * 3.1416);
	EMISSION = (mix(col, core, inner * 0.85) * (0.55 + 0.45 * inner) * (0.8 + 0.25 * swirl) + col * fr * 0.6) * energy * p;
}
"""

# ---------------------------------------------------------------- Lichtkegel (Dunst, statisch)
const BEAM_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, fog_disabled, shadows_disabled;
uniform vec3 col : source_color = vec3(1.0, 0.8, 0.55);
uniform float strength = 0.08;
varying float hy; varying vec3 lnv;
void vertex(){ hy = VERTEX.y; }
void fragment(){
	float edge = pow(abs(dot(NORMAL, VIEW)), 1.6);
	float along = smoothstep(-0.5, 0.45, hy) ;   // heller an der Lampe (oben)
	ALBEDO = col * strength * edge * (0.2 + 0.8 * along * along);
}
"""

const LENS_SHADER := """
shader_type canvas_item;
uniform float vig = 0.35;
void fragment(){
	vec2 d = UV - 0.5; d.x *= 1.6;
	float v = 1.0 - vig * smoothstep(0.25, 0.95, length(d));
	COLOR = vec4(0.0, 0.0, 0.0, 1.0 - v);
}
"""

static func lens(parent: Node, vig := 0.35) -> void:
	var cl := CanvasLayer.new()
	parent.add_child(cl)
	var cr := ColorRect.new()
	cr.set_anchors_preset(Control.PRESET_FULL_RECT)
	cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = LENS_SHADER
	m.shader = sh
	m.set_shader_parameter("vig", vig)
	cr.material = m
	cl.add_child(cr)

# Flaechenmaterial fuer extrudierte Ausschnitte (geo.gd extrude): Kraftliner, UV in Metern
static func flat_mat(params := {}) -> ShaderMaterial:
	var p := {"sheet": Vector2(500, 500), "tape_seams": 0.0, "scuff": 0.0}
	p.merge(params, true)
	return mat(FLOOR_SHADER.replace("vec2 p = wp.xz;", "vec2 p = UV;"), p)

static func shader(code: String) -> Shader:
	var sh := Shader.new()
	sh.code = code.replace("#COMMON", COMMON)
	return sh

static func mat(code: String, params := {}) -> ShaderMaterial:
	load_textures()
	var m := ShaderMaterial.new()
	m.shader = shader(code)
	var std := {"alb_tex": "liner_albedo", "nrm_tex": "liner_normal", "rgh_tex": "liner_rough", "tape_tex": "tape_normal", "prn_tex": "prints"}
	if code == PAPER_SHADER:
		std = {"alb_tex": "crumple_albedo", "nrm_tex": "crumple_normal"}
	for k in std:
		m.set_shader_parameter(k, tex[std[k]])
	for k in params:
		m.set_shader_parameter(k, params[k])
	return m

# ---------------------------------------------------------------- Karton-Liste -> MultiMesh
# Eintrag: {p: Mittelpunkt, s: Groesse, r: Drehung um y (rad), t: Klebeband 0/1, i: Druck 0..16, b: Helligkeit 0..1}
static func boxes(parent: Node, list: Array, m: Material, shadows := true) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	var bm := BoxMesh.new()
	bm.subdivide_width = 3
	bm.subdivide_height = 3
	bm.subdivide_depth = 3
	mm.mesh = bm
	mm.instance_count = list.size()
	for i in list.size():
		var b: Dictionary = list[i]
		var basis := Basis(Vector3.UP, b.get("r", 0.0))
		if b.has("rx"):
			basis = basis * Basis(Vector3.RIGHT, b["rx"])
		if b.has("rz"):
			basis = basis * Basis(Vector3.BACK, b["rz"])
		basis = basis * Basis.from_scale(b["s"])
		mm.set_instance_transform(i, Transform3D(basis, b["p"]))
		mm.set_instance_custom_data(i, Color(b.get("seed", randf()), b.get("t", 0.0), b.get("i", 0.0) / 16.0, b.get("b", 0.5)))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = m
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mmi)
	return mmi

# Wand aus gestapelten Kartons fuellen. o = linke untere vordere Ecke, ax = Richtung entlang der Wand
# (normiert, horizontal), Wand waechst nach oben, Kartons ragen nach -nrm (nrm zeigt zur Strasse).
# holes: Array von Rect2 (x entlang Wand, y Hoehe) – dort bleiben Oeffnungen (Fenster, Tueren).
static func stack_wall(list: Array, rng: RandomNumberGenerator, o: Vector3, ax: Vector3, nrm: Vector3,
		length: float, height: float, holes: Array = [], opts := {}) -> void:
	var y := 0.0
	var gap := 0.004
	var heights: Array = opts.get("heights", [0.3, 0.35, 0.4, 0.4, 0.45])
	var widths: Array = opts.get("widths", [0.4, 0.5, 0.6, 0.6, 0.7])
	var depth_rng: Vector2 = opts.get("depth", Vector2(0.35, 0.6))
	var jut: float = opts.get("jut", 0.035)
	var tape_p: float = opts.get("tape", 0.55)
	var print_p: float = opts.get("print", 0.25)
	var prints: Array = opts.get("prints", [1, 2, 3, 4, 15])
	var ang := atan2(-ax.z, ax.x)
	while y < height - 0.05:
		var rh: float = heights[rng.randi() % heights.size()]
		rh = min(rh, height - y)
		var x := -rng.randf_range(0.0, 0.3) if y > 0.0 else 0.0
		while x < length - 0.05:
			var w: float = widths[rng.randi() % widths.size()]
			var x0: float = max(x, 0.0)
			var x1: float = min(x + w, length)
			var cx := (x0 + x1) * 0.5
			var ww := x1 - x0 - gap
			var blocked := false
			for h in holes:
				var hr: Rect2 = h
				if x1 > hr.position.x + 0.01 and x0 < hr.end.x - 0.01 and y + rh > hr.position.y + 0.01 and y < hr.end.y - 0.01:
					blocked = true
					# Kartons an Lochrand anpassen: links/rechts kuerzen
					if x0 < hr.position.x and hr.position.x - x0 > 0.12:
						var cxx := (x0 + hr.position.x) * 0.5
						_add_box(list, rng, o, ax, nrm, cxx, hr.position.x - x0 - gap, y, rh, depth_rng, jut, tape_p, print_p, prints, ang)
					if x1 > hr.end.x and x1 - hr.end.x > 0.12:
						var cxx2 := (hr.end.x + x1) * 0.5
						_add_box(list, rng, o, ax, nrm, cxx2, x1 - hr.end.x - gap, y, rh, depth_rng, jut, tape_p, print_p, prints, ang)
					break
			if not blocked and ww > 0.1:
				_add_box(list, rng, o, ax, nrm, cx, ww, y, rh, depth_rng, jut, tape_p, print_p, prints, ang)
			x += w
		y += rh

static func _add_box(list: Array, rng: RandomNumberGenerator, o: Vector3, ax: Vector3, nrm: Vector3, cx: float, ww: float,
		y: float, rh: float, depth_rng: Vector2, jut: float, tape_p: float, print_p: float, prints: Array, ang: float) -> void:
	var d := rng.randf_range(depth_rng.x, depth_rng.y)
	var out := rng.randf_range(-0.008, 0.008)
	if rng.randf() < 0.06:
		out += rng.randf_range(0.015, jut)
	var p := o + ax * cx + Vector3.UP * (y + (rh - 0.003) * 0.5) + nrm * (out - d * 0.5)
	list.append({"p": p, "s": Vector3(ww, rh - 0.003, d), "r": ang + rng.randf_range(-0.012, 0.012),
		"t": 1.0 if rng.randf() < tape_p else 0.0, "i": float(prints[rng.randi() % prints.size()]) if rng.randf() < print_p else 0.0,
		"b": rng.randf(), "seed": rng.randf()})

# Zerknitterte Packpapier-Bahn (Vorhang): steht senkrecht, Vorderseite zeigt nach +z des Knotens.
static func paper_sheet(parent: Node, pos: Vector3, size: Vector2, rot_y: float, m: ShaderMaterial, sub := 90, shadow := true) -> MeshInstance3D:
	var pm := PlaneMesh.new()
	pm.size = size
	pm.subdivide_width = sub
	pm.subdivide_depth = int(sub * size.y / size.x)
	var mi := MeshInstance3D.new()
	mi.mesh = pm
	var mm := m.duplicate() as ShaderMaterial
	mm.set_shader_parameter("size", size)
	mi.material_override = mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = pos
	mi.rotation = Vector3(PI / 2.0, rot_y, 0.0)
	parent.add_child(mi)
	return mi

static func tube(parent: Node, pos: Vector3, r: float, h: float, m: ShaderMaterial) -> MeshInstance3D:
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = 28
	var mi := MeshInstance3D.new()
	mi.mesh = cm
	var mm := m.duplicate() as ShaderMaterial
	mm.set_shader_parameter("radius", r)
	mi.material_override = mm
	mi.position = pos
	parent.add_child(mi)
	return mi

static func marbles(parent: Node, points: Array, r: float, m: Material) -> MultiMeshInstance3D:
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 32
	sm.rings = 16
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = sm
	mm.instance_count = points.size()
	for i in points.size():
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, points[i]))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = m
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mmi)
	return mmi

# Scheinwerfer mit Schatten und optionalem Dunstkegel
static func spot(parent: Node, pos: Vector3, target: Vector3, color: Color, energy: float, angle: float,
		rng_m: float, beam := 0.0, shadow := true) -> SpotLight3D:
	var s := SpotLight3D.new()
	parent.add_child(s)
	s.transform = Transform3D(Basis.looking_at(target - pos, Vector3.UP if abs((target - pos).normalized().y) < 0.99 else Vector3.FORWARD), pos)
	s.light_color = color
	s.light_energy = energy
	s.spot_angle = angle
	s.spot_angle_attenuation = 0.6
	s.spot_range = rng_m
	s.spot_attenuation = 0.6
	s.shadow_enabled = shadow
	s.shadow_blur = 1.5
	s.shadow_bias = 0.03
	s.light_specular = 0.6
	if beam > 0.0:
		var L: float = min(pos.distance_to(target) * 1.05, rng_m)
		var cm := CylinderMesh.new()
		cm.top_radius = 0.12
		cm.bottom_radius = tan(deg_to_rad(angle)) * L * 0.92
		cm.height = L
		cm.radial_segments = 40
		cm.cap_top = false
		cm.cap_bottom = false
		var mi := MeshInstance3D.new()
		mi.mesh = cm
		var bm := ShaderMaterial.new()
		bm.shader = shader(BEAM_SHADER)
		bm.set_shader_parameter("col", color)
		bm.set_shader_parameter("strength", beam)
		mi.material_override = bm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mi)
		var dir := (target - pos).normalized()
		var b := Basis(Quaternion(Vector3.DOWN, dir))
		mi.transform = Transform3D(b, pos + dir * L * 0.5)
	return s

static func omni(parent: Node, pos: Vector3, color: Color, energy: float, rng_m: float, shadow := false) -> OmniLight3D:
	var o := OmniLight3D.new()
	o.position = pos
	o.light_color = color
	o.light_energy = energy
	o.omni_range = rng_m
	o.omni_attenuation = 1.2
	o.shadow_enabled = shadow
	o.shadow_blur = 2.0
	parent.add_child(o)
	return o

static func kelvin(k: float) -> Color:
	# grobe Naeherung Schwarzkoerper (Tanner Helland), reicht fuer Lichtfarben
	var t := k / 100.0
	var r: float; var g: float; var b: float
	if t <= 66.0:
		r = 255.0
		g = 99.4708025861 * log(t) - 161.1195681661
		b = 0.0 if t <= 19.0 else 138.5177312231 * log(t - 10.0) - 305.0447927307
	else:
		r = 329.698727446 * pow(t - 60.0, -0.1332047592)
		g = 288.1221695283 * pow(t - 60.0, -0.0755148492)
		b = 255.0
	return Color(clamp(r, 0, 255) / 255.0, clamp(g, 0, 255) / 255.0, clamp(b, 0, 255) / 255.0)
