# Richtung E "Buehnenstadt Shibai-machi" – Stil-Prototyp (Art Director, Phase 1, NICHT Spielcode).
# Die Stadt ist eine Kabuki-Buehne: Hinoki-Buehnenboden statt Asphalt, Hauptstrasse = Hanamichi
# (erhoehter Laufsteg mit Fussrampenlichtern), Haeuser sind gemalte Hiki-dogu-Kulissen (flach,
# gestaffelt, mit roher Sperrholzkante und Stuetzen hinten), dazwischen gestreifte Vorhaenge,
# ueber der Strasse haengende Kirschzweig-Borten (Tsurieda), Papierschnee (Kamiyuki),
# schwarzer Vorhang (Kuromaku = Nacht) als Himmel, Mond an der sichtbaren Stange.
# Platz = Drehbuehne (Mawari-butai). Ausgang = gruen leuchtende Versenkung (Suppon/Seri) mit 出口.
extends Node3D

const Geo := preload("res://geo.gd")

var cam: Camera3D
var rng := RandomNumberGenerator.new()
var font: FontFile
var reduce_fx := false

# Gemalte Kulisse: Textur (in Metern gemappt) oder Flachfarbe, kein Licht – Ton je
# Flaechenrichtung, Helligkeit nimmt nach oben ab (Buehnenlicht von vorn/unten).
const PAINT_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform vec3 col : source_color = vec3(0.9);
uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform float use_tex = 0.0;
uniform vec4 map = vec4(0.0, 0.0, 1.0, 1.0); // uv-Ursprung (x,y) und Groesse (z,w) in Metern
uniform float top_fade = 0.0;   // Abdunkelung nach oben (Buehnenlicht)
uniform float emit = 0.0;
uniform float alpha_cut = 0.0;
uniform float flip_y = 1.0;
varying vec3 wpos; varying vec3 wn;
void vertex(){ wpos = (MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; wn = normalize((MODEL_MATRIX*vec4(NORMAL,0.0)).xyz); }
void fragment(){
	vec3 c = col;
	float a = 1.0;
	if (use_tex > 0.5) {
		vec2 uv = (UV - map.xy) / map.zw;
		if (flip_y > 0.5) uv.y = 1.0 - uv.y;
		vec4 t = texture(tex, uv);
		c = t.rgb * col; a = t.a;
	}
	if (alpha_cut > 0.0 && a < alpha_cut) discard;
	float tone = 1.0;
	if (abs(wn.y) > 0.6) tone = 1.04; else if (abs(wn.x) > abs(wn.z)) tone = 0.95;
	tone *= mix(1.0, 0.55, clamp((wpos.y - 4.5) / 9.0, 0.0, 1.0) * top_fade);
	ALBEDO = c * tone * (1.0 + emit);
}
"""

# Rohe Schnittkante der Kulissen: Sperrholz-Schichten (helles Holz mit dunklen Lagen).
const PLY_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform vec3 col : source_color = vec3(0.86, 0.74, 0.55);
void fragment(){
	float v = UV.y;
	float layer = step(0.5, fract(v * 5.0));
	vec3 c = mix(col, col * 0.78, layer * 0.6);
	c *= 0.92 + 0.08 * sin(UV.x * 37.0);
	ALBEDO = c;
}
"""

# Hinoki-Buehnenboden: Dielen entlang z, Fugen, Maserung, leichte Farbstreuung.
const FLOOR_SHADER := """
shader_type spatial;
render_mode unshaded;
uniform vec3 col : source_color = vec3(0.85, 0.72, 0.52);
uniform vec3 seam : source_color = vec3(0.36, 0.25, 0.16);
uniform float plank = 0.3;
varying vec3 wpos;
float h11(float x){ return fract(sin(x * 127.1) * 43758.5453); }
void vertex(){ wpos = (MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; }
void fragment(){
	float px = wpos.x / plank;
	float id = floor(px);
	float f = fract(px);
	float zlen = 3.6 + h11(id) * 2.0;
	float zid = floor((wpos.z + h11(id + 3.0) * 5.0) / zlen);
	vec3 c = col * (0.88 + 0.16 * h11(id * 7.0 + zid * 13.0));
	float grain = sin(wpos.z * 9.0 + sin(wpos.z * 0.7 + id) * 3.0 + f * 6.0);
	c *= 0.95 + 0.05 * grain;
	float s = smoothstep(0.0, 0.04, f) * smoothstep(1.0, 0.96, f);
	float e = abs(fract((wpos.z + h11(id + 3.0) * 5.0) / zlen) - 0.5) * 2.0;
	s *= smoothstep(1.0, 0.985, e);
	float d = length(wpos - CAMERA_POSITION_WORLD);
	c = mix(seam, c, mix(s, 1.0, smoothstep(18.0, 45.0, d) * 0.85));
	ALBEDO = c;
}
"""

# Joshiki-maku: senkrechte Streifen Schwarz / Kaki / Moegi (gedeckt), Falten ueber Sinus.
const CURTAIN_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform vec3 c1 : source_color = vec3(0.08);
uniform vec3 c2 : source_color = vec3(0.70, 0.33, 0.16);
uniform vec3 c3 : source_color = vec3(0.27, 0.38, 0.25);
uniform float stripe = 0.9;
uniform float fold = 0.45;
varying vec3 wpos;
void vertex(){
	wpos = (MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
}
void fragment(){
	float u = UV.x * stripe;
	float k = mod(floor(u), 3.0);
	vec3 c = k < 0.5 ? c1 : (k < 1.5 ? c2 : c3);
	float f = sin(UV.x * stripe * 6.2831 * 2.0);
	c *= 0.80 + 0.2 * (f * 0.5 + 0.5);
	c *= mix(1.0, 0.6, clamp((wpos.y - 4.0) / 8.0, 0.0, 1.0));
	ALBEDO = c;
}
"""

# Kuromaku: schwarzer Samtvorhang rundum (= Nacht auf der Kabuki-Buehne), weiche Falten.
const KURO_SHADER := """
shader_type spatial;
render_mode unshaded, cull_front, fog_disabled;
varying vec3 lp;
void vertex(){ lp = VERTEX; }
void fragment(){
	float a = atan(lp.x, lp.z);
	float f = sin(a * 160.0) * 0.5 + 0.5;
	f = pow(f, 3.0);
	float h = clamp(lp.y / 60.0 + 0.5, 0.0, 1.0);
	vec3 c = vec3(0.055, 0.045, 0.045) + vec3(0.05, 0.04, 0.035) * f * (1.0 - h);
	ALBEDO = c;
}
"""

const ORB_SHADER := """
shader_type spatial;
render_mode unshaded, fog_disabled;
uniform vec3 col : source_color = vec3(1.0, 0.78, 0.16);
uniform vec3 core : source_color = vec3(1.0, 0.96, 0.78);
void fragment(){
	float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	ALBEDO = mix(col, core, smoothstep(0.6, 0.95, ndv)) * 1.15;
}
"""

# Ausgang: gruen leuchtende Versenkung, 0,5-Hz-Puls (bei "Effekte reduzieren" konstant).
const EXIT_SHADER := """
shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled;
uniform vec3 col : source_color = vec3(0.16, 0.89, 0.42);
uniform float pulse = 1.0;
void fragment(){ ALBEDO = col * (0.92 + 0.08 * sin(TIME * 3.14159) * pulse); }
"""

# Lichtsaeule ueber der Versenkung: additiv, nach oben auslaufend.
const BEAM_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, fog_disabled;
uniform vec3 col : source_color = vec3(0.16, 0.89, 0.42);
void fragment(){
	float edge = 1.0 - abs(UV.x - 0.5) * 2.0;
	ALBEDO = col * pow(1.0 - UV.y, 0.0) * 0.0 + col * smoothstep(0.0, 0.6, edge) * (UV.y) * 0.55;
}
"""

# Papierschnee / Kirschblaetter (Kamiyuki): Quads fallen und taumeln im Vertex-Shader.
# speed = 0 bei "Effekte reduzieren" (stehen in der Luft – oder ganz ausblenden).
const FLAKE_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform float speed = 1.0;
uniform float height = 12.0;
uniform vec3 col_a : source_color = vec3(0.98, 0.96, 0.92);
uniform vec3 col_b : source_color = vec3(0.95, 0.72, 0.78);
uniform float mix_b = 0.0;
varying float seedv;
void vertex(){
	float seed = INSTANCE_CUSTOM.x;
	seedv = seed;
	float t = TIME * speed * (0.5 + seed * 0.4);
	float fall = mod(t + seed * height, height);
	vec3 o = MODEL_MATRIX[3].xyz;
	float ang = t * 2.0 + seed * 40.0;
	mat3 r = mat3(vec3(cos(ang), sin(ang), 0.0), vec3(-sin(ang), cos(ang), 0.0), vec3(0.0, 0.0, 1.0));
	vec3 v = r * VERTEX;
	v.x += sin(t * 1.3 + seed * 9.0) * 0.4;
	v.y -= fall;
	VERTEX = v;
}
void fragment(){ ALBEDO = (fract(seedv * 13.7) < mix_b) ? col_b : col_a; }
"""

const PAL := {
	"sumi": "#1A1714", "gofun": "#F2ECE0", "hinoki": "#D9B884", "wood": "#6B4A2E", "wood_d": "#3B281A",
	"kaki": "#B4542A", "moegi": "#3A5034", "ai": "#2B3A67", "asagi": "#5E8FA8", "beni": "#C1272D",
	"sakura": "#F2B8C6", "roof": "#3A3A42", "ply": "#DBBD8C", "kuroko": "#141112",
	"kugel": "#FFC629", "kugelkern": "#FFF4C8", "ausgang": "#29E36B",
}
func c(k: String) -> Color: return Color.html(PAL.get(k, k))

var ply_m: ShaderMaterial

func paint(k: String, params := {}) -> ShaderMaterial:
	var p := {"col": c(k)}
	p.merge(params, true)
	return Geo.mat(PAINT_SHADER, p)

func quad_tex(file: String, params := {}) -> ShaderMaterial:
	var p := {"map": Vector4(0, 0, 1, 1), "flip_y": 0.0}
	p.merge(params, true)
	return paint_tex(file, Vector4(0, 0, 1, 1), p)

func paint_tex(file: String, map: Vector4, params := {}) -> ShaderMaterial:
	var p := {"col": Color.WHITE, "tex": Geo.tex("res://prints/" + file), "use_tex": 1.0, "map": map}
	p.merge(params, true)
	return Geo.mat(PAINT_SHADER, p)

func _ready() -> void:
	rng.seed = 1603
	reduce_fx = OS.get_environment("REDUCE_FX") == "1"
	font = FontFile.new()
	font.load_dynamic_font(ProjectSettings.globalize_path("res://fonts/NotoSerifJP-Black-Subset.otf"))
	cam = Camera3D.new()
	cam.near = 0.1
	cam.far = 600.0
	add_child(cam)
	cam.current = true
	ply_m = Geo.mat(PLY_SHADER, {"col": c("ply")})
	_environment()
	_sky()
	_floor()
	_hanamichi()
	_street()
	_borders()
	_plaza()
	_life()
	_flakes()
	_pellets()

func _environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.025, 0.025)
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.fog_enabled = true
	env.fog_light_color = Color(0.04, 0.03, 0.03)
	env.fog_density = 0.012
	env.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

func _sky() -> void:
	var cyl := Geo.cylinder(self, Vector3(0, 20, -20), 95.0, 95.0, 80.0, Geo.mat(KURO_SHADER), 96)
	cyl.mesh.cap_top = true
	# Mond: Papierscheibe an sichtbarer Stange (Buehnen-Mond, keine Illusion)
	var moon := Geo.extrude(self, Geo.circle_poly(4.0, 48, Vector2(0, 4.0)), 0.15, paint("#F4EBD2", {"emit": 0.05}), ply_m,
		Vector3(-14, 21, -70))
	Geo.cylinder(self, Vector3(-14, 34, -70), 0.06, 0.06, 18.0, paint("sumi"), 6)

func _floor() -> void:
	Geo.plane(self, Vector3(0, 0, -20), Vector2(190, 190), Geo.mat(FLOOR_SHADER, {"col": c("hinoki")}))
	# Fuehrungsschienen der Schiebekulissen (Hiki-dogu) im Boden
	var rail := paint("wood_d")
	for sx in [-1.0, 1.0]:
		for off in [0.0, 0.5]:
			Geo.box(self, Vector3(sx * (5.05 + off), 0.005, -6.0), Vector3(0.05, 0.012, 50.0), rail)

func _hanamichi() -> void:
	# erhoehter Laufsteg (20 cm) entlang der Hauptachse, Seiten dunkel, Fussrampenlichter = Kante
	var top := Geo.mat(FLOOR_SHADER, {"col": Color.html("#E3C895"), "plank": 0.22})
	Geo.box(self, Vector3(0, 0.1, -6.0), Vector3(2.0, 0.2, 48.0), top)
	var side := paint("wood_d")
	for sx in [-1.0, 1.0]:
		Geo.box(self, Vector3(sx * 1.02, 0.1, -6.0), Vector3(0.04, 0.2, 48.0), side)
	var lamp := paint("#FFE9B8", {"emit": 0.6})
	for k in 24:
		for sx in [-1.0, 1.0]:
			Geo.box(self, Vector3(sx * 1.06, 0.1, 17.0 - k * 2.0), Vector3(0.05, 0.08, 0.5), lamp)
	# Schild am Anfang
	var q := Geo.quad(self, Vector3(-3.1, 1.75, 10.5), Vector2(1.6, 0.5), quad_tex("schild_hanamichi.png"))
	q.rotation.y = 0.45
	Geo.cylinder(self, Vector3(-3.1, 0.75, 10.5), 0.04, 0.04, 1.5, paint("wood_d"), 6)

# Eine Kulisse (Hiki-dogu): flacher Ausschnitt mit gemalter Fassade, Dachprofil darueber,
# rohe Sperrholzkante, hinten zwei Stuetzen (Shiki). Seite sx: -1 links, +1 rechts.
func _flat(sx: float, zc: float, w: float, hgt: float, tex_file: String, x_off: float) -> void:
	var x := sx * (5.4 + x_off)
	var rot := Vector3(0, sx * -PI / 2.0, 0)  # Vorderseite zur Strasse
	var face := paint_tex(tex_file, Vector4(-w / 2.0, 0.0, w, hgt), {"top_fade": 1.0})
	Geo.extrude(self, Geo.rect_poly(w, hgt), 0.12, face, ply_m, Vector3(x, 0, zc), rot, paint("ply"))
	# Dach-Ausschnitt: geschwungenes Profil mit Ueberstand
	var roof := PackedVector2Array()
	var rw := w + 0.9
	roof.append(Vector2(-rw / 2.0, 0.0))
	for i in 13:
		var t := float(i) / 12.0
		var xx := -rw / 2.0 + t * rw
		roof.append(Vector2(xx, 0.0) if i == 0 else Vector2(xx, 0.0))
	roof = PackedVector2Array([Vector2(-rw / 2.0, 0.0), Vector2(rw / 2.0, 0.0), Vector2(rw / 2.0 - 0.25, 0.45)])
	for i in 11:
		var t := float(i) / 10.0
		var xx := rw / 2.0 - 0.6 - t * (rw - 1.2)
		var yy := 1.5 - 0.35 * pow(abs(t - 0.5) * 2.0, 2.0)
		roof.append(Vector2(xx, yy))
	roof.append(Vector2(-rw / 2.0 + 0.25, 0.45))
	var rm := paint_tex("dach.png", Vector4(-rw / 2.0, 0.0, 4.0, 2.0), {"top_fade": 1.0})
	rm.set_shader_parameter("map", Vector4(0, 0, 4.0, 2.0))
	Geo.extrude(self, roof, 0.14, rm, ply_m, Vector3(x - sx * 0.25, hgt - 0.1, zc), rot)
	Geo.box(self, Vector3(x - sx * 0.3, hgt + 1.46, zc), Vector3(0.22, 0.14, w * 0.75), paint("sumi"))
	# Stuetzen hinter der Kulisse (sichtbar in der Totale)
	var st := ply_m
	for dz in [-w * 0.3, w * 0.3]:
		var b := Geo.box(self, Vector3(x + sx * 1.0, hgt * 0.4, zc + dz), Vector3(0.08, hgt * 0.95, 0.16), paint("ply"))
		b.rotation.z = sx * 0.42
		Geo.box(self, Vector3(x + sx * 1.6, 0.1, zc + dz), Vector3(0.4, 0.2, 0.3), paint("wood_d"))  # Gewicht
	# Laternen unter dem Vordach (paarweise, Papier mit 大入)
	for dz in [-w * 0.32, w * 0.32]:
		var lp := Vector3(x - sx * 0.8, 4.35, zc + dz)
		var lm := quad_tex("laterne.png", {"emit": 0.25})
		Geo.sphere(self, lp, 0.5, lm, Vector3(0.62, 1.0, 0.62), 20)
		Geo.cylinder(self, lp + Vector3(0, 0.55, 0), 0.02, 0.02, 0.4, paint("sumi"), 4)

func _curtain(sx: float, zc: float, w: float, hgt: float) -> void:
	# Joshiki-maku zwischen den Kulissen, leicht zurueckgesetzt
	var x := sx * 6.0
	var q := Geo.quad(self, Vector3(x, hgt / 2.0, zc), Vector2(w, hgt), Geo.mat(CURTAIN_SHADER,
		{"c1": c("sumi"), "c2": c("kaki"), "c3": c("moegi"), "stripe": 3.0}))
	q.rotation.y = sx * -PI / 2.0
	Geo.box(self, Vector3(x, hgt + 0.05, zc), Vector3(0.1, 0.1, w + 0.3), paint("wood_d"))

func _street() -> void:
	# links und rechts: Kulisse – Vorhang – Kulisse ..., gestaffelt (x_off), bis zum Platz bei z = -26
	var houses := ["haus_a.png", "haus_b.png", "haus_c.png"]
	var z := 18.0
	var i := 0
	while z > -24.0:
		for sx in [-1.0, 1.0]:
			var w := 7.0
			var hgt := 5.6
			var hf: String = houses[(i + (1 if sx > 0 else 0)) % 3]
			_flat(sx, z - w / 2.0, w, hgt, hf, 0.35 * float((i + (1 if sx > 0 else 0)) % 2))
			_curtain(sx, z - w - 1.1, 2.2, 6.4)
		z -= 9.2
		i += 1
	# zweite und dritte Kulissenreihe dahinter (Stadt in Ebenen gestaffelt, hoeher und dunkler)
	for row in [[9.0, 7.2, 0.8], [14.5, 8.6, 0.65]]:
		var zz := 16.0
		var j := 0
		while zz > -22.0:
			for sx in [-1.0, 1.0]:
				_flat(sx, zz - 4.0, 8.0, row[1], houses[(j + 2) % 3], row[0] - 5.4 + 0.6 * float(j % 2))
			zz -= 10.0
			j += 1
	# Nobori-Fahnen an der Bordkante: Held (rot) / Gegenspieler (blau) im Wechsel
	var held := quad_tex("fahne_held.png")
	var gegen := quad_tex("fahne_gegen.png")
	var pole := paint("sumi")
	var k := 0
	for fz in [11.0, 2.0, -7.0, -16.0]:
		for sx in [-1.0, 1.0]:
			var m: ShaderMaterial = held if (k % 2 == 0) else gegen
			var q := Geo.quad(self, Vector3(sx * 4.2, 3.0, fz), Vector2(0.9, 3.2), m)
			q.rotation.y = sx * -PI / 2.0 + sx * 0.35
			Geo.cylinder(self, Vector3(sx * 4.2, 2.3, fz - sx * 0.0), 0.04, 0.04, 4.6, pole, 6)
			k += 1

func _borders() -> void:
	# Tsurieda: haengende Kirschzweig-Borten quer ueber der Strasse (wie Buehnen-Soffitten)
	var m := quad_tex("tsurieda.png", {"alpha_cut": 0.5})
	for z in [9.0, 0.0, -9.0, -18.0]:
		Geo.quad(self, Vector3(0, 8.2, z), Vector2(12.0, 6.0), m)
		Geo.box(self, Vector3(0, 11.2, z), Vector3(13.0, 0.12, 0.12), paint("wood_d"))

func _plaza() -> void:
	# Drehbuehne (Mawari-butai): runde Bodenscheibe mit Fuge, darauf eine zweiseitige Kulisse.
	var cz := -40.0
	var ring := Geo.cylinder(self, Vector3(0, 0.02, cz), 11.0, 11.0, 0.04, paint("wood_d"), 96)
	Geo.cylinder(self, Vector3(0, 0.04, cz), 10.85, 10.85, 0.04, Geo.mat(FLOOR_SHADER, {"col": Color.html("#D2B07A"), "plank": 0.36}), 96)
	# Seitenkulissen des Platzes: Vorhang links/rechts (breit)
	for sx in [-1.0, 1.0]:
		var q := Geo.quad(self, Vector3(sx * 14.0, 4.5, cz + 2.0), Vector2(26.0, 9.0), Geo.mat(CURTAIN_SHADER,
			{"c1": c("sumi"), "c2": c("kaki"), "c3": c("moegi"), "stripe": 30.0}))
		q.rotation.y = sx * -PI / 2.0
	# gemalter Prospekt hinten
	var bd := Geo.quad(self, Vector3(0, 6.0, -58.0), Vector2(36.0, 13.5), quad_tex("prospekt.png"))
	# Drehbuehnen-Aufbau: verschneite Kiefer als Ausschnitt (eigene Form) + Steinlaterne
	var pine := PackedVector2Array([Vector2(-0.35, 0), Vector2(0.35, 0), Vector2(0.4, 3.0), Vector2(2.6, 3.2), Vector2(3.4, 3.9),
		Vector2(1.6, 4.1), Vector2(0.9, 4.6), Vector2(2.9, 5.0), Vector2(3.5, 5.6), Vector2(1.3, 5.8), Vector2(0.4, 6.6),
		Vector2(1.8, 7.0), Vector2(1.0, 7.8), Vector2(-0.6, 7.6), Vector2(-1.9, 7.0), Vector2(-0.9, 6.5), Vector2(-3.2, 5.9),
		Vector2(-2.4, 5.2), Vector2(-0.6, 5.0), Vector2(-3.6, 4.2), Vector2(-2.9, 3.5), Vector2(-0.45, 3.4)])
	Geo.extrude(self, pine, 0.14, paint("#24302A"), ply_m, Vector3(5.5, 0, cz - 4.0), Vector3(0, -0.3, 0))
	# Schnee auf den Aesten: zweiter, heller Ausschnitt davor
	for sp in [[Vector2(2.6, 3.25), 1.6], [Vector2(2.9, 5.05), 1.4], [Vector2(-2.9, 4.25), 1.5], [Vector2(-2.6, 5.95), 1.4], [Vector2(0.6, 7.75), 1.2]]:
		var p: Vector2 = sp[0]
		var w: float = sp[1]
		var snow := PackedVector2Array([Vector2(-w / 2, 0), Vector2(w / 2, 0), Vector2(w / 2 - 0.2, 0.28), Vector2(0, 0.38), Vector2(-w / 2 + 0.2, 0.26)])
		var sn := Geo.extrude(self, snow, 0.16, paint("gofun"), ply_m, Vector3(0, 0, 0), Vector3.ZERO)
		sn.position = Vector3(5.5, 0, cz - 4.0) + Basis(Vector3.UP, -0.3) * Vector3(p.x - (0.6 if p.x > 0 else -0.6), p.y - 0.05, 0.05)
		sn.rotation.y = -0.3
	# zweiseitiges Teehaus-Kulissenhaus links auf der Drehbuehne (Rueckseite sichtbar: Stuetzen)
	_flat(-1.0, cz - 1.0, 6.0, 5.0, "haus_b.png", -0.9 + 0.0)
	# Ausgang: Versenkung (Suppon) im Hanamichi-Ende, gruen leuchtend, Lichtsaeule + Schild 出口
	var ez := -31.0
	var pulse := 0.0 if reduce_fx else 1.0
	Geo.box(self, Vector3(0, 0.03, ez), Vector3(2.0, 0.06, 2.0), Geo.mat(EXIT_SHADER, {"col": c("ausgang"), "pulse": pulse}))
	for sx in [-1.0, 1.0]:
		Geo.box(self, Vector3(sx * 1.08, 0.08, ez), Vector3(0.16, 0.16, 2.3), paint("sumi"))
		Geo.box(self, Vector3(0, 0.08, ez + sx * 1.08), Vector3(2.3, 0.16, 0.16), paint("sumi"))
	for r in 4:
		var bq := Geo.quad(self, Vector3(0, 3.0, ez), Vector2(2.0, 6.0), Geo.mat(BEAM_SHADER, {"col": c("ausgang")}))
		bq.rotation.y = float(r) * PI / 4.0
	# haengende Tafel 出口 ueber der Versenkung, an zwei Schnueren
	var sign := Geo.quad(self, Vector3(0, 6.6, ez), Vector2(3.2, 1.6), Geo.mat(EXIT_SHADER + "", {"col": Color.WHITE}))
	sign.material_override = quad_tex("ausgang.png", {"emit": 0.15})
	sign.material_override.set_shader_parameter("col", Color(1, 1, 1))
	for sx in [-1.0, 1.0]:
		Geo.cylinder(self, Vector3(sx * 1.4, 9.5, ez), 0.015, 0.015, 4.2, paint("sumi"), 4)

func _life() -> void:
	# Kuroko (Buehnenhelfer in Schwarz – nach Konvention "unsichtbar"): dunkelste Werte der Szene
	var kur := paint("kuroko")
	var veil := paint("#221D1E")
	for f in [[Vector3(-3.6, 0, 7.0), 0.4], [Vector3(3.4, 0, -3.0), -2.6], [Vector3(-3.2, 0, -14.0), 1.2], [Vector3(4.0, 0, -36.0), 2.0], [Vector3(-6.0, 0, -42.0), 0.9]]:
		var n := Geo.figure(self, f[0], kur, veil, f[1])
		Geo.box(n, Vector3(0, 1.48, 0.12), Vector3(0.3, 0.32, 0.02), veil)  # Schleier
	# Darsteller als bemalte Ausschnitt-Figuren in Mie-Pose (eigene Silhouetten): Held rot, Gegenspieler blau
	var pose := PackedVector2Array([Vector2(-0.35, 0), Vector2(-0.1, 0), Vector2(0.0, 0.7), Vector2(0.15, 0), Vector2(0.75, 0),
		Vector2(0.4, 0.8), Vector2(0.35, 1.25), Vector2(1.1, 1.65), Vector2(1.2, 1.9), Vector2(0.25, 1.6), Vector2(0.18, 1.85),
		Vector2(0.28, 2.0), Vector2(0.18, 2.25), Vector2(-0.1, 2.3), Vector2(-0.25, 2.1), Vector2(-0.2, 1.85), Vector2(-0.35, 1.6),
		Vector2(-1.0, 2.0), Vector2(-1.1, 1.75), Vector2(-0.4, 1.25), Vector2(-0.5, 0.7)])
	var hero := paint("#F2ECE0")
	var heroc := paint("beni")
	Geo.extrude(self, pose, 0.08, hero, ply_m, Vector3(-5.0, 0, -36.0), Vector3(0, 0.5, 0))
	Geo.extrude(self, pose, 0.08, paint("ai"), ply_m, Vector3(4.6, 0, -38.0), Vector3(0, -0.5, 0))
	# Kostuemband
	var belt := PackedVector2Array([Vector2(-0.42, 1.05), Vector2(0.42, 1.05), Vector2(0.4, 1.25), Vector2(-0.4, 1.25)])
	Geo.extrude(self, belt, 0.1, heroc, ply_m, Vector3(-5.0, 0, -36.0) + Basis(Vector3.UP, 0.5) * Vector3(0, 0, 0.03), Vector3(0, 0.5, 0))

func _flakes() -> void:
	# Papierschnee + Kirschblaetter (MultiMesh, im Shader animiert)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	var q := QuadMesh.new()
	q.size = Vector2(0.09, 0.09)
	mm.mesh = q
	mm.instance_count = 900
	for i in mm.instance_count:
		var p := Vector3(rng.randf_range(-9, 9), 12.0, rng.randf_range(-48, 18))
		mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, rng.randf() * TAU), p))
		mm.set_instance_custom_data(i, Color(rng.randf(), 0, 0, 0))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = Geo.mat(FLAKE_SHADER, {"speed": 0.0 if reduce_fx else 0.6, "mix_b": 0.55})
	mmi.extra_cull_margin = 40.0
	add_child(mmi)

func _pellets() -> void:
	var pts := Geo.pellet_line(Vector3(0, 0.55, 16.0), Vector3(0, 0.55, -28.0), 2.0)
	Geo.pellets(self, pts, 0.25, Geo.mat(ORB_SHADER, {"col": c("kugel"), "core": c("kugelkern")}))

func views() -> Array:
	return [
		["strasse", Vector3(0.0, 1.9, 17.0), Vector3(0.0, 3.6, -40.0), 70.0],
		["totale", Vector3(17.0, 21.0, 26.0), Vector3(0.0, 1.0, -18.0), 56.0],
		["ausgang", Vector3(-2.6, 1.9, -22.0), Vector3(0.6, 2.6, -40.0), 72.0],
		["capsule", Vector3(0.0, 1.8, 5.0), Vector3(0.0, 4.8, -40.0), 62.0],
	]

func set_view(pos: Vector3, look: Vector3, fov: float) -> void:
	cam.position = pos
	cam.look_at(look)
	cam.fov = fov
