# Richtung K "Umzugswohnung" – Stil-Prototyp (Art Director, Nachtrag 04.10.2026, NICHT Spielcode).
# Eine Altbauwohnung am Umzugsabend, in der alles aus Pappe ist: Umzugskartons sind zu Gaengen
# gestapelt (das Labyrinth), beschriftet mit Edding ("KUECHE", "BUECHER" – die Beschriftung ist
# zugleich Wegweiser), Moebel aus Pappe sind die Wahrzeichen (Standuhr, Ohrensessel, Regal,
# Esstisch, Stehlampe). Abendsonne gluet durch zerknitterte Packpapier-Vorhaenge, Haengelampen mit
# Packpapierschirm. Kugeln = blaue Glasmurmeln auf dem Boden. Ausgang = gruen gestrichene
# Wohnungstuer, Licht aus dem Treppenhaus.
extends Node3D

const P := preload("res://pappe.gd")
const Geo := preload("res://geo.gd")

var cam: Camera3D
var rng := RandomNumberGenerator.new()
var reduce_fx := false
var boxes: Array = []
var furn: Array = []
var shell: Array = []
var paint_boxes: Array = []
var ceil: Array = []
var ceil_mmi: MultiMeshInstance3D
var root3: Node3D

const X0 := -8.0
const X1 := 8.0
const Z0 := 4.0
const Z1 := -20.0
const CEIL := 3.1

func _init() -> void:
	rng.seed = 2207
	reduce_fx = OS.get_environment("REDUCE_FX") == "1"
	root3 = Node3D.new()
	add_child(root3)
	_env()
	_shell()
	_stacks()
	_furniture()
	_windows()
	_lamps()
	_exit()
	_marbles()
	P.boxes(root3, boxes, P.mat(P.BOX_SHADER, {"hole_prob": 0.45}))
	P.boxes(root3, furn, P.mat(P.BOX_SHADER, {"hole_prob": 0.0, "bulge": 0.006}))
	P.boxes(root3, shell, P.mat(P.BOX_SHADER, {"panel": 1.0, "edge_pitch": 0.008, "hole_prob": 0.0, "bulge": 0.0, "edge_ao": 0.85}))
	ceil_mmi = P.boxes(root3, ceil, P.mat(P.BOX_SHADER, {"panel": 1.0, "edge_pitch": 0.008, "hole_prob": 0.0, "bulge": 0.0, "edge_ao": 0.85}))
	P.boxes(root3, paint_boxes, P.mat(P.BOX_SHADER, {"paint": 1.0, "paint_col": Color("#1FA855"), "paint_emit": 0.2, "hole_prob": 0.0, "bulge": 0.004}))
	P.lens(self, 0.38)
	cam = Camera3D.new()
	cam.near = 0.05
	cam.far = 200.0
	add_child(cam)

func _env() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.015, 0.01)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#8C6A48")
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.9
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_bloom = 0.03
	env.glow_hdr_threshold = 1.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 0.95
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

func _b(list: Array, p: Vector3, s: Vector3, extra := {}) -> void:
	var d := {"p": p, "s": s, "t": 0.0, "i": 0.0, "b": rng.randf(), "seed": rng.randf()}
	d.merge(extra, true)
	list.append(d)

