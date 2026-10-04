# Richtung B v2 "Sternennacht ueber Arles – verfeinert" (Art Director, 04.10.2026, Prototyp, NICHT Spielcode).
# Baut die ganze Kartenskizze aus karte.json (wie kyoto_maze.gd: Strassen-Rechtecke, Wahrzeichen an
# Strassenenden) mit echten Arles-Orten, stilisiert und frei angeordnet:
#   Gelbes Haus (rekonstruiert, gruene Tuer = Ausgang) · Porte de la Cavalerie · Kai an der Rhone ·
#   Thermen-Apsis · Caféterrasse (ohne Namen) + roemische Saeulen + Statue · Amphitheater (Arenes) ·
#   Hotel de Ville mit Uhrturm · Obelisk · Saint-Trophime (Portal) · Theatre antique · Grand Prieure.
# Technik-Auflagen der Pruefung sichtbar umgesetzt (siehe shaders.gd): gebackener, nahtloser Wirbelhimmel
# (Flowmap, Drift 0,04), Strich-LOD (nah Impasto, ab ~25 m Mittelfarbe + Pixel-Filter), ruhiger Boden,
# Halo-MultiMesh, <= 8 Omni-Lichter ohne Schatten (alle anderen Laternen als gemalte Lichtpfuetzen),
# Kugeln Zinnober mit dunkler Kontur, Gruen nur am Ausgang, Passanten heller als der Boden.
# Umgebung: VARIANT = nacht (tiefe Nacht, Standard) | blau (blaue Stunde); REDUCE_FX=1; LOD=0 (Vergleich).
extends Node3D

const Geo := preload("res://geo.gd")
const SH := preload("res://shaders.gd")

var cam: Camera3D
var rng := RandomNumberGenerator.new()
var variant := "nacht"
var reduce_fx := false
var lod_on := 1.0
var K: Dictionary = {}
var R := 0
var C := 0
var open_: Array = []
var lm_at: Dictionary = {}
var lamps: Array = []            # Vector4(x, y, z, staerke) fuer Lichtpfuetzen
var refl: Array = []             # Spiegelungen im Wasser
var lamp_mats: Array = []
var halos: Array = []            # [pos, size, seed, rings, energy, typ]
var omni_count := 0
var sky_mat: ShaderMaterial
var facade_mat: ShaderMaterial
var far_mat: ShaderMaterial
var V: Dictionary = {}           # Farben/Werte der Variante

func c(h: String) -> Color: return Color.html(h)
func lin(h: String) -> Vector3:
	var k := Color.html(h).srgb_to_linear()
	return Vector3(k.r, k.g, k.b)

func reg(m: ShaderMaterial) -> ShaderMaterial:
	m.set_shader_parameter("lod_on", lod_on)
	m.set_shader_parameter("lod_near", 14.0)
	m.set_shader_parameter("lod_far", 28.0)
	m.set_shader_parameter("calm", 1.0 if reduce_fx else 0.0)
	lamp_mats.append(m)
	return m

var shader_cache := {}
var mat_cache := {}
func smat(code: String, params := {}) -> ShaderMaterial:
	# ein Shader-Objekt je Quelltext (spart Kompilierung), Material je Parametersatz
	if not shader_cache.has(code):
		var sh := Shader.new()
		sh.code = code
		shader_cache[code] = sh
	var m := ShaderMaterial.new()
	m.shader = shader_cache[code]
	for k in params:
		m.set_shader_parameter(k, params[k])
	return m

func M(a: String, b: String, acc: String, params := {}, two_sided := false) -> ShaderMaterial:
	var key := a + b + acc + str(params) + str(two_sided)
	if mat_cache.has(key):
		return mat_cache[key]
	var p := {"col_a": c(a), "col_b": c(b), "col_c": c(acc)}
	p.merge(params, true)
	var m := reg(smat(SH.OBJ2S if two_sided else SH.OBJ, p))
	mat_cache[key] = m
	return m

func wx(col: float) -> float: return col * 2.0 + 1.0
func wz(row: float) -> float: return row * 2.0 + 1.0

func _ready() -> void:
	reduce_fx = OS.get_environment("REDUCE_FX") == "1"
	if OS.get_environment("VARIANT") != "":
		variant = OS.get_environment("VARIANT")
	if OS.get_environment("LOD") == "0":
		lod_on = 0.0
	rng.seed = 1888
	_load_map()
	_variant_values()
	cam = Camera3D.new()
	cam.near = 0.1
	cam.far = 1400.0
	add_child(cam)
	cam.current = true
	_environment()
	_place_lamps()
	_sky()
	_ground()
	_water()
	_blocks()
	_parapet()
	_landmarks()
	_trees()
	_life()
	_far()
	_halos()
	_pellets()
	for m in lamp_mats:
		var arr := PackedVector4Array()
		for l in lamps:
			arr.append(l)
		m.set_shader_parameter("lamps", arr)
		m.set_shader_parameter("nlamps", min(lamps.size(), 48))
	assert(omni_count <= 8, "Auflage: hoechstens 8 Omni-Lichter")
	print("ARLES omni=", omni_count, " lamps=", lamps.size(), " halos=", halos.size(), " variant=", variant, " reduce=", reduce_fx, " lod=", lod_on)

# ---------------------------------------------------------------- Karte
func _load_map() -> void:
	K = JSON.parse_string(FileAccess.get_file_as_string("res://karte.json"))
	R = int(K["rows"])
	C = int(K["cols"])
	for r in R:
		var row := []
		row.resize(C)
		row.fill(false)
		open_.append(row)
	for s in K["streets"]:
		for r in range(int(s["r0"]), int(s["r1"]) + 1):
			for cc in range(int(s["c0"]), int(s["c1"]) + 1):
				open_[r][cc] = true
	for L in K["landmarks"]:
		for r in range(int(L["r0"]), int(L["r1"]) + 1):
			for cc in range(int(L["c0"]), int(L["c1"]) + 1):
				if L.get("gate", false) and open_[r][cc]:
					continue
				open_[r][cc] = false
				lm_at[Vector2i(r, cc)] = L["id"]

func is_parapet(r: int, cc: int) -> bool:
	var p: Dictionary = K["parapet"]
	return cc == int(p["col"]) and r >= int(p["r0"]) and r <= int(p["r1"])

func is_block(r: int, cc: int) -> bool:
	if r < 0 or cc < 0 or r >= R or cc >= C:
		return false
	return not open_[r][cc] and not lm_at.has(Vector2i(r, cc)) and not is_parapet(r, cc)

# ---------------------------------------------------------------- Variante
func _variant_values() -> void:
	if variant == "blau":
		V = {"bg": "#2A4A8E", "amb": "#4C66AC", "amb_e": 1.15, "fog": "#4A64A0", "fog_d": 0.0038,
			"moon": "#B4C8F0", "moon_e": 0.8, "sky": ["#25469A", "#4C7CC6", "#A6D2F2", "#F6D46A"], "glow": "#E7A77A", "glow_amt": 0.55,
			"lit": 0.24, "halo_e": 0.85, "pool": 0.7, "stars": 10, "pave": ["#46598A", "#3C4E7E", "#A8844A"],
			"water": ["#16306E", "#2C4F98", "#7FA6DA"]}
	else:
		V = {"bg": "#141D4A", "amb": "#2A3B7A", "amb_e": 0.9, "fog": "#1E2C66", "fog_d": 0.003,
			"moon": "#8FA8E0", "moon_e": 0.5, "sky": ["#1B2A6B", "#2F55A8", "#7FB2E5", "#F6C945"], "glow": "#000000", "glow_amt": 0.0,
			"lit": 0.38, "halo_e": 1.1, "pool": 1.0, "stars": 22, "pave": ["#33456F", "#2B3B66", "#9C7A3E"],
			"water": ["#0C1648", "#1E3478", "#5E86C8"]}

func _environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = c(V["bg"])
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = c(V["amb"])
	env.ambient_light_energy = V["amb_e"]
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	env.glow_enabled = OS.get_environment("NOGLOW") == ""
	env.glow_intensity = 0.5
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 1.1
	env.fog_enabled = true
	env.fog_light_color = c(V["fog"])
	env.fog_density = V["fog_d"]
	env.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var moon := DirectionalLight3D.new()
	moon.light_color = c(V["moon"])
	moon.light_energy = V["moon_e"]
	moon.rotation_degrees = Vector3(-38, 35, 0)
	add_child(moon)

