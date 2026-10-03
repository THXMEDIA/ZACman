extends RefCounted
## TokyoScenery — builds the static scenery of the Tokyo line city on top of
## MazeView's black wall MultiMesh (CityTheme.scenery_builder_script, see
## city_themes.gd tokyo()). Everything is merged per material so the whole
## static city stays at a fixed, small number of draw calls
## (tests/test_tokyo.gd checks the budget):
##   Neon_amber / Neon_weiss / Neon_magenta / Neon_mast   line meshes (NeonLines)
##   Masse         black mass that is not a grid wall (towers, footbridge, skyline)
##   Fahrbahnfarbe zebras, scramble diagonals, center dashes
##   Ladenfronten  shop-front glow under the base line
##   Screen_*      the two video screens (magenta accent)
##   Schild_*      sign lettering (bundled CJK subset font)
## plus a few sodium lamp lights. Building geometry and collision come from
## the grid (tokyo_maze.gd); the base line is drawn exactly on the boundary
## between wall and open cells, i.e. on the collision edge.
##
## All decoration that varies (floor bands, mullions, skyline) comes from the
## level seed (`seed`), never from a fixed seed or the global generator.

const NeonLinesScript := preload("res://scripts/neon_lines.gd")
const TokyoMazeScript := preload("res://scripts/tokyo_maze.gd")
const Style := preload("res://scripts/tokyo_style.gd")
const MASS_SHADER := preload("res://shaders/tokyo_mass.gdshader")
const PAINT_SHADER := preload("res://shaders/tokyo_paint.gdshader")
const SHOP_SHADER := preload("res://shaders/tokyo_shopfront.gdshader")
const SCREEN_SHADER := preload("res://shaders/tokyo_screen.gdshader")
const FONT_PATH := "res://fonts/NotoSansCJKjp-Bold-Subset.otf"

const CELL := 2.0

## Street lamps mounted on facades (no free-standing poles: nothing in the
## street the player could walk through without it showing as collision).
## [x, z, outward direction x, outward direction z]
const LAMPS := [
	[39.0, 16.0, 1.0, 0.0], [53.0, 30.0, -1.0, 0.0],
	[53.0, 62.0, -1.0, 0.0],
	[14.0, 39.0, 0.0, 1.0], [28.0, 53.0, 0.0, -1.0],
	[66.0, 39.0, 0.0, 1.0],
	[15.0, 26.0, 1.0, 0.0], # north-west alley
	[12.0, 67.0, 0.0, 1.0], # south-west alley
]
const LAMP_Y := 4.6
const LAMP_LIGHT_RANGE := 9.0
const LAMP_LIGHT_ENERGY := 2.4


static func load_sign_font() -> Font:
	var f = load(FONT_PATH) if ResourceLoader.exists(FONT_PATH) else null
	if f is Font:
		return f
	# Fallback for a checkout that was never imported (raw .otf).
	var ff := FontFile.new()
	if ff.load_dynamic_font(FONT_PATH) == OK:
		return ff
	return null


## Cell rect (inclusive) -> world bounds {x0, x1, z0, z1}.
static func rect_world(b: Dictionary) -> Dictionary:
	return {"x0": b.c0 * CELL - CELL * 0.5, "x1": b.c1 * CELL + CELL * 0.5, "z0": b.r0 * CELL - CELL * 0.5, "z1": b.r1 * CELL + CELL * 0.5}


