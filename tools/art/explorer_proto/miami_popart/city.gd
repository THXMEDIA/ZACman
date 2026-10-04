# Richtung C "Druckfarben-Miami" (Pop Art) – Stil-Prototyp (Art Director, Phase 1, NICHT Spielcode).
# Prinzip: Vierfarbdruck. Jede Flaeche ist Papierweiss oder eine von vier Druckfarben; Toene
# entstehen nur aus Rasterpunkten (Ben-Day-Raster: Punktgroesse nach Helligkeitsstufe, Raster
# liegt auf der Bildebene, 45 Grad gedreht). Cel-Shading mit drei Stufen (licht / mittel /
# Schatten = drei Punktdichten), schwarze Kontur als Inverted Hull mit bildschirmkonstanter
# Breite. Comic-Elemente nur als eigene Erfindung (Starburst mit "ZAP!", Tempolinien).
extends Node3D

const Geo := preload("res://geo.gd")

var cam: Camera3D
var rng := RandomNumberGenerator.new()
var zap_pos := Vector3(5.45, 9.5, -14.0)

const HALFTONE_FN := """
// Rasterpunkt auf der Bildebene: Deckung cov (0..1) -> Punktradius
float benday(vec2 frag, float cell, float cov){
	if (cov <= 0.001) return 0.0;
	mat2 R = mat2(vec2(0.7071, -0.7071), vec2(0.7071, 0.7071));
	vec2 g = R * frag / cell;
	vec2 f = fract(g) - 0.5;
	float d = length(f);
	float r = sqrt(cov) * 0.56;
	return 1.0 - smoothstep(r - 0.07, r + 0.07, d);
}
"""

# Druckflaeche: Grundfarbe + Rasterpunkte in Tintenfarbe, drei Lichtstufen; optional Streifen.
const PRINT_SHADER := "shader_type spatial;\nrender_mode unshaded, cull_back;\n" + HALFTONE_FN + """
uniform vec3 col : source_color = vec3(1.0, 0.99, 0.96);
uniform vec3 ink : source_color = vec3(0.0, 0.64, 0.88);
uniform vec3 col2 : source_color = vec3(0.89, 0.0, 0.17);
uniform float cell = 7.0;
uniform float cov_lit = 0.0;
uniform float cov_mid = 0.4;
uniform float cov_shade = 0.78;
uniform float stripes = 0.0;   // >0: Streifen col/col2 entlang der Weltachse y (Frequenz)
uniform float stripes_axis = 1.0; // 1 = y, 0 = x+z
uniform vec3 sun = vec3(-0.45, 0.8, 0.4);
varying vec3 wn; varying vec3 wpos;
void vertex(){ wn = normalize((MODEL_MATRIX*vec4(NORMAL,0.0)).xyz); wpos = (MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; }
void fragment(){
	float l = dot(wn, normalize(sun));
	float cov = (l > 0.3) ? cov_lit : ((l > -0.15) ? cov_mid : cov_shade);
	vec3 base = col;
	if (stripes > 0.0) {
		float s = (stripes_axis > 0.5) ? wpos.y : (wpos.x + wpos.z);
		base = mix(col, col2, step(0.5, fract(s * stripes)));
	}
	float d = benday(FRAGCOORD.xy, cell, cov);
	ALBEDO = mix(base, ink, d);
}
"""

# Himmel: Papier unten, Cyan-Raster nach oben dichter (Druckverlauf).
const SKY_SHADER := "shader_type spatial;\nrender_mode unshaded, cull_front, fog_disabled;\n" + HALFTONE_FN + """
uniform vec3 paper : source_color = vec3(1.0, 0.99, 0.96);
uniform vec3 ink : source_color = vec3(0.0, 0.64, 0.88);
uniform float cell = 9.0;
varying vec3 dir;
void vertex(){ dir = normalize((MODEL_MATRIX*vec4(VERTEX,1.0)).xyz - CAMERA_POSITION_WORLD); }
void fragment(){
	float up = clamp(dir.y, 0.0, 1.0);
	float cov = smoothstep(0.0, 0.6, up) * 0.95;
	// Streifenwolke: zwei weisse Baender ohne Raster
	float cloud = step(0.93, sin(dir.y*22.0 + dir.x*3.0)) * step(0.05, up) * step(up, 0.42);
	float d = benday(FRAGCOORD.xy, cell, cov) * (1.0 - cloud);
	ALBEDO = mix(paper, ink, d);
}
"""

