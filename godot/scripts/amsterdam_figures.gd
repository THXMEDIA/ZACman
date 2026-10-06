extends RefCounted
## AmsterdamFigures — the little cardboard people and bicycles of the Amsterdam
## model (docs/design/amsterdam-explorer.md, "Passanten und Fahrräder"): flat
## cut-outs of thin card (1 mm x 100 = 10 cm), two cut-outs crossed at 90
## degrees like the trees of the model (no figure is a paper-thin slab seen
## edge-on), the cut edge shows kraft board, the faces the printed paper, a
## round base disc under the feet like architectural-model people. Everything
## procedural, no copied assets. Two meshes, each ONE MultiMesh in
## amsterdam_life.gd; the gait is animated in amsterdam_folk.gdshader from
## the vertex attributes below, the CPU only moves instance transforms.
##
## Local frame: forward -Z, right +X, up +Y, origin on the floor.
## Vertex attributes:
##   COLOR.r  part id / 16 (P_* below)       COLOR.g  weight 0 at the pivot
##   COLOR.b  unused                          (hip, shoulder) .. 1 at the
##   COLOR.a  1 on the cut edge (kraft)       free end (foot, hand)
##   UV       edge faces: (along, 0..1 across the card), faces: (0, 0)
## Palette texture: folk_palette() (rows: coats, skins, bike frames).

const CARD := 0.10 # thickness of the card (m)

## Parts (COLOR.r * 16).
const P_COAT := 0
const P_LEG_A := 1
const P_LEG_B := 2
const P_ARM_A := 3
const P_ARM_B := 4
const P_HEAD := 5
const P_BASE := 6
const P_FRAME := 7
const P_WHEEL := 8
const P_MARK_R := 9 # rim marker of the rear wheel (turns around the hub)
const P_MARK_F := 10 # ... of the front wheel
const P_SPOT := 11 # saddle, bell: dark small parts

## Bicycle geometry (side view, u = forward, v = up; the hubs are the pivots
## of the wheel markers in the shader).
const WHEEL_R := 0.34
const HUB_REAR := Vector2(-0.55, 0.34)
const HUB_FRONT := Vector2(0.55, 0.34)
const HIP_Y := 0.84
const SHOULDER_Y := 1.45
const HEIGHT := 1.75 # standing figure incl. head
## Bike total length (m, wheel to wheel plus tyre) - used by the parked-bike
## push capsule.
const BIKE_LEN := 1.78

const PAL_W := 8
const PAL_H := 4


