# Richtung D "Kulissenstadt Himmelsbrunn" – Stil-Prototyp (Art Director, Phase 1, NICHT Spielcode).
# Fiktiver mitteleuropaeischer Kurort. Prinzipien (beschrieben, nicht kopiert): strikte
# Zentralperspektive und Spiegelsymmetrie, frontale Fassaden wie Kulissen mit echten
# Ausschnitten (dahinter farbige Innenraum-Rueckwaende), flaches Licht ohne Schatten
# (Ton nur je Flaechenrichtung), Pastellpalette mit dunklen Zierleisten, Schilder ueberall,
# Modellbau-Anmutung (Tilt-Shift nur in der Totale, Papier-Bäume, flache Wolken).
# Ausgang: Standseilbahn hinter dem Kurhaus am Ende der Achse.
extends Node3D

const Geo := preload("res://geo.gd")

var cam: Camera3D
var rng := RandomNumberGenerator.new()
var font_m: FontFile
var font_b: FontFile
var tilt: MeshInstance3D

# Flache Farbe: Ton je Flaechenrichtung (oben hell, Seiten etwas dunkler), kein Licht,
# keine Schatten; leichte Kontakt-Verdunkelung am Boden (Modell-Anmutung), feines Korn.
const FLAT_SHADER := """
shader_type spatial;
render_mode unshaded, cull_back;
uniform vec3 col : source_color = vec3(0.95, 0.75, 0.70);
uniform vec3 col2 : source_color = vec3(1.0);
uniform float stripes = 0.0;      // >0: Markisen-/Kabinenstreifen entlang Welt-x+z
uniform float side_tone = 0.92;
uniform float top_tone = 1.05;
uniform float contact = 0.10;     // Verdunkelung am Fuss (0..1)
uniform float emit = 0.0;
varying vec3 wn; varying vec3 wpos;
float h21(vec2 p){ p = fract(p*vec2(123.34, 456.21)); p += dot(p, p+45.32); return fract(p.x*p.y); }
void vertex(){ wn = normalize((MODEL_MATRIX*vec4(NORMAL,0.0)).xyz); wpos = (MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; }
void fragment(){
	vec3 c = col;
	if (stripes > 0.0) c = mix(col, col2, step(0.5, fract((wpos.x + wpos.z) * stripes)));
	float t = 1.0;
	if (wn.y > 0.5) t = top_tone; else if (wn.y < -0.5) t = 0.85; else if (abs(wn.x) > abs(wn.z)) t = side_tone;
	t *= mix(1.0 - contact, 1.0, smoothstep(0.0, 0.6, wpos.y));
	c *= t;
	c *= 0.985 + 0.03 * h21(floor(FRAGCOORD.xy * 0.5));
	ALBEDO = c * (1.0 + emit);
}
"""

# Himmel: flacher Verlauf Puderblau -> Creme am Horizont (wie gemalter Prospekt).
const SKY_SHADER := """
shader_type spatial;
render_mode unshaded, cull_front, fog_disabled;
uniform vec3 top : source_color = vec3(0.70, 0.82, 0.90);
uniform vec3 horizon : source_color = vec3(0.98, 0.93, 0.84);
varying vec3 dir;
void vertex(){ dir = normalize((MODEL_MATRIX*vec4(VERTEX,1.0)).xyz - CAMERA_POSITION_WORLD); }
void fragment(){
	float t = smoothstep(-0.02, 0.45, dir.y);
	// sichtbare Farbbaender wie ein gemalter Rundhorizont (4 Stufen)
	t = floor(t * 5.0) / 4.0;
	ALBEDO = mix(horizon, top, clamp(t, 0.0, 1.0));
}
"""

const ORB_SHADER := """
shader_type spatial;
render_mode unshaded;
uniform vec3 col : source_color = vec3(1.0, 0.76, 0.0);
uniform vec3 core : source_color = vec3(1.0, 0.95, 0.70);
void fragment(){
	float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	ALBEDO = mix(col, core, smoothstep(0.75, 0.95, ndv)); // flach: zwei Toene, Glanzpunkt
}
"""