# Meer: Cyan voll, weisse Wellenstriche; Strand: Papier mit feinem Punktraster.
const SEA_SHADER := "shader_type spatial;\nrender_mode unshaded;\n" + HALFTONE_FN + """
uniform vec3 col : source_color = vec3(0.0, 0.64, 0.88);
uniform vec3 paper : source_color = vec3(1.0, 0.99, 0.96);
varying vec3 wpos;
void vertex(){ wpos = (MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; }
void fragment(){
	float w = sin(wpos.z*0.9 + sin(wpos.x*0.35)*1.5 + TIME*0.6);
	float wave = step(0.86, w) * step(0.3, fract(wpos.x*0.11 + wpos.z*0.05));
	float d = benday(FRAGCOORD.xy, 8.0, 0.25*(1.0-wave));
	vec3 c = mix(col, paper, wave);
	ALBEDO = mix(c, paper, d*0.0) ;
	ALBEDO = mix(c, col*0.75, d);
}
"""

const ORB_SHADER := "shader_type spatial;\nrender_mode unshaded;\n" + HALFTONE_FN + """
uniform vec3 col : source_color = vec3(1.0, 0.84, 0.0);
uniform vec3 ink : source_color = vec3(0.07, 0.07, 0.07);
void fragment(){
	float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float cov = (ndv > 0.45) ? 0.0 : 0.45;
	float d = benday(FRAGCOORD.xy, 6.0, cov);
	ALBEDO = mix(col, ink, d);
}
"""

const METRO_SHADER := """
shader_type spatial;
render_mode unshaded;
uniform vec3 col : source_color = vec3(0.0, 0.78, 0.33);
uniform vec3 paper : source_color = vec3(1.0, 0.99, 0.96);
void fragment(){
	float p = step(0.5, fract(TIME*0.5)); // 0,5 Hz Pfeil-Blinken
	float arrow = step(abs(UV.x-0.5)*1.6 + (UV.y-0.25), 0.35) * step(0.25, UV.y) * p;
	ALBEDO = mix(col, paper, arrow*0.9);
}
"""

# Schwarze Kontur, bildschirmkonstant (eigene Variante: etwas dicker, feste Breite ab 3 m)
const INK_HULL := """
shader_type spatial;
render_mode unshaded, cull_front, fog_disabled;
uniform vec3 col : source_color = vec3(0.07, 0.07, 0.07);
uniform float width = 0.03;
uniform float px = 0.0;
uniform int mode = 0;
void vertex(){
	vec3 dir = (mode == 0) ? sign(VERTEX) : NORMAL;
	vec3 wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float dist = max(length(wpos - CAMERA_POSITION_WORLD), 3.0);
	float w = width * dist * 0.22;
	vec3 scl = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	VERTEX += dir * w / scl;
}
void fragment(){ ALBEDO = col; }
"""

const PAPER := "#FFFDF5"
const BLACK := "#111111"
const CYAN := "#00A3E0"
const RED := "#E4002B"
const YELLOW := "#FFD500"
const GREEN := "#00C853"

func c(h: String) -> Color: return Color.html(h)

func prt(col: String, ink: String, params := {}) -> ShaderMaterial:
	var p := {"col": c(col), "ink": c(ink)}
	p.merge(params, true)
	return Geo.mat(PRINT_SHADER, p)

func _ready() -> void:
	rng.seed = 1961
	cam = Camera3D.new()
	cam.near = 0.1
	cam.far = 900.0
	add_child(cam)
	cam.current = true
	_environment()
	_sky()
	_ground()
	_buildings()
	_beach()
	_metro()
	_life()
	_pellets()
	_comic()
	Geo.hull_all(self, c(BLACK), 0.03, 0.0, [], INK_HULL)

func _environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = c(PAPER)
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.fog_enabled = false
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

func _sky() -> void:
	var s := Geo.sphere(self, Vector3(0, -30, 0), 600.0, Geo.mat(SKY_SHADER, {"paper": c(PAPER), "ink": c(CYAN)}), Vector3.ONE, 48)
	s.set_meta("nohull", true)