func omni(pos: Vector3, col: String, energy: float, rng_: float) -> void:
	var l := OmniLight3D.new()
	l.light_color = c(col)
	l.light_energy = energy
	l.omni_range = rng_
	l.omni_attenuation = 1.3
	l.shadow_enabled = false
	l.position = pos
	add_child(l)
	omni_count += 1

# ---------------------------------------------------------------- Laternen
# Gaslaternen an Strassenrand, Kai-Bruestung und Plaetzen. Nur 8 echte Omni-Lichter (Auflage);
# alle anderen beleuchten Wand und Boden ueber die gemalte Lichtpfuetze im Shader.
func _place_lamps() -> void:
	var posts := [
		# Rue de la Calade
		[46.0, 68.6], [56.0, 68.6], [51.0, 73.4], [57.5, 73.4],
		# Place de la Republique
		[18.6, 65.0], [40.4, 64.6], [40.4, 75.4], [18.6, 75.0],
		# Rue de l'Hotel de Ville
		[24.6, 56.0], [29.4, 61.0],
		# Place du Forum
		[16.6, 33.0], [16.6, 50.6], [37.4, 50.6], [37.4, 37.0],
		# Rue du Forum
		[11.0, 43.4], [42.0, 38.6], [46.0, 43.4],
		# Place Lamartine, Thermen-Gasse, Rue de la Cavalerie
		[24.0, 15.4], [33.0, 2.6], [20.0, 18.6], [48.6, 9.0], [53.4, 18.0],
		# Rond-point des Arenes
		[60.0, 24.6], [78.0, 24.6], [60.0, 65.4], [78.0, 65.4], [48.6, 34.0], [48.6, 55.0], [87.4, 36.0], [87.4, 54.0],
	]
	for p in posts:
		_lamp(Vector3(p[0], 0, p[1]), 3.4)
	# Kai: auf der Bruestung, hoeher; spiegeln sich in der Rhone
	for z in [7.0, 17.0, 27.0, 37.0, 47.0, 57.0, 67.0]:
		_lamp(Vector3(1.75, 1.1, z), 3.6, true)
	omni(Vector3(2.6, 4.2, 17.0), "#FFC24A", 1.6, 12.0)
	omni(Vector3(2.6, 4.2, 47.0), "#FFC24A", 1.6, 12.0)
	# Wandlaternen am Gelben Haus
	_lamp(Vector3(11.6, 0, 2.5), 3.2)
	_lamp(Vector3(18.4, 0, 2.5), 3.2)

func _lamp(pos: Vector3, h: float, water := false) -> void:
	var post := M("#1A2340", "#121A30", "#2A3660", {"len": 0.5, "wid": 0.05})
	Geo.cylinder(self, pos + Vector3(0, h / 2, 0), 0.07, 0.12, h, post, 8)
	var glass := M("#FFE9A0", "#F6C945", "#FFFFFF", {"accent": 0.3, "len": 0.2, "wid": 0.05, "emit": 2.2})
	Geo.box(self, pos + Vector3(0, h + 0.3, 0), Vector3(0.36, 0.5, 0.36), glass)
	Geo.box(self, pos + Vector3(0, h + 0.6, 0), Vector3(0.5, 0.08, 0.5), post)
	var top := pos + Vector3(0, h + 0.3, 0)
	halos.append([top, 2.6, pos.z * 0.37 + pos.x, 6.0, V["halo_e"], 0])
	lamps.append(Vector4(top.x, top.y, top.z, 1.25 * V["pool"]))
	if water:
		refl.append(Vector4(top.x, top.y, top.z, 1.0))

# ---------------------------------------------------------------- Himmel (gebacken)
func _sky() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(2048, 1024)
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var rect := ColorRect.new()
	rect.size = Vector2(2048, 1024)
	rect.material = smat(SH.SKY_BAKE, {"W": 10.0})
	vp.add_child(rect)
	add_child(vp)
	var sk: Array = V["sky"]
	sky_mat = smat(SH.SKY, {"base": c(sk[0]), "mid": c(sk[1]), "light": c(sk[2]), "yellow": c(sk[3]),
		"glow": c(V["glow"]), "glow_amt": V["glow_amt"], "haze": c(V["fog"]), "moving": 0.0 if reduce_fx else 1.0, "baked": vp.get_texture()})
	var s := Geo.sphere(self, Vector3(45, -40, 41), 650.0, sky_mat, Vector3.ONE, 48)
	s.set_meta("nohull", true)
	_finish_bake(vp)
	# Sterne ringsum (die Kamera dreht sich im Spiel frei), Mond im Suedosten
	var n: int = V["stars"]
	for i in n:
		var az := float(i) / float(n) * TAU + rng.randf_range(-0.12, 0.12)
		var el := rng.randf_range(0.28, 1.05)
		var d := 330.0
		var p := Vector3(45, 0, 41) + Vector3(sin(az) * cos(el), sin(el), -cos(az) * cos(el)) * d
		halos.append([p, rng.randf_range(20.0, 44.0) * (0.75 if variant == "blau" else 1.0), float(i) * 1.7, 4.0 + float(i % 3), 1.4, 1])
	halos.append([Vector3(45, 0, 41) + Vector3(0.62, 0.42, 0.66).normalized() * 330.0, 100.0, 5.5, 7.0, 1.2, 2])

func _finish_bake(vp: SubViewport) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	if img == null:
		return
	img.generate_mipmaps()
	sky_mat.set_shader_parameter("baked", ImageTexture.create_from_image(img))
	var sd := OS.get_environment("SKY_SAVE")
	if sd != "":
		var small := img.duplicate()
		small.clear_mipmaps()
		small.resize(1024, 512)
		small.save_png(sd)
	vp.queue_free()

# ---------------------------------------------------------------- Boden, Wasser, Kai
func _ground() -> void:
	var gi := Image.load_from_file("res://raster.png")
	gi.convert(Image.FORMAT_L8)
	var pv: Array = V["pave"]
	var gm := reg(smat(SH.FLOOR, {"grid": ImageTexture.create_from_image(gi), "gsize": Vector2(C, R),
		"pave_a": c(pv[0]), "pave_b": c(pv[1]), "pave_c": c(pv[2]), "gutter": c("#0E1130"), "kerb": c("#6A6E92"),
		"outside": c("#1A1E40"), "calm_floor": 0.62 if reduce_fx else 0.45}))
	var g := Geo.plane(self, Vector3(300, 0, 40), Vector2(600, 1000), gm)
	g.set_meta("nohull", true)

func _water() -> void:
	var wv: Array = V["water"]
	var wm := reg(smat(SH.WATER, {"deep": c(wv[0]), "mid": c(wv[1]), "hi": c(wv[2]), "shimmer": 0.0 if reduce_fx else 1.0}))
	# gegenueberliegendes Ufer (Trinquetaille): Laternen fuer die Spiegelung
	for z in range(-40, 130, 14):
		var p := Vector3(-71.0, 3.2, float(z) + 3.0)
		refl.append(Vector4(p.x, p.y, p.z, 0.8))
		halos.append([p, 1.8, float(z), 5.0, V["halo_e"] * 0.9, 0])
	var arr := PackedVector4Array()
	for l in refl:
		arr.append(l)
	wm.set_shader_parameter("refl", arr)
	wm.set_shader_parameter("nrefl", min(refl.size(), 40))
	var w := Geo.plane(self, Vector3(-100, -2.2, 40), Vector2(200, 600), wm)
	w.set_meta("nohull", true)
	var quay := M("#6E6A7E", "#58556A", "#9A93A8", {"len": 0.5, "wid": 0.12, "angle": 0.0, "accent": 0.1})
	Geo.box(self, Vector3(-0.25, -1.1, 40), Vector3(0.5, 2.2, 260), quay)
	# Kaikante: die Kaimauer steht bei x = 1,4; die Bruestung (0,6 m) bildet die Kollisionskante x = 2
	Geo.box(self, Vector3(0.7, -0.6, 36.0), Vector3(1.4, 1.2, 68.0), quay)
	Geo.box(self, Vector3(-70.0, -1.1, 40), Vector3(1.0, 2.6, 260), quay)

