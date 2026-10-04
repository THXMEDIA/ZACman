# Richtung J "Pappmodell Amsterdam" – Stil-Prototyp (Art Director, Nachtrag 04.10.2026, NICHT Spielcode).
# Ein Architekturmodell im Massstab 1:100 aus Wellpappe, erlebt auf Ameisenhoehe: Die Haeuser haben
# echte Groesse, aber das Material ist 100-fach vergroessert – die Pappe ist 40 cm dick, jede
# Schnittkante zeigt die Welle als meterhohen Querschnitt, die Flaechen die Waschbrett-Abzeichnung.
# Grachtengiebel (Treppen-, Glocken-, Halsgiebel), Bruecke, Modellbaeume aus zwei gekreuzten
# Ausschnitten. Jenseits der Modellkante: der Arbeitstisch mit Riesen-Bleistift und Kaffeebecher.
# Licht: Tageslicht aus einem grossen Atelierfenster (Sonne + Himmel), heller Dunst wie im Makrofoto.
# Kugeln = blaue Glaskopf-Stecknadeln, mit denen der Modellbauer den Weg markiert hat.
# Ausgang = gruen gestrichene Papp-Strassenbahn.
extends Node3D

const P := preload("res://pappe.gd")
const Geo := preload("res://geo.gd")

var cam: Camera3D
var rng := RandomNumberGenerator.new()
var reduce_fx := false
var panels: Array = []
var paint_panels: Array = []
var root3: Node3D
var face_m: ShaderMaterial
var edge_m: ShaderMaterial

const T := 0.4          # Pappstaerke auf Ameisenhoehe (4 mm x 100)
const PITCH := 0.7      # Wellenteilung (7 mm x 100)
const CANAL := 4.0      # Grachten-Halbbreite
const QUAY := 9.5       # Fassadenflucht

func _init() -> void:
	rng.seed = 1675
	reduce_fx = OS.get_environment("REDUCE_FX") == "1"
	root3 = Node3D.new()
	add_child(root3)
	face_m = P.flat_mat({"tile_m": 2.6, "far_flat": 60.0})
	edge_m = P.mat(P.EDGE_SHADER, {"thick": T, "pitch": PITCH, "tile_m": 2.6})
	_env()
	_base()
	_row(1.0)
	_row(-1.0)
	_bridge(-16.0)
	_trees()
	_tram()
	_desk()
	_pins()
	var pm := P.mat(P.BOX_SHADER, {"panel": 1.0, "edge_pitch": PITCH, "rib_pitch": PITCH, "rib_amp": 0.25, "tile_m": 2.6, "bulge": 0.0, "edge_ao": 0.8, "far_flat": 60.0})
	P.boxes(root3, panels, pm)
	P.boxes(root3, paint_panels, P.mat(P.BOX_SHADER, {"panel": 1.0, "edge_pitch": PITCH, "rib_pitch": PITCH, "tile_m": 2.6, "bulge": 0.0,
		"paint": 1.0, "paint_col": Color("#1FA855"), "paint_emit": 0.12}))
	P.lens(self, 0.3)
	cam = Camera3D.new()
	cam.near = 0.05
	cam.far = 600.0
	add_child(cam)

func _env() -> void:
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color("#BFC3C4")
	sm.sky_horizon_color = Color("#E9E3D8")
	sm.ground_bottom_color = Color("#5E4D3C")
	sm.ground_horizon_color = Color("#B9A890")
	sm.sun_angle_max = 8.0
	sky.sky_material = sm
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.75
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.tonemap_white = 4.0
	env.fog_enabled = true
	env.fog_light_color = Color("#DCD3C6")
	env.fog_density = 0.0055
	env.fog_sky_affect = 0.0
	env.glow_enabled = true
	env.glow_intensity = 0.4
	env.glow_hdr_threshold = 1.3
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.05
	env.adjustment_saturation = 0.95
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_color = P.kelvin(5200)
	sun.light_energy = 2.1
	sun.shadow_enabled = true
	sun.shadow_blur = 2.0
	sun.directional_shadow_max_distance = 140.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.shadow_bias = 0.05
	sun.shadow_normal_bias = 1.5
	add_child(sun)
	sun.transform = Transform3D(Basis.looking_at(Vector3(-0.55, -0.62, -0.42).normalized(), Vector3.UP), Vector3.ZERO)

