# Richtung B "Sternennacht ueber Arles" – Stil-Prototyp (Art Director, Phase 1, NICHT Spielcode).
# Himmel: animiertes Wirbelfeld (Line-Integral-Convolution ueber Vortex-Feld) als Shader auf
# einer Himmelskugel. Waende/Boden: Impasto-Strich-Shader, Strichrichtung folgt der Flaeche
# (triplanar, Boden konzentrisch um die Cafeterrasse), Relief ueber gestoerte Normale.
# Sterne/Gaslaternen: Halo-Scheiben (Billboards mit Ringen und Radialstrichen).
extends Node3D

const Geo := preload("res://geo.gd")

var cam: Camera3D
var rng := RandomNumberGenerator.new()

const NOISE := """
float hash21(vec2 p){ p = fract(p*vec2(123.34, 456.21)); p += dot(p, p+45.32); return fract(p.x*p.y); }
float vnoise(vec2 p){ vec2 i=floor(p); vec2 f=fract(p); f=f*f*(3.0-2.0*f);
	float a=hash21(i), b=hash21(i+vec2(1,0)), c=hash21(i+vec2(0,1)), d=hash21(i+vec2(1,1));
	return mix(mix(a,b,f.x), mix(c,d,f.x), f.y); }
"""

# Himmel: Wirbelfeld aus Drift + vier Vortizes; Striche durch LIC (10 Schritte vor/zurueck).
const SKY_SHADER := "shader_type spatial;\nrender_mode unshaded, cull_front, fog_disabled;\n" + NOISE + """
uniform vec3 base : source_color = vec3(0.08, 0.13, 0.40);
uniform vec3 mid : source_color = vec3(0.18, 0.33, 0.66);
uniform vec3 light : source_color = vec3(0.50, 0.70, 0.90);
uniform vec3 yellow : source_color = vec3(0.96, 0.79, 0.27);
uniform float speed = 0.04;   // Drift der Striche; < 0.5 Hz, kein Flackern
uniform float horizon = 0.22;
varying vec3 dir;
void vertex(){ dir = normalize((MODEL_MATRIX*vec4(VERTEX,1.0)).xyz - CAMERA_POSITION_WORLD); }
vec2 vortex(vec2 p, vec2 c, float s, float k){ vec2 r = p - c; float d2 = dot(r,r); return vec2(-r.y, r.x) * s * exp(-d2*k) / (sqrt(d2)+0.15); }
vec2 flow(vec2 p){
	vec2 f = vec2(0.28, 0.08);
	f += vortex(p, vec2(0.7, 2.0), 2.6, 0.22);
	f += vortex(p, vec2(-1.7, 1.5), -2.0, 0.3);
	f += vortex(p, vec2(2.9, 1.1), 1.8, 0.35);
	f += vortex(p, vec2(-0.6, 3.4), -1.6, 0.4);
	f += vortex(p, vec2(1.9, 3.6), 1.4, 0.5);
	return normalize(f);
}
void fragment(){
	vec2 p = vec2(atan(dir.x, -dir.z)*1.7, dir.y*4.2 + 0.4); // Naht hinter der Kamera (+z)
	float t = TIME*speed;
	float acc = 0.0; vec2 q = p; vec2 q2 = p;
	for (int i = 0; i < 7; i++){
		q += flow(q)*0.03; q2 -= flow(q2)*0.03;
		acc += vnoise(q*vec2(14.0, 26.0) + t) + vnoise(q2*vec2(14.0, 26.0) - t);
	}
	acc /= 14.0;
	// in drei Toene brechen: dunkle Luecke, Kobalt-Strich, heller Strich
	float strokes = smoothstep(0.46, 0.50, acc);
	float hi = smoothstep(0.545, 0.575, acc);
	vec3 c = mix(base, mid, strokes);
	c = mix(c, light, hi*0.9);
	// Chromgelb-Striche nur in Zonen (zweites, grobes Rauschen), auf hellen Strichen
	float zone = smoothstep(0.66, 0.78, vnoise(p*1.8 + 7.0 + t*0.3));
	float y = hi * zone;
	c = mix(c, yellow, y*0.85);
	// Strichkanten quer: feine Lamellen
	c *= 0.88 + 0.24*step(0.5, fract(acc*40.0 + vnoise(p*30.0)));
	c *= mix(0.5, 1.0, smoothstep(-0.05, horizon, dir.y));
	ALBEDO = c;
}
"""

