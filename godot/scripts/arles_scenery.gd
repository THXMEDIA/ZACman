extends RefCounted
## ArlesScenery — builds the painted night city of the Arles Explorer
## (CityTheme.scenery_builder_script, see city_themes.gd arles(); spec
## docs/design/arles-explorer.md; art: direction B v2, prototype
## tools/art/explorer_proto/arles_v2 on the art branch). Built in map space
## (world + (1, 0, 1), the prototype's coordinates) under the node "City",
## merged into a handful of draw calls:
##   Houses    every house of the street grid, the far city and the far bank
##             as ONE mesh (arles_facade.gdshader: windows, shutters, shops,
##             doors, plinth row, cornice, painted window glow)
##   Objects   landmarks, lamps, props, figures, trees, cypresses, quay, far
##             silhouettes as ONE mesh (arles_obj.gdshader; the brush material
##             index rides in UV2.x, the table is ArlesStyle.MATS)
##   Arcades   the amphitheatre's outer shell (arches cut in the shader)
##   Tympanum  the relief hint over the portal of Saint-Trophime
##   Rhône     water with the mirrored lamps (arles_water.gdshader)
##   Sky       the swirl sky, baked once at level start (arles_root.gd)
##   Halos     every lamp, star and the moon as ONE MultiMesh
## Light: the moon (directional, no shadow) and 6 omni lights without shadow
## in the city (+1 green one in the exit = 7, technical condition <= 8); all
## other lamps and every window only paint light pools / glow in the shaders
## (per 4 m tile the nearest 8 lamps, tile list in a texture).
## Everything that reaches into the walkable space below eye height (lamp
## posts, trees, the café terrace, statue, obelisk, steps, figures, the cart)
## gets a collision box (node "Obstacles", wall layer): what you see is what
## stops you. Variation from the level seed only.

const M := preload("res://scripts/arles_maze.gd")
const Style := preload("res://scripts/arles_style.gd")
const RootScript := preload("res://scripts/arles_root.gd")
const OBJ_SHADER := preload("res://shaders/arles_obj.gdshader")
const FACADE_SHADER := preload("res://shaders/arles_facade.gdshader")
const WATER_SHADER := preload("res://shaders/arles_water.gdshader")
const SKY_SHADER := preload("res://shaders/arles_sky.gdshader")
const SKY_BAKE_SHADER := preload("res://shaders/arles_sky_bake.gdshader")
const HALO_SHADER := preload("res://shaders/arles_halo.gdshader")
const ARCADE_SHADER := preload("res://shaders/arles_arcade.gdshader")
const TYMPANON_SHADER := preload("res://shaders/arles_tympanon.gdshader")

const CELL := 2.0
## World = map - MAP_SHIFT (the City node sits at -MAP_SHIFT).
const MAP_SHIFT := Vector3(1.0, 0.0, 1.0)
## Everything below this height in an open cell is in the player's way.
const EYE := 1.9
## Paint-thin details may reach this far from a wall into a street (m).
const WALL_TOL := 0.12
const OBSTACLE_TOP := 2.4

## Pool tile grid (map space): origin, tile size, count (arles_common).
const TILE_ORIGIN := Vector2(-16.0, -16.0)
const TILE_SIZE := 4.0
const TILE_COUNT := Vector2i(32, 30)
const TILE_LAMPS := 8
const POOL_RADIUS := 15.0

## Amphitheatre (map space): centre, half axes, height.
const ARENA_C := Vector2(68.0, 45.0)
const ARENA_A := 13.6
const ARENA_B := 14.6
const ARENA_H := 13.0
const PLINTH_H := 0.6

## Gas lamp posts on streets and squares (map x, z), as in the prototype.
const POSTS := [
	# Rue de la Calade
	Vector2(46.0, 68.6), Vector2(56.0, 68.6), Vector2(51.0, 73.4), Vector2(57.5, 73.4),
	# Place de la République
	Vector2(18.6, 65.0), Vector2(40.4, 64.6), Vector2(40.4, 75.4), Vector2(18.6, 75.0),
	# Rue de l'Hôtel de Ville
	Vector2(24.6, 56.0), Vector2(29.4, 61.0),
	# Place du Forum
	Vector2(16.6, 33.0), Vector2(16.6, 50.6), Vector2(37.4, 50.6), Vector2(37.4, 37.0),
	# Rue du Forum
	Vector2(11.0, 43.4), Vector2(42.0, 38.6), Vector2(46.0, 43.4),
	# Place Lamartine, lane to the baths, Rue de la Cavalerie
	Vector2(24.0, 15.4), Vector2(33.0, 2.6), Vector2(20.0, 18.6), Vector2(48.6, 15.4), Vector2(53.4, 18.0),
	# Rond-point des Arènes
	Vector2(60.0, 24.6), Vector2(78.0, 24.6), Vector2(60.0, 65.4), Vector2(78.0, 65.4), Vector2(48.6, 34.0),
	Vector2(48.6, 55.0), Vector2(87.4, 36.0), Vector2(87.4, 54.0),
	# the two wall lamps of the Yellow House
	Vector2(11.6, 2.5), Vector2(18.4, 2.5),
]
const POST_H := 3.4
## Lamps on the quay parapet: higher, mirrored in the Rhône.
const QUAY_LAMPS_Z := [7.0, 17.0, 27.0, 37.0, 47.0, 57.0, 67.0]
const QUAY_LAMP_X := 1.75
## The real lights (omni, no shadow): café, statue, portal, arena, 2 x quay.
const OMNI := [
	{"name": "Cafe", "pos": Vector3(29.5, 2.6, 32.5), "col": "ffc24a", "e": 2.4, "r": 11.0},
	{"name": "Statue", "pos": Vector3(29.0, 1.2, 47.5), "col": "ffc870", "e": 1.0, "r": 7.0},
	{"name": "Portal", "pos": Vector3(28.0, 4.8, 71.5), "col": "ffc870", "e": 1.4, "r": 9.0},
	{"name": "Arena", "pos": Vector3(51.4, 4.5, 42.0), "col": "ffb850", "e": 1.6, "r": 14.0},
	{"name": "QuayNorth", "pos": Vector3(2.6, 4.2, 17.0), "col": "ffc24a", "e": 1.6, "r": 12.0},
	{"name": "QuaySouth", "pos": Vector3(2.6, 4.2, 47.0), "col": "ffc24a", "e": 1.6, "r": 12.0},
]
const MOON_ROT_DEG := Vector3(-38.0, 35.0, 0.0)
## Sky sphere (map space).
const SKY_CENTER := Vector3(45.0, -40.0, 41.0)
const SKY_RADIUS := 650.0


