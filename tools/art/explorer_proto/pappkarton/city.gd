# Richtung F "Pappstadt Danboru-cho" – Stil-Prototyp (Art Director, Phase 1, NICHT Spielcode).
# Die Stadt ist aus brauner Wellpappe gebaut wie aus Versandkartons: Haeuser sind Kartons mit
# offenen Laschen als Vordaecher, Klebeband, Tackerklammern, Druckreste (eigene Piktogramme,
# 天地無用 usw.), aufgeklebte Fenster mit sichtbarer Wellen-Schnittkante. Kabuki in Pappe
# uebersetzt: Vorhangstreifen mit Plakatfarbe auf Pappe, Darsteller als Aufsteller mit
# Marker-Gesicht und Stuetze hinten, Laternen aus gerollter Pappe, Drehbuehne als Pappscheibe
# mit Musterbeutelklammer. Ausgang = gruen gestrichener Karton mit offener Klapptuer.
# Echtes Licht (eine Sonne + Schatten) – Pappe lebt von Kanten und Schatten.
extends Node3D

const Geo := preload("res://geo.gd")

var cam: Camera3D
var rng := RandomNumberGenerator.new()
var reduce_fx := false
var sun: DirectionalLight3D

# Wellpappe: Deckpapier (Liner) mit Fasern, durchscheinenden Wellen und Plakatfarbe;
# Schnittkanten mit Wellen zwischen zwei Linern.
# mode 0: Box in lokalen Koordinaten (thin_axis = Dicke-Achse; -1 = geschlossener Karton, nur Liner)
# mode 1: nur Liner (UV in Metern) · mode 2: Schnittkante ueber UV (x = Laenge, y = 0..1 ueber Dicke)
const CARD_SHADER := """
shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_schlick_ggx;
uniform vec3 kraft : source_color = vec3(0.72, 0.53, 0.32);
uniform vec3 paint_col : source_color = vec3(1.0);
uniform float paint = 0.0;        // Deckung der Plakatfarbe 0..1
uniform float paint_stripes = 0.0; // >0: Streifen (Vorhang) – Breite in m, 3 Farben
uniform vec3 stripe2 : source_color = vec3(0.70, 0.33, 0.16);
uniform int mode = 0;
uniform int thin_axis = -1;
uniform float thick = 0.3;
uniform float pitch = 0.16;
uniform float tele_axis = 0.0;    // 0: Wellen laufen entlang lokal x, 1: entlang y
uniform float emit = 0.0;
uniform vec3 half_size = vec3(0.0);
varying vec3 lp; varying vec3 ln; varying vec3 wp;
float h21(vec2 p){ p = fract(p * vec2(234.34, 435.345)); p += dot(p, p + 34.23); return fract(p.x * p.y); }
float vn(vec2 p){ vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1, 0)), f.x), mix(h21(i + vec2(0, 1)), h21(i + vec2(1, 1)), f.x), f.y); }
void vertex(){ lp = VERTEX; ln = NORMAL; wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
vec3 liner(vec2 q){
	vec3 c = kraft;
	float fib = vn(q * vec2(90.0, 9.0)) * 0.6 + vn(q * vec2(300.0, 25.0)) * 0.4;
	c *= 0.93 + 0.1 * fib;
	c *= 0.96 + 0.06 * vn(q * 1.3);              // Flecken
	float tele = 0.5 + 0.5 * cos((tele_axis > 0.5 ? q.y : q.x) * 6.2831 / pitch);
	c *= 0.975 + 0.035 * tele;                    // Wellen zeichnen sich ab
	if (paint > 0.0) {
		float brush = vn(q * vec2(2.0, 14.0)) * 0.55 + vn(q * vec2(9.0, 40.0)) * 0.45;
		float m = smoothstep(1.0 - paint - 0.05, 1.0 - paint + 0.05, brush);
		vec3 pc = paint_col;
		if (paint_stripes > 0.0) {
			float s = (tele_axis > 0.5 ? q.y : q.x) / paint_stripes + vn(q * vec2(1.0, 6.0)) * 0.08;
			float k = mod(floor(s), 3.0);
			pc = k < 0.5 ? paint_col : (k < 1.5 ? stripe2 : kraft);
			if (k > 1.5) m = 0.0;
		}
		c = mix(c, pc * (0.94 + 0.08 * brush), m);
	}
	return c;
}
vec3 edge(float u, float v){
	float lin = 0.11;
	float w = 0.5 + (0.5 - lin - 0.05) * sin(u * 6.2831 / pitch);
	float d = abs(v - w);
	float flute = 1.0 - smoothstep(0.04, 0.07, d);
	float inl = step(v, lin) + step(1.0 - lin, v);
	float paper = clamp(flute + inl, 0.0, 1.0);
	vec3 inner = kraft * vec3(1.08, 1.06, 1.0);
	float occ = smoothstep(0.0, 0.25, d);
	vec3 voidc = kraft * 0.22 * (1.4 - occ);
	return mix(voidc, inner * (0.92 + 0.08 * vn(vec2(u * 60.0, v * 4.0))), paper);
}
void fragment(){
	vec3 c;
	if (mode == 2) {
		c = edge(UV.x, UV.y);
	} else if (mode == 1) {
		c = liner(UV);
	} else {
		vec3 an = abs(ln);
		int na = (an.x > an.y && an.x > an.z) ? 0 : ((an.y > an.z) ? 1 : 2);
		if (thin_axis < 0 || na == thin_axis) {
			vec2 q = (na == 0) ? lp.zy : ((na == 1) ? lp.xz : lp.xy);
			c = liner(q);
			if (half_size.x > 0.0) {
				int a1 = (na == 0) ? 1 : 0;
				int a2 = (na == 2) ? 1 : 2;
				float dd = min(half_size[a1] - abs(lp[a1]), half_size[a2] - abs(lp[a2]));
				c *= mix(0.72, 1.0, smoothstep(0.0, 0.09, dd));   // Faltkante dunkler
				c *= 1.0 + 0.10 * (1.0 - smoothstep(0.09, 0.14, dd)) * smoothstep(0.05, 0.09, dd); // Glanzgrat
			}
		} else {
			int other = 3 - thin_axis - na;
			float u = lp[other];
			float v = lp[thin_axis] / thick + 0.5;
			c = edge(u, v);
		}
	}
	ALBEDO = c;
	ROUGHNESS = 0.92;
	SPECULAR = 0.15;
	EMISSION = c * emit;
}
"""