func _parapet() -> void:
	var p: Dictionary = K["parapet"]
	var z0 := float(p["r0"]) * 2.0
	var z1 := float(p["r1"]) * 2.0 + 2.0
	var stone := M("#8A8296", "#6E6880", "#B8AEB8", {"len": 0.45, "wid": 0.1, "accent": 0.12})
	Geo.box(self, Vector3(1.7, 0.5, (z0 + z1) / 2), Vector3(0.6, 1.0, z1 - z0), stone)
	Geo.box(self, Vector3(1.7, 1.05, (z0 + z1) / 2), Vector3(0.75, 0.12, z1 - z0), stone)

# ---------------------------------------------------------------- Haeuser aus dem Raster
func _lot(r: int, cc: int) -> Vector2i: return Vector2i(int(r / 3), int(cc / 3))
func _hash(v: Vector2i, k: float) -> float:
	var x := sin(float(v.x) * 127.1 + float(v.y) * 311.7 + k * 74.7) * 43758.5453
	return x - floor(x)

func _roof(x: float, z: float, lot: Vector2i, h: float, ridge_x: bool) -> float:
	var lzc := float(lot.x) * 6.0 + 3.0
	var lxc := float(lot.y) * 6.0 + 3.0
	if ridge_x:
		return h + 1.3 * (1.0 - clamp(abs(z - lzc) / 3.0, 0.0, 1.0))
	return h + 1.3 * (1.0 - clamp(abs(x - lxc) / 3.0, 0.0, 1.0))

func _tri(st: SurfaceTool, a: Vector3, b: Vector3, d: Vector3, n: Vector3) -> void:
	if (b - a).cross(d - a).dot(n) > 0.0:
		var t := b
		b = d
		d = t
	st.set_normal(n)
	st.add_vertex(a)
	st.set_normal(n)
	st.add_vertex(b)
	st.set_normal(n)
	st.add_vertex(d)

func _quad(st: SurfaceTool, a: Vector3, b: Vector3, cq: Vector3, d: Vector3, n: Vector3, col: Color) -> void:
	st.set_color(col)
	_tri(st, a, b, cq, n)
	st.set_color(col)
	_tri(st, a, cq, d, n)

func _blocks() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pals := [0, 1, 2, 3, 4, 5, 0, 2, 5, 1]
	for r in R:
		for cc in C:
			if not is_block(r, cc):
				continue
			var lot := _lot(r, cc)
			var h := 7.0 + _hash(lot, 1.0) * 4.5
			var rx := _hash(lot, 2.0) < 0.5
			var pal: int = pals[int(_hash(lot, 3.0) * 10.0) % 10]
			var col := Color(float(pal) / 8.0, _hash(lot, 4.0), h / 20.0, 1.0)
			var x0 := cc * 2.0
			var z0 := r * 2.0
			# Dach: in zwei Haelften quer zum First, damit der First als Kante liegt
			for k in 2:
				var xa := x0 + (0.0 if rx else float(k))
				var xb := x0 + (2.0 if rx else float(k) + 1.0)
				var za := z0 + (float(k) if rx else 0.0)
				var zb := z0 + (float(k) + 1.0 if rx else 2.0)
				var p1 := Vector3(xa, _roof(xa, za, lot, h, rx), za)
				var p2 := Vector3(xb, _roof(xb, za, lot, h, rx), za)
				var p3 := Vector3(xb, _roof(xb, zb, lot, h, rx), zb)
				var p4 := Vector3(xa, _roof(xa, zb, lot, h, rx), zb)
				var n := (p2 - p1).cross(p4 - p1).normalized()
				if n.y < 0:
					n = -n
				_quad(st, p1, p2, p3, p4, n, col)
			# Seiten: Fassade ueberall, wo der Nachbar kein Block desselben Grundstuecks ist
			var sides := [[Vector2i(-1, 0), Vector3(0, 0, -1)], [Vector2i(1, 0), Vector3(0, 0, 1)], [Vector2i(0, -1), Vector3(-1, 0, 0)], [Vector2i(0, 1), Vector3(1, 0, 0)]]
			for sd in sides:
				var d: Vector2i = sd[0]
				var n: Vector3 = sd[1]
				var nr := r + d.x
				var ncc := cc + d.y
				if is_block(nr, ncc) and _lot(nr, ncc) == lot:
					continue
				for k in 2:
					var a: Vector3
					var b: Vector3
					if d.x != 0:
						var z := z0 + (0.0 if d.x < 0 else 2.0)
						a = Vector3(x0 + float(k), 0, z)
						b = Vector3(x0 + float(k) + 1.0, 0, z)
					else:
						var x := x0 + (0.0 if d.y < 0 else 2.0)
						a = Vector3(x, 0, z0 + float(k))
						b = Vector3(x, 0, z0 + float(k) + 1.0)
					var at := Vector3(a.x, _roof(a.x, a.z, lot, h, rx), a.z)
					var bt := Vector3(b.x, _roof(b.x, b.z, lot, h, rx), b.z)
					_quad(st, a, b, bt, at, n, col)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	facade_mat = reg(_facade_material(V["lit"]))
	mi.material_override = facade_mat
	add_child(mi)

func _facade_material(lit: float) -> ShaderMaterial:
	var pa := PackedVector3Array([lin("#4B4A86"), lin("#B88A3C"), lin("#5A6FA8"), lin("#8E6B5A"), lin("#3F5F7A"), lin("#C2A06A")])
	var pb := PackedVector3Array([lin("#3C3B72"), lin("#9C7030"), lin("#45598E"), lin("#73554A"), lin("#2F4A62"), lin("#A3844E")])
	var pcc := PackedVector3Array([lin("#8A86C4"), lin("#E0B45A"), lin("#9FB6E0"), lin("#C79A7A"), lin("#7FA8C0"), lin("#E6C890")])
	var ra := PackedVector3Array([lin("#7A3F3A"), lin("#5A4E8E"), lin("#8E5A3A"), lin("#4A4A7A")])
	var rb := PackedVector3Array([lin("#6E4A3C"), lin("#4A3E76"), lin("#74482E"), lin("#3A3A66")])
	return smat(SH.FACADE, {"pal_a": pa, "pal_b": pb, "pal_c": pcc, "roof_a": ra, "roof_b": rb, "lit_ratio": lit,
		"win_a": lin("#F6C945"), "win_b": lin("#F3B33A"), "win_c": lin("#FFF1B0"),
		"shut_a": lin("#5E7FB0"), "shut_b": lin("#3E5A8A"), "glass": lin("#151A3C"), "door_col": lin("#3A2A20"), "roof_c": lin("#2A2A55")})

# Freie Box mit Fassaden-Material (fuer Wahrzeichen-Haeuser, Ferne, anderes Ufer)
func add_box(st: SurfaceTool, x0: float, x1: float, z0: float, z1: float, h: float, pal: int, seed: float) -> void:
	var col := Color(float(pal) / 8.0, seed, h / 20.0, 1.0)
	_quad(st, Vector3(x0, h, z0), Vector3(x1, h, z0), Vector3(x1, h, z1), Vector3(x0, h, z1), Vector3.UP, col)
	_quad(st, Vector3(x0, 0, z0), Vector3(x1, 0, z0), Vector3(x1, h, z0), Vector3(x0, h, z0), Vector3(0, 0, -1), col)
	_quad(st, Vector3(x0, 0, z1), Vector3(x1, 0, z1), Vector3(x1, h, z1), Vector3(x0, h, z1), Vector3(0, 0, 1), col)
	_quad(st, Vector3(x0, 0, z0), Vector3(x0, 0, z1), Vector3(x0, h, z1), Vector3(x0, h, z0), Vector3(-1, 0, 0), col)
	_quad(st, Vector3(x1, 0, z0), Vector3(x1, 0, z1), Vector3(x1, h, z1), Vector3(x1, h, z0), Vector3(1, 0, 0), col)

func commit_boxes(st: SurfaceTool, m: ShaderMaterial) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = m
	add_child(mi)

