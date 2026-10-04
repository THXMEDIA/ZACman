# Arles v2 – Shader-Quelltexte (Art Director, 04.10.2026, Prototyp, NICHT Spielcode).
# Gemeinsame Bausteine: periodisches Rauschen, Impasto-Strich mit Strich-LOD, gemalte
# Laternen-Lichtpfuetzen (statt vieler Omni-Lichter), Fassaden mit prozeduralen Fenstern,
# ruhiger Boden mit Rinnstein = Kollisionskante, Wasser mit Laternen-Spiegelungen,
# gebackener Wirbelhimmel (Flowmap, 3 Textur-Taps zur Laufzeit), Halo-MultiMesh, Kugeln mit Kontur.
extends RefCounted

const NOISE := """
float hash21(vec2 p){ p = fract(p*vec2(123.34, 456.21)); p += dot(p, p+45.32); return fract(p.x*p.y); }
float vnoise(vec2 p){ vec2 i=floor(p); vec2 f=fract(p); f=f*f*(3.0-2.0*f);
	float a=hash21(i), b=hash21(i+vec2(1,0)), c=hash21(i+vec2(0,1)), d=hash21(i+vec2(1,1));
	return mix(mix(a,b,f.x), mix(c,d,f.x), f.y); }
"""

# Impasto-Strich + LOD + Lichtpfuetzen. lod 0 = voller Strich, 1 = Mittelfarbe ohne Relief.
const COMMON := NOISE + """
uniform float lod_on = 1.0;
uniform float lod_near = 13.0;
uniform float lod_far = 26.0;
uniform float calm = 0.0;          // "Effekte reduzieren": ruhigerer Pinsel
uniform vec4 lamps[48];            // xyz Position, w Staerke (gemalte Lichtpfuetzen)
uniform int nlamps = 0;
uniform vec3 lamp_col = vec3(1.0, 0.76, 0.40);
uniform float pool_gain = 1.0;

float stroke_lod(float dist, float pix){
	float l = max(smoothstep(lod_near, lod_far, dist), smoothstep(0.30, 0.75, pix));
	return clamp(max(l*lod_on, calm*0.45), 0.0, 1.0);
}
vec3 pools(vec3 p, vec3 n){
	vec3 acc = vec3(0.0);
	for (int i = 0; i < nlamps; i++){
		vec3 d = lamps[i].xyz - p; float dd = dot(d, d);
		float ndl = clamp(dot(n, d*inversesqrt(dd + 0.0001))*0.65 + 0.35, 0.0, 1.0);
		acc += lamps[i].w * ndl / (1.0 + dd*0.10) * smoothstep(225.0, 25.0, dd);
	}
	return acc*lamp_col;
}
float cell_angle(vec2 uv, float len, float base, int mode, vec2 ctr){
	float cs = len*2.6;
	vec2 mc = floor(uv/cs + vec2(0.0, 0.5*mod(floor(uv.x/cs), 2.0)));
	vec2 mcc = (mc + 0.5)*cs;
	float a = base;
	if (mode == 1) a = atan(mcc.y-ctr.y, mcc.x-ctr.x) + 1.5708;
	if (mode == 2) a = atan(mcc.y-ctr.y, mcc.x-ctr.x);
	return a + (hash21(mc + 0.37)-0.5)*0.55;
}
// liefert Farbe; ridge (Relief quer zum Strich) und Strichrichtung fuer die Normale
vec3 impasto(vec2 uv, vec3 ca, vec3 cb, vec3 cc, float accent, float a, float len, float wid, float lod, out vec2 dv, out float ridge){
	vec2 d = vec2(cos(a), sin(a)); vec2 pd = vec2(-d.y, d.x);
	float s = dot(uv, d); float t = dot(uv, pd);
	float row = floor(t/wid);
	float rl = len*(0.6 + 0.8*hash21(vec2(row, 7.7)));
	float off = hash21(vec2(row, 3.1))*rl;
	float cell = floor((s+off)/rl);
	float h = hash21(vec2(row, cell));
	float h2 = hash21(vec2(cell, row) + 9.0);
	float ft = fract(t/wid); float fs = fract((s+off)/rl);
	float body = smoothstep(0.0, 0.10, fs)*smoothstep(1.0, 0.90, fs);
	vec3 c = mix(ca, cb, h);
	c = mix(c, cc, step(1.0-accent, h2));
	c *= mix(0.80, 1.10, h2);
	c = mix(c*0.55, c, body);
	vec3 mean = (mix(ca, cb, 0.5)*(1.0-accent) + cc*accent)*0.92;
	dv = pd; ridge = (ft-0.5)*2.0*(1.0-lod);
	// Ferne: keine flache Mittelfarbe, sondern grosse, weiche Tupfer (niedrige Frequenz, kein Flimmern)
	vec3 far = mean*(0.72 + 0.56*vnoise(vec2(s/(len*5.0), t/(wid*16.0))));
	return mix(c, far, lod);
}
"""