# Impasto: Striche in Zellen (lang x schmal), Richtung per Winkel oder um ein Zentrum,
# dunkle Luecken, Relief ueber Normale -> Lampen geben Glanzkanten auf dem "dicken" Farbauftrag.
const IMPASTO_SHADER := "shader_type spatial;\n" + NOISE + """
uniform vec3 col_a : source_color = vec3(0.5);
uniform vec3 col_b : source_color = vec3(0.6);
uniform vec3 col_c : source_color = vec3(0.9, 0.7, 0.2);
uniform float accent = 0.10;
uniform float angle = 0.0;
uniform float len = 0.7;
uniform float wid = 0.09;
uniform float bump = 0.7;
uniform float rough = 0.5;
uniform int center_mode = 0;
uniform vec2 center = vec2(0.0);
uniform float emit = 0.0;
varying vec3 wpos; varying vec3 wn;
void vertex(){ wpos = (MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; wn = normalize((MODEL_MATRIX*vec4(NORMAL,0.0)).xyz); }
void fragment(){
	vec3 an = abs(wn); vec2 uv; vec3 tu; vec3 tv;
	if (an.y > 0.5) { uv = wpos.xz; tu = vec3(1,0,0); tv = vec3(0,0,1); }
	else if (an.x > 0.5) { uv = wpos.zy; tu = vec3(0,0,1); tv = vec3(0,1,0); }
	else { uv = wpos.xy; tu = vec3(1,0,0); tv = vec3(0,1,0); }
	// Makro-Zellen: in jeder Zelle eine feste Strichrichtung (Flecken aus parallelen Strichen)
	float cs = len*2.6;
	vec2 mc = floor(uv/cs + vec2(0.0, 0.5*mod(floor(uv.x/cs), 2.0)));
	vec2 mcc = (mc + 0.5)*cs;
	float a = angle;
	if (center_mode == 1) a = atan(mcc.y-center.y, mcc.x-center.x) + 1.5708;
	if (center_mode == 2) a = atan(mcc.y-center.y, mcc.x-center.x);
	a += (hash21(mc + 0.37)-0.5)*0.55;
	vec2 d = vec2(cos(a), sin(a)); vec2 pd = vec2(-d.y, d.x);
	float s = dot(uv,d); float t = dot(uv,pd);
	float row = floor(t/wid);
	float rl = len*(0.6 + 0.8*hash21(vec2(row, 7.7)));   // Strichlaenge je Reihe variabel
	float off = hash21(vec2(row, 3.1))*rl;
	float cell = floor((s+off)/rl);
	float h = hash21(vec2(row, cell));
	float h2 = hash21(vec2(cell, row)+9.0);
	float ft = fract(t/wid); float fs = fract((s+off)/rl);
	float body = smoothstep(0.0, 0.10, fs)*smoothstep(1.0, 0.90, fs);
	vec3 c = mix(col_a, col_b, h);
	c = mix(c, col_c, step(1.0-accent, h2));
	c *= mix(0.78, 1.12, h2);
	c = mix(c*0.5, c, body);
	float ridge = (ft-0.5)*2.0;
	vec3 wtan = normalize(tu*pd.x + tv*pd.y);
	vec3 n = normalize(wn + wtan*ridge*bump + (tu*d.x+tv*d.y)*(fs-0.5)*bump*0.5*(1.0-body));
	NORMAL = normalize((VIEW_MATRIX*vec4(n,0.0)).xyz);
	ALBEDO = c; ROUGHNESS = rough; SPECULAR = 0.55;
	EMISSION = c*emit;
}
"""