# ---------------------------------------------------------------- Formen-Helfer
func prism(pos: Vector3, w: float, h: float, depth: float, m: Material, rot_y := 0.0) -> MeshInstance3D:
	# dreieckiges Prisma (Giebel, Ziergiebel): Grundlinie auf pos.y, Spitze bei pos.y + h
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var d := depth / 2.0
	var l0 := Vector3(-w / 2, 0, d); var r0 := Vector3(w / 2, 0, d); var t0 := Vector3(0, h, d)
	var l1 := Vector3(-w / 2, 0, -d); var r1 := Vector3(w / 2, 0, -d); var t1 := Vector3(0, h, -d)
	_tri(st, l0, r0, t0, Vector3(0, 0, 1))
	_tri(st, l1, r1, t1, Vector3(0, 0, -1))
	var nl := Vector3(-h, w / 2, 0).normalized()
	var nr := Vector3(h, w / 2, 0).normalized()
	_tri(st, l0, t0, t1, nl)
	_tri(st, l0, t1, l1, nl)
	_tri(st, r0, t0, t1, nr)
	_tri(st, r0, t1, r1, nr)
	_tri(st, l0, r0, r1, Vector3.DOWN)
	_tri(st, l0, r1, l1, Vector3.DOWN)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = m
	mi.position = pos
	mi.rotation.y = rot_y
	add_child(mi)
	return mi

func crenels(center: Vector3, size_x: float, size_z: float, m: Material, step_ := 1.1) -> void:
	# Zinnenkranz auf einem rechteckigen Turm/Mauerstueck
	var nx := int(size_x / step_)
	var nz := int(size_z / step_)
	for i in nx:
		if i % 2 == 0:
			var x := center.x - size_x / 2 + (float(i) + 0.5) * size_x / nx
			Geo.box(self, Vector3(x, center.y + 0.4, center.z - size_z / 2 + 0.2), Vector3(size_x / nx, 0.8, 0.4), m)
			Geo.box(self, Vector3(x, center.y + 0.4, center.z + size_z / 2 - 0.2), Vector3(size_x / nx, 0.8, 0.4), m)
	for i in nz:
		if i % 2 == 0:
			var z := center.z - size_z / 2 + (float(i) + 0.5) * size_z / nz
			Geo.box(self, Vector3(center.x - size_x / 2 + 0.2, center.y + 0.4, z), Vector3(0.4, 0.8, size_z / nz), m)
			Geo.box(self, Vector3(center.x + size_x / 2 - 0.2, center.y + 0.4, z), Vector3(0.4, 0.8, size_z / nz), m)

func round_crenels(center: Vector3, r: float, m: Material) -> void:
	var n := int(TAU * r / 1.0)
	for i in n:
		if i % 2 == 0:
			var a := float(i) / float(n) * TAU
			Geo.box(self, center + Vector3(cos(a) * (r - 0.2), 0.4, sin(a) * (r - 0.2)), Vector3(0.4, 0.8, TAU * r / n), m, -a)

func arch_ring(center: Vector3, r: float, thick: float, depth: float, m: Material, n := 12) -> void:
	# Halbkreis-Bogen aus Steinen (Archivolte), in der x-y-Ebene, Blick nach -z/+z
	for i in n:
		var a := PI * (float(i) + 0.5) / float(n)
		var p := center + Vector3(cos(a) * r, sin(a) * r, 0)
		var mi := Geo.box(self, p, Vector3(thick, PI * r / n * 1.02, depth), m)
		mi.rotation.z = a

func column(base: Vector3, h: float, r: float, m: Material, cap_m: Material) -> void:
	Geo.cylinder(self, base + Vector3(0, h / 2, 0), r * 0.9, r, h, m, 12)
	Geo.box(self, base + Vector3(0, h + 0.25, 0), Vector3(r * 2.6, 0.5, r * 2.6), cap_m)
	Geo.box(self, base + Vector3(0, 0.15, 0), Vector3(r * 2.4, 0.3, r * 2.4), cap_m)

# ---------------------------------------------------------------- Wahrzeichen
func _landmarks() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Wahrzeichen-Stein leuchtet in der Nacht leicht von selbst (gemaltes Mondlicht): helle Masse vor dunklem Himmel
	var se := 0.10 if variant == "nacht" else 0.0
	var stone := M("#B9A27A", "#94826A", "#E2CFA0", {"len": 0.6, "wid": 0.09, "accent": 0.14, "emit": se})
	var stone_d := M("#8C7E6A", "#6E6458", "#B8A688", {"len": 0.6, "wid": 0.09, "accent": 0.12, "emit": se})
	var dark := M("#1E1A34", "#151228", "#2E2850", {"len": 0.4, "wid": 0.07, "accent": 0.08})
	_arena(stone, stone_d, dark)
	_cafe_forum(st, stone, dark)
	_republique(st, stone, stone_d, dark)
	_theatre(stone, stone_d, dark)
	_kai_landmarks(st, stone, stone_d, dark)
	_lamartine(st, stone, stone_d, dark)
	commit_boxes(st, facade_mat)

func _arena(stone: ShaderMaterial, stone_d: ShaderMaterial, dark: ShaderMaterial) -> void:
	var cx := 68.0
	var cz := 45.0
	var a := 13.6
	var b := 14.6
	var hgt := 13.0
	var outer := CylinderMesh.new()
	outer.top_radius = 1.0
	outer.bottom_radius = 1.0
	outer.height = hgt
	outer.radial_segments = 120
	outer.rings = 1
	outer.cap_top = false
	outer.cap_bottom = false
	var arc := reg(smat(SH.ARCADE, {"col_a": c("#C4AE84"), "col_b": c("#9E8A6C"), "col_c": c("#EAD8A8"),
		"ctr": Vector2(cx, cz), "nbay": 28.0, "perim": PI * (a + b), "rad": (a + b) / 2.0, "emit": 0.10 if variant == "nacht" else 0.0}))
	var mo := MeshInstance3D.new()
	mo.mesh = outer
	mo.material_override = arc
	mo.position = Vector3(cx, hgt / 2, cz)
	mo.scale = Vector3(a, 1, b)
	add_child(mo)
	# Innenschale (dunkles Gewoelbe hinter den Boegen), warmes Licht im Erdgeschoss
	var vault := M("#2E2A4A", "#3A3560", "#6A5A8A", {"len": 0.5, "wid": 0.08, "accent": 0.1, "emit": 0.05})
	var inner := CylinderMesh.new()
	inner.top_radius = 1.0
	inner.bottom_radius = 1.0
	inner.height = 8.4
	inner.radial_segments = 64
	inner.rings = 1
	var mi := MeshInstance3D.new()
	mi.mesh = inner
	mi.material_override = vault
	mi.position = Vector3(cx, 4.2, cz)
	mi.scale = Vector3(a - 2.4, 1, b - 2.4)
	add_child(mi)
	# Zuschauerraum (Cavea) als Trichter: von oben Sitzstufen konzentrisch, von aussen Gewoelbe
	var cav := CylinderMesh.new()
	cav.top_radius = 1.0
	cav.bottom_radius = 0.5
	cav.height = 11.0
	cav.radial_segments = 64
	cav.rings = 1
	cav.cap_top = false
	var cm := M("#9C8A70", "#7E6E5C", "#C8B48E", {"center_mode": 1, "center": Vector2(cx, cz), "len": 0.9, "wid": 0.35, "accent": 0.1,
		"back_dark": 1.0, "back_col": c("#2A2644")}, true)
	var mc := MeshInstance3D.new()
	mc.mesh = cav
	mc.material_override = cm
	mc.position = Vector3(cx, hgt - 5.5, cz)
	mc.scale = Vector3(a - 0.05, 1, b - 0.05)
	add_child(mc)
	# drei mittelalterliche Tuerme (West: Blickpunkt der Rue du Forum; Nord; Sued)
	for t in [[PI, 6.0], [-PI / 2, 5.5], [PI / 2, 5.5]]:
		var ang: float = t[0]
		var tp := Vector3(cx + cos(ang) * a, 0, cz + sin(ang) * b)
		var w: float = t[1]
		Geo.box(self, tp + Vector3(0, 10.5, 0), Vector3(w, 21.0, w), stone)
		crenels(tp + Vector3(0, 21.0, 0), w, w, stone)
		for k in 3:
			Geo.box(self, tp + Vector3(cos(ang) * (w / 2 + 0.02), 14.0 + k * 1.8, sin(ang) * (w / 2 + 0.02)), Vector3(0.25 if abs(cos(ang)) > 0.5 else 0.5, 1.0, 0.5 if abs(cos(ang)) > 0.5 else 0.25), dark)
	omni(Vector3(cx - a - 3.0, 4.5, cz - 3.0), "#FFB850", 1.6, 14.0)