func _panel(list: Array, center: Vector3, size: Vector3, b := -1.0) -> void:
	list.append({"p": center, "s": size, "t": 0.0, "i": 0.0, "b": rng.randf() if b < 0.0 else b, "seed": rng.randf()})

func _base() -> void:
	# Grundplatte: Kaiflaechen sind Plattenstuecke; die Kaimauer ist die Schnittkante der Platte
	for sx in [-1.0, 1.0]:
		_panel(panels, Vector3(sx * (CANAL + 10.0), -0.5, -14.0), Vector3(20.0, 1.0, 72.0), 0.55)
	# Grachtenboden unter Wasser
	_panel(panels, Vector3(0, -1.3, -14.0), Vector3(2 * CANAL + 0.2, 0.4, 72.0), 0.3)
	# Wasser: lackierte, dunkle Pappe (glaenzend), Pinselstriche im Lack
	var w := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(2 * CANAL, 72.0)
	w.mesh = pm
	w.position = Vector3(0, -0.85, -14.0)
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.085, 0.062, 0.042)
	wm.roughness = 0.06
	wm.metallic_specular = 0.7
	wm.normal_enabled = true
	wm.normal_texture = P.tex["tape_normal"]
	wm.normal_scale = 0.35
	wm.uv1_scale = Vector3(1.2, 6.0, 1.0)
	wm.clearcoat_enabled = true
	wm.clearcoat = 1.0
	wm.clearcoat_roughness = 0.03
	w.material_override = wm
	root3.add_child(w)
	# Querstrasse am Ende (Platz mit Bleistift) und Modellkante bei z = -50
	_panel(panels, Vector3(0, -0.5, -46.5), Vector3(2 * CANAL + 0.4, 1.0, 7.0), 0.6)

# Eine Haeuserzeile; side +1 = rechte Gracht-Seite (Fassade bei x = +QUAY, schaut nach -x)
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