# Halo-Scheibe: Kern -> Gelb -> Orange-Rand, Ringe und Radialstriche; Billboard.
const HALO_SHADER := "shader_type spatial;\nrender_mode unshaded, cull_disabled, fog_disabled, depth_draw_never;\n" + NOISE + """
uniform vec3 core : source_color = vec3(1.0, 0.97, 0.78);
uniform vec3 yellow : source_color = vec3(0.98, 0.80, 0.27);
uniform vec3 rim : source_color = vec3(0.86, 0.50, 0.16);
uniform float energy = 1.4;
uniform float rings = 5.0;
uniform float seed = 0.0;
uniform float soft = 0.55; // Transparenz des Aussenrings
void vertex(){
""" + Geo.BILLBOARD_VERTEX + """
}
void fragment(){
	vec2 p = UV - 0.5; float r = length(p)*2.0; float ang = atan(p.y, p.x);
	float rn = fract(r*rings + (vnoise(vec2(ang*2.0 + seed, r*3.0))-0.5)*0.5);
	vec3 c = mix(core, yellow, smoothstep(0.0, 0.35, r));
	c = mix(c, rim, smoothstep(0.45, 1.0, r));
	float str = 0.85 + 0.3*step(0.5, fract(ang*7.0 + r*2.0 + seed));
	c *= mix(0.78, 1.15, smoothstep(0.25, 0.75, rn));
	float a = smoothstep(1.0, 0.86, r + (vnoise(vec2(ang*4.0, seed))-0.5)*0.15);
	a *= mix(1.0, soft, smoothstep(0.35, 1.0, r));
	ALBEDO = c*str*energy; ALPHA = a;
}
"""

const ORB_SHADER := """
shader_type spatial;
render_mode unshaded;
uniform vec3 col : source_color = vec3(1.0, 0.29, 0.11);
uniform vec3 core : source_color = vec3(1.0, 0.89, 0.78);
uniform float energy = 2.4;
void fragment(){
	float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	ALBEDO = mix(col, core, pow(ndv, 3.0)) * energy * (0.7 + 0.3*ndv);
}
"""

const METRO_SHADER := "shader_type spatial;\nrender_mode unshaded;\n" + NOISE + """
uniform vec3 col : source_color = vec3(0.22, 1.0, 0.42);
uniform float energy = 1.8;
void fragment(){
	float p = 0.85 + 0.15*sin(TIME*3.14); // 0,5 Hz
	float s = 0.9 + 0.2*step(0.5, fract(UV.y*18.0 + vnoise(UV*6.0)));
	ALBEDO = col*energy*p*s;
}
"""

func c(h: String) -> Color: return Color.html(h)

func imp(a: String, b: String, acc: String, params := {}) -> ShaderMaterial:
	var p := {"col_a": c(a), "col_b": c(b), "col_c": c(acc)}
	p.merge(params, true)
	return Geo.mat(IMPASTO_SHADER, p)

func _ready() -> void:
	rng.seed = 1888
	cam = Camera3D.new()
	cam.near = 0.1
	cam.far = 900.0
	add_child(cam)
	cam.current = true
	_environment()
	_sky()
	_ground()
	_buildings()
	_square()
	_life()
	_pellets()

func _environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = c("#141D4A")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = c("#2A3B7A")
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_bloom = 0.1
	env.glow_hdr_threshold = 1.05
	env.fog_enabled = true
	env.fog_light_color = c("#1E2C66")
	env.fog_density = 0.006
	env.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	# Mondlicht: kuehl, schwach, von links oben – Impasto-Relief bekommt Kanten.
	var moon := DirectionalLight3D.new()
	moon.light_color = c("#8FA8E0")
	moon.light_energy = 0.55
	moon.rotation_degrees = Vector3(-38, 35, 0)
	add_child(moon)