# Einzelobjekte (Wahrzeichen, Requisiten, Figuren). Triplanar aus Weltposition.
const OBJ_BODY := """
uniform vec3 col_a : source_color = vec3(0.5);
uniform vec3 col_b : source_color = vec3(0.6);
uniform vec3 col_c : source_color = vec3(0.9, 0.7, 0.2);
uniform vec3 band_col : source_color = vec3(0.45, 0.25, 0.2);
uniform vec3 back_col : source_color = vec3(0.12, 0.10, 0.2);
uniform float back_dark = 0.0;     // zweiseitig: Rueckseite dunkel (Gewoelbe)
uniform float band = 0.0;          // >0: waagrechte Baender (Ziegel/Stein im Wechsel), Hoehe in m
uniform float accent = 0.12;
uniform float angle = 0.0;
uniform float len = 0.7;
uniform float wid = 0.09;
uniform float bump = 0.7;
uniform float rough = 0.55;
uniform int center_mode = 0;
uniform vec2 center = vec2(0.0);
uniform float emit = 0.0;
varying vec3 wpos; varying vec3 wn;
void vertex(){ wpos = (MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; wn = normalize((MODEL_MATRIX*vec4(NORMAL,0.0)).xyz); }
void fragment(){
	vec3 nn = FRONT_FACING ? wn : -wn;
	vec3 an = abs(nn); vec2 uv; vec3 tu; vec3 tv;
	if (an.y > 0.6) { uv = wpos.xz; tu = vec3(1,0,0); tv = vec3(0,0,1); }
	else if (an.x > an.z) { uv = wpos.zy; tu = vec3(0,0,1); tv = vec3(0,1,0); }
	else { uv = wpos.xy; tu = vec3(1,0,0); tv = vec3(0,1,0); }
	float a = cell_angle(uv, len, angle, center_mode, center);
	float lod = stroke_lod(length(wpos - CAMERA_POSITION_WORLD), length(fwidth(uv/wid)));
	vec3 ca = col_a; vec3 cb = col_b;
	if (band > 0.0 && mod(floor(wpos.y/band), 2.0) > 0.5) { ca = band_col; cb = band_col*0.82; }
	if (back_dark > 0.5 && FRONT_FACING) { ca = back_col; cb = back_col*0.8; }
	vec2 dv; float ridge;
	vec3 c = impasto(uv, ca, cb, col_c, accent, a, len, wid, lod, dv, ridge);
	vec3 wtan = normalize(tu*dv.x + tv*dv.y);
	vec3 n = normalize(nn + wtan*ridge*bump*(1.0-calm*0.5));
	NORMAL = normalize((VIEW_MATRIX*vec4(n, 0.0)).xyz);
	ALBEDO = c; ROUGHNESS = rough; SPECULAR = 0.5;
	EMISSION = c*emit + c*pools(wpos, nn)*pool_gain;
}
"""
const OBJ := "shader_type spatial;\n" + COMMON + OBJ_BODY
const OBJ2S := "shader_type spatial;\nrender_mode cull_disabled;\n" + COMMON + OBJ_BODY