## Every straight piece of the wall/open boundary of the grid, merged:
## [{a: Vector3, b: Vector3, n: Vector3 (outward, into the street)}] at y 0.
## This boundary IS the collision edge (wall cells are full CELL boxes).
static func facade_runs(maze) -> Array:
	var runs := []
	# Boundaries between row r and r+1 (lines of constant z).
	for r in range(-1, maze.rows):
		var z := r * CELL + CELL * 0.5
		var cur_dir := 0
		var start_c := 0
		for c in range(0, maze.cols + 1):
			var d := 0
			if c < maze.cols:
				var up := _wall(maze, r, c)
				var down := _wall(maze, r + 1, c)
				if up and not down:
					d = 1 # facade faces +z (south)
				elif down and not up:
					d = -1 # facade faces -z (north)
			if d != cur_dir:
				if cur_dir != 0:
					runs.append({"a": Vector3(start_c * CELL - CELL * 0.5, 0, z), "b": Vector3(c * CELL - CELL * 0.5, 0, z), "n": Vector3(0, 0, cur_dir)})
				cur_dir = d
				start_c = c
	# Boundaries between col c and c+1 (lines of constant x).
	for c in range(-1, maze.cols):
		var x := c * CELL + CELL * 0.5
		var cur_dir2 := 0
		var start_r := 0
		for r in range(0, maze.rows + 1):
			var d2 := 0
			if r < maze.rows:
				var left := _wall(maze, r, c)
				var right := _wall(maze, r, c + 1)
				if left and not right:
					d2 = 1
				elif right and not left:
					d2 = -1
			if d2 != cur_dir2:
				if cur_dir2 != 0:
					runs.append({"a": Vector3(x, 0, start_r * CELL - CELL * 0.5), "b": Vector3(x, 0, r * CELL - CELL * 0.5), "n": Vector3(cur_dir2, 0, 0)})
				cur_dir2 = d2
				start_r = r
	return runs


## Outside the grid counts as open only where it matters: never (the Tokyo
## border is all buildings), so out-of-range cells are "not wall" and the
## outermost walls get no facade facing the void.
static func _wall(maze, r: int, c: int) -> bool:
	if r < 0 or r >= maze.rows or c < 0 or c >= maze.cols:
		return true
	return maze.grid[r][c] == 1