func _sky() -> void:
	var m := Geo.mat(SKY_SHADER, {"base": c("#1B2A6B"), "mid": c("#2F55A8"), "light": c("#7FB2E5"), "yellow": c("#F6C945")})
	var s := Geo.sphere(self, Vector3(0, -40, 0), 600.0, m, Vector3.ONE, 48)
	s.set_meta("nohull", true)
	# Sterne als Halo-Scheiben, eine grosse Mondscheibe
	var hm := Geo.mat(HALO_SHADER, {"energy": 1.5})
	var stars := [
		[Vector3(-120, 95, -300), 46.0], [Vector3(-30, 125, -320), 36.0], [Vector3(70, 105, -310), 52.0],
		[Vector3(150, 80, -280), 34.0], [Vector3(-200, 70, -260), 30.0], [Vector3(20, 170, -280), 28.0],
		[Vector3(110, 150, -260), 24.0], [Vector3(-80, 175, -250), 22.0], [Vector3(200, 130, -240), 26.0],
		[Vector3(-160, 140, -230), 20.0], [Vector3(60, 60, -340), 24.0], [Vector3(-40, 80, -330), 20.0],
		[Vector3(0, 210, -220), 18.0], [Vector3(-260, 110, -200), 22.0], [Vector3(250, 90, -210), 20.0],
	]
	var i := 0
	for st in stars:
		var q := Geo.quad(self, st[0], Vector2(st[1], st[1]), Geo.clone(hm, {"seed": float(i)*1.7, "rings": 4.0 + float(i % 3)}))
		q.set_meta("nohull", true)
		i += 1
	var moon := Geo.quad(self, Vector3(-230, 170, -200), Vector2(110, 110), Geo.clone(hm, {"seed": 5.5, "rings": 7.0, "energy": 1.25, "core": c("#FFF8D6"), "yellow": c("#F9D55A"), "rim": c("#C98A2E")}))
	moon.set_meta("nohull", true)

func _ground() -> void:
	# Pflaster: Striche konzentrisch um die Cafeterrasse (Zentrum x=9, z=-17), Kobalt/Ocker.
	var gm := imp("#3A4D7A", "#2E3F6E", "#B88A3C", {"accent": 0.22, "len": 0.9, "wid": 0.16, "bump": 0.8, "center_mode": 1, "center": Vector2(9.0, -17.0), "rough": 0.45})
	var g := Geo.plane(self, Vector3(0, 0, -8), Vector2(120, 120), gm)
	g.set_meta("nohull", true)

func _house(pos: Vector3, size: Vector3, wall: ShaderMaterial, roof_col: String, floors: int, win_m: ShaderMaterial, facing_x: float) -> void:
	Geo.box(self, pos + Vector3(0, size.y/2, 0), size, wall)
	# Dach: flacher Walm als Keil (Box, gedreht), Strich laengs der Dachneigung
	var roof := imp(roof_col, "#6E4A3C", "#2A2A55", {"angle": 0.0, "len": 0.6, "wid": 0.12, "accent": 0.15})
	Geo.box(self, pos + Vector3(0, size.y + 0.5, 0), Vector3(size.x + 0.5, 1.0, size.z + 0.5), roof)
	Geo.box(self, pos + Vector3(0, size.y + 1.3, 0), Vector3(size.x * 0.6, 0.7, size.z * 0.8), roof)
	# Fenster: leuchtende Boxen an der Strassenseite
	var fh := size.y / float(floors)
	var nw: int = max(1, int(size.z / 2.4))
	for f in floors:
		for w in nw:
			if rng.randf() < 0.3:
				continue
			var z: float = pos.z - size.z/2 + (float(w) + 0.5) * size.z / float(nw)
			var y := fh * (float(f) + 0.55)
			if f == 0:
				y = 1.9
			Geo.box(self, Vector3(pos.x + facing_x * (size.x/2 + 0.04), y, z), Vector3(0.08, 1.1, 0.7), win_m)