## ---------------------------------------------------------------- mesh kit
## Collects primitives into ONE indexed mesh (vertex, normal, UV2.x = brush
## material index) and records every part's map-space AABB with its group.
class Buf:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uv2 := PackedVector2Array()
	var idx := PackedInt32Array()
	var parts: Array = [] # {"aabb": AABB, "group": String, "mat": String}
	var group := ""
	var _cache := {}
	var _mids := {}

	func _mid(m: String) -> float:
		if not _mids.has(m):
			var i := Style.mat_index(m)
			assert(i >= 0, "unknown brush material " + m)
			_mids[m] = float(i)
		return _mids[m]

	func add_arrays(arr: Array, xf: Transform3D, m: String) -> void:
		var mi := _mid(m)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var ix: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var base := verts.size()
		var nb := xf.basis.inverse().transposed()
		var lo := Vector3(INF, INF, INF)
		var hi := Vector3(-INF, -INF, -INF)
		for i in v.size():
			var p := xf * v[i]
			verts.append(p)
			norms.append((nb * n[i]).normalized())
			uv2.append(Vector2(mi, 0.0))
			lo = lo.min(p)
			hi = hi.max(p)
		for k in ix:
			idx.append(base + k)
		parts.append({"aabb": AABB(lo, hi - lo), "group": group, "mat": m})

	func _prim(key: String, make: Callable) -> Array:
		if not _cache.has(key):
			var pm: PrimitiveMesh = make.call()
			_cache[key] = pm.get_mesh_arrays()
		return _cache[key]

	func box(c: Vector3, s: Vector3, m: String, basis := Basis()) -> void:
		var arr := _prim("box", func():
			var b := BoxMesh.new()
			b.size = Vector3.ONE
			return b)
		add_arrays(arr, Transform3D(basis * Basis.from_scale(s), c), m)

	func cyl(c: Vector3, r_top: float, r_bot: float, h: float, m: String, segs := 16, basis := Basis(), caps := true) -> void:
		var key := "cyl%f_%f_%d_%s" % [r_top, r_bot, segs, caps]
		var arr := _prim(key, func():
			var cm := CylinderMesh.new()
			cm.top_radius = r_top
			cm.bottom_radius = r_bot
			cm.height = 1.0
			cm.radial_segments = segs
			cm.rings = 1
			cm.cap_top = caps
			cm.cap_bottom = caps
			return cm)
		add_arrays(arr, Transform3D(basis * Basis.from_scale(Vector3(1, h, 1)), c), m)

	func sphere(c: Vector3, r: float, m: String, sc := Vector3.ONE, segs := 16, basis := Basis()) -> void:
		var key := "sph%d" % segs
		var arr := _prim(key, func():
			var sm := SphereMesh.new()
			sm.radius = 1.0
			sm.height = 2.0
			sm.radial_segments = segs
			sm.rings = maxi(segs / 2, 4)
			return sm)
		add_arrays(arr, Transform3D(basis * Basis.from_scale(sc * r), c), m)

	## Triangular prism: base line at pos.y, apex at pos.y + h (gables).
	func prism(pos: Vector3, w: float, h: float, depth: float, m: String, rot_y := 0.0) -> void:
		var arr := _prim("prism", func():
			var pm := PrismMesh.new()
			pm.size = Vector3.ONE
			return pm)
		add_arrays(arr, Transform3D(Basis(Vector3.UP, rot_y) * Basis.from_scale(Vector3(w, h, depth)), pos + Vector3(0, h * 0.5, 0)), m)

	## A passer-by: capsule body and a round head, feet on pos.y.
	func figure(pos: Vector3, body: String, head: String, rot_y := 0.0, h := 1.7) -> void:
		var k := h / 1.7
		var arr := _prim("capsule", func():
			var cm := CapsuleMesh.new()
			cm.radius = 0.19
			cm.height = 1.15
			cm.radial_segments = 12
			cm.rings = 4
			return cm)
		add_arrays(arr, Transform3D(Basis(Vector3.UP, rot_y) * Basis.from_scale(Vector3(k, k, k)), pos + Vector3(0, 0.78 * k, 0)), body)
		sphere(pos + Vector3(0, 1.52 * k, 0), 0.13 * k, head, Vector3.ONE, 12)

	func commit() -> ArrayMesh:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = norms
		arrays[Mesh.ARRAY_TEX_UV2] = uv2
		arrays[Mesh.ARRAY_INDEX] = idx
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return mesh


## Houses: quads with vertex colour (palette, lot seed, eave, lit share).
class Houses:
	var st := SurfaceTool.new()
	var count := 0
	var boxes: Array = [] # map-space AABBs of free boxes (tests)

	func _init() -> void:
		st.begin(Mesh.PRIMITIVE_TRIANGLES)

	func tri(a: Vector3, b: Vector3, d: Vector3, n: Vector3, col: Color) -> void:
		if (b - a).cross(d - a).dot(n) > 0.0:
			var t := b
			b = d
			d = t
		for p in [a, b, d]:
			st.set_color(col)
			st.set_normal(n)
			st.add_vertex(p)

	func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, col: Color) -> void:
		tri(a, b, c, n, col)
		tri(a, c, d, n, col)

	## A free box of houses (landmark neighbours, far city, far bank).
	func box(x0: float, x1: float, z0: float, z1: float, h: float, pal: int, seed: float, lit := 1.0) -> void:
		var col := Color(float(pal) / 8.0, seed, h / 20.0, lit)
		quad(Vector3(x0, h, z0), Vector3(x1, h, z0), Vector3(x1, h, z1), Vector3(x0, h, z1), Vector3.UP, col)
		quad(Vector3(x0, 0, z0), Vector3(x1, 0, z0), Vector3(x1, h, z0), Vector3(x0, h, z0), Vector3(0, 0, -1), col)
		quad(Vector3(x0, 0, z1), Vector3(x1, 0, z1), Vector3(x1, h, z1), Vector3(x0, h, z1), Vector3(0, 0, 1), col)
		quad(Vector3(x0, 0, z0), Vector3(x0, 0, z1), Vector3(x0, h, z1), Vector3(x0, h, z0), Vector3(-1, 0, 0), col)
		quad(Vector3(x1, 0, z0), Vector3(x1, 0, z1), Vector3(x1, h, z1), Vector3(x1, h, z0), Vector3(1, 0, 0), col)
		boxes.append(AABB(Vector3(x0, 0, z0), Vector3(x1 - x0, h, z1 - z0)))
		count += 1


## ---------------------------------------------------------------- helpers
static func to_world(p: Vector3) -> Vector3:
	return p - MAP_SHIFT


## Map-space cell of a map-space point.
static func cell_of_map(p: Vector3) -> Vector2i:
	return Vector2i(int(floor(p.z / CELL)), int(floor(p.x / CELL)))


static func lot(r: int, c: int) -> Vector2i:
	return Vector2i(r / 3, c / 3)


static func lot_hash(v: Vector2i, k: float) -> float:
	var x := sin(float(v.x) * 127.1 + float(v.y) * 311.7 + k * 74.7) * 43758.5453
	return x - floor(x)


static func roof_y(x: float, z: float, lt: Vector2i, h: float, ridge_x: bool) -> float:
	var lzc := float(lt.x) * 6.0 + 3.0
	var lxc := float(lt.y) * 6.0 + 3.0
	if ridge_x:
		return h + 1.3 * (1.0 - clampf(absf(z - lzc) / 3.0, 0.0, 1.0))
	return h + 1.3 * (1.0 - clampf(absf(x - lxc) / 3.0, 0.0, 1.0))


## Eave height of a house cell (7-11.5 m per 6 x 6 m lot).
static func eave(r: int, c: int) -> float:
	return 7.0 + lot_hash(lot(r, c), 1.0) * 4.5


## ---------------------------------------------------------------- lamps
## Every gas lamp: [top position (map), is on the quay].
static func lamp_heads() -> Array:
	var out: Array = []
	for p in POSTS:
		out.append([Vector3(p.x, POST_H + 0.3, p.y), false])
	for z in QUAY_LAMPS_Z:
		out.append([Vector3(QUAY_LAMP_X, 1.1 + 3.6 + 0.3, z), true])
	return out


## The lamps that paint light pools (xyz map, w strength): all gas lamps,
## the big café lantern and the lit clock face.
static func pool_lamps() -> Array:
	var out: Array = []
	for l in lamp_heads():
		var p: Vector3 = l[0]
		out.append(Vector4(p.x, p.y, p.z, 1.25))
	out.append(Vector4(31.4, 4.0, 31.0, 2.2))
	out.append(Vector4(16.5, 19.5, 70.0, 0.6))
	return out


static var _lamp_tex: ImageTexture = null
static var _tile_tex: ImageTexture = null
static var _tile_max := 0


