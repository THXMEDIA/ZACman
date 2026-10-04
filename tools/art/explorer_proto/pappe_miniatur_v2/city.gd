# Richtung J v2 "Pappmodell Amsterdam 1:100" – Realismus und Look-Varianten (Art Director, 04.10.2026).
# NICHT Spielcode. Baut auf v1 (pappe_miniatur/city.gd) auf:
#  - Foto-Ebene: echter CC0-Kartonscan (Poly Haven) als Makro-Variation auf allen Pappflaechen,
#    Tischplatte aus einem CC0-Holzscan (ambientCG), Umgebung aus CC0-HDRIs (Poly Haven).
#  - Kaimauern mit ECHTER Wellen-Geometrie (doppelwellige Platte, offene Hohlraeume mit Schatten).
#  - Modellbau-Spuren: Bleistift-Anriss, Leimtropfen, Ueberschnitte an Fensterecken, Klebestreifen,
#    leicht schiefe Haeuser und vorstehende Teile, Schneidematte, Stahllineal, Stecknadeln.
#  - Wahrzeichen-Typologie: Amsterdamer Zugbruecke (generisch, kein bestimmtes Bauwerk).
#  - Licht-/Stimmungsvarianten ueber VARIANT = atelier | abend | studio | nacht.
#  - Optik als Vollbild-Shader (laeuft auch im Compatibility-Renderer): Tiefenunschaerfe/Tilt-Shift,
#    Vignette, statisches Korn, Farbabstimmung. REDUCE_FX=1 schaltet Unschaerfe und Korn ab.
# Kugeln = blaue Glaskopf-Stecknadeln, Ausgang = gruen gestrichene Papp-Strassenbahn.
extends Node3D

const P := preload("res://pappe.gd")
const Geo := preload("res://geo.gd")

var cam: Camera3D
var rng := RandomNumberGenerator.new()
var reduce_fx := false
var variant := "atelier"
var panels: Array = []
var paint_panels: Array = []
var white_panels: Array = []
var cuts: Array = []          # Ueberschnitte (dunkle Striche)
var glue: Array = []          # Leimtropfen
var root3: Node3D
var face_m: ShaderMaterial
var edge_m: ShaderMaterial
var post_m: ShaderMaterial
var scan := {}
var view_fx := {}

const T := 0.4          # Pappstaerke auf Ameisenhoehe (4 mm x 100)
const PITCH := 0.7      # Wellenteilung (7 mm x 100)
const CANAL := 4.0      # Grachten-Halbbreite
const QUAY := 9.5       # Fassadenflucht
const KD := 1.2         # Tiefe der offenen Wellen-Hohlraeume an der Kaimauer

func _init() -> void:
	rng.seed = 1675
	reduce_fx = OS.get_environment("REDUCE_FX") == "1"
	if OS.get_environment("VARIANT") != "":
		variant = OS.get_environment("VARIANT")
	root3 = Node3D.new()
	add_child(root3)
	_load_scans()
	face_m = P.flat_mat({"tile_m": 2.6, "far_flat": 60.0})
	_foto(face_m, 1.0)
	edge_m = P.mat(P.EDGE_SHADER, {"thick": T, "pitch": PITCH, "tile_m": 2.6})
	_env()
	_base()
	_quay_edge(1.0)
	_quay_edge(-1.0)
	_row(1.0)
	_row(-1.0)
	_bridge(-16.0)
	_drawbridge(-31.0)
	_trees()
	_tram()
	_desk()
	_pins()
	_marks()
	var pm := P.mat(P.BOX_SHADER, {"panel": 1.0, "edge_pitch": PITCH, "rib_pitch": PITCH, "rib_amp": 0.25, "tile_m": 2.6, "bulge": 0.0, "edge_ao": 0.8, "far_flat": 60.0})
	_foto(pm, 1.0)
	P.boxes(root3, panels, pm)
	var gm := P.mat(P.BOX_SHADER, {"panel": 1.0, "edge_pitch": PITCH, "rib_pitch": PITCH, "tile_m": 2.6, "bulge": 0.0,
		"paint": 1.0, "paint_col": Color("#00B894"), "paint_emit": 0.14})   # Vorschlag statt #1FA855 (Rot-Gruen-Schwaeche, s. Doku)
	_foto(gm, 0.6)
	P.boxes(root3, paint_panels, gm)
	var wm := P.mat(P.BOX_SHADER, {"panel": 0.0, "tape_prob": 0.0, "hole_prob": 0.0, "tile_m": 2.6, "bulge": 0.0, "edge_ao": 0.85,
		"paint": 1.15, "paint_col": Color("#E9E4D8"), "paint_emit": 0.0})
	_foto(wm, 0.5)
	P.boxes(root3, white_panels, wm)
	_cuts_and_glue()
	cam = Camera3D.new()
	cam.near = 0.05
	cam.far = 900.0
	add_child(cam)
	_post()

# ------------------------------------------------------------------ Scans (CC0) laden
func _load_scans() -> void:
	for n in ["kraft_foto_albedo", "kraft_foto_normal", "kraft_foto_rough", "tape_foto_albedo", "tape_foto_normal", "holz_albedo", "holz_normal", "holz_rough"]:
		var img := Image.load_from_file(ProjectSettings.globalize_path("res://scans/%s.jpg" % n))
		img.generate_mipmaps()
		scan[n] = ImageTexture.create_from_image(img)
	for n in ["matte", "lineal", "anriss_a", "anriss_b"]:
		var img2 := Image.load_from_file(ProjectSettings.globalize_path("res://prints/%s.png" % n))
		img2.generate_mipmaps()
		scan[n] = ImageTexture.create_from_image(img2)

func _foto(m: ShaderMaterial, amt: float) -> void:
	m.set_shader_parameter("foto", amt)
	m.set_shader_parameter("foto_m", 38.0)
	m.set_shader_parameter("foto_alb", scan["kraft_foto_albedo"])
	m.set_shader_parameter("foto_nrm", scan["kraft_foto_normal"])
	m.set_shader_parameter("foto_rgh", scan["kraft_foto_rough"])

# ------------------------------------------------------------------ Licht und Stimmung
func _hdr(name: String) -> ImageTexture:
	var img := Image.load_from_file(ProjectSettings.globalize_path("res://prints/hdri_%s_unscharf.hdr" % name))
	img.convert(Image.FORMAT_RGBH)   # RGBE9995 zeigt der Compatibility-Renderer nicht als Himmel
	return ImageTexture.create_from_image(img)