static func build(maze, _city_theme, seed: int) -> Node3D:
	var root := Node3D.new()
	root.name = "TokyoScenery"
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var lines = NeonLinesScript.new()
	lines.define("amber", Style.AMBER, Style.AMBER_ENERGY)
	lines.define("weiss", Style.WHITE, Style.WHITE_ENERGY)
	lines.define("magenta", Style.MAGENTA, Style.MAGENTA_ENERGY)
	lines.define("mast", Style.POLE, Style.POLE_ENERGY)
	var mass = NeonLinesScript.TriBatch.new()
	var paint = NeonLinesScript.TriBatch.new()
	var shop = NeonLinesScript.TriBatch.new()
	var font := load_sign_font()

	# ---- buildings: corner edges, top outline, floor bands, mullions ----
	for b in TokyoMazeScript.BUILDINGS:
		var w := rect_world(b)
		var key: String = b.col
		var opts := {}
		if b.get("kind", "") == "station":
			opts = {"band_prob": 0.0, "mullion_prob": 0.0, "bands_at": [4.4, 6.9]}
		elif b.get("kind", "") == "edge":
			opts = {"mullion_prob": 0.0}
		_block_outline(lines, rng, w.x0, w.x1, w.z0, w.z1, 0.0, b.h, key, opts)

	# ---- base line (Sockellinie) and shop fronts along every facade ----
	var runs := facade_runs(maze)
	var half := Style.BASE_LINE_THICK * 0.5
	var base_lines := [] # what was drawn, for the collision test
	for run in runs:
		var n: Vector3 = run.n
		var a: Vector3 = run.a
		var bb: Vector3 = run.b
		var along := (bb - a).normalized()
		# The tube's inner side lies exactly on the facade = the collision edge.
		var off := n * half + Vector3(0, Style.BASE_LINE_Y, 0)
		lines.line(a + off - along * half, bb + off + along * half, "amber", Style.BASE_LINE_THICK, Style.BASE_LINE_MUL)
		base_lines.append({"a": a + off, "b": bb + off, "n": n, "thick": Style.BASE_LINE_THICK})
		var length := a.distance_to(bb)
		var o := n * 0.02
		shop.quad(a + o, bb + o, bb + o + Vector3(0, Style.SHOP_H, 0), a + o + Vector3(0, Style.SHOP_H, 0),
			Vector2(0, 0), Vector2(length, 0), Vector2(length, 1), Vector2(0, 1))

	# ---- landmarks (placeholders, no real buildings) ----
	_octagon_tower(lines, mass, rng)
	_north_tower(lines, mass, rng, root, font)
	_skydeck_tower(lines, mass, rng)
	_footbridge(lines, mass)
	_station_front(lines)

	# ---- street: curbs, road paint, lamps ----
	_curbs(lines)
	_road_paint(paint)
	_lamps(lines, root)

	# ---- signs (generic words, no brands) ----
	_vsign(lines, root, font, Vector3(15.0, 2.8, 22.0), PI / 2.0, "居酒屋", 3.6)
	_vsign(lines, root, font, Vector3(15.0, 2.9, 31.0), PI / 2.0, "本屋", 2.4)
	_vsign(lines, root, font, Vector3(30.0, 2.8, 53.0), PI, "ラーメン", 4.4)
	_vsign(lines, root, font, Vector3(77.0, 2.9, 64.0), -PI / 2.0, "薬", 1.4)
	_vsign(lines, root, font, Vector3(16.0, 2.8, 73.0), PI, "喫茶", 2.4)
	_screen(root, Vector3(52.94, 8.0, 64.0), Vector2(4.0, 6.0), -PI / 2.0, 2.7, 0.6, Style.AMBER, "")

	# ---- skyline beyond the map: depth through light density ----
	_skyline(lines, mass, rng, maze)

	# ---- assemble ----
	lines.build(root, Style.FADE_H, Style.TOP_MUL)
	var mass_mat := ShaderMaterial.new()
	mass_mat.shader = MASS_SHADER
	mass_mat.set_shader_parameter("mass_color", Style.MASS)
	root.add_child(mass.to_instance("Masse", mass_mat))
	var paint_mat := ShaderMaterial.new()
	paint_mat.shader = PAINT_SHADER
	paint_mat.set_shader_parameter("paint_color", Style.PAINT)
	root.add_child(paint.to_instance("Fahrbahnfarbe", paint_mat))
	var shop_mat := ShaderMaterial.new()
	shop_mat.shader = SHOP_SHADER
	shop_mat.set_shader_parameter("glow_color", Style.SHOP)
	shop_mat.set_shader_parameter("energy", 0.24)
	root.add_child(shop.to_instance("Ladenfronten", shop_mat))

	root.set_meta("line_segments", lines.segment_count())
	root.set_meta("line_signature", lines.signature())
	root.set_meta("decor_signature", hash([lines.signature(), mass.signature(), paint.signature(), shop.signature()]))
	root.set_meta("facade_runs", runs)
	root.set_meta("base_lines", base_lines)
	return root