## The pool lamps as a float texture and the per-tile list of the nearest 8.
static func pool_textures() -> Array:
	if _lamp_tex != null:
		return [_lamp_tex, _tile_tex]
	var lamps := pool_lamps()
	var li := Image.create(lamps.size(), 1, false, Image.FORMAT_RGBAF)
	for i in lamps.size():
		var l: Vector4 = lamps[i]
		li.set_pixel(i, 0, Color(l.x, l.y, l.z, l.w))
	_lamp_tex = ImageTexture.create_from_image(li)
	var ti := Image.create(TILE_COUNT.x * 2, TILE_COUNT.y, false, Image.FORMAT_RGBA8)
	for tz in TILE_COUNT.y:
		for tx in TILE_COUNT.x:
			var ids := tile_lamps(tx, tz, lamps)
			_tile_max = maxi(_tile_max, ids.size())
			for k in 2:
				var v := [0, 0, 0, 0]
				for j in 4:
					var n := k * 4 + j
					if n < ids.size():
						v[j] = int(ids[n]) + 1
				ti.set_pixel(tx * 2 + k, tz, Color8(v[0], v[1], v[2], v[3]))
	_tile_tex = ImageTexture.create_from_image(ti)
	return [_lamp_tex, _tile_tex]


## Indices of the (at most 8) lamps nearest to tile (tx, tz) whose pool
## reaches it.
static func tile_lamps(tx: int, tz: int, lamps: Array) -> Array:
	var x0 := TILE_ORIGIN.x + tx * TILE_SIZE
	var z0 := TILE_ORIGIN.y + tz * TILE_SIZE
	var ctr := Vector2(x0 + TILE_SIZE * 0.5, z0 + TILE_SIZE * 0.5)
	var cand: Array = []
	for i in lamps.size():
		var l: Vector4 = lamps[i]
		var dx := maxf(maxf(x0 - l.x, 0.0), l.x - (x0 + TILE_SIZE))
		var dz := maxf(maxf(z0 - l.z, 0.0), l.z - (z0 + TILE_SIZE))
		if Vector2(dx, dz).length() < POOL_RADIUS:
			cand.append([Vector2(l.x, l.z).distance_to(ctr), i])
	cand.sort_custom(func(a, b): return a[0] < b[0])
	var out: Array = []
	for k in mini(cand.size(), TILE_LAMPS):
		out.append(cand[k][1])
	return out


static func set_pool_params(sm: ShaderMaterial) -> void:
	var tx := pool_textures()
	sm.set_shader_parameter("lamp_tex", tx[0])
	sm.set_shader_parameter("tile_tex", tx[1])
	sm.set_shader_parameter("tile_grid", Vector4(TILE_ORIGIN.x, TILE_ORIGIN.y, TILE_SIZE, 0.0))
	sm.set_shader_parameter("tile_count", Vector2(TILE_COUNT.x, TILE_COUNT.y))
	sm.set_shader_parameter("lamp_col", Vector3(Style.LAMP_POOL.r, Style.LAMP_POOL.g, Style.LAMP_POOL.b))
	sm.set_shader_parameter("lod_near", Style.LOD_NEAR)
	sm.set_shader_parameter("lod_far", Style.LOD_FAR)


static func obj_material() -> ShaderMaterial:
	var sm := ShaderMaterial.new()
	sm.shader = OBJ_SHADER
	Style.apply_mat_table(sm)
	set_pool_params(sm)
	return sm


static func facade_material() -> ShaderMaterial:
	var sm := ShaderMaterial.new()
	sm.shader = FACADE_SHADER
	var pa := PackedVector3Array()
	var pb := PackedVector3Array()
	var pc := PackedVector3Array()
	for i in 6:
		pa.append(Style.lin(Style.FACADE_A[i]))
		pb.append(Style.lin(Style.FACADE_B[i]))
		pc.append(Style.lin(Style.FACADE_C[i]))
	var ra := PackedVector3Array()
	var rb := PackedVector3Array()
	for i in 4:
		ra.append(Style.lin(Style.ROOF_A[i]))
		rb.append(Style.lin(Style.ROOF_B[i]))
	sm.set_shader_parameter("pal_a", pa)
	sm.set_shader_parameter("pal_b", pb)
	sm.set_shader_parameter("pal_c", pc)
	sm.set_shader_parameter("roof_a", ra)
	sm.set_shader_parameter("roof_b", rb)
	sm.set_shader_parameter("roof_c", Style.lin(Style.ROOF_DARK))
	sm.set_shader_parameter("lit_ratio", Style.LIT_RATIO)
	sm.set_shader_parameter("win_a", Style.lin(Style.WINDOW))
	sm.set_shader_parameter("win_b", Style.lin(Style.WINDOW_B))
	sm.set_shader_parameter("win_c", Style.lin(Style.WINDOW_C))
	sm.set_shader_parameter("shut_a", Style.lin(Style.SHUTTER_A))
	sm.set_shader_parameter("shut_b", Style.lin(Style.SHUTTER_B))
	sm.set_shader_parameter("glass", Style.lin(Style.GLASS))
	sm.set_shader_parameter("door_col", Style.lin(Style.DOOR))
	set_pool_params(sm)
	return sm


## Floor setup (CityTheme.floor_setup_script): calm paving, gutter on the
## block edge, light pools.
static func setup_floor(mat: ShaderMaterial, _maze, _seed: int) -> void:
	mat.set_shader_parameter("maze_size", Vector2(M.COLS, M.ROWS))
	mat.set_shader_parameter("pave_a", Style.PAVE[0])
	mat.set_shader_parameter("pave_b", Style.PAVE[1])
	mat.set_shader_parameter("pave_c", Style.PAVE[2])
	mat.set_shader_parameter("gutter", Style.GUTTER)
	mat.set_shader_parameter("kerb", Style.KERB)
	mat.set_shader_parameter("outside", Style.OUTSIDE)
	set_pool_params(mat)


## ---------------------------------------------------------------- houses
static func houses(seed: int) -> Houses:
	var H := Houses.new()
	for r in M.ROWS:
		for c in M.COLS:
			if not M.is_house(r, c):
				continue
			var lt := lot(r, c)
			var h := eave(r, c)
			var rx := lot_hash(lt, 2.0) < 0.5
			var pal: int = Style.FACADE_PICK[int(lot_hash(lt, 3.0) * 10.0) % 10]
			var col := Color(float(pal) / 8.0, lot_hash(lt, 4.0), h / 20.0, 1.0)
			var x0 := c * CELL
			var z0 := r * CELL
			# roof in two halves across the ridge, so the ridge is an edge
			for k in 2:
				var xa := x0 + (0.0 if rx else float(k))
				var xb := x0 + (2.0 if rx else float(k) + 1.0)
				var za := z0 + (float(k) if rx else 0.0)
				var zb := z0 + (float(k) + 1.0 if rx else 2.0)
				var p1 := Vector3(xa, roof_y(xa, za, lt, h, rx), za)
				var p2 := Vector3(xb, roof_y(xb, za, lt, h, rx), za)
				var p3 := Vector3(xb, roof_y(xb, zb, lt, h, rx), zb)
				var p4 := Vector3(xa, roof_y(xa, zb, lt, h, rx), zb)
				var n := (p2 - p1).cross(p4 - p1).normalized()
				if n.y < 0:
					n = -n
				H.quad(p1, p2, p3, p4, n, col)
			# walls wherever the neighbour is not a house cell of the same lot
			for sd in [[Vector2i(-1, 0), Vector3(0, 0, -1)], [Vector2i(1, 0), Vector3(0, 0, 1)], [Vector2i(0, -1), Vector3(-1, 0, 0)], [Vector2i(0, 1), Vector3(1, 0, 0)]]:
				var d: Vector2i = sd[0]
				var n: Vector3 = sd[1]
				var nr := r + d.x
				var nc := c + d.y
				if M.is_house(nr, nc) and lot(nr, nc) == lt:
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
					H.quad(a, b, Vector3(b.x, roof_y(b.x, b.z, lt, h, rx), b.z), Vector3(a.x, roof_y(a.x, a.z, lt, h, rx), a.z), n, col)
	# houses next to landmarks
	H.box(22.0, 32.0, 22.0, 30.0, 10.5, 0, 0.71) # the café's house (Place du Forum north)
	H.box(14.0, 18.0, 22.0, 30.0, 9.5, 2, 0.33) # house with the Roman columns
	H.box(10.0, 16.0, 64.0, 76.0, 12.0, 5, 0.52) # Hôtel de Ville
	H.box(10.0, 12.0, -6.0, 2.0, 9.0, 3, 0.18) # neighbours of the Yellow House
	H.box(18.0, 22.0, -6.0, 2.0, 10.0, 3, 0.81)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	# the far bank (Trinquetaille): low houses with lit windows
	for z in range(-60, 150, 7):
		var h := rng.randf_range(5.0, 10.0)
		var x0 := -86.0 - rng.randf_range(0, 6)
		H.box(x0, -70.5, float(z), float(z) + rng.randf_range(5.0, 7.0), h, [0, 2, 3, 4][rng.randi() % 4], rng.randf(), 0.8)
	# the town around the map (the stroke LOD turns it into soft dabs)
	for k in 40:
		var x := rng.randf_range(92.0, 170.0)
		var z := rng.randf_range(-40.0, 130.0)
		H.box(x, x + rng.randf_range(6, 10), z, z + rng.randf_range(6, 10), rng.randf_range(7, 12), rng.randi() % 6, rng.randf(), 0.6)
	for k in 36:
		var x := rng.randf_range(0.0, 95.0)
		var z := rng.randf_range(84.0, 140.0)
		if x > 18.0 and x < 38.0 and z < 95.0:
			continue # Saint-Trophime's crossing tower stays free
		H.box(x, x + rng.randf_range(6, 10), z, z + rng.randf_range(6, 10), rng.randf_range(7, 12), rng.randi() % 6, rng.randf(), 0.6)
	for k in 30:
		var x := rng.randf_range(4.0, 95.0)
		var z := rng.randf_range(-45.0, -18.0)
		H.box(x, x + rng.randf_range(6, 10), z, z + rng.randf_range(6, 10), rng.randf_range(7, 12), rng.randi() % 6, rng.randf(), 0.6)
	return H