func _env() -> void:
	var sky := Sky.new()
	var pm := PanoramaSkyMaterial.new()
	pm.panorama = _hdr(variant)
	sky.sky_material = pm
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 6.0
	env.fog_enabled = true
	env.fog_sky_affect = 0.0
	# Glow aus: im Compatibility-Renderer verschiebt der Glow-Zwischenpuffer die Werte, die der
	# Optik-Shader liest (Bild wird zu dunkel). Im Spiel (Forward+) Glow wieder an.
	env.glow_enabled = false
	env.adjustment_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 160.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	add_child(sun)
	# Rueckstrahlung: braune Pappe wirft warmes Licht in alle Schatten (Ersatz fuer GI im Fallback)
	var bounce := DirectionalLight3D.new()
	bounce.shadow_enabled = false
	bounce.light_specular = 0.0
	add_child(bounce)
	bounce.transform = Transform3D(Basis.looking_at(Vector3(0.2, 1.0, 0.1).normalized(), Vector3.FORWARD), Vector3.ZERO)
	match variant:
		"atelier":
			# Grosses Nordfenster: kuehles, helles Tageslicht, weiche Schatten, heller Raum dahinter
			env.background_energy_multiplier = 2.0
			env.ambient_light_energy = 0.12
			env.sky_rotation = Vector3(0, deg_to_rad(180), 0)   # Fenster am Ende der Strasse (Gegenlicht im Hintergrund)
			env.tonemap_exposure = 0.8
			env.fog_light_color = Color("#E6E1D8")
			env.fog_density = 0.0035
			env.adjustment_contrast = 1.06
			env.adjustment_saturation = 1.0
			sun.light_color = P.kelvin(5600)
			sun.light_energy = 1.1
			sun.shadow_blur = 2.6
			sun.transform = Transform3D(Basis.looking_at(Vector3(-0.55, -0.62, -0.42).normalized(), Vector3.UP), Vector3.ZERO)
			bounce.light_color = Color("#C89A66")
			bounce.light_energy = 0.22
		"abend":
			# Goldene Stunde: tiefe Sonne quer ueber die Gracht, lange Schatten, warme Schreibtischlampe
			env.background_energy_multiplier = 1.8
			env.ambient_light_energy = 0.28
			env.sky_rotation = Vector3(0, deg_to_rad(110), 0)
			env.tonemap_exposure = 0.76
			env.fog_light_color = Color("#E9C79C")
			env.fog_density = 0.004
			env.adjustment_contrast = 1.1
			env.adjustment_saturation = 1.08
			sun.light_color = P.kelvin(2900)
			sun.light_energy = 2.0
			sun.shadow_blur = 1.4
			sun.transform = Transform3D(Basis.looking_at(Vector3(0.5, -0.24, -0.83).normalized(), Vector3.UP), Vector3.ZERO)
			bounce.light_color = Color("#D08A4A")
			bounce.light_energy = 0.3
			var lamp := P.spot(root3, Vector3(-150, 170, -95), Vector3(4, 0, -22), P.kelvin(2700), 0.5, 16.0, 600.0, 0.0, true)
			lamp.spot_attenuation = 0.0
			lamp.spot_angle_attenuation = 1.6
			lamp.shadow_blur = 2.0
		"studio":
			# Architekturmodell-Fotografie: grosser weicher Leuchtkasten, dunkler Studio-Hintergrund
			env.background_energy_multiplier = 1.4
			env.ambient_light_energy = 0.42
			env.sky_rotation = Vector3(0, deg_to_rad(30), 0)
			env.tonemap_exposure = 1.1
			env.fog_light_color = Color("#9A9894")
			env.fog_density = 0.002
			env.adjustment_contrast = 1.12
			env.adjustment_saturation = 0.94
			sun.light_color = P.kelvin(5000)
			sun.light_energy = 1.0
			sun.shadow_blur = 6.0
			sun.transform = Transform3D(Basis.looking_at(Vector3(0.45, -0.8, -0.35).normalized(), Vector3.UP), Vector3.ZERO)
			bounce.light_color = Color("#B89A7A")
			bounce.light_energy = 0.18
			var rim := DirectionalLight3D.new()
			rim.light_color = P.kelvin(6500)
			rim.light_energy = 0.55
			rim.shadow_enabled = false
			add_child(rim)
			rim.transform = Transform3D(Basis.looking_at(Vector3(-0.3, -0.35, 0.88).normalized(), Vector3.UP), Vector3.ZERO)
		"nacht":
			# Nacht im Atelier: Lichterkette ueber der Gracht, eine Taschenlampe liegt auf dem Tisch
			env.background_energy_multiplier = 0.25
			env.ambient_light_energy = 0.2
			env.sky_rotation = Vector3(0, deg_to_rad(0), 0)
			env.tonemap_exposure = 1.25
			env.fog_light_color = Color("#2A2018")
			env.fog_density = 0.003
			env.adjustment_contrast = 1.05
			env.adjustment_saturation = 1.05
			sun.light_color = P.kelvin(8000)
			sun.light_energy = 0.12
			sun.shadow_blur = 3.0
			sun.transform = Transform3D(Basis.looking_at(Vector3(-0.3, -0.7, -0.6).normalized(), Vector3.UP), Vector3.ZERO)
			bounce.light_color = Color("#C27A3A")
			bounce.light_energy = 0.04
			_fairy_lights()
			var torch := P.spot(root3, Vector3(44, 2.0, 46), Vector3(5, 1.0, -20), P.kelvin(5600), 3.5, 9.0, 300.0, 0.0, true)
			torch.spot_attenuation = 0.0
			torch.spot_angle_attenuation = 2.2
			_torch_body(Vector3(44, 2.0, 46), Vector3(5, 1.0, -20))

func _fairy_lights() -> void:
	# Lichterkette: Draht in Kettenlinien von Giebel zu Giebel ueber die Gracht, Birnen 5 mm (= 0,5 m)
	var wire := StandardMaterial3D.new()
	wire.albedo_color = Color(0.05, 0.06, 0.05)
	wire.roughness = 0.5
	var bulb := StandardMaterial3D.new()
	bulb.albedo_color = Color(0.9, 0.6, 0.3)
	bulb.emission_enabled = true
	bulb.emission = Color(1.0, 0.55, 0.2)
	bulb.emission_energy_multiplier = 1.6
	var lights := 0
	for zc in [8.0, -6.0, -24.0, -38.0]:
		var a := Vector3(-QUAY + 0.6, 10.5, zc + 2.0)
		var b := Vector3(QUAY - 0.6, 10.0, zc - 2.5)
		var n := 24
		var prev := a
		for i in range(1, n + 1):
			var t := float(i) / n
			var p := a.lerp(b, t) + Vector3.DOWN * 3.2 * 4.0 * t * (1.0 - t)
			var seg := Geo.cylinder(root3, (prev + p) * 0.5, 0.04, 0.04, prev.distance_to(p), wire, 6)
			seg.look_at_from_position((prev + p) * 0.5, p, Vector3.UP if abs((p - prev).normalized().y) < 0.95 else Vector3.FORWARD)
			seg.rotate_object_local(Vector3.RIGHT, PI * 0.5)
			if i % 2 == 0 and i < n:
				Geo.sphere(root3, p + Vector3(0, -0.35, 0), 0.26, bulb, Vector3(1, 1.4, 1), 12)
				if i % 6 == 0 and lights < 16:
					P.omni(root3, p + Vector3(0, -0.6, 0), P.kelvin(2300), 1.6, 11.0)
					lights += 1
			prev = p