# Haeuser aus dem Stadtraster (eine Mesh fuer alle Bloecke). Vertexfarbe: r = Palette/8,
# g = Seed des Grundstuecks, b = Traufhoehe/20. Fenster, Laeden, Tueren, Sockel, Gesims im Shader.
const FACADE := "shader_type spatial;\n" + COMMON + """
uniform vec3 pal_a[6]; uniform vec3 pal_b[6]; uniform vec3 pal_c[6];
uniform vec3 roof_a[4]; uniform vec3 roof_b[4];
uniform vec3 roof_c = vec3(0.03, 0.03, 0.09);
uniform vec3 win_a = vec3(0.92, 0.58, 0.07);
uniform vec3 win_b = vec3(0.90, 0.45, 0.04);
uniform vec3 win_c = vec3(1.0, 0.88, 0.45);
uniform vec3 shut_a = vec3(0.10, 0.18, 0.42);
uniform vec3 shut_b = vec3(0.06, 0.11, 0.28);
uniform vec3 glass = vec3(0.01, 0.015, 0.05);
uniform vec3 door_col = vec3(0.07, 0.04, 0.03);
uniform float lit_ratio = 0.38;
uniform float win_emit = 1.5;
varying vec3 wpos; varying vec3 wn; varying vec4 vc;
void vertex(){ wpos = (MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; wn = normalize((MODEL_MATRIX*vec4(NORMAL,0.0)).xyz); vc = COLOR; }
void fragment(){
	// Vertexfarbe quantisieren: sonst kippt der Hash durch Interpolationsrauschen pro Pixel
	vec4 q = floor(vc*255.0 + 0.5)/255.0;
	int pi = clamp(int(q.r*8.0 + 0.5), 0, 5); float seed = q.g; float eave = q.b*20.0;
	bool roof = wn.y > 0.3;
	vec2 uv; vec3 tu; vec3 tv; float a; float len; float wid;
	vec3 ca; vec3 cb; vec3 cc; float acc;
	if (roof) {
		uv = wpos.xz; tu = vec3(1,0,0); tv = vec3(0,0,1);
		a = atan(wn.z, wn.x) + (hash21(floor(wpos.xz*0.7))-0.5)*0.4; len = 0.55; wid = 0.13;
		int ri = int(mod(seed*13.0, 4.0));
		ca = roof_a[ri]; cb = roof_b[ri]; cc = roof_c; acc = 0.14;
	} else {
		if (abs(wn.x) > 0.5) { uv = wpos.zy; tu = vec3(0,0,1); tv = vec3(0,1,0); }
		else { uv = wpos.xy; tu = vec3(1,0,0); tv = vec3(0,1,0); }
		len = 0.75; wid = 0.09;
		a = cell_angle(uv, len, (seed-0.5)*0.6, 0, vec2(0.0));
		ca = pal_a[pi]; cb = pal_b[pi]; cc = pal_c[pi]; acc = 0.12;
	}
	float dist = length(wpos - CAMERA_POSITION_WORLD);
	float lod = stroke_lod(dist, length(fwidth(uv/wid)));
	vec2 dv; float ridge;
	vec3 c = impasto(uv, ca, cb, cc, acc, a, len, wid, lod, dv, ridge);
	vec3 emitc = vec3(0.0);
	if (!roof) {
		float s = abs(wn.x) > 0.5 ? wpos.z : wpos.x;
		float y = wpos.y;
		float colid = floor(s/2.0); float fx = fract(s/2.0) - 0.5;
		float flo = floor((y - 0.4)/3.0); float fy = y - (flo*3.0 + 0.4);
		float h1 = hash21(vec2(colid, flo) + seed*31.7);
		float h2 = hash21(vec2(flo + 5.0, colid) + seed*7.3);
		float h3 = hash21(vec2(colid*1.7, flo + 3.0) + seed*3.1);
		vec3 c_wall = c;
		float wl = smoothstep(0.10, 0.40, fwidth(s)*0.5);   // Fensterraster zu fein fuer die Pixel -> mitteln
		if (y < 0.55) c *= 0.5;                                     // Sockel = Kollisionskante
		if (y > eave - 0.38 && y < eave) c = mix(c*0.42, c*1.2, step(eave - 0.09, y));  // Gesims
		vec3 wc = c; float win = 0.0; float we = 0.0;
		float iny = step(0.9, fy)*step(fy, 2.45);
		if (flo >= 1.0 && y < eave - 0.55 && h1 < 0.85) {
			if (abs(fx) < 0.19 && iny > 0.5) {
				if (h2 < lit_ratio) {
					vec2 d2; float r2;
					wc = impasto(uv, win_a, win_b, win_c, 0.25, 1.5708 + (h3-0.5)*0.5, 0.42, 0.13, max(lod, 0.25), d2, r2);
					we = win_emit;
					if (abs(fx) < 0.016 || abs(fy - 1.95) < 0.028) { wc *= 0.3; we *= 0.25; }
				} else if (h3 < 0.62) {
					wc = mix(shut_a, shut_b, step(0.5, fract(fy*9.0)))*mix(0.85, 1.15, h1);
				} else { wc = glass; }
				win = 1.0;
			} else if (h2 < lit_ratio && abs(fx) < 0.31 && iny > 0.5) {
				wc = mix(shut_a, shut_b, step(0.5, fract(fy*9.0)))*0.95; win = 1.0;   // offene Laeden
			}
			if (abs(fx) < 0.25 && fy > 0.78 && fy < 0.9) { wc = c*0.45; win = 1.0; }   // Fensterbank
		}
		if (flo < 1.0 && y < eave - 0.55) {
			if (h1 < 0.20 && abs(fx) < 0.24 && fy < 2.35) {
				wc = door_col*(0.8 + 0.4*step(0.5, fract(fx*9.0))); win = 1.0;
			} else if (h1 < 0.34 && abs(fx) < 0.40 && fy > 0.55 && fy < 2.6) {
				vec2 d2; float r2;
				wc = impasto(uv, win_a, win_b, win_c, 0.25, 1.5708, 0.42, 0.13, max(lod, 0.25), d2, r2);
				we = win_emit*0.75; win = 1.0;
			}
		}
		c = mix(c, wc, win);
		emitc = wc*we*win;
		// warmer Schein um erleuchtete Fenster auf der Wand (gemalter Lichthof, kein Licht)
		if (flo >= 1.0 && y < eave - 0.55 && h1 < 0.85 && h2 < lit_ratio) {
			float ddx = max(abs(fx)*2.0 - 0.38, 0.0); float ddy = max(abs(fy - 1.675) - 0.775, 0.0);
			emitc += win_a*exp(-length(vec2(ddx, ddy))*3.5)*0.45*(1.0 - win)*win_emit;
		}
		float upper_ = step(1.0, flo)*step(y, eave - 0.55);
		c = mix(c, c_wall*0.8, wl);
		emitc = mix(emitc, win_a*win_emit*lit_ratio*0.25*upper_, wl);
		ridge *= (1.0 - win*0.8);
	}
	vec3 wtan = normalize(tu*dv.x + tv*dv.y);
	vec3 n = normalize(wn + wtan*ridge*0.7*(1.0-calm*0.5));
	NORMAL = normalize((VIEW_MATRIX*vec4(n, 0.0)).xyz);
	ALBEDO = c; ROUGHNESS = 0.55; SPECULAR = 0.5;
	EMISSION = emitc + c*pools(wpos, wn)*pool_gain;
}
"""