## ---------------------------------------------------------------- objects
static func crenels(B: Buf, center: Vector3, sx: float, sz: float, m: String, step_ := 1.1) -> void:
	var nx := int(sx / step_)
	var nz := int(sz / step_)
	for i in nx:
		if i % 2 == 0:
			var x := center.x - sx / 2 + (float(i) + 0.5) * sx / nx
			B.box(Vector3(x, center.y + 0.4, center.z - sz / 2 + 0.2), Vector3(sx / nx, 0.8, 0.4), m)
			B.box(Vector3(x, center.y + 0.4, center.z + sz / 2 - 0.2), Vector3(sx / nx, 0.8, 0.4), m)
	for i in nz:
		if i % 2 == 0:
			var z := center.z - sz / 2 + (float(i) + 0.5) * sz / nz
			B.box(Vector3(center.x - sx / 2 + 0.2, center.y + 0.4, z), Vector3(0.4, 0.8, sz / nz), m)
			B.box(Vector3(center.x + sx / 2 - 0.2, center.y + 0.4, z), Vector3(0.4, 0.8, sz / nz), m)


static func round_crenels(B: Buf, center: Vector3, r: float, m: String) -> void:
	var n := int(TAU * r / 1.0)
	for i in n:
		if i % 2 == 0:
			var a := float(i) / float(n) * TAU
			B.box(center + Vector3(cos(a) * (r - 0.2), 0.4, sin(a) * (r - 0.2)), Vector3(0.4, 0.8, TAU * r / n), m, Basis(Vector3.UP, -a))


## Half-circle arch of stones (archivolt) in the x-y plane.
static func arch_ring(B: Buf, center: Vector3, r: float, thick: float, depth: float, m: String, n := 12) -> void:
	for i in n:
		var a := PI * (float(i) + 0.5) / float(n)
		B.box(center + Vector3(cos(a) * r, sin(a) * r, 0), Vector3(thick, PI * r / n * 1.02, depth), m, Basis(Vector3.BACK, a))


static func column(B: Buf, base: Vector3, h: float, r: float, m: String) -> void:
	B.cyl(base + Vector3(0, h / 2, 0), r * 0.9, r, h, m, 12)
	B.box(base + Vector3(0, h + 0.25, 0), Vector3(r * 2.6, 0.5, r * 2.6), m)
	B.box(base + Vector3(0, 0.15, 0), Vector3(r * 2.4, 0.3, r * 2.4), m)


static func lamp(B: Buf, pos: Vector3, h: float) -> void:
	B.cyl(pos + Vector3(0, h / 2, 0), 0.07, 0.12, h, "post", 8)
	B.box(pos + Vector3(0, h + 0.3, 0), Vector3(0.36, 0.5, 0.36), "glass")
	B.box(pos + Vector3(0, h + 0.6, 0), Vector3(0.5, 0.08, 0.5), "post")


static func cypress(B: Buf, pos: Vector3, h: float, rng: RandomNumberGenerator, m := "cypress") -> void:
	var y := 1.0
	var r := h * 0.16
	while y < h:
		var rr := r * (1.0 - pow(y / h, 1.6)) + 0.25
		B.sphere(pos + Vector3(rng.randf_range(-0.2, 0.2), y + rr * 0.6, rng.randf_range(-0.2, 0.2)), rr, m, Vector3(1.0, 1.9, 1.0), 12, Basis(Vector3.UP, rng.randf() * TAU))
		y += rr * 1.5


## All single objects of the city in map space. Returns the Buf (mesh data,
## parts with groups for the obstacle boxes).
static func objects(seed: int) -> Buf:
	var B := Buf.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	# ---- gas lamps (posts) and the quay lamps on the parapet
	for i in POSTS.size():
		B.group = "lamp%d" % i
		lamp(B, Vector3(POSTS[i].x, 0, POSTS[i].y), POST_H)
	B.group = ""
	for z in QUAY_LAMPS_Z:
		lamp(B, Vector3(QUAY_LAMP_X, 1.1, z), 3.6)
	_arena(B)
	_forum(B)
	_republique(B)
	_theatre(B)
	_quay(B, rng)
	_lamartine(B)
	_trees(B, rng)
	_life(B)
	_far(B, rng)
	return B


static func _arena(B: Buf) -> void:
	var cx := ARENA_C.x
	var cz := ARENA_C.y
	var a := ARENA_A
	var b := ARENA_B
	# the plinth fills the whole landmark block: its edge is the collision edge
	B.box(Vector3(68.0, PLINTH_H * 0.5, 45.0), Vector3(28.0, PLINTH_H, 30.0), "plinth")
	# dark vault behind the arches (the outer shell is its own mesh)
	B.cyl(Vector3(cx, 4.2, cz), 1.0, 1.0, 8.4, "vault", 48, Basis.from_scale(Vector3(a - 2.4, 1, b - 2.4)))
	# the cavea as a funnel: seats seen from above, vaults from outside
	B.cyl(Vector3(cx, ARENA_H - 5.5, cz), 1.0, 0.5, 11.0, "cavea", 48, Basis.from_scale(Vector3(a - 0.05, 1, b - 0.05)), false)
	# three medieval towers (west: end of the Rue du Forum; north; south),
	# standing on the ring of the shell, never in the street
	for t in [[Vector3(57.0, 0, 42.0), 6.0, Vector3(-1, 0, 0)], [Vector3(68.0, 0, 32.75), 5.5, Vector3(0, 0, -1)], [Vector3(68.0, 0, 57.25), 5.5, Vector3(0, 0, 1)]]:
		var tp: Vector3 = t[0]
		var w: float = t[1]
		var o: Vector3 = t[2]
		B.box(tp + Vector3(0, 10.5, 0), Vector3(w, 21.0, w), "stone")
		crenels(B, tp + Vector3(0, 21.0, 0), w, w, "stone")
		for k in 3:
			B.box(tp + o * (w / 2 + 0.02) + Vector3(0, 14.0 + k * 1.8, 0), Vector3(0.25 if o.x != 0.0 else 0.5, 1.0, 0.5 if o.x != 0.0 else 0.25), "dark")