func _torch_body(pos: Vector3, target: Vector3) -> void:
	# Taschenlampe (generisch, dunkles Alu) liegt auf der Schneidematte und leuchtet ins Modell
	var alu := StandardMaterial3D.new()
	alu.albedo_color = Color(0.13, 0.13, 0.14)
	alu.metallic = 0.8
	alu.roughness = 0.35
	var t := Node3D.new()
	root3.add_child(t)
	t.look_at_from_position(pos, target, Vector3.UP)
	var body := Geo.cylinder(t, Vector3(0, 0, 9.0), 2.0, 2.0, 18.0, alu, 32)
	body.rotation.x = PI * 0.5
	var head := Geo.cylinder(t, Vector3(0, 0, -1.0), 2.8, 2.2, 3.0, alu, 32)
	head.rotation.x = PI * 0.5
	var lens := StandardMaterial3D.new()
	lens.emission_enabled = true
	lens.emission = Color(1.0, 0.97, 0.9)
	lens.emission_energy_multiplier = 6.0
	var ln := Geo.cylinder(t, Vector3(0, 0, -2.55), 2.5, 2.5, 0.1, lens, 32)
	ln.rotation.x = PI * 0.5

# ------------------------------------------------------------------ Grundplatte
func _panel(list: Array, center: Vector3, size: Vector3, b := -1.0) -> void:
	list.append({"p": center, "s": size, "t": 0.0, "i": 0.0, "b": rng.randf() if b < 0.0 else b, "seed": rng.randf()})

func _base() -> void:
	# Kaiflaechen: Plattenstuecke (doppelwellig, 10 mm = 1 m). Die vorderen KD Meter zur Gracht
	# baut _quay_edge mit echter Wellen-Geometrie.
	for sx in [-1.0, 1.0]:
		_panel(panels, Vector3(sx * (CANAL + KD + (20.0 - KD) * 0.5), -0.5, -14.0), Vector3(20.0 - KD, 1.0, 72.0), 0.55)
	# Grachtenboden (duenner Karton auf der Matte) und Wasser
	_panel(panels, Vector3(0, -0.95, -14.0), Vector3(2 * CANAL + 0.2, 0.1, 72.0), 0.3)
	var w := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(2 * CANAL, 72.0)
	w.mesh = pm
	w.position = Vector3(0, -0.85, -14.0)
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.075, 0.055, 0.038)
	wm.roughness = 0.05
	wm.metallic_specular = 0.7
	wm.normal_enabled = true
	wm.normal_texture = P.tex["tape_normal"]
	wm.normal_scale = 0.3
	wm.uv1_scale = Vector3(1.2, 6.0, 1.0)
	wm.clearcoat_enabled = true
	wm.clearcoat = 1.0
	wm.clearcoat_roughness = 0.03
	w.material_override = wm
	root3.add_child(w)
	_panel(panels, Vector3(0, -0.5, -46.5), Vector3(2 * CANAL + 0.4, 1.0, 7.0), 0.6)
	# Plattenstoss quer ueber die Strasse (zwei Platten stumpf gestossen, mit Klebeband gesichert)
	for sx in [-1.0, 1.0]:
		_tape(Vector3(sx * (CANAL + 3.2), 0.012, -4.0), Vector2(3.6, 1.6), PI * 0.5 + rng.randf_range(-0.04, 0.04))
	_tape(Vector3(CANAL + 14.0, 0.012, 21.0), Vector2(5.0, 1.6), rng.randf_range(-0.1, 0.1))
	_tape(Vector3(-CANAL - 15.0, 0.012, 21.2), Vector2(4.0, 1.6), rng.randf_range(-0.1, 0.1))

func _tape(pos: Vector3, size: Vector2, rot_y: float, up := Vector3.UP) -> void:
	# Klebestreifen aus dem Foto-Scan (19 mm Band = 1,9 m); leicht glaenzend, Rand minimal erhaben
	var m := StandardMaterial3D.new()
	m.albedo_texture = scan["tape_foto_albedo"]
	m.normal_enabled = true
	m.normal_texture = scan["tape_foto_normal"]
	m.roughness = 0.32
	m.metallic_specular = 0.6
	m.uv1_scale = Vector3(size.x / 4.0, 1.0, 1.0)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(size.x, 0.02, size.y)
	mi.mesh = bm
	mi.material_override = m
	mi.position = pos
	mi.rotation.y = rot_y
	root3.add_child(mi)

# Kaimauer = Schnittkante der Grundplatte, gebaut aus Deckpapieren (Platten) und gewellten Bahnen
# (Mesh), die KD Meter tief in die Platte laufen. Hohlraeume sind echt offen und werfen Schatten.
func _quay_edge(side: float) -> void:
	var x0 := side * CANAL                 # Schnittebene
	var z0 := 22.0
	var z1 := -50.0
	var L := z0 - z1
	var lt := 0.07
	# Deckpapiere: unten, Mitte, oben (Doppelwelle B+C)
	for yy in [-1.0 + lt * 0.5, -0.5, -lt * 0.5]:
		panels.append({"p": Vector3(x0 + side * KD * 0.5, yy, (z0 + z1) * 0.5), "s": Vector3(KD, lt, L), "t": 0.0, "i": 0.0, "b": 0.55, "seed": rng.randf()})
	# Rueckwand der Hohlraeume (dunkel, Leim und Faserreste)
	var back := StandardMaterial3D.new()
	back.albedo_color = Color(0.09, 0.06, 0.04)
	back.roughness = 1.0
	var bq := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(L, 1.0)
	bq.mesh = qm
	bq.material_override = back
	bq.position = Vector3(x0 + side * (KD - 0.01), -0.5, (z0 + z1) * 0.5)
	bq.rotation.y = -side * PI * 0.5
	root3.add_child(bq)
	# Wellen: zwei Lagen, B-Welle (flacher, enger) unten, C-Welle oben
	var fm := StandardMaterial3D.new()
	fm.albedo_texture = scan["kraft_foto_albedo"]
	fm.vertex_color_use_as_albedo = true
	fm.roughness = 0.92
	fm.cull_mode = BaseMaterial3D.CULL_DISABLED
	fm.uv1_scale = Vector3(1.0 / 6.0, 1.0 / 6.0, 1.0)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for layer in [[-1.0 + lt, -0.5 - lt * 0.5, PITCH * 0.72], [-0.5 + lt * 0.5, -lt, PITCH]]:
		var ya: float = layer[0]
		var yb: float = layer[1]
		var pit: float = layer[2]
		var mid := (ya + yb) * 0.5
		var amp := (yb - ya) * 0.5 - 0.025
		var th := 0.05
		var segs := int(L / pit * 14.0)
		for i in segs:
			var za := z0 - L * float(i) / segs
			var zb := z0 - L * float(i + 1) / segs
			var wa := mid + amp * sin((za + rng.randf_range(-0.002, 0.002)) * TAU / pit)
			var wb := mid + amp * sin(zb * TAU / pit)
			for off in [-th * 0.5, th * 0.5]:
				# Wellenbahn laeuft von der Schnittebene (d=0) bis zur Rueckwand (d=KD); dunkler mit Tiefe
				for k in 3:
					var d0 := KD * k / 3.0
					var d1 := KD * (k + 1) / 3.0
					var c0: Color = Color(1, 1, 1) * lerp(1.0, 0.18, pow(d0 / KD, 0.7))
					var c1: Color = Color(1, 1, 1) * lerp(1.0, 0.18, pow(d1 / KD, 0.7))
					var q := [Vector3(x0 + side * d0, wa + off, za), Vector3(x0 + side * d0, wb + off, zb), Vector3(x0 + side * d1, wb + off, zb), Vector3(x0 + side * d1, wa + off, za)]
					var cc := [c0, c0, c1, c1]
					var nrm := Vector3(0, sign(off), 0)
					for idx in [0, 1, 2, 0, 2, 3]:
						st.set_color(cc[idx])
						st.set_normal(nrm)
						st.set_uv(Vector2(q[idx].z, q[idx].y + q[idx].x))
						st.add_vertex(q[idx])
			# Stirnseite der Wellenbahn in der Schnittebene (heller Papierstreifen)
			var f := [Vector3(x0, wa - th * 0.5, za), Vector3(x0, wb - th * 0.5, zb), Vector3(x0, wb + th * 0.5, zb), Vector3(x0, wa + th * 0.5, za)]
			for idx in [0, 1, 2, 0, 2, 3]:
				st.set_color(Color(1.08, 1.05, 1.0))
				st.set_normal(Vector3(-side, 0, 0))
				st.set_uv(Vector2(f[idx].z, f[idx].y))
				st.add_vertex(f[idx])
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = fm
	root3.add_child(mi)