## Neon contour of a box building: corner edges, top outline, floor bands
## (probability per band from the level seed) and some mullions.
static func _block_outline(lines, rng: RandomNumberGenerator, x0: float, x1: float, z0: float, z1: float, y0: float, h: float, key: String, opts: Dictionary = {}) -> void:
	var o := Style.EDGE_THICK * 0.5
	var c := [Vector3(x0 - o, 0, z0 - o), Vector3(x1 + o, 0, z0 - o), Vector3(x1 + o, 0, z1 + o), Vector3(x0 - o, 0, z1 + o)]
	var mul: float = opts.get("mul", Style.EDGE_MUL)
	var thick: float = opts.get("thick", Style.EDGE_THICK)
	for i in 4:
		var a: Vector3 = c[i]
		var b: Vector3 = c[(i + 1) % 4]
		lines.line(a + Vector3(0, y0, 0), a + Vector3(0, h, 0), key, thick, mul)
		lines.line(a + Vector3(0, h, 0), b + Vector3(0, h, 0), key, thick, mul)
	var band_prob: float = opts.get("band_prob", 0.5)
	var step: float = opts.get("floor_step", Style.FLOOR_STEP)
	var y := maxf(y0 + step, Style.FIRST_BAND_Y)
	var bands: Array = opts.get("bands_at", [])
	while band_prob > 0.0 and y < h - 1.2:
		if rng.randf() < band_prob:
			bands.append(y)
		y += step
	for by in bands:
		for i in 4:
			lines.line(c[i] + Vector3(0, by, 0), c[(i + 1) % 4] + Vector3(0, by, 0), key, Style.BAND_THICK, mul * Style.BAND_MUL)
	var mullion_prob: float = opts.get("mullion_prob", 0.12)
	if mullion_prob <= 0.0:
		return
	for i in 4:
		var a2: Vector3 = c[i]
		var b2: Vector3 = c[(i + 1) % 4]
		var n := int(a2.distance_to(b2) / 3.0)
		for k in range(1, n):
			if rng.randf() < mullion_prob:
				var p := a2.lerp(b2, float(k) / n)
				lines.line(p + Vector3(0, maxf(y0, Style.BASE_LINE_Y + 0.6), 0), p + Vector3(0, h * rng.randf_range(0.45, 1.0), 0), key, Style.BAND_THICK, mul * Style.MULLION_MUL)


## The "round tower", deliberately estranged so it cannot be read as a real
## building: an octagon (not a cylinder) on its podium, a slanted crown, two
## slanted magenta rings as the accent, no sign pillar, no lettering.
static func _octagon_tower(lines, mass, rng: RandomNumberGenerator) -> void:
	var cx := 32.5
	var cz := 30.0
	var r := 5.0
	var y0 := 5.0
	var poly := []
	var tops := []
	for i in 8:
		var a := TAU * (i + 0.5) / 8.0
		var p := Vector3(cx + cos(a) * r, 0, cz + sin(a) * r)
		poly.append(p)
		tops.append(27.0 + (p.x - cx) * 0.38)
	mass.prism(poly, y0, tops)
	var top_pts := []
	for i in 8:
		var p: Vector3 = poly[i]
		lines.line(Vector3(p.x, y0, p.z), Vector3(p.x, tops[i], p.z), "amber", Style.EDGE_THICK)
		top_pts.append(Vector3(p.x, tops[i], p.z))
	lines.polyline(top_pts, "amber", Style.EDGE_THICK, 1.0, true)
	var y := y0 + 3.0
	while y < 21.0:
		if rng.randf() < 0.6:
			var ring := []
			for p in poly:
				ring.append(Vector3(p.x, y, p.z))
			lines.polyline(ring, "amber", Style.BAND_THICK, Style.BAND_MUL, true)
		y += Style.FLOOR_STEP
	# accent: two rings parallel to the slanted crown, a little outside
	for k in 2:
		var ring2 := []
		for i in 8:
			var p2: Vector3 = poly[i]
			var dir := (p2 - Vector3(cx, 0, cz)).normalized()
			ring2.append(Vector3(p2.x, tops[i] - 4.2 - k * 0.5, p2.z) + dir * 0.12)
		lines.polyline(ring2, "magenta", 0.1, 1.0, true)