func _cafe_forum(st: SurfaceTool, stone: ShaderMaterial, dark: ShaderMaterial) -> void:
	# Café an der Nordseite der Place du Forum: Blick frontal von Sueden ueber den Platz
	# (bewusst nicht der Bildausschnitt des Gemaeldes – der schaut von Nordosten schraeg nach Sueden).
	add_box(st, 22.0, 32.0, 20.0, 30.0, 10.5, 0, 0.71)
	var yel := M("#F2C14E", "#E8B03C", "#FFE48A", {"accent": 0.25, "len": 0.6, "wid": 0.1, "emit": 0.55, "angle": 0.1})
	Geo.box(self, Vector3(27, 1.7, 30.07), Vector3(10.0, 3.4, 0.14), yel)
	Geo.box(self, Vector3(22.07, 1.7, 28), Vector3(0.14, 3.4, 4.0), yel)
	for dx in [-3.0, 1.0]:
		Geo.box(self, Vector3(27 + dx, 1.25, 30.16), Vector3(1.4, 2.5, 0.06), M("#5A3A22", "#46301C", "#7A5432", {"len": 0.3, "wid": 0.05}))
	var awn := M("#F6C945", "#EFB83A", "#FFF1B0", {"accent": 0.2, "len": 1.4, "wid": 0.12, "emit": 0.35, "angle": 1.5708})
	var aw := Geo.box(self, Vector3(27, 3.3, 31.8), Vector3(10.4, 0.1, 3.6), awn)
	aw.rotation.x = 0.30
	Geo.box(self, Vector3(27, 2.65, 33.55), Vector3(10.4, 0.5, 0.06), awn)
	# grosse Laterne an der Ecke (echtes Licht 1/8)
	var glass := M("#FFE9A0", "#F6C945", "#FFFFFF", {"accent": 0.3, "len": 0.2, "wid": 0.05, "emit": 2.4})
	Geo.box(self, Vector3(31.4, 4.0, 30.6), Vector3(0.6, 0.9, 0.6), glass)
	halos.append([Vector3(31.4, 4.0, 30.6), 4.2, 3.3, 6.0, V["halo_e"] * 1.1, 0])
	lamps.append(Vector4(31.4, 4.0, 31.0, 2.2 * V["pool"]))
	omni(Vector3(29.5, 2.6, 32.5), "#FFC24A", 2.4, 11.0)
	# Terrasse: Tische und Stuehle (Platz-Nordrand), Gaeste sitzen
	var table := M("#E9D9A8", "#D6C48F", "#FFFFFF", {"len": 0.3, "wid": 0.05, "emit": 0.15})
	var chair := M("#6B4A2E", "#55391F", "#8B6A3A", {"len": 0.25, "wid": 0.05})
	var coat := M("#7A86C0", "#6A76B0", "#A8B4E0", {"len": 0.3, "wid": 0.06, "angle": 1.5708})
	var skin := M("#D9A066", "#C98A50", "#F0C080", {"len": 0.15, "wid": 0.05})
	var i := 0
	for tz in [31.6, 33.6]:
		for tx in [23.2, 25.6, 28.4, 30.8]:
			var x: float = tx + (0.5 if tz > 32.0 else 0.0)
			Geo.cylinder(self, Vector3(x, 0.72, tz), 0.42, 0.42, 0.06, table, 14)
			Geo.cylinder(self, Vector3(x, 0.36, tz), 0.04, 0.12, 0.7, chair, 8)
			for s in [-1.0, 1.0]:
				Geo.box(self, Vector3(x + 0.75 * s, 0.45, tz), Vector3(0.4, 0.06, 0.4), chair)
				Geo.box(self, Vector3(x + 0.95 * s, 0.7, tz), Vector3(0.05, 0.5, 0.4), chair)
			if i % 3 == 0:
				Geo.figure(self, Vector3(x + 0.75, 0.0, tz), coat, skin, -PI / 2, 1.3)
			i += 1
	# zwei roemische Saeulen in der Hausecke (NW-Ecke des Platzes)
	add_box(st, 14.0, 18.0, 22.0, 30.0, 9.5, 1, 0.33)
	for x in [15.0, 17.4]:
		column(Vector3(x, 0, 30.45), 6.6, 0.36, stone, stone)
	Geo.box(self, Vector3(16.2, 7.45, 30.45), Vector3(3.4, 0.6, 0.8), stone)
	prism(Vector3(16.2, 7.75, 30.45), 3.4, 1.0, 0.8, stone)
	# Statue (Denkmal von 1909, Bildhauer +1912 -> gemeinfrei) auf Sockel
	var bronze := M("#3A3A52", "#2A2A42", "#8A7A5A", {"len": 0.25, "wid": 0.05, "angle": 1.5708})
	Geo.box(self, Vector3(31, 0.2, 45), Vector3(2.2, 0.4, 2.2), stone)
	Geo.box(self, Vector3(31, 1.6, 45), Vector3(1.3, 2.4, 1.3), stone)
	Geo.figure(self, Vector3(31, 2.8, 45), bronze, bronze, PI, 2.2)
	omni(Vector3(29.0, 1.2, 47.5), "#FFC870", 1.0, 7.0)

func _republique(st: SurfaceTool, stone: ShaderMaterial, stone_d: ShaderMaterial, dark: ShaderMaterial) -> void:
	# Saint-Trophime: Fassade nach Norden (z = 76), romanisches Portal mit Archivolten, Fries,
	# Saeulen auf Loewen (angedeutet), Tympanon nur als Relief-Andeutung, Vierungsturm dahinter.
	var cx := 28.0
	Geo.box(self, Vector3(cx, 7.5, 80.5), Vector3(12.0, 15.0, 9.0), stone_d)
	prism(Vector3(cx, 15.0, 80.5), 12.4, 4.0, 9.0, stone_d)
	Geo.box(self, Vector3(cx, 0.6, 75.3), Vector3(8.4, 1.2, 1.4), stone)
	for k in 3:   # drei Stufen vor dem Podest
		var sh_ := 0.4 * (k + 1)
		Geo.box(self, Vector3(cx, sh_ / 2, 73.0 + k * 0.5), Vector3(5.8 - k * 0.6, sh_, 0.5), stone)
	for sx in [-1.0, 1.0]:
		Geo.box(self, Vector3(cx + sx * 3.15, 3.6, 75.35), Vector3(2.1, 4.8, 1.3), stone)
		for j in 3:
			var px: float = cx + sx * (2.05 + j * 0.55)
			Geo.sphere(self, Vector3(px, 1.45, 74.45), 0.26, dark, Vector3(1.0, 0.8, 1.4), 10)
			Geo.cylinder(self, Vector3(px, 3.3, 74.45), 0.13, 0.15, 3.4, stone, 8)
	Geo.box(self, Vector3(cx, 5.25, 74.7), Vector3(8.2, 0.75, 0.55), M("#D2BE94", "#B4A07A", "#F0E0B8", {"len": 0.25, "wid": 0.06, "accent": 0.2}))
	Geo.box(self, Vector3(cx, 3.0, 75.95), Vector3(2.6, 3.6, 0.1), dark)
	for s in [-0.66, 0.66]:
		Geo.box(self, Vector3(cx + s, 2.4, 75.86), Vector3(1.2, 2.4, 0.08), M("#5A3A22", "#46301C", "#7A5432", {"len": 0.3, "wid": 0.05, "angle": 1.5708}))
	var tym := Geo.quad(self, Vector3(cx, 6.35, 75.62), Vector2(2.8, 1.4), smat(SH.TYMPANON, {"stone": c("#C9B48A"), "shade": c("#4A4260")}), Vector3(0, PI, 0))
	tym.set_meta("nohull", true)
	for k in 3:
		arch_ring(Vector3(cx, 5.65, 75.3 - k * 0.25), 1.55 + k * 0.42, 0.36, 0.6, stone if k % 2 == 0 else stone_d, 14)
	prism(Vector3(cx, 8.0, 75.4), 8.6, 2.4, 1.2, stone, 0.0)
	omni(Vector3(cx, 4.8, 71.5), "#FFC870", 1.4, 9.0)
	# Vierungsturm hinter der Fassade
	Geo.box(self, Vector3(cx, 14.0, 89.0), Vector3(6.0, 28.0, 6.0), stone_d)
	for f in [[0.0, 3.02], [0.0, -3.02]]:
		for k in 2:
			Geo.box(self, Vector3(cx - 1.2 + k * 2.4, 24.5, 89.0 + f[1]), Vector3(0.9, 2.2, 0.08), dark)
	var pyr := Geo.cylinder(self, Vector3(cx, 29.5, 89.0), 0.0, 4.4, 3.0, M("#7A3F3A", "#6E4A3C", "#2A2A55", {"len": 0.5, "wid": 0.1}), 4)
	pyr.rotation.y = PI / 4
	# Obelisk mit Brunnenbecken
	var gran := M("#9A8A92", "#7A6A78", "#C8B0B0", {"len": 0.5, "wid": 0.07, "angle": 1.5708})
	var ob := Vector3(35.0, 0, 67.0)
	Geo.cylinder(self, ob + Vector3(0, 0.3, 0), 2.3, 2.4, 0.6, stone, 24)
	Geo.box(self, ob + Vector3(0, 1.7, 0), Vector3(1.6, 2.2, 1.6), stone)
	var sh := Geo.cylinder(self, ob + Vector3(0, 2.8 + 6.5, 0), 0.38, 0.64, 13.0, gran, 4)
	sh.rotation.y = PI / 4
	var py2 := Geo.cylinder(self, ob + Vector3(0, 16.3 + 0.5, 0), 0.0, 0.38, 1.0, gran, 4)
	py2.rotation.y = PI / 4
	# Hotel de Ville (Westseite, Blickpunkt der Calade-Achse) mit Uhrturm
	add_box(st, 4.0, 16.0, 63.6, 76.4, 12.0, 5, 0.52)
	for k in 7:
		Geo.box(self, Vector3(16.1, 6.0, 64.0 + k * 2.0), Vector3(0.2, 12.0, 0.35), stone)
	Geo.box(self, Vector3(16.15, 12.2, 70.0), Vector3(0.5, 0.6, 13.2), stone)
	Geo.box(self, Vector3(9.0, 12.0, 70.0), Vector3(5.0, 24.0, 5.0), stone)
	crenels(Vector3(9.0, 24.0, 70.0), 5.0, 5.0, stone)
	for k in 4:
		var a := float(k) * PI / 2 + PI / 4
		Geo.cylinder(self, Vector3(9.0 + cos(a) * 1.5, 25.6, 70.0 + sin(a) * 1.5), 0.15, 0.18, 2.4, stone, 8)
	Geo.sphere(self, Vector3(9.0, 27.0, 70.0), 1.9, M("#4A4A7A", "#3A3A66", "#8A86C4", {"len": 0.4, "wid": 0.08}), Vector3(1, 0.6, 1), 16)
	Geo.figure(self, Vector3(9.0, 28.1, 70.0), M("#3A3A52", "#2A2A42", "#8A7A5A", {"len": 0.25, "wid": 0.05}), M("#3A3A52", "#2A2A42", "#8A7A5A", {"len": 0.25, "wid": 0.05}), PI / 2, 1.6)
	var clock := Geo.cylinder(self, Vector3(11.56, 19.5, 70.0), 1.1, 1.1, 0.12, M("#FFE9A0", "#F6D27A", "#FFFFFF", {"emit": 1.2, "len": 0.2, "wid": 0.05, "center_mode": 1, "center": Vector2(11.56, 70.0)}), 24)
	clock.rotation.z = PI / 2
	Geo.box(self, Vector3(11.66, 19.85, 70.0), Vector3(0.05, 0.75, 0.1), dark)
	var hand := Geo.box(self, Vector3(11.66, 19.5, 70.35), Vector3(0.05, 0.1, 0.75), dark)
	hand.rotation.x = 0.4
	lamps.append(Vector4(12.5, 19.5, 70.0, 0.6))