# Boden: ruhiges Pflaster (Strich laengs der Strasse, wenig Kontrast), Rinnstein dunkel
# genau an der Blockkante (= Kollision), Platz um die Caféterrasse konzentrisch.
const FLOOR := "shader_type spatial;\n" + COMMON + """
uniform sampler2D grid : filter_nearest;
uniform vec2 gsize = vec2(45.0, 41.0);
uniform vec3 pave_a : source_color = vec3(0.2);
uniform vec3 pave_b : source_color = vec3(0.18);
uniform vec3 pave_c : source_color = vec3(0.6, 0.45, 0.2);
uniform vec3 gutter : source_color = vec3(0.05, 0.05, 0.1);
uniform vec3 kerb : source_color = vec3(0.4, 0.4, 0.5);
uniform vec3 outside : source_color = vec3(0.08, 0.08, 0.16);
uniform vec4 plaza = vec4(16.0, 30.0, 38.0, 52.0);   // Place du Forum (x0, z0, x1, z1)
uniform vec2 plaza_ctr = vec2(27.0, 30.0);
uniform float calm_floor = 0.45;                      // Boden ruhiger als Waende
varying vec3 wpos;
void vertex(){ wpos = (MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; }
float o(vec2 cell){
	if (cell.x < 0.0 || cell.y < 0.0 || cell.x >= gsize.x || cell.y >= gsize.y) return 0.0;
	return texture(grid, (cell + 0.5)/gsize).r;
}
void fragment(){
	vec2 cell = floor(wpos.xz/2.0); vec2 f = fract(wpos.xz/2.0);
	float here = o(cell);
	float ow = o(cell + vec2(-1, 0)); float oe = o(cell + vec2(1, 0));
	float on = o(cell + vec2(0, -1)); float os = o(cell + vec2(0, 1));
	float a = (on + os > ow + oe) ? 1.5708 : 0.0;
	int mode = 0;
	if (wpos.x > plaza.x && wpos.x < plaza.z && wpos.z > plaza.y && wpos.z < plaza.w) mode = 1;
	vec2 uv = wpos.xz;
	float ang = cell_angle(uv, 1.1, a, mode, plaza_ctr);
	float lod = stroke_lod(length(wpos - CAMERA_POSITION_WORLD), length(fwidth(uv/0.2)));
	vec2 dv; float ridge;
	vec3 c = impasto(uv, pave_a, pave_b, pave_c, 0.07, ang, 1.1, 0.2, max(lod, calm_floor), dv, ridge);
	float dmin = 9.0;
	if (ow < 0.5) dmin = min(dmin, f.x*2.0);
	if (oe < 0.5) dmin = min(dmin, (1.0 - f.x)*2.0);
	if (on < 0.5) dmin = min(dmin, f.y*2.0);
	if (os < 0.5) dmin = min(dmin, (1.0 - f.y)*2.0);
	if (dmin < 0.26) c = gutter;
	else if (dmin < 0.40) c = mix(kerb, c, 0.35);
	if (here < 0.5) c = outside;
	ALBEDO = c; ROUGHNESS = 0.7; SPECULAR = 0.35;
	vec3 wtan = vec3(dv.x, 0.0, dv.y);
	NORMAL = normalize((VIEW_MATRIX*vec4(normalize(vec3(0,1,0) + wtan*ridge*0.35), 0.0)).xyz);
	EMISSION = c*pools(wpos, vec3(0,1,0))*pool_gain*1.15;
}
"""