static func _forum(B: Buf) -> void:
	# café terrace on the north side of the Place du Forum, seen frontally from
	# the south across the square (not the painting's view from the north-east)
	B.box(Vector3(27, 1.7, 30.03), Vector3(10.0, 3.4, 0.06), "cafe_wall")
	B.box(Vector3(22.03, 1.7, 28), Vector3(0.06, 3.4, 4.0), "cafe_wall")
	for dx in [-3.0, 1.0]:
		B.box(Vector3(27 + dx, 1.25, 30.08), Vector3(1.4, 2.5, 0.04), "wood_door")
	B.box(Vector3(27, 3.3, 31.8), Vector3(10.4, 0.1, 3.6), "awning", Basis(Vector3.RIGHT, 0.30))
	B.box(Vector3(27, 2.65, 33.55), Vector3(10.4, 0.5, 0.06), "awning")
	B.box(Vector3(31.4, 4.0, 30.6), Vector3(0.6, 0.9, 0.6), "glass_big")
	B.box(Vector3(31.4, 3.45, 30.25), Vector3(0.08, 0.3, 0.5), "post")
	# the terrace: tables and chairs, guests sitting (one obstacle)
	B.group = "terrace"
	var i := 0
	for tz in [31.6, 33.6]:
		for tx in [23.2, 25.6, 28.4, 30.8]:
			var x: float = tx + (0.5 if tz > 32.0 else 0.0)
			B.cyl(Vector3(x, 0.72, tz), 0.42, 0.42, 0.06, "table", 14)
			B.cyl(Vector3(x, 0.36, tz), 0.04, 0.12, 0.7, "chair", 8)
			for s in [-1.0, 1.0]:
				B.box(Vector3(x + 0.75 * s, 0.45, tz), Vector3(0.4, 0.06, 0.4), "chair")
				B.box(Vector3(x + 0.95 * s, 0.7, tz), Vector3(0.05, 0.5, 0.4), "chair")
			if i % 3 == 0:
				B.figure(Vector3(x + 0.75, 0.0, tz), "coat_blue", "skin", -PI / 2, 1.3)
			i += 1
	# two Roman columns in the house corner (north-west of the square), half
	# set into the facade
	B.group = "columns"
	for x in [15.0, 17.4]:
		column(B, Vector3(x, 0, 30.35), 6.6, 0.36, "stone")
	B.box(Vector3(16.2, 7.45, 30.35), Vector3(3.4, 0.6, 0.8), "stone")
	B.prism(Vector3(16.2, 7.75, 30.35), 3.4, 1.0, 0.8, "stone")
	# the Mistral monument (Rivière, 1909; public domain) on its plinth
	B.group = "statue"
	B.box(Vector3(31, 0.2, 45), Vector3(2.2, 0.4, 2.2), "stone")
	B.box(Vector3(31, 1.6, 45), Vector3(1.3, 2.4, 1.3), "stone")
	B.figure(Vector3(31, 2.8, 45), "bronze", "bronze", PI, 2.2)
	B.group = ""
	# the apse of the Constantine baths (brick and stone bands) at the end of
	# the lane, with wall pieces up to the block edge
	B.cyl(Vector3(35.8, 4.5, 20.0), 3.8, 3.8, 9.0, "baths", 24)
	B.sphere(Vector3(35.8, 9.0, 20.0), 3.8, "baths", Vector3(1, 0.55, 1), 20)
	B.box(Vector3(33.2, 3.5, 17.2), Vector3(2.4, 7.0, 2.4), "baths")
	B.box(Vector3(33.2, 3.5, 22.8), Vector3(2.4, 7.0, 2.4), "baths")
	for an in [PI, PI * 0.78, PI * 1.22]:
		B.box(Vector3(35.8 + cos(an) * 3.82, 5.6, 20.0 + sin(an) * 3.82), Vector3(0.15, 2.6, 1.1), "dark", Basis(Vector3.UP, -an))


static func _republique(B: Buf) -> void:
	# Saint-Trophime: front facing north (z 76), Romanesque portal with
	# archivolts, frieze, columns on lions (hinted), the tympanum only as a
	# relief hint (own mesh), crossing tower behind
	var cx := 28.0
	B.box(Vector3(cx, 7.5, 80.5), Vector3(12.0, 15.0, 9.0), "stone_d")
	B.prism(Vector3(cx, 15.0, 80.5), 12.4, 4.0, 9.0, "stone_d")
	B.group = "portal"
	B.box(Vector3(cx, 0.6, 75.3), Vector3(8.4, 1.2, 1.4), "stone")
	for k in 3:
		var sh := 0.4 * (k + 1)
		B.box(Vector3(cx, sh / 2, 73.0 + k * 0.5), Vector3(5.8 - k * 0.6, sh, 0.5), "stone")
	for sx in [-1.0, 1.0]:
		B.box(Vector3(cx + sx * 3.15, 3.6, 75.35), Vector3(2.1, 4.8, 1.3), "stone")
		for j in 3:
			var px: float = cx + sx * (2.05 + j * 0.55)
			B.sphere(Vector3(px, 1.45, 74.45), 0.26, "dark", Vector3(1.0, 0.8, 1.4), 10)
			B.cyl(Vector3(px, 3.3, 74.45), 0.13, 0.15, 3.4, "stone", 8)
	B.box(Vector3(cx, 5.25, 74.7), Vector3(8.2, 0.75, 0.55), "frieze")
	B.box(Vector3(cx, 3.0, 75.95), Vector3(2.6, 3.6, 0.1), "dark")
	for s in [-0.66, 0.66]:
		B.box(Vector3(cx + s, 2.4, 75.86), Vector3(1.2, 2.4, 0.08), "wood_door_v")
	B.group = ""
	for k in 3:
		arch_ring(B, Vector3(cx, 5.65, 75.3 - k * 0.25), 1.55 + k * 0.42, 0.36, 0.6, "stone" if k % 2 == 0 else "stone_d", 14)
	B.prism(Vector3(cx, 8.0, 75.4), 8.6, 2.4, 1.2, "stone")
	# crossing tower behind the front
	B.box(Vector3(cx, 14.0, 89.0), Vector3(6.0, 28.0, 6.0), "stone_d")
	for f in [3.02, -3.02]:
		for k in 2:
			B.box(Vector3(cx - 1.2 + k * 2.4, 24.5, 89.0 + f), Vector3(0.9, 2.2, 0.08), "dark")
	B.cyl(Vector3(cx, 29.5, 89.0), 0.0, 4.4, 3.0, "roof_red", 4, Basis(Vector3.UP, PI / 4))
	# obelisk on its fountain basin
	B.group = "obelisk"
	var ob := Vector3(35.0, 0, 67.0)
	B.cyl(ob + Vector3(0, 0.3, 0), 2.3, 2.4, 0.6, "stone", 24)
	B.box(ob + Vector3(0, 1.7, 0), Vector3(1.6, 2.2, 1.6), "stone")
	B.cyl(ob + Vector3(0, 2.8 + 6.5, 0), 0.38, 0.64, 13.0, "granite", 4, Basis(Vector3.UP, PI / 4))
	B.cyl(ob + Vector3(0, 16.8, 0), 0.0, 0.38, 1.0, "granite", 4, Basis(Vector3.UP, PI / 4))
	B.group = ""
	# Hôtel de Ville (west side, end of the Calade axis): pilasters, cornice,
	# the clock tower behind the front (lit face without numerals)
	for k in 7:
		B.box(Vector3(16.05, 6.0, 64.0 + k * 2.0), Vector3(0.1, 12.0, 0.35), "stone")
	B.box(Vector3(16.15, 12.2, 70.0), Vector3(0.5, 0.6, 13.2), "stone")
	var tw := Vector3(13.0, 0.0, 70.0)
	B.box(tw + Vector3(0, 12.0, 0), Vector3(5.0, 24.0, 5.0), "stone")
	crenels(B, tw + Vector3(0, 24.0, 0), 5.0, 5.0, "stone")
	for k in 4:
		var an := float(k) * PI / 2 + PI / 4
		B.cyl(tw + Vector3(cos(an) * 1.5, 25.6, sin(an) * 1.5), 0.15, 0.18, 2.4, "stone", 8)
	B.sphere(tw + Vector3(0, 27.0, 0), 1.9, "dome", Vector3(1, 0.6, 1), 16)
	B.figure(tw + Vector3(0, 28.1, 0), "bronze", "bronze", PI / 2, 1.6)
	B.cyl(Vector3(15.56, 19.5, 70.0), 1.1, 1.1, 0.12, "clock", 24, Basis(Vector3.BACK, PI / 2))
	B.box(Vector3(15.66, 19.85, 70.0), Vector3(0.05, 0.75, 0.1), "dark")
	B.box(Vector3(15.66, 19.5, 70.35), Vector3(0.05, 0.1, 0.75), "dark", Basis(Vector3.RIGHT, 0.4))