func _shell() -> void:
	# Boden: Pappbahnen; Waende und Decke: grosse Pappplatten (Plattenmodus, Stoesse sichtbar)
	var f := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(X1 - X0, Z0 - Z1)
	f.mesh = pm
	f.position = Vector3((X0 + X1) * 0.5, 0, (Z0 + Z1) * 0.5)
	f.material_override = P.mat(P.FLOOR_SHADER, {"tape_seams": 0.4, "sheet": Vector2(1.2, 2.4), "seam_dark": 0.55})
	root3.add_child(f)
	var t := 0.03
	# Waende aus Platten 1,2 m breit
	var zz := Z0
	while zz > Z1 + 0.01:
		var w: float = min(1.2, zz - Z1)
		for sx in [X0, X1]:
			if sx == X1 and zz < -1.0 and zz > -8.6:
				continue  # Fensterwand: wird in _windows gebaut
			_b(shell, Vector3(sx, CEIL * 0.5, zz - w * 0.5), Vector3(t, CEIL, w - 0.004), {"b": rng.randf_range(0.45, 0.6)})
		zz -= 1.2
	var xx := X0
	while xx < X1 - 0.01:
		var w2: float = min(1.2, X1 - xx)
		_b(shell, Vector3(xx + w2 * 0.5, CEIL * 0.5, Z0), Vector3(w2 - 0.004, CEIL, t), {"b": rng.randf_range(0.45, 0.6)})
		if abs(xx + w2 * 0.5) > 1.0:
			_b(shell, Vector3(xx + w2 * 0.5, CEIL * 0.5, Z1), Vector3(w2 - 0.004, CEIL, t), {"b": rng.randf_range(0.45, 0.6)})
		xx += 1.2
	# Decke: Platten, darunter Deckenleisten
	xx = X0
	while xx < X1 - 0.01:
		zz = Z0
		while zz > Z1 + 0.01:
			_b(ceil, Vector3(xx + 0.6, CEIL + 0.015, zz - 1.2), Vector3(1.196, t, 2.396), {"b": rng.randf_range(0.35, 0.5)})
			zz -= 2.4
		xx += 1.2
	# Fussleisten
	for sx in [X0 + 0.03, X1 - 0.03]:
		_b(shell, Vector3(sx, 0.06, (Z0 + Z1) * 0.5), Vector3(0.025, 0.12, Z0 - Z1), {"b": 0.3})

# Stapel als Block: Aussenseiten aus gestapelten Kartons, oben eine Deckschicht
func _block(x0: float, z0: float, x1: float, z1: float, h: float, labels: Array) -> void:
	var opts := {"print": 0.45, "prints": labels, "tape": 0.85, "heights": [0.32, 0.38, 0.4, 0.45], "widths": [0.4, 0.5, 0.6, 0.6], "depth": Vector2(0.4, 0.55)}
	P.stack_wall(boxes, rng, Vector3(x0, 0, z0), Vector3(1, 0, 0), Vector3(0, 0, 1), x1 - x0, h, [], opts)
	P.stack_wall(boxes, rng, Vector3(x1, 0, z1), Vector3(-1, 0, 0), Vector3(0, 0, -1), x1 - x0, h, [], opts)
	P.stack_wall(boxes, rng, Vector3(x0, 0, z1), Vector3(0, 0, 1), Vector3(-1, 0, 0), z0 - z1, h, [], opts)
	P.stack_wall(boxes, rng, Vector3(x1, 0, z0), Vector3(0, 0, -1), Vector3(1, 0, 0), z0 - z1, h, [], opts)
	# ein paar lose Kartons oben drauf (unregelmaessige Silhouette)
	for i in rng.randi_range(1, 3):
		var w := rng.randf_range(0.4, 0.6)
		var hh := rng.randf_range(0.3, 0.42)
		_b(boxes, Vector3(rng.randf_range(x0 + 0.4, x1 - 0.4), h + hh * 0.5 + 0.004, rng.randf_range(z1 + 0.4, z0 - 0.4)), Vector3(w, hh, rng.randf_range(0.35, 0.5)),
			{"r": rng.randf_range(-0.3, 0.3), "t": 1.0, "i": float(labels[rng.randi() % labels.size()])})

func _stacks() -> void:
	# Grundriss: Flur von der Tuer (Start, z = +3) nach Norden; links Wohnzimmer, rechts Essplatz am Fenster
	var L_KUE := [5, 5, 12, 10, 3]      # KUECHE, Pfeil, GLAS
	var L_BUE := [4, 4, 8, 13, 14]      # BUECHER, DIVERSES, Kreuz, Nummer
	var L_BAD := [6, 6, 11, 7, 9]       # BAD, FLUR, WINTER, OBEN!
	_block(-3.6, 2.6, -1.0, -1.4, 1.75, L_BAD)
	_block(1.0, 2.6, 3.2, 0.4, 2.15, L_KUE)
	_block(1.0, -1.6, 2.8, -4.8, 1.6, L_KUE)
	_block(-3.0, -3.4, -1.0, -7.0, 2.3, L_BUE)
	_block(1.2, -9.4, 3.4, -11.6, 1.85, L_KUE)
	_block(-3.4, -9.2, -1.1, -13.2, 1.7, L_BUE)
	_block(1.1, -13.6, 2.6, -17.0, 2.2, L_BAD)
	_block(-7.6, -17.0, -4.6, -19.6, 2.4, L_BUE)
	_block(4.8, 3.6, 7.6, 1.2, 1.9, L_KUE)
	_block(-7.6, 3.6, -5.2, 0.4, 2.0, L_BAD)