func _buildings() -> void:
	var win := imp("#F6C945", "#F3B33A", "#FFF1B0", {"accent": 0.3, "len": 0.25, "wid": 0.07, "emit": 1.4, "angle": 1.5708})
	var walls := [
		imp("#4B4A86", "#3C3B72", "#8A86C4", {"accent": 0.12, "angle": 0.2, "len": 0.8}),
		imp("#B88A3C", "#9C7030", "#E0B45A", {"accent": 0.15, "angle": -0.15, "len": 0.7}),
		imp("#5A6FA8", "#45598E", "#9FB6E0", {"accent": 0.1, "angle": 0.1, "len": 0.9}),
		imp("#8E6B5A", "#73554A", "#C79A7A", {"accent": 0.12, "angle": 0.0, "len": 0.75}),
		imp("#3F5F7A", "#2F4A62", "#7FA8C0", {"accent": 0.1, "angle": 0.3, "len": 0.8}),
	]
	var roofs := ["#7A3F3A", "#5A4E8E", "#8E5A3A", "#4A4A7A"]
	# Strasse: Haeuser links (x<0) und rechts (x>0) von z=18 bis z=-10
	for side: float in [-1.0, 1.0]:
		var z := 18.0
		var i := 0
		while z > -9.0:
			var depth := rng.randf_range(5.0, 8.0)
			var h := rng.randf_range(7.0, 11.5)
			var w := rng.randf_range(5.0, 7.0)
			var x: float = side * (4.6 + w/2)
			_house(Vector3(x, 0, z - depth/2), Vector3(w, h, depth), walls[(i + int(side > 0) * 2) % walls.size()], roofs[i % roofs.size()], 2 + int(h > 9.5), win, -side)
			z -= depth + 0.3
			i += 1
	# Haeuserwand um den Platz (hinten und seitlich, hoeher, weiter weg)
	for k in 6:
		var x := -16.0 + k * 6.4
		if abs(x) < 3.5:
			continue
		var h := rng.randf_range(8.0, 13.0)
		_house(Vector3(x, 0, -34.0), Vector3(6.0, h, 7.0), walls[k % walls.size()], roofs[k % roofs.size()], 3, win, 0.0)
	# Fernsilhouette: dunkle Daecher und ein Turm
	var dark := imp("#1E2650", "#161C40", "#2C3570", {"accent": 0.05, "len": 1.2})
	for k in 14:
		var x := -60.0 + k * 9.0 + rng.randf_range(-2, 2)
		var h := rng.randf_range(10.0, 22.0)
		Geo.box(self, Vector3(x, h/2, -60.0 - rng.randf_range(0, 15)), Vector3(7.0, h, 7.0), dark)
	Geo.cylinder(self, Vector3(22, 14, -62), 2.2, 2.6, 28.0, dark, 10)
	Geo.cylinder(self, Vector3(22, 30, -62), 0.0, 2.6, 4.0, dark, 10)

