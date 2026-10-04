# Richtung A "Aquarell-Paris" – Stil-Prototyp (Art Director, Phase 1, NICHT Spielcode).
# Prinzip: Tusche-Linie + Lasur. Alle Flaechen sind Aquarell-Lasuren auf Papier (Shader:
# Pigment-Granulation im Weltraum, Papierkorn auf der Bildebene, Randverdunkelung an
# Flaechenkanten und Silhouetten, zwei Lichtstufen mit lila Schatten). Konturen sind
# Inverted-Hull-Linien in Sepia, die per Rauschen abreissen (nicht geschlossene Linie).
# Entfernung verblasst ins Papierweiss (Nebel = Luftperspektive).
extends Node3D

const Geo := preload("res://geo.gd")

var cam: Camera3D
var rng := RandomNumberGenerator.new()

const NOISE := """
float hash21(vec2 p){ p = fract(p*vec2(123.34, 456.21)); p += dot(p, p+45.32); return fract(p.x*p.y); }
float vnoise(vec2 p){ vec2 i=floor(p); vec2 f=fract(p); f=f*f*(3.0-2.0*f);
	float a=hash21(i), b=hash21(i+vec2(1,0)), c=hash21(i+vec2(0,1)), d=hash21(i+vec2(1,1));
	return mix(mix(a,b,f.x), mix(c,d,f.x), f.y); }
float fbm(vec2 p){ return 0.55*vnoise(p) + 0.3*vnoise(p*2.1+3.0) + 0.15*vnoise(p*4.3+7.0); }
"""

# Lasur-Shader: unshaded, eigene Sonne mit zwei Stufen; Papier scheint durch.
const WASH_SHADER := "shader_type spatial;\nrender_mode unshaded, cull_back, depth_draw_opaque;\n" + NOISE + """
uniform vec3 col : source_color = vec3(0.9, 0.86, 0.76);
uniform vec3 shade : source_color = vec3(0.79, 0.73, 0.79); // lila Schatten
uniform vec3 paper : source_color = vec3(0.97, 0.95, 0.91);
uniform vec3 edge_col : source_color = vec3(0.45, 0.38, 0.40);
uniform float density = 0.85;   // Pigmentdichte 0..1 (1 = deckend)
uniform float granul = 0.35;    // Granulation
uniform float edge = 0.045;     // Randverdunkelung (Anteil der Flaeche, Box-UV)
uniform float wobble = 0.03;    // Handzittern der Kanten in Metern
uniform int uvmode = 0;         // 0 Box-Atlas, 1 Kugel/Kapsel (Fresnel), 2 Plane
uniform vec3 sun = vec3(-0.5, 0.75, 0.4);
uniform float emit = 0.0;
uniform float alpha = 1.0;
varying vec3 wpos; varying vec3 wn; varying vec2 fuv;
void vertex(){
	vec3 wp = (MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
	// Kanten zittern: Verschiebung aus Weltposition (pro Flaeche konsistent)
	float w1 = vnoise(wp.yz*1.7 + 2.0) - 0.5; float w2 = vnoise(wp.xz*1.7 + 5.0) - 0.5; float w3 = vnoise(wp.xy*1.7 + 9.0) - 0.5;
	VERTEX += (inverse(MODEL_MATRIX) * vec4(vec3(w1, w2, w3)*wobble*2.0, 0.0)).xyz;
	wpos = wp;
	wn = normalize((MODEL_MATRIX*vec4(NORMAL,0.0)).xyz);
	fuv = (uvmode == 0) ? fract(UV*vec2(3.0, 2.0)) : UV;
}
void fragment(){
	// Pigment: Granulation im Weltraum (Lasur klebt am Objekt)
	vec2 g = (abs(wn.y) > 0.5) ? wpos.xz : ((abs(wn.x) > 0.5) ? wpos.zy : wpos.xy);
	float gran = fbm(g*2.3) ;
	float dens = clamp(density*(1.0 - granul*(gran-0.5)*2.0), 0.0, 1.0);
	// Randverdunkelung: Pigment sammelt sich am Rand der Lasur
	float e = 1.0;
	if (uvmode == 0) { float m = min(min(fuv.x, 1.0-fuv.x), min(fuv.y, 1.0-fuv.y)); e = smoothstep(0.0, edge, m); }
	else if (uvmode == 1) { float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0); e = smoothstep(0.0, 0.45, ndv); }
	float rim = (1.0 - e) * (0.6 + 0.4*vnoise(g*9.0));
	// zwei Lichtstufen, Schatten kippt ins Lila
	float l = dot(wn, normalize(sun));
	float lit = smoothstep(-0.05, 0.25, l);
	vec3 c = mix(shade, col, lit);
	// nass-in-nass: zweite, hellere Lasur blueht auf (grosse weiche Flecken)
	float bloom = smoothstep(0.55, 0.8, fbm(g*0.45 + 11.0));
	c = mix(c, mix(c, paper, 0.3), bloom*0.35);
	c = mix(c, edge_col, rim*0.55);
	c = mix(paper, c, dens);
	// Papierkorn auf der Bildebene
	float grain = vnoise(FRAGCOORD.xy*0.55) * 0.5 + vnoise(FRAGCOORD.xy*0.13)*0.5;
	c *= 0.93 + 0.1*grain;
	ALBEDO = c + c*emit;
	ALPHA = alpha;
}
"""