func _furniture() -> void:
	# Standuhr (Wahrzeichen, links hinten): Korpus, Kopf mit Zifferblatt, Pendelfenster
	var c := Vector3(-6.9, 0, -8.5)
	_b(furn, c + Vector3(0, 0.9, 0), Vector3(0.42, 1.8, 0.55), {"b": 0.35})
	_b(furn, c + Vector3(0, 2.05, 0), Vector3(0.5, 0.55, 0.62), {"b": 0.4})
	_b(furn, c + Vector3(0, 2.38, 0), Vector3(0.56, 0.1, 0.68), {"b": 0.5})
	_b(furn, c + Vector3(0, 0.06, 0), Vector3(0.52, 0.12, 0.66), {"b": 0.5})
	var face := Geo.extrude(root3, Geo.circle_poly(0.21, 40), 0.006, P.flat_mat({"tint": Color(1.12, 1.1, 1.06)}), P.mat(P.EDGE_SHADER, {}), c + Vector3(0.215, 2.06, 0), Vector3(0, PI * 0.5, 0))
	for k in 12:
		var a := k / 12.0 * TAU
		_b(furn, c + Vector3(0.222, 2.06 + cos(a) * 0.17, sin(a) * 0.17), Vector3(0.004, 0.035 if k % 3 == 0 else 0.02, 0.012), {"rx": a, "b": 0.0})
	_b(furn, c + Vector3(0.224, 2.1, 0.03), Vector3(0.004, 0.13, 0.014), {"rx": -0.6, "b": 0.0})
	_b(furn, c + Vector3(0.224, 2.04, -0.04), Vector3(0.004, 0.09, 0.014), {"rx": 2.1, "b": 0.0})
	# Pendelfenster: dunkle Oeffnung mit Pendelscheibe
	_b(furn, c + Vector3(0.212, 1.05, 0), Vector3(0.004, 0.9, 0.3), {"b": 0.0, "i": 0.0})
	_b(furn, c + Vector3(0.216, 1.25, 0), Vector3(0.004, 0.5, 0.02), {"b": 0.6})
	Geo.extrude(root3, Geo.circle_poly(0.07, 24), 0.006, P.flat_mat(), P.mat(P.EDGE_SHADER, {}), c + Vector3(0.222, 0.95, 0), Vector3(0, PI * 0.5, 0))
	# Akzentlicht auf die Uhr (Wahrzeichen bleibt ueber die Stapel hinweg lesbar)
	P.spot(root3, c + Vector3(1.8, 2.9, -1.2), c + Vector3(0, 1.6, 0), P.kelvin(3000), 3.5, 22.0, 5.0, 0.0, true)
	# Ohrensessel (vor der Uhr, schraeg)
	var s := Node3D.new()
	var sc := Vector3(-5.6, 0, -11.0)
	var sl: Array = [[Vector3(0, 0.22, 0), Vector3(0.8, 0.44, 0.75)], [Vector3(0, 0.5, 0.05), Vector3(0.6, 0.12, 0.6)], [Vector3(0, 0.75, -0.33), Vector3(0.8, 1.1, 0.14)],
		[Vector3(-0.36, 0.55, 0.0), Vector3(0.12, 0.3, 0.7)], [Vector3(0.36, 0.55, 0.0), Vector3(0.12, 0.3, 0.7)], [Vector3(-0.36, 1.1, -0.22), Vector3(0.1, 0.4, 0.3)], [Vector3(0.36, 1.1, -0.22), Vector3(0.1, 0.4, 0.3)]]
	var ra := 0.7
	for e in sl:
		var off: Vector3 = Basis(Vector3.UP, ra) * e[0]
		_b(furn, sc + off, e[1], {"r": ra, "b": 0.55})
	# Buecherregal an der Westwand: Rahmen + Pappbuecher
	var rx := X0 + 0.2
	var rz := -13.5
	_b(furn, Vector3(rx, 1.0, rz), Vector3(0.36, 2.0, 0.02), {"b": 0.5})
	_b(furn, Vector3(rx, 1.0, rz - 1.6), Vector3(0.36, 2.0, 0.02), {"b": 0.5})
	for k in 5:
		var y := 0.05 + k * 0.48
		_b(furn, Vector3(rx, y, rz - 0.8), Vector3(0.36, 0.025, 1.6), {"b": 0.6})
		if k < 4:
			var zb := rz - 0.04
			while zb > rz - 1.55:
				var bw := rng.randf_range(0.03, 0.07)
				var bh := rng.randf_range(0.25, 0.4)
				var lean := 0.0 if rng.randf() > 0.12 else 0.25
				_b(furn, Vector3(rx - 0.02, y + 0.0125 + bh * 0.5, zb - bw * 0.5), Vector3(rng.randf_range(0.2, 0.28), bh, bw - 0.003), {"b": rng.randf(), "rx": lean})
				zb -= bw + 0.002
				if rng.randf() < 0.08:
					zb -= 0.15
	# Esstisch mit vier Stuehlen am Fenster (rechts)
	var tc := Vector3(5.6, 0, -6.0)
	_b(furn, tc + Vector3(0, 0.74, 0), Vector3(1.0, 0.04, 1.7), {"b": 0.6, "t": 1.0})
	var tube_m := P.mat(P.TUBE_SHADER, {})
	for lx in [-0.42, 0.42]:
		for lz in [-0.75, 0.75]:
			P.tube(root3, tc + Vector3(lx, 0.36, lz), 0.03, 0.72, tube_m)
	for ch in [[Vector3(-0.75, 0, -0.35), PI * 0.5], [Vector3(-0.75, 0, 0.4), PI * 0.5], [Vector3(0.75, 0, -0.3), -PI * 0.5], [Vector3(0.0, 0, 1.15), PI]]:
		var cp: Vector3 = tc + ch[0]
		var r: float = ch[1] + rng.randf_range(-0.15, 0.15)
		_b(furn, cp + Vector3(0, 0.45, 0), Vector3(0.42, 0.03, 0.42), {"r": r, "b": 0.5})
		_b(furn, cp + Basis(Vector3.UP, r) * Vector3(0, 0.72, -0.2), Vector3(0.42, 0.55, 0.03), {"r": r, "b": 0.5})
		for lx2 in [-0.18, 0.18]:
			for lz2 in [-0.18, 0.18]:
				_b(furn, cp + Basis(Vector3.UP, r) * Vector3(lx2, 0.22, lz2), Vector3(0.03, 0.44, 0.03), {"r": r, "b": 0.45})
	# Tischlampe? Nein: Schale mit Pappobst waere Kitsch. Ein offener Karton mit Packpapier auf dem Tisch.
	_b(furn, tc + Vector3(0.1, 0.86, 0.3), Vector3(0.36, 0.2, 0.28), {"b": 0.7, "t": 0.0, "i": 5.0})