func _square() -> void:
	# Cafe an der Ostseite des Platzes: gelbe Wand unter der Markise, Lampe, Tische.
	var cafe_wall := imp("#F2C14E", "#E8B03C", "#FFE48A", {"accent": 0.25, "len": 0.6, "wid": 0.1, "emit": 0.55, "angle": 0.1})
	var upper := imp("#4B4A86", "#3C3B72", "#8A86C4", {"accent": 0.12, "angle": 0.2})
	Geo.box(self, Vector3(12.5, 2.0, -17.0), Vector3(6.0, 4.0, 12.0), cafe_wall)
	Geo.box(self, Vector3(12.5, 7.0, -17.0), Vector3(6.0, 6.0, 12.0), upper)
	var roof := imp("#7A3F3A", "#6E4A3C", "#2A2A55", {"len": 0.6, "wid": 0.12})
	Geo.box(self, Vector3(12.5, 10.5, -17.0), Vector3(6.6, 1.0, 12.6), roof)
	# Markise: schraeg, gelb, mit Strich laengs
	var awning := imp("#F6C945", "#EFB83A", "#FFF1B0", {"accent": 0.2, "len": 1.4, "wid": 0.12, "emit": 0.35, "angle": 0.0})
	var aw := Geo.box(self, Vector3(8.0, 3.9, -17.0), Vector3(4.2, 0.12, 12.4), awning)
	aw.rotation.z = -0.28
	# Tische und Stuehle
	var table := imp("#E9D9A8", "#D6C48F", "#FFFFFF", {"len": 0.3, "wid": 0.05, "emit": 0.15})
	var chair := imp("#6B4A2E", "#55391F", "#8B6A3A", {"len": 0.25, "wid": 0.05})
	for i in 5:
		var z := -12.0 - i * 2.4
		var x := 8.2 + (i % 2) * 1.6
		Geo.cylinder(self, Vector3(x, 0.72, z), 0.45, 0.45, 0.06, table, 14)
		Geo.cylinder(self, Vector3(x, 0.36, z), 0.04, 0.12, 0.7, chair, 8)
		for s in [-1.0, 1.0]:
			Geo.box(self, Vector3(x + 0.8 * s, 0.45, z), Vector3(0.4, 0.06, 0.4), chair)
			Geo.box(self, Vector3(x + 1.0 * s, 0.7, z), Vector3(0.05, 0.5, 0.4), chair)
	# Gaslaternen: Strasse und Platz
	for z in [12.0, 4.0, -4.0]:
		for sx in [-4.3, 4.3]:
			_lamp(Vector3(sx, 0, z))
	_lamp(Vector3(6.6, 0, -12.5), 4.2)
	_lamp(Vector3(6.6, 0, -22.0), 4.2)
	_lamp(Vector3(-7.0, 0, -28.0))
	# Zypressen: Flammenform aus gestapelten Ellipsoiden, Strich steil nach oben gedreht
	var cyp := imp("#102520", "#1E3F30", "#2E5A3E", {"accent": 0.1, "angle": 1.35, "len": 0.9, "wid": 0.12, "bump": 0.9, "rough": 0.7})
	for cz in [[-9.5, -14.0, 10.5], [-11.5, -21.0, 13.0], [-8.0, -27.5, 9.0]]:
		_cypress(Vector3(cz[0], 0, cz[1]), cz[2], cyp)
	# U-Bahn-Ausgang in der Platzrueckwand: gruenes gefuelltes Portal, Rahmen, Schild
	var frame := imp("#2A2A55", "#1E1E44", "#3E3E7A", {"len": 0.4, "wid": 0.08})
	Geo.box(self, Vector3(0, 2.4, -30.6), Vector3(4.6, 4.8, 1.2), frame)
	var portal := Geo.quad(self, Vector3(0, 1.9, -29.95), Vector2(3.2, 3.8), Geo.mat(METRO_SHADER, {"col": c("#39FF6A")}))
	portal.set_meta("nohull", true)
	var lbl := Label3D.new()
	lbl.text = "MÉTRO"
	lbl.font_size = 140
	lbl.pixel_size = 0.006
	lbl.modulate = c("#39FF6A")
	lbl.outline_modulate = c("#0B2A14")
	lbl.outline_size = 24
	lbl.position = Vector3(0, 4.3, -29.9)
	add_child(lbl)
	var ml := OmniLight3D.new()
	ml.light_color = c("#39FF6A")
	ml.light_energy = 2.2
	ml.omni_range = 9.0
	ml.position = Vector3(0, 2.2, -28.5)
	add_child(ml)

func _cypress(pos: Vector3, h: float, m: ShaderMaterial) -> void:
	var trunk := imp("#2A1E14", "#1E140C", "#3A2A1A", {"len": 0.5, "wid": 0.06})
	Geo.cylinder(self, pos + Vector3(0, 0.6, 0), 0.18, 0.25, 1.2, trunk, 8)
	var y := 1.0
	var r := h * 0.16
	var i := 0
	while y < h:
		var rr := r * (1.0 - pow(y / h, 1.6)) + 0.25
		var seg := Geo.sphere(self, pos + Vector3(rng.randf_range(-0.2, 0.2), y + rr * 0.6, rng.randf_range(-0.2, 0.2)), rr, m, Vector3(1.0, 1.9, 1.0), 14)
		seg.rotation.y = rng.randf() * TAU
		seg.rotation.z = rng.randf_range(-0.12, 0.12)
		y += rr * 1.5
		i += 1

func _lamp(pos: Vector3, h := 3.4) -> void:
	var post := imp("#1A2340", "#121A30", "#2A3660", {"len": 0.5, "wid": 0.05})
	Geo.cylinder(self, pos + Vector3(0, h/2, 0), 0.07, 0.12, h, post, 8)
	var glass := imp("#FFE9A0", "#F6C945", "#FFFFFF", {"accent": 0.3, "len": 0.2, "wid": 0.05, "emit": 2.2})
	Geo.box(self, pos + Vector3(0, h + 0.3, 0), Vector3(0.36, 0.5, 0.36), glass)
	Geo.box(self, pos + Vector3(0, h + 0.6, 0), Vector3(0.5, 0.08, 0.5), post)
	var halo := Geo.quad(self, pos + Vector3(0, h + 0.3, 0), Vector2(3.4, 3.4), Geo.mat(HALO_SHADER, {"energy": 1.1, "rings": 6.0, "seed": pos.z, "soft": 0.35, "rim": c("#E8862A")}))
	halo.material_override.set_shader_parameter("core", c("#FFF3B0"))
	halo.set_meta("nohull", true)
	var l := OmniLight3D.new()
	l.light_color = c("#FFC24A")
	l.light_energy = 2.6
	l.omni_range = 13.0
	l.omni_attenuation = 1.3
	l.position = pos + Vector3(0, h + 0.2, 0)
	add_child(l)

