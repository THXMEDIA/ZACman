extends RefCounted
## AmsterdamScenery — builds the 1:100 cardboard model of the Amsterdam
## Explorer city (CityTheme.scenery_builder_script, see city_themes.gd
## amsterdam(); spec docs/design/amsterdam-explorer.md). Everything is plain
## data first (panels(), cuts(), trees(), flute_runs() — the tests check them
## without a renderer), then merged into a handful of draw calls:
##   Panels    every board of the model (facades with real window openings,
##             piers, sills, window crosses, side and back walls, roofs, the
##             Westerkerk tower, the bridges' rails and portals, cutter
##             overruns) as ONE MultiMesh of a unit box; amsterdam_panel.gdshader
##             draws faces (photo scan, washboard, worn corners, tape) and cut
##             edges (liner - flute - liner) from the instance scale
##   Cuts      cut-out shapes extruded at build time and merged into ONE mesh:
##             gables (step, neck, bell, spout), crossed trees, bridge cheeks,
##             clock faces, the imperial crown and the spire
##   Flutes    the real corrugation at every cut edge of the base plate (quay
##             walls and the model's outer edge): liners, two wave sheets,
##             open cavities 1.2 m deep that take light and shadow
##   Water     lacquered card 0.85 m below the street
##   Desk      cutting mat, wooden desk, pencil / ruler (beyond the edge) and
##             the mug with a pencil in it at the end of the Westermarkt
##   Glue      clear glue beads at house feet and tree bases (transparent)
## plus the evening light: a low warm sun with shadows (the only shadow
## caster), the desk lamp and a warm bounce light (the sky / HDRI comes from
## the theme environment). Variation comes from the level seed only. No
## animation in the city.
##
## Build time (QA W2, code W1): the quay flutes depend on the map only and
## are built once per session (static cache, indexed, arrays sized up front);
## the kit, the cut-out mesh and the board / glue buffers are cached per level
## seed. A second build only creates nodes.

const M := preload("res://scripts/amsterdam_maze.gd")
const Style := preload("res://scripts/amsterdam_style.gd")
const PANEL_SHADER := preload("res://shaders/amsterdam_panel.gdshader")
const CUT_SHADER := preload("res://shaders/amsterdam_cut.gdshader")
const FLUTE_SHADER := preload("res://shaders/amsterdam_flute.gdshader")
const WATER_SHADER := preload("res://shaders/amsterdam_water.gdshader")
const MAT_SHADER := preload("res://shaders/amsterdam_mat.gdshader")
const PROPS_SHADER := preload("res://shaders/amsterdam_props.gdshader")
const GLUE_SHADER := preload("res://shaders/amsterdam_glue.gdshader")
const RootScript := preload("res://scripts/amsterdam_root.gd")

const CELL := 2.0
const T := Style.T
const KD := Style.KD
const FLAG_TAPE := 1
const FLAG_SOLID := 2
const PAINT_WHITE := 0.5
const PAINT_EXIT := 1.0
## Flute samples per wave (geometry of the quay walls).
const FLUTE_SAMPLES := 6
## Trees stand this far from the quay edge (trunk centre); the collision box
## closes the gap to the edge, so nobody squeezes between tree and water.
const TREE_IN := 0.45
const TREE_BOX := 0.5
## Model plate, cutting mat and desk (world m).
const PLATE_X0 := -1.0
const PLATE_X1 := 97.0
const PLATE_Z0 := -1.0
const PLATE_Z1 := 97.0
const MAT_SIZE := Vector2(150.0, 124.0)
const MAT_CENTER := Vector2(44.0, 46.0)
## Things beyond the model edge (scale reveal). The mug (12 m = 12 cm) with a
## pencil stuck in it stands a few metres behind the cut edge in the axis of
## the Westermarkt, whose south end runs out to the edge (GD K1): the street
## ends on it, the pencil rises over the low houses at the edge.
const MUG_POS := Vector3(16.0, 0.0, 104.0)
const MUG_H := 12.0
const MUG_R := 4.6
## The pencil in the mug: tip on the mug's floor, leaning out over the rim
## towards the street and to the west (rad from upright).
const MUG_PENCIL_TILT := 0.2
## A steel ruler (30 cm = 30 m) stands in the mug next to the pencil, its
## broad face to the street: the silhouette that rises far over the roofs.
const MUG_RULER_LEN := 30.0
const MUG_RULER_W := 3.0
const MUG_RULER_TILT := 0.1
const PENCIL_X := -12.0 # a second pencil lies west of the Keizersgracht / Prinsengracht ends
const RULER_X := 106.0
## Houses near the cut edge at the Westermarkt's end stay low (2 floors), so
## mug and pencil stand out over the roofs (world x/z rect).
const LOW_HOUSES := Rect2(0.0, 80.0, 42.0, 18.0)
## Desk lamp (2700 K spot with shadows) high up behind the model's west side.
const LAMP_POS := Vector3(-70.0, 150.0, 150.0)
const LAMP_TARGET := Vector3(40.0, 0.0, 40.0)


## A board / cut-out collector with a local frame (house, bridge, tower), so
## every element is written in its own coordinates and placed by the frame.
class Kit:
	var panels: Array = []
	var cuts: Array = []
	var glue: Array = []
	var trees: Array = []
	var houses: Array = [] # {o, n, w, lean, gable, dancing}
	var corner_fronts: Array = [] # corner houses with a second front
	var cutbacks: Array = [] # {p, n, depth}: a row end cut back for a corner house
	var rng := RandomNumberGenerator.new()
	var frame := Transform3D()
	var jitter := 0.0 # chance that a board stands out a few cm (model-making error)
	var tape := 0.0 # chance of a tape strip on a board

	func board(c: Vector3, s: Vector3, b: float, rot := Basis(), paint := 0.0, flags := 0) -> void:
		var o := frame * c
		if jitter > 0.0 and rng.randf() < jitter:
			o += frame.basis.z * rng.randf_range(-0.05, 0.05)
		if tape > 0.0 and flags == 0 and paint == 0.0 and s.y > 1.0 and rng.randf() < tape:
			flags = FLAG_TAPE
		panels.append({"xf": Transform3D(frame.basis * rot * Basis.from_scale(s), o), "b": clampf(b, 0.0, 1.0), "paint": paint, "flags": flags, "seed": rng.randf()})

	func cut(poly: PackedVector2Array, thick: float, c: Vector3, rot := Basis(), b := 0.6, paint := 0.0) -> void:
		cuts.append({"poly": poly, "thick": thick, "xf": Transform3D(frame.basis * rot, frame * c), "b": clampf(b, 0.0, 1.0), "paint": paint, "seed": rng.randf()})


static var _kinds: Array = []


## Cell kind for the model: the notch cut out of the plate ("cut") is off
## the model, like the cells beyond the map.
static func kind(r: int, c: int) -> String:
	if _kinds.is_empty():
		for rr in M.ROWS:
			var row := []
			for cc in M.COLS:
				var k := M.cell_kind(rr, cc)
				row.append("outside" if k == "cut" else k)
			_kinds.append(row)
	if r < 0 or r >= M.ROWS or c < 0 or c >= M.COLS:
		return "outside"
	return _kinds[r][c]


static func cell_of(p: Vector3) -> Vector2i:
	return Vector2i(int(floor(p.z / CELL + 0.5)), int(floor(p.x / CELL + 0.5)))


static func is_open(k: String) -> bool:
	return k == "street" or k == "bridge"


static func is_plate(k: String) -> bool:
	return k == "street" or k == "block" or k == "church" or k == "tram"


## Merged straight pieces of the boundary between a cell whose kind passes
## `a_ok` and its 4-neighbour whose kind passes `b_ok`: [{a, b, n}] at y 0,
## n pointing from the a-cell to the b-cell. Cells off the map are "outside".
static func runs(a_ok: Callable, b_ok: Callable) -> Array:
	var out := []
	for r in range(-1, M.ROWS):
		var z := r * CELL + CELL * 0.5
		for dir in [1, -1]:
			var start := -1
			for c in range(0, M.COLS + 1):
				var ok := false
				if c < M.COLS:
					var ka := kind(r if dir == 1 else r + 1, c)
					var kb := kind(r + 1 if dir == 1 else r, c)
					ok = a_ok.call(ka) and b_ok.call(kb)
				if ok and start < 0:
					start = c
				elif not ok and start >= 0:
					out.append({"a": Vector3(start * CELL - 1.0, 0, z), "b": Vector3(c * CELL - 1.0, 0, z), "n": Vector3(0, 0, dir)})
					start = -1
	for c in range(-1, M.COLS):
		var x := c * CELL + CELL * 0.5
		for dir in [1, -1]:
			var start := -1
			for r in range(0, M.ROWS + 1):
				var ok := false
				if r < M.ROWS:
					var ka := kind(r, c if dir == 1 else c + 1)
					var kb := kind(r, c + 1 if dir == 1 else c)
					ok = a_ok.call(ka) and b_ok.call(kb)
				if ok and start < 0:
					start = r
				elif not ok and start >= 0:
					out.append({"a": Vector3(x, 0, start * CELL - 1.0), "b": Vector3(x, 0, r * CELL - 1.0), "n": Vector3(dir, 0, 0)})
					start = -1
	return out


## Facade lines of the generic houses: block cells facing a street.
static func facade_runs() -> Array:
	return runs(func(k): return k == "block", is_open)


## House fronts standing right on the water (Damrak: the dancing houses;
## the east bank of the Amstel).
static func waterfront_runs() -> Array:
	return runs(func(k): return k == "block", func(k): return k == "water")