func _windows() -> void:
	# Fensterwand (Osten): zwei hohe Fenster, Packpapier-Vorhaenge, Abendsonne dahinter
	var t := 0.03
	var segs := [[-1.0, -2.2, "wall"], [-2.2, -3.8, "win"], [-3.8, -5.6, "wall"], [-5.6, -7.2, "win"], [-7.2, -8.6, "wall"]]
	for sgm in segs:
		var za: float = sgm[0]
		var zb: float = sgm[1]
		var zc := (za + zb) * 0.5
		var w: float = za - zb
		if sgm[2] == "wall":
			_b(shell, Vector3(X1, CEIL * 0.5, zc), Vector3(t, CEIL, w - 0.004), {"b": 0.5})
		else:
			_b(shell, Vector3(X1, 0.45, zc), Vector3(t, 0.9, w), {"b": 0.5})
			_b(shell, Vector3(X1, CEIL - 0.25, zc), Vector3(t, 0.5, w), {"b": 0.5})
			# Fensterbank
			_b(furn, Vector3(X1 - 0.1, 0.92, zc), Vector3(0.24, 0.04, w + 0.1), {"b": 0.7})
			# zwei Vorhangbahnen, leicht geoeffnet
			var pmat := P.mat(P.PAPER_SHADER, {"folds": 7.0, "fold_depth": 0.06, "crumple": 0.05, "seed": zc * 3.0,
				"glow": Color(1.0, 0.6, 0.25) * 1.25, "translucency": 1.0})
			P.paper_sheet(root3, Vector3(X1 - 0.12, 1.75, zc + w * 0.27), Vector2(w * 0.52, 2.4), -PI * 0.5, pmat, 70)
			P.paper_sheet(root3, Vector3(X1 - 0.14, 1.75, zc - w * 0.3), Vector2(w * 0.46, 2.4), -PI * 0.5, pmat, 70)
			# Abendsonne: harte Lichtbahn durch den Spalt auf den Boden
			P.spot(root3, Vector3(X1 + 4.0, 3.4, zc + 1.6), Vector3(X1 - 3.5, 0.0, zc - 0.6), P.kelvin(2700), 26.0, 14.0, 16.0, 0.05, true)
			P.omni(root3, Vector3(X1 + 0.5, 1.8, zc), Color(1.0, 0.62, 0.3), 2.0, 3.0)
			# draussen: helle Abendluft hinter dem Spalt (unbeleuchtete Leuchtflaeche)
			var sky := StandardMaterial3D.new()
			sky.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			sky.albedo_color = Color(1.0, 0.72, 0.42) * 1.6
			var sq := Geo.quad(root3, Vector3(X1 + 0.6, 1.75, zc), Vector2(w + 0.6, 2.6), sky, Vector3(0, -PI * 0.5, 0))
			sq.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _lamps() -> void:
	# Haengelampen mit Packpapierschirm (Gluehen) + warmes Licht mit Schatten
	for lp in [Vector3(0.0, 0, 0.2), Vector3(-0.2, 0, -8.0), Vector3(0.0, 0, -15.5), Vector3(-5.5, 0, -12.5)]:
		var y := CEIL - 0.75
		var shade := P.mat(P.PAPER_SHADER, {"folds": 6.0, "fold_depth": 0.015, "crumple": 0.02, "seed": lp.z, "glow": Color(1.0, 0.66, 0.32) * 1.8})
		for k in 6:
			var a := k * TAU / 6.0
			P.paper_sheet(root3, lp + Vector3(sin(a) * 0.22, y, cos(a) * 0.22), Vector2(0.24, 0.32), a, shade, 16, false)
		_b(furn, lp + Vector3(0, (CEIL + y) * 0.5 + 0.08, 0), Vector3(0.012, CEIL - y - 0.16, 0.012), {"b": 0.0})
		P.spot(root3, lp + Vector3(0, y - 0.12, 0), lp + Vector3(0.01, 0.0, 0.0), P.kelvin(2900), 4.6, 64.0, 6.5, 0.0, true)
		P.omni(root3, lp + Vector3(0, y + 0.1, 0), P.kelvin(2900), 0.7, 4.5, false)
	# Stehlampe neben dem Sessel
	var sp := Vector3(-6.6, 0, -11.9)
	P.tube(root3, sp + Vector3(0, 0.8, 0), 0.025, 1.6, P.mat(P.TUBE_SHADER, {}))
	_b(furn, sp + Vector3(0, 0.02, 0), Vector3(0.36, 0.04, 0.36), {"b": 0.5})
	var sh2 := P.mat(P.PAPER_SHADER, {"folds": 5.0, "fold_depth": 0.01, "crumple": 0.015, "seed": 9.0, "glow": Color(1.0, 0.64, 0.3) * 1.6})
	for k in 6:
		var a := k * TAU / 6.0
		P.paper_sheet(root3, sp + Vector3(sin(a) * 0.2, 1.72, cos(a) * 0.2), Vector2(0.22, 0.34), a, sh2, 14, false)
	P.spot(root3, sp + Vector3(0, 1.55, 0), sp + Vector3(0.3, 0.0, 0.2), P.kelvin(2800), 4.0, 55.0, 4.0, 0.0, true)
	P.omni(root3, sp + Vector3(0, 1.75, 0), P.kelvin(2800), 0.6, 3.0, false)

