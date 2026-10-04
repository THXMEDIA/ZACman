# Richtung I "Kartonbuehne" – Stil-Prototyp (Art Director, Nachtrag 04.10.2026, NICHT Spielcode).
# Eine Kleinstadt-Gasse als Buehnenbild aus echten Umzugskartons auf schwarzer Buehne: Haeuser
# sind gestapelte Kartons (Fugen, Klebeband, Druck), Fenster sind ausgesparte Oeffnungen mit
# zerknittertem Packpapier, hinter dem Licht brennt; Laternen aus Papprollen mit Packpapierschirm;
# am Platz ein Uhrturm aus Kartons. Licht wie im Theater: harte warme Scheinwerfer von oben,
# Dunstkegel, ein kuehles Gegenlicht, alles andere schwarz. Kugeln = blaue Glasmurmeln am Boden,
# Ausgang = gruen gestrichene Kartontuer mit gruenem Licht.
extends Node3D

const P := preload("res://pappe.gd")
const Geo := preload("res://geo.gd")

var cam: Camera3D
var rng := RandomNumberGenerator.new()
var reduce_fx := false
var boxes: Array = []
var paint_boxes: Array = []
var root3: Node3D

const STREET_W := 4.6
const Z0 := 14.0
const Z1 := -30.0

func _init() -> void:
	rng.seed = 4711
	reduce_fx = OS.get_environment("REDUCE_FX") == "1"
	root3 = Node3D.new()
	add_child(root3)
	_env()
	_floor()
	_street()
	_square()
	_lamps()
	_rig()
	_pellets()
	P.boxes(root3, boxes, P.mat(P.BOX_SHADER, {"tape_prob": 1.0}))
	P.boxes(root3, paint_boxes, P.mat(P.BOX_SHADER, {"paint": 1.0, "paint_col": Color("#1FA855"), "paint_emit": 0.25}))
	P.lens(self, 0.4)
	cam = Camera3D.new()
	cam.near = 0.05
	cam.far = 300.0
	add_child(cam)

func _env() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#8A6A4A")
	env.ambient_light_energy = 0.30
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.82
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_bloom = 0.02
	env.glow_hdr_threshold = 1.1
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.fog_enabled = true
	env.fog_light_color = Color(0, 0, 0)
	env.fog_density = 0.012
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 0.95
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

func _floor() -> void:
	# Buehnenboden: Pappbahnen 1,2 x 2,4 m, teils mit Klebeband auf den Stoessen
	var f := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, Z0 - Z1 + 26)
	f.mesh = pm
	f.position = Vector3(0, 0, (Z0 + Z1) * 0.5 - 11.0)
	f.material_override = P.mat(P.FLOOR_SHADER, {"tint": Color(1.02, 1.0, 0.98), "tape_seams": 0.15, "far_flat": 26.0, "sheet": Vector2(2.4, 4.8), "seam_dark": 0.35, "lane_half": STREET_W * 0.5})
	root3.add_child(f)
	# Buehnenkante vorn: schwarze Stirn
	var lip := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(40, 1.2, 0.2)
	lip.mesh = bm
	lip.position = Vector3(0, -0.6, Z0 + 2.0)
	var black := StandardMaterial3D.new()
	black.albedo_color = Color(0.01, 0.01, 0.01)
	lip.material_override = black
	root3.add_child(lip)