# Paketklebeband: braun-transparent mit Glanz und Laengsschlieren.
const TAPE_SHADER := """
shader_type spatial;
render_mode cull_disabled, blend_mix, depth_draw_opaque;
uniform vec3 col : source_color = vec3(0.80, 0.60, 0.32);
uniform float alpha = 0.55;
float h(float x){ return fract(sin(x * 91.7) * 4375.5); }
void fragment(){
	float streak = h(floor(UV.y * 40.0));
	ALBEDO = col * (0.9 + 0.15 * streak);
	ALPHA = alpha;
	ROUGHNESS = 0.18;
	SPECULAR = 0.7;
}
"""

# Decal: Druck/Marker/Etikett aus PNG, auf Pappe aufgebracht (Alpha-Schnitt, matte Tinte).
const DECAL_SHADER := """
shader_type spatial;
render_mode cull_back;
uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform float emit = 0.0;
void fragment(){
	vec4 t = texture(tex, UV);
	if (t.a < 0.5) discard;
	ALBEDO = t.rgb;
	ROUGHNESS = 0.85;
	EMISSION = t.rgb * emit;
}
"""

# Himmel: Innenseite eines riesigen Kartondeckels, mit blauer Plakatfarbe gestrichen
# (Pinselstriche, Pappe scheint durch).
const SKY_SHADER := """
shader_type spatial;
render_mode unshaded, cull_front, fog_disabled;
uniform vec3 blue : source_color = vec3(0.45, 0.66, 0.84);
uniform vec3 kraft : source_color = vec3(0.72, 0.53, 0.32);
varying vec3 d;
float h21(vec2 p){ p = fract(p * vec2(234.34, 435.345)); p += dot(p, p + 34.23); return fract(p.x * p.y); }
float vn(vec2 p){ vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1, 0)), f.x), mix(h21(i + vec2(0, 1)), h21(i + vec2(1, 1)), f.x), f.y); }
void vertex(){ d = normalize(VERTEX); }
void fragment(){
	vec2 q = vec2(atan(d.x, d.z) * 30.0, d.y * 40.0);
	float brush = vn(q * vec2(0.5, 3.0)) * 0.6 + vn(q * vec2(2.0, 12.0)) * 0.4;
	float m = smoothstep(0.1, 0.17, brush);
	vec3 b = blue * (0.9 + 0.14 * vn(q * vec2(0.3, 6.0))) * mix(0.92, 1.06, clamp(d.y * 2.0, 0.0, 1.0));
	vec3 c = mix(kraft * 0.95, b, m);
	ALBEDO = c;
}
"""