func _ground() -> void:
	# Fahrbahn: Papier mit schwarzem Raster (grau), Gehweg: Papier rein, Bordstein schwarz
	var road := prt(PAPER, BLACK, {"cov_lit": 0.22, "cov_mid": 0.22, "cov_shade": 0.22, "cell": 7.0})
	var walk := prt(PAPER, CYAN, {"cov_lit": 0.0, "cov_mid": 0.0, "cov_shade": 0.0})
	var g := Geo.plane(self, Vector3(10, 0, -10), Vector2(60, 160), walk)
	g.set_meta("nohull", true)
	var r := Geo.box(self, Vector3(0, 0.02, -8), Vector3(10.0, 0.04, 90.0), road)
	r.set_meta("nohull", true)
	# Mittelstreifen gelb? Nein – Gelb ist exklusiv fuer Kugeln. Weisse Striche:
	for k in 22:
		var m := Geo.box(self, Vector3(0, 0.05, 34 - k * 4.0), Vector3(0.2, 0.02, 2.0), walk)
		m.set_meta("nohull", true)
	var curb := prt(PAPER, BLACK, {"cov_lit": 0.0, "cov_mid": 0.0, "cov_shade": 0.0})
	Geo.box(self, Vector3(-5.1, 0.08, -8), Vector3(0.3, 0.16, 90.0), curb)
	Geo.box(self, Vector3(5.1, 0.08, -8), Vector3(0.3, 0.16, 90.0), curb)

# Art-Deco-Block: Kasten, abgerundete Ecke, Augenbrauen ueber den Fenstern, zentrale Finne,
# gestufter Abschluss. Pastell nur aus Raster (Cyan- oder Rot-Punkte auf Papier).
func _deco(pos: Vector3, w: float, d: float, h: float, ink: String, pastel: float, facing_x: float) -> void:
	var wall := prt(PAPER, ink, {"cov_lit": pastel, "cov_mid": pastel + 0.3, "cov_shade": pastel + 0.55})
	var trim := prt(PAPER, BLACK, {"cov_lit": 0.0, "cov_mid": 0.0, "cov_shade": 0.0})
	var glass := prt(PAPER, CYAN, {"cov_lit": 0.55, "cov_mid": 0.75, "cov_shade": 0.9, "cell": 5.0})
	Geo.box(self, pos + Vector3(0, h/2, 0), Vector3(w, h, d), wall)
	# runde Ecke zur Strasse
	Geo.cylinder(self, pos + Vector3(facing_x * w/2, h/2, d/2), 1.6, 1.6, h, wall, 20)
	# gestufter Abschluss + Finne
	Geo.box(self, pos + Vector3(0, h + 0.6, 0), Vector3(w * 0.7, 1.2, d * 0.7), wall)
	Geo.box(self, pos + Vector3(facing_x * (w/2 + 0.2), h/2 + 1.2, 0), Vector3(0.5, h + 2.4, 0.9), trim)
	# Fensterbaender mit Augenbrauen
	var floors: int = max(2, int(h / 3.2))
	for f in floors:
		var y := 1.6 + float(f) * 3.2
		var nw: int = max(2, int(d / 3.0))
		for k in nw:
			var z := pos.z - d/2 + (float(k) + 0.5) * d / float(nw)
			if abs(z - pos.z) < 0.8:
				continue
			Geo.box(self, Vector3(pos.x + facing_x * (w/2 + 0.03), y, z), Vector3(0.06, 1.6, 1.8), glass)
		Geo.box(self, Vector3(pos.x + facing_x * (w/2 + 0.35), y + 1.0, pos.z), Vector3(0.7, 0.14, d - 1.0), trim)
	# Markise Erdgeschoss rot/weiss gestreift
	var awn := prt(PAPER, BLACK, {"cov_lit": 0.0, "cov_mid": 0.0, "cov_shade": 0.0, "stripes": 1.2, "stripes_axis": 0.0, "col2": c(RED)})
	var aw := Geo.box(self, Vector3(pos.x + facing_x * (w/2 + 1.1), 3.2, pos.z - d * 0.15), Vector3(2.2, 0.1, min(d * 0.45, 6.0)), awn)
	aw.rotation.z = facing_x * 0.3