func _theatre(stone: ShaderMaterial, stone_d: ShaderMaterial, dark: ShaderMaterial) -> void:
	# Theatre antique: die beiden stehenden Saeulen mit Gebaelkrest auf der Buehne, Sitzstufen
	# steigen nach Osten an, Tour de Roland an der Nordseite. Blickpunkt am Ostende der Calade.
	Geo.box(self, Vector3(71.0, 0.5, 71.0), Vector3(6.0, 1.0, 10.0), stone_d)
	for z in [69.2, 72.8]:
		column(Vector3(69.6, 1.0, z), 8.2, 0.42, stone, stone)
	Geo.box(self, Vector3(69.6, 9.95, 71.0), Vector3(1.1, 0.9, 4.6), stone)
	Geo.box(self, Vector3(69.6, 10.7, 71.6), Vector3(1.0, 0.6, 2.4), stone_d)
	var drum := Geo.cylinder(self, Vector3(72.5, 1.4, 68.0), 0.42, 0.42, 1.6, stone, 12)
	drum.rotation.x = PI / 2
	drum.rotation.y = 0.6
	Geo.cylinder(self, Vector3(73.0, 1.4, 74.0), 0.45, 0.45, 0.8, stone, 12)
	var seats := M("#A8967A", "#8C7C64", "#D0BE98", {"len": 0.8, "wid": 0.3, "angle": 1.5708, "accent": 0.1})
	for i in 7:   # Sitzstufen steigen hinter der Buehne nach Osten an
		var hh := 1.2 + i * 0.95
		Geo.box(self, Vector3(74.6 + i * 1.5, hh / 2, 71.0), Vector3(1.5, hh, 9.6 + i * 1.2), seats)
	Geo.box(self, Vector3(73.0, 9.0, 65.5), Vector3(4.2, 18.0, 4.2), stone_d)
	crenels(Vector3(73.0, 18.0, 65.5), 4.2, 4.2, stone_d)
	for k in 2:
		Geo.box(self, Vector3(70.86, 6.0 + k * 6.0, 65.5), Vector3(0.1, 2.4, 1.2), dark)

func _kai_landmarks(st: SurfaceTool, stone: ShaderMaterial, stone_d: ShaderMaterial, dark: ShaderMaterial) -> void:
	# Grand Prieure am Suedende des Kais: Zinnenfassade, Spitzbogenfenster, Eckturm
	Geo.box(self, Vector3(6.0, 6.0, 74.5), Vector3(9.0, 12.0, 9.0), stone_d)
	crenels(Vector3(6.0, 12.0, 74.5), 9.0, 9.0, stone_d, 0.9)
	for k in 3:
		Geo.box(self, Vector3(3.0 + k * 3.0, 6.0, 69.97), Vector3(0.9, 3.2, 0.1), M("#F6C945", "#E8B03C", "#FFF1B0", {"emit": 0.9, "len": 0.2, "wid": 0.05, "angle": 1.5708}) if k == 1 else dark)
		prism(Vector3(3.0 + k * 3.0, 7.6, 69.97), 0.9, 0.7, 0.1, dark)
	Geo.cylinder(self, Vector3(1.4, 7.0, 70.6), 1.3, 1.3, 14.0, stone_d, 16)
	round_crenels(Vector3(1.4, 14.0, 70.6), 1.3, stone_d)
	# Thermen-Apsis (Ziegel und Stein im Wechsel) am Ende der Seitengasse
	var band := M("#B9A27A", "#94826A", "#E2CFA0", {"band": 0.55, "band_col": c("#7A4A3A"), "len": 0.4, "wid": 0.08})
	Geo.cylinder(self, Vector3(35.8, 4.5, 20.0), 3.8, 3.8, 9.0, band, 24)
	Geo.sphere(self, Vector3(35.8, 9.0, 20.0), 3.8, band, Vector3(1, 0.55, 1), 20)
	for a in [PI, PI * 0.78, PI * 1.22]:
		var p := Vector3(35.8 + cos(a) * 3.82, 5.6, 20.0 + sin(a) * 3.82)
		Geo.box(self, p, Vector3(0.15, 2.6, 1.1), dark, -a)
	# anderes Ufer (Trinquetaille): niedrige Haeuser, Fenster ueber den Fassaden-Shader
	for z in range(-60, 150, 7):
		var h := rng.randf_range(5.0, 10.0)
		var x0 := -86.0 - rng.randf_range(0, 6)
		add_box(st, x0, -70.5, float(z), float(z) + rng.randf_range(5.0, 7.0), h, [0, 2, 3, 4][rng.randi() % 4], rng.randf())
	# Eisenbruecke (Typologie, 1888 gab es eine Eisen-Bogenbruecke nach Trinquetaille) im Norden
	var iron := M("#1A2140", "#141A34", "#3A4470", {"len": 0.6, "wid": 0.08})
	for x in [-14.0, -35.0, -56.0]:
		Geo.box(self, Vector3(x, 0.0, -46.0), Vector3(2.4, 5.0, 3.0), stone_d)
	Geo.box(self, Vector3(-35.0, 3.0, -46.0), Vector3(70.0, 0.4, 7.0), iron)
	for seg in 3:
		for i in 10:
			var a := PI * (float(i) + 0.5) / 10.0
			var x: float = -3.5 - seg * 21.0 - 10.5 + cos(a) * 10.5
			for zz in [-49.2, -42.8]:
				var bx := Geo.box(self, Vector3(x, 3.2 + sin(a) * 4.0, zz), Vector3(3.4, 0.35, 0.3), iron)
				bx.rotation.z = a - PI / 2
	for x in [-10.0, -24.0, -38.0, -52.0, -66.0]:
		halos.append([Vector3(x, 5.6, -42.6), 1.6, x, 5.0, V["halo_e"] * 0.9, 0])
		refl.append(Vector4(x, 5.6, -42.6, 0.7))
	# zwei Boote am Kai
	var hull := M("#3A2A2E", "#2A1E22", "#6A4A3A", {"len": 0.5, "wid": 0.08})
	for p in [Vector3(-3.0, -1.9, 33.0), Vector3(-4.2, -1.9, 52.0)]:
		Geo.sphere(self, p, 1.0, hull, Vector3(1.0, 0.35, 3.0), 12)
		Geo.cylinder(self, p + Vector3(0, 2.0, 0), 0.05, 0.06, 4.0, hull, 6)