func _exit() -> void:
	# Wohnungstuer (Nordwand, Ende des Flurs): gruen gestrichener Karton, Tuerspalt mit Licht
	var dz := Z1 + 0.06
	_b(paint_boxes, Vector3(0, 1.05, dz), Vector3(1.0, 2.1, 0.06), {"b": 0.6})
	_b(paint_boxes, Vector3(-0.56, 1.1, dz), Vector3(0.1, 2.2, 0.1), {"b": 0.6})
	_b(paint_boxes, Vector3(0.56, 1.1, dz), Vector3(0.1, 2.2, 0.1), {"b": 0.6})
	_b(paint_boxes, Vector3(0, 2.25, dz), Vector3(1.22, 0.1, 0.1), {"b": 0.6})
	_b(furn, Vector3(0.38, 1.0, dz + 0.06), Vector3(0.12, 0.03, 0.04), {"b": 0.1})
	# Wand ueber der Tuer und Laibung
	_b(shell, Vector3(0, 2.7, Z1), Vector3(2.0, 0.8, 0.03), {"b": 0.5})
	# gruenes Licht aus dem Treppenhaus durch den Spalt unten
	var gp := P.mat(P.PAPER_SHADER, {"folds": 2.0, "fold_depth": 0.0, "crumple": 0.0, "seed": 1.0, "glow": Color(0.25, 1.0, 0.45) * 3.0, "tint": Color(0.8, 1.05, 0.85)})
	P.paper_sheet(root3, Vector3(0, 0.012, dz + 0.035), Vector2(0.96, 0.02), 0.0, gp, 4)
	P.omni(root3, Vector3(0, 0.5, dz + 0.6), Color(0.3, 1.0, 0.5), 1.4, 3.5)
	P.spot(root3, Vector3(0, 2.9, dz + 2.0), Vector3(0, 1.0, dz), Color(0.4, 1.0, 0.55), 2.2, 30.0, 5.0, 0.0, false)