const ORB_SHADER := """
shader_type spatial;
render_mode unshaded, fog_disabled;
uniform vec3 col : source_color = vec3(1.0, 0.82, 0.1);
uniform vec3 core : source_color = vec3(1.0, 0.97, 0.75);
varying vec3 lp;
float h21(vec2 p){ p = fract(p * vec2(234.34, 435.345)); p += dot(p, p + 34.23); return fract(p.x * p.y); }
void vertex(){ lp = VERTEX; }
void fragment(){
	// zerknuellte Papierkugel: facettierter Ton, heller Kern
	float facet = h21(floor(lp.xy * 14.0) + floor(lp.z * 14.0));
	float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	vec3 c = col * (0.88 + 0.16 * facet);
	ALBEDO = mix(c, core, smoothstep(0.7, 0.98, ndv) * 0.8);
}
"""

const EXIT_GLOW := """
shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled;
uniform vec3 col : source_color = vec3(0.12, 0.85, 0.40);
uniform float pulse = 1.0;
void fragment(){ ALBEDO = col * (0.95 + 0.08 * sin(TIME * 3.14159) * pulse); }
"""

const PAL := {
	"kraft": "#98714A", "kraft_hell": "#A88158", "kraft_dunkel": "#7C5A39", "graupappe": "#6E6558",
	"tinte": "#201A16", "rot": "#B02824", "kaki": "#B4542A", "weiss": "#F2EBDD", "blau": "#5E93C6",
	"kugel": "#FFD21A", "kugelkern": "#FFF6C2", "ausgang": "#22C25E", "ausgang_licht": "#2EE874", "stahl": "#9EA3A8",
}
func c(k: String) -> Color: return Color.html(PAL.get(k, k))

func card(params := {}) -> ShaderMaterial:
	var p := {"kraft": c("kraft"), "mode": 0, "thin_axis": -1, "thick": 0.3, "pitch": 0.16}
	p.merge(params, true)
	return Geo.mat(CARD_SHADER, p)

var tape_m: ShaderMaterial
var tape_w: ShaderMaterial
var edge_m: ShaderMaterial
var face_m: ShaderMaterial

func _ready() -> void:
	rng.seed = 1984
	reduce_fx = OS.get_environment("REDUCE_FX") == "1"
	cam = Camera3D.new()
	cam.near = 0.1
	cam.far = 700.0
	add_child(cam)
	cam.current = true
	tape_m = Geo.mat(TAPE_SHADER, {"col": Color.html("#B8873E"), "alpha": 0.72})
	tape_w = Geo.mat(TAPE_SHADER, {"col": c("weiss"), "alpha": 0.9})
	edge_m = card({"mode": 2})
	face_m = card({"mode": 1})
	_environment()
	_sky()
	_ground()
	_street()
	_overhead()
	_plaza()
	_life()
	_pellets()

func _environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = c("blau")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.86, 0.80, 0.72)
	env.ambient_light_energy = 0.42
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.85
	env.fog_enabled = true
	env.fog_light_color = Color(0.72, 0.78, 0.84)
	env.fog_density = 0.004
	env.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.95, 0.86)
	sun.light_energy = 0.8
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 90.0
	sun.rotation = Vector3(deg_to_rad(-52.0), deg_to_rad(-35.0), 0)
	add_child(sun)