## Cut edges of the base plate: quay walls (plate | water) and the model's
## outer edge (plate | outside). The cut plane is the collision edge.
static func flute_runs() -> Array:
	return runs(is_plate, func(k): return k == "water") + runs(is_plate, func(k): return k == "outside")


## Quay lines that carry trees (Keizersgracht and Prinsengracht only; the
## Damrak and Amstel quays stay open for the view across the water).
static func tree_runs() -> Array:
	var out := []
	for run in runs(func(k): return k == "street", func(k): return k == "water"):
		var mid: Vector3 = (run.a + run.b) * 0.5 + run.n * 1.0
		var w := M.water_at(cell_of(mid).x, cell_of(mid).y)
		if w.get("id", "") in ["keizersgracht", "prinsengracht"]:
			out.append(run)
	return out


## Unit tangent of a run (local x of anything standing on it, n = local z).
static func tangent(n: Vector3) -> Vector3:
	return Vector3.UP.cross(n)


# ------------------------------------------------------------------ gables

static func gable(kind_i: int, w: float) -> PackedVector2Array:
	var hw := w * 0.5
	var p := PackedVector2Array()
	match kind_i:
		0: # step gable (trapgevel)
			var steps := 4
			var sh := 0.95
			var sw := hw / (steps + 0.5)
			p.append(Vector2(-hw, 0))
			for s in steps:
				var x0 := -hw + s * sw
				p.append(Vector2(x0, (s + 1) * sh))
				p.append(Vector2(x0 + sw, (s + 1) * sh))
			for s in range(steps - 1, -1, -1):
				var x1 := hw - s * sw
				p.append(Vector2(x1 - sw, (s + 1) * sh))
				p.append(Vector2(x1, (s + 1) * sh))
			p.append(Vector2(hw, 0))
		1: # bell gable (klokgevel)
			var nw := hw * 0.55
			p.append(Vector2(-hw, 0))
			for i in 9:
				var t := i / 8.0
				p.append(Vector2(-hw + (hw - nw) * t, 0.2 + sin(t * PI * 0.5) * 2.4 + (1.0 - cos(t * PI)) * 0.2))
			for i in range(1, 12):
				var a := PI - i / 12.0 * PI
				p.append(Vector2(cos(a) * nw, 2.8 + sin(a) * 1.2))
			for i in 9:
				var t := 1.0 - i / 8.0
				p.append(Vector2(hw - (hw - nw) * t, 0.2 + sin(t * PI * 0.5) * 2.4 + (1.0 - cos(t * PI)) * 0.2))
			p.append(Vector2(hw, 0))
		2: # neck gable (halsgevel) with a pediment
			var nw2 := hw * 0.5
			p.append_array(PackedVector2Array([Vector2(-hw, 0), Vector2(-hw, 0.5), Vector2(-nw2 - 0.35, 1.3), Vector2(-nw2, 1.4), Vector2(-nw2, 3.4),
				Vector2(-nw2 - 0.25, 3.45), Vector2(0, 4.7), Vector2(nw2 + 0.25, 3.45), Vector2(nw2, 3.4), Vector2(nw2, 1.4), Vector2(nw2 + 0.35, 1.3), Vector2(hw, 0.5), Vector2(hw, 0)]))
		_: # spout gable (tuitgevel)
			p.append_array(PackedVector2Array([Vector2(-hw, 0), Vector2(-0.45, 3.9), Vector2(-0.45, 4.4), Vector2(0.45, 4.4), Vector2(0.45, 3.9), Vector2(hw, 0)]))
	return p


static func poly_top(p: PackedVector2Array) -> float:
	var h := 0.0
	for v in p:
		h = maxf(h, v.y)
	return h


static func circle(r: float, n: int) -> PackedVector2Array:
	var p := PackedVector2Array()
	for i in n:
		var a := TAU * float(i) / n
		p.append(Vector2(cos(a) * r, sin(a) * r))
	return p


static func tree_poly(rng: RandomNumberGenerator, r: float, h: float) -> PackedVector2Array:
	var p := PackedVector2Array()
	p.append(Vector2(-0.2, 0))
	p.append(Vector2(-0.2, h - r * 0.9))
	var n := 22
	for i in n + 1:
		var a := -PI * 0.5 - 0.25 - i / float(n) * (TAU - 0.5)
		var rr := r * (0.86 + 0.14 * sin(i * 2.7) + 0.06 * rng.randf())
		p.append(Vector2(cos(a) * rr, h + sin(a) * rr * 1.1))
	p.append(Vector2(0.2, h - r * 0.9))
	p.append(Vector2(0.2, 0))
	return p


# ------------------------------------------------------------------ houses

## One canal house in the kit's frame (x across the front, y up, z out to the
## street; the front face is the plane z = 0 = the collision edge).
static func house(K: Kit, w: float, floors: int, gkind: int, depth: float, bri: float, door := true, open_left := false, open_right := false) -> void:
	var H := facade(K, w, floors, bri, door)
	var zc := -T * 0.5
	# side walls (fire walls) - or, at a street corner, a second front with windows
	for s in [-1.0, 1.0]:
		if (s < 0.0 and open_left) or (s > 0.0 and open_right):
			# The side front runs between the front board and the back wall
			# (z -depth+T .. -T), not into them: its end caps would lie in the
			# front's plane (z 0) and the back's plane (a coplanar strip 40 cm
			# wide over the whole height at every outer corner, z-fighting).
			# Very shallow corner houses keep a 2.6 m minimum (the ends then
			# vanish inside the front and back boards).
			var keep := K.frame
			K.frame = keep * Transform3D(Basis(Vector3.UP, s * PI * 0.5), Vector3(s * w * 0.5, 0, -depth * 0.5))
			facade(K, maxf(depth - 2.0 * T, 2.6), floors, bri, false)
			K.frame = keep
		else:
			# Fire wall between the front board (z -T..0) and the back wall
			# (z -depth..-depth+T): it must not reach into either, or its end
			# faces would lie in the same planes as theirs (z-fighting strips
			# at every house corner = edge flicker, Abnahme 06.10.).
			K.board(Vector3(s * (w * 0.5 - T * 0.25), H * 0.5, -depth * 0.5), Vector3(T * 0.5, H, depth - 2.0 * T), bri * 0.85)
	K.board(Vector3(0, H * 0.5, -depth + T * 0.5), Vector3(w, H, T), bri * 0.8)
	# gable and the saddle roof behind it (ridge runs back from the street)
	var gp := gable(gkind, w)
	var gh := poly_top(gp)
	K.cut(gp, T, Vector3(0, H - 0.01, zc), Basis(), bri)
	var rh := minf(gh * 0.8, 3.6)
	var ra := atan2(rh, w * 0.5)
	var rl := sqrt(w * w * 0.25 + rh * rh)
	for s in [-1.0, 1.0]:
		K.board(Vector3(s * w * 0.25, H + rh * 0.5, -(T + depth) * 0.5), Vector3(rl + 0.15, T * 0.6, depth - T), bri * 0.9, Basis(Vector3(0, 0, 1), -s * ra))
	# hoist beam under the gable top
	K.board(Vector3(0, H + gh - 0.9, 0.45), Vector3(0.28, 0.28, 1.3), bri)


## The front of a house in the kit's frame (front plane z = 0, x across):
## sills, piers and lintels around real window openings, window crosses, a
## door set back, cutter overruns, the dark rooms behind. Returns the height.
static func facade(K: Kit, w: float, floors: int, bri: float, door: bool) -> float:
	var g0 := 3.8 # ground floor (higher, like the real ones)
	var fh := 3.1
	var H := g0 + fh * (floors - 1)
	var nwin := clampi(int(round(w / 1.9)), 1, 5) if w > 5.5 else (2 if w < 5.0 else 3)
	var ww := 1.1
	var pier := (w - nwin * ww) / (nwin + 1)
	var door_k := nwin / 2
	var zc := -T * 0.5
	for f in floors:
		var y0 := 0.0 if f == 0 else g0 + fh * (f - 1)
		var hgt := g0 if f == 0 else fh
		var yb := y0 + (0.65 if f == 0 else 0.85)
		var yt := yb + (2.45 if f == 0 else 1.75)
		if f > 0:
			K.board(Vector3(0, (y0 + yb) * 0.5, zc), Vector3(w, yb - y0, T), bri)
		for k in nwin + 1:
			var px := -w * 0.5 + pier * 0.5 + k * (ww + pier)
			K.board(Vector3(px, (yb + yt) * 0.5, zc), Vector3(pier, yt - yb, T), bri)
		K.board(Vector3(0, (yt + y0 + hgt) * 0.5, zc), Vector3(w, y0 + hgt - yt, T), bri)
		for k in nwin:
			var wx := -w * 0.5 + pier + ww * 0.5 + k * (ww + pier)
			if f == 0 and k == door_k and door:
				# the door: no sill, a darker board set back in the opening
				K.board(Vector3(wx, yt * 0.5, -T - 0.05), Vector3(ww - 0.05, yt, 0.1), bri * 0.45)
				continue
			if f == 0:
				K.board(Vector3(wx, yb * 0.5, zc), Vector3(ww, yb, T), bri)
			# window cross of thin strips, a little behind the front (the
			# crossbar is 2 cm shallower than the post: no coplanar faces where
			# they cross, no z-fighting square)
			K.board(Vector3(wx, yb + (yt - yb) * 0.62, -T * 0.55), Vector3(ww, 0.12, 0.10), bri)
			K.board(Vector3(wx, (yb + yt) * 0.5, -T * 0.55), Vector3(0.12, yt - yb, 0.12), bri)
			# the cutter ran a little too far at a window corner
			if K.rng.randf() < 0.35:
				var cy := yt if K.rng.randf() < 0.5 else yb
				var cx := wx + (ww * 0.5 if K.rng.randf() < 0.5 else -ww * 0.5)
				var horiz := K.rng.randf() < 0.5
				var ln := minf(K.rng.randf_range(0.18, 0.45), pier * 0.75) # never past the house edge
				var off := Vector3(signf(cx - wx) * ln * 0.5, 0, 0) if horiz else Vector3(0, signf(cy - (yb + yt) * 0.5) * ln * 0.5, 0)
				K.board(Vector3(cx, cy, 0.004) + off, Vector3(ln if horiz else 0.035, 0.035 if horiz else ln, 0.01), 0.0, Basis(), 0.0, FLAG_SOLID)
	# the dark rooms behind the window openings
	K.board(Vector3(0, H * 0.5, -1.3), Vector3(w - 0.3, H, 0.05), 0.0, Basis(), 0.0, FLAG_SOLID)
	return H