static func _theatre(B: Buf) -> void:
	# Théâtre antique: the two standing columns with a piece of entablature
	# on the stage, the seats rising to the east, Tour de Roland north-east
	B.box(Vector3(71.0, 0.5, 71.0), Vector3(6.0, 1.0, 10.0), "stone_d")
	for z in [69.2, 72.8]:
		column(B, Vector3(69.6, 1.0, z), 8.2, 0.42, "stone")
	B.box(Vector3(69.6, 9.95, 71.0), Vector3(1.1, 0.9, 4.6), "stone")
	B.box(Vector3(69.6, 10.7, 71.6), Vector3(1.0, 0.6, 2.4), "stone_d")
	B.cyl(Vector3(72.5, 1.4, 68.0), 0.42, 0.42, 1.6, "stone", 12, Basis(Vector3.UP, 0.6) * Basis(Vector3.RIGHT, PI / 2))
	B.cyl(Vector3(73.0, 1.4, 74.0), 0.45, 0.45, 0.8, "stone", 12)
	for i in 7:
		var hh := 1.2 + i * 0.95
		# the seat rows stay inside the theatre block (rows 33-37), never in the ring
		B.box(Vector3(74.6 + i * 1.5, hh / 2, 71.0), Vector3(1.5, hh, minf(8.4 + i * 0.6, 9.96)), "seats")
	var rt := Vector3(76.2, 0.0, 68.2)
	B.box(rt + Vector3(0, 9.0, 0), Vector3(4.2, 18.0, 4.2), "stone_d")
	crenels(B, rt + Vector3(0, 18.0, 0), 4.2, 4.2, "stone_d")
	for k in 2:
		B.box(rt + Vector3(-2.14, 6.0 + k * 6.0, 0), Vector3(0.1, 2.4, 1.2), "dark")


static func _quay(B: Buf, rng: RandomNumberGenerator) -> void:
	# quay wall and parapet: the 0.6 m parapet is the collision edge (x 2)
	B.box(Vector3(-0.25, -1.1, 40), Vector3(0.5, 2.2, 260), "quay")
	B.box(Vector3(0.7, -0.6, 36.0), Vector3(1.4, 1.2, 68.0), "quay")
	B.box(Vector3(-70.0, -1.1, 40), Vector3(1.0, 2.6, 260), "quay")
	var z0 := float(M.PARAPET_R0) * CELL
	var z1 := float(M.PARAPET_R1) * CELL + CELL
	B.box(Vector3(1.7, 0.5, (z0 + z1) / 2), Vector3(0.6, 1.0, z1 - z0), "parapet")
	B.box(Vector3(1.7, 1.05, (z0 + z1) / 2), Vector3(0.7, 0.12, z1 - z0), "parapet")
	# Grand Prieuré at the south end of the quay: crenellated front, pointed
	# windows (one lit), corner tower
	B.box(Vector3(6.0, 6.0, 74.5), Vector3(9.0, 12.0, 9.0), "stone_d")
	crenels(B, Vector3(6.0, 12.0, 74.5), 9.0, 9.0, "stone_d", 0.9)
	for k in 3:
		B.box(Vector3(3.0 + k * 3.0, 6.0, 69.97), Vector3(0.9, 3.2, 0.1), "window_lit" if k == 1 else "dark")
		B.prism(Vector3(3.0 + k * 3.0, 7.6, 69.97), 0.9, 0.7, 0.1, "dark")
	B.cyl(Vector3(1.3, 7.0, 71.4), 1.3, 1.3, 14.0, "stone_d", 16)
	round_crenels(B, Vector3(1.3, 14.0, 71.4), 1.3, "stone_d")
	# the iron arch bridge to Trinquetaille (typology, north)
	for x in [-14.0, -35.0, -56.0]:
		B.box(Vector3(x, 0.0, -46.0), Vector3(2.4, 5.0, 3.0), "stone_d")
	B.box(Vector3(-35.0, 3.0, -46.0), Vector3(70.0, 0.4, 7.0), "iron")
	for seg in 3:
		for i in 10:
			var an := PI * (float(i) + 0.5) / 10.0
			var x: float = -3.5 - seg * 21.0 - 10.5 + cos(an) * 10.5
			for zz in [-49.2, -42.8]:
				B.box(Vector3(x, 3.2 + sin(an) * 4.0, zz), Vector3(3.4, 0.35, 0.3), "iron", Basis(Vector3.BACK, an - PI / 2))
	# two boats at the quay
	for p in [Vector3(-3.0, -1.9, 33.0), Vector3(-4.2, -1.9, 52.0)]:
		B.sphere(p, 1.0, "hull", Vector3(1.0, 0.35, 3.0), 12)
		B.cyl(p + Vector3(0, 2.0, 0), 0.05, 0.06, 4.0, "hull", 6)


static func _lamartine(B: Buf) -> void:
	# Porte de la Cavalerie: two round towers with crenels, wall pieces, the
	# arch over the passage (the towers stay inside the landmark block)
	for z in [3.4, 14.6]:
		B.cyl(Vector3(38.6, 7.5, z), 2.6, 2.6, 15.0, "stone_d", 20)
		round_crenels(B, Vector3(38.6, 15.0, z), 2.6, "stone_d")
		B.box(Vector3(36.0, 9.0, z), Vector3(0.12, 1.4, 0.5), "dark")
	B.box(Vector3(43.5, 4.5, 4.0), Vector3(9.0, 9.0, 4.0), "stone")
	B.box(Vector3(43.5, 4.5, 14.0), Vector3(9.0, 9.0, 4.0), "stone")
	B.box(Vector3(39.5, 10.6, 9.0), Vector3(2.0, 2.0, 7.0), "stone_d")
	# rampart tower at the north end of the Rue de la Cavalerie
	B.box(Vector3(51.0, 7.0, 0.0), Vector3(6.0, 14.0, 4.0), "stone_d")
	crenels(B, Vector3(51.0, 14.0, 0.0), 6.0, 4.0, "stone_d")


static func _trees(B: Buf, rng: RandomNumberGenerator) -> void:
	# plane trees (blue crowns: green belongs to the exit); the north-west one
	# stands a little south, off the way along the café terrace (GD W3)
	var i := 0
	for p in [Vector3(19.5, 0, 37.6), Vector3(19.5, 0, 48.5),
 Vector3(35.5, 0, 48.5), Vector3(35.5, 0, 36.5),
			Vector3(20.0, 0, 13.0), Vector3(30.0, 0, 13.0), Vector3(9.0, 0, 13.0)]:
		B.group = "tree%d" % i
		B.cyl(p + Vector3(0, 3.2, 0), 0.2, 0.3, 6.4, "trunk", 8)
		B.cyl(p + Vector3(0.5, 5.4, 0.2), 0.08, 0.16, 2.4, "trunk", 6)
		for k in 9:
			var o := Vector3(rng.randf_range(-2.2, 2.2), rng.randf_range(6.4, 9.2), rng.randf_range(-2.2, 2.2))
			B.sphere(p + o, rng.randf_range(0.9, 1.4), "crown", Vector3(1.0, 0.75, 1.0), 10)
		i += 1
	# cypresses in the garden of the Place Lamartine (nearly black)
	for cz in [[25.0, 12.6, 9.5], [33.5, 12.4, 11.5]]:
		B.group = "cypress%d" % i
		cypress(B, Vector3(cz[0], 0, cz[1]), cz[2], rng)
		i += 1
	B.group = ""