func _sky() -> void:
	Geo.sphere(self, Vector3(0, 0, -20), 300.0, Geo.mat(SKY_SHADER, {"blue": c("blau"), "kraft": c("kraft")}), Vector3.ONE, 48)
	# Wolken: Pappausschnitte, weiss gestrichen, an Faeden haengend
	var cloud := PackedVector2Array()
	for i in 24:
		var a := float(i) / 24.0 * TAU
		var r := 1.0 + 0.22 * sin(a * 5.0)
		cloud.append(Vector2(cos(a) * 3.2 * r, 1.4 + sin(a) * 1.3 * r))
	var cw := card({"mode": 1, "paint": 0.9, "paint_col": c("weiss")})
	for p in [Vector3(-11, 17, -30), Vector3(9, 19, -44), Vector3(-4, 22, -62), Vector3(16, 15, -12)]:
		var mi := Geo.extrude(self, cloud, 0.25, cw, edge_m, p, Vector3(0, rng.randf_range(-0.3, 0.3), 0))
		Geo.cylinder(self, p + Vector3(0, 12.0, 0), 0.012, 0.012, 20.0, card({"kraft": c("weiss")}), 4)

func _ground() -> void:
	# Bodenbogen (Pappe) und Fahrbahn aus Graupappe; Gehwege als aufgelegte Wellpappstreifen
	# (die Wellen-Schnittkante ist die Kollisionskante).
	Geo.plane(self, Vector3(0, 0, -20), Vector2(240, 240), card({"mode": 1, "kraft": Color.html("#86603C")}))
	Geo.box(self, Vector3(0, 0.01, -8), Vector3(9.0, 0.02, 64.0), card({"kraft": c("graupappe"), "tele_axis": 0.0}))
	for sx in [-1.0, 1.0]:
		var sw := Geo.box(self, Vector3(sx * 5.6, 0.12, -8), Vector3(2.2, 0.24, 64.0), card({"thin_axis": 1, "thick": 0.24, "pitch": 0.26}))
	# Klebeband-Naehte quer ueber die Fahrbahn
	for z in [10.0, -6.0, -22.0]:
		Geo.box(self, Vector3(0, 0.03, z), Vector3(9.0, 0.006, 0.5), tape_w)
	# Hanamichi: ein langer, aufgelegter Wellpappstreifen in der Mitte (Kugeln liegen darauf)
	Geo.box(self, Vector3(0, 0.12, -6.0), Vector3(1.9, 0.24, 46.0), card({"thin_axis": 1, "thick": 0.24, "pitch": 0.26, "kraft": c("kraft_dunkel"), "paint": 0.0}))
	# mit Marker gezogene Mittellinie auf dem Streifen
	Geo.box(self, Vector3(-0.8, 0.245, -6.0), Vector3(0.05, 0.004, 46.0), card({"kraft": c("tinte")}))
	Geo.box(self, Vector3(0.8, 0.245, -6.0), Vector3(0.05, 0.004, 46.0), card({"kraft": c("tinte")}))

func _decal(file: String, pos: Vector3, size: Vector2, rot_y: float, emit := 0.0) -> MeshInstance3D:
	return Geo.quad(self, pos, size, Geo.mat(DECAL_SHADER, {"tex": Geo.tex("res://prints/" + file), "emit": emit}), Vector3(0, rot_y, 0))