const METRO_SHADER := """
shader_type spatial;
render_mode unshaded;
uniform vec3 col : source_color = vec3(0.10, 0.66, 0.36);
void fragment(){ ALBEDO = col * (0.9 + 0.1 * sin(TIME * 3.14159)); } // 0,5 Hz
"""

# Tilt-Shift (nur Totale): Vollbild-Quad vor der Kamera, Unschaerfe nach Abstand vom
# Fokusband, leicht mehr Saettigung -> Modellbau-Anmutung.
const TILT_SHADER := """
shader_type spatial;
render_mode unshaded, depth_test_disabled, depth_draw_never, cull_disabled, fog_disabled;
uniform sampler2D screen : hint_screen_texture, filter_linear;
uniform float focus = 0.5;
uniform float band = 0.2;
uniform float strength = 2.4;
void vertex(){ POSITION = vec4(VERTEX.xy * 2.0, 0.0, 1.0); }
void fragment(){
	vec2 uv = SCREEN_UV;
	float d = max(abs(uv.y - focus) - band, 0.0) / (1.0 - band);
	float r = clamp(d * strength, 0.0, 1.0) * 0.012;
	vec3 c = texture(screen, uv).rgb;
	for (int i = 0; i < 16; i++) {
		float a = float(i) * 2.39996;
		float rr = r * sqrt((float(i) + 0.5) / 16.0);
		c += texture(screen, uv + vec2(cos(a), sin(a)) * rr * vec2(0.5625, 1.0)).rgb;
	}
	c /= 17.0;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(l), c, 1.15);
	ALBEDO = c;
}
"""

# ---------- Palette (eigene, keiner Filmpalette nachgebaut) ----------
const PAL := {
	"lachs": "#F2B5A0", "altrosa": "#E7A1AE", "lavendel": "#BCA9D3", "puder": "#A9C6DE",
	"creme": "#F5E8CC", "vanille": "#F3D9A4", "bordeaux": "#8E2F3C", "navy": "#25365C",
	"weiss": "#FBF6EC", "strasse": "#CDBFC0", "gehweg": "#EBCFC6", "innen": "#6B4A63",
	"kugel": "#FFC20E", "kugelkern": "#FFF2B3", "bahn": "#1AA85C", "himmel": "#B3D1E6", "horizont": "#FAEFD9",
	"baum": "#D98FA0", "hang": "#C9B6D6",
}

func c(k: String) -> Color: return Color.html(PAL.get(k, k))

func flat(k: String, params := {}) -> ShaderMaterial:
	var p := {"col": c(k)}
	p.merge(params, true)
	return Geo.mat(FLAT_SHADER, p)

func _ready() -> void:
	rng.seed = 1932
	font_m = FontFile.new()
	font_m.load_dynamic_font(ProjectSettings.globalize_path("res://fonts/Jost-500-Medium.ttf"))
	font_b = FontFile.new()
	font_b.load_dynamic_font(ProjectSettings.globalize_path("res://fonts/Jost-700-Bold.ttf"))
	cam = Camera3D.new()
	cam.near = 0.1
	cam.far = 900.0
	add_child(cam)
	cam.current = true
	_environment()
	_sky()
	_ground()
	_street()
	_kurhaus()
	_hill()
	_life()
	_pellets()
	_tiltshift()

func _environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = c("horizont")
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.fog_enabled = true
	env.fog_light_color = c("horizont")
	env.fog_density = 0.0012
	env.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

func _sky() -> void:
	var s := Geo.sphere(self, Vector3(0, -20, 0), 600.0, Geo.mat(SKY_SHADER, {"top": c("himmel"), "horizon": c("horizont")}), Vector3.ONE, 48)
	# Wolken als flache, gestapelte Ellipsen (Kulissen-Wolken), symmetrisch zur Achse
	var cloud := flat("weiss", {"side_tone": 1.0, "top_tone": 1.0, "contact": 0.0})
	for sx in [-1.0, 1.0]:
		for k in 3:
			var p := Vector3(sx * (22.0 + k * 14.0), 34.0 + k * 6.0, -90.0 - k * 6.0)
			Geo.sphere(self, p, 6.0, cloud, Vector3(1.6, 0.55, 0.15), 20)
			Geo.sphere(self, p + Vector3(sx * -4.0, 1.6, 0.2), 4.2, cloud, Vector3(1.4, 0.6, 0.15), 20)