# ------------------------------------------------------------------ Haeuser
func _row(side: float) -> void:
	var z := 20.0
	var kinds := [0, 1, 2, 3, 1, 0, 2, 1, 3, 0, 2, 1]
	var i := 0
	while z > -42.0:
		var w := rng.randf_range(5.0, 7.2)
		if side > 0.0 and z - w < -40.0:
			break
		var floors := rng.randi_range(3, 4)
		_house(side, z, w, floors, kinds[i % kinds.size()])
		z -= w + 0.02
		i += 1

# Panel eines Hauses: Fertigungsfehler (leichte Neigung des ganzen Hauses, vereinzelt vorstehende Teile)
var _lean := 0.0
var _pivot := Vector3.ZERO
func _hp(center: Vector3, size: Vector3, b: float, list: Array = panels) -> void:
	var rel := center - _pivot
	var p := _pivot + Basis(Vector3.BACK, _lean) * rel
	if rng.randf() < 0.07:
		p.x += rng.randf_range(-0.05, 0.05)
	list.append({"p": p, "s": size, "rz": _lean + rng.randf_range(-0.002, 0.002), "t": 0.0, "i": 0.0, "b": b, "seed": rng.randf()})

func _house(side: float, z0: float, w: float, floors: int, kind: int) -> void:
	var x := side * QUAY
	var fh := 3.3
	var zc := z0 - w * 0.5
	var nwin := 3 if w > 5.6 else 2
	var ww := 1.15
	var pier := (w - nwin * ww) / (nwin + 1)
	var bri := rng.randf_range(0.25, 0.85)
	var H := floors * fh
	_pivot = Vector3(x, 0, zc)
	_lean = rng.randf_range(-0.006, 0.006)
	var xf := x - side * T * 0.5       # Vorderflaeche der Fassade
	for f in floors:
		var y0 := f * fh
		var yb := y0 + (0.9 if f > 0 else 0.0)
		var yt := yb + (2.0 if f > 0 else 2.7)
		if f > 0:
			_hp(Vector3(x, (y0 + yb) * 0.5, zc), Vector3(T, yb - y0, w), bri)
		else:
			for k in nwin:
				var bz := z0 - pier - k * (ww + pier) - ww * 0.5
				if k != nwin / 2:
					_hp(Vector3(x, 0.45, bz), Vector3(T, 0.9, ww), bri)
		for k in nwin + 1:
			var pz := z0 - k * (ww + pier) - pier * 0.5
			_hp(Vector3(x, (yb + yt) * 0.5, pz), Vector3(T, yt - yb, pier), bri)
		_hp(Vector3(x, (yt + y0 + fh) * 0.5, zc), Vector3(T, y0 + fh - yt, w), bri)
		for k in nwin:
			var bz := z0 - pier - k * (ww + pier) - ww * 0.5
			if f == 0 and k == nwin / 2:
				continue
			_hp(Vector3(x + side * 0.08, (yb + yt) * 0.5 + (0.25 if f > 0 else 0.0), bz), Vector3(0.14, 0.14, ww), bri)
			_hp(Vector3(x + side * 0.08, (yb + yt) * 0.5, bz), Vector3(0.14, yt - yb, 0.14), bri)
			# Ueberschnitte: das Cuttermesser ist an den Fensterecken etwas zu weit gelaufen
			if rng.randf() < 0.45:
				var cy := yt if rng.randf() < 0.5 else yb
				var cz := bz + (ww * 0.5 if rng.randf() < 0.5 else -ww * 0.5)
				var horiz := rng.randf() < 0.5
				var ln := rng.randf_range(0.18, 0.45)
				var off := Vector3(0, 0, sign(cz - bz) * ln * 0.5) if horiz else Vector3(0, sign(cy - (yb + yt) * 0.5) * ln * 0.5, 0)
				var cp := _pivot + Basis(Vector3.BACK, _lean) * (Vector3(xf - side * 0.004, cy, cz) + off - _pivot)
				cuts.append([cp, Vector3(0.01, 0.035 if horiz else ln, ln if horiz else 0.035)])
	for zs in [z0, z0 - w]:
		_hp(Vector3(x + side * 4.6, H * 0.5, zs), Vector3(9.2, H, T * 0.5), bri * 0.85)
	_hp(Vector3(x + side * 9.0, H * 0.5, zc), Vector3(T, H, w), bri * 0.8)
	var g := _gable(kind, w)
	Geo.extrude(root3, g, T, face_m, edge_m, Vector3(x + side * H * sin(_lean) * 0.0, H, zc), Vector3(0, -side * PI * 0.5, 0))
	var gh: float = 0.0
	for v in g:
		gh = max(gh, v.y)
	_hp(Vector3(x - side * 0.8, H + gh - 0.9, zc), Vector3(1.6, 0.3, 0.3), bri)
	var ra := atan2(gh * 0.85, w * 0.5)
	for s2 in [-1.0, 1.0]:
		var len := sqrt(pow(w * 0.5, 2) + pow(gh * 0.85, 2))
		panels.append({"p": Vector3(x + side * 4.6, H + gh * 0.85 * 0.5, zc + s2 * w * 0.25), "s": Vector3(9.0, T, len),
			"rx": -s2 * ra, "t": 0.0, "i": 0.0, "b": bri * 0.9, "seed": rng.randf()})
	_panel(panels, Vector3(x + side * 1.2, H * 0.5, zc), Vector3(0.05, H, w - 0.2), 0.05)
	# Leim: an manchen Haeusern ist am Fuss Kleber herausgequollen (glaenzende Wuelste)
	if rng.randf() < 0.55:
		var n := rng.randi_range(1, 3)
		for k in n:
			glue.append([Vector3(xf - side * 0.12, 0.02, zc + rng.randf_range(-w * 0.45, w * 0.45)), rng.randf_range(0.25, 0.6)])

