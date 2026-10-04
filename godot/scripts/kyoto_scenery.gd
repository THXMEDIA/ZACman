extends RefCounted
## KyotoScenery — builds the pop-up book city of the Kyoto Explorer level
## (CityTheme.scenery_builder_script, see city_themes.gd kyoto()). Every
## building, tree, torii, figure and backdrop is one card of a single
## MultiMesh, printed procedurally by kyoto_card.gdshader (one draw call for
## the whole city), plus the bokashi sky sphere:
##   - house rows on every block edge facing a street (machiya, shops, temple
##     walls), cut into houses of 4-7 m; some get a roof or pine card behind
##   - landmarks at the street ends (kyoto_maze.gd LANDMARKS): the theatre,
##     the shrine gate, the pagoda (twice, behind the temple walls), the
##     Kiyomizu stage, the Kennin-ji gate, the Inari shrine
##   - a tunnel of torii in the torii lane, a few figures in doorways
##   - backdrop that never folds: the Higashiyama hills, Kyoto Tower, mist bands
## Cards stand on the facade line (the collision edge) and fold back onto the
## block with distance. Variation comes from the level seed only.

const KyotoMazeScript := preload("res://scripts/kyoto_maze.gd")
const TokyoScenery := preload("res://scripts/tokyo_scenery.gd")
const Style := preload("res://scripts/kyoto_style.gd")
const CARD_SHADER := preload("res://shaders/kyoto_card.gdshader")
const SKY_SHADER := preload("res://shaders/kyoto_sky.gdshader")
const RootScript := preload("res://scripts/kyoto_popup_root.gd")

const CELL := 2.0
const CARD_BASE_Y := 0.07 # on top of the printed block plan
const FACADE_OUT := 0.01 # cards sit a hair in front of the collision edge
const PAGODA_H := 22.0 # the spire about a quarter of the height (UX N4)
## Torii tunnel: one gate per cell along the torii lane; the posts stand at
## +-TORII_POST m from the lane's centre line, and a collision rail along
## each post line keeps the camera from running through them.
const TORII_FROM := 2
const TORII_TO := 20
const TORII_Z := 39.0 * 2.0
const TORII_POST := 2.3
const TORII_POST_HALF := 0.22
const TORII_LANE_X0 := 1.0 # west end of the lane (col 1)
const TORII_LANE_X1 := 43.0 # where it meets Hanamikoji (col 22)
const TORII_LANE_HALF := 3.0

## Street id -> house kind and height range.
const STREET_LOOK := {
	"shijo": {"kind": Style.K_SHOP, "h": [7.6, 9.6], "w": [5.0, 7.0]},
	"hanamikoji": {"kind": Style.K_MACHIYA, "h": [6.2, 7.0], "w": [4.2, 5.6]},
	"hanamikoji_nord": {"kind": Style.K_MACHIYA, "h": [6.2, 7.0], "w": [4.2, 5.6]},
	"seitengasse": {"kind": -1, "h": [6.0, 7.2], "w": [4.5, 6.0]},
	"yasaka_dori": {"kind": -1, "h": [6.0, 7.2], "w": [4.2, 5.6]},
	"sannenzaka": {"kind": -1, "h": [6.0, 7.4], "w": [4.2, 5.8]},
	"ninenzaka": {"kind": -1, "h": [6.0, 7.4], "w": [4.2, 5.8]},
	"ninenzaka_nord": {"kind": -1, "h": [6.0, 7.4], "w": [4.2, 5.8]},
	"torii_gasse": {"kind": Style.K_TEMPLE_WALL, "h": [4.0, 4.4], "w": [5.0, 7.0]},
}


static func block_depth_torii() -> float:
	return 2.4 # a lying torii stays inside its lane (lane half-width 3 m)