# Ein Karton-Haus. sx: Seite (-1 links, +1 rechts), Front zeigt zur Strasse.
func _box_house(sx: float, zc: float, w: float, d: float, h: float, tone: Color, flaps := true) -> void:
	var xc := sx * (6.9 + d / 2.0)
	var fx := sx * 6.9  # Frontflaeche
	var body := card({"kraft": tone, "pitch": 0.14, "tele_axis": 1.0, "half_size": Vector3(d, h, w) * 0.5})
	Geo.box(self, Vector3(xc, h / 2.0, zc), Vector3(d, h, w), body)
	var rf := -sx * PI / 2.0  # Quads zur Strasse drehen
	# Laschen oben: vordere Lasche als Vordach schraeg nach aussen, hintere steil, seitliche halb offen
	if flaps:
		var t := 0.12
		var fl := card({"kraft": tone, "thin_axis": 1, "thick": t, "pitch": 0.11})
		var f1 := Geo.box(self, Vector3(0, 0, 0), Vector3(d * 0.5, t, w - 0.05), fl)
		f1.position = Vector3(fx - sx * (cos(0.5) * d * 0.25 - 0.0) + sx * 0.0, h + sin(0.5) * d * 0.25, zc)
		f1.rotation = Vector3(0, 0, sx * 0.5)
		f1.position.x = fx - sx * (-cos(0.5) * d * 0.25)
		f1.position.x = fx + sx * 0.0 - sx * (cos(2.6) * d * 0.25)
		# einfach: Lasche am oberen Frontrand angelenkt, 30 Grad ueber die Strasse geneigt
		var hinge := Vector3(fx, h, zc)
		var ang := deg_to_rad(28.0)
		var dir := Vector3(-sx * cos(ang), sin(ang), 0)
		f1.position = hinge + dir * (d * 0.25)
		f1.rotation = Vector3(0, 0, -sx * ang)
		var f2 := Geo.box(self, Vector3.ZERO, Vector3(d * 0.5, t, w - 0.05), fl)
		var hinge2 := Vector3(fx + sx * d, h, zc)
		var ang2 := deg_to_rad(70.0)
		f2.position = hinge2 + Vector3(sx * cos(ang2), sin(ang2), 0) * (d * 0.25)
		f2.rotation = Vector3(0, 0, sx * ang2)
		for sz in [-1.0, 1.0]:
			var f3 := Geo.box(self, Vector3.ZERO, Vector3(d - 0.1, t, w * 0.35), fl)
			var a3 := deg_to_rad(55.0)
			f3.position = Vector3(xc, h, zc + sz * w / 2.0) + Vector3(0, sin(a3), sz * cos(a3)) * (w * 0.175)
			f3.rotation = Vector3(-sz * a3, 0, 0)
		# Tackerklammern an der Vordach-Lasche
		for k in 3:
			Geo.box(self, hinge + Vector3(-sx * 0.02, -0.06, zc * 0.0 + (float(k) - 1.0) * w * 0.3), Vector3(0.02, 0.22, 0.06), card({"kraft": c("stahl")}))
	else:
		# geschlossener Karton: Klebeband ueber den Deckel und die Front hinunter
		Geo.box(self, Vector3(xc, h + 0.004, zc), Vector3(d + 0.02, 0.006, 0.55), tape_m)
		Geo.box(self, Vector3(fx - sx * 0.006, h - 0.6, zc), Vector3(0.006, 1.2, 0.55), tape_m)
	Geo.box(self, Vector3(fx - sx * 0.006, h - 0.8, zc + w * 0.02), Vector3(0.006, 1.6, 0.6), tape_m)
	# aufgeklebte Fenster (Rahmen aus Wellpappe, Schnittkanten sichtbar) mit dunklem "Loch"
	var rows := int((h - 1.0) / 2.4)
	var hole := card({"kraft": Color(0.17, 0.12, 0.08), "mode": 1})
	var frame := card({"kraft": c("kraft_dunkel"), "thin_axis": 0, "thick": 0.1, "pitch": 0.09})
	for r in rows:
		var y := 3.2 + r * 2.4
		if y + 0.8 > h - 0.3:
			break
		for k in [-1.0, 1.0]:
			var z: float = zc + k * w * 0.24
			Geo.quad(self, Vector3(fx - sx * 0.01, y, z), Vector2(1.1, 1.2), hole, Vector3(0, rf, 0))
			for e in [[0.0, 0.65, 1.5, 0.18], [0.0, -0.65, 1.5, 0.18], [0.66, 0.0, 0.18, 1.2], [-0.66, 0.0, 0.18, 1.2]]:
				Geo.box(self, Vector3(fx - sx * 0.05, y + e[1], z + e[0]), Vector3(0.1, e[3], e[2]), frame)
	# Tuer: ausgeschnittene Klappe, halb offen, dunkles Inneres dahinter
	var door_z := zc + (rng.randf_range(-0.2, 0.2)) * w
	Geo.quad(self, Vector3(fx - sx * 0.01, 1.15, door_z), Vector2(1.3, 2.3), hole, Vector3(0, rf, 0))
	var door := Geo.box(self, Vector3.ZERO, Vector3(0.1, 2.3, 1.3), card({"kraft": tone, "thin_axis": 0, "thick": 0.1, "pitch": 0.09}))
	var da := 0.9
	door.position = Vector3(fx - sx * 0.65 * sin(da), 1.15, door_z - 0.65 + 0.65 * cos(da) * 1.0)
	door.position = Vector3(fx, 1.15, door_z - 0.65) + Vector3(-sx * sin(da), 0, cos(da)) * 0.65
	door.rotation.y = sx * da
	# Druckreste: 1–2 Decals pro Karton, eigene Piktogramme
	var decs := [["tenchi.png", Vector2(1.6, 0.8)], ["ware.png", Vector2(0.9, 0.9)], ["kasa.png", Vector2(0.9, 0.9)],
		["toriatsukai.png", Vector2(1.5, 0.5)], ["etikett.png", Vector2(1.0, 0.66)]]
	var a: Array = decs[rng.randi() % decs.size()]
	_decal(a[0], Vector3(fx - sx * 0.012, h - 1.1, zc - w * 0.26), a[1] * 1.45, rf)
	if true:
		var b: Array = decs[(rng.randi() + 2) % decs.size()]
		_decal(b[0], Vector3(fx - sx * 0.012, 2.6, zc + w * 0.36), b[1] * 1.1, rf)