func _house(side: float, z0: float, w: float, floors: int, kind: int) -> void:
	var x := side * QUAY
	var fh := 3.3
	var zc := z0 - w * 0.5
	var nwin := 3 if w > 5.6 else 2
	var ww := 1.15
	var pier := (w - nwin * ww) / (nwin + 1)
	var bri := rng.randf_range(0.25, 0.85)
	var H := floors * fh
	for f in floors:
		var y0 := f * fh
		var yb := y0 + (0.9 if f > 0 else 0.0)
		var yt := yb + (2.0 if f > 0 else 2.7)
		# Bruestungsband unten (im Erdgeschoss nur unter Fenstern, nicht unter der Tuer)
		if f > 0:
			_panel(panels, Vector3(x, (y0 + yb) * 0.5, zc), Vector3(T, yb - y0, w), bri)
		else:
			# EG: Tuer im mittleren Feld, Fenster daneben ab 0,9 m
			for k in nwin:
				var bz := z0 - pier - k * (ww + pier) - ww * 0.5
				if k != nwin / 2:
					_panel(panels, Vector3(x, 0.45, bz), Vector3(T, 0.9, ww), bri)
		# Pfeiler
		for k in nwin + 1:
			var pz := z0 - k * (ww + pier) - pier * 0.5
			_panel(panels, Vector3(x, (yb + yt) * 0.5, pz), Vector3(T, yt - yb, pier), bri)
		# Sturzband oben
		_panel(panels, Vector3(x, (yt + y0 + fh) * 0.5, zc), Vector3(T, y0 + fh - yt, w), bri)
		# Fensterkreuze aus duennen Streifen (Sprossen)
		for k in nwin:
			var bz := z0 - pier - k * (ww + pier) - ww * 0.5
			if f == 0 and k == nwin / 2:
				continue
			_panel(panels, Vector3(x + side * 0.08, (yb + yt) * 0.5 + (0.25 if f > 0 else 0.0), bz), Vector3(0.14, 0.14, ww), bri)
			_panel(panels, Vector3(x + side * 0.08, (yb + yt) * 0.5, bz), Vector3(0.14, yt - yb, 0.14), bri)
	# Seitenwaende (Brandmauern) und Rueckwand
	for zs in [z0, z0 - w]:
		_panel(panels, Vector3(x + side * 4.6, H * 0.5, zs), Vector3(9.2, H, T * 0.5), bri * 0.85)
	# Rueckwand und Dach (geschlossener Modellkoerper, innen dunkel)
	_panel(panels, Vector3(x + side * 9.0, H * 0.5, zc), Vector3(T, H, w), bri * 0.8)
	# Giebel
	var g := _gable(kind, w)
	var gm := Geo.extrude(root3, g, T, face_m, edge_m, Vector3(x, H, zc), Vector3(0, -side * PI * 0.5, 0))
	var gh: float = 0.0
	for v in g:
		gh = max(gh, v.y)
	# Hijsbalk (Lastbalken) am Giebel
	_panel(panels, Vector3(x - side * 0.8, H + gh - 0.9, zc), Vector3(1.6, 0.3, 0.3), bri)
	# Dachflaechen hinter dem Giebel (Satteldach entlang der Haustiefe)
	var ra := atan2(gh * 0.85, w * 0.5)
	for s2 in [-1.0, 1.0]:
		var len := sqrt(pow(w * 0.5, 2) + pow(gh * 0.85, 2))
		panels.append({"p": Vector3(x + side * 4.6, H + gh * 0.85 * 0.5, zc + s2 * w * 0.25), "s": Vector3(9.0, T, len),
			"rx": -s2 * ra, "t": 0.0, "i": 0.0, "b": bri * 0.9, "seed": rng.randf()})
	# Innen: dunkle Rueckseite hinter den Fenstern (Modell ist hohl, nur Streulicht)
	_panel(panels, Vector3(x + side * 1.2, H * 0.5, zc), Vector3(0.05, H, w - 0.2), 0.05)

func _gable(kind: int, w: float) -> PackedVector2Array:
	var hw := w * 0.5
	var p := PackedVector2Array()
	match kind:
		0: # Treppengiebel
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
		1: # Glockengiebel: Schultern, geschwungener Hals, Bogen oben
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
		2: # Halsgiebel: senkrechter Hals mit Schultern und Dreieck oben
			var nw2 := hw * 0.5
			p.append_array(PackedVector2Array([Vector2(-hw, 0), Vector2(-hw, 0.5), Vector2(-nw2 - 0.3, 1.3), Vector2(-nw2, 1.4), Vector2(-nw2, 3.4),
				Vector2(0, 4.6), Vector2(nw2, 3.4), Vector2(nw2, 1.4), Vector2(nw2 + 0.3, 1.3), Vector2(hw, 0.5), Vector2(hw, 0)]))
		_: # Tuitgevel: schlichter Spitzgiebel mit kleiner Abdeckung
			p.append_array(PackedVector2Array([Vector2(-hw, 0), Vector2(-0.4, 3.8), Vector2(-0.4, 4.3), Vector2(0.4, 4.3), Vector2(0.4, 3.8), Vector2(hw, 0)]))
	return p