## Passers-by brighter than paving and facades (technical condition), a horse
## cart on the Place de la République. They stand still.
const FIGURES := [
	[Vector3(5.5, 0, 26.0), 0.3], [Vector3(8.6, 0, 44.0), 2.8], [Vector3(5.6, 0, 60.0), 0.0], [Vector3(21.0, 0, 43.5), 1.2],
	[Vector3(33.5, 0, 50.5), -2.0], [Vector3(25.0, 0, 58.0), 3.0], [Vector3(22.0, 0, 69.4), 0.8], [Vector3(38.0, 0, 73.0), -1.4],
	[Vector3(44.0, 0, 69.5), 1.6], [Vector3(12.5, 0, 12.0), 2.6], [Vector3(30.0, 0, 6.5), -0.6], [Vector3(52.6, 0, 30.0), 0.2],
	[Vector3(49.2, 0, 37.4), 1.9], [Vector3(86.6, 0, 46.0), 3.1],
]


static func _life(B: Buf) -> void:
	var coats := ["coat_blue", "coat_ochre", "coat_lilac"]
	for i in FIGURES.size():
		B.group = "figure%d" % i
		B.figure(FIGURES[i][0], coats[i % 3], "skin", FIGURES[i][1])
	B.group = "cart"
	var basis := Basis(Vector3.UP, 1.4)
	var o := Vector3(23.0, 0, 73.5)
	B.box(o + basis * Vector3(0, 0.95, 0), Vector3(1.5, 0.7, 2.6), "cart_wood", basis)
	for sx in [-0.85, 0.85]:
		B.cyl(o + basis * Vector3(sx, 0.6, 0.6), 0.6, 0.6, 0.12, "cart_wood", 14, basis * Basis(Vector3.BACK, PI / 2))
	B.sphere(o + basis * Vector3(0, 1.25, -2.6), 0.45, "horse", Vector3(1.0, 1.0, 2.0), 14, basis)
	B.sphere(o + basis * Vector3(0, 1.9, -3.7), 0.22, "horse", Vector3(1.0, 1.4, 1.0), 10, basis)
	for lx in [-0.25, 0.25]:
		for lz in [-2.0, -3.3]:
			B.cyl(o + basis * Vector3(lx, 0.45, lz), 0.06, 0.08, 0.9, "horse", 6, basis)
	B.group = ""


static func _far(B: Buf, rng: RandomNumberGenerator) -> void:
	# ground beyond the map (east of the quay) and on the far bank
	B.box(Vector3(300.0, -0.06, 40.0), Vector3(600.0, 0.04, 1000.0), "ground")
	B.box(Vector3(-235.0, 0.18, 40.0), Vector3(330.0, 0.04, 1000.0), "ground")
	# railway viaduct (north), Montmajour on its hill (north-east), the
	# Alpilles (east), cypress groups - dark silhouettes
	for i in 16:
		B.box(Vector3(-10.0 + i * 9.0, 4.5, -75.0), Vector3(2.0, 9.0, 4.0), "far")
	B.box(Vector3(57.0, 9.6, -75.0), Vector3(150.0, 1.2, 4.0), "far")
	B.sphere(Vector3(260, -8, -330), 90.0, "far", Vector3(1.8, 0.28, 1.0), 24)
	B.box(Vector3(255, 34, -320), Vector3(14, 26, 14), "far")
	B.box(Vector3(280, 26, -322), Vector3(30, 12, 12), "far")
	for k in 7:
		B.sphere(Vector3(500 + k * 15, -6, -200 + k * 70), 110.0, "far", Vector3(0.6, 0.3, 1.4), 20)
	for p in [Vector3(120, 0, -30), Vector3(126, 0, -26), Vector3(-92, 0, 20), Vector3(-95, 0, 26), Vector3(140, 0, 110)]:
		cypress(B, p, 12.0, rng)


## ---------------------------------------------------------------- halos
## [map position, size, seed, rings, energy, type] of every halo in the city.
static func halos(seed: int) -> Array:
	var out: Array = []
	for l in lamp_heads():
		var p: Vector3 = l[0]
		out.append([p, 3.4 if l[1] else 2.6, fmod(p.z * 0.37 + p.x, 10.0), 6.0, 1.1, 0])
	out.append([Vector3(31.4, 4.0, 30.6), 4.2, 3.3, 6.0, 1.2, 0]) # the café lantern
	for z in range(-40, 130, 14):
		out.append([Vector3(-71.0, 3.2, float(z) + 3.0), 1.8, fmod(float(z), 10.0), 5.0, 1.0, 0])
	for x in [-10.0, -24.0, -38.0, -52.0, -66.0]:
		out.append([Vector3(x, 5.6, -42.6), 1.6, fmod(-x, 10.0), 5.0, 1.0, 0])
	var rng := RandomNumberGenerator.new()
	rng.seed = seed + 11
	var n := 22
	for i in n:
		var az := float(i) / float(n) * TAU + rng.randf_range(-0.12, 0.12)
		var el := rng.randf_range(0.28, 1.05)
		var p := Vector3(45, 0, 41) + Vector3(sin(az) * cos(el), sin(el), -cos(az) * cos(el)) * 330.0
		out.append([p, rng.randf_range(20.0, 44.0), float(i) * 1.7, 4.0 + float(i % 3), 1.4, 1])
	out.append([Vector3(45, 0, 41) + Vector3(0.62, 0.42, 0.66).normalized() * 330.0, 100.0, 5.5, 7.0, 1.2, 2]) # moon, south-east
	return out


## The lamps mirrored in the Rhône (map position, strength).
static func reflections() -> Array:
	var out: Array = []
	for l in lamp_heads():
		if l[1]:
			var p: Vector3 = l[0]
			out.append(Vector4(p.x, p.y, p.z, 1.0))
	for z in range(-40, 130, 14):
		out.append(Vector4(-71.0, 3.2, float(z) + 3.0, 0.8))
	for x in [-10.0, -24.0, -38.0, -52.0, -66.0]:
		out.append(Vector4(x, 5.6, -42.6, 0.7))
	return out


static func halo_multimesh(list: Array) -> MultiMesh:
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = q
	mm.instance_count = list.size()
	for i in list.size():
		var hh: Array = list[i]
		var s: float = hh[1]
		mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(s, s, 1)), hh[0]))
		mm.set_instance_custom_data(i, Color(hh[2], hh[3], hh[4], float(hh[5])))
	return mm


static func halo_material() -> ShaderMaterial:
	var sm := ShaderMaterial.new()
	sm.shader = HALO_SHADER
	sm.set_shader_parameter("core", Style.HALO_CORE)
	sm.set_shader_parameter("yellow", Style.HALO_YELLOW)
	sm.set_shader_parameter("rim", Style.HALO_RIM)
	sm.set_shader_parameter("g_core", Style.EXIT_CORE)
	sm.set_shader_parameter("g_mid", Style.EXIT)
	sm.set_shader_parameter("g_rim", Style.EXIT_RIM)
	return sm


## ---------------------------------------------------------------- obstacles
## Does a map-space footprint reach into the walkable space (more than
## WALL_TOL away from a closed side of an open cell)?
static func intrudes(lo: Vector2, hi: Vector2) -> bool:
	var c0 := int(floor(lo.x / CELL))
	var c1 := int(floor((hi.x - 0.0001) / CELL))
	var r0 := int(floor(lo.y / CELL))
	var r1 := int(floor((hi.y - 0.0001) / CELL))
	for r in range(r0, r1 + 1):
		for c in range(c0, c1 + 1):
			if not M.is_open(r, c):
				continue
			var x0 := c * CELL + (WALL_TOL if not M.is_open(r, c - 1) else 0.0)
			var x1 := c * CELL + CELL - (WALL_TOL if not M.is_open(r, c + 1) else 0.0)
			var z0 := r * CELL + (WALL_TOL if not M.is_open(r - 1, c) else 0.0)
			var z1 := r * CELL + CELL - (WALL_TOL if not M.is_open(r + 1, c) else 0.0)
			if minf(hi.x, x1) - maxf(lo.x, x0) > 0.001 and minf(hi.y, z1) - maxf(lo.y, z0) > 0.001:
				return true
	return false