## Depth of a house from its front (at `o`, facing `n`): half the block when
## houses stand on the other side too, else the whole block; 3..9 m.
static func house_depth(o: Vector3, n: Vector3) -> float:
	var d := 0.5
	while d < 40.0:
		var cc := cell_of(o - n * d + Vector3(0, 0, 0))
		var k := kind(cc.x, cc.y)
		if k != "block":
			if k == "street" or k == "bridge":
				return clampf(d * 0.5 - 0.2, 3.0, 9.0)
			return clampf(d - 0.3, 3.0, 9.0)
		d += 0.5
	return 9.0


## Houses along one run. `look`: {floors: [min, max], w: [min, max],
## lean: amplitude (rad, smooth along the run), tilt: forward tilt (rad)}.
static func house_row(K: Kit, run: Dictionary, look: Dictionary) -> void:
	var n: Vector3 = run.n
	var t := tangent(n)
	var a: Vector3 = run.a
	var b: Vector3 = run.b
	if (b - a).dot(t) < 0.0:
		var tmp := a
		a = b
		b = tmp
	var length := a.distance_to(b)
	if length < 2.5:
		return
	var target: float = K.rng.randf_range(look.w[0], look.w[1])
	var count := maxi(1, int(round(length / target)))
	var hw := length / float(count)
	var phase := K.rng.randf() * TAU
	# street corners at the ends of this row: the corner house shows a second
	# front there (kit() cut the crossing row back by that house's depth)
	var corners: Array = run.get("corners", [])
	var open_a := -1.0
	var open_b := -1.0
	for cn in corners:
		if cn.p.distance_to(a) < 0.01:
			open_a = cn.depth
		elif cn.p.distance_to(b) < 0.01:
			open_b = cn.depth
	for i in count:
		var o := a + t * (hw * (float(i) + 0.5))
		var w := hw - 0.02
		var floors: int = K.rng.randi_range(look.floors[0], look.floors[1])
		if LOW_HOUSES.has_point(Vector2(o.x, o.z)):
			floors = mini(floors, 2)
		var gk := K.rng.randi_range(0, 3)
		var lean: float = look.get("lean", 0.0)
		var le: float = K.rng.randf_range(-0.004, 0.004)
		if lean > 0.0:
			# dancing: neighbours lean alike, changing from house to house
			le = lean * (0.8 * sin(phase + float(i) * 0.95) + 0.2 * sin(phase * 2.0 + float(i) * 2.3))
		var tilt: float = look.get("tilt", 0.0) * K.rng.randf_range(0.4, 1.0)
		K.frame = Transform3D(Basis(t, Vector3.UP, n) * Basis(Vector3(0, 0, 1), le) * Basis(Vector3(1, 0, 0), tilt), o)
		K.jitter = 0.07
		var bri := K.rng.randf_range(0.25, 0.85)
		var depth := house_depth(o, n)
		var ol := i == 0 and open_a > 0.0
		var orr := i == count - 1 and open_b > 0.0
		if ol:
			depth = open_a
		if orr:
			depth = open_b if not ol else minf(open_a, open_b)
		if ol or orr:
			le = 0.0 # a corner house stands straight (it closes two rows)
			K.frame = Transform3D(Basis(t, Vector3.UP, n), o)
		house(K, w, floors, gk, depth, bri, not look.get("water", false), ol, orr)
		if ol or orr:
			K.corner_fronts.append({"o": o, "n": n, "w": w, "depth": depth, "left": ol, "right": orr})
		K.houses.append({"o": o, "n": n, "w": w, "lean": le, "gable": gk, "dancing": lean > 0.0})
		K.jitter = 0.0
		# white glue squeezed out at the foot of some houses
		if K.rng.randf() < 0.5:
			for k in K.rng.randi_range(1, 3):
				K.glue.append([o + t * K.rng.randf_range(-w * 0.45, w * 0.45) + n * 0.1 + Vector3(0, 0.02, 0), K.rng.randf_range(0.22, 0.5)])


# ------------------------------------------------------------------ landmarks

## A hollow square stage of the tower (four boards), centre (x, z) in the
## frame, from y0 to y1, side `s`; `rot` turns it (45 deg: the octagon).
static func stage(K: Kit, s: float, y0: float, y1: float, bri: float, rot := Basis()) -> void:
	var h := y1 - y0
	for k in 4:
		var r := rot * Basis(Vector3.UP, k * PI * 0.5)
		K.board(Vector3(0, (y0 + y1) * 0.5, 0) + r * Vector3(0, 0, s * 0.5 - T * 0.5), Vector3(s - (T if k % 2 == 1 else 0.0), h, T), bri, r)
		# dark louvre opening in the upper part of every face
		K.board(Vector3(0, y0 + h * 0.62, 0) + r * Vector3(0, 0, s * 0.5 + 0.01), Vector3(minf(1.3, s * 0.25), h * 0.42, 0.04), 0.0, r, 0.0, FLAG_SOLID)
	# cornice slab on top
	K.board(Vector3(0, y1 + 0.2, 0), Vector3(s + 0.6, 0.4, s + 0.6), bri * 1.05, rot)