# Himmel: Papier mit blassblauer Lasur oben, Wolkenflecken nass-in-nass.
const SKY_SHADER := "shader_type spatial;\nrender_mode unshaded, cull_front, fog_disabled;\n" + NOISE + """
uniform vec3 paper : source_color = vec3(0.97, 0.95, 0.91);
uniform vec3 blue : source_color = vec3(0.70, 0.80, 0.88);
uniform vec3 grey : source_color = vec3(0.70, 0.73, 0.76);
varying vec3 dir;
void vertex(){ dir = normalize((MODEL_MATRIX*vec4(VERTEX,1.0)).xyz - CAMERA_POSITION_WORLD); }
void fragment(){
	vec2 p = vec2(atan(dir.x, -dir.z)*2.0, dir.y*3.0);
	float up = smoothstep(0.02, 0.5, dir.y);
	float wash = fbm(p*1.3 + vec2(TIME*0.01, 0.0));
	vec3 c = mix(paper, blue, up*(0.35 + 0.65*smoothstep(0.35, 0.7, wash)));
	float cloud = smoothstep(0.5, 0.62, fbm(p*0.9 + 20.0 + vec2(TIME*0.008, 0.0)));
	c = mix(c, grey, cloud*up*0.55);
	// Randverdunkelung der Wolkenlasur
	float ce = smoothstep(0.48, 0.5, fbm(p*0.9 + 20.0)) - cloud;
	c = mix(c, grey*0.85, clamp(ce, 0.0, 1.0)*0.5*up);
	float grain = vnoise(FRAGCOORD.xy*0.55);
	c *= 0.95 + 0.07*grain;
	ALBEDO = c;
}
"""

# Fluss: liegende Lasur, Spiegel als senkrecht verschmierte Flecken.
const WATER_SHADER := "shader_type spatial;\nrender_mode unshaded;\n" + NOISE + """
uniform vec3 col : source_color = vec3(0.56, 0.66, 0.75);
uniform vec3 deep : source_color = vec3(0.42, 0.53, 0.64);
uniform vec3 paper : source_color = vec3(0.97, 0.95, 0.91);
uniform vec3 refl : source_color = vec3(0.86, 0.80, 0.70);
varying vec3 wpos;
void vertex(){ wpos = (MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; }
void fragment(){
	vec2 p = wpos.xz;
	float band = fbm(vec2(p.x*0.15, p.y*1.2) + vec2(TIME*0.02, 0.0));
	vec3 c = mix(col, deep, smoothstep(0.4, 0.7, band));
	float r = smoothstep(0.55, 0.75, fbm(vec2(p.x*0.9, p.y*0.12) + 3.0));
	c = mix(c, refl, r*0.6);
	float light = smoothstep(0.6, 0.8, vnoise(vec2(p.x*0.8, p.y*2.5) + 9.0));
	c = mix(c, paper, light*0.5);
	float grain = vnoise(FRAGCOORD.xy*0.55);
	c *= 0.94 + 0.08*grain;
	ALBEDO = c;
}
"""