func _gable(kind: int, w: float) -> PackedVector2Array:
	var hw := w * 0.5
	var p := PackedVector2Array()
	match kind:
		0:
			var steps := 4
			var sh := 0.95
			p.append(Vector2(-hw, 0))
			for s in steps:
				var x0 := -hw + s * hw / (steps + 0.5)
				p.append(Vector2(x0, s * sh + sh))
				p.append(Vector2(x0 + hw / (steps + 0.5), s * sh + sh))
			for s in range(steps - 1, -1, -1):
				var x1 := hw - s * hw / (steps + 0.5)
				p.append(Vector2(x1 - hw / (steps + 0.5), s * sh + sh))
				p.append(Vector2(x1, s * sh + sh))
			p.append(Vector2(hw, 0))
		1:
			var nw := hw * 0.55
			p.append(Vector2(-hw, 0))
			for i in 9:
				var t := i / 8.0
				p.append(Vector2(-hw + (hw - nw) * t, 0.2 + sin(t * PI * 0.5) * 2.4 + (1.0 - cos(t * PI)) * 0.2))
			for i in 13:
				var a := PI - i / 12.0 * PI
				p.append(Vector2(cos(a) * nw, 2.8 + sin(a) * 1.2 + (1.0 if i == 6 else 0.0) * 0.25))
			for i in 9:
				var t := 1.0 - i / 8.0
				p.append(Vector2(hw - (hw - nw) * t, 0.2 + sin(t * PI * 0.5) * 2.4 + (1.0 - cos(t * PI)) * 0.2))
			p.append(Vector2(hw, 0))
		2:
			var nw2 := hw * 0.5
			p.append_array(PackedVector2Array([Vector2(-hw, 0), Vector2(-hw, 0.5), Vector2(-nw2 - 0.3, 1.3), Vector2(-nw2, 1.4), Vector2(-nw2, 3.4),
				Vector2(0, 4.6), Vector2(nw2, 3.4), Vector2(nw2, 1.4), Vector2(nw2 + 0.3, 1.3), Vector2(hw, 0.5), Vector2(hw, 0)]))
		_:
			p.append_array(PackedVector2Array([Vector2(-hw, 0), Vector2(-0.4, 3.8), Vector2(-0.4, 4.3), Vector2(0.4, 4.3), Vector2(0.4, 3.8), Vector2(hw, 0)]))
	return p

# ------------------------------------------------------------------ Bruecken
func _bridge(z: float) -> void:
	_panel(panels, Vector3(0, -0.2, z), Vector3(2 * CANAL + 1.0, T, 5.0), 0.5)
	var arch := PackedVector2Array()
	arch.append(Vector2(-CANAL - 0.5, 0.2))
	arch.append(Vector2(-CANAL - 0.5, -0.85))
	for i in 17:
		var a := PI - i / 16.0 * PI
		arch.append(Vector2(cos(a) * (CANAL - 0.6), -0.85 + sin(a) * 0.8 - 0.0))
	arch.append(Vector2(CANAL + 0.5, -0.85))
	arch.append(Vector2(CANAL + 0.5, 0.2))
	for s in [-1.0, 1.0]:
		Geo.extrude(root3, arch, T, face_m, edge_m, Vector3(0, 0, z + s * 2.55))
		_panel(panels, Vector3(0, 0.75, z + s * 2.35), Vector3(2 * CANAL + 1.0, 0.18, 0.18), 0.6)
		for k in 9:
			_panel(panels, Vector3(-CANAL + k * CANAL / 4.0, 0.4, z + s * 2.35), Vector3(0.16, 0.8, 0.16), 0.6)

# Amsterdamer Zugbruecke (Typologie: zwei Portale mit Waagebalken, Klappe, Ketten). Weiss gestrichene
# Pappe – kein bestimmtes Bauwerk nachgebaut.
func _drawbridge(z: float) -> void:
	var span := 2 * CANAL + 1.2
	# Fahrbahn (zwei Klappen, Mittelfuge), Laengstraeger darunter
	for s in [-1.0, 1.0]:
		_panel(panels, Vector3(s * span * 0.25, 0.05, z), Vector3(span * 0.5 - 0.06, 0.25, 4.6), 0.62)
	for zz in [-1.8, 0.0, 1.8]:
		white_panels.append({"p": Vector3(0, -0.25, z + zz), "s": Vector3(span, 0.35, 0.25), "t": 0.0, "b": 0.6, "seed": rng.randf()})
	# Portale (Galgen) auf beiden Ufern: zwei Pfosten + Querholm, Waagebalken schraeg darueber
	for sx in [-1.0, 1.0]:
		var px: float = sx * (CANAL + 0.9)
		for sz in [-1.0, 1.0]:
			white_panels.append({"p": Vector3(px, 3.6, z + sz * 2.2), "s": Vector3(0.38, 7.2, 0.38), "t": 0.0, "b": 0.6, "seed": rng.randf()})
			# Schraegstreben
			white_panels.append({"p": Vector3(px + sx * 0.8, 1.6, z + sz * 2.2), "s": Vector3(0.22, 3.4, 0.22), "rz": sx * 0.45, "t": 0.0, "b": 0.6, "seed": rng.randf()})
		white_panels.append({"p": Vector3(px, 7.3, z), "s": Vector3(0.45, 0.45, 5.0), "t": 0.0, "b": 0.6, "seed": rng.randf()})
		# Waagebalken: Rahmen aus zwei Laengsbalken und Sprossen, kippt zur Grachtenmitte
		# Waagebalken (Balans): Gitterrahmen, ruht auf dem Querholm, ragt zur Grachtenmitte und nach hinten
		var bl := 8.6
		var bc: float = px - sx * 1.6
		for sz in [-1.0, 1.0]:
			white_panels.append({"p": Vector3(bc, 7.75, z + sz * 1.7), "s": Vector3(bl, 0.34, 0.3), "rz": sx * 0.035, "t": 0.0, "b": 0.6, "seed": rng.randf()})
		for k in 6:
			var t: float = (k - 2.5) * bl / 5.5
			white_panels.append({"p": Vector3(bc + t, 7.75, z), "s": Vector3(0.22, 0.22, 3.4), "t": 0.0, "b": 0.6, "seed": rng.randf()})
		for k in 4:
			var t2: float = (k - 1.5) * bl / 4.0
			white_panels.append({"p": Vector3(bc + t2 + bl / 8.0, 7.75, z), "s": Vector3(bl / 4.0 * 1.1, 0.16, 0.16), "r": 0.75 if k % 2 == 0 else -0.75, "t": 0.0, "b": 0.6, "seed": rng.randf()})
		# Zugstangen (Ketten) von der Balkenspitze zur Klappe
		var steel := StandardMaterial3D.new()
		steel.albedo_color = Color(0.12, 0.12, 0.12)
		steel.metallic = 0.7
		steel.roughness = 0.4
		for sz in [-1.0, 1.0]:
			var top := Vector3(bc - sx * bl * 0.5 + sx * 0.3, 7.6, z + sz * 1.7)
			var bot := Vector3(top.x, 0.2, z + sz * 1.7)
			var c := Geo.cylinder(root3, (top + bot) * 0.5, 0.06, 0.06, top.distance_to(bot), steel, 8)
			c.look_at_from_position((top + bot) * 0.5, bot, Vector3.FORWARD)
			c.rotate_object_local(Vector3.RIGHT, PI * 0.5)
	# Gelaender weiss
	for sz in [-1.0, 1.0]:
		white_panels.append({"p": Vector3(0, 1.0, z + sz * 2.25), "s": Vector3(span - 1.0, 0.14, 0.14), "t": 0.0, "b": 0.6, "seed": rng.randf()})
		for k in 7:
			white_panels.append({"p": Vector3(-span * 0.5 + 1.0 + k * (span - 2.0) / 6.0, 0.55, z + sz * 2.25), "s": Vector3(0.12, 0.9, 0.12), "t": 0.0, "b": 0.6, "seed": rng.randf()})