func _ground() -> void:
	var road := flat("strasse", {"contact": 0.0})
	var walk := flat("gehweg", {"contact": 0.0})
	Geo.plane(self, Vector3(0, 0, -20), Vector2(160, 160), walk)
	Geo.box(self, Vector3(0, 0.01, -14), Vector3(7.0, 0.02, 64.0), road)
	# Mittellinie und Querstreifen streng symmetrisch
	var white := flat("weiss", {"contact": 0.0})
	for k in 14:
		Geo.box(self, Vector3(0, 0.03, 14.0 - k * 4.0), Vector3(0.18, 0.02, 1.8), white)
	for z in [-2.0, -30.0]:
		for i in 7:
			Geo.box(self, Vector3(-3.0 + i * 1.0, 0.03, z), Vector3(0.5, 0.02, 2.4), white)
	# Bordsteine (Kollisionskante) als Bordeaux-Linie
	var curb := flat("bordeaux", {"contact": 0.0})
	for sx in [-1.0, 1.0]:
		Geo.box(self, Vector3(sx * 3.55, 0.07, -14), Vector3(0.12, 0.14, 64.0), curb)

# Ein Haus als Kulisse: Frontwand aus Pfeilern und Baendern (echte Fensteroeffnungen),
# dahinter eine farbige Innen-Rueckwand, oben ein symmetrischer Giebel. Seite 'sx'
# (-1 links, +1 rechts) – rechts ist exakt der Spiegel von links.
func _house(sx: float, z0: float, d: float, h: float, wall: String, trim: String, sign_txt: String, gable: int) -> void:
	var front_x := sx * 5.2
	var wm := flat(wall)
	var tm := flat(trim)
	var inner := flat("innen", {"contact": 0.0, "side_tone": 1.0})
	var zc := z0 - d / 2.0
	# Koerper hinter der Kulisse (verdeckt die Tiefe, damit Ausschnitte "Innenraum" zeigen)
	Geo.box(self, Vector3(front_x + sx * (0.6 + 2.5), h / 2.0, zc), Vector3(5.0, h, d), wm)
	Geo.box(self, Vector3(front_x + sx * 0.55, h / 2.0, zc), Vector3(0.1, h, d - 0.1), inner)
	# Frontwand: 3 Fensterachsen, symmetrisch um die Hausmitte
	var t := 0.3
	var cols := 3
	var win_w := d / (cols * 2.0 + 1.0)
	for i in cols * 2 + 1:
		var zz := z0 - (float(i) + 0.5) * win_w
		if i % 2 == 0:
			Geo.box(self, Vector3(front_x, h / 2.0, zz), Vector3(t, h, win_w), wm)  # Pfeiler
		else:
			for f in int(h / 3.0):
				var y0 := float(f) * 3.0
				if f == 0:
					Geo.box(self, Vector3(front_x, 0.4, zz), Vector3(t, 0.8, win_w), wm)
					Geo.box(self, Vector3(front_x, 2.8, zz), Vector3(t, 0.4, win_w), wm)
				else:
					Geo.box(self, Vector3(front_x, y0 + 0.45, zz), Vector3(t, 0.9, win_w), wm)
					Geo.box(self, Vector3(front_x, y0 + 2.8, zz), Vector3(t, 0.4, win_w), wm)
					# Fensterbank + Sturz als Zierleiste
					Geo.box(self, Vector3(front_x - sx * 0.12, y0 + 0.92, zz), Vector3(0.18, 0.08, win_w + 0.2), tm)
	# Gesimse
	Geo.box(self, Vector3(front_x - sx * 0.1, 3.05, zc), Vector3(0.25, 0.18, d), tm)
	Geo.box(self, Vector3(front_x - sx * 0.12, h, zc), Vector3(0.35, 0.3, d + 0.2), tm)
	# Giebel: 0 Dreieck (Prisma), 1 Stufengiebel, 2 Rundbogen-Aufsatz
	if gable == 0:
		var pr := Geo.cylinder(self, Vector3(front_x + sx * 0.4, h + 1.0, zc), 2.0, 2.0, 1.0, wm, 3)
		pr.rotation = Vector3(0, 0, PI / 2.0)
		pr.rotation.x = -PI / 2.0
		pr.scale = Vector3(1.0, 1.0, d / 4.2)
	elif gable == 1:
		for s in 3:
			Geo.box(self, Vector3(front_x + sx * 0.2, h + 0.5 + s * 0.8, zc), Vector3(0.6, 0.8, d * (0.8 - s * 0.24)), wm)
			Geo.box(self, Vector3(front_x, h + 0.92 + s * 0.8, zc), Vector3(0.66, 0.1, d * (0.8 - s * 0.24) + 0.1), tm)
	else:
		var arc := Geo.cylinder(self, Vector3(front_x + sx * 0.2, h + 0.2, zc), d * 0.3, d * 0.3, 0.6, wm, 24)
		arc.rotation.z = PI / 2.0
		var ring := Geo.cylinder(self, Vector3(front_x, h + 0.2, zc), d * 0.12, d * 0.12, 0.66, flat("weiss"), 24)
		ring.rotation.z = PI / 2.0
	# Ladenschild ueber dem Erdgeschoss + gestreifte Markise
	var board := Geo.box(self, Vector3(front_x - sx * 0.2, 3.55, zc), Vector3(0.12, 0.7, d * 0.62), tm)
	_label(sign_txt, Vector3(front_x - sx * 0.27, 3.55, zc), -sx, 0.0055, c("weiss"), font_b, 64)
	var aw := Geo.box(self, Vector3(front_x - sx * 0.85, 2.55, zc), Vector3(1.5, 0.08, d * 0.7), flat(wall, {"stripes": 2.2, "col2": c("weiss"), "contact": 0.0}))
	aw.rotation.z = sx * 0.32