class FigBuf:
	var V := PackedVector3Array()
	var N := PackedVector3Array()
	var C := PackedColorArray()
	var U := PackedVector2Array()

	func tri(a: Vector3, b: Vector3, c: Vector3, n: Vector3, cols: Array, uvs: Array) -> void:
		var o := [0, 1, 2]
		if (b - a).cross(c - a).dot(n) > 0.0:
			o = [0, 2, 1]
		var pts := [a, b, c]
		for k in o:
			V.append(pts[k])
			N.append(n)
			C.append(cols[k])
			U.append(uvs[k])

	## A flat shape (u, v) cut out of card: `ax` = direction of u, the card's
	## thickness runs along `nz`; centred on the plane through the origin.
	## `w` are the per-vertex weights (null: 0). Front and back face plus the
	## kraft cut edge.
	func shape(pts: PackedVector2Array, ax: Vector3, nz: Vector3, thick: float, part: int, w = null) -> void:
		var poly := pts
		var wt: PackedFloat32Array = w if w != null else PackedFloat32Array()
		if wt.is_empty():
			wt.resize(poly.size())
		if Geometry2D.is_polygon_clockwise(poly):
			poly = poly.duplicate()
			poly.reverse()
			wt = wt.duplicate()
			wt.reverse()
		var pid := float(part) / 16.0
		var hz := thick * 0.5
		var idx := Geometry2D.triangulate_polygon(poly)
		if idx.is_empty():
			return
		for side in [1.0, -1.0]:
			var nn: Vector3 = nz * side
			for i in range(0, idx.size(), 3):
				var cols := []
				var pp := []
				for k in 3:
					var q := poly[idx[i + k]]
					pp.append(ax * q.x + Vector3(0, q.y, 0) + nz * (hz * side))
					cols.append(Color(pid, wt[idx[i + k]], 0.0, 0.0))
				tri(pp[0], pp[1], pp[2], nn, cols, [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
		var acc := 0.0
		for i in poly.size():
			var p0 := poly[i]
			var p1 := poly[(i + 1) % poly.size()]
			var seg := p1 - p0
			var sl := seg.length()
			if sl < 0.0001:
				continue
			var n2 := Vector2(seg.y, -seg.x) / sl
			var nn := (ax * n2.x + Vector3(0, n2.y, 0)).normalized()
			var a0 := ax * p0.x + Vector3(0, p0.y, 0) + nz * hz
			var a1 := ax * p1.x + Vector3(0, p1.y, 0) + nz * hz
			var b0 := ax * p0.x + Vector3(0, p0.y, 0) - nz * hz
			var b1 := ax * p1.x + Vector3(0, p1.y, 0) - nz * hz
			var c0 := Color(pid, wt[i], 0.0, 1.0)
			var c1 := Color(pid, wt[(i + 1) % poly.size()], 0.0, 1.0)
			tri(a0, a1, b1, nn, [c0, c1, c1], [Vector2(acc, 0), Vector2(acc + sl, 0), Vector2(acc + sl, 1)])
			tri(a0, b1, b0, nn, [c0, c1, c0], [Vector2(acc, 0), Vector2(acc + sl, 1), Vector2(acc, 1)])
			acc += sl

	## A straight bar from a to b, `width` wide; weight 0 at a, 1 at b.
	func bar(a: Vector2, b: Vector2, width: float, ax: Vector3, nz: Vector3, thick: float, part: int) -> void:
		var d := (b - a).normalized()
		var n := Vector2(-d.y, d.x) * width * 0.5
		shape(PackedVector2Array([a - n, a + n, b + n, b - n]), ax, nz, thick, part, PackedFloat32Array([0.0, 0.0, 1.0, 1.0]))

	## A flat ring (tyre): outer / inner radius, around `c`.
	func ring(c: Vector2, r_out: float, r_in: float, n: int, ax: Vector3, nz: Vector3, thick: float, part: int) -> void:
		var pid := float(part) / 16.0
		var hz := thick * 0.5
		var col_f := Color(pid, 0.0, 0.0, 0.0)
		var col_e := Color(pid, 0.0, 0.0, 1.0)
		for i in n:
			var a0 := TAU * float(i) / n
			var a1 := TAU * float(i + 1) / n
			var d0 := Vector2(cos(a0), sin(a0))
			var d1 := Vector2(cos(a1), sin(a1))
			var o0 := c + d0 * r_out
			var o1 := c + d1 * r_out
			var i0 := c + d0 * r_in
			var i1 := c + d1 * r_in
			for side: float in [1.0, -1.0]:
				var z: Vector3 = nz * (hz * side)
				var P := func(q: Vector2) -> Vector3: return ax * q.x + Vector3(0, q.y, 0) + z
				var nn: Vector3 = nz * side
				tri(P.call(o0), P.call(o1), P.call(i1), nn, [col_f, col_f, col_f], [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
				tri(P.call(o0), P.call(i1), P.call(i0), nn, [col_f, col_f, col_f], [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
			for e in [[o0, o1, 1.0], [i0, i1, -1.0]]:
				var q0: Vector2 = e[0]
				var q1: Vector2 = e[1]
				var dm := ((d0 + d1) * 0.5).normalized() * float(e[2])
				var nn2 := ax * dm.x + Vector3(0, dm.y, 0)
				var A0 := ax * q0.x + Vector3(0, q0.y, 0) + nz * hz
				var A1 := ax * q1.x + Vector3(0, q1.y, 0) + nz * hz
				var B0 := ax * q0.x + Vector3(0, q0.y, 0) - nz * hz
				var B1 := ax * q1.x + Vector3(0, q1.y, 0) - nz * hz
				tri(A0, A1, B1, nn2, [col_e, col_e, col_e], [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1)])
				tri(A0, B1, B0, nn2, [col_e, col_e, col_e], [Vector2(0, 0), Vector2(1, 1), Vector2(0, 1)])

	## The base disc under the feet (card too): a fat low cylinder.
	func disc(r: float, h: float, n: int, part: int) -> void:
		var pid := float(part) / 16.0
		var col_f := Color(pid, 0.0, 0.0, 0.0)
		var col_e := Color(pid, 0.0, 0.0, 1.0)
		for i in n:
			var a0 := TAU * float(i) / n
			var a1 := TAU * float(i + 1) / n
			var p0 := Vector3(cos(a0) * r, 0.0, sin(a0) * r)
			var p1 := Vector3(cos(a1) * r, 0.0, sin(a1) * r)
			var t0 := p0 + Vector3(0, h, 0)
			var t1 := p1 + Vector3(0, h, 0)
			tri(Vector3(0, h, 0), t0, t1, Vector3.UP, [col_f, col_f, col_f], [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
			var nm := Vector3(cos((a0 + a1) * 0.5), 0.0, sin((a0 + a1) * 0.5))
			tri(p0, p1, t1, nm, [col_e, col_e, col_e], [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1)])
			tri(p0, t1, t0, nm, [col_e, col_e, col_e], [Vector2(0, 0), Vector2(1, 1), Vector2(0, 1)])

	func commit() -> ArrayMesh:
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = V
		arr[Mesh.ARRAY_NORMAL] = N
		arr[Mesh.ARRAY_COLOR] = C
		arr[Mesh.ARRAY_TEX_UV] = U
		var m := ArrayMesh.new()
		if V.size() > 0:
			m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		return m


static func circle(c: Vector2, r: float, n: int) -> PackedVector2Array:
	var p := PackedVector2Array()
	for i in n:
		var a := TAU * float(i) / n
		p.append(c + Vector2(cos(a), sin(a)) * r)
	return p


## The two crossed planes: the side view (u runs forward, thickness along X)
## and the front view (u runs right, thickness along Z).
static func _side_ax() -> Vector3:
	return Vector3(0, 0, -1)


## A standing / walking person, 1.75 m: coat, head, two legs and two arms (the
## shader swings the free ends), a base disc under the feet.
static func walker_mesh() -> ArrayMesh:
	var B := FigBuf.new()
	var sx := _side_ax()
	var sn := Vector3(1, 0, 0)
	var fx := Vector3(1, 0, 0)
	var fn := Vector3(0, 0, 1)
	# side view: long coat, head a little proud of it, legs and arms in the
	# thicknesses 0.08 (legs) / 0.10 (coat) / 0.12 (head) / 0.13 (arms): no
	# two faces in one plane
	B.shape(PackedVector2Array([Vector2(-0.12, 1.50), Vector2(0.13, 1.50), Vector2(0.16, 0.80), Vector2(-0.18, 0.80)]), sx, sn, CARD, P_COAT)
	B.shape(circle(Vector2(0.02, 1.64), 0.115, 12), sx, sn, 0.12, P_HEAD)
	B.bar(Vector2(0.0, HIP_Y), Vector2(0.20, 0.05), 0.13, sx, sn, 0.08, P_LEG_A)
	B.bar(Vector2(0.0, HIP_Y), Vector2(-0.20, 0.05), 0.13, sx, sn, 0.08, P_LEG_B)
	B.bar(Vector2(0.0, SHOULDER_Y), Vector2(-0.17, 0.95), 0.09, sx, sn, 0.13, P_ARM_A)
	B.bar(Vector2(0.0, SHOULDER_Y), Vector2(0.17, 0.95), 0.09, sx, sn, 0.13, P_ARM_B)
	# front view: the coat a little wider at the hem, legs close together
	B.shape(PackedVector2Array([Vector2(-0.20, 1.50), Vector2(0.20, 1.50), Vector2(0.24, 0.80), Vector2(-0.24, 0.80)]), fx, fn, 0.09, P_COAT)
	B.shape(circle(Vector2(0.0, 1.64), 0.115, 12), fx, fn, 0.11, P_HEAD)
	B.bar(Vector2(-0.07, HIP_Y), Vector2(-0.09, 0.05), 0.11, fx, fn, 0.07, P_LEG_A)
	B.bar(Vector2(0.07, HIP_Y), Vector2(0.09, 0.05), 0.11, fx, fn, 0.07, P_LEG_B)
	B.bar(Vector2(-0.20, SHOULDER_Y - 0.02), Vector2(-0.27, 0.95), 0.08, fx, fn, 0.12, P_ARM_A)
	B.bar(Vector2(0.20, SHOULDER_Y - 0.02), Vector2(0.27, 0.95), 0.08, fx, fn, 0.12, P_ARM_B)
	B.disc(0.27, 0.045, 12, P_BASE)
	return B.commit()


## A bicycle with a rider (the shader hides the rider for a parked bike):
## frame, two tyre rings with a rim marker each, a pedalling rider seated
## upright, handlebars. Side view with a narrow front view crossed through it.
static func bike_mesh() -> ArrayMesh:
	var B := FigBuf.new()
	var sx := _side_ax()
	var sn := Vector3(1, 0, 0)
	var fx := Vector3(1, 0, 0)
	var fn := Vector3(0, 0, 1)
	# tyres (rings) and the rim marker of each wheel
	for h in [HUB_REAR, HUB_FRONT]:
		B.ring(h, WHEEL_R, WHEEL_R - 0.045, 20, sx, sn, 0.07, P_WHEEL)
	for k in 2:
		var h: Vector2 = HUB_REAR if k == 0 else HUB_FRONT
		var m := Vector2(h.x, h.y + WHEEL_R - 0.11)
		B.shape(PackedVector2Array([m + Vector2(-0.035, -0.035), m + Vector2(0.035, -0.035), m + Vector2(0.035, 0.035), m + Vector2(-0.035, 0.035)]), sx, sn, 0.09, P_MARK_R if k == 0 else P_MARK_F)
	# frame: chain stay, seat stay, seat tube, down tube, top tube, head
	# tube, fork (all 4.5 cm tubes, 6 cm card)
	var bb := Vector2(-0.02, 0.30)
	var seat := Vector2(-0.22, 0.90)
	var head_top := Vector2(0.40, 0.93)
	var head_bot := Vector2(0.44, 0.80)
	for t in [[HUB_REAR, bb], [HUB_REAR, seat], [bb, seat], [bb, head_bot], [seat, head_top], [head_bot, head_top], [head_bot, HUB_FRONT]]:
		B.bar(t[0], t[1], 0.045, sx, sn, 0.06, P_FRAME)
	B.bar(Vector2(-0.62, 0.70), Vector2(-0.28, 0.74), 0.04, sx, sn, 0.06, P_FRAME) # rear carrier
	B.bar(Vector2(-0.62, 0.70), HUB_REAR, 0.03, sx, sn, 0.06, P_FRAME)
	B.bar(head_top, Vector2(0.30, 1.04), 0.04, sx, sn, 0.07, P_FRAME) # handlebar
	B.bar(Vector2(-0.34, 0.945), Vector2(-0.12, 0.945), 0.07, sx, sn, 0.09, P_SPOT) # saddle
	# rider, side view: torso leaning a little, head, arm to the grip, legs to the pedals
	B.bar(Vector2(-0.22, 1.00), Vector2(0.10, 1.50), 0.26, sx, sn, CARD, P_COAT)
	B.shape(circle(Vector2(0.16, 1.66), 0.115, 12), sx, sn, 0.12, P_HEAD)
	B.bar(Vector2(0.10, SHOULDER_Y), Vector2(0.30, 1.04), 0.09, sx, sn, 0.13, P_ARM_A)
	B.bar(Vector2(-0.20, 0.98), Vector2(0.03, 0.34), 0.13, sx, sn, 0.08, P_LEG_A)
	B.bar(Vector2(-0.20, 0.98), Vector2(0.03, 0.34), 0.13, sx, sn, 0.075, P_LEG_B)
	# front view (narrow): rider, handlebar, wheel edge-on
	B.shape(PackedVector2Array([Vector2(-0.19, 1.50), Vector2(0.19, 1.50), Vector2(0.17, 0.98), Vector2(-0.17, 0.98)]), fx, fn, 0.09, P_COAT)
	B.shape(circle(Vector2(0.0, 1.66), 0.115, 12), fx, fn, 0.11, P_HEAD)
	B.bar(Vector2(-0.10, 0.98), Vector2(-0.13, 0.33), 0.11, fx, fn, 0.07, P_LEG_A)
	B.bar(Vector2(0.10, 0.98), Vector2(0.13, 0.33), 0.11, fx, fn, 0.065, P_LEG_B)
	B.bar(Vector2(-0.30, 1.04), Vector2(0.30, 1.04), 0.04, fx, fn, 0.06, P_FRAME) # handlebar
	B.bar(Vector2(-0.23, 1.46), Vector2(-0.29, 1.04), 0.08, fx, fn, 0.12, P_ARM_A)
	return B.commit()


## The colours: 8 columns x 4 rows (nearest filtering, sRGB):
## row 0 coats, 1 skin tones (4 used), 2 bike frames, 3 spare (graphite).
static func folk_palette() -> ImageTexture:
	var Style := load("res://scripts/amsterdam_style.gd")
	var img := Image.create(PAL_W, PAL_H, false, Image.FORMAT_RGB8)
	for i in PAL_W:
		img.set_pixel(i, 0, Style.FOLK_COATS[i])
		img.set_pixel(i, 1, Style.FOLK_SKIN[i % Style.FOLK_SKIN.size()])
		img.set_pixel(i, 2, Style.FOLK_BIKES[i])
		img.set_pixel(i, 3, Style.FOLK_BIKES[0])
	return ImageTexture.create_from_image(img)