# Tusche-Kontur: Inverted Hull, bildschirmkonstant duenn, reisst per Rauschen ab.
const INK_HULL := "shader_type spatial;\nrender_mode unshaded, cull_front, fog_disabled;\n" + NOISE + """
uniform vec3 col : source_color = vec3(0.29, 0.23, 0.18);
uniform float width = 0.012;
uniform float px = 0.0;
uniform int mode = 0;
varying vec3 wpos;
void vertex(){
	vec3 dir = (mode == 0) ? sign(VERTEX) : NORMAL;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float dist = length(wpos - CAMERA_POSITION_WORLD);
	float w = width * (0.5 + dist * 0.07);
	vec3 scl = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	VERTEX += dir * w / scl;
}
void fragment(){
	float n = fbm(wpos.xy*1.3 + wpos.zz*0.7);
	if (n > 0.74) discard;   // Linie reisst ab
	ALBEDO = col * (0.9 + 0.2*vnoise(wpos.xz*8.0));
}
"""

const ORB_SHADER := """
shader_type spatial;
render_mode unshaded;
uniform vec3 col : source_color = vec3(0.96, 0.65, 0.14);
uniform vec3 core : source_color = vec3(1.0, 0.95, 0.84);
uniform float energy = 1.6;
void fragment(){
	float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	ALBEDO = mix(col, core, pow(ndv, 3.5)) * energy;
}
"""

const METRO_SHADER := "shader_type spatial;\nrender_mode unshaded;\n" + NOISE + """
uniform vec3 col : source_color = vec3(0.12, 0.64, 0.39);
uniform float energy = 1.3;
void fragment(){
	float p = 0.88 + 0.12*sin(TIME*3.14); // 0,5 Hz
	float g = 0.9 + 0.2*fbm(UV*6.0);
	ALBEDO = col*energy*p*g;
}
"""

func c(h: String) -> Color: return Color.html(h)

func wash(col: String, shade: String, params := {}) -> ShaderMaterial:
	var p := {"col": c(col), "shade": c(shade), "paper": c("#F7F2E8"), "edge_col": c("#6B5A60")}
	p.merge(params, true)
	return Geo.mat(WASH_SHADER, p)

func _ready() -> void:
	rng.seed = 1874
	cam = Camera3D.new()
	cam.near = 0.1
	cam.far = 900.0
	add_child(cam)
	cam.current = true
	_environment()
	_sky()
	_ground()
	_buildings()
	_trees()
	_metro()
	_life()
	_pellets()
	# Tusche auf alles, was nicht ausgenommen ist
	Geo.hull_all(self, c("#4A3B2E"), 0.03, 0.0, [], INK_HULL)

func _environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = c("#F7F2E8")
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.fog_enabled = true
	env.fog_light_color = c("#EFEAE0")
	env.fog_density = 0.0055
	env.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

func _sky() -> void:
	var s := Geo.sphere(self, Vector3(0, -30, 0), 600.0, Geo.mat(SKY_SHADER, {"paper": c("#F7F2E8"), "blue": c("#B9CEDF"), "grey": c("#B4BAC2")}), Vector3.ONE, 48)
	s.set_meta("nohull", true)