func _bridge(z: float) -> void:
	# Bogenbruecke: Fahrbahnplatte, zwei Bogenwangen als Ausschnitt, Gelaender aus Streifen
	_panel(panels, Vector3(0, -0.2, z), Vector3(2 * CANAL + 1.0, T, 5.0), 0.5)
	var arch := PackedVector2Array()
	arch.append(Vector2(-CANAL - 0.5, 0.2))
	arch.append(Vector2(-CANAL - 0.5, -2.0))
	for i in 17:
		var a := PI - i / 16.0 * PI
		arch.append(Vector2(cos(a) * (CANAL - 0.6), -2.0 + sin(a) * 1.6))
	arch.append(Vector2(CANAL + 0.5, -2.0))
	arch.append(Vector2(CANAL + 0.5, 0.2))
	for s in [-1.0, 1.0]:
		Geo.extrude(root3, arch, T, face_m, edge_m, Vector3(0, 0, z + s * 2.55))
		_panel(panels, Vector3(0, 0.75, z + s * 2.35), Vector3(2 * CANAL + 1.0, 0.18, 0.18), 0.6)
		for k in 9:
			_panel(panels, Vector3(-CANAL + k * CANAL / 4.0, 0.4, z + s * 2.35), Vector3(0.16, 0.8, 0.16), 0.6)

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
	# Modellbaeume: zwei gekreuzte Pappausschnitte (klassische Modellbautechnik)
	for side in [-1.0, 1.0]:
		var z := 14.0
		while z > -38.0:
			if abs(z + 16.0) > 4.0:
				var poly := _tree_poly(rng.randf_range(2.0, 2.6), rng.randf_range(6.5, 8.0))
				var x: float = side * (CANAL + 1.0)
				Geo.extrude(root3, poly, 0.12, face_m, edge_m, Vector3(x, 0, z), Vector3(0, 0.3, 0))
				Geo.extrude(root3, poly, 0.12, face_m, edge_m, Vector3(x, 0, z), Vector3(0, 0.3 + PI * 0.5, 0))
			z -= rng.randf_range(7.5, 9.0)

func _tram() -> void:
	# Ausgang: gruen gestrichene Papp-Strassenbahn an der Querstrasse, Licht innen
	var c := Vector3(5.6, 0, -45.0)
	var L := 11.0
	var W := 2.5
	var Hh := 3.2
	# Seitenwaende mit Fensterband
	for s in [-1.0, 1.0]:
		paint_panels.append({"p": c + Vector3(s * W * 0.5, 0.65, 0), "s": Vector3(T * 0.5, 1.1, L), "t": 0.0, "b": 0.6, "seed": rng.randf()})
		paint_panels.append({"p": c + Vector3(s * W * 0.5, Hh - 0.35, 0), "s": Vector3(T * 0.5, 0.7, L), "t": 0.0, "b": 0.6, "seed": rng.randf()})
		for k in 6:
			paint_panels.append({"p": c + Vector3(s * W * 0.5, 1.75, -L * 0.5 + 0.2 + k * (L - 0.4) / 5.0), "s": Vector3(T * 0.5, 1.2, 0.3), "t": 0.0, "b": 0.6, "seed": rng.randf()})
	# Stirnseiten: unten geschlossen, oben Frontscheibe (Ausschnitt), Zielschild, Scheinwerfer
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
	# Stromabnehmer: zwei schraege Pappstreifen
	paint_panels.append({"p": c + Vector3(0, Hh + 0.7, -0.6), "s": Vector3(0.12, 1.4, 0.12), "rx": 0.6, "t": 0.0, "b": 0.6, "seed": rng.randf()})
	paint_panels.append({"p": c + Vector3(0, Hh + 0.7, 0.6), "s": Vector3(0.12, 1.4, 0.12), "rx": -0.6, "t": 0.0, "b": 0.6, "seed": rng.randf()})
	_panel(panels, c + Vector3(0, Hh + 1.3, 0), Vector3(1.6, 0.08, 0.12), 0.1)
	paint_panels.append({"p": c + Vector3(0, Hh + 0.05, 0), "s": Vector3(W + 0.2, T * 0.5, L + 0.3), "t": 0.0, "b": 0.6, "seed": rng.randf()})
	# Innenlicht und gruener Schein auf den Boden
	var gl := P.mat(P.PAPER_SHADER, {"folds": 3.0, "fold_depth": 0.02, "crumple": 0.02, "seed": 2.0, "glow": Color(0.3, 1.0, 0.5) * 2.0, "tint": Color(0.8, 1.05, 0.85)})
	P.paper_sheet(root3, c + Vector3(0, 1.6, 0), Vector2(L - 0.6, 2.6), PI * 0.5, gl, 40)
	P.omni(root3, c + Vector3(0, 1.8, 0), Color(0.35, 1.0, 0.55), 2.5, 8.0)
	# Schienen: zwei aufgeklebte Pappstreifen
	for s in [-0.72, 0.72]:
		_panel(panels, Vector3(c.x + s, 0.05, -45.0), Vector3(0.18, 0.1, 18.0), 0.2)