func _buildings() -> void:
	# Ostseite der Avenue (rechts, x > 5): Deco-Blocks; Westseite (links) Strand.
	var z := 26.0
	var i := 0
	while z > -44.0:
		var d := rng.randf_range(9.0, 14.0)
		var h: float = [9.0, 12.5, 16.0, 11.0][i % 4]
		var ink := CYAN if i % 3 != 1 else RED
		var pastel: float = [0.0, 0.18, 0.28][i % 3]
		_deco(Vector3(5.6 + 7.0, 0, z - d/2), 14.0, d, h, ink, pastel, -1.0)
		if i == 3:
			zap_pos = Vector3(5.45, h - 2.6, z - d/2 - d*0.22)
		z -= d + 0.6
		i += 1
	# Hintergrund: hohe Tuerme weiter oestlich, nur Papier + schwarzes Raster
	var far := prt(PAPER, BLACK, {"cov_lit": 0.0, "cov_mid": 0.22, "cov_shade": 0.4, "cell": 9.0})
	for k in 7:
		var x := 30.0 + k * 11.0
		Geo.box(self, Vector3(x, 14.0, -50.0 - rng.randf_range(0, 12)), Vector3(8.0, 28.0 + rng.randf_range(-6, 10), 8.0), far)

func _beach() -> void:
	# Palmen entlang des Gehwegs, Rettungsschwimmerturm, Meer dahinter
	var trunk := prt(PAPER, BLACK, {"cov_lit": 0.18, "cov_mid": 0.4, "cov_shade": 0.6, "cell": 5.0})
	var frond := prt(BLACK, BLACK, {"cov_lit": 0.0, "cov_mid": 0.0, "cov_shade": 0.0})
	for pz in [20.0, 11.0, 2.0, -7.0, -16.0, -25.0, -34.0]:
		var p := Vector3(-7.0, 0, pz)
		var t := Geo.cylinder(self, p + Vector3(0, 3.6, 0), 0.22, 0.32, 7.2, trunk, 10)
		t.rotation.z = -0.08
		for k in 9:
			var a := float(k) / 9.0 * TAU + rng.randf_range(-0.2, 0.2)
			var dir := Vector3(cos(a) * 0.8, -0.45 + rng.randf_range(0, 0.5), sin(a) * 0.8).normalized()
			# Wedel: flacher, spitz zulaufender Kegel (Zylinder mit Spitze, in einer Achse plattgedrueckt)
			var fr := Geo.cylinder(self, p + Vector3(-0.55, 7.2, 0) + dir * 2.1, 0.02, 0.42, 4.2, frond, 6)
			fr.basis = Basis(Quaternion(Vector3.UP, dir)) * Basis.from_scale(Vector3(1.0, 1.0, 0.25))
		Geo.sphere(self, p + Vector3(-0.55, 7.0, 0), 0.5, frond, Vector3.ONE, 10)
	# Rettungsschwimmerturm: rot-weiss gestreifter Kasten auf Stelzen
	var tower := prt(PAPER, BLACK, {"cov_lit": 0.0, "cov_mid": 0.0, "cov_shade": 0.0, "stripes": 0.7, "col2": c(RED)})
	var red := prt(RED, BLACK, {"cov_lit": 0.0, "cov_mid": 0.3, "cov_shade": 0.55})
	var tp := Vector3(-15.0, 0, -12.0)
	for sx in [-1.3, 1.3]:
		for sz in [-1.3, 1.3]:
			Geo.box(self, tp + Vector3(sx, 1.2, sz), Vector3(0.25, 2.4, 0.25), red)
	Geo.box(self, tp + Vector3(0, 3.5, 0), Vector3(3.4, 2.2, 3.4), tower)
	Geo.box(self, tp + Vector3(0, 4.9, 0), Vector3(4.2, 0.3, 4.2), red)
	Geo.box(self, tp + Vector3(0, 5.5, 0), Vector3(2.4, 0.9, 2.4), red)
	# Strandlinie und Meer
	var sea := Geo.plane(self, Vector3(-55, -0.05, -10), Vector2(70, 200), Geo.mat(SEA_SHADER, {"col": c(CYAN), "paper": c(PAPER)}))
	sea.set_meta("nohull", true)
	# Sonnenschirme: rot/weiss, Kugelhaelften
	var umb := prt(PAPER, BLACK, {"cov_lit": 0.0, "cov_mid": 0.0, "cov_shade": 0.0, "stripes": 0.8, "stripes_axis": 0.0, "col2": c(RED)})
	for u in [[-12.0, 4.0], [-14.5, -24.0], [-11.5, -30.0]]:
		Geo.cylinder(self, Vector3(u[0], 1.1, u[1]), 0.04, 0.04, 2.2, trunk, 6)
		Geo.cylinder(self, Vector3(u[0], 2.2, u[1]), 0.1, 1.5, 0.5, umb, 12)