func _tree_poly(r: float, h: float) -> PackedVector2Array:
	var p := PackedVector2Array()
	p.append(Vector2(-0.22, 0))
	p.append(Vector2(-0.22, h - r * 0.9))
	var n := 22
	for i in n + 1:
		var a := -PI * 0.5 - 0.25 - i / float(n) * (TAU - 0.5)
		var rr := r * (0.86 + 0.14 * sin(i * 2.7) + 0.06 * rng.randf())
		p.append(Vector2(cos(a) * rr, h + sin(a) * rr * 1.1))
	p.append(Vector2(0.22, h - r * 0.9))
	p.append(Vector2(0.22, 0))
	return p

func _trees() -> void:
	for side in [-1.0, 1.0]:
		var z := 14.0
		while z > (-33.0 if side > 0.0 else -38.0):   # rechts vor der Tram frei lassen (Ausgang sichtbar)
			if abs(z + 16.0) > 4.0 and abs(z + 31.0) > 4.5:
				var poly := _tree_poly(rng.randf_range(2.0, 2.6), rng.randf_range(6.5, 8.0))
				var x: float = side * (CANAL + KD + 0.6)
				var tilt := Vector3(rng.randf_range(-0.02, 0.02), 0.3 + rng.randf_range(-0.05, 0.05), rng.randf_range(-0.02, 0.02))
				Geo.extrude(root3, poly, 0.12, face_m, edge_m, Vector3(x, 0, z), tilt)
				Geo.extrude(root3, poly, 0.12, face_m, edge_m, Vector3(x, 0, z), tilt + Vector3(0, PI * 0.5, 0))
				if rng.randf() < 0.5:
					glue.append([Vector3(x + 0.25, 0.02, z + 0.2), 0.3])
			z -= rng.randf_range(7.5, 9.0)

func _tram() -> void:
	var c := Vector3(5.6, 0, -45.0)
	var L := 11.0
	var W := 2.5
	var Hh := 3.2
	for s in [-1.0, 1.0]:
		paint_panels.append({"p": c + Vector3(s * W * 0.5, 0.65, 0), "s": Vector3(T * 0.5, 1.1, L), "t": 0.0, "b": 0.6, "seed": rng.randf()})
		paint_panels.append({"p": c + Vector3(s * W * 0.5, Hh - 0.35, 0), "s": Vector3(T * 0.5, 0.7, L), "t": 0.0, "b": 0.6, "seed": rng.randf()})
		for k in 6:
			paint_panels.append({"p": c + Vector3(s * W * 0.5, 1.75, -L * 0.5 + 0.2 + k * (L - 0.4) / 5.0), "s": Vector3(T * 0.5, 1.2, 0.3), "t": 0.0, "b": 0.6, "seed": rng.randf()})
	for s in [-1.0, 1.0]:
		paint_panels.append({"p": c + Vector3(0, 0.75, s * L * 0.5), "s": Vector3(W, 1.3, T * 0.5), "t": 0.0, "b": 0.6, "seed": rng.randf()})
		paint_panels.append({"p": c + Vector3(0, Hh - 0.3, s * L * 0.5), "s": Vector3(W, 0.6, T * 0.5), "t": 0.0, "b": 0.6, "seed": rng.randf()})
		for sx2 in [-1.0, 0.0, 1.0]:
			paint_panels.append({"p": c + Vector3(sx2 * (W * 0.5 - 0.12), 1.85, s * L * 0.5), "s": Vector3(0.24 if sx2 != 0.0 else 0.12, 1.1, T * 0.5), "t": 0.0, "b": 0.6, "seed": rng.randf()})
		_panel(panels, c + Vector3(0, Hh - 0.3, s * (L * 0.5 + 0.12)), Vector3(1.4, 0.32, 0.06), 0.05)
		var lamp := StandardMaterial3D.new()
		lamp.albedo_color = Color(1.0, 0.95, 0.85)
		lamp.emission_enabled = true
		lamp.emission = Color(1.0, 0.9, 0.7)
		lamp.emission_energy_multiplier = 1.5
		for hx in [-0.8, 0.8]:
			Geo.extrude(root3, Geo.circle_poly(0.16, 24), 0.08, lamp, edge_m, c + Vector3(hx, 0.75, s * (L * 0.5 + 0.12)))
	paint_panels.append({"p": c + Vector3(0, Hh + 0.7, -0.6), "s": Vector3(0.12, 1.4, 0.12), "rx": 0.6, "t": 0.0, "b": 0.6, "seed": rng.randf()})
	paint_panels.append({"p": c + Vector3(0, Hh + 0.7, 0.6), "s": Vector3(0.12, 1.4, 0.12), "rx": -0.6, "t": 0.0, "b": 0.6, "seed": rng.randf()})
	_panel(panels, c + Vector3(0, Hh + 1.3, 0), Vector3(1.6, 0.08, 0.12), 0.1)
	paint_panels.append({"p": c + Vector3(0, Hh + 0.05, 0), "s": Vector3(W + 0.2, T * 0.5, L + 0.3), "t": 0.0, "b": 0.6, "seed": rng.randf()})
	var gl := P.mat(P.PAPER_SHADER, {"folds": 3.0, "fold_depth": 0.02, "crumple": 0.02, "seed": 2.0, "glow": Color(0.25, 1.0, 0.8) * 2.0, "tint": Color(0.8, 1.05, 0.95)})
	P.paper_sheet(root3, c + Vector3(0, 1.6, 0), Vector2(L - 0.6, 2.6), PI * 0.5, gl, 40)
	P.omni(root3, c + Vector3(0, 1.8, 0), Color(0.3, 1.0, 0.8), 2.5 if variant != "nacht" else 1.6, 8.0)
	for s in [-0.72, 0.72]:
		_panel(panels, Vector3(c.x + s, 0.05, -45.0), Vector3(0.18, 0.1, 18.0), 0.2)