func _street() -> void:
	var tones := [c("kraft"), c("kraft_hell"), c("kraft_dunkel"), Color.html("#A07A50")]
	var z := 18.0
	var i := 0
	while z > -24.0:
		for sx in [-1.0, 1.0]:
			var w := rng.randf_range(6.0, 8.0)
			var h := rng.randf_range(5.0, 8.5)
			var d := rng.randf_range(5.0, 7.0)
			_box_house(sx, z - w / 2.0, w, d, h, tones[(i * 2 + (1 if sx > 0 else 0)) % 4], (i + (1 if sx > 0 else 0)) % 3 != 2)
			# kleiner Karton obendrauf, schraeg (gestapelt)
			if rng.randf() < 0.45:
				var w2 := w * 0.5
				var h2 := 1.8
				var bx := Geo.box(self, Vector3(sx * (7.4 + d * 0.4), h + h2 / 2.0, z - w / 2.0 + rng.randf_range(-0.5, 0.5)),
					Vector3(d * 0.6, h2, w2), card({"kraft": tones[(i + 1) % 4]}))
				bx.rotation.y = rng.randf_range(-0.2, 0.2)
				Geo.box(bx, Vector3(0, h2 / 2.0 + 0.004, 0), Vector3(d * 0.6 + 0.02, 0.006, 0.45), tape_m)
			# Vorhang-Tafel (Joshiki-maku in Plakatfarbe: Schwarz / Kaki / ungestrichene Pappe) in der Luecke
			var pz := z - w - 0.9
			var panel := card({"mode": 0, "thin_axis": 0, "thick": 0.14, "pitch": 0.1, "paint": 0.92, "paint_col": c("tinte"),
				"stripe2": c("kaki"), "paint_stripes": 0.45, "tele_axis": 0.0})
			panel.set_shader_parameter("tele_axis", 0.0)
			var pnl := Geo.box(self, Vector3(sx * 7.6, 3.2, pz), Vector3(0.14, 6.4, 1.8), panel)
			z -= 0.0
		z -= 9.2
		i += 1
	# Aufsteller: Darsteller mit Marker-Gesicht (Held rot, Gegenspieler blau), mit Stuetze hinten
	_standee(Vector3(-4.0, 0.24, 6.0), 0.5, "gesicht_held.png", c("weiss"))
	_standee(Vector3(4.1, 0.24, -4.0), -0.6, "gesicht_gegen.png", Color.html("#3E5A8C"))
	_standee(Vector3(-4.2, 0.24, -15.0), 0.7, "gesicht_gegen.png", Color.html("#3E5A8C"))
	# Ladenschilder in Marker-Schrift
	_decal("schild_shibai.png", Vector3(-6.85, 4.9, 12.0), Vector2(2.4, 0.6), PI / 2.0)
	_decal("schild_dan.png", Vector3(6.85, 4.6, 2.0), Vector2(2.4, 0.6), -PI / 2.0)