func _metro() -> void:
	# U-Bahn: einziges Gruen, gefuellt, am Ende der Avenue auf dem rechten Gehweg
	var green := prt(GREEN, BLACK, {"cov_lit": 0.0, "cov_mid": 0.25, "cov_shade": 0.45})
	var p := Vector3(7.5, 0, -40.0)
	Geo.box(self, p + Vector3(-1.9, 1.6, 0), Vector3(0.3, 3.2, 0.3), green)
	Geo.box(self, p + Vector3(1.9, 1.6, 0), Vector3(0.3, 3.2, 0.3), green)
	Geo.box(self, p + Vector3(0, 3.5, 0), Vector3(4.6, 0.9, 0.4), green)
	var portal := Geo.quad(self, p + Vector3(0, 1.4, -0.2), Vector2(3.4, 2.8), Geo.mat(METRO_SHADER, {"col": c(GREEN), "paper": c(PAPER)}))
	portal.set_meta("nohull", true)
	var stairs := Geo.box(self, p + Vector3(0, 0.03, 1.6), Vector3(3.4, 0.06, 3.0), green)
	stairs.set_meta("nohull", true)
	var lbl := Label3D.new()
	lbl.text = "METRO"
	lbl.font_size = 140
	lbl.pixel_size = 0.005
	lbl.modulate = c(PAPER)
	lbl.outline_modulate = c(BLACK)
	lbl.outline_size = 28
	lbl.position = p + Vector3(0, 3.5, 0.25)
	add_child(lbl)

func _life() -> void:
	# Haut = Papier mit roten Punkten (Druck-Fleischton), Kleidung Cyan/Rot/Schwarz
	var skin := prt(PAPER, RED, {"cov_lit": 0.22, "cov_mid": 0.42, "cov_shade": 0.6, "cell": 5.0})
	var cyan := prt(CYAN, BLACK, {"cov_lit": 0.0, "cov_mid": 0.3, "cov_shade": 0.55})
	var red := prt(RED, BLACK, {"cov_lit": 0.0, "cov_mid": 0.3, "cov_shade": 0.55})
	var white := prt(PAPER, BLACK, {"cov_lit": 0.0, "cov_mid": 0.25, "cov_shade": 0.5})
	var figs := [
		[Vector3(-6.0, 0, 8.0), 0.4, cyan], [Vector3(6.2, 0, -4.0), -0.6, red], [Vector3(-9.5, 0, -2.0), 1.6, white], [Vector3(6.8, 0, -20.0), 1.2, cyan],
		[Vector3(-8.0, 0, -14.0), 0.0, skin], [Vector3(5.8, 0, -30.0), 2.4, red], [Vector3(-12.0, 0, -20.0), 3.0, skin], [Vector3(-6.4, 0, -28.0), -1.0, cyan],
	]
	for f in figs:
		Geo.figure(self, f[0], f[2], skin, f[1])
	# Autos: rotes Cabrio und cyanfarbener Wagen, Tempolinien hinter dem Cabrio
	var wheel := prt(BLACK, BLACK, {"cov_lit": 0.0, "cov_mid": 0.0, "cov_shade": 0.0})
	var glass := prt(PAPER, CYAN, {"cov_lit": 0.4, "cov_mid": 0.6, "cov_shade": 0.8, "cell": 5.0})
	Geo.car(self, Vector3(2.4, 0, 0.0), 0.0, red, wheel, glass, 4.8, 1.9)
	Geo.car(self, Vector3(-2.4, 0, -18.0), PI, cyan, wheel, glass)
	var line := prt(BLACK, BLACK, {"cov_lit": 0.0, "cov_mid": 0.0, "cov_shade": 0.0})
	for k in 4:
		var l := Geo.box(self, Vector3(2.4 + (k - 1.5) * 0.45, 0.6 + (k % 2) * 0.35, 4.6 + k * 0.4), Vector3(0.06, 0.06, 2.6 - k * 0.3), line)
		l.set_meta("nohull", true)