func _label(txt: String, pos: Vector3, facing: float, px: float, col: Color, font: Font, size := 64, outline := Color(0, 0, 0, 0)) -> Label3D:
	var l := Label3D.new()
	l.text = txt
	l.font = font
	l.font_size = size
	l.pixel_size = px
	l.modulate = col
	l.outline_size = 0 if outline.a == 0.0 else 12
	l.outline_modulate = outline
	l.position = pos
	l.rotation.y = facing * PI / 2.0  # facing -1: Text schaut nach -x ... +1: nach +x
	l.double_sided = false
	add_child(l)
	return l

func _street() -> void:
	# Links von vorn nach hinten; rechts gespiegelt mit denselben Massen (Symmetrie).
	var rows := [
		[8.0, 9.0, "lachs", "bordeaux", "SCHIRMMACHER", 0],
		[8.0, 12.0, "lavendel", "navy", "HUTMACHER", 1],
		[9.0, 9.0, "vanille", "bordeaux", "APOTHEKE", 2],
		[8.0, 12.0, "puder", "navy", "POST", 0],
	]
	var rows_r := ["BUCHBINDER", "BARBIER", "TELEGRAF", "BÄCKEREI"]
	var z := 16.0
	var i := 0
	for r in rows:
		_house(-1.0, z, r[0], r[1], r[2], r[3], r[4], r[5])
		_house(1.0, z, r[0], r[1], r[2], r[3], rows_r[i], r[5])
		z -= r[0] + 0.0
		i += 1
	# Querstrasse bei z = -16..-22 (offen), dann zwei weitere Paare bis zum Kurhaus
	z -= 6.0
	var rows2 := [[9.0, 10.5, "altrosa", "navy", "KURMITTELHAUS", 1], [8.0, 9.0, "creme", "bordeaux", "LESEHALLE", 0]]
	var r2_r := ["TRINKHALLE", "MUSIKPAVILLON"]
	i = 0
	for r in rows2:
		_house(-1.0, z, r[0], r[1], r[2], r[3], r[4], r[5])
		_house(1.0, z, r[0], r[1], r[2], r[3], r2_r[i], r[5])
		z -= r[0]
		i += 1
	# Wegweiser an der Querstrasse (Schilder als Orientierung), symmetrisch
	var post := flat("navy")
	for sx in [-1.0, 1.0]:
		Geo.cylinder(self, Vector3(sx * 4.4, 1.5, -18.5), 0.06, 0.06, 3.0, post, 8)
		Geo.box(self, Vector3(sx * 4.4, 2.6, -18.5), Vector3(1.9, 0.42, 0.06), flat("weiss"))
		_label("STANDSEILBAHN", Vector3(sx * 4.4, 2.6, -18.46), 0.0, 0.0028, c("bahn"), font_b, 64).rotation.y = 0.0
		Geo.box(self, Vector3(sx * 4.4, 2.1, -18.5), Vector3(1.9, 0.42, 0.06), flat("weiss"))
		_label("KURHAUS", Vector3(sx * 4.4, 2.1, -18.46), 0.0, 0.0028, c("navy"), font_b, 64).rotation.y = 0.0
	# Laternen paarweise
	var lamp := flat("navy")
	var glob := flat("weiss", {"emit": 0.1})
	for lz in [12.0, 4.0, -4.0, -12.0, -26.0, -34.0]:
		for sx in [-1.0, 1.0]:
			Geo.cylinder(self, Vector3(sx * 3.95, 1.7, lz), 0.05, 0.08, 3.4, lamp, 8)
			Geo.sphere(self, Vector3(sx * 3.95, 3.55, lz), 0.22, glob, Vector3.ONE, 12)
	# Puppenhaus-Schnitt: das Eckhaus rechts an der Querstrasse ist zur Strasse offen
	_dollhouse(Vector3(13.0, 0, -19.6))