## The Westerkerk: nave with tall windows and two transept gables on the
## Westermarkt, and the tower with the imperial crown (built 1638, public
## domain; stylised, no copy of the real proportions). Its 7 m base stands in
## the church front, at the end of the Damrak quay (the axis of the start).
static func westerkerk(K: Kit) -> void:
	var n := Vector3(1, 0, 0)
	var t := tangent(n) # (0, 0, -1)
	var fx := 7.0 * CELL - 1.0 # front of the church block (x 13)
	var tz := M.TOWER_Z
	K.frame = Transform3D(Basis(t, Vector3.UP, n), Vector3(fx, 0, tz))
	var bri := 0.62
	var H := 13.0
	var depth := 13.5
	# nave front: two pieces left and right of the tower (local x = -(z - 24))
	for seg in [[-13.0, -3.5], [3.5, 17.0]]:
		var x0: float = seg[0]
		var x1: float = seg[1]
		var w := x1 - x0
		var cx := (x0 + x1) * 0.5
		K.board(Vector3(cx, 1.5, -T * 0.5), Vector3(w, 3.0, T), bri)
		K.board(Vector3(cx, 11.5, -T * 0.5), Vector3(w, 3.0, T), bri)
		var nw := int(floor(w / 4.0))
		var ww := 1.7
		var pier := (w - nw * ww) / (nw + 1)
		for k in nw + 1:
			K.board(Vector3(x0 + pier * 0.5 + k * (ww + pier), 6.5, -T * 0.5), Vector3(pier, 7.0, T), bri)
		for k in nw:
			var wx := x0 + pier + ww * 0.5 + k * (ww + pier)
			K.cut(_arch_top(ww), T, Vector3(wx, 8.6, -T * 0.5), Basis(), bri)
			K.board(Vector3(wx, 6.0, -T * 0.6), Vector3(0.12, 6.0, 0.12), bri)
			K.board(Vector3(wx, 6.4, -T * 0.6), Vector3(ww, 0.12, 0.12), bri)
		K.board(Vector3(cx, H * 0.5, -1.6), Vector3(w - 0.3, H, 0.05), 0.0, Basis(), 0.0, FLAG_SOLID)
	# nave roof along the street, ridge 9 m above the eaves, and its end gables
	var ra := atan2(9.0, depth * 0.5)
	var rl := sqrt(81.0 + depth * depth * 0.25) + 0.3
	K.board(Vector3(2.0, H + 4.5, -depth * 0.25), Vector3(30.5, T * 0.6, rl), bri * 0.85, Basis(Vector3(1, 0, 0), ra))
	K.board(Vector3(2.0, H + 4.5, -depth * 0.75), Vector3(30.5, T * 0.6, rl), bri * 0.85, Basis(Vector3(1, 0, 0), -ra))
	var tri := PackedVector2Array([Vector2(-depth * 0.5, 0), Vector2(0, 9.0), Vector2(depth * 0.5, 0)])
	for ex in [-13.0, 17.0]:
		# the end walls stand behind the front boards (z -T..0), shifted in by
		# half a board: no end face in the plane of the front (z-fighting)
		var exi: float = ex + (T * 0.5 if ex < 0.0 else -T * 0.5)
		K.board(Vector3(exi, H * 0.5, -(depth + T) * 0.5), Vector3(T, H, depth - T), bri * 0.8)
		K.cut(tri, T, Vector3(exi, H, -depth * 0.5), Basis(Vector3.UP, PI * 0.5), bri * 0.8)
	# two transept gables on the front (step gables, 8 m wide)
	for gx in [-8.3, 10.3]:
		K.cut(gable(0, 8.0), T, Vector3(gx, H - 0.01, -T * 0.5), Basis(), bri)
		K.cut(gable(0, 8.0), T, Vector3(gx, H - 0.01, -4.5), Basis(), bri * 0.8)
		for s in [-1.0, 1.0]:
			K.board(Vector3(gx + s * 2.0, H + 2.0, -2.5), Vector3(4.6, T * 0.6, 4.6), bri * 0.85, Basis(Vector3(0, 0, 1), -s * 0.75))
	# the tower, centred on the axis; local frame of the tower: origin at its centre
	var tf := K.frame
	K.frame = Transform3D(tf.basis, tf * Vector3(0, 0, -3.5))
	# base 0..26: front with the door, sides, back
	var s1 := 7.0
	for k in [1, 2, 3]:
		var r := Basis(Vector3.UP, k * PI * 0.5)
		K.board(r * Vector3(0, 0, s1 * 0.5 - T * 0.5) + Vector3(0, 13.0, 0), Vector3(s1 - (T if k % 2 == 1 else 0.0), 26.0, T), bri, r)
	K.board(Vector3(-2.4, 13.0, s1 * 0.5 - T * 0.5), Vector3(2.2, 26.0, T), bri)
	K.board(Vector3(2.4, 13.0, s1 * 0.5 - T * 0.5), Vector3(2.2, 26.0, T), bri)
	K.board(Vector3(0, 15.5, s1 * 0.5 - T * 0.5), Vector3(2.6, 21.0, T), bri)
	K.cut(_arch_top(2.6), T, Vector3(0, 4.0, s1 * 0.5 - T * 0.5), Basis(), bri)
	K.board(Vector3(0, 2.6, s1 * 0.5 - 0.6), Vector3(2.6, 5.2, 0.1), 0.15)
	for wy in [11.0, 19.0]:
		K.board(Vector3(0, wy, s1 * 0.5 + 0.01), Vector3(1.1, 4.2, 0.04), 0.0, Basis(), 0.0, FLAG_SOLID)
	K.board(Vector3(0, 26.2, 0), Vector3(s1 + 0.6, 0.4, s1 + 0.6), bri * 1.05)
	# clock stage 26..34 with white clock faces
	stage(K, 6.0, 26.4, 34.0, bri)
	for k in 4:
		var r := Basis(Vector3.UP, k * PI * 0.5)
		K.cut(circle(1.5, 28), 0.15, r * Vector3(0, 0, 3.08) + Vector3(0, 29.2, 0), r, 0.6, PAINT_WHITE)
		K.board(r * Vector3(0, 0, 3.17) + Vector3(0.0, 29.5, 0), Vector3(0.1, 1.1, 0.03), 0.0, r * Basis(Vector3(0, 0, 1), 0.5), 0.0, FLAG_SOLID)
		K.board(r * Vector3(0, 0, 3.17) + Vector3(0.0, 29.2, 0), Vector3(0.1, 0.8, 0.03), 0.0, r * Basis(Vector3(0, 0, 1), -1.3), 0.0, FLAG_SOLID)
	# two octagonal stages (two squares, one turned 45 deg)
	for oct in [[5.0, 34.4, 42.0], [3.8, 42.4, 48.0]]:
		stage(K, oct[0], oct[1], oct[2], bri)
		stage(K, oct[0], oct[1], oct[2], bri, Basis(Vector3.UP, PI * 0.25))
	# the imperial crown, painted white, as four crossed cut-outs
	var crown := _crown()
	for k in 4:
		K.cut(crown, 0.25, Vector3(0, 48.4, 0), Basis(Vector3.UP, k * PI * 0.25), 0.6, PAINT_WHITE)
	# spire with a little ball
	var spire := PackedVector2Array([Vector2(-0.7, 0), Vector2(0, M.TOWER_H - 55.0), Vector2(0.7, 0)])
	for k in 2:
		K.cut(spire, 0.18, Vector3(0, 55.0, 0), Basis(Vector3.UP, k * PI * 0.5), 0.7)
	K.cut(circle(0.45, 16), 0.3, Vector3(0, 58.0, 0), Basis(), 0.7, PAINT_WHITE)


static func _arch_top(w: float) -> PackedVector2Array:
	var p := PackedVector2Array()
	var hw := w * 0.5
	# a lintel with a round arch cut out of its underside: band from y 0 to hw + 0.5
	p.append(Vector2(-hw, 0))
	for i in 13:
		var a := PI - i / 12.0 * PI
		p.append(Vector2(cos(a) * hw, sin(a) * hw))
	p.append(Vector2(hw, 0))
	p.append(Vector2(hw + 0.02, hw + 0.4))
	p.append(Vector2(-hw - 0.02, hw + 0.4))
	return p


static func _crown() -> PackedVector2Array:
	# band, two arches meeting under the orb, cross on top (6.5 m)
	var p := PackedVector2Array()
	p.append_array(PackedVector2Array([Vector2(-2.2, 0), Vector2(2.2, 0), Vector2(2.3, 1.1), Vector2(2.0, 1.2)]))
	for i in 9:
		var a := float(i) / 8.0 * PI * 0.5
		p.append(Vector2(2.0 * cos(a) * 0.95, 1.2 + sin(a) * 2.6))
	p.append_array(PackedVector2Array([Vector2(0.45, 4.0), Vector2(0.7, 4.5), Vector2(0.18, 4.8), Vector2(0.18, 5.6), Vector2(0.6, 5.6), Vector2(0.6, 5.95),
		Vector2(0.18, 5.95), Vector2(0.18, 6.5), Vector2(-0.18, 6.5), Vector2(-0.18, 5.95), Vector2(-0.6, 5.95), Vector2(-0.6, 5.6), Vector2(-0.18, 5.6),
		Vector2(-0.18, 4.8), Vector2(-0.7, 4.5), Vector2(-0.45, 4.0)]))
	for i in 9:
		var a := PI * 0.5 + float(i) / 8.0 * PI * 0.5
		p.append(Vector2(2.0 * cos(a) * 0.95, 1.2 + sin(a) * 2.6))
	p.append_array(PackedVector2Array([Vector2(-2.0, 1.2), Vector2(-2.3, 1.1)]))
	return p


## A bridge over a canal: cheeks with arches under the deck, a deck board,
## rails just outside the walkable width (the water cells beside the bridge
## are the collision; the rail marks that edge). The Magere Brug is white and
## gets the drawbridge portals with the balance beams.
static func bridge(K: Kit, b: Dictionary) -> void:
	var white: bool = b.id == "magere_brug"
	var paint := PAINT_WHITE if white else 0.0
	var bri := 0.62
	var ns: bool = b.axis == "ns"
	var x0: float = b.c0 * CELL - 1.0
	var x1: float = b.c1 * CELL + 1.0
	var z0: float = b.r0 * CELL - 1.0
	var z1: float = b.r1 * CELL + 1.0
	# frame: local x along the span, z across (the deck width), centre at the deck middle
	var span := (z1 - z0) if ns else (x1 - x0)
	var width := (x1 - x0) if ns else (z1 - z0)
	var basis := Basis(Vector3.UP, -PI * 0.5) if ns else Basis()
	K.frame = Transform3D(basis, Vector3((x0 + x1) * 0.5, 0, (z0 + z1) * 0.5))
	var hs := span * 0.5
	var hw := width * 0.5
	# deck underside
	K.board(Vector3(0, -0.24, 0), Vector3(span + 1.0, 0.44, width + 0.6), bri, Basis(), paint)
	# cheeks with arches (one big arch, the Magere Brug three)
	var arches: Array = [[-4.0, 1.75], [0.0, 1.9], [4.0, 1.75]] if white else [[0.0, hs - 0.7]]
	var cheek := PackedVector2Array()
	cheek.append(Vector2(-hs, 0.12))
	cheek.append(Vector2(hs, 0.12))
	cheek.append(Vector2(hs, -0.9))
	var arcs := arches.duplicate()
	arcs.reverse()
	for ar in arcs:
		var cx: float = ar[0]
		var r: float = ar[1]
		for i in 13:
			var a := float(i) / 12.0 * PI
			cheek.append(Vector2(cx + cos(a) * r, -0.9 + sin(a) * minf(0.62, r * 0.6)))
	cheek.append(Vector2(-hs, -0.9))
	for s in [-1.0, 1.0]:
		K.cut(cheek, T, Vector3(0, 0, s * (hw + T * 0.5)), Basis(), bri, paint)
	# rails: top rail and posts, just outside the edge
	for s in [-1.0, 1.0]:
		var rz: float = s * (hw + 0.2)
		# rails end at the quay edge (they stand over the water, beside the walkable width)
		K.board(Vector3(0, 1.0, rz), Vector3(span - 0.16, 0.14, 0.16), bri, Basis(), paint)
		K.board(Vector3(0, 0.55, rz), Vector3(span - 0.16, 0.1, 0.1), bri, Basis(), paint)
		var np := int(span / 1.4)
		for k in np + 1:
			K.board(Vector3(-hs + 0.12 + k * (span - 0.24) / np, 0.5, rz), Vector3(0.14, 1.0, 0.14), bri, Basis(), paint)
	if not white:
		return
	# Magere Brug: two portals ("galgen") near the middle, each with a lattice
	# balance beam over the road; tie rods from the beam ends to the deck edges.
	for sx in [-1.0, 1.0]:
		var px: float = sx * 2.0
		for sz in [-1.0, 1.0]:
			K.board(Vector3(px, 3.6, sz * (hw + 0.45)), Vector3(0.38, 7.2, 0.38), bri, Basis(), paint)
			K.board(Vector3(px + sx * 0.75, 1.5, sz * (hw + 0.45)), Vector3(0.2, 3.3, 0.2), bri, Basis(Vector3(0, 0, 1), sx * 0.45), paint)
		K.board(Vector3(px, 7.3, 0), Vector3(0.45, 0.45, width + 1.6), bri, Basis(), paint)
		var bl := 6.0
		var bc: float = px + sx * 1.3
		for sz in [-1.0, 1.0]:
			K.board(Vector3(bc, 7.78, sz * (hw + 0.3)), Vector3(bl, 0.34, 0.3), bri, Basis(Vector3(0, 0, 1), -sx * 0.035), paint)
		for k in 5:
			var tx := bc + (k - 2) * bl / 4.4
			K.board(Vector3(tx, 7.78, 0), Vector3(0.22, 0.22, width + 0.6), bri, Basis(), paint)
		for k in 4:
			var tx2 := bc + (k - 1.5) * bl / 4.0
			K.board(Vector3(tx2, 7.78, 0), Vector3(0.16, 0.16, width * 0.9), bri, Basis(Vector3.UP, 0.6 if k % 2 == 0 else -0.6), paint)
		for sz in [-1.0, 1.0]:
			var tip := Vector3(bc + sx * bl * 0.5 - sx * 0.4, 0, sz * (hw + 0.3)) # over the water, inside the span
			K.board(Vector3(tip.x, 3.95, tip.z), Vector3(0.08, 7.6, 0.08), 0.0, Basis(), 0.0, FLAG_SOLID)