# ------------------------------------------------------------------ Arbeitsplatz
func _desk() -> void:
	# Tisch (Holzscan, 2,2 x 1,6 m = 220 x 160 m), darauf die Schneidematte A0, darauf das Modell
	var t := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(260, 4.0, 190)
	t.mesh = bm
	t.position = Vector3(10, -3.3, -20)
	var wood := StandardMaterial3D.new()
	wood.albedo_texture = scan["holz_albedo"]
	wood.normal_enabled = true
	wood.normal_texture = scan["holz_normal"]
	wood.normal_scale = 0.6
	wood.roughness_texture = scan["holz_rough"]
	wood.roughness = 1.0
	wood.uv1_triplanar = true
	wood.uv1_scale = Vector3(1.0 / 110.0, 1.0 / 110.0, 1.0 / 55.0)
	t.material_override = wood
	root3.add_child(t)
	var mat := MeshInstance3D.new()
	var mb := BoxMesh.new()
	mb.size = Vector3(90, 0.3, 120)
	mat.mesh = mb
	mat.position = Vector3(2, -1.15, -15)
	var mm := StandardMaterial3D.new()
	mm.albedo_texture = scan["matte"]
	mm.roughness = 0.78
	mm.uv1_scale = Vector3(1, 1, 1)
	mat.material_override = mm
	root3.add_child(mat)
	# Stahllineal 60 cm neben dem Modell
	var rl := MeshInstance3D.new()
	var rb := BoxMesh.new()
	rb.size = Vector3(3.0, 0.12, 62.0)
	rl.mesh = rb
	rl.position = Vector3(31.5, -0.94, -12.0)
	rl.rotation.y = 0.03
	var rm := StandardMaterial3D.new()
	rm.albedo_texture = scan["lineal"]
	rm.metallic = 0.85
	rm.roughness = 0.32
	rm.uv1_scale = Vector3(1, 1, 1)
	rl.material_override = rm
	root3.add_child(rl)
	# Bleistift
	var pen := Node3D.new()
	root3.add_child(pen)
	pen.position = Vector3(0.5, 0.4, -47.8)
	pen.rotation = Vector3(0, 0.12, 0)
	var lack := StandardMaterial3D.new()
	lack.albedo_color = Color("#D9A21E")
	lack.roughness = 0.28
	lack.clearcoat_enabled = true
	var body := Geo.cylinder(pen, Vector3.ZERO, 0.4, 0.4, 14.0, lack, 6)
	body.rotation.z = PI * 0.5
	var woodm := StandardMaterial3D.new()
	woodm.albedo_color = Color("#D8B48A")
	woodm.roughness = 0.8
	var tip := Geo.cylinder(pen, Vector3(-8.2, 0, 0), 0.4, 0.06, 2.4, woodm, 24)
	tip.rotation.z = -PI * 0.5
	var lead := StandardMaterial3D.new()
	lead.albedo_color = Color(0.12, 0.12, 0.13)
	lead.metallic = 0.6
	lead.roughness = 0.35
	Geo.sphere(pen, Vector3(-9.45, 0, 0), 0.07, lead)
	var ferr := StandardMaterial3D.new()
	ferr.albedo_color = Color(0.75, 0.75, 0.72)
	ferr.metallic = 1.0
	ferr.roughness = 0.3
	var fe := Geo.cylinder(pen, Vector3(7.4, 0, 0), 0.42, 0.42, 0.9, ferr, 24)
	fe.rotation.z = PI * 0.5
	var eras := StandardMaterial3D.new()
	eras.albedo_color = Color("#C9877C")
	eras.roughness = 0.9
	var er := Geo.cylinder(pen, Vector3(8.2, 0, 0), 0.4, 0.4, 0.8, eras, 24)
	er.rotation.z = PI * 0.5
	# Kaffeebecher auf der Matte hinter der Modellkante
	var cer := StandardMaterial3D.new()
	cer.albedo_color = Color("#E8E2D6")
	cer.roughness = 0.12
	cer.clearcoat_enabled = true
	Geo.cylinder(root3, Vector3(-3.0, 4.5, -66.0), 4.0, 3.8, 11.0, cer, 48)
	var coffee := StandardMaterial3D.new()
	coffee.albedo_color = Color(0.12, 0.06, 0.03)
	coffee.roughness = 0.05
	Geo.cylinder(root3, Vector3(-3.0, 9.0, -66.0), 3.7, 3.7, 1.2, coffee, 48)
	var handle := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 2.2
	tm.outer_radius = 3.0
	handle.mesh = tm
	handle.material_override = cer
	handle.position = Vector3(1.2, 5.0, -66.0)
	handle.rotation = Vector3(PI * 0.5, 0, 0)
	root3.add_child(handle)
	# Klebestreifen, die die Grundplatte auf der Matte halten (Ecken)
	for c in [Vector3(-CANAL - 19.5, -0.98, 21.5), Vector3(CANAL + 19.5, -0.98, 21.5), Vector3(CANAL + 19.5, -0.98, -49.5)]:
		_tape(c, Vector2(5.0, 1.9), PI * 0.25 * sign(c.x) * sign(c.z))

func _pins() -> void:
	var heads: Array = []
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.8, 0.8, 0.82)
	steel.metallic = 1.0
	steel.roughness = 0.18
	var z := 15.0
	while z > -41.0:
		var head := Vector3(6.6 + rng.randf_range(-0.1, 0.1), 0.85, z)
		heads.append(head)
		var tilt := Vector3(rng.randf_range(-0.12, 0.12), 0, rng.randf_range(-0.12, 0.12))
		var pin := Geo.cylinder(root3, head + Vector3(0, -0.5, 0), 0.03, 0.03, 1.0, steel, 10)
		pin.rotation = tilt
		pin.position = head - Basis.from_euler(tilt) * Vector3(0, 0.5, 0)
		z -= 2.2
	for k in 4:
		var h2 := Vector3(3.6 - k * 2.2, 0.85, -16.0)
		heads.append(h2)
		Geo.cylinder(root3, h2 + Vector3(0, -0.5, 0), 0.03, 0.03, 1.0, steel, 10)
	P.marbles(root3, heads, 0.2, P.mat(P.MARBLE_SHADER, {"energy": 1.6 if variant != "nacht" else 2.4}))

# ------------------------------------------------------------------ Modellbau-Spuren
func _marks() -> void:
	# Bleistift-Anriss auf beiden Strassen (Grafit: dunkel, leicht glaenzend), als Decal-Flaeche
	for side in [-1.0, 1.0]:
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.16, 0.16, 0.17)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_texture = scan["anriss_a" if side > 0.0 else "anriss_b"]
		m.roughness = 0.45
		m.metallic = 0.25
		# Graustufenbild -> Deckkraft ueber den Kanal: Textur in Alpha umdeuten
		var sh := Shader.new()
		sh.code = """
shader_type spatial;
render_mode blend_mix, depth_draw_never, diffuse_burley;
uniform sampler2D a : filter_linear_mipmap_anisotropic, repeat_disable;
uniform float flip = 1.0;
void fragment(){
	float g = texture(a, vec2(flip > 0.0 ? UV.x : 1.0 - UV.x, UV.y)).r;
	ALBEDO = vec3(0.12, 0.12, 0.13);
	ROUGHNESS = 0.42;
	METALLIC = 0.2;
	ALPHA = clamp(g * 0.85, 0.0, 0.85);
}
"""
		var sm := ShaderMaterial.new()
		sm.shader = sh
		sm.set_shader_parameter("a", scan["anriss_a" if side > 0.0 else "anriss_b"])
		sm.set_shader_parameter("flip", side)
		var q := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(QUAY - CANAL - T * 0.5 + 0.1, 72.0)
		q.mesh = pm
		q.material_override = sm
		q.position = Vector3(side * (CANAL + (QUAY - CANAL - T * 0.5) * 0.5), 0.006, -14.0)
		q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root3.add_child(q)