## Collision boxes (map-space AABBs) for every group of parts that reaches
## into the walkable space below eye height.
static func obstacles(parts: Array) -> Array:
	var groups := {}
	var order: Array = []
	for i in parts.size():
		var p: Dictionary = parts[i]
		var bb: AABB = p.aabb
		if bb.position.y > EYE or bb.end.y < 0.05:
			continue
		if not intrudes(Vector2(bb.position.x, bb.position.z), Vector2(bb.end.x, bb.end.z)):
			continue
		var key: String = p.group if p.group != "" else "#%d" % i
		var clip := AABB(Vector3(bb.position.x, 0.0, bb.position.z), Vector3(bb.size.x, OBSTACLE_TOP, bb.size.z))
		if groups.has(key):
			groups[key] = groups[key].merge(clip)
		else:
			groups[key] = clip
			order.append(key)
	var out: Array = []
	for k in order:
		out.append({"name": k, "aabb": groups[k]})
	return out


## ---------------------------------------------------------------- build
static func build(_maze, _city_theme, seed: int) -> Node3D:
	var root := Node3D.new()
	root.name = "ArlesScenery"
	root.set_script(RootScript)
	var city := Node3D.new()
	city.name = "City"
	city.position = -MAP_SHIFT
	root.add_child(city)
	root.city = city

	var H := houses(seed)
	var hm := MeshInstance3D.new()
	hm.name = "Houses"
	hm.mesh = H.st.commit()
	var fm := facade_material()
	hm.material_override = fm
	city.add_child(hm)
	root.house_box_count = H.count

	var B := objects(seed)
	var om := MeshInstance3D.new()
	om.name = "Objects"
	om.mesh = B.commit()
	var obm := obj_material()
	om.material_override = obm
	city.add_child(om)
	root.object_parts = B.parts

	# the amphitheatre's outer shell (arches cut in the shader)
	var shell := CylinderMesh.new()
	shell.top_radius = 1.0
	shell.bottom_radius = 1.0
	shell.height = ARENA_H
	shell.radial_segments = 120
	shell.rings = 1
	shell.cap_top = false
	shell.cap_bottom = false
	var arc := MeshInstance3D.new()
	arc.name = "Arcades"
	arc.mesh = shell
	arc.position = Vector3(ARENA_C.x, ARENA_H / 2, ARENA_C.y)
	arc.scale = Vector3(ARENA_A, 1, ARENA_B)
	var am := ShaderMaterial.new()
	am.shader = ARCADE_SHADER
	am.set_shader_parameter("col_a", Color("c4ae84"))
	am.set_shader_parameter("col_b", Color("9e8a6c"))
	am.set_shader_parameter("col_c", Color("ead8a8"))
	am.set_shader_parameter("ctr", ARENA_C)
	am.set_shader_parameter("perim", PI * (ARENA_A + ARENA_B))
	am.set_shader_parameter("rad", (ARENA_A + ARENA_B) / 2.0)
	am.set_shader_parameter("emit", 0.10)
	set_pool_params(am)
	arc.material_override = am
	city.add_child(arc)

	# the tympanum of Saint-Trophime: only a relief hint, no figures
	var ty := MeshInstance3D.new()
	ty.name = "Tympanum"
	var tq := QuadMesh.new()
	tq.size = Vector2(2.8, 1.4)
	ty.mesh = tq
	ty.position = Vector3(28.0, 6.35, 75.62)
	ty.rotation.y = PI
	var tm := ShaderMaterial.new()
	tm.shader = TYMPANON_SHADER
	tm.set_shader_parameter("stone", Color("c9b48a"))
	tm.set_shader_parameter("shade", Color("4a4260"))
	ty.material_override = tm
	city.add_child(ty)

	# the Rhône
	var water := MeshInstance3D.new()
	water.name = "Rhone"
	var wp := PlaneMesh.new()
	wp.size = Vector2(200.0, 600.0)
	water.mesh = wp
	water.position = Vector3(-100.0, -2.2, 40.0)
	var wm := ShaderMaterial.new()
	wm.shader = WATER_SHADER
	wm.set_shader_parameter("deep", Style.WATER[0])
	wm.set_shader_parameter("mid", Style.WATER[1])
	wm.set_shader_parameter("hi", Style.WATER[2])
	wm.set_shader_parameter("r_core", Style.REFL_CORE)
	wm.set_shader_parameter("r_rim", Style.REFL_RIM)
	var refl := reflections()
	var ra := PackedVector4Array()
	for v in refl:
		ra.append(v)
	wm.set_shader_parameter("refl", ra)
	wm.set_shader_parameter("nrefl", mini(refl.size(), 40))
	set_pool_params(wm)
	water.material_override = wm
	city.add_child(water)

	# the sky sphere: the material gets its baked texture in arles_root.gd
	var sky := MeshInstance3D.new()
	sky.name = "Sky"
	var sp := SphereMesh.new()
	sp.radius = SKY_RADIUS
	sp.height = SKY_RADIUS * 2.0
	sp.radial_segments = 48
	sp.rings = 24
	sky.mesh = sp
	sky.position = SKY_CENTER
	var skm := ShaderMaterial.new()
	skm.shader = SKY_SHADER
	skm.set_shader_parameter("base", Style.SKY_BASE)
	skm.set_shader_parameter("mid", Style.SKY_MID)
	skm.set_shader_parameter("light", Style.SKY_LIGHT)
	skm.set_shader_parameter("yellow", Style.SKY_YELLOW)
	skm.set_shader_parameter("haze", Style.FOG)
	skm.set_shader_parameter("speed", Style.SKY_DRIFT)
	sky.material_override = skm
	sky.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	city.add_child(sky)
	var bake_mat := ShaderMaterial.new()
	bake_mat.shader = SKY_BAKE_SHADER
	root.setup_sky(skm, bake_mat)

	# halos: every lamp, star and the moon in ONE MultiMesh
	var hl := halos(seed)
	var hmi := MultiMeshInstance3D.new()
	hmi.name = "Halos"
	hmi.multimesh = halo_multimesh(hl)
	hmi.material_override = halo_material()
	hmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	city.add_child(hmi)
	root.halo_count = hl.size()

	# what reaches into the streets below eye height blocks the player
	var obs := obstacles(B.parts)
	var body := StaticBody3D.new()
	body.name = "Obstacles"
	body.collision_layer = 2
	body.collision_mask = 0
	for o in obs:
		var bb: AABB = o.aabb
		var shape := BoxShape3D.new()
		shape.size = bb.size
		var cs := CollisionShape3D.new()
		cs.name = String(o.name)
		cs.shape = shape
		cs.position = bb.get_center()
		body.add_child(cs)
	city.add_child(body)
	root.obstacle_boxes = obs

	# light: the moon and 6 omni lights without shadows
	var moon := DirectionalLight3D.new()
	moon.name = "Moon"
	moon.light_color = Style.MOON
	moon.light_energy = 0.5
	moon.shadow_enabled = false
	moon.rotation_degrees = MOON_ROT_DEG
	city.add_child(moon)
	for o in OMNI:
		var l := OmniLight3D.new()
		l.name = o.name
		l.light_color = Color(o.col)
		l.light_energy = o.e
		l.omni_range = o.r
		l.omni_attenuation = 1.3
		l.shadow_enabled = false
		l.position = o.pos
		city.add_child(l)
	root.omni_count = OMNI.size()

	root.brush_materials = [fm, obm, am, wm]
	root.water_material = wm
	root.halo_material = hmi.material_override
	return root