func _ground() -> void:
	# Gehweg/Fahrbahn: helle Lasur, Fahrbahn etwas grauer; Bordstein als Tuschekante
	var walk := wash("#E3D8C4", "#C9BCC6", {"uvmode": 2, "density": 0.8, "granul": 0.55, "edge": 0.0, "wobble": 0.0})
	var road := wash("#B9B2AC", "#9E97A6", {"uvmode": 2, "density": 0.9, "granul": 0.5, "edge": 0.0, "wobble": 0.0})
	var g := Geo.plane(self, Vector3(20, 0, -10), Vector2(70, 140), walk)  # endet am Quai (x = -15)
	g.set_meta("nohull", true)
	var r := Geo.box(self, Vector3(0, 0.02, -8), Vector3(9.0, 0.04, 70.0), road)
	r.set_meta("nohull", true)
	# Bordsteine als duenne Boxen (Tusche-Linie entsteht durch die Hull)
	var curb := wash("#D9D1C4", "#BFB4BE", {"density": 0.9, "wobble": 0.01})
	Geo.box(self, Vector3(-4.5, 0.08, -8), Vector3(0.25, 0.16, 70.0), curb)
	Geo.box(self, Vector3(4.5, 0.08, -8), Vector3(0.25, 0.16, 70.0), curb)
	# Seine links hinter dem Quai: Wasserflaeche tiefer, Quaimauer, Bruecke mit Boegen
	var water := Geo.plane(self, Vector3(-40, -3.0, -10), Vector2(50, 140), Geo.mat(WATER_SHADER, {"col": c("#7E9DB8"), "deep": c("#58789A"), "paper": c("#F7F2E8"), "refl": c("#D8CDB5")}))
	water.set_meta("nohull", true)
	var quai := wash("#DED3BF", "#C3B6C0", {"density": 0.85})
	Geo.box(self, Vector3(-15.5, -1.5, -10), Vector3(1.2, 3.0, 140.0), quai)
	Geo.box(self, Vector3(-15.0, 0.5, -10), Vector3(0.12, 1.0, 140.0), wash("#5E6A78", "#4A5262", {"density": 0.9}))  # Gelaender
	# Bruecke ueber die Seine (quer), drei Boegen
	var bridge := wash("#E2D7C2", "#C8BBC4", {"density": 0.85})
	Geo.box(self, Vector3(-40, 0.3, -46), Vector3(50, 0.8, 7.0), bridge)
	for bx in [-28.0, -40.0, -52.0]:
		var arch := Geo.cylinder(self, Vector3(bx, -2.6, -46), 4.2, 4.2, 7.4, bridge, 20)
		arch.rotation.x = PI/2
	# Laternen am Quai
	var lamp := wash("#4C5566", "#3A4150", {"density": 0.95, "wobble": 0.0})
	for lz in [14.0, 2.0, -10.0, -22.0, -34.0]:
		Geo.cylinder(self, Vector3(-14.2, 1.8, lz), 0.05, 0.08, 3.6, lamp, 8)
		Geo.sphere(self, Vector3(-14.2, 3.8, lz), 0.22, wash("#F3EBD2", "#D8CFC0", {"uvmode": 1, "density": 0.6}), Vector3.ONE, 12)