## North tower: a setback tower on the north-east block and the big vertical
## screen facing the crossing (the strongest light source of the scene).
static func _north_tower(lines, mass, rng: RandomNumberGenerator, root: Node3D, font: Font) -> void:
	var x0 := 56.0
	var x1 := 69.0
	var z0 := 14.0
	var z1 := 33.0
	mass.box(x0, x1, 20.0, 42.0, z0, z1)
	_block_outline(lines, rng, x0, x1, z0, z1, 20.0, 42.0, "amber", {"band_prob": 0.55})
	# The big screen hangs diagonally across the tower's south-west corner,
	# 1.2 m in front of it and 7 m above the street (above the base line,
	# so it changes nothing at the collision edge), facing the crossing.
	var n := Vector3(-1, 0, 1).normalized()
	var center := Vector3(53.0, 13.0, 39.0) + n * 1.2
	var rot := atan2(n.x, n.z)
	_screen(root, center, Vector2(7.0, 11.0), rot, 1.3, 1.0, Style.AMBER, "カ\nラ\nオ\nケ", font)
	var tangent := Vector3(n.z, 0, -n.x)
	var back := center - n * 0.05
	var fr := [back + tangent * 3.6 + Vector3(0, -5.6, 0), back - tangent * 3.6 + Vector3(0, -5.6, 0), back - tangent * 3.6 + Vector3(0, 5.6, 0), back + tangent * 3.6 + Vector3(0, 5.6, 0)]
	# black backing, both windings: the screen's back is seen from the north avenue
	mass.quad(fr[0], fr[1], fr[2], fr[3])
	mass.quad(fr[3], fr[2], fr[1], fr[0])
	lines.polyline(fr, "amber", Style.EDGE_THICK, 0.8, true)


## Sky-deck tower: the tall landmark behind the station (deck ring near the
## top, sparse bands), fading towards the sky.
static func _skydeck_tower(lines, mass, rng: RandomNumberGenerator) -> void:
	var x0 := 80.0
	var x1 := 90.0
	var z0 := 14.0
	var z1 := 28.0
	mass.box(x0, x1, 26.0, 96.0, z0, z1)
	_block_outline(lines, rng, x0, x1, z0, z1, 26.0, 96.0, "weiss", {"band_prob": 0.7, "floor_step": 6.0, "thick": 0.12, "mullion_prob": 0.0})
	var deck := [Vector3(x0 - 1.2, 90.0, z0 - 1.2), Vector3(x1 + 1.2, 90.0, z0 - 1.2), Vector3(x1 + 1.2, 90.0, z1 + 1.2), Vector3(x0 - 1.2, 90.0, z1 + 1.2)]
	lines.polyline(deck, "weiss", 0.12, 1.0, true)


## Raised footbridge across the northern avenue (no collision: it is above
## the street, the player walks under it).
static func _footbridge(lines, mass) -> void:
	var x0 := 39.0
	var x1 := 53.0
	for z in [20.4, 23.6]:
		lines.line(Vector3(x0, 4.2, z), Vector3(x1, 4.2, z), "amber", 0.07, 1.1)
		lines.line(Vector3(x0, 5.3, z), Vector3(x1, 5.3, z), "amber", 0.045, 0.75)
		var x := x0 + 1.4
		while x < x1:
			lines.line(Vector3(x, 4.2, z), Vector3(x, 5.3, z), "amber", 0.025, 0.4)
			x += 1.4
	mass.box(x0, x1, 4.1, 4.5, 20.4, 23.6)


## Station facade: a long canopy line over the plaza (the subway exit
## itself is the green MetroStation node Main places, tokyo_metro_station.gd).
static func _station_front(lines) -> void:
	lines.line(Vector3(1.0, 3.4, 5.6), Vector3(91.0, 3.4, 5.6), "weiss", 0.05, 0.55)


## Curbs: low white lines along the road edges of both avenues, rounded at
## the four corners of the crossing.
static func _curbs(lines) -> void:
	var y := Style.CURB_Y
	var t := Style.CURB_THICK
	var m := Style.CURB_MUL
	for x in [41.0, 51.0]:
		lines.line(Vector3(x, y, 11.0), Vector3(x, y, 39.0), "weiss", t, m)
		lines.line(Vector3(x, y, 53.0), Vector3(x, y, 91.0), "weiss", t, m)
	for z in [41.0, 51.0]:
		lines.line(Vector3(1.0, y, z), Vector3(39.0, y, z), "weiss", t, m)
		lines.line(Vector3(53.0, y, z), Vector3(91.0, y, z), "weiss", t, m)
	# corners: [arc center, start angle]
	for c in [[Vector3(39, y, 39), 0.0], [Vector3(53, y, 39), PI * 0.5], [Vector3(53, y, 53), PI], [Vector3(39, y, 53), PI * 1.5]]:
		lines.arc(c[0], Vector3.RIGHT, Vector3.BACK, 2.0, 6, c[1], c[1] + PI * 0.5, "weiss", t, m)