func _life() -> void:
	var coat := imp("#1A2340", "#243060", "#3A4A8A", {"len": 0.3, "wid": 0.06, "angle": 1.5708})
	var coat2 := imp("#4A2A2A", "#3A2020", "#7A4A3A", {"len": 0.3, "wid": 0.06, "angle": 1.5708})
	var skin := imp("#D9A066", "#C98A50", "#F0C080", {"len": 0.15, "wid": 0.05})
	var figs := [
		[Vector3(-2.6, 0, 6.0), 0.4], [Vector3(2.9, 0, -2.0), -0.6], [Vector3(7.2, 0, -14.5), 1.6], [Vector3(7.4, 0, -19.0), 1.2],
		[Vector3(-3.5, 0, -16.0), 0.0], [Vector3(2.0, 0, -24.0), 2.4], [Vector3(-1.8, 0, 10.0), 3.0], [Vector3(5.5, 0, -26.0), -1.0],
	]
	var i := 0
	for f in figs:
		Geo.figure(self, f[0], coat if i % 3 != 1 else coat2, skin, f[1])
		i += 1
	# Pferdekarren als Primitive (kein Auto in Arles 1888): Kasten, Raeder, Pferd aus Kapsel
	var wood := imp("#6B4A2E", "#55391F", "#8B6A3A", {"len": 0.5, "wid": 0.08})
	var n := Node3D.new()
	n.position = Vector3(3.0, 0, -8.0)
	n.rotation.y = 0.25
	add_child(n)
	Geo.box(n, Vector3(0, 0.95, 0), Vector3(1.5, 0.7, 2.6), wood)
	for sx in [-0.85, 0.85]:
		var w := Geo.cylinder(n, Vector3(sx, 0.6, 0.6), 0.6, 0.6, 0.12, wood, 14)
		w.rotation.z = PI/2
	var horse := imp("#3A2A20", "#2A1C14", "#5A4030", {"len": 0.4, "wid": 0.08})
	var hb := Geo.sphere(n, Vector3(0, 1.25, -2.6), 0.45, horse, Vector3(1.0, 1.0, 2.0), 14)
	Geo.sphere(n, Vector3(0, 1.9, -3.7), 0.22, horse, Vector3(1.0, 1.4, 1.0), 10)
	for lx in [-0.25, 0.25]:
		for lz in [-2.0, -3.3]:
			Geo.cylinder(n, Vector3(lx, 0.45, lz), 0.06, 0.08, 0.9, horse, 6)

func _pellets() -> void:
	var pts := Geo.pellet_line(Vector3(0, 0.55, 14.0), Vector3(0, 0.55, -28.0), 2.0)
	pts += Geo.pellet_line(Vector3(-2.0, 0.55, -12.0), Vector3(-12.0, 0.55, -12.0), 2.0)
	Geo.pellets(self, pts, 0.24, Geo.mat(ORB_SHADER, {"col": c("#FF4A1C"), "core": c("#FFB088"), "energy": 1.6}))

func views() -> Array:
	return [
		["strasse", Vector3(-0.9, 1.7, 13.0), Vector3(0.6, 3.2, -14.0), 72.0],
		["totale", Vector3(-16.0, 15.0, 22.0), Vector3(2.0, 3.0, -16.0), 64.0],
		["platz", Vector3(-4.0, 1.7, -8.0), Vector3(8.0, 3.5, -22.0), 74.0],
		["capsule", Vector3(1.5, 1.6, 6.0), Vector3(-1.0, 9.0, -20.0), 62.0],
	]

func set_view(pos: Vector3, look: Vector3, fov: float) -> void:
	cam.position = pos
	cam.look_at(look)
	cam.fov = fov