# Ein Haus = Abschnitt einer Strassenseite. side -1 links (Wand bei x = -STREET_W/2, Kartons nach -x)
func _house(side: float, z_start: float, length: float, height: float, setback: float, kind: int) -> void:
	var x := side * (STREET_W * 0.5 + setback)
	# Wand laeuft entlang -z (links) bzw. +z (rechts), damit nrm zur Strasse zeigt
	var ax := Vector3(0, 0, -1) if side < 0 else Vector3(0, 0, 1)
	var o := Vector3(x, 0, z_start) if side < 0 else Vector3(x, 0, z_start - length)
	var nrm := Vector3(1, 0, 0) if side < 0 else Vector3(-1, 0, 0)
	var holes: Array = []
	# Fenster in Reihen; Erdgeschoss: Tuer oder Laden
	var bays := int(length / 1.8)
	var bay_w := length / bays
	for b in bays:
		var cx := bay_w * (b + 0.5)
		if b == bays / 2 or (kind == 1 and b == 0):
			holes.append(Rect2(cx - 0.55, 0.0, 1.1, 2.15))
		elif kind == 1:
			holes.append(Rect2(cx - 0.7, 0.55, 1.4, 1.6))
		else:
			holes.append(Rect2(cx - 0.42, 0.85, 0.84, 1.15))
		var fl := 2.9
		while fl + 1.4 < height - 0.4:
			holes.append(Rect2(cx - 0.42, fl, 0.84, 1.2))
			fl += 2.3
	P.stack_wall(boxes, rng, o, ax, nrm, length, height, holes, {"print": 0.35, "prints": [1, 2, 3, 13, 14, 1], "depth": Vector2(0.42, 0.46)})
	# Gesims: eine Reihe vorspringender, flacher Kartons
	var gy := height
	var gl := 0.0
	while gl < length - 0.1:
		var w := rng.randf_range(0.5, 0.75)
		w = min(w, length - gl)
		boxes.append({"p": o + ax * (gl + w * 0.5) + Vector3.UP * (gy + 0.11) + nrm * (0.06 - 0.25), "s": Vector3(w - 0.004, 0.22, 0.5),
			"r": atan2(-ax.z, ax.x), "t": 1.0, "b": rng.randf(), "seed": rng.randf()})
		gl += w
	# Fenster: Packpapier dahinter, Licht dahinter; Tueren: dunkles Papier
	for h in holes:
		var r: Rect2 = h
		var mid := o + ax * (r.position.x + r.size.x * 0.5) + Vector3.UP * (r.position.y + r.size.y * 0.5) + nrm * -0.42
		var door := r.position.y < 0.01
		var lit := (not door) and rng.randf() < 0.8
		var pmat := P.mat(P.PAPER_SHADER, {"folds": 6.0 + rng.randf() * 4.0, "fold_depth": 0.045, "crumple": 0.03,
			"seed": rng.randf() * 50.0, "glow": (Color(1.0, 0.64, 0.30) * 1.1) if lit else Color(0, 0, 0),
			"tint": Color(1, 1, 1) if not door else Color(0.6, 0.55, 0.5)})
		P.paper_sheet(root3, mid, Vector2(r.size.x + 0.1, r.size.y + 0.1), atan2(nrm.x, nrm.z), pmat, 60)
		if lit and rng.randf() < 0.35:
			P.omni(root3, mid + nrm * -0.5, Color(1.0, 0.66, 0.36), 1.4, 3.2)
		# Fensterbank: flacher Karton
		if not door:
			boxes.append({"p": o + ax * (r.position.x + r.size.x * 0.5) + Vector3.UP * (r.position.y - 0.03) + nrm * 0.06,
				"s": Vector3(r.size.x + 0.16, 0.06, 0.2), "r": atan2(-ax.z, ax.x), "t": 0.0, "b": rng.randf(), "seed": rng.randf()})

func _street() -> void:
	# links und rechts Hauszeilen, links bei z = -6..-10 eine Seitengasse
	var z := Z0
	var segs_l := [[6.2, 5.6, 0.0, 0], [5.4, 4.6, 0.15, 1], [4.0, 0.0, 0.0, -1], [6.6, 6.2, 0.05, 0], [5.8, 5.0, 0.2, 1], [6.0, 5.8, 0.0, 0], [5.0, 4.4, 0.1, 0]]
	for s in segs_l:
		if s[3] >= 0:
			_house(-1.0, z, s[0], s[1], s[2], s[3])
		z -= s[0]
	z = Z0
	var segs_r := [[5.0, 4.8, 0.1, 1], [6.4, 6.0, 0.0, 0], [5.6, 5.2, 0.2, 0], [6.0, 4.4, 0.05, 1], [6.8, 6.4, 0.0, 0], [5.2, 5.0, 0.15, 0], [4.0, 4.0, 0.0, 0]]
	for s in segs_r:
		_house(1.0, z, s[0], s[1], s[2], s[3])
		z -= s[0]
	# Seitengasse links: Rueckwand mit Blick auf eine Laterne
	_house(-1.0, Z0 - 11.6 + 0.0, 4.0, 3.2, 4.0, 0)