func _desk() -> void:
	# Arbeitstisch (Holz) unter der Grundplatte, Riesen-Bleistift auf dem Platz, Kaffeebecher dahinter
	var t := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(400, 2.0, 400)
	t.mesh = bm
	t.position = Vector3(0, -2.0, -40)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color("#6E5139")
	wood.roughness = 0.45
	wood.normal_enabled = true
	wood.normal_texture = P.tex["tape_normal"]
	wood.normal_scale = 0.4
	wood.uv1_scale = Vector3(0.02, 0.02, 0.02)
	wood.uv1_triplanar = true
	t.material_override = wood
	root3.add_child(t)
	# Bleistift: Sechskant, gelb lackiert, Holzspitze, Mine – liegt quer ueber dem Platz
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
	var lt := Geo.sphere(pen, Vector3(-9.45, 0, 0), 0.07, lead)
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
	# Kaffeebecher auf dem Tisch hinter der Modellkante (8 m Durchmesser = 8 cm)
	var cer := StandardMaterial3D.new()
	cer.albedo_color = Color("#E8E2D6")
	cer.roughness = 0.12
	cer.clearcoat_enabled = true
	Geo.cylinder(root3, Vector3(-3.0, 3.5, -68.0), 4.0, 3.8, 11.0, cer, 48)
	var coffee := StandardMaterial3D.new()
	coffee.albedo_color = Color(0.12, 0.06, 0.03)
	coffee.roughness = 0.05
	Geo.cylinder(root3, Vector3(-3.0, 8.0, -68.0), 3.7, 3.7, 1.2, coffee, 48)
	var handle := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 2.2
	tm.outer_radius = 3.0
	handle.mesh = tm
	handle.material_override = cer
	handle.position = Vector3(1.2, 4.0, -68.0)
	handle.rotation = Vector3(PI * 0.5, 0, 0)
	root3.add_child(handle)

func _pins() -> void:
	# Stecknadeln mit blauem Glaskopf: Kopf 0,4 m (4 mm), Nadel schraeg in der Platte
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
	P.marbles(root3, heads, 0.2, P.mat(P.MARBLE_SHADER, {"energy": 1.6}))

func views() -> Array:
	return [
		["strasse", Vector3(6.4, 1.9, 19.0), Vector3(4.0, 2.6, -20.0), 68.0],
		["totale", Vector3(30.0, 30.0, 30.0), Vector3(-1.0, 1.0, -16.0), 50.0],
		["gracht", Vector3(0.0, 2.1, -13.2), Vector3(0.0, 3.0, -60.0), 70.0],
		["ausgang", Vector3(7.8, 1.9, -33.5), Vector3(3.2, 1.8, -48.0), 70.0],
		["capsule", Vector3(7.6, 1.6, 6.0), Vector3(2.0, 4.5, -30.0), 64.0],
	]

func set_view(pos: Vector3, look: Vector3, fov: float) -> void:
	cam.position = pos
	cam.look_at(look)
	cam.fov = fov