func _haussmann(pos: Vector3, w: float, d: float, facing_x: float) -> void:
	var stone := wash("#E6D2AC", "#CDBCC9", {"density": 0.92, "granul": 0.45})
	var zinc := wash("#7F8A99", "#5E6778", {"density": 0.95, "granul": 0.3})
	var win := wash("#4E5C70", "#3A4556", {"density": 0.95, "edge": 0.12, "wobble": 0.0})
	var iron := wash("#3F4650", "#2E333C", {"density": 0.95, "wobble": 0.0})
	var h := 19.0
	Geo.box(self, pos + Vector3(0, h/2, 0), Vector3(w, h, d), stone)
	# Mansarddach: steile Zinkflaeche + flacher Aufsatz
	Geo.box(self, pos + Vector3(0, h + 1.6, 0), Vector3(w * 0.92, 3.2, d * 0.92), zinc)
	Geo.box(self, pos + Vector3(0, h + 3.5, 0), Vector3(w * 0.7, 0.6, d * 0.7), zinc)
	# Fenster (hohe franzoesische Fenster), Balkone im 2. und 5. Stock (Haussmann-Regel)
	var nw: int = max(2, int(d / 2.6))
	for f in 6:
		var y := 1.8 + float(f) * 3.0
		if f == 0:
			y = 2.0
		for k in nw:
			var z := pos.z - d/2 + (float(k) + 0.5) * d / float(nw)
			Geo.box(self, Vector3(pos.x + facing_x * (w/2 + 0.03), y, z), Vector3(0.06, 2.2 if f > 0 else 2.8, 1.1), win)
		if f == 2 or f == 5:
			Geo.box(self, Vector3(pos.x + facing_x * (w/2 + 0.35), y - 1.0, pos.z), Vector3(0.7, 0.08, d - 0.4), iron)
			Geo.box(self, Vector3(pos.x + facing_x * (w/2 + 0.68), y - 0.5, pos.z), Vector3(0.05, 0.95, d - 0.4), iron)
	# Ladenfront mit Markise im Erdgeschoss (gedaempftes Bordeaux, kein Gruen, kein Gold)
	var awn := wash("#8E4A52", "#6E3A44", {"density": 0.9})
	if rng.randf() < 0.7:
		var aw := Geo.box(self, Vector3(pos.x + facing_x * (w/2 + 0.9), 3.3, pos.z + rng.randf_range(-d*0.2, d*0.2)), Vector3(1.8, 0.1, min(d*0.5, 6.0)), awn)
		aw.rotation.z = facing_x * 0.35
	# Gesims zwischen 1. und 2. Stock
	Geo.box(self, Vector3(pos.x + facing_x * (w/2 + 0.12), 4.9, pos.z), Vector3(0.25, 0.25, d), stone)
	# Dachgauben
	for k in int(nw / 2):
		var z := pos.z - d/2 + (float(k) + 0.5) * d / float(int(nw/2))
		Geo.box(self, Vector3(pos.x + facing_x * (w * 0.46), h + 1.3, z), Vector3(0.6, 1.3, 1.0), stone)

func _buildings() -> void:
	# Boulevard: Haussmann-Blocks rechts von z=20 bis z=-40, links nur bis zum Quai-Platz
	var z := 22.0
	while z > -42.0:
		var d := rng.randf_range(10.0, 16.0)
		_haussmann(Vector3(4.6 + 7.0, 0, z - d/2), 14.0, d, -1.0)
		z -= d + 0.2
	z = 22.0
	while z > 4.0:
		var d := rng.randf_range(9.0, 13.0)
		if z - d < 3.0:
			d = z - 3.0
		_haussmann(Vector3(-4.6 - 7.0, 0, z - d/2), 14.0, d, 1.0)
		z -= d + 0.2
	# Ferne Kuppel und Daecher jenseits der Seine (Silhouette, hell verblasst)
	var far := wash("#D8D3CC", "#C4BECB", {"density": 0.55, "granul": 0.5})
	for k in 9:
		var x := -75.0 + k * 9.0
		Geo.box(self, Vector3(x, 8.0, -70.0 - rng.randf_range(0, 10)), Vector3(8.0, 16.0 + rng.randf_range(-3, 6), 8.0), far)
	var dome := Geo.sphere(self, Vector3(-48, 24, -78), 7.0, far, Vector3.ONE, 20)
	Geo.cylinder(self, Vector3(-48, 12, -78), 7.5, 8.0, 24.0, far, 20)
	Geo.cylinder(self, Vector3(-48, 33, -78), 0.3, 1.2, 5.0, far, 8)