func _lamartine(st: SurfaceTool, stone: ShaderMaterial, stone_d: ShaderMaterial, dark: ShaderMaterial) -> void:
	# Gelbes Haus (1944 zerstoert, rekonstruiert nach gemeinfreien Fotos/Beschreibungen): zwei
	# Geschosse, Ocker-Gelb, Laeden und Tuer gruen -> der einzige gruene Ort = AUSGANG.
	var moving := 0.0 if reduce_fx else 1.0
	var yh := M("#E2B34C", "#C99A3A", "#F6D27A", {"accent": 0.18, "len": 0.6, "wid": 0.1, "angle": 0.05, "emit": 0.12})
	Geo.box(self, Vector3(15.0, 4.0, -2.0), Vector3(6.0, 8.0, 8.0), yh)
	var rf := M("#8E4A3A", "#74402E", "#2A2A55", {"len": 0.5, "wid": 0.12})
	var roof := Geo.cylinder(self, Vector3(15.0, 8.7, -2.0), 2.4, 4.6, 1.4, rf, 4)
	roof.rotation.y = PI / 4
	roof.scale = Vector3(0.95, 1, 1.15)
	add_box(st, 10.0, 12.0, -6.0, 2.0, 9.0, 3, 0.18)
	add_box(st, 18.0, 22.0, -6.0, 2.0, 10.0, 3, 0.81)
	var door := Geo.quad(self, Vector3(15.0, 1.4, 2.04), Vector2(1.7, 2.8), smat(SH.EXIT, {"col": c("#3AF5C8"), "moving": moving, "energy": 1.8}))
	door.set_meta("nohull", true)
	Geo.box(self, Vector3(15.0, 2.95, 2.06), Vector3(2.1, 0.2, 0.1), dark)
	var shut := smat(SH.EXIT, {"col": c("#3AF5C8"), "moving": moving, "energy": 0.85, "panels": 0.0})
	var win := M("#F6C945", "#F3B33A", "#FFF1B0", {"emit": 1.3, "len": 0.22, "wid": 0.06, "angle": 1.5708, "accent": 0.3})
	for x in [12.9, 15.0, 17.1]:
		Geo.box(self, Vector3(x, 5.6, 2.03), Vector3(0.75, 1.5, 0.06), win)
		for s in [-1.0, 1.0]:
			var q := Geo.quad(self, Vector3(x + s * 0.62, 5.6, 2.06), Vector2(0.42, 1.5), shut)
			q.set_meta("nohull", true)
	for x in [12.9, 17.1]:
		Geo.box(self, Vector3(x, 1.3, 2.03), Vector3(1.1, 2.4, 0.06), M("#3A2A20", "#2A1E16", "#5A4030", {"len": 0.3, "wid": 0.05, "angle": 1.5708}))
	omni(Vector3(15.0, 1.6, 4.6), "#3AF5C8", 2.2, 8.0)
	# gruener Stern ueber dem Haus: von ueberall ueber die Daecher sichtbar (Puls 0,5 Hz)
	halos.append([Vector3(15.0, 18.0, -1.0), 7.0, 2.2, 6.0, 1.5, 3])
	# Porte de la Cavalerie: zwei Rundtuerme mit Zinnen, Mauerstuecke, Bogen ueber dem Durchgang
	for z in [4.4, 13.6]:
		Geo.cylinder(self, Vector3(38.6, 7.5, z), 2.6, 2.7, 15.0, stone_d, 20)
		round_crenels(Vector3(38.6, 15.0, z), 2.6, stone_d)
		Geo.box(self, Vector3(36.0, 9.0, z), Vector3(0.12, 1.4, 0.5), dark)
	Geo.box(self, Vector3(43.5, 4.5, 4.0), Vector3(9.0, 9.0, 4.0), stone)
	Geo.box(self, Vector3(43.5, 4.5, 14.0), Vector3(9.0, 9.0, 4.0), stone)
	Geo.box(self, Vector3(39.5, 10.6, 9.0), Vector3(2.0, 2.0, 7.0), stone_d)
	# Mauerturm am Nordende der Rue de la Cavalerie
	Geo.box(self, Vector3(51.0, 7.0, 0.0), Vector3(6.0, 14.0, 4.0), stone_d)
	crenels(Vector3(51.0, 14.0, 0.0), 6.0, 4.0, stone_d)

# ---------------------------------------------------------------- Baeume
func _trees() -> void:
	var trunk := M("#B8B090", "#7A7A6A", "#D8D0B0", {"len": 0.35, "wid": 0.07, "angle": 1.5708})
	var crown := M("#34557A", "#2A4868", "#8AAAC8", {"len": 0.45, "wid": 0.08, "accent": 0.2, "bump": 0.9, "center_mode": 2, "center": Vector2(27.0, 40.0)})
	for p in [Vector3(19.5, 0, 35.0), Vector3(19.5, 0, 48.5), Vector3(35.5, 0, 48.5), Vector3(35.5, 0, 36.5),
			Vector3(20.0, 0, 13.0), Vector3(30.0, 0, 13.0), Vector3(9.0, 0, 13.0)]:
		Geo.cylinder(self, p + Vector3(0, 3.2, 0), 0.2, 0.3, 6.4, trunk, 8)
		Geo.cylinder(self, p + Vector3(0.5, 5.4, 0.2), 0.08, 0.16, 2.4, trunk, 6)
		for k in 9:
			var o := Vector3(rng.randf_range(-2.2, 2.2), rng.randf_range(6.4, 9.2), rng.randf_range(-2.2, 2.2))
			Geo.sphere(self, p + o, rng.randf_range(0.9, 1.4), crown, Vector3(1.0, 0.75, 1.0), 10)
	# Zypressen im Garten der Place Lamartine (fast schwarz – Gruen bleibt dem Ausgang)
	var cyp := M("#102520", "#1E3F30", "#2E5A3E", {"accent": 0.1, "angle": 1.35, "len": 0.9, "wid": 0.12, "bump": 0.9, "rough": 0.7})
	for cz in [[25.0, 12.6, 9.5], [33.5, 12.4, 11.5]]:
		_cypress(Vector3(cz[0], 0, cz[1]), cz[2], cyp)

func _cypress(pos: Vector3, h: float, m: ShaderMaterial) -> void:
	var y := 1.0
	var r := h * 0.16
	while y < h:
		var rr := r * (1.0 - pow(y / h, 1.6)) + 0.25
		var seg := Geo.sphere(self, pos + Vector3(rng.randf_range(-0.2, 0.2), y + rr * 0.6, rng.randf_range(-0.2, 0.2)), rr, m, Vector3(1.0, 1.9, 1.0), 14)
		seg.rotation.y = rng.randf() * TAU
		y += rr * 1.5