## Crossed cut-out trees along the Keizersgracht and Prinsengracht quays,
## every 8-9 m, not near bridges, run ends or the exit.
static func tree_rows(K: Kit) -> void:
	for run in tree_runs():
		var n: Vector3 = run.n # from the street towards the water
		var t := tangent(n)
		var a: Vector3 = run.a
		var b: Vector3 = run.b
		if (b - a).dot(t) < 0.0:
			var tmp := a
			a = b
			b = tmp
		var length := a.distance_to(b)
		var u := K.rng.randf_range(3.0, 6.0)
		while u < length - 3.0:
			var p := a + t * u - n * TREE_IN
			var ok := true
			for br in M.BRIDGES:
				var bx0: float = br.c0 * CELL - 1.0 - 4.0
				var bx1: float = br.c1 * CELL + 1.0 + 4.0
				var bz0: float = br.r0 * CELL - 1.0 - 4.0
				var bz1: float = br.r1 * CELL + 1.0 + 4.0
				if p.x > bx0 and p.x < bx1 and p.z > bz0 and p.z < bz1:
					ok = false
			if ok:
				var poly := tree_poly(K.rng, K.rng.randf_range(2.0, 2.6), K.rng.randf_range(6.4, 7.8))
				var yaw := K.rng.randf_range(0.2, 0.45)
				K.frame = Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3(1, 0, 0), K.rng.randf_range(-0.02, 0.02)), p)
				K.cut(poly, 0.12, Vector3.ZERO, Basis(), K.rng.randf_range(0.4, 0.8))
				K.cut(poly, 0.12, Vector3.ZERO, Basis(Vector3.UP, PI * 0.5), K.rng.randf_range(0.4, 0.8))
				K.trees.append(p)
				if K.rng.randf() < 0.5:
					K.glue.append([p + Vector3(0.25, 0.02, 0.2), 0.3])
			u += K.rng.randf_range(7.5, 9.0)


## Outer street corners: two rows of house fronts meet at a block corner and
## their houses would overlap there (one's fire wall in the other's front, so
## the windows show cardboard). The east-west row keeps the corner: its end
## house gets a second front with windows on the crossing street, and the
## north-south row is cut back by that house's depth.
static func corner_cut(K: Kit, fronts: Array) -> void:
	for fr in fronts:
		fr.run = fr.run.duplicate()
	for ns in fronts:
		if absf(ns.run.n.x) < 0.5:
			continue
		for end in ["a", "b"]:
			var e: Vector3 = ns.run[end]
			var other_ns: Vector3 = ns.run["b" if end == "a" else "a"]
			for ew in fronts:
				if absf(ew.run.n.z) < 0.5:
					continue
				for eend in ["a", "b"]:
					if ew.run[eend].distance_to(e) > 0.01:
						continue
					var other_ew: Vector3 = ew.run["b" if eend == "a" else "a"]
					# outer corner: each row runs on behind the other one's front
					if (other_ew - e).dot(-ns.run.n) < 0.5 or (other_ns - e).dot(-ew.run.n) < 0.5:
						continue
					var d := house_depth(e + (other_ew - e).normalized() * 1.5, ew.run.n)
					if e.distance_to(other_ns) - d < 2.5:
						d = e.distance_to(other_ns) # too short for a house: the corner front closes it all
					var cs: Array = ew.run.get("corners", [])
					cs.append({"p": e, "depth": d})
					ew.run["corners"] = cs
					ns.run[end] = e + (other_ns - e).normalized() * d
					K.cutbacks.append({"p": e, "n": ns.run.n, "depth": d})


## The whole model as plain data: {panels, cuts, glue, trees}.
static func kit(seed: int) -> Kit:
	var K := Kit.new()
	K.rng.seed = seed
	K.tape = 0.06
	var fronts := []
	for run in facade_runs():
		var mid: Vector3 = (run.a + run.b) * 0.5 + run.n * 1.0
		var st := M.street_at(cell_of(mid).x, cell_of(mid).y)
		var narrow: bool = st.get("id", "").begins_with("gasse")
		fronts.append({"run": run, "look": {"floors": [3, 4] if narrow else [3, 5], "w": [4.4, 6.8]}})
	for run in waterfront_runs():
		var mid2: Vector3 = (run.a + run.b) * 0.5 + run.n * 1.0
		var w := M.water_at(cell_of(mid2).x, cell_of(mid2).y)
		if w.get("id", "") == "damrak" and run.n.z > 0.5:
			# the dancing houses: narrow, tall, leaning against each other
			fronts.append({"run": run, "look": {"floors": [4, 5], "w": [4.2, 5.6], "lean": 0.065, "tilt": 0.035, "water": true}})
		else:
			fronts.append({"run": run, "look": {"floors": [4, 5], "w": [4.6, 6.6], "water": true}})
	corner_cut(K, fronts)
	for fr in fronts:
		house_row(K, fr.run, fr.look)
	K.tape = 0.0
	westerkerk(K)
	for b in M.BRIDGES:
		bridge(K, b)
	tree_rows(K)
	return K


static func panels(seed: int) -> Array:
	return kit(seed).panels


## Tree trunk positions of the cached model of a level seed (the moving
## figures keep clear of them, amsterdam_life.gd).
static func trees(seed: int) -> Array:
	return _cached(seed).kit.trees


# ------------------------------------------------------------------ meshes

## Triangle buffer for the merged meshes. Front faces in Godot are clockwise:
## a triangle is emitted so that (v1 - v0) x (v2 - v0) points away from its
## wanted normal.
class Buf:
	var V := PackedVector3Array()
	var N := PackedVector3Array()
	var U := PackedVector2Array()
	var C := PackedColorArray()
	var TG := PackedFloat32Array()
	var tangents := false

	func tri(a: Vector3, b: Vector3, c: Vector3, n: Vector3, cols: Array, uvs: Array, tg := Vector3.ZERO) -> void:
		var o := [0, 1, 2]
		if (b - a).cross(c - a).dot(n) > 0.0:
			o = [0, 2, 1]
		var pts := [a, b, c]
		for k in o:
			V.append(pts[k])
			N.append(n)
			C.append(cols[k])
			U.append(uvs[k])
			if tangents:
				TG.append_array([tg.x, tg.y, tg.z, 1.0])

	## q0..q3 around the quad; cols/uvs per corner.
	func quad(q: Array, n: Vector3, cols: Array, uvs: Array, tg := Vector3.ZERO) -> void:
		tri(q[0], q[1], q[2], n, [cols[0], cols[1], cols[2]], [uvs[0], uvs[1], uvs[2]], tg)
		tri(q[0], q[2], q[3], n, [cols[0], cols[2], cols[3]], [uvs[0], uvs[2], uvs[3]], tg)

	func commit() -> ArrayMesh:
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = V
		arr[Mesh.ARRAY_NORMAL] = N
		arr[Mesh.ARRAY_TEX_UV] = U
		arr[Mesh.ARRAY_COLOR] = C
		if tangents:
			arr[Mesh.ARRAY_TANGENT] = TG
		var m := ArrayMesh.new()
		if V.size() > 0:
			m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		return m


## All cut-outs extruded and merged into one ArrayMesh (one draw call).
static func cut_mesh(cuts: Array) -> ArrayMesh:
	var B := Buf.new()
	B.tangents = true
	for ct in cuts:
		var poly: PackedVector2Array = ct.poly
		if Geometry2D.is_polygon_clockwise(poly):
			poly = poly.duplicate()
			poly.reverse()
		var xf: Transform3D = ct.xf
		var hz: float = ct.thick * 0.5
		var col_f := Color(ct.b, ct.seed, ct.paint, 0.0)
		var col_e := Color(ct.b, ct.seed, ct.paint, 1.0)
		var cf := [col_f, col_f, col_f]
		var ce := [col_e, col_e, col_e, col_e]
		var nz := (xf.basis * Vector3(0, 0, 1)).normalized()
		var tx := (xf.basis * Vector3(1, 0, 0)).normalized()
		var idx := Geometry2D.triangulate_polygon(poly)
		var uvo := Vector2(ct.seed * 37.0, ct.seed * 11.0)
		for side in [1.0, -1.0]:
			var nn: Vector3 = nz * side
			for i in range(0, idx.size(), 3):
				var p0 := poly[idx[i]]
				var p1 := poly[idx[i + 1]]
				var p2 := poly[idx[i + 2]]
				B.tri(xf * Vector3(p0.x, p0.y, hz * side), xf * Vector3(p1.x, p1.y, hz * side), xf * Vector3(p2.x, p2.y, hz * side), nn,
					cf, [p0 + uvo, p1 + uvo, p2 + uvo], tx * side)
		var acc := 0.0
		for i in poly.size():
			var p0 := poly[i]
			var p1 := poly[(i + 1) % poly.size()]
			var seg := p1 - p0
			var sl := seg.length()
			if sl < 0.0001:
				continue
			var n2 := Vector2(seg.y, -seg.x) / sl # outward for a counter-clockwise polygon
			var nn := (xf.basis * Vector3(n2.x, n2.y, 0)).normalized()
			var a0 := xf * Vector3(p0.x, p0.y, hz)
			var a1 := xf * Vector3(p1.x, p1.y, hz)
			var b0 := xf * Vector3(p0.x, p0.y, -hz)
			var b1 := xf * Vector3(p1.x, p1.y, -hz)
			B.quad([a0, a1, b1, b0], nn, ce, [Vector2(acc, 0), Vector2(acc + sl, 0), Vector2(acc + sl, 1), Vector2(acc, 1)], (a1 - a0).normalized())
			acc += sl
	return B.commit()