func _square() -> void:
	# Platz am Ende: Uhrturm aus Kartons (Wahrzeichen), gruene Kartontuer (Ausgang)
	var zc := Z1 - 4.0
	# Platzwaende links/rechts und hinten (niedriger)
	_house(-1.0, Z1 + 0.0, 9.0, 3.4, 3.5, 0)
	_house(1.0, Z1 + 0.0, 9.0, 3.8, 3.5, 1)
	# Turm: 2,6 x 2,6 m Grundriss, 11 m hoch, vier Wandseiten gestapelt
	var tz := zc - 3.0
	var hw := 1.3
	var th := 10.5
	P.stack_wall(boxes, rng, Vector3(-hw, 0, tz + hw), Vector3(1, 0, 0), Vector3(0, 0, 1), 2 * hw, th, [Rect2(0.85, 0.0, 0.9, 2.0)], {"jut": 0.03})
	P.stack_wall(boxes, rng, Vector3(hw, 0, tz - hw), Vector3(-1, 0, 0), Vector3(0, 0, -1), 2 * hw, th, [], {"jut": 0.03})
	P.stack_wall(boxes, rng, Vector3(-hw, 0, tz - hw), Vector3(0, 0, 1), Vector3(-1, 0, 0), 2 * hw, th, [], {"jut": 0.03})
	P.stack_wall(boxes, rng, Vector3(hw, 0, tz + hw), Vector3(0, 0, -1), Vector3(1, 0, 0), 2 * hw, th, [], {"jut": 0.03})
	# Turmhelm: gestufte Kartons
	for i in 4:
		var s := 2.9 - i * 0.62
		boxes.append({"p": Vector3(0, th + 0.2 + i * 0.42, tz - 0.25), "s": Vector3(s, 0.4, s), "t": 1.0, "b": rng.randf(), "seed": rng.randf()})
	# Zifferblatt: Pappscheibe mit Wellen-Schnittkante, Zeiger aus Pappstreifen
	var face_m := P.mat(P.BOX_SHADER, {"tape_prob": 0.0})
	var edge_m := P.mat(P.EDGE_SHADER, {"thick": 0.03, "pitch": 0.03})
	var disc := Geo.extrude(root3, Geo.circle_poly(0.95, 48), 0.03, _flat_mat(), edge_m, Vector3(0, th - 1.6, tz + hw + 0.06))
	var ring := Geo.extrude(root3, Geo.circle_poly(1.08, 48), 0.02, _flat_mat(0.82), edge_m, Vector3(0, th - 1.6, tz + hw + 0.035))
	for k in 12:
		var a := k / 12.0 * TAU
		boxes.append({"p": Vector3(sin(a) * 0.78, th - 1.6 + cos(a) * 0.78, tz + hw + 0.085), "s": Vector3(0.05, 0.16 if k % 3 == 0 else 0.09, 0.012), "rz": -a, "t": 0.0, "b": 0.1, "seed": rng.randf()})
	boxes.append({"p": Vector3(0.18, th - 1.6 + 0.26, tz + hw + 0.1), "s": Vector3(0.06, 0.62, 0.012), "rz": -0.6, "t": 0.0, "b": 0.05, "seed": rng.randf()})
	boxes.append({"p": Vector3(-0.3, th - 1.6 + 0.08, tz + hw + 0.11), "s": Vector3(0.06, 0.42, 0.012), "rz": 1.3, "t": 0.0, "b": 0.05, "seed": rng.randf()})
	P.spot(root3, Vector3(0, th - 1.6, tz + 9.0), Vector3(0, th - 1.6, tz + hw), Color(1.0, 0.86, 0.66), 6.0, 9.0, 16.0, 0.0, false)
	# Ausgang: gruen gestrichene Kartontuer rechts am Turm, Licht dahinter
	var ex := Vector3(3.6, 0, zc - 1.2)
	var dl: Array = []
	P.stack_wall(paint_boxes, rng, ex + Vector3(-1.1, 0, 0), Vector3(1, 0, 0), Vector3(0, 0, 1), 2.2, 2.9, [Rect2(0.5, 0.0, 1.2, 2.3)], {"tape": 0.3, "print": 0.0})
	var gpaper := P.mat(P.PAPER_SHADER, {"folds": 5.0, "fold_depth": 0.05, "crumple": 0.03, "seed": 3.0,
		"glow": Color(0.25, 1.0, 0.45) * 2.4, "tint": Color(0.75, 1.05, 0.8)})
	P.paper_sheet(root3, ex + Vector3(0.0, 1.17, -0.45), Vector2(1.25, 2.35), 0.0, gpaper, 60)
	P.omni(root3, ex + Vector3(0, 1.4, 1.0), Color(0.3, 1.0, 0.5), 2.2, 6.0)
	P.spot(root3, ex + Vector3(0, 6.5, 3.0), ex + Vector3(0, 0, 0.6), Color(0.35, 1.0, 0.5), 3.0, 22.0, 12.0, 0.05, true)

func _flat_mat(bri := 1.0) -> ShaderMaterial:
	# Flaechen von Ausschnitten (extrude): Kraftliner mit UV in Metern
	var m := P.mat(P.FLOOR_SHADER.replace("vec2 p = wp.xz;", "vec2 p = UV * 1.0;"), {"sheet": Vector2(50, 50), "tape_seams": 0.0, "scuff": 0.0, "tint": Color(bri, bri, bri)})
	return m