func _pellets() -> void:
	var pts := Geo.pellet_line(Vector3(0, 0.55, 18.0), Vector3(0, 0.55, -38.0), 2.0)
	pts += Geo.pellet_line(Vector3(2.0, 0.55, -40.0), Vector3(6.0, 0.55, -40.0), 2.0)
	pts += Geo.pellet_line(Vector3(-6.0, 0.55, -10.0), Vector3(-13.0, 0.55, -10.0), 2.0)
	var mm := Geo.pellets(self, pts, 0.26, Geo.mat(ORB_SHADER, {"col": c(YELLOW), "ink": c(BLACK)}))
	mm.set_meta("nohull", true)
	# Kontur fuer die Kugeln: zweite MultiMesh mit Hull-Material
	var outline := MultiMeshInstance3D.new()
	outline.multimesh = mm.multimesh
	outline.material_override = Geo.mat(INK_HULL, {"col": c(BLACK), "width": 0.03, "mode": 1})
	outline.set_meta("nohull", true)
	add_child(outline)

# Comic-Elemente, eigene Erfindung: Starburst mit "ZAP!" als Wandschild, Raster im Burst.
func _comic() -> void:
	var p := zap_pos
	var burst := _starburst(14, 3.2, 2.1)
	var mi := MeshInstance3D.new()
	mi.mesh = burst
	mi.material_override = prt(RED, BLACK, {"cov_lit": 0.0, "cov_mid": 0.0, "cov_shade": 0.0})
	mi.position = p
	mi.rotation.y = -PI / 2.0
	mi.set_meta("nohull", true)
	add_child(mi)
	var mi2 := MeshInstance3D.new()
	mi2.mesh = _starburst(14, 3.45, 2.3)
	mi2.material_override = prt(BLACK, BLACK, {"cov_lit": 0.0, "cov_mid": 0.0, "cov_shade": 0.0})
	mi2.position = p + Vector3(0.02, 0, 0)
	mi2.rotation.y = -PI / 2.0
	mi2.set_meta("nohull", true)
	add_child(mi2)
	var lbl := Label3D.new()
	lbl.text = "ZAP!"
	lbl.font_size = 160
	lbl.pixel_size = 0.006
	lbl.modulate = c(PAPER)
	lbl.outline_modulate = c(BLACK)
	lbl.outline_size = 28
	lbl.position = p + Vector3(-0.06, 0, 0)
	lbl.rotation.y = -PI / 2.0
	add_child(lbl)

func _starburst(points: int, r_out: float, r_in: float) -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	verts.append(Vector3.ZERO); norms.append(Vector3(0, 0, 1)); uvs.append(Vector2(0.5, 0.5))
	var n := points * 2
	for i in n:
		var a := float(i) / float(n) * TAU
		var r := r_out if i % 2 == 0 else r_in
		verts.append(Vector3(cos(a) * r, sin(a) * r * 0.7, 0))
		norms.append(Vector3(0, 0, 1))
		uvs.append(Vector2(0.5 + cos(a) * 0.5, 0.5 + sin(a) * 0.5))
	for i in n:
		idx.append(0); idx.append(1 + (i + 1) % n); idx.append(1 + i)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m

func views() -> Array:
	return [
		["strasse", Vector3(-1.4, 1.7, 17.0), Vector3(1.0, 4.5, -16.0), 72.0],
		["totale", Vector3(-30.0, 22.0, 30.0), Vector3(2.0, 6.0, -20.0), 62.0],
		["strand", Vector3(-9.5, 1.7, 4.0), Vector3(-30.0, 3.0, -30.0), 74.0],
		["capsule", Vector3(-4.0, 1.6, 2.0), Vector3(4.0, 8.0, -24.0), 60.0],
	]

func set_view(pos: Vector3, look: Vector3, fov: float) -> void:
	cam.position = pos
	cam.look_at(look)
	cam.fov = fov