## Indexed triangle buffer with arrays sized up front (the quay flutes: a
## counting pass first, then every vertex written once; wave samples are
## shared by neighbouring segments).
class IBuf:
	var V := PackedVector3Array()
	var N := PackedVector3Array()
	var U := PackedVector2Array()
	var C := PackedColorArray()
	var I := PackedInt32Array()
	var nv := 0
	var ni := 0

	func _init(vcount: int, icount: int) -> void:
		V.resize(vcount)
		N.resize(vcount)
		U.resize(vcount)
		C.resize(vcount)
		I.resize(icount)

	func vert(p: Vector3, n: Vector3, c: Color, uv: Vector2) -> int:
		V[nv] = p
		N[nv] = n
		C[nv] = c
		U[nv] = uv
		nv += 1
		return nv - 1

	## Two triangles over a, b, c, d (around the quad); `flip` turns them so
	## the front face (clockwise in Godot) looks along the wanted normal.
	func quad_idx(a: int, b: int, c: int, d: int, flip: bool) -> void:
		if flip:
			I[ni] = a; I[ni + 1] = c; I[ni + 2] = b
			I[ni + 3] = a; I[ni + 4] = d; I[ni + 5] = c
		else:
			I[ni] = a; I[ni + 1] = b; I[ni + 2] = c
			I[ni + 3] = a; I[ni + 4] = c; I[ni + 5] = d
		ni += 6

	static func flipped(q0: Vector3, q1: Vector3, q2: Vector3, n: Vector3) -> bool:
		return (q1 - q0).cross(q2 - q0).dot(n) > 0.0

	## A flat quad with its own four corners.
	func quad(q: Array, n: Vector3, cols: Array, uvs: Array) -> void:
		var i0 := vert(q[0], n, cols[0], uvs[0])
		vert(q[1], n, cols[1], uvs[1])
		vert(q[2], n, cols[2], uvs[2])
		vert(q[3], n, cols[3], uvs[3])
		quad_idx(i0, i0 + 1, i0 + 2, i0 + 3, flipped(q[0], q[1], q[2], n))

	func commit() -> ArrayMesh:
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = V
		arr[Mesh.ARRAY_NORMAL] = N
		arr[Mesh.ARRAY_TEX_UV] = U
		arr[Mesh.ARRAY_COLOR] = C
		arr[Mesh.ARRAY_INDEX] = I
		var m := ArrayMesh.new()
		if nv > 0:
			m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		return m


## Flute layers of the quay walls (B flute below, C flute above): [y0, y1, pitch].
static func _flute_layers() -> Array:
	var lt := 0.07
	var y_bot := Style.PLATE_Y
	return [[y_bot + lt, -0.5 - lt * 0.5, Style.PITCH * 0.72], [-0.5 + lt * 0.5, -lt, Style.PITCH]]


static func _flute_segs(L: float, pit: float) -> int:
	return maxi(2, int(ceil(L / pit * FLUTE_SAMPLES)))


static var _flute_cache: ArrayMesh = null


## The quay flutes of the map, built once per session (they depend on the
## map only).
static func flute_mesh_cached() -> ArrayMesh:
	if _flute_cache == null:
		_flute_cache = flute_mesh(flute_runs())
	return _flute_cache