func _standee(p: Vector3, rot: float, face: String, costume: Color) -> void:
	var pose := PackedVector2Array([Vector2(-0.45, 0), Vector2(-0.12, 0), Vector2(0.0, 0.9), Vector2(0.2, 0), Vector2(0.95, 0),
		Vector2(0.5, 1.0), Vector2(0.45, 1.6), Vector2(1.4, 2.1), Vector2(1.5, 2.4), Vector2(0.32, 2.05), Vector2(0.4, 2.3),
		Vector2(0.45, 2.75), Vector2(0.3, 3.1), Vector2(-0.3, 3.1), Vector2(-0.45, 2.75), Vector2(-0.4, 2.3), Vector2(-0.45, 2.05),
		Vector2(-1.3, 2.55), Vector2(-1.4, 2.25), Vector2(-0.5, 1.6), Vector2(-0.62, 0.9)])
	var face_m := card({"mode": 1, "paint": 0.85, "paint_col": costume, "kraft": c("kraft")})
	var back := card({"mode": 1, "kraft": c("kraft_hell")})
	var mi := Geo.extrude(self, pose, 0.14, face_m, edge_m, p, Vector3(0, rot, 0), back)
	var fq := Geo.quad(mi, Vector3(0, 2.75, 0.075), Vector2(0.62, 0.78), Geo.mat(DECAL_SHADER, {"tex": Geo.tex("res://prints/" + face)}))
	# Stuetze hinten (Aufsteller-Fuss)
	var strut := Geo.box(mi, Vector3(0, 1.0, -0.45), Vector3(0.5, 2.1, 0.08), card({"thin_axis": 2, "thick": 0.08, "pitch": 0.09}))
	strut.rotation.x = -0.42

func _overhead() -> void:
	# Leinen quer ueber die Strasse mit Laternen aus gerollter Pappe (大入, Marker)
	var lm := Geo.mat(DECAL_SHADER, {"tex": Geo.tex("res://prints/laterne.png")})
	var string := card({"kraft": c("weiss")})
	for z in [12.0, 3.0, -6.0, -15.0]:
		Geo.box(self, Vector3(0, 6.6, z), Vector3(13.0, 0.03, 0.03), string)
		for k in 5:
			var x := -5.0 + k * 2.5
			var y := 6.0 - 0.35 * cos((x / 6.5) * PI / 2.0)
			var cy := Geo.cylinder(self, Vector3(x, y - 0.3, z), 0.34, 0.34, 1.0, lm, 18)
			cy.mesh.cap_top = false
			cy.mesh.cap_bottom = false
			Geo.cylinder(self, Vector3(x, y + 0.26, z), 0.02, 0.02, 0.6, string, 4)