# Rhone: dunkle waagrechte Striche + Laternen-Spiegelungen als lange, in Striche gebrochene
# Saeulen (Kern Gelb, Rand Rostgold). Zeit nur fuer leichtes Zittern, steht bei "Effekte reduzieren".
const WATER := "shader_type spatial;\nrender_mode unshaded, fog_disabled;\n" + COMMON + """
uniform vec4 refl[40]; uniform int nrefl = 0;
uniform vec3 deep : source_color = vec3(0.04, 0.07, 0.22);
uniform vec3 mid : source_color = vec3(0.10, 0.18, 0.45);
uniform vec3 hi : source_color = vec3(0.30, 0.45, 0.75);
uniform vec3 r_core : source_color = vec3(1.0, 0.86, 0.45);
uniform vec3 r_rim : source_color = vec3(0.79, 0.60, 0.24);   // Rostgold -> Gold (Abstand zur Kugel)
uniform float shimmer = 1.0;
varying vec3 wpos;
void vertex(){ wpos = (MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; }
void fragment(){
	float t = TIME*0.6*shimmer;
	vec3 cam = CAMERA_POSITION_WORLD;
	vec3 V = normalize(wpos - cam);
	vec3 R = vec3(V.x, -V.y, V.z);
	float azr = atan(R.x, R.z); float elr = asin(clamp(R.y, -1.0, 1.0));
	vec2 uv = wpos.xz*vec2(1.0, 0.35);
	float lod = stroke_lod(length(wpos - cam), length(fwidth(uv/0.10)));
	vec2 dv; float ridge;
	vec3 c = impasto(uv, deep, mid, hi, 0.08, 0.0 + (vnoise(wpos.xz*0.05)-0.5)*0.4, 0.9, 0.10, lod*0.8, dv, ridge);
	c *= 0.75;
	vec3 add = vec3(0.0);
	for (int i = 0; i < nrefl; i++){
		vec3 d = refl[i].xyz - wpos;
		float azd = atan(d.x, d.z); float eld = atan(d.y, length(d.xz));
		float da = azr - azd; da = da - 6.2831853*floor((da + 3.14159265)/6.2831853);
		float wob = (vnoise(vec2(wpos.z*0.9 + float(i)*3.1, wpos.x*2.5 + t)) - 0.5)*0.016;
		da += wob;
		float de = elr - eld;                      // >0: Wasserpunkt naeher am Ufer als das Spiegelbild
		float col = exp(-pow(da/0.016, 2.0));
		float wide = exp(-pow(da/0.045, 2.0))*0.30;
		float len_ = smoothstep(0.42, 0.0, de) * smoothstep(-0.05, 0.0, de);   // Saeule vom Spiegelbild zum Betrachter
		float dash = 0.45 + 0.55*step(0.42, vnoise(vec2(eld*0.0 + elr*90.0, float(i)*5.7 + t*0.4)));
		float k = (col + wide)*len_*dash*refl[i].w;
		add += mix(r_rim, r_core, clamp(col*1.3, 0.0, 1.0))*k;
	}
	ALBEDO = c + add;
}
"""