# Ein Haus im Querschnitt (Seite zur Querstrasse offen): Zimmer in verschiedenen Farben.
func _dollhouse(p: Vector3) -> void:
	# Schliesst die Querstrasse rechts ab (Blickpunkt), offen zur Hauptachse (-x).
	var d := 6.0  # Breite entlang z
	var colors := [["altrosa", "puder", "vanille"], ["lavendel", "lachs", "puder"], ["vanille", "altrosa", "lavendel"]]
	for f in 3:
		for r in 3:
			var z: float = p.z + (float(r) - 1.0) * (d / 3.0)
			Geo.box(self, Vector3(p.x + 3.4, f * 3.0 + 1.5, z), Vector3(0.2, 2.9, d / 3.0 - 0.12), flat(colors[f][r], {"contact": 0.0}))  # Rueckwand
			Geo.box(self, Vector3(p.x + 1.7, f * 3.0 + 0.05, z), Vector3(3.6, 0.1, d / 3.0), flat("weiss"))  # Boden
			Geo.box(self, Vector3(p.x + 3.0, f * 3.0 + 0.65, z - 0.35), Vector3(0.5, 1.2, 0.6), flat("bordeaux" if r % 2 == 0 else "navy"))
			Geo.box(self, Vector3(p.x + 1.9, f * 3.0 + 0.5, z + 0.25), Vector3(0.6, 0.08, 0.8), flat("weiss"))
			Geo.cylinder(self, Vector3(p.x + 1.9, f * 3.0 + 0.25, z + 0.25), 0.05, 0.05, 0.5, flat("navy"), 6)
			# Bild an der Rueckwand
			Geo.box(self, Vector3(p.x + 3.28, f * 3.0 + 1.9, z), Vector3(0.05, 0.6, 0.8), flat("creme"))
	for wz in [-d / 2.0, d / 2.0]:
		Geo.box(self, Vector3(p.x + 1.7, 4.6, p.z + wz), Vector3(3.8, 9.2, 0.2), flat("creme"))
	Geo.box(self, Vector3(p.x + 1.7, 9.3, p.z), Vector3(4.2, 0.3, d + 0.4), flat("bordeaux"))
	for st in 3:
		Geo.box(self, Vector3(p.x + 1.7, 9.85 + st * 0.8, p.z), Vector3(3.8, 0.8, d * (0.85 - st * 0.25)), flat("altrosa"))
		Geo.box(self, Vector3(p.x + 1.7, 10.27 + st * 0.8, p.z), Vector3(3.9, 0.1, d * (0.85 - st * 0.25) + 0.1), flat("bordeaux"))
	_label("PENSION", Vector3(p.x + 0.2, 8.6, p.z), -1.0, 0.005, c("navy"), font_b, 72)