## The corrugated cut edges of the base plate (flute_runs) as one indexed
## mesh. COLOR.r = light reaching in (1 at the cut plane), COLOR.g = 1 on
## paper in the cut plane.
static func flute_mesh(runs_list: Array) -> ArrayMesh:
	var lt := 0.07
	var y_bot := Style.PLATE_Y
	var lit := Color(1.0, 0.0, 0, 1)
	var paper := Color(1.0, 1.0, 0, 1)
	var dark := Color(0.12, 0.0, 0, 1)
	var layers := _flute_layers()
	# counting pass: 10 flat quads per run, per layer and sample 4 vertices
	var vc := 0
	var ic := 0
	for run in runs_list:
		var L: float = run.a.distance_to(run.b)
		vc += 40
		ic += 60
		for layer in layers:
			var segs := _flute_segs(L, layer[2])
			vc += 4 * (segs + 1)
			ic += 12 * segs
	var B := IBuf.new(vc, ic)
	for run in runs_list:
		var n: Vector3 = run.n # out of the plate (into the water / off the model)
		var a: Vector3 = run.a
		var d: Vector3 = (run.b - run.a).normalized()
		var L: float = a.distance_to(run.b)
		var inn := -n
		# liner strips in the cut plane
		for yy in [[y_bot, y_bot + lt], [-0.5 - lt * 0.5, -0.5 + lt * 0.5], [-lt, 0.0]]:
			B.quad([_fp(a, d, inn, 0.0, 0.0, yy[0]), _fp(a, d, inn, L, 0.0, yy[0]), _fp(a, d, inn, L, 0.0, yy[1]), _fp(a, d, inn, 0.0, 0.0, yy[1])], n,
				[paper, paper, paper, paper], [Vector2(0, yy[0]), Vector2(L, yy[0]), Vector2(L, yy[1]), Vector2(0, yy[1])])
		# liner faces inside the cavities (seen into the openings)
		for lf in [[y_bot + lt, Vector3.UP], [-0.5 - lt * 0.5, Vector3.DOWN], [-0.5 + lt * 0.5, Vector3.UP], [-lt, Vector3.DOWN]]:
			var y2: float = lf[0]
			B.quad([_fp(a, d, inn, 0.0, 0.0, y2), _fp(a, d, inn, L, 0.0, y2), _fp(a, d, inn, L, KD, y2), _fp(a, d, inn, 0.0, KD, y2)], lf[1],
				[lit, lit, dark, dark], [Vector2(0, 0), Vector2(L, 0), Vector2(L, KD), Vector2(0, KD)])
		# back of the cavities and the end caps
		B.quad([_fp(a, d, inn, 0.0, KD, y_bot), _fp(a, d, inn, L, KD, y_bot), _fp(a, d, inn, L, KD, 0.0), _fp(a, d, inn, 0.0, KD, 0.0)], n,
			[dark, dark, dark, dark], [Vector2(0, 0), Vector2(L, 0), Vector2(L, 1), Vector2(0, 1)])
		for e in [[0.0, d], [L, -d]]:
			B.quad([_fp(a, d, inn, e[0], 0.0, y_bot), _fp(a, d, inn, e[0], 0.0, 0.0), _fp(a, d, inn, e[0], KD, 0.0), _fp(a, d, inn, e[0], KD, y_bot)], e[1],
				[dark, dark, dark, dark], [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
		# the wave sheets: per sample a vertex at the cut plane and one at the
		# back of the cavity (sheet), two in the cut plane (the sheet's paper edge)
		for layer in layers:
			var ya: float = layer[0]
			var yb: float = layer[1]
			var pit: float = layer[2]
			var ym := (ya + yb) * 0.5
			var amp := (yb - ya) * 0.5 - 0.02
			var th := 0.045
			var segs := _flute_segs(L, pit)
			var ph := (a.x + a.z) * TAU / pit
			var k := TAU / pit
			var s0 := B.nv
			for i in segs + 1:
				var u := L * float(i) / segs
				var w := ym + amp * sin(u * k + ph)
				var nw := (Vector3.UP - d * (amp * k * cos(u * k + ph))).normalized()
				B.vert(_fp(a, d, inn, u, 0.0, w), nw, lit, Vector2(u, 0))
				B.vert(_fp(a, d, inn, u, KD, w), nw, dark, Vector2(u, KD))
				B.vert(_fp(a, d, inn, u, 0.0, w - th), n, paper, Vector2(u, w))
				B.vert(_fp(a, d, inn, u, 0.0, w + th), n, paper, Vector2(u, w + 0.1))
			var f_sheet := IBuf.flipped(B.V[s0], B.V[s0 + 4], B.V[s0 + 5], B.N[s0])
			var f_edge := IBuf.flipped(B.V[s0 + 2], B.V[s0 + 6], B.V[s0 + 7], n)
			for i in segs:
				var v0 := s0 + i * 4
				var v1 := v0 + 4
				B.quad_idx(v0, v1, v1 + 1, v0 + 1, f_sheet)
				B.quad_idx(v0 + 2, v1 + 2, v1 + 3, v0 + 3, f_edge)
	return B.commit()


static func _fp(a: Vector3, d: Vector3, inn: Vector3, u: float, dep: float, y: float) -> Vector3:
	return a + d * u + inn * dep + Vector3(0, y, 0)


## A lathe body along `axis` from `base`: prof = [[h, r, (colour)], ...].
static func _lathe(B: Buf, base: Vector3, axis: Vector3, prof: Array, segs: int, col: Color) -> void:
	var ax := axis.normalized()
	var side := ax.cross(Vector3.UP if absf(ax.y) < 0.9 else Vector3.RIGHT).normalized()
	var up2 := side.cross(ax).normalized()
	var z2 := Vector2(0, -1)
	for i in prof.size() - 1:
		var h0: float = prof[i][0]
		var r0: float = prof[i][1]
		var h1: float = prof[i + 1][0]
		var r1: float = prof[i + 1][1]
		var c0: Color = prof[i][2] if prof[i].size() > 2 else col
		for k in segs:
			var a0 := TAU * float(k) / segs
			var a1 := TAU * float(k + 1) / segs
			var d0 := side * cos(a0) + up2 * sin(a0)
			var d1 := side * cos(a1) + up2 * sin(a1)
			var dm := (d0 + d1).normalized()
			var nn: Vector3
			if absf(h1 - h0) < 0.0001:
				nn = ax * (1.0 if r1 < r0 else -1.0)
			else:
				nn = (dm + ax * ((r0 - r1) / (h1 - h0))).normalized()
			B.quad([base + ax * h0 + d0 * r0, base + ax * h0 + d1 * r0, base + ax * h1 + d1 * r1, base + ax * h1 + d0 * r1], nn,
				[c0, c0, c0, c0], [z2, z2, z2, z2])


## Pencil, mug and ruler beyond the model edge, in one mesh with vertex
## colours (amsterdam_props.gdshader picks the surface from COLOR.a).
static func props_mesh() -> ArrayMesh:
	var B := Buf.new()
	# giant pencil (hexagonal, 17.4 m = 17.4 cm), lying on the mat
	var yel := Color(Style.PENCIL, 0.4)
	var wood := Color(Color("d8b48a"), 0.1)
	var lead := Color(Color(0.12, 0.12, 0.13), 0.1)
	var ferr := Color(Color(0.75, 0.75, 0.72), 0.9)
	var eras := Color(Color("c9877c"), 0.1)
	var pr := 0.42
	var pbase := Vector3(PENCIL_X, Style.PLATE_Y + pr * 0.87, 30.0)
	_lathe(B, pbase, Vector3(0.06, 0, 1), [[0.0, 0.0, eras], [0.0, pr * 0.9, eras], [0.8, pr * 0.9, ferr], [0.8, pr * 1.02, ferr], [1.7, pr * 1.02, yel],
		[1.7, pr, yel], [14.6, pr, wood], [16.8, 0.07, lead], [17.4, 0.0, lead]], 6, yel)
	# the mug (12 m = 12 cm high), used as a pencil cup, behind the cut edge at
	# the end of the Westermarkt
	var cer := Color(Style.MUG, 0.6)
	var mb := Vector3(MUG_POS.x, Style.PLATE_Y, MUG_POS.z)
	var R := MUG_R
	var H := MUG_H
	_lathe(B, mb, Vector3.UP, [[0.0, 0.0], [0.0, R - 0.2], [H, R], [H, R - 0.3], [1.0, R - 0.5], [1.0, 0.0]], 40, cer)
	# handle: a bent tube on the east side (seen in profile from the street)
	var hc := mb + Vector3(R + 0.2, H * 0.52, 0)
	var hs := 16
	for i in hs:
		var a0 := -PI * 0.5 + PI * float(i) / hs
		var a1 := -PI * 0.5 + PI * float(i + 1) / hs
		var c0 := hc + Vector3(cos(a0) * 2.6, sin(a0) * 3.0, 0)
		var c1 := hc + Vector3(cos(a1) * 2.6, sin(a1) * 3.0, 0)
		_lathe(B, c0, c1 - c0, [[0.0, 0.5], [c0.distance_to(c1), 0.5]], 10, cer)
	# the pencil in the mug: tip on the mug's floor, leaning out over the rim
	# towards the street and to the west
	var pax := Vector3(-sin(MUG_PENCIL_TILT), cos(MUG_PENCIL_TILT), -0.12).normalized()
	var ptip := mb + Vector3(1.6, 1.0, 1.0)
	_lathe(B, ptip, pax, [[0.0, 0.0, lead], [0.6, 0.07, lead], [2.8, pr, wood], [15.7, pr, yel], [15.7, pr * 1.02, ferr], [16.6, pr * 1.02, ferr],
		[16.6, pr * 0.9, eras], [17.4, pr * 0.9, eras], [17.4, 0.0, eras]], 6, yel)
	# the steel ruler standing in the mug, leaning a little east, face north
	var steel_r := Color(Color(0.7, 0.7, 0.72), 0.9)
	var rup := Vector3(sin(MUG_RULER_TILT), cos(MUG_RULER_TILT), 0.05).normalized()
	var rside := Vector3(cos(MUG_RULER_TILT), -sin(MUG_RULER_TILT), 0.0).normalized()
	var rfront := rside.cross(rup).normalized() # towards -z (the street)
	_slab(B, mb + Vector3(-0.6, 1.0, -0.4), rup, rside, rfront, MUG_RULER_W, 0.12, MUG_RULER_LEN, steel_r)

	# steel ruler (60 m = 60 cm), lying on the mat east of the model
	var y := Style.PLATE_Y + 0.12
	var x0 := RULER_X - 1.6
	var x1 := RULER_X + 1.6
	var z0 := 14.0
	var z1 := 74.0
	var steel := Color(Color(0.7, 0.7, 0.72), 0.9)
	B.quad([Vector3(x0, y, z0), Vector3(x1, y, z0), Vector3(x1, y, z1), Vector3(x0, y, z1)], Vector3.UP, [steel, steel, steel, steel],
		[Vector2(0, 1), Vector2(0, 0.001), Vector2(z1 - z0, 0.001), Vector2(z1 - z0, 1)])
	for zz in [[x0, -1.0], [x1, 1.0]]:
		B.quad([Vector3(zz[0], y - 0.12, z0), Vector3(zz[0], y, z0), Vector3(zz[0], y, z1), Vector3(zz[0], y - 0.12, z1)], Vector3(zz[1], 0, 0),
			[steel, steel, steel, steel], [Vector2(0, -1), Vector2(0, -1), Vector2(0, -1), Vector2(0, -1)])
	return B.commit()


## A flat box (the standing ruler): bottom centre `base`, `up` along its
## length L, `side` across its width w, `front` through its thickness t. The
## broad faces carry the ruler's scale (uv.x = metres along, uv.y across).
static func _slab(B: Buf, base: Vector3, up: Vector3, side: Vector3, front: Vector3, w: float, t: float, L: float, col: Color) -> void:
	var cols := [col, col, col, col]
	var hw := side * w * 0.5
	var ht := front * t * 0.5
	var top := up * L
	for f in [1.0, -1.0]:
		var o: Vector3 = base + ht * f
		B.quad([o - hw, o + hw, o + hw + top, o - hw + top], front * f, cols, [Vector2(0, 1), Vector2(0, 0.001), Vector2(L, 0.001), Vector2(L, 1)])
	for s in [1.0, -1.0]:
		var e: Vector3 = base + hw * s
		B.quad([e - ht, e + ht, e + ht + top, e - ht + top], side * s, cols, [Vector2(0, -1), Vector2(0, -1), Vector2(0, -1), Vector2(0, -1)])
	B.quad([base + top - hw - ht, base + top + hw - ht, base + top + hw + ht, base + top - hw + ht], up, cols, [Vector2(0, -1), Vector2(0, -1), Vector2(0, -1), Vector2(0, -1)])


## Top of the things standing in the mug (m): the ruler.
static func mug_top() -> float:
	return Style.PLATE_Y + 1.0 + MUG_RULER_LEN * Vector3(sin(MUG_RULER_TILT), cos(MUG_RULER_TILT), 0.05).normalized().y


## Per-cell kinds for the floor shader: r = 0 street, 0.25 bridge, 0.5 white
## bridge, 0.75 house/block, 1 water; g = 1 for a north-south bridge deck.
static func kind_image() -> Image:
	var img := Image.create(M.COLS, M.ROWS, false, Image.FORMAT_RGBA8)
	for r in M.ROWS:
		for c in M.COLS:
			var k := kind(r, c)
			var v := 0.75
			var g := 0.0
			match k:
				"street":
					v = 0.0
				"outside":
					v = 1.0 # the notch at the Westermarkt: no plate (discarded like water)
				"bridge":
					var b := M.bridge_at(r, c)
					v = 0.5 if b.id == "magere_brug" else 0.25
					g = 1.0 if b.axis == "ns" else 0.0
				"water":
					v = 1.0
			img.set_pixel(c, r, Color(v, g, 0.0, 1.0))
	return img


## Floor setup (CityTheme.floor_setup_script): the cell kinds, the scans.
static func setup_floor(mat: ShaderMaterial, _maze, _seed: int) -> void:
	mat.set_shader_parameter("kind_tex", ImageTexture.create_from_image(kind_image()))
	mat.set_shader_parameter("maze_size", Vector2(M.COLS, M.ROWS))
	_scan_params(mat)
	mat.set_shader_parameter("tape_alb", Style.tex(Style.TEX_TAPE_ALBEDO))
	mat.set_shader_parameter("white_paint", Style.WHITE_PAINT)


static func _scan_params(mat: ShaderMaterial) -> void:
	mat.set_shader_parameter("foto_alb", Style.tex(Style.TEX_KRAFT_ALBEDO))
	mat.set_shader_parameter("foto_nrm", Style.tex(Style.TEX_KRAFT_NORMAL))
	mat.set_shader_parameter("foto_rgh", Style.tex(Style.TEX_KRAFT_ROUGH))
	mat.set_shader_parameter("foto_m", Style.FOTO_M)
	mat.set_shader_parameter("foto_detail_m", Style.FOTO_DETAIL_M)
	mat.set_shader_parameter("foto_mean", Style.FOTO_MEAN)
	mat.set_shader_parameter("kraft", Style.KRAFT)
	mat.set_shader_parameter("pitch", Style.PITCH)


static func panel_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = PANEL_SHADER
	_scan_params(mat)
	mat.set_shader_parameter("tape_alb", Style.tex(Style.TEX_TAPE_ALBEDO))
	mat.set_shader_parameter("white_paint", Style.WHITE_PAINT)
	mat.set_shader_parameter("exit_paint", Style.EXIT)
	return mat


## One MultiMesh of unit boxes for a list of panels (also used by the exit),
## filled in one go through MultiMesh.buffer (12 transform floats - the basis
## rows with the origin - and 4 custom floats per instance; H6).
static func panel_multimesh(list: Array) -> MultiMesh:
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = box
	mm.instance_count = list.size()
	var buf := PackedFloat32Array()
	buf.resize(list.size() * 16)
	var j := 0
	for p in list:
		var xf: Transform3D = p.xf
		var bx := xf.basis.x
		var by := xf.basis.y
		var bz := xf.basis.z
		buf[j] = bx.x; buf[j + 1] = by.x; buf[j + 2] = bz.x; buf[j + 3] = xf.origin.x
		buf[j + 4] = bx.y; buf[j + 5] = by.y; buf[j + 6] = bz.y; buf[j + 7] = xf.origin.y
		buf[j + 8] = bx.z; buf[j + 9] = by.z; buf[j + 10] = bz.z; buf[j + 11] = xf.origin.z
		buf[j + 12] = p.seed; buf[j + 13] = p.b; buf[j + 14] = p.paint; buf[j + 15] = float(p.flags) / 8.0
		j += 16
	if list.size() > 0:
		mm.buffer = buf
	return mm


## Per level seed: {kit, panels (MultiMesh), cuts (ArrayMesh), glue (MultiMesh)}.
static var _seed_cache := {}


static func _cached(seed: int) -> Dictionary:
	if _seed_cache.has(seed):
		return _seed_cache[seed]
	var K := kit(seed)
	var gmm := MultiMesh.new()
	gmm.transform_format = MultiMesh.TRANSFORM_3D
	var sm := SphereMesh.new()
	sm.radial_segments = 16
	sm.rings = 8
	gmm.mesh = sm
	gmm.instance_count = K.glue.size()
	var grng := RandomNumberGenerator.new()
	grng.seed = seed + 7
	for i in K.glue.size():
		var gr: float = K.glue[i][1]
		gmm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, grng.randf() * TAU) * Basis.from_scale(Vector3(gr * 2.6, gr * 0.3, gr * 1.4)), K.glue[i][0]))
	var c := {"kit": K, "panels": panel_multimesh(K.panels), "cuts": cut_mesh(K.cuts), "glue": gmm}
	_seed_cache[seed] = c
	return c