## Road paint: four zebras around the crossing, the two scramble diagonals,
## dashed center lines on both avenues.
static func _road_paint(paint) -> void:
	var y := 0.012
	var x := 41.5
	while x < 50.6:
		paint.floor_rect(x, x + 0.5, 36.2, 39.2, y)
		paint.floor_rect(x, x + 0.5, 52.8, 55.8, y)
		x += 1.0
	var z := 41.5
	while z < 50.6:
		paint.floor_rect(36.2, 39.2, z, z + 0.5, y)
		paint.floor_rect(52.8, 55.8, z, z + 0.5, y)
		z += 1.0
	var c := Vector3(46.0, y, 46.0)
	var first := true
	for dir in [Vector3(1, 0, 1).normalized(), Vector3(1, 0, -1).normalized()]:
		var s := -6.0
		while s <= 6.0:
			# the second diagonal pauses where it crosses the first: one clean X
			if first or absf(s) > 1.5:
				paint.floor_strip(c + dir * s, dir, 0.5, 2.4)
			s += 1.0
		first = false
	var d := 12.0
	while d < 35.0:
		paint.floor_rect(45.94, 46.06, d, d + 2.0, y)
		paint.floor_rect(45.94, 46.06, 92.0 - d - 2.0, 92.0 - d, y)
		paint.floor_rect(d, d + 2.0, 45.94, 46.06, y)
		paint.floor_rect(92.0 - d - 2.0, 92.0 - d, 45.94, 46.06, y)
		d += 4.0


## Sodium lamps on facade brackets: dim bracket, bright head, one light each
## (at most 8 lamp lights — the light budget of docs/design/tokyo-explorer.md).
static func _lamps(lines, root: Node3D) -> void:
	for l in LAMPS:
		var base := Vector3(l[0], LAMP_Y, l[1])
		var out := Vector3(l[2], 0, l[3])
		var head := base + out * 1.3
		lines.line(base, head, "mast", 0.06)
		lines.line(base - Vector3(0, 0.6, 0), base + out * 0.4, "mast", 0.04)
		var side := Vector3(-out.z, 0, out.x)
		lines.line(head - side * 0.3 - Vector3(0, 0.05, 0), head + side * 0.3 - Vector3(0, 0.05, 0), "amber", 0.1, Style.LAMP_MUL)
		var light := OmniLight3D.new()
		light.name = "Lampe"
		light.light_color = Style.LAMP
		light.light_energy = LAMP_LIGHT_ENERGY
		light.omni_range = LAMP_LIGHT_RANGE
		light.omni_attenuation = 1.4
		light.position = head - Vector3(0, 0.25, 0)
		root.add_child(light)


## Vertical shop sign flat on a facade above the base line: white frame,
## generic words in the bundled CJK font.
static func _vsign(lines, root: Node3D, font: Font, base: Vector3, rot_y: float, text: String, h: float) -> void:
	var fwd := Vector3(sin(rot_y), 0, cos(rot_y))
	var right := Vector3(cos(rot_y), 0, -sin(rot_y))
	var w := 1.0
	var p := base + fwd * 0.06
	var c := [p - right * w * 0.5, p + right * w * 0.5, p + right * w * 0.5 + Vector3(0, h, 0), p - right * w * 0.5 + Vector3(0, h, 0)]
	lines.polyline(c, "weiss", 0.045, 1.1, true)
	var l := Label3D.new()
	l.name = "Schild_" + text
	var chars := ""
	for ch in text:
		chars += ch + "\n"
	l.text = chars.strip_edges()
	if font != null:
		l.font = font
	l.font_size = 96
	l.outline_size = 0
	l.pixel_size = (w * 0.62) / 96.0
	l.line_spacing = -18
	l.modulate = Color(Style.WHITE.r * 1.6, Style.WHITE.g * 1.6, Style.WHITE.b * 1.6)
	l.shaded = false
	l.double_sided = false
	l.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	l.position = p + Vector3(0, h * 0.5, 0) + fwd * 0.02
	l.rotation.y = rot_y
	root.add_child(l)