# Himmel, Schritt 1 (einmal beim Levelaufbau): LIC ueber ein Wirbelfeld, ringsum nahtlos
# (periodisch in x). Ausgabe: R = Strichwert, G = Gelb-Zone, BA = Stroemungsrichtung.
const SKY_BAKE := "shader_type canvas_item;\n" + """
uniform float W = 10.0;
float hash21(vec2 p){ p = fract(p*vec2(123.34, 456.21)); p += dot(p, p+45.32); return fract(p.x*p.y); }
float vnp(vec2 p, float per){ vec2 i = floor(p); vec2 f = fract(p); f = f*f*(3.0-2.0*f);
	float x0 = mod(i.x, per); float x1 = mod(i.x + 1.0, per);
	float a = hash21(vec2(x0, i.y)), b = hash21(vec2(x1, i.y)), c = hash21(vec2(x0, i.y+1.0)), d = hash21(vec2(x1, i.y+1.0));
	return mix(mix(a,b,f.x), mix(c,d,f.x), f.y); }
vec2 vortex(vec2 p, vec2 c, float s, float k){ vec2 r = p - c; r.x -= W*round(r.x/W); float d2 = dot(r,r); return vec2(-r.y, r.x)*s*exp(-d2*k)/(sqrt(d2) + 0.15); }
vec2 flow(vec2 p){
	vec2 f = vec2(0.28, 0.06);
	f += vortex(p, vec2(0.7, 2.0), 2.6, 0.22);
	f += vortex(p, vec2(2.4, 1.4), -2.0, 0.3);
	f += vortex(p, vec2(3.9, 2.6), 1.8, 0.35);
	f += vortex(p, vec2(5.6, 1.6), -1.7, 0.3);
	f += vortex(p, vec2(7.1, 2.2), 2.2, 0.28);
	f += vortex(p, vec2(8.7, 1.3), -1.5, 0.4);
	f += vortex(p, vec2(4.6, 3.6), 1.4, 0.5);
	f += vortex(p, vec2(9.4, 3.4), -1.4, 0.45);
	return normalize(f);
}
void fragment(){
	float elev = (1.0 - UV.y)*1.5708;
	vec2 p = vec2(UV.x*W, sin(elev)*4.2 + 0.4);
	float acc = 0.0; vec2 q = p; vec2 q2 = p;
	for (int i = 0; i < 7; i++){
		q += flow(q)*0.03; q2 -= flow(q2)*0.03;
		acc += vnp(q*vec2(14.0, 26.0), 14.0*W) + vnp(q2*vec2(14.0, 26.0), 14.0*W);
	}
	acc /= 14.0;
	float zone = smoothstep(0.62, 0.78, vnp(p*1.8 + vec2(7.0, 3.0), 18.0));
	vec2 f = flow(p);
	COLOR = vec4(acc, zone, f*0.5 + 0.5);
}
"""

# Himmel, Schritt 2 (Laufzeit): Flowmap-Animation mit zwei versetzten Abtastungen der
# gebackenen Strichtextur (+1 Abtastung fuer Richtung/Zone), kein Rauschen, keine Schleife.
const SKY := "shader_type spatial;\nrender_mode unshaded, cull_front, fog_disabled;\n" + """
uniform sampler2D baked : filter_linear_mipmap, repeat_enable;
uniform vec3 base : source_color = vec3(0.08, 0.13, 0.40);
uniform vec3 mid : source_color = vec3(0.18, 0.33, 0.66);
uniform vec3 light : source_color = vec3(0.50, 0.70, 0.90);
uniform vec3 yellow : source_color = vec3(0.96, 0.79, 0.27);
uniform vec3 glow : source_color = vec3(0.0);      // Horizontschimmer (blaue Stunde)
uniform float glow_amt = 0.0;
uniform float speed = 0.04;                         // Phase/s, << 0,5 Hz
uniform float moving = 1.0;                         // 0 bei "Effekte reduzieren"
uniform float horizon = 0.22;
uniform vec3 haze : source_color = vec3(0.08, 0.1, 0.25);
varying vec3 dir;
void vertex(){ dir = normalize((MODEL_MATRIX*vec4(VERTEX,1.0)).xyz - CAMERA_POSITION_WORLD); }
void fragment(){
	float az = atan(dir.x, -dir.z);
	float elev = asin(clamp(dir.y, 0.0, 1.0));
	vec2 uv = vec2(az/6.2831853 + 0.5, min(1.0 - elev/1.5708, 0.985));   // v nicht ueber den Rand wickeln
	vec4 b0 = texture(baked, uv);
	vec2 f = b0.ba*2.0 - 1.0;
	float t = TIME*speed*moving;
	float ph1 = fract(t); float ph2 = fract(t + 0.5);
	vec2 off = vec2(f.x/10.0, -f.y/(4.2*1.5708))*0.35;
	float a1 = texture(baked, uv - off*ph1).r;
	float a2 = texture(baked, uv - off*ph2).r;
	float w = abs(1.0 - 2.0*ph1);
	float acc = mix(a1, a2, w);
	if (moving < 0.5) acc = b0.r;
	float strokes = smoothstep(0.46, 0.50, acc);
	float hi = smoothstep(0.545, 0.575, acc);
	vec3 c = mix(base, mid, strokes);
	c = mix(c, light, hi*0.9);
	c = mix(c, yellow, hi*b0.g*0.85);
	c *= 0.88 + 0.24*step(0.5, fract(acc*40.0));
	c = mix(c, glow, glow_amt*smoothstep(0.35, 0.0, dir.y)*(0.6 + 0.4*hi));
	c *= mix(0.5, 1.0, smoothstep(-0.05, horizon, dir.y));
	c = mix(c, haze, smoothstep(0.10, -0.01, dir.y)*0.9);
	ALBEDO = c;
}
"""