static func build(_maze, _city_theme, seed: int) -> Node3D:
	var root := Node3D.new()
	root.name = "AmsterdamScenery"
	root.set_script(RootScript)
	var cache := _cached(seed)
	var K: Kit = cache.kit

	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Panels"
	mmi.multimesh = cache.panels
	mmi.material_override = panel_material()
	root.add_child(mmi)
	root.panel_count = K.panels.size()

	var cut := MeshInstance3D.new()
	cut.name = "Cuts"
	cut.mesh = cache.cuts
	var cm := ShaderMaterial.new()
	cm.shader = CUT_SHADER
	_scan_params(cm)
	cm.set_shader_parameter("white_paint", Style.WHITE_PAINT)
	cm.set_shader_parameter("exit_paint", Style.EXIT)
	cut.material_override = cm
	root.add_child(cut)
	root.cut_count = K.cuts.size()

	var fl := MeshInstance3D.new()
	fl.name = "Flutes"
	fl.mesh = flute_mesh_cached()
	var fm := ShaderMaterial.new()
	fm.shader = FLUTE_SHADER
	_scan_params(fm)
	fl.material_override = fm
	root.add_child(fl)

	var water := MeshInstance3D.new()
	water.name = "Water"
	var wp := PlaneMesh.new()
	wp.size = Vector2(PLATE_X1 - PLATE_X0, PLATE_Z1 - PLATE_Z0)
	water.mesh = wp
	water.position = Vector3((PLATE_X0 + PLATE_X1) * 0.5, Style.WATER_Y, (PLATE_Z0 + PLATE_Z1) * 0.5)
	var wm := ShaderMaterial.new()
	wm.shader = WATER_SHADER
	wm.set_shader_parameter("lacquer", Style.WATER)
	wm.set_shader_parameter("tape_nrm", Style.tex(Style.TEX_TAPE_NORMAL))
	wm.set_shader_parameter("cut_rect", Vector4(M.CUT.c0 * CELL - 1.0, M.CUT.r0 * CELL - 1.0, M.CUT.c1 * CELL + 1.0, M.CUT.r1 * CELL + 1.0))

	water.material_override = wm
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(water)

	# the desk: cutting mat, wooden table top, pencil / mug / ruler
	var mat := MeshInstance3D.new()
	mat.name = "CuttingMat"
	var mb := BoxMesh.new()
	mb.size = Vector3(MAT_SIZE.x, 0.3, MAT_SIZE.y)
	mat.mesh = mb
	mat.position = Vector3(MAT_CENTER.x, Style.PLATE_Y - 0.15, MAT_CENTER.y)
	var mm2 := ShaderMaterial.new()
	mm2.shader = MAT_SHADER
	mm2.set_shader_parameter("base", Style.MAT)
	mat.material_override = mm2
	mat.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mat)

	var desk := MeshInstance3D.new()
	desk.name = "Desk"
	var db := BoxMesh.new()
	db.size = Vector3(420.0, 4.0, 320.0)
	desk.mesh = db
	desk.position = Vector3(48.0, Style.TABLE_Y - 2.0, 48.0)
	var wood := StandardMaterial3D.new()
	wood.albedo_texture = Style.tex(Style.TEX_WOOD_ALBEDO)
	wood.normal_enabled = true
	wood.normal_texture = Style.tex(Style.TEX_WOOD_NORMAL)
	wood.normal_scale = 0.6
	wood.roughness_texture = Style.tex(Style.TEX_WOOD_ROUGH)
	wood.roughness = 1.0
	wood.uv1_triplanar = true
	wood.uv1_scale = Vector3(1.0 / 110.0, 1.0 / 110.0, 1.0 / 55.0)
	wood.albedo_color = Color(0.5, 0.36, 0.25) # the scan is light pine; the desk is darker oak (#6E5139)
	desk.material_override = wood
	desk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(desk)

	var props := MeshInstance3D.new()
	props.name = "DeskThings"
	props.mesh = props_mesh()
	var pm := ShaderMaterial.new()
	pm.shader = PROPS_SHADER
	props.material_override = pm
	root.add_child(props)

	var glue := MultiMeshInstance3D.new()
	glue.name = "Glue"
	glue.multimesh = cache.glue
	var gm := ShaderMaterial.new()
	gm.shader = GLUE_SHADER
	glue.material_override = gm
	glue.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(glue)

	# trunks are obstacles (wall layer): no squeezing between tree and quay
	var tb := StaticBody3D.new()
	tb.name = "TreeBlocks"
	tb.collision_layer = 2
	tb.collision_mask = 0
	for p in K.trees:
		var shape := BoxShape3D.new()
		shape.size = Vector3(TREE_BOX, 2.4, TREE_BOX)
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.position = p + Vector3(0, 1.2, 0)
		tb.add_child(cs)
	root.add_child(tb)
	root.tree_count = K.trees.size()

	# ---- evening light ----
	# The sun is the only shadow caster (QA W3, code W2): a hard light source
	# (angular distance 0 - PCSS would cost a search per pixel), the soft
	# rim comes from shadow_blur; two splits are enough for a 130 m model.
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = Style.SUN_COLOR
	sun.light_energy = 2.0
	sun.shadow_enabled = true
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	sun.shadow_blur = 1.6
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_split_1 = 0.22
	sun.directional_shadow_max_distance = 130.0
	sun.directional_shadow_fade_start = 0.85
	sun.light_angular_distance = 0.0
	root.add_child(sun)
	sun.transform = Transform3D(Basis.looking_at(Style.SUN_DIR.normalized(), Vector3.UP), Vector3.ZERO)
	var bounce := DirectionalLight3D.new()
	bounce.name = "Bounce"
	bounce.light_color = Style.BOUNCE_COLOR
	bounce.light_energy = 0.3
	bounce.light_specular = 0.0
	bounce.shadow_enabled = false
	root.add_child(bounce)
	bounce.transform = Transform3D(Basis.looking_at(Vector3(0.2, 1.0, 0.1).normalized(), Vector3.FORWARD), Vector3.ZERO)
	var lamp := SpotLight3D.new()
	lamp.name = "DeskLamp"
	lamp.light_color = Style.LAMP_COLOR
	lamp.light_energy = 0.55
	lamp.spot_range = 420.0
	lamp.spot_angle = 17.0
	lamp.spot_attenuation = 0.0
	lamp.spot_angle_attenuation = 1.6
	# no shadows from the lamp: its light comes from high behind the west side
	# and only warms the model (the sun draws the long shadows)
	lamp.shadow_enabled = false

	root.add_child(lamp)
	lamp.transform = Transform3D(Basis.looking_at((LAMP_TARGET - LAMP_POS).normalized(), Vector3.UP), LAMP_POS)
	root.sun = sun
	root.lamp = lamp
	root.bounce = bounce
	return root