func _lamps() -> void:
	# Laternen: Papprolle + Packpapierschirm mit Gluehen + Omni-Licht
	var tube_m := P.mat(P.TUBE_SHADER, {})
	for l in [[-1.0, 9.5], [1.0, 3.0], [-1.0, -3.2], [1.0, -12.0], [-1.0, -20.0], [1.0, -26.5]]:
		var x: float = l[0] * (STREET_W * 0.5 - 0.35)
		var z: float = l[1]
		P.tube(root3, Vector3(x, 1.6, z), 0.07, 3.2, tube_m)
		var shade := P.mat(P.PAPER_SHADER, {"folds": 7.0, "fold_depth": 0.02, "crumple": 0.02, "seed": z, "glow": Color(1.0, 0.66, 0.3) * 1.5})
		# Schirm als gerollte Bahn: vier Bahnen im Quadrat
		for k in 4:
			var a := k * PI * 0.5
			P.paper_sheet(root3, Vector3(x + sin(a) * 0.2, 3.45, z + cos(a) * 0.2), Vector2(0.42, 0.55), a, shade, 24)
		P.omni(root3, Vector3(x, 3.45, z), Color(1.0, 0.68, 0.36), 1.6, 5.5, false)

func _rig() -> void:
	# Scheinwerfer: harte, warme Kegel von oben vorn, Dunst; Gegenlicht kuehl-neutral von hinten
	var warm := P.kelvin(3500)
	P.spot(root3, Vector3(-6.0, 14.0, 18.0), Vector3(-0.3, 0.0, 6.0), warm, 16.0, 18.0, 40.0, 0.16)
	P.spot(root3, Vector3(5.0, 13.0, 4.0), Vector3(0.4, 0.0, -6.0), warm, 16.0, 17.0, 36.0, 0.16)
	P.spot(root3, Vector3(-4.0, 13.0, -9.0), Vector3(0.0, 0.0, -19.0), warm, 15.0, 17.0, 36.0, 0.16)
	P.spot(root3, Vector3(3.0, 15.0, -18.0), Vector3(0.0, 0.0, -32.0), warm, 16.0, 20.0, 40.0, 0.14)
	P.spot(root3, Vector3(0.0, 12.0, -48.0), Vector3(0.0, 2.0, -24.0), P.kelvin(6500), 14.0, 25.0, 50.0, 0.025)
	P.spot(root3, Vector3(-7.0, 15.0, -26.0), Vector3(1.0, 0.0, -36.0), warm, 12.0, 22.0, 30.0, 0.1)
	P.spot(root3, Vector3(0.0, 22.0, 34.0), Vector3(0.0, 0.0, -12.0), P.kelvin(3800), 2.2, 32.0, 80.0, 0.0, false)
	# Traversen im Dunkeln (fangen etwas Licht): schwarze Rohre mit Scheinwerfergehaeusen
	var black := StandardMaterial3D.new()
	black.albedo_color = Color(0.03, 0.03, 0.03)
	black.roughness = 0.4
	black.metallic = 0.6
	for z in [18.0, 4.0, -9.0, -18.0]:
		var bar := Geo.cylinder(root3, Vector3(0, 14.6, z), 0.05, 0.05, 30.0, black)
		bar.rotation.z = PI / 2.0

func _pellets() -> void:
	# Blaue Glasmurmeln auf der Strassenmitte, liegen auf dem Boden
	var pts: Array = []
	var z := Z0 - 3.0
	while z > Z1 - 2.0:
		pts.append(Vector3(rng.randf_range(-0.04, 0.04), 0.17, z))
		z -= 1.6
	# Abzweig in die Seitengasse
	for i in 4:
		pts.append(Vector3(-1.6 - i * 1.4, 0.17, Z0 - 13.3))
	P.marbles(root3, pts, 0.17, P.mat(P.MARBLE_SHADER, {"pulse": 0.0 if reduce_fx else 0.0}))

func views() -> Array:
	return [
		["strasse", Vector3(0.35, 1.9, 13.0), Vector3(-0.2, 2.2, -20.0), 68.0],
		["totale", Vector3(-1.5, 9.5, 27.0), Vector3(0.0, 1.0, -8.0), 50.0],
		["turm", Vector3(-1.2, 1.9, -24.0), Vector3(0.8, 5.5, -37.0), 72.0],
		["capsule", Vector3(1.2, 1.7, 7.0), Vector3(-0.8, 3.0, -30.0), 60.0],
	]

func set_view(pos: Vector3, look: Vector3, fov: float) -> void:
	cam.position = pos
	cam.look_at(look)
	cam.fov = fov