func _trees() -> void:
	# Kahle Platanen am Quai: Stamm, Aeste als duenne Boxen, lila-graue Lasur-Wolke
	var bark := wash("#B8AFA4", "#9A8F9A", {"density": 0.75, "uvmode": 1})
	var crown := wash("#BFAFC4", "#A897B0", {"density": 0.7, "granul": 0.8, "uvmode": 1, "edge": 0.0, "alpha": 0.38})
	for tz in [12.0, 3.0, -6.0, -15.0, -24.0, -33.0]:
		var p := Vector3(-11.5, 0, tz)
		Geo.cylinder(self, p + Vector3(0, 2.4, 0), 0.16, 0.3, 4.8, bark, 8)
		var top := p + Vector3(0, 4.8, 0)
		for i in 8:
			var a := rng.randf() * TAU
			var tilt := rng.randf_range(0.3, 0.75)
			var dir := Vector3(cos(a) * sin(tilt), cos(tilt), sin(a) * sin(tilt))
			var L := rng.randf_range(3.2, 4.4)
			var b := Geo.box(self, top + dir * L / 2.0, Vector3(0.09, L, 0.09), bark)
			b.basis = Basis(Quaternion(Vector3.UP, dir))
			for j in 2:
				var a2 := a + rng.randf_range(-0.9, 0.9)
				var t2 := tilt + rng.randf_range(0.1, 0.5)
				var d2 := Vector3(cos(a2) * sin(t2), cos(t2), sin(a2) * sin(t2))
				var L2 := rng.randf_range(1.6, 2.6)
				var tw := Geo.box(self, top + dir * L * rng.randf_range(0.6, 1.0) + d2 * L2 / 2.0, Vector3(0.05, L2, 0.05), bark)
				tw.basis = Basis(Quaternion(Vector3.UP, d2))
		var cr := Geo.sphere(self, p + Vector3(0, 8.6, 0), 2.8, crown, Vector3(1.0, 0.75, 1.0), 16)
		cr.set_meta("nohull", true)

func _metro() -> void:
	# U-Bahn-Eingang am Ende des Boulevards (rechter Gehweg): geschwungener Rahmen, gruenes
	# Portal (einzige gefuellte, gesaettigte Gruenflaeche), Schild mit Allgemeinwort.
	var green := wash("#3F8F62", "#2E6E4A", {"density": 0.95, "wobble": 0.0})
	var p := Vector3(6.4, 0, -36.0)
	for sx in [-1.6, 1.6]:
		var post := Geo.cylinder(self, p + Vector3(sx, 1.6, 0), 0.08, 0.12, 3.2, green, 8)
		post.rotation.z = -sx * 0.12
		var bend := Geo.cylinder(self, p + Vector3(sx * 0.7, 3.4, 0), 0.07, 0.08, 1.8, green, 8)
		bend.rotation.z = -sx * 1.1
	Geo.box(self, p + Vector3(0, 3.9, 0), Vector3(2.8, 0.7, 0.14), green)
	var portal := Geo.quad(self, p + Vector3(0, 1.3, -0.3), Vector2(2.9, 2.6), Geo.mat(METRO_SHADER, {"col": c("#1FA463")}))
	portal.set_meta("nohull", true)
	# Treppe hinunter als gruene Flaeche am Boden
	var stairs := Geo.box(self, p + Vector3(0, 0.03, 1.4), Vector3(2.9, 0.06, 2.6), Geo.mat(METRO_SHADER, {"col": c("#1FA463"), "energy": 1.0}))
	stairs.set_meta("nohull", true)
	var lbl := Label3D.new()
	lbl.text = "MÉTRO"
	lbl.font_size = 120
	lbl.pixel_size = 0.005
	lbl.modulate = c("#F7F2E8")
	lbl.outline_modulate = c("#1C4A32")
	lbl.outline_size = 16
	lbl.position = p + Vector3(0, 3.9, 0.1)
	add_child(lbl)