func _plaza() -> void:
	var cz := -38.0
	# Drehbuehne: grosse Pappscheibe mit Musterbeutelklammer in der Mitte, Pfeil "dreht"
	var disc := Geo.cylinder(self, Vector3(0, 0.13, cz), 11.0, 11.0, 0.26, card({"mode": 1, "kraft": c("kraft_hell")}), 72)
	# Kante der Scheibe = Welle: als Ring aus Segmenten mit Kanten-Shader
	for k in 72:
		var a := float(k) / 72.0 * TAU
		var seg := Geo.box(self, Vector3(sin(a) * 11.0, 0.13, cz + cos(a) * 11.0), Vector3(0.96, 0.26, 0.02), card({"thin_axis": 1, "thick": 0.26, "pitch": 0.12}))
		seg.rotation.y = a + PI / 2.0
	Geo.cylinder(self, Vector3(0, 0.3, cz), 0.5, 0.6, 0.12, card({"kraft": c("stahl")}), 24)
	# Rueckwand: grosse Tafel mit Plakatfarben-Vorhang (Schwarz / Kaki / Pappe)
	var bw := card({"mode": 0, "thin_axis": 2, "thick": 0.3, "pitch": 0.14, "paint": 0.92, "paint_col": c("tinte"),
		"stripe2": c("kaki"), "paint_stripes": 1.2})
	Geo.box(self, Vector3(0, 5.0, cz - 13.0), Vector3(30.0, 10.0, 0.3), bw)
	Geo.box(self, Vector3(0, 10.2, cz - 13.0), Vector3(31.0, 0.5, 0.5), tape_w)
	# Pappmond an Stab
	var moon := Geo.extrude(self, Geo.circle_poly(2.6, 40, Vector2(0, 2.6)), 0.25, card({"mode": 1, "paint": 0.9, "paint_col": c("weiss")}), edge_m, Vector3(-8.0, 11.0, cz - 12.0))
	Geo.cylinder(self, Vector3(-8.0, 8.0, cz - 12.05), 0.05, 0.05, 6.0, card({"kraft": c("kraft_dunkel")}), 6)
	# Ausgang: gruen gestrichener Karton, Klapptuer offen, innen leuchtend; Schablonen-出口 oben
	var ex := Vector3(0, 0, cz + 2.0)
	var gm := card({"paint": 0.97, "paint_col": c("ausgang"), "emit": 0.12})
	Geo.box(self, ex + Vector3(-2.0, 2.0, 0), Vector3(1.0, 4.0, 3.0), gm)
	Geo.box(self, ex + Vector3(2.0, 2.0, 0), Vector3(1.0, 4.0, 3.0), gm)
	Geo.box(self, ex + Vector3(0, 4.3, 0), Vector3(5.0, 0.6, 3.0), gm)
	var pulse := 0.0 if reduce_fx else 1.0
	Geo.quad(self, ex + Vector3(0, 1.95, 0.2), Vector2(3.0, 3.9), Geo.mat(EXIT_GLOW, {"col": c("ausgang_licht"), "pulse": pulse}))
	var dflap := Geo.box(self, Vector3.ZERO, Vector3(3.0, 0.12, 2.2), card({"thin_axis": 1, "thick": 0.12, "pitch": 0.1, "paint": 0.95, "paint_col": c("ausgang")}))
	dflap.position = ex + Vector3(0, 0.06, 1.5 + 1.1)
	_decal("ausgang.png", ex + Vector3(0, 5.4, 1.52), Vector2(3.2, 1.6), 0.0, 0.25)
	Geo.box(self, ex + Vector3(0, 5.4, 1.45), Vector3(3.6, 1.8, 0.12), card({"thin_axis": 2, "thick": 0.12, "pitch": 0.1, "paint": 0.97, "paint_col": c("ausgang")}))
	var gl := OmniLight3D.new()
	gl.light_color = c("ausgang_licht")
	gl.light_energy = 2.0
	gl.omni_range = 7.0
	gl.position = ex + Vector3(0, 1.5, 2.0)
	add_child(gl)
	_standee(Vector3(-6.0, 0.26, cz - 3.0), 0.3, "gesicht_held.png", c("weiss"))
	_standee(Vector3(6.5, 0.26, cz - 4.0), -0.35, "gesicht_gegen.png", Color.html("#3E5A8C"))

func _life() -> void:
	# Passanten: Papprollen-Leute (Kern einer Rolle + Papierhut), dunkler als die Kartons
	var tube := card({"mode": 1, "kraft": Color.html("#8A6A48")})
	var hat := card({"mode": 1, "kraft": c("weiss"), "paint": 0.0})
	for f in [Vector3(-3.2, 0.24, 14.0), Vector3(3.0, 0.24, 8.0), Vector3(-3.6, 0.24, -2.0), Vector3(3.4, 0.24, -12.0),
			Vector3(-2.6, 0.24, -20.0), Vector3(5.0, 0.26, -30.0), Vector3(-4.5, 0.26, -32.0)]:
		Geo.cylinder(self, f + Vector3(0, 0.85, 0), 0.24, 0.24, 1.7, tube, 18)
		Geo.cylinder(self, f + Vector3(0, 1.95, 0), 0.0, 0.32, 0.5, hat, 18)

func _pellets() -> void:
	var pts := Geo.pellet_line(Vector3(0, 0.62, 16.0), Vector3(0, 0.62, -30.0), 2.0)
	Geo.pellets(self, pts, 0.26, Geo.mat(ORB_SHADER, {"col": c("kugel"), "core": c("kugelkern")}))

func views() -> Array:
	return [
		["strasse", Vector3(0.0, 1.95, 17.0), Vector3(0.0, 3.4, -40.0), 70.0],
		["totale", Vector3(-19.0, 22.0, 24.0), Vector3(0.0, 1.0, -16.0), 56.0],
		["ausgang", Vector3(-3.0, 2.0, -22.0), Vector3(0.0, 2.6, -40.0), 70.0],
		["capsule", Vector3(1.0, 1.9, 6.0), Vector3(-0.5, 4.2, -40.0), 62.0],
	]

func set_view(pos: Vector3, look: Vector3, fov: float) -> void:
	cam.position = pos
	cam.look_at(look)
	cam.fov = fov