func _cuts_and_glue() -> void:
	# Ueberschnitte: dunkle, haarfeine Kerben
	var cm := StandardMaterial3D.new()
	cm.albedo_color = Color(0.06, 0.04, 0.03)
	cm.roughness = 1.0
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = BoxMesh.new()
	mm.instance_count = cuts.size()
	for i in cuts.size():
		mm.set_instance_transform(i, Transform3D(Basis.from_scale(cuts[i][1]), cuts[i][0]))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = cm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root3.add_child(mi)
	# Leim: flache, glasklare Wuelste mit Glanzlicht (Weissleim trocknet klar, leicht gelblich)
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.95, 0.9, 0.75, 0.32)
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gm.roughness = 0.04
	gm.metallic_specular = 0.9
	gm.clearcoat_enabled = true
	gm.clearcoat = 1.0
	gm.clearcoat_roughness = 0.02
	var sm := SphereMesh.new()
	sm.radial_segments = 20
	sm.rings = 10
	var g := MultiMesh.new()
	g.transform_format = MultiMesh.TRANSFORM_3D
	g.mesh = sm
	g.instance_count = glue.size()
	for i in glue.size():
		var r: float = glue[i][1]
		g.set_instance_transform(i, Transform3D(Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3(r * 2.6, r * 0.32, r * 1.4)), glue[i][0]))
	var gi := MultiMeshInstance3D.new()
	gi.multimesh = g
	gi.material_override = gm
	gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root3.add_child(gi)

# ------------------------------------------------------------------ Optik (Vollbild, Compatibility-tauglich)
const POST := """
shader_type spatial;
render_mode unshaded, depth_draw_never, depth_test_disabled, cull_disabled, fog_disabled, shadows_disabled;
uniform sampler2D st : hint_screen_texture, filter_linear, repeat_disable;
uniform sampler2D dt : hint_depth_texture, filter_nearest, repeat_disable;
uniform int mode = 0;              // 0 aus, 1 nur Hintergrund (ab far_start), 2 Makro/Tilt-Shift um focus
uniform float focus = 30.0;
uniform float aperture = 10.0;     // max. Unschaerfe in Pixeln (bei 720p)
uniform float far_start = 80.0;
uniform float vig = 0.28;
uniform float grain = 0.025;
uniform vec3 lift = vec3(0.0);
uniform vec3 gain = vec3(1.0);
uniform float ca = 0.6;            // Farbsaum am Bildrand (Pixel)
void vertex(){ POSITION = vec4(VERTEX.xy, 1.0, 1.0); }
// Tiefe wird im fragment() gelesen (Compatibility deklariert den Tiefenpuffer nur dort)
float zlin(float d, vec2 uv, mat4 ip){
	vec4 v = ip * vec4(uv * 2.0 - 1.0, d * 2.0 - 1.0, 1.0);
	return -v.z / v.w;
}
float coc(float z){
	if (mode == 1) return clamp((z - far_start) / far_start, 0.0, 1.0);
	return clamp(abs(z - focus) / z * 2.2, 0.0, 1.0);
}
float h(vec2 p){ return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
void fragment(){
	vec2 px = 1.0 / VIEWPORT_SIZE;
	float sc = VIEWPORT_SIZE.y / 720.0;
	vec3 col;
	float c0 = mode > 0 ? coc(zlin(texture(dt, SCREEN_UV).r, SCREEN_UV, INV_PROJECTION_MATRIX)) : 0.0;
	if (c0 * aperture * sc > 0.6) {
		vec3 acc = vec3(0.0); float wsum = 0.0;
		float R = c0 * aperture * sc;
		for (int i = 0; i < 40; i++) {
			float t = float(i) + 0.5;
			float r = sqrt(t / 40.0);
			float a = t * 2.39996;
			vec2 o = vec2(cos(a), sin(a)) * r * R;
			vec2 uv = SCREEN_UV + o * px;
			float cs = coc(zlin(texture(dt, uv).r, uv, INV_PROJECTION_MATRIX));
			// scharfe Vordergrund-Pixel nicht in unscharfe Flaechen ziehen
			float w = clamp(cs * aperture * sc - r * R + 1.0, 0.0, 1.0) + 0.02;
			acc += texture(st, uv).rgb * w; wsum += w;
		}
		col = acc / wsum;
	} else {
		col = texture(st, SCREEN_UV).rgb;
	}
	// Farbsaum (Objektiv) nur am Rand
	vec2 d = SCREEN_UV - 0.5;
	float rr = dot(d, d);
	if (ca > 0.0) {
		vec2 o = d * rr * ca * 4.0 * px * sc;
		col.r = mix(col.r, texture(st, SCREEN_UV + o).r, 0.6);
		col.b = mix(col.b, texture(st, SCREEN_UV - o).b, 0.6);
	}
	col = col * gain + lift * (1.0 - col);
	d.x *= VIEWPORT_SIZE.x / VIEWPORT_SIZE.y * 0.75;
	col *= 1.0 - vig * smoothstep(0.15, 0.75, length(d) * 1.2);
	col += (h(FRAGCOORD.xy) - 0.5) * grain * (1.0 - col * 0.5);
	ALBEDO = col;
}
"""

func _post() -> void:
	var q := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(2, 2)
	q.mesh = qm
	q.extra_cull_margin = 16384.0
	q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	post_m = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = POST
	post_m.shader = sh
	var grade := {
		"atelier": [Vector3(0.01, 0.012, 0.018), Vector3(0.97, 0.99, 1.02)],
		"abend": [Vector3(0.03, 0.012, 0.0), Vector3(1.04, 0.97, 0.86)],
		"studio": [Vector3(0.0, 0.0, 0.006), Vector3(1.0, 1.0, 1.0)],
		"nacht": [Vector3(0.0, 0.008, 0.02), Vector3(1.02, 0.96, 0.9)],
	}
	post_m.set_shader_parameter("lift", grade[variant][0])
	post_m.set_shader_parameter("gain", grade[variant][1])
	post_m.set_shader_parameter("vig", 0.34 if variant in ["studio", "nacht"] else 0.24)
	post_m.set_shader_parameter("grain", 0.0 if reduce_fx else 0.022)
	post_m.set_shader_parameter("ca", 0.0)   # Farbsaum getestet: wirkt im Modellmassstab wie ein Fehler
	q.material_override = post_m
	if OS.get_environment("NOPOST") == "":
		add_child(q)

# ------------------------------------------------------------------ Ansichten
# [name, pos, look_at, fov, dof] mit dof = [mode, focus, aperture]
func views() -> Array:
	return [
		["strasse", Vector3(7.3, 1.9, -6.0), Vector3(5.2, 2.2, -46.0), 66.0, [1, 0.0, 7.0]],
		["totale", Vector3(34.0, 30.0, 34.0), Vector3(-1.0, 0.0, -14.0), 46.0, [2, 60.0, 8.0]],
		["gracht", Vector3(0.0, 2.6, -14.5), Vector3(0.0, 3.4, -60.0), 66.0, [1, 0.0, 7.0]],
		["kante", Vector3(1.2, -0.35, -3.5), Vector3(4.0, -0.45, -7.5), 60.0, [2, 4.6, 7.0]],
		["capsule", Vector3(7.6, 1.6, 6.0), Vector3(2.0, 4.5, -30.0), 64.0, [1, 0.0, 6.0]],
	]

func set_view(pos: Vector3, look: Vector3, fov: float) -> void:
	cam.position = pos
	cam.look_at(look)
	cam.fov = fov
	for v in views():
		if v[1] == pos:
			var dof: Array = v[4]
			post_m.set_shader_parameter("mode", 0 if reduce_fx else dof[0])
			post_m.set_shader_parameter("focus", dof[1])
			post_m.set_shader_parameter("aperture", dof[2])
			post_m.set_shader_parameter("far_start", 75.0)