func _life() -> void:
	var coat := wash("#3F4A5C", "#2E3644", {"uvmode": 1, "density": 0.9})
	var coat2 := wash("#7A6A5A", "#5E5048", {"uvmode": 1, "density": 0.85})
	var skin := wash("#E8C9A8", "#CBA890", {"uvmode": 1, "density": 0.7})
	var figs := [
		[Vector3(-6.2, 0, 8.0), 0.4], [Vector3(6.0, 0, -4.0), -0.6], [Vector3(-13.2, 0, -2.0), 1.6], [Vector3(6.6, 0, -20.0), 1.2],
		[Vector3(-7.0, 0, -14.0), 0.0], [Vector3(5.6, 0, -30.0), 2.4], [Vector3(-13.0, 0, -20.0), 3.0], [Vector3(-6.4, 0, -28.0), -1.0],
	]
	var i := 0
	for f in figs:
		var n := Geo.figure(self, f[0], coat if i % 3 != 1 else coat2, skin, f[1])
		# Regenschirm als flache Scheibe in einer Tusche-Linie
		if i % 2 == 0:
			var umb := Geo.cylinder(n, Vector3(0, 1.95, 0), 0.0, 0.55, 0.25, coat2 if i % 3 != 1 else coat, 10)
		i += 1
	# Fahrzeuge: zwei Wagen in gedaempftem Blaugrau, ein Bus-Kasten
	var car := wash("#6E7F93", "#55647A", {"density": 0.85})
	var wheel := wash("#3A3F48", "#2A2E36", {"density": 0.95, "uvmode": 1})
	var glass := wash("#B7C3CE", "#97A5B5", {"density": 0.7})
	Geo.car(self, Vector3(2.2, 0, 2.0), 0.0, car, wheel, glass)
	Geo.car(self, Vector3(-2.2, 0, -16.0), PI, wash("#8C8A84", "#6E6C6E", {"density": 0.85}), wheel, glass)
	var bus := Node3D.new()
	bus.position = Vector3(2.4, 0, -26.0)
	add_child(bus)
	Geo.box(bus, Vector3(0, 1.6, 0), Vector3(2.4, 2.6, 9.0), wash("#C8D2CE", "#A9B3B5", {"density": 0.8}))
	Geo.box(bus, Vector3(0, 2.0, 0), Vector3(2.5, 0.9, 8.6), glass)
	for sz in [-3.0, 3.0]:
		for sx in [-1.2, 1.2]:
			var w := Geo.cylinder(bus, Vector3(sx, 0.45, sz), 0.45, 0.45, 0.25, wheel, 12)
			w.rotation.z = PI/2

func _pellets() -> void:
	var pts := Geo.pellet_line(Vector3(0, 0.55, 16.0), Vector3(0, 0.55, -34.0), 2.0)
	pts += Geo.pellet_line(Vector3(2.0, 0.55, -36.0), Vector3(5.0, 0.55, -36.0), 1.5)
	pts += Geo.pellet_line(Vector3(-6.0, 0.55, -10.0), Vector3(-13.0, 0.55, -10.0), 2.0)
	var mm := Geo.pellets(self, pts, 0.24, Geo.mat(ORB_SHADER, {"col": c("#F5A623"), "core": c("#FFF1D6"), "energy": 1.25}))
	mm.set_meta("nohull", true)

func views() -> Array:
	return [
		["strasse", Vector3(-1.2, 1.7, 15.0), Vector3(0.8, 4.0, -16.0), 72.0],
		["totale", Vector3(-34.0, 30.0, 34.0), Vector3(0.0, 6.0, -22.0), 60.0],
		["quai", Vector3(-13.3, 1.7, -4.0), Vector3(-34.0, 4.0, -44.0), 74.0],
		["capsule", Vector3(-3.0, 1.6, 6.0), Vector3(2.0, 9.0, -24.0), 60.0],
	]

func set_view(pos: Vector3, look: Vector3, fov: float) -> void:
	cam.position = pos
	cam.look_at(look)
	cam.fov = fov