func _kurhaus() -> void:
	# Abschluss der Achse: breites, streng symmetrisches Kurhaus mit Mittelturm.
	var zf := -46.0
	var wall := flat("altrosa")
	var trim := flat("bordeaux")
	var white := flat("weiss")
	Geo.box(self, Vector3(0, 6.0, zf - 5.0), Vector3(34.0, 12.0, 10.0), wall)
	# Fensterraster der Front (5 Achsen je Fluegel), Rahmen weiss, Glas dunkel
	var glass := flat("innen", {"contact": 0.0})
	for sx in [-1.0, 1.0]:
		for k in 5:
			var x: float = sx * (5.0 + k * 2.4)
			for f in 3:
				Geo.box(self, Vector3(x, 1.8 + f * 3.4, zf + 0.02), Vector3(1.2, 1.9, 0.05), glass)
				Geo.box(self, Vector3(x, 0.75 + f * 3.4, zf + 0.08), Vector3(1.5, 0.12, 0.15), white)
	Geo.box(self, Vector3(0, 12.2, zf - 5.0), Vector3(35.0, 0.5, 10.6), trim)
	Geo.box(self, Vector3(0, 3.9, zf + 0.1), Vector3(34.2, 0.25, 0.3), trim)
	# Mittelrisalit mit Turm, Uhr, Fahnen
	Geo.box(self, Vector3(0, 8.0, zf - 4.7), Vector3(8.0, 16.0, 9.0), flat("vanille"))
	Geo.box(self, Vector3(0, 16.2, zf - 4.7), Vector3(8.6, 0.5, 9.6), trim)
	Geo.box(self, Vector3(0, 20.0, zf - 4.0), Vector3(4.0, 7.0, 4.0), flat("lavendel"))
	Geo.cylinder(self, Vector3(0, 25.0, zf - 4.0), 0.0, 3.0, 3.2, flat("puder"), 4).rotation.y = PI / 4.0
	var clock := Geo.cylinder(self, Vector3(0, 20.5, zf - 1.95), 1.3, 1.3, 0.1, white, 32)
	clock.rotation.x = PI / 2.0
	Geo.box(self, Vector3(0, 20.85, zf - 1.88), Vector3(0.1, 0.8, 0.05), flat("navy"))
	Geo.box(self, Vector3(0.25, 20.5, zf - 1.88), Vector3(0.55, 0.1, 0.05), flat("navy"))
	for sx in [-1.0, 1.0]:
		Geo.cylinder(self, Vector3(sx * 16.5, 15.0, zf - 0.5), 0.05, 0.05, 6.0, flat("navy"), 6)
		Geo.box(self, Vector3(sx * 16.5 - sx * 0.9, 17.2, zf - 0.5), Vector3(1.8, 1.0, 0.05), flat("bordeaux", {"stripes": 2.5, "col2": c("vanille")}))
	# Schriftzug ueber dem Portal
	Geo.box(self, Vector3(0, 13.3, zf + 0.5), Vector3(8.4, 1.4, 0.15), flat("navy"))
	_label("KURHAUS HIMMELSBRUNN", Vector3(0, 13.3, zf + 0.6), 0.0, 0.006, c("weiss"), font_b, 96).rotation.y = 0.0
	# Treppe, symmetrisch
	for s in 4:
		Geo.box(self, Vector3(0, 0.15 + s * 0.3, zf + 3.0 - s * 0.7), Vector3(12.0 - s * 1.2, 0.3, 0.8), flat("creme"))
	# Ausgang: Standseilbahn-Station im Portal (einziges gesaettigtes Gruen, gefuellt)
	var portal := Geo.quad(self, Vector3(0, 3.0, zf + 0.06), Vector2(3.6, 4.0), Geo.mat(METRO_SHADER, {"col": c("bahn")}))
	Geo.box(self, Vector3(0, 5.25, zf + 0.15), Vector3(4.4, 0.5, 0.3), flat("weiss"))
	for sx in [-1.0, 1.0]:
		Geo.box(self, Vector3(sx * 2.0, 2.6, zf + 0.15), Vector3(0.35, 5.2, 0.3), flat("weiss"))
	_label("STANDSEILBAHN", Vector3(0, 5.25, zf + 0.32), 0.0, 0.0042, c("bahn"), font_b, 72).rotation.y = 0.0