# Halos (Laternen, Sterne, Mond, gruener Ausgangsstern) als EINE MultiMesh.
# INSTANCE_CUSTOM: x Seed, y Ringe, z Energie, w Typ (0 Laterne, 1 Stern, 2 Mond, 3 Ausgang).
const HALO := "shader_type spatial;\nrender_mode unshaded, cull_disabled, fog_disabled, depth_draw_never;\n" + NOISE + """
uniform vec3 core : source_color = vec3(1.0, 0.95, 0.69);
uniform vec3 yellow : source_color = vec3(0.98, 0.80, 0.27);
uniform vec3 rim : source_color = vec3(0.83, 0.63, 0.23);
uniform vec3 g_core : source_color = vec3(0.85, 1.0, 0.88);
uniform vec3 g_mid : source_color = vec3(0.22, 1.0, 0.42);
uniform vec3 g_rim : source_color = vec3(0.05, 0.45, 0.18);
uniform float moving = 1.0;
uniform float soft = 0.4;
varying vec4 cu; varying float fade;
void vertex(){
	cu = INSTANCE_CUSTOM;
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz),0,0,0), vec4(0,length(MODEL_MATRIX[1].xyz),0,0), vec4(0,0,1,0), vec4(0,0,0,1));
	float d = distance(MODEL_MATRIX[3].xyz, CAMERA_POSITION_WORLD);
	fade = smoothstep(2.5, 7.0, d);                  // kein Vollbild-Blitz vor der Kamera
}
void fragment(){
	vec2 p = UV - 0.5; float r = length(p)*2.0; float ang = atan(p.y, p.x);
	float seed = cu.x; float rings = cu.y; float energy = cu.z; int typ = int(cu.w + 0.5);
	vec3 k0 = core; vec3 k1 = yellow; vec3 k2 = rim;
	if (typ == 3) { k0 = g_core; k1 = g_mid; k2 = g_rim; energy *= 1.0 + 0.25*sin(TIME*3.14159)*moving; }
	float rn = fract(r*rings + (vnoise(vec2(ang*2.0 + seed, r*3.0)) - 0.5)*0.5);
	vec3 c = mix(k0, k1, smoothstep(0.0, 0.35, r));
	c = mix(c, k2, smoothstep(0.45, 1.0, r));
	float str = 0.85 + 0.3*step(0.5, fract(ang*7.0 + r*2.0 + seed));
	c *= mix(0.78, 1.15, smoothstep(0.25, 0.75, rn));
	float a = smoothstep(1.0, 0.86, r + (vnoise(vec2(ang*4.0, seed)) - 0.5)*0.15);
	a *= mix(1.0, (typ == 0) ? soft : 0.75, smoothstep(0.35, 1.0, r));
	ALBEDO = c*str*energy; ALPHA = a*fade;
}
"""

# Kugeln: Zinnober (exklusiv), heller Kern, dunkle Kontur am Rand (lesbar vor gelbem Licht).
const ORB := """
shader_type spatial;
render_mode unshaded;
uniform vec3 col : source_color = vec3(1.0, 0.29, 0.11);
uniform vec3 core : source_color = vec3(1.0, 0.69, 0.53);
uniform vec3 outline : source_color = vec3(0.23, 0.05, 0.02);
uniform float energy = 1.5;
void fragment(){
	float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	vec3 body = mix(col, core, pow(ndv, 4.0))*energy*(0.75 + 0.25*ndv);
	ALBEDO = mix(outline, body, smoothstep(0.20, 0.36, ndv));
}
"""

# Ausgang: gruen gefuellte Tuer, Puls 0,5 Hz (steht bei "Effekte reduzieren"), senkrechte Striche.
const EXIT := "shader_type spatial;\nrender_mode unshaded;\n" + NOISE + """
uniform vec3 col : source_color = vec3(0.23, 0.96, 0.78);
uniform vec3 dark : source_color = vec3(0.03, 0.16, 0.13);
uniform float energy = 1.6;
uniform float moving = 1.0;
uniform float panels = 1.0;     // 1: Tuerfuellung mit Rahmen, 0: Fensterladen-Lamellen
void fragment(){
	float p = 0.86 + 0.14*sin(TIME*3.14159)*moving;
	float s = 0.9 + 0.2*step(0.5, fract(UV.x*14.0 + vnoise(UV*vec2(6.0, 2.0))*0.6));
	vec3 c = col*energy*p*s;
	if (panels > 0.5) {
		float fr = step(0.06, UV.x)*step(UV.x, 0.94)*step(0.04, UV.y);
		float mid_ = 1.0 - step(abs(UV.x - 0.5), 0.02);
		c = mix(dark, c, fr*mid_);
	} else {
		c *= 0.55 + 0.45*step(0.35, fract(UV.y*10.0));
	}
	ALBEDO = c;
}
"""