func _marbles() -> void:
	var pts: Array = []
	var z := 1.6
	while z > Z1 + 1.2:
		pts.append(Vector3(rng.randf_range(-0.12, 0.12), 0.11, z))
		z -= 1.25
	for k in 4:
		pts.append(Vector3(-1.4 - k * 1.05, 0.11, -8.2 + rng.randf_range(-0.1, 0.1)))
	P.marbles(root3, pts, 0.11, P.mat(P.MARBLE_SHADER, {"energy": 2.0}))

func views() -> Array:
	return [
		["strasse", Vector3(0.05, 1.9, 3.2), Vector3(-0.1, 1.45, -16.0), 70.0],
		["totale", Vector3(9.0, 17.0, 11.0), Vector3(-0.5, 0.0, -8.5), 52.0],
		["uhr", Vector3(-4.0, 1.9, -15.6), Vector3(-6.6, 1.4, -9.0), 70.0],
		["fenster", Vector3(3.8, 1.9, -0.4), Vector3(7.6, 1.2, -6.2), 70.0],
		["ausgang", Vector3(0.1, 1.9, -12.0), Vector3(0.0, 1.2, -20.0), 70.0],
		["capsule", Vector3(0.4, 1.75, -0.6), Vector3(-1.5, 1.8, -12.0), 62.0],
	]

func set_view(pos: Vector3, look: Vector3, fov: float) -> void:
	cam.position = pos
	cam.look_at(look)
	cam.fov = fov
	# Aufsicht: Decke ausblenden (Puppenhaus-Schnitt)
	if ceil_mmi:
		ceil_mmi.visible = pos.y < CEIL