func _hill() -> void:
	# Kulissen-Berg hinter dem Kurhaus: gestaffelte, flache Huegel-Prospekte, Papierbaeume,
	# Standseilbahn-Trasse diagonal hinauf, gruene Kabine, Bergstation oben.
	var hang := flat("hang", {"contact": 0.0, "side_tone": 1.0})
	var hang2 := flat("#B7A2C8", {"contact": 0.0, "side_tone": 1.0})
	var h1 := Geo.sphere(self, Vector3(0, -8, -100), 46.0, hang2, Vector3(1.2, 1.0, 0.25), 40)
	var h2 := Geo.sphere(self, Vector3(-38, -14, -82), 32.0, hang, Vector3(1.1, 1.0, 0.25), 40)
	var h3 := Geo.sphere(self, Vector3(38, -14, -82), 32.0, hang, Vector3(1.1, 1.0, 0.25), 40)
	# Trasse: schraeges Band vom Kurhaus (Mitte) hinauf zur Bergstation
	var a := Vector3(0, 2.0, -58.0)
	var b := Vector3(0, 36.0, -84.0)
	var mid := (a + b) / 2.0
	var track := Geo.box(self, mid, Vector3(2.4, 0.2, a.distance_to(b)), flat("creme", {"contact": 0.0}))
	track.look_at_from_position(mid, b, Vector3.UP)
	for k in 12:
		var p := a.lerp(b, float(k) / 11.0)
		var sl := Geo.box(self, p + Vector3(0, 0.15, 0), Vector3(2.8, 0.12, 0.25), flat("navy"))
		sl.look_at_from_position(p + Vector3(0, 0.15, 0), p + (b - a), Vector3.UP)
	# Kabine (gruen = Ausgang), schraeg gestuft
	var cp := a.lerp(b, 0.42) + Vector3(0, 1.4, 0)
	var cab := Geo.box(self, cp, Vector3(2.2, 2.2, 3.4), flat("bahn", {"stripes": 0.0}))
	cab.look_at_from_position(cp, cp + (b - a), Vector3.UP)
	Geo.box(self, cp + Vector3(0, 0.3, 0.0), Vector3(2.3, 0.7, 2.6), flat("weiss"))
	# Bergstation
	Geo.box(self, b + Vector3(0, 2.5, -2.0), Vector3(8.0, 5.0, 5.0), flat("vanille"))
	Geo.box(self, b + Vector3(0, 5.2, -2.0), Vector3(8.6, 0.4, 5.6), flat("bordeaux"))
	# Papierbaeume: Kegel in Altrosa auf duennem Stamm, symmetrisch gesetzt
	var crown := flat("baum", {"contact": 0.0})
	var stem := flat("bordeaux")
	for sx in [-1.0, 1.0]:
		for k in 6:
			var p := Vector3(sx * (6.0 + k * 4.5), 4.0 + k * 3.2, -66.0 - k * 3.0)
			Geo.cylinder(self, p + Vector3(0, 0.7, 0), 0.08, 0.1, 1.4, stem, 6)
			Geo.cylinder(self, p + Vector3(0, 2.6, 0), 0.0, 1.3, 3.2, crown, 12)
	# Strassenbaeume an der Allee: Kugeln auf Stab (Modellbau), paarweise
	var round := flat("baum", {"contact": 0.0})
	for lz in [8.0, 0.0, -8.0, -30.0, -38.0]:
		for sx in [-1.0, 1.0]:
			Geo.cylinder(self, Vector3(sx * 4.6, 1.3, lz), 0.07, 0.07, 2.6, stem, 6)
			Geo.sphere(self, Vector3(sx * 4.6, 3.3, lz), 1.1, round, Vector3(1.0, 1.0, 1.0), 16)