## A video screen (flat light source) with optional vertical lettering and a
## soft light in front of it for the wet floor.
static func _screen(root: Node3D, center: Vector3, size: Vector2, rot_y: float, seed_v: float, energy_mul: float, color_b: Color, text: String, font: Font = null) -> void:
	var mi := MeshInstance3D.new()
	mi.name = "Screen"
	var q := QuadMesh.new()
	q.size = size
	mi.mesh = q
	var m := ShaderMaterial.new()
	m.shader = SCREEN_SHADER
	m.set_shader_parameter("color_a", Style.MAGENTA)
	m.set_shader_parameter("color_b", color_b)
	m.set_shader_parameter("energy", 1.7 * energy_mul)
	m.set_shader_parameter("seed", seed_v)
	mi.material_override = m
	mi.position = center
	mi.rotation.y = rot_y
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	var fwd := Vector3(sin(rot_y), 0, cos(rot_y))
	if text != "":
		var l := Label3D.new()
		l.name = "Screen_Schrift"
		l.text = text
		if font != null:
			l.font = font
		l.font_size = 96
		l.outline_size = 0
		l.pixel_size = (size.x * 0.34) / 96.0
		l.line_spacing = -16
		l.modulate = Color(2.0, 1.9, 1.85)
		l.shaded = false
		l.alpha_cut = Label3D.ALPHA_CUT_DISCARD
		l.position = center + fwd * 0.05
		l.rotation.y = rot_y
		root.add_child(l)
	var light := OmniLight3D.new()
	light.name = "ScreenLicht"
	light.light_color = Style.MAGENTA.lerp(color_b, 0.3)
	light.light_energy = 1.1 * energy_mul
	light.omni_range = 11.0 * energy_mul
	light.position = Vector3(center.x, maxf(center.y - size.y * 0.5, 2.0), center.z) + fwd * 2.5
	root.add_child(light)


## Dim skyline outside the walkable map: black boxes with faint contours
## between ~65 and ~150 m from the crossing (depth through light density);
## positions and heights from the level seed.
static func _skyline(lines, mass, rng: RandomNumberGenerator, maze) -> void:
	var center := Vector3(maze.cols - 1, 0, maze.rows - 1) # crossing, (cols-1)*CELL/2
	var placed := 0
	var tries := 0
	while placed < 46 and tries < 400:
		tries += 1
		var a := rng.randf_range(-PI, PI)
		var d := rng.randf_range(70.0, 150.0)
		var cx := center.x + sin(a) * d
		var cz := center.z + cos(a) * d
		var w := rng.randf_range(9.0, 20.0)
		var dd := rng.randf_range(9.0, 20.0)
		# outside the walkable map (with margin) only
		if cx + w * 0.5 > -6.0 and cx - w * 0.5 < 98.0 and cz + dd * 0.5 > -6.0 and cz - dd * 0.5 < 98.0:
			continue
		var h := rng.randf_range(14.0, 55.0) * (1.0 + d / 220.0)
		var key := "amber" if placed % 2 == 0 else "weiss"
		mass.box(cx - w * 0.5, cx + w * 0.5, 0.0, h, cz - dd * 0.5, cz + dd * 0.5)
		_block_outline(lines, rng, cx - w * 0.5, cx + w * 0.5, cz - dd * 0.5, cz + dd * 0.5, 0.0, h, key,
			{"mul": Style.BACKGROUND_MUL, "thick": 0.22, "floor_step": 5.2, "band_prob": 0.45, "mullion_prob": 0.0})
		placed += 1