## Collision rails along the torii posts: {center, size} boxes.
## They fill the whole strip from the inner post face to the lane wall, over
## the lane's full length (no gap to slip behind the posts, code review H4).
static func torii_rails() -> Array:
	var x0 := TORII_LANE_X0
	var x1 := TORII_LANE_X1
	var inner := TORII_POST - TORII_POST_HALF
	var out := []
	for side in [-1.0, 1.0]:
		var zc: float = TORII_Z + side * (inner + TORII_LANE_HALF) * 0.5
		out.append({"center": Vector3((x0 + x1) * 0.5, 1.5, zc), "size": Vector3(x1 - x0, 3.0, TORII_LANE_HALF - inner + 0.2)})
	return out


## Floor setup (CityTheme.floor_setup_script): palette from KyotoStyle and the
## printed torii rails.
static func setup_floor(mat: ShaderMaterial, _maze, _seed: int) -> void:
	mat.set_shader_parameter("floor_albedo", Style.PAPER)
	mat.set_shader_parameter("ai1", Style.AI1)
	mat.set_shader_parameter("ai3", Style.AI3)
	mat.set_shader_parameter("ai4", Style.AI4)
	mat.set_shader_parameter("rail_x", Vector2(TORII_LANE_X0, TORII_LANE_X1))
	mat.set_shader_parameter("rail_z", TORII_Z)
	mat.set_shader_parameter("rail_in", TORII_POST - TORII_POST_HALF)


static func cell_of(p: Vector3) -> Vector2i:
	return Vector2i(int(floor(p.z / CELL + 0.5)), int(floor(p.x / CELL + 0.5)))