func _life() -> void:
	# Figuren in Uniform-Farben, frontal oder im Profil (keine Filmfiguren nachgebaut)
	var navy := flat("navy")
	var bord := flat("bordeaux")
	var lav := flat("lavendel")
	var skin := flat("#F1CDB4")
	var hats := flat("navy")
	var figs := [[Vector3(-4.6, 0, 10.0), 0.0, bord], [Vector3(4.6, 0, 10.0), PI, bord], [Vector3(-4.3, 0, -6.0), PI / 2, navy],
		[Vector3(4.3, 0, -6.0), -PI / 2, navy], [Vector3(-1.6, 0, -40.0), 0.0, lav], [Vector3(1.6, 0, -40.0), 0.0, lav],
		[Vector3(-4.6, 0, -28.0), PI, navy], [Vector3(4.6, 0, -28.0), 0.0, navy]]
	for f in figs:
		var n := Geo.figure(self, f[0], f[2], skin, f[1])
		Geo.cylinder(n, Vector3(0, 1.72, 0), 0.14, 0.14, 0.16, hats, 12)  # Kappe
	# Fahrzeug: kleiner Kurort-Bus, frontal in der Achse geparkt, und zwei Oldtimer gespiegelt
	var wheel := flat("navy")
	var glass := flat("innen")
	Geo.car(self, Vector3(-2.2, 0, 6.0), PI, flat("vanille"), wheel, glass, 3.8, 1.7)
	Geo.car(self, Vector3(2.2, 0, 6.0), 0.0, flat("vanille"), wheel, glass, 3.8, 1.7)

func _pellets() -> void:
	var pts := Geo.pellet_line(Vector3(0, 0.55, 16.0), Vector3(0, 0.55, -40.0), 2.0)
	Geo.pellets(self, pts, 0.25, Geo.mat(ORB_SHADER, {"col": c("kugel"), "core": c("kugelkern")}))

func _tiltshift() -> void:
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	tilt = MeshInstance3D.new()
	tilt.mesh = q
	tilt.material_override = Geo.mat(TILT_SHADER, {})
	tilt.extra_cull_margin = 16384.0
	tilt.visible = false
	add_child(tilt)

func views() -> Array:
	return [
		["strasse", Vector3(0.0, 1.7, 18.0), Vector3(0.0, 4.2, -40.0), 70.0],
		["totale", Vector3(0.0, 19.0, 22.0), Vector3(0.0, 3.0, -30.0), 54.0],
		["kurhaus", Vector3(0.0, 1.7, -28.0), Vector3(0.0, 8.0, -60.0), 74.0],
		["puppenhaus", Vector3(-3.0, 1.7, -19.6), Vector3(14.0, 4.6, -19.6), 64.0],
		["capsule", Vector3(0.0, 1.5, 3.0), Vector3(0.0, 7.0, -40.0), 60.0],
	]

func set_view(pos: Vector3, look: Vector3, fov: float) -> void:
	cam.position = pos
	cam.look_at(look)
	cam.fov = fov
	tilt.visible = (pos.y > 10.0)  # Tilt-Shift nur in der erhoehten Totale