# ---------------------------------------------------------------- Leben
func _life() -> void:
	# Passanten HELLER als Boden und Fassaden (Auflage der Pruefung)
	var coats := [M("#7A86C0", "#6A76B0", "#A8B4E0", {"len": 0.3, "wid": 0.06, "angle": 1.5708}),
		M("#B08A62", "#9A7450", "#D8B488", {"len": 0.3, "wid": 0.06, "angle": 1.5708}),
		M("#9A8AC8", "#8474B4", "#C4B8E8", {"len": 0.3, "wid": 0.06, "angle": 1.5708})]
	var skin := M("#D9A066", "#C98A50", "#F0C080", {"len": 0.15, "wid": 0.05})
	var figs := [[Vector3(5.5, 0, 26.0), 0.3], [Vector3(8.6, 0, 44.0), 2.8], [Vector3(6.0, 0, 60.0), 0.0], [Vector3(21.0, 0, 43.5), 1.2],
		[Vector3(33.5, 0, 50.5), -2.0], [Vector3(25.0, 0, 58.0), 3.0], [Vector3(22.0, 0, 70.0), 0.8], [Vector3(38.0, 0, 73.0), -1.4],
		[Vector3(44.0, 0, 69.5), 1.6], [Vector3(12.5, 0, 12.0), 2.6], [Vector3(30.0, 0, 6.5), -0.6], [Vector3(52.0, 0, 30.0), 0.2],
		[Vector3(50.0, 0, 40.5), 1.9], [Vector3(84.5, 0, 46.0), 3.1]]
	var i := 0
	for f in figs:
		Geo.figure(self, f[0], coats[i % 3], skin, f[1])
		i += 1
	# Pferdekarren auf der Place de la Republique
	var wood := M("#8B6A4A", "#6B4A2E", "#AB8A5A", {"len": 0.5, "wid": 0.08})
	var n := Node3D.new()
	n.position = Vector3(23.0, 0, 73.5)
	n.rotation.y = 1.4
	add_child(n)
	Geo.box(n, Vector3(0, 0.95, 0), Vector3(1.5, 0.7, 2.6), wood)
	for sx in [-0.85, 0.85]:
		var w := Geo.cylinder(n, Vector3(sx, 0.6, 0.6), 0.6, 0.6, 0.12, wood, 14)
		w.rotation.z = PI / 2
	var horse := M("#6A5A50", "#54463E", "#8A7462", {"len": 0.4, "wid": 0.08})
	Geo.sphere(n, Vector3(0, 1.25, -2.6), 0.45, horse, Vector3(1.0, 1.0, 2.0), 14)
	Geo.sphere(n, Vector3(0, 1.9, -3.7), 0.22, horse, Vector3(1.0, 1.4, 1.0), 10)
	for lx in [-0.25, 0.25]:
		for lz in [-2.0, -3.3]:
			Geo.cylinder(n, Vector3(lx, 0.45, lz), 0.06, 0.08, 0.9, horse, 6)

# ---------------------------------------------------------------- Ferne
func _far() -> void:
	# Stadt ringsum (ausserhalb der Karte), Bahnviadukt im Norden, Montmajour auf dem Huegel im NO,
	# Alpilles als Kamm im Osten, Zypressengruppen. Strich-LOD macht das alles zur Mittelfarbe.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 40:
		var x := rng.randf_range(92.0, 170.0)
		var z := rng.randf_range(-40.0, 130.0)
		add_box(st, x, x + rng.randf_range(6, 10), z, z + rng.randf_range(6, 10), rng.randf_range(7, 12), rng.randi() % 6, rng.randf())
	for k in 36:
		var x := rng.randf_range(0.0, 95.0)
		var z := rng.randf_range(84.0, 140.0)
		if x > 18.0 and x < 38.0 and z < 95.0:
			continue
		add_box(st, x, x + rng.randf_range(6, 10), z, z + rng.randf_range(6, 10), rng.randf_range(7, 12), rng.randi() % 6, rng.randf())
	for k in 30:
		var x := rng.randf_range(4.0, 95.0)
		var z := rng.randf_range(-45.0, -8.0)
		add_box(st, x, x + rng.randf_range(6, 10), z, z + rng.randf_range(6, 10), rng.randf_range(7, 12), rng.randi() % 6, rng.randf())
	far_mat = reg(_facade_material(V["lit"] * 0.6))
	commit_boxes(st, far_mat)
	var darkf := M("#1E2650", "#161C40", "#2C3570", {"accent": 0.05, "len": 1.2})
	# Bahnviadukt (zwei Bahnbruecken lagen nahe der Place Lamartine)
	for i in 16:
		Geo.box(self, Vector3(-10.0 + i * 9.0, 4.5, -75.0), Vector3(2.0, 9.0, 4.0), darkf)
	Geo.box(self, Vector3(57.0, 9.6, -75.0), Vector3(150.0, 1.2, 4.0), darkf)
	# Montmajour auf dem Huegel im Nordosten
	Geo.sphere(self, Vector3(260, -8, -330), 90.0, darkf, Vector3(1.8, 0.28, 1.0), 24)
	Geo.box(self, Vector3(255, 34, -320), Vector3(14, 26, 14), darkf)
	Geo.box(self, Vector3(280, 26, -322), Vector3(30, 12, 12), darkf)
	# Alpilles
	for k in 7:
		Geo.sphere(self, Vector3(500 + k * 15, -6, -200 + k * 70), 110.0, darkf, Vector3(0.6, 0.3, 1.4), 20)
	var cyp := M("#102520", "#1E3F30", "#2E5A3E", {"accent": 0.1, "angle": 1.35, "len": 0.9, "wid": 0.12})
	for p in [Vector3(120, 0, -30), Vector3(126, 0, -26), Vector3(-92, 0, 20), Vector3(-95, 0, 26), Vector3(140, 0, 110)]:
		_cypress(p, 12.0, cyp)

# ---------------------------------------------------------------- Halos, Kugeln
func _halos() -> void:
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = q
	mm.instance_count = halos.size()
	for i in halos.size():
		var hh: Array = halos[i]
		var s: float = hh[1]
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3(s, s, 1)), hh[0]))
		mm.set_instance_custom_data(i, Color(hh[2], hh[3], hh[4], float(hh[5])))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = smat(SH.HALO, {"moving": 0.0 if reduce_fx else 1.0, "rim": c("#D4A03A"), "core": c("#FFF3B0"),
		"g_core": c("#E0FFF6"), "g_mid": c("#3AF5C8"), "g_rim": c("#0E7A66")})
	mmi.set_meta("nohull", true)
	add_child(mmi)

func _pellets() -> void:
	var sp: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://spur.json"))
	var pts := []
	for t in sp["trail"]:
		pts.append(Vector3(wx(float(t[1])), 0.55, wz(float(t[0]))))
	Geo.pellets(self, pts, 0.26, smat(SH.ORB, {"col": c("#FF4A1C"), "core": c("#FFB088"), "outline": c("#3A0E06"), "energy": 1.5}))

# ---------------------------------------------------------------- Ansichten
func views() -> Array:
	var dv := OS.get_environment("VIEW")   # freie Kamera zum Pruefen: "name,x,y,z,lx,ly,lz,fov"
	if dv != "":
		var f := dv.split(",")
		return [[f[0], Vector3(float(f[1]), float(f[2]), float(f[3])), Vector3(float(f[4]), float(f[5]), float(f[6])), float(f[7])]]
	return [
		["strasse", Vector3(27.0, 1.7, 63.0), Vector3(27.0, 3.6, 28.0), 72.0],
		["totale", Vector3(-46.0, 30.0, 46.0), Vector3(50.0, 9.0, 40.0), 64.0],
		["forum", Vector3(19.0, 1.7, 47.0), Vector3(28.5, 3.6, 30.0), 72.0],
		["arenes", Vector3(49.5, 1.7, 26.5), Vector3(64.0, 7.5, 39.0), 74.0],
		["trophime", Vector3(22.5, 1.7, 65.0), Vector3(29.0, 6.5, 76.0), 74.0],
		["theatre", Vector3(62.5, 1.7, 70.6), Vector3(71.0, 6.8, 71.0), 74.0],
		["kai", Vector3(3.2, 1.7, 56.0), Vector3(-10.0, 0.6, 24.0), 72.0],
		["ausgang", Vector3(15.5, 1.7, 15.0), Vector3(15.0, 6.5, 0.0), 72.0],
		["capsule", Vector3(24.5, 1.2, 44.0), Vector3(27.5, 7.5, 30.0), 74.0],
	]

func set_view(pos: Vector3, look: Vector3, fov: float) -> void:
	cam.position = pos
	cam.look_at(look)
	cam.fov = fov