static func in_map(maze, cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < maze.rows and cell.y >= 0 and cell.y < maze.cols


static func yaw_for(n: Vector3) -> float:
	return atan2(n.x, n.z)


static func card(pos: Vector3, n: Vector3, w: float, h: float, kind: int, s: float, fold_len: float = 0.0) -> Dictionary:
	return {"pos": pos, "yaw": yaw_for(n), "w": w, "h": h, "kind": kind, "s": s, "fold_len": fold_len if fold_len > 0.0 else h}


## How far a card at `pos` may lie back (against its normal `n`) and stay on
## its own block: the distance to the next street cell behind it, minus a
## margin. Off the map counts as block (the book's margin).
static func block_depth(maze, pos: Vector3, n: Vector3) -> float:
	var d := 0.25
	while d < 30.0:
		var cell := cell_of(pos - n * d)
		if in_map(maze, cell) and maze.grid[cell.x][cell.y] == 0:
			return maxf(0.6, d - 0.45)
		d += 0.25
	return 30.0


## All cards of the city as plain data (tests check them without a renderer).
static func cards(maze, seed: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var out: Array = []

	# ---- house rows along every block edge that faces a street ----
	for run in TokyoScenery.facade_runs(maze):
		var a: Vector3 = run.a
		var b: Vector3 = run.b
		var n: Vector3 = run.n
		var mid := (a + b) * 0.5
		var out_cell := cell_of(mid + n * 1.0)
		var wall_cell := cell_of(mid - n * 1.0)
		if not in_map(maze, out_cell) or maze.grid[out_cell.x][out_cell.y] != 0:
			continue
		var lm := KyotoMazeScript.landmark_block_at(wall_cell.x, wall_cell.y)
		var temple := false
		if not lm.is_empty():
			if lm.id == "pagoda":
				temple = true # the pagoda stands inside temple walls
			elif Vector2(n.x, n.z).is_equal_approx(lm.face):
				continue # the landmark card covers this edge
		var street := KyotoMazeScript.street_at(out_cell.x, out_cell.y)
		var look: Dictionary = STREET_LOOK.get(street.get("id", ""), STREET_LOOK["seitengasse"])
		var length := a.distance_to(b)
		var target: float = rng.randf_range(look.w[0], look.w[1])
		var count := maxi(1, int(round(length / target)))
		var hw := length / float(count)
		var dir := (b - a).normalized()
		for i in count:
			var center := a + dir * (hw * (float(i) + 0.5)) + n * FACADE_OUT
			center.y = CARD_BASE_Y
			var kind: int = look.kind
			var h: float = rng.randf_range(look.h[0], look.h[1])
			if temple:
				kind = Style.K_TEMPLE_WALL
				h = 4.2
			elif kind < 0:
				var roll := rng.randf()
				kind = Style.K_MACHIYA if roll < 0.55 else (Style.K_SHOP if roll < 0.85 else Style.K_TEMPLE_WALL)
				if kind == Style.K_TEMPLE_WALL:
					h = 4.2
			var s := rng.randf()
			out.append(card(center, n, hw + 0.02, h, kind, s, block_depth(maze, center, n)))
			# second layer: a roof or a pine behind the house, if the block is deep enough
			if kind != Style.K_TEMPLE_WALL or temple:
				var back := center - n * 3.6
				var bw := hw + 0.1
				var ok := true
				for e in [back, back + dir * bw * 0.5, back - dir * bw * 0.5]:
					var bc := cell_of(e)
					if not in_map(maze, bc) or maze.grid[bc.x][bc.y] != 1 or not KyotoMazeScript.landmark_block_at(bc.x, bc.y).is_empty():
						ok = false
				if ok:
					var roll2 := rng.randf()
					var depth := block_depth(maze, back, n)
					if roll2 < 0.5:
						out.append(card(back, n, bw, h + rng.randf_range(2.0, 3.6), Style.K_ROOFS, rng.randf(), depth))
					elif roll2 < 0.68:
						out.append(card(back, n, minf(bw, rng.randf_range(4.0, 5.2)), rng.randf_range(6.5, 8.5), Style.K_PINE, rng.randf(), depth))

	# ---- landmarks at the street ends: they never fold, so every street
	# shows its goal from its whole length ----
	var lf := Style.NO_FOLD
	var x_w := 0.5 * CELL + FACADE_OUT # facade of col 0, facing east
	var x_e := 47.5 * CELL - FACADE_OUT # facade of col 48, facing west
	out.append(card(Vector3(x_w, CARD_BASE_Y, 10.0 * CELL), Vector3(1, 0, 0), 10.6, 13.2, Style.K_THEATER + lf, 0.5))
	out.append(card(Vector3(x_e, CARD_BASE_Y, 10.0 * CELL), Vector3(-1, 0, 0), 11.2, 13.2, Style.K_GATE + lf, 0.5))
	out.append(card(Vector3(x_w, CARD_BASE_Y, 39.0 * CELL), Vector3(1, 0, 0), 6.4, 7.6, Style.K_SHRINE + lf, 0.5))
	out.append(card(Vector3(23.0 * CELL, CARD_BASE_Y, 43.5 * CELL - FACADE_OUT), Vector3(0, 0, -1), 6.4, 8.2, Style.K_TEMPLE_GATE + lf, 0.5))
	# Kiyomizu: set back 1.6 m so the exit door stands in front of it
	out.append(card(Vector3(44.0 * CELL, CARD_BASE_Y, 41.5 * CELL + 1.6), Vector3(0, 0, -1), 18.8, 16.8, Style.K_KIYOMIZU + lf, 0.5))
	# Yasaka pagoda in the middle of its temple block, printed on both sides:
	# seen from Yasaka-dori (west), Sannenzaka (south) and Seitengasse (north)
	# Two crossed cards, so it reads as a pagoda from every lane (GD W2).
	var pagoda_pos := Vector3(39.5 * CELL, CARD_BASE_Y, 31.0 * CELL)
	out.append(card(pagoda_pos, Vector3(-1, 0, 0), 11.0, PAGODA_H, Style.K_PAGODA + lf, 0.5))
	out.append(card(pagoda_pos, Vector3(0, 0, 1), 11.0, PAGODA_H, Style.K_PAGODA + lf, 0.5))
	# Small temple gates close the three lanes that would otherwise end on a
	# blank wall (GD W5): Ninenzaka north, Hanamikoji north, side lane west.
	out.append(card(Vector3(44.0 * CELL, CARD_BASE_Y, 23.5 * CELL + FACADE_OUT), Vector3(0, 0, -1), 6.4, 8.2, Style.K_TEMPLE_GATE + lf, 0.3))
	out.append(card(Vector3(23.0 * CELL, CARD_BASE_Y, 0.5 * CELL + FACADE_OUT), Vector3(0, 0, 1), 6.4, 8.2, Style.K_TEMPLE_GATE + lf, 0.7))
	out.append(card(Vector3(x_w, CARD_BASE_Y, 21.0 * CELL), Vector3(1, 0, 0), 6.4, 8.2, Style.K_TEMPLE_GATE + lf, 0.4))

	# ---- torii tunnel: one gate every cell along the torii lane ----
	# (posts at +-2.3 m; TORII_RAIL keeps the player inside them)
	# east to west: the gate nearest to a player coming from Hanamikoji is
	# drawn first (early depth rejects the ones behind, code review W3)
	for c in range(TORII_TO, TORII_FROM - 1, -1):
		out.append(card(Vector3(c * CELL, CARD_BASE_Y, TORII_Z), Vector3(1, 0, 0), 5.8, 5.3, Style.K_TORII, 0.5, block_depth_torii()))

	# ---- figures in doorways (Hanamikoji, Ninenzaka, Shijo) ----
	var spots := [
		[Vector3(21.5 * CELL, 0, 16.0 * CELL), Vector3(1, 0, 0)], [Vector3(24.5 * CELL, 0, 19.0 * CELL), Vector3(-1, 0, 0)],
		[Vector3(21.5 * CELL, 0, 27.0 * CELL), Vector3(1, 0, 0)], [Vector3(24.5 * CELL, 0, 34.0 * CELL), Vector3(-1, 0, 0)],
		[Vector3(42.5 * CELL, 0, 16.0 * CELL), Vector3(1, 0, 0)], [Vector3(45.5 * CELL, 0, 38.0 * CELL), Vector3(-1, 0, 0)],
		[Vector3(42.5 * CELL, 0, 19.0 * CELL), Vector3(1, 0, 0)], [Vector3(14.0 * CELL, 0, 7.5 * CELL), Vector3(0, 0, 1)],
		[Vector3(31.0 * CELL, 0, 12.5 * CELL), Vector3(0, 0, -1)], [Vector3(8.0 * CELL, 0, 19.5 * CELL), Vector3(0, 0, 1)],
	]
	for sp in spots:
		var p: Vector3 = sp[0] + sp[1] * 0.05
		p.y = CARD_BASE_Y
		out.append(card(p, sp[1], 1.5, 2.1, Style.K_FIGURE, rng.randf()))

	# ---- backdrop (never folds): hills, tower, mist ----
	var nf := Style.NO_FOLD
	out.append(card(Vector3(150.0, 0.0, 44.0), Vector3(-1, 0, 0), 190.0, 34.0, Style.K_MOUNTAINS + nf, 0.2))
	out.append(card(Vector3(190.0, 0.0, 30.0), Vector3(-1, 0, 0), 260.0, 50.0, Style.K_MOUNTAINS + nf, 0.8))
	out.append(card(Vector3(48.0, 0.0, -70.0), Vector3(0, 0, 1), 260.0, 30.0, Style.K_MOUNTAINS + nf, 0.7))
	out.append(card(Vector3(-120.0, 0.0, 40.0), Vector3(1, 0, 0), 260.0, 26.0, Style.K_MOUNTAINS + nf, 0.9))
	out.append(card(Vector3(48.0, 0.0, 170.0), Vector3(0, 0, -1), 260.0, 22.0, Style.K_MOUNTAINS + nf, 0.6))
	var tower_pos := Vector3(-55.0, 0.0, 135.0)
	out.append(card(tower_pos, (Vector3(48.0, 0.0, 44.0) - tower_pos).normalized(), 11.0, 70.0, Style.K_TOWER + nf, 0.5))
	# kasumi: long pale bands in front of the hills, as in the prints
	var mists := [[Vector3(128, 9, 60), Vector3(-1, 0, 0)], [Vector3(132, 15, 10), Vector3(-1, 0, 0)], [Vector3(30, 8, -52), Vector3(0, 0, 1)],
		[Vector3(-95, 7, 70), Vector3(1, 0, 0)], [Vector3(70, 7, 150), Vector3(0, 0, -1)]]
	for m in mists:
		out.append(card(m[0], m[1], rng.randf_range(60.0, 90.0), 2.6, Style.K_MIST + nf, rng.randf()))
	return out


static func build(maze, _city_theme, seed: int) -> Node3D:
	var root := Node3D.new()
	root.name = "KyotoScenery"
	root.set_script(RootScript)

	var list := cards(maze, seed)
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	quad.center_offset = Vector3(0.0, 0.5, 0.0)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.use_colors = true
	mm.mesh = quad
	mm.instance_count = list.size()
	for i in list.size():
		var c: Dictionary = list[i]
		var basis := Basis(Vector3.UP, c.yaw) * Basis.from_scale(Vector3(c.w, c.h, c.h))
		mm.set_instance_transform(i, Transform3D(basis, c.pos))
		mm.set_instance_custom_data(i, Color(float(c.kind) / 255.0, c.w / 100.0, c.h / 100.0, c.s))
		mm.set_instance_color(i, Color(c.fold_len / 100.0, 0.0, 0.0, 1.0))
	# Folding moves a card's top back by up to its height: one generous box
	# for culling instead of per-frame bounds.
	mm.custom_aabb = AABB(Vector3(-300.0, -5.0, -250.0), Vector3(650.0, 120.0, 600.0))
	var mat := ShaderMaterial.new()
	mat.shader = CARD_SHADER
	mat.set_shader_parameter("ai1", Style.AI1)
	mat.set_shader_parameter("ai2", Style.AI2)
	mat.set_shader_parameter("ai3", Style.AI3)
	mat.set_shader_parameter("ai4", Style.AI4)
	mat.set_shader_parameter("paper", Style.PAPER)
	mat.set_shader_parameter("sumi", Style.SUMI)
	mat.set_shader_parameter("beni", Style.BENI)
	mat.set_shader_parameter("fold_near", Style.FOLD_NEAR)
	mat.set_shader_parameter("fold_far", Style.FOLD_FAR)
	mat.set_shader_parameter("fold_max", Style.FOLD_MAX)
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Cards"
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mmi)
	root.card_material = mat
	root.card_count = list.size()

	var rails := StaticBody3D.new()
	rails.name = "ToriiRails"
	rails.collision_layer = 2 # the wall layer the player collides with
	rails.collision_mask = 0
	for r in torii_rails():
		var shape := BoxShape3D.new()
		shape.size = r.size
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.position = r.center
		rails.add_child(cs)
	root.add_child(rails)

	# Figures stand in doorways; a small block in front of each keeps the
	# camera from pressing into the card (UX N3).
	var fig_body := StaticBody3D.new()
	fig_body.name = "FigureBlocks"
	fig_body.collision_layer = 2
	fig_body.collision_mask = 0
	for c in list:
		if c.kind != Style.K_FIGURE:
			continue
		var n := Vector3(sin(c.yaw), 0.0, cos(c.yaw))
		var shape := BoxShape3D.new()
		shape.size = Vector3(0.7, 2.0, 0.7)
		var cs2 := CollisionShape3D.new()
		cs2.shape = shape
		cs2.position = Vector3(c.pos.x, 1.0, c.pos.z) + n * 0.3
		cs2.rotation.y = c.yaw
		fig_body.add_child(cs2)
	root.add_child(fig_body)

	var sphere := SphereMesh.new()
	sphere.radius = 380.0
	sphere.height = 760.0
	sphere.radial_segments = 32
	sphere.rings = 16
	var sky := MeshInstance3D.new()
	sky.name = "Sky"
	sky.mesh = sphere
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = SKY_SHADER
	sky_mat.set_shader_parameter("top", Style.AI1)
	sky_mat.set_shader_parameter("mid", Style.AI2)
	sky_mat.set_shader_parameter("hor", Style.PAPER)
	sky.material_override = sky_mat
	sky.position = Vector3(48.0, 0.0, 44.0)
	sky.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(sky)
	return root
