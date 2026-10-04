# Richtung G "Aizuri-Pop-up – Bilderbuch-Theaterstadt" – Stil-Prototyp (Art Director, Phase 1,
# NICHT Spielcode). Die Stadt ist ein aufgeschlagenes Theater-Bilderbuch (Ehon): der Boden sind
# zwei Buchseiten, die Hauptstrasse liegt im Falz, alle Haeuser, Baeume, Wellen und Darsteller
# sind Pop-up-Teile aus bedrucktem Papier im Holzschnitt-Blaudruck (Aizuri-e-Prinzip:
# Preussischblau in Stufen, Papierweiss, Tusche, Bokashi, leichter Passerversatz).
# Signatur-Mechanik: Pop-up-Teile liegen in der Ferne flach auf der Seite und klappen auf,
# wenn der Spieler naeher kommt (Vertex-Shader, Abstand zur Kamera; "Effekte reduzieren" =
# alles steht). Die Kamera wird nie bewegt. Kugeln = Blattgold-Gelb (einzige Warmfarbe neben
# kleinen Beni-Akzenten), Ausgang = gruenes Lesebaendchen + aufgeklappte Seitentuer mit Licht.
extends Node3D

const Geo := preload("res://geo.gd")

var cam: Camera3D
var rng := RandomNumberGenerator.new()
var font: FontFile
var reduce_fx := false
var pops: Array = []