# Tympanon von Saint-Trophime: Halbkreis, Relief nur angedeutet (Mandorla in der Mitte,
# vier Felder ringsum) – bewusst keine Figuren nachgebildet.
const TYMPANON := "shader_type spatial;\n" + NOISE + """
uniform vec3 stone : source_color = vec3(0.72, 0.64, 0.50);
uniform vec3 shade : source_color = vec3(0.30, 0.26, 0.36);
void fragment(){
	vec2 p = vec2(UV.x - 0.5, 1.0 - UV.y);   // Mitte unten
	p.x *= 2.0;
	float r = length(p);
	if (r > 1.0 || p.y < 0.0) discard;
	float m = length(vec2(p.x/0.32, (p.y - 0.48)/0.46));
	float relief = smoothstep(1.0, 0.92, m);
	float fields = step(0.22, abs(p.x))*step(0.18, p.y)*step(r, 0.88);
	float rings = step(0.5, fract(r*9.0));
	vec3 c = mix(shade, stone, 0.55 + 0.25*rings*(1.0 - relief));
	c = mix(c, stone*1.1, relief*(0.7 + 0.3*vnoise(p*30.0)));
	c = mix(c, stone*0.9, fields*0.6*step(0.5, vnoise(p*14.0)));
	ALBEDO = c; ROUGHNESS = 0.8;
}
"""

# Amphitheater-Aussenschale: Arkaden werden im Shader aus der Wand geschnitten (discard),
# dahinter liegt die dunkle Innenschale -> echte Tiefe ohne Einzelbogen-Geometrie.
const ARCADE := "shader_type spatial;\n" + COMMON + """
uniform vec3 col_a : source_color = vec3(0.7);
uniform vec3 col_b : source_color = vec3(0.6);
uniform vec3 col_c : source_color = vec3(0.9);
uniform vec2 ctr = vec2(68.0, 45.0);
uniform float nbay = 28.0;
uniform float perim = 88.6;
uniform float rad = 14.1;
uniform float emit = 0.0;
varying vec3 wpos; varying vec3 wn;
void vertex(){ wpos = (MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; wn = normalize((MODEL_MATRIX*vec4(NORMAL,0.0)).xyz); }
void fragment(){
	float th = atan(wpos.z - ctr.y, wpos.x - ctr.x);
	float u = th/6.2831853*nbay; float bw = perim/nbay;
	float xm = (fract(u) - 0.5)*bw;
	float y = wpos.y; float r1 = 0.95;
	float s1 = 4.1; float s2 = 10.3;
	bool open_ = false;
	if (abs(xm) < r1 && y > 0.0 && (y < s1 || xm*xm + (y-s1)*(y-s1) < r1*r1)) open_ = true;
	if (abs(xm) < r1 && y > 7.1 && (y < s2 || xm*xm + (y-s2)*(y-s2) < r1*r1)) open_ = true;
	if (open_) discard;
	vec2 uv = vec2(th*rad, y);
	float a = cell_angle(uv, 0.6, 0.0, 0, vec2(0.0));
	float sp = (y < 6.6) ? s1 : s2;
	float rr = length(vec2(xm, y - sp));
	bool vous = y > sp && rr < r1 + 0.42;                       // Bogensteine radial
	if (vous) a = atan(y - sp, xm);
	bool pil = abs(xm) > bw*0.5 - 0.30;                         // Pilaster zwischen den Boegen
	if (pil && !vous) a = 1.5708;
	bool ent = (y > 5.85 && y < 6.75) || y > 12.1;              // Gebaelk
	if (ent) a = 0.0;
	float lod = stroke_lod(length(wpos - CAMERA_POSITION_WORLD), length(fwidth(uv/0.09)));
	vec2 dv; float ridge;
	vec3 c = impasto(uv, col_a, col_b, col_c, 0.14, a, 0.6, 0.09, lod, dv, ridge);
	if (vous) c *= 0.82;
	if (pil) c *= 1.08;
	if (ent) c *= (fract(y*3.0) < 0.25) ? 0.6 : 1.05;
	if (y < 0.5) c *= 0.55;
	vec3 tu = normalize(vec3(-wn.z, 0.0, wn.x)); vec3 tv = vec3(0, 1, 0);
	vec3 n = normalize(wn + normalize(tu*dv.x + tv*dv.y)*ridge*0.6*(1.0-calm*0.5));
	NORMAL = normalize((VIEW_MATRIX*vec4(n, 0.0)).xyz);
	ALBEDO = c; ROUGHNESS = 0.6; SPECULAR = 0.45;
	EMISSION = c*pools(wpos, wn)*pool_gain + c*emit;
}
"""