# Pop-up-Teil: bedruckter Bogen (RGBA, Alpha = Ausschnitt), Rueckseite unbedrucktes Papier.
# Klappt um die Fusskante (lokal y = 0) nach hinten, abhaengig vom Abstand zur Kamera.
const POP_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform vec3 paper : source_color = vec3(0.95, 0.93, 0.88);
uniform float near_d = 26.0;
uniform float far_d = 52.0;
uniform float max_fold = 1.50;   // rad, ~86 Grad: liegt fast flach
uniform float fold_on = 1.0;     // 0 = "Effekte reduzieren": alles steht
uniform vec3 player = vec3(0.0); // Spielerposition (im Spiel = Kamera; fuer die Totale gesetzt)
uniform float use_player = 0.0;
varying float k;
void vertex(){
	vec3 o = MODEL_MATRIX[3].xyz;
	vec3 pp = use_player > 0.5 ? player : CAMERA_POSITION_WORLD;
	float d = length(o.xz - pp.xz);
	k = smoothstep(near_d, far_d, d) * fold_on;
	float a = -k * max_fold;
	float y = VERTEX.y;
	VERTEX.y = y * cos(a);
	VERTEX.z = VERTEX.z + y * sin(a);
}
void fragment(){
	vec4 t = texture(tex, vec2(UV.x, UV.y));
	if (t.a < 0.5) discard;
	vec3 c = FRONT_FACING ? t.rgb : paper * 0.93;
	c *= mix(1.0, 0.94, k);   // liegende Teile minimal dunkler (Seitenschatten)
	ALBEDO = c;
}
"""

# Buchseite: Washi mit Fasern, gedruckter hellblauer Weg im Falz (Bokashi), Falzschatten,
# Seitenrand mit Blattschnitt.
const PAGE_SHADER := """
shader_type spatial;
render_mode unshaded;
uniform vec3 paper : source_color = vec3(0.95, 0.93, 0.88);
uniform vec3 ai3 : source_color = vec3(0.55, 0.69, 0.84);
uniform vec3 ai4 : source_color = vec3(0.81, 0.88, 0.93);
uniform vec3 ai1 : source_color = vec3(0.12, 0.23, 0.43);
varying vec3 wp;
float h21(vec2 p){ p = fract(p * vec2(234.34, 435.345)); p += dot(p, p + 34.23); return fract(p.x * p.y); }
float vn(vec2 p){ vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1, 0)), f.x), mix(h21(i + vec2(0, 1)), h21(i + vec2(1, 1)), f.x), f.y); }
void vertex(){ wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment(){
	float ax = abs(wp.x);
	vec3 c = paper * (0.985 + 0.015 * vn(wp.xz * vec2(6.0, 1.5)));
	// gedruckter Weg (Bokashi von der Mitte nach aussen), mit Holzmaserung
	float road = 1.0 - smoothstep(3.6, 5.2, ax);
	vec3 rc = mix(ai3, ai4, smoothstep(0.0, 4.6, ax)) * (0.97 + 0.03 * vn(wp.xz * vec2(0.25, 2.0)));
	c = mix(c, rc, road * 0.9);
	// Gehweg-Kante als Konturlinie (Kollision)
	c = mix(c, ai1, (1.0 - smoothstep(0.03, 0.08, abs(ax - 4.6))));
	// Falz: dunkle feine Linie + weicher Schatten
	c *= 1.0 - 0.18 * (1.0 - smoothstep(0.0, 0.5, ax));
	c = mix(c, ai1 * 0.9, 1.0 - smoothstep(0.015, 0.04, ax));
	// Seitenraender: Randschatten zum Blattschnitt hin
	c *= 1.0 - 0.15 * smoothstep(26.0, 30.0, ax);
	ALBEDO = c;
}
"""

# Himmel: Bokashi Preussischblau oben -> Papier am Horizont (Holzschnitt-Himmel).
const SKY_SHADER := """
shader_type spatial;
render_mode unshaded, cull_front, fog_disabled;
uniform vec3 top : source_color = vec3(0.12, 0.23, 0.43);
uniform vec3 mid : source_color = vec3(0.30, 0.47, 0.70);
uniform vec3 hor : source_color = vec3(0.95, 0.93, 0.88);
varying vec3 d;
void vertex(){ d = normalize(VERTEX); }
void fragment(){
	float t = clamp(d.y * 2.2, 0.0, 1.0);
	vec3 c = mix(hor, mid, smoothstep(0.05, 0.45, t));
	c = mix(c, top, smoothstep(0.5, 1.0, t));
	ALBEDO = c;
}
"""

# Blattschnitt (Seitenstapel) und Einband
const BLOCK_SHADER := """
shader_type spatial;
render_mode unshaded;
uniform vec3 paper : source_color = vec3(0.93, 0.90, 0.83);
varying vec3 lp;
void vertex(){ lp = VERTEX; }
void fragment(){
	float lines = 0.5 + 0.5 * sin(lp.y * 900.0);
	ALBEDO = (abs(NORMAL.y) > 0.5) ? paper : paper * (0.82 + 0.1 * lines);
}
"""

const FLAT_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform vec3 col : source_color = vec3(1.0);
uniform float emit = 0.0;
void fragment(){ ALBEDO = col * (1.0 + emit); }
"""

const ORB_SHADER := """
shader_type spatial;
render_mode unshaded, fog_disabled;
uniform vec3 col : source_color = vec3(1.0, 0.80, 0.08);
uniform vec3 core : source_color = vec3(1.0, 0.96, 0.70);
uniform vec3 key : source_color = vec3(0.11, 0.10, 0.12);
void fragment(){
	float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	vec3 c = mix(col, core, smoothstep(0.65, 0.95, ndv));
	c = mix(key, c, smoothstep(0.12, 0.22, ndv));   // Konturplatte als Rand: Kugel wirkt gedruckt
	ALBEDO = c;
}
"""

const EXIT_SHADER := """
shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled;
uniform vec3 col : source_color = vec3(0.13, 0.77, 0.38);
uniform float pulse = 1.0;
void fragment(){ ALBEDO = col * (0.95 + 0.07 * sin(TIME * 3.14159) * pulse); }
"""

const BEAM_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, fog_disabled;
uniform vec3 col : source_color = vec3(0.13, 0.77, 0.38);
void fragment(){
	float edge = 1.0 - abs(UV.x - 0.5) * 2.0;
	ALBEDO = col * smoothstep(0.0, 0.7, edge) * UV.y * 0.45;
}
"""

const PAL := {
	"ai1": "#1E3A6E", "ai2": "#3F6CA8", "ai3": "#8DB0D6", "ai4": "#CFE0EE", "papier": "#F3EEE2",
	"sumi": "#1C1A1E", "beni": "#C8384B", "kugel": "#FFC714", "kugelkern": "#FFF3B8", "ausgang": "#22C460",
	"einband": "#24304F",
}
func c(k: String) -> Color: return Color.html(PAL.get(k, k))

func flat(k: String, emit := 0.0) -> ShaderMaterial:
	return Geo.mat(FLAT_SHADER, {"col": c(k), "emit": emit})

# Ein Pop-up-Teil: Quad mit Fuss am Ursprung (Scharnier), Breite w, Hoehe h.
func pop(file: String, base: Vector3, w: float, h: float, rot_y: float, near_d := 26.0, far_d := 52.0) -> MeshInstance3D:
	var mesh := QuadMesh.new()
	mesh.size = Vector2(w, h)
	mesh.center_offset = Vector3(0, h / 2.0, 0)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = Geo.mat(POP_SHADER, {"tex": Geo.tex("res://prints/" + file), "paper": c("papier"),
		"near_d": near_d, "far_d": far_d, "fold_on": 0.0 if reduce_fx else 1.0})
	mi.position = base
	mi.rotation.y = rot_y
	mi.extra_cull_margin = h
	pops.append(mi.material_override)
	add_child(mi)
	# Falz-Lasche am Fuss (gefaltetes Papier, bleibt liegen) + Falzlinie
	var tab := Geo.quad(self, base + Basis(Vector3.UP, rot_y) * Vector3(0, 0.012, 0.25), Vector2(w * 0.9, 0.5), flat("papier"), Vector3(-PI / 2.0, rot_y, 0))
	return mi

func _ready() -> void:
	rng.seed = 1765
	reduce_fx = OS.get_environment("REDUCE_FX") == "1"
	font = FontFile.new()
	font.load_dynamic_font(ProjectSettings.globalize_path("res://fonts/NotoSerifJP-Black-Subset.otf"))
	cam = Camera3D.new()
	cam.near = 0.1
	cam.far = 700.0
	add_child(cam)
	cam.current = true
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = c("papier")
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	_book()
	_street()
	_theater()
	_exit()
	_sky_parts()
	_pellets()

func _book() -> void:
	Geo.sphere(self, Vector3(0, 0, -20), 320.0, Geo.mat(SKY_SHADER, {"top": c("ai1"), "mid": c("ai2"), "hor": c("papier")}), Vector3.ONE, 48)
	# Seiten (60 m breit, 90 m lang), leicht zum Falz geneigt
	var pm := Geo.mat(PAGE_SHADER, {"paper": c("papier"), "ai3": c("ai3"), "ai4": c("ai4"), "ai1": c("ai1")})
	for sx in [-1.0, 1.0]:
		var p := Geo.plane(self, Vector3(sx * 15.0, 0.0, -18.0), Vector2(30.0, 90.0), pm)
		p.rotation.z = 0.0
		p.position.y = 0.18
	# Blattschnitt (Seitenstapel) und Einband
	var blk := Geo.mat(BLOCK_SHADER, {"paper": Color.html("#EAE3D2")})
	for sx in [-1.0, 1.0]:
		Geo.box(self, Vector3(sx * 15.0, -0.5, -18.0), Vector3(29.9, 1.3, 89.9), blk)
		Geo.box(self, Vector3(sx * 15.4, -1.3, -18.0), Vector3(31.0, 0.3, 91.0), flat("einband"))
	# Titel-Kartusche und Seitenzahl auf der linken Seite (wie im Bilderbuch)
	var k := Geo.quad(self, Vector3(-9.5, 0.4, 6.0), Vector2(1.6, 5.0), Geo.mat(POP_SHADER, {"tex": Geo.tex("res://prints/kartusche.png"), "fold_on": 0.0}), Vector3(-PI / 2.0, 0, 0))
	var pn := Label3D.new()
	pn.text = "十二"
	pn.font = font
	pn.font_size = 96
	pn.pixel_size = 0.008
	pn.modulate = c("sumi")
	pn.position = Vector3(-26.0, 0.42, 22.0)
	pn.rotation = Vector3(-PI / 2.0, 0, 0)
	add_child(pn)

func _street() -> void:
	var houses := ["haus_a.png", "haus_b.png", "haus_c.png"]
	var z := 18.0
	var i := 0
	while z > -30.0:
		for sx in [-1.0, 1.0]:
			var f: String = houses[(i + (1 if sx > 0 else 0)) % 3]
			pop(f, Vector3(sx * 5.4, 0.2, z - 4.0), 8.0, 7.0, -sx * PI / 2.0)
			# zweite Ebene dahinter, hoeher gestaffelt (Pop-up-Schichten)
			pop(houses[(i + 2) % 3], Vector3(sx * 10.5, 0.24, z - 8.5), 9.0, 7.9, -sx * PI / 2.0)
		# Kiefer zwischen den Haeusern
		pop("kiefer.png", Vector3(-6.4, 0.2, z - 8.6), 3.6, 4.8, PI / 2.0 - 0.25)
		pop("kiefer.png", Vector3(6.4, 0.2, z - 8.6), 3.6, 4.8, -PI / 2.0 + 0.25)
		z -= 9.0
		i += 1
	# Darsteller als Pop-up-Figuren an der Wegkante (eigene Figuren in Mie-Pose)
	pop("darsteller_a.png", Vector3(-3.9, 0.2, 4.0), 1.5, 2.5, 0.35)
	pop("darsteller_b.png", Vector3(3.9, 0.2, -6.0), 1.5, 2.5, -0.35)
	pop("darsteller_a.png", Vector3(-3.9, 0.2, -18.0), 1.5, 2.5, 0.4)
	# Wellenband als Kulisse ganz hinten an den Seiten (Hafen hinter den Haeusern)
	for sx in [-1.0, 1.0]:
		pop("wellen.png", Vector3(sx * 17.0, 0.22, -10.0), 26.0, 9.0, -sx * PI / 2.0, 60.0, 90.0)

func _theater() -> void:
	# Schauspielhaus als grosses Pop-up am Ende der Achse (klappt als letztes auf)
	pop("theater.png", Vector3(0, 0.2, -44.0), 22.0, 13.75, 0.0, 34.0, 62.0)
	pop("darsteller_b.png", Vector3(-6.0, 0.2, -38.0), 1.6, 2.7, 0.3, 34.0, 62.0)

func _exit() -> void:
	# Ausgang: aufgeklappte Seitentuer im Weg (Papierklappe steht, darunter gruenes Licht)
	# + gruenes Lesebaendchen als weithin sichtbarer Wegweiser (steht immer, klappt nicht).
	var ez := -33.0
	var pulse := 0.0 if reduce_fx else 1.0
	Geo.box(self, Vector3(0, 0.2, ez), Vector3(2.6, 0.04, 2.6), Geo.mat(EXIT_SHADER, {"col": c("ausgang"), "pulse": pulse}))
	var flap := Geo.box(self, Vector3(0, 1.3, ez - 1.3), Vector3(2.6, 2.6, 0.03), flat("papier"))
	flap.rotation.x = -0.25
	flap.position = Vector3(0, 0.2 + 1.3 * cos(0.25), ez - 1.3 - 1.3 * sin(0.25))
	for r in 3:
		var bq := Geo.quad(self, Vector3(0, 2.6, ez), Vector2(2.6, 5.0), Geo.mat(BEAM_SHADER, {"col": c("ausgang")}))
		bq.rotation.y = float(r) * PI / 3.0
	# Lesebaendchen: langes gruenes Seidenband, oben aus dem "Buchruecken" haengend
	var rib := PackedVector2Array([Vector2(-0.35, 0), Vector2(0.0, 0.5), Vector2(0.35, 0), Vector2(0.35, 13.0), Vector2(-0.35, 13.0)])
	var rm := Geo.mat(EXIT_SHADER, {"col": c("ausgang"), "pulse": 0.0})
	var r1 := Geo.extrude(self, rib, 0.03, rm, rm, Vector3(1.9, 0.2, ez - 1.0), Vector3(0, 0, 0.06))
	# Schild 出口 an der Klappe
	Geo.quad(self, Vector3(0, 3.5, ez - 1.0), Vector2(2.4, 1.2), Geo.mat(POP_SHADER, {"tex": Geo.tex("res://prints/ausgang.png"), "fold_on": 0.0}))

func _sky_parts() -> void:
	# Nebelbaender (Kasumi) als Pop-up-Streifen auf Draht ueber der Stadt
	var km := Geo.mat(POP_SHADER, {"tex": Geo.tex("res://prints/kasumi.png"), "fold_on": 0.0})
	for p in [Vector3(-12, 16, -40), Vector3(10, 19, -55), Vector3(-2, 22, -70), Vector3(18, 13, -25)]:
		var q := Geo.quad(self, p, Vector2(18.0, 3.5), km)
		Geo.cylinder(self, p + Vector3(0, 10, 0), 0.01, 0.01, 18.0, flat("ai2"), 4)

func _pellets() -> void:
	var pts := Geo.pellet_line(Vector3(0, 0.6, 16.0), Vector3(0, 0.6, -31.0), 2.0)
	Geo.pellets(self, pts, 0.26, Geo.mat(ORB_SHADER, {"col": c("kugel"), "core": c("kugelkern"), "key": c("sumi")}))

func views() -> Array:
	return [
		["strasse", Vector3(0.0, 1.9, 17.0), Vector3(0.0, 3.4, -40.0), 70.0],
		["totale", Vector3(5.0, 21.0, 36.0), Vector3(0.0, 0.0, -16.0), 58.0],
		["ausgang", Vector3(-2.4, 2.0, -21.0), Vector3(0.3, 3.0, -44.0), 72.0],
		["capsule", Vector3(0.6, 1.9, 0.0), Vector3(0.0, 4.4, -44.0), 62.0],
	]

func set_view(pos: Vector3, look: Vector3, fov: float) -> void:
	cam.position = pos
	cam.look_at(look)
	cam.fov = fov
	# erhoehte Ansicht: Aufklappen relativ zu einem gedachten Spieler am Strassenanfang
	for m in pops:
		m.set_shader_parameter("use_player", 1.0 if pos.y > 10.0 else 0.0)
		m.set_shader_parameter("player", Vector3(0, 1.7, 12.0))
