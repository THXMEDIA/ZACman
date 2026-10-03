extends SceneTree
## Headless test: the moving Tokyo city (docs/design/tokyo-explorer.md, M2;
## tokyo_life.gd, tokyo_figures.gd, tokyo_wet.gd and the M2 shaders):
## MultiMesh structure and limits (rain <= 8000, 25-30 passers-by plus a
## scramble wave of 100+), the total draw-call budget of Tokyo (statics +
## dynamics) and the additive budget (<= 20), no allocations per frame in
## rain / traffic / passers-by (object, resource and node counters, static
## memory), determinism with the level seed, the scramble phases (cars hold
## during All Walk, the wave crosses straight and diagonally, the crossing
## is clear again before the cars go), cars stop for the player, the comfort
## options, the wet floor (baked puddle mask, <= 8 lights) and the pellets
## as one MultiMesh. Run with
##   godot --headless --path . --script res://tests/test_tokyo_life.gd
## Exits with code 0 on success, 1 on any failure. Main-level checks
## (collision push, settings, theme reset) run in tests/bot_test.gd.

const TokyoMaze := preload("res://scripts/tokyo_maze.gd")
const TokyoLife := preload("res://scripts/tokyo_life.gd")
const Wet := preload("res://scripts/tokyo_wet.gd")
const Style := preload("res://scripts/tokyo_style.gd")
const LEVEL_SEED := 7310

## Draw calls of the whole Tokyo level: statics (<= 20, test_tokyo.gd) +
## pellets (1) + the subway exit (portal, frame, sign: 3) + the moving city
## (6 MultiMeshes). Documented in docs/design/tokyo-explorer.md 4.3.
const TOTAL_DRAW_BUDGET := 32
const DYNAMIC_DRAW_BUDGET := 6
const ADDITIVE_DRAW_BUDGET := 20

var failures := 0
var checks := 0


func _check(name: String, cond: bool, detail := "") -> void:
	checks += 1
	if not cond:
		failures += 1
		print("FAIL ", name, (" -> " + detail) if detail != "" else "")


func _initialize() -> void:
	var maze = TokyoMaze.new().generate()
	var mv := _build_view(maze, LEVEL_SEED)
	var life := _make_life(mv, LEVEL_SEED)

	# ---- structure and limits ----
	_check("life: six MultiMeshes (rain, cars, people, halos, cones, streaks)", life.draw_calls() == DYNAMIC_DRAW_BUDGET and _all_multimesh(life), str(life.draw_calls()))
	_check("rain: at most 8000 drops, one MultiMesh", life.rain_mmi.multimesh.instance_count <= 8000 and life.rain_mmi.multimesh.instance_count == TokyoLife.RAIN_MAX)
	_check("rain: moves in the shader (vertex shader wraps around the camera, no transforms)", _shader_has(life.rain_mmi, "INSTANCE_ID") and _shader_has(life.rain_mmi, "mod("))
	_check("people: 25-30 passers-by in normal operation", TokyoLife.WALKER_COUNT >= 25 and TokyoLife.WALKER_COUNT <= 30)
	_check("people: a scramble wave of 100+ in the same MultiMesh", TokyoLife.CROWD_PER_CORNER * 4 >= 100 and life.walker_mmi.multimesh.instance_count == TokyoLife.WALKER_COUNT + TokyoLife.CROWD_PER_CORNER * 4)
	_check("people: gait in the vertex shader via INSTANCE_CUSTOM (phase, tempo)", _shader_has(life.walker_mmi, "INSTANCE_CUSTOM") and _shader_has(life.walker_mmi, "TIME") and life.walker_mmi.multimesh.use_custom_data)
	_check("cars: wire figures in one MultiMesh, white head lights front, red tail lights back", life.car_mmi.multimesh.instance_count == life.car_count() and life.car_count() >= 12 and Style.HEADLIGHT.is_equal_approx(Color.WHITE) and Style.TAILLIGHT.r > 0.9 and Style.TAILLIGHT.g < 0.2)
	_check("halos: lamps, subway and 4 per car in one MultiMesh", life.halo_mmi.multimesh.instance_count == TokyoLife.TokyoScenery.LAMPS.size() + 1 + life.car_count() * 4)
	_check("cones: lamps, subway and 2 beams per car in one MultiMesh", life.cone_mmi.multimesh.instance_count == TokyoLife.TokyoScenery.LAMPS.size() + 1 + life.car_count() * 2)
	var metro_hz: float = life.halo_mmi.multimesh.get_instance_custom_data(TokyoLife.TokyoScenery.LAMPS.size()).a
	_check("subway: pulses below 3 Hz (halo and cone)", metro_hz > 0.0 and metro_hz < 3.0 and life.cone_mmi.multimesh.get_instance_custom_data(TokyoLife.TokyoScenery.LAMPS.size()).a < 3.0, str(metro_hz))
	var walker_lum := _lum(Style.PASSERBY) * float(life.walker_mmi.material_override.get_shader_parameter("energy"))
	var line_lum := _lum(Style.WHITE) * Style.WHITE_ENERGY
	_check("people: about half as bright as the building lines", walker_lum > line_lum * 0.25 and walker_lum < line_lum * 0.6, "%.2f vs %.2f" % [walker_lum, line_lum])

	# ---- draw-call budget (statics + dynamics) ----
	var geo := []
	_collect(mv, geo)
	_collect(life, geo)
	var metro = load("res://scripts/tokyo_metro_station.gd").new()
	root.add_child(metro)
	metro.setup(Vector3(TokyoMaze.METRO_CELL.y * 2.0, 0.9, TokyoMaze.METRO_CELL.x * 2.0))
	_collect(metro, geo)
	_check("budget: Tokyo total <= %d draw calls (statics, pellets, subway, moving city)" % TOTAL_DRAW_BUDGET, geo.size() <= TOTAL_DRAW_BUDGET, "%d: %s" % [geo.size(), ", ".join(geo.map(func(g): return String(g.name)))])
	var additive := []
	for g in geo:
		if _is_additive(g):
			additive.append(String(g.name))
	_check("budget: additive elements <= %d draw calls" % ADDITIVE_DRAW_BUDGET, additive.size() <= ADDITIVE_DRAW_BUDGET and additive.size() >= 5, "%d: %s" % [additive.size(), ", ".join(additive)])
	print("TOKYO DRAW CALLS: total %d, additive %d (%s)" % [geo.size(), additive.size(), ", ".join(additive)])

	# ---- pellets as one MultiMesh ----
	_check("pellets: one MultiMesh instance per pellet", mv.pellet_mmi != null and mv.pellet_multimesh.instance_count == mv.pellet_cells.size())
	var p0: Vector3 = mv.pellet_position(0)
	_check("pellets: visible before eating", mv.pellet_visible(0))
	var eaten: Dictionary = mv.consume_at(p0, 0.0)
	_check("pellets: an eaten pellet collapses its instance (no node per pellet)", eaten.pellet and not mv.pellet_visible(0) and mv.pellet_visible(1) and mv.remaining_pickups() == mv.pellet_cells.size() - 1)

	# ---- wet floor ----
	var fm: ShaderMaterial = mv.floor_mesh.material_override
	_check("floor: the wet floor shader", fm != null and fm.shader.resource_path.ends_with("tokyo_floor.gdshader"))
	var mask = fm.get_shader_parameter("puddle_tex")
	_check("floor: pre-baked puddle mask texture (no fbm per pixel)", mask is Texture2D and mask.get_width() == Wet.MASK_SIZE and fm.shader.code.find("fbm(") == -1)
	_check("floor: roughness follows the puddle mask (SSR roughness mask)", fm.shader.code.find("ROUGHNESS = mix(") != -1)
	_check("floor: at most 8 light pools", int(fm.get_shader_parameter("light_n")) <= 8 and fm.shader.code.find("light_pos[8]") != -1)
	_check("floor: same seed -> same mask, other seed -> other mask", Wet.bake_puddle_mask(LEVEL_SEED) == mask and Wet.bake_puddle_mask(LEVEL_SEED + 1).get_image().get_data() != mask.get_image().get_data())
	var refl: Node = mv.scenery_root.get_node_or_null("Bodenspiegelung")
	_check("floor: reflection fallback without SSR (Compatibility), off with SSR", (refl != null) == (not Wet.ssr_available()))
	_check("floor: never black (lift and sky reflection)", fm.shader.code.find("floor_lift") != -1 and float(fm.get_shader_parameter("floor_lift") if fm.get_shader_parameter("floor_lift") != null else 0.006) > 0.0)

	# ---- rain thins out over the pellets ----
	var pm: Texture2D = life.rain_material.get_shader_parameter("pellet_map")
	var cell: Vector2i = mv.pellet_cells[3]
	_check("rain: lighter where the pellets lie (pellet map)", pm != null and pm.get_image().get_pixel(cell.y, cell.x).r > 0.9 and pm.get_image().get_pixel(0, 0).r < 0.1)
	_check("rain: lit by at most 8 lights", int(life.rain_material.get_shader_parameter("light_n")) <= 8 and int(life.rain_material.get_shader_parameter("light_n")) > 0)

	# ---- comfort ----
	life.set_comfort(true, false)
	_check("comfort: 'Regen reduzieren' -> 35 % of the drops, dimmer", life.rain_visible_count() == int(8000 * 0.35) and life.rain_gain() < 0.7)
	life.set_comfort(false, true)
	_check("comfort: 'Effekte reduzieren' dampens the rain too", life.rain_visible_count() == int(8000 * 0.7) and life.rain_gain() < 1.0)
	life.set_comfort(true, true)
	_check("comfort: both -> the fewest drops", life.rain_visible_count() == int(8000 * 0.35) and life.rain_gain() <= 0.5)
	life.set_comfort(false, false)
	_check("comfort: off -> full rain", life.rain_visible_count() == 8000 and is_equal_approx(life.rain_gain(), 1.0))

	# ---- no allocations per frame ----
	var cam := Vector3(48.6, 0.95, 64.0)
	for i in 120:
		life.update(1.0 / 60.0, cam, cam)
	var obj0 := Performance.get_monitor(Performance.OBJECT_COUNT)
	var res0 := Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)
	var node0 := _count_nodes(root)
	var mem0 := OS.get_static_memory_usage()
	for i in 600:
		life.update(1.0 / 60.0, cam + Vector3(0, 0, -i * 0.05), cam + Vector3(0, 0, -i * 0.05))
	var obj1 := Performance.get_monitor(Performance.OBJECT_COUNT)
	var res1 := Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)
	var node1 := _count_nodes(root)
	var mem1 := OS.get_static_memory_usage()
	_check("frames: no new objects in 600 frames of rain, traffic and people", obj1 == obj0, "%d -> %d" % [obj0, obj1])
	_check("frames: no new resources (no mesh rebuild)", res1 == res0, "%d -> %d" % [res0, res1])
	_check("frames: no new nodes (no node per figure)", node1 == node0, "%d -> %d" % [node0, node1])
	_check("frames: static memory does not grow", mem1 - mem0 < 64 * 1024, "%d bytes" % (mem1 - mem0))
	print("TOKYO FRAME COUNTERS: objects %d -> %d, resources %d -> %d, nodes %d -> %d, static memory %+d bytes" % [obj0, obj1, res0, res1, node0, node1, mem1 - mem0])

	# ---- determinism with the level seed ----
	var a := _make_life(mv, LEVEL_SEED)
	var b := _make_life(mv, LEVEL_SEED)
	var c := _make_life(mv, LEVEL_SEED + 1)
	a.advance(47.0)
	b.advance(47.0)
	c.advance(47.0)
	_check("determinism: same seed -> same traffic", a.car_s == b.car_s and a.car_v == b.car_v)
	_check("determinism: same seed -> same people", a.p_pos == b.p_pos and a.p_vis == b.p_vis)
	_check("determinism: other seed -> other traffic and people", a.car_s != c.car_s and a.p_pos != c.p_pos)

	# ---- scramble phases ----
	var s := _make_life(mv, LEVEL_SEED)
	var walk_signals := [0]
	s.walk_started.connect(func(): walk_signals[0] += 1)
	var moved_in_flow := false
	var t := 0.0
	var step := 1.0 / 30.0
	while not s.is_walk_phase() and t < 90.0:
		s.advance(step)
		t += step
		for i in s.car_count():
			if s.car_speed(i) > 3.0:
				moved_in_flow = true
	_check("scramble: traffic flows before All Walk", moved_in_flow)
	_check("scramble: All Walk after ~24 s (cycle 80 s: 60 s traffic, 20 s walk)", absf(t - (TokyoLife.WALK_START - TokyoLife.CYCLE_START)) < 0.2 and is_equal_approx(TokyoLife.WALK_END - TokyoLife.WALK_START, 20.0) and is_equal_approx(TokyoLife.WALK_START, 60.0), "%.2f s" % t)
	_check("scramble: the walk phase announces itself (tone signal)", walk_signals[0] == 1)
	_check("scramble: both car directions red during All Walk", not s.is_green(0) and not s.is_green(1) and s.phase() == "walk")
	var waiting := 0
	for i in 112:
		if s.walker_visible(TokyoLife.WALKER_COUNT + i):
			waiting += 1
	_check("scramble: the crowd waits at the corners (100+)", waiting >= 100, str(waiting))
	s.advance(3.0)
	var cars_hold := true
	var crowd_max := 0
	var wave_max := 0
	var diagonal_seen := false
	var crossing_steps := int((TokyoLife.WALK_END - TokyoLife.WALK_START - 3.0) / step) - 1
	for k in crossing_steps:
		s.advance(step)
		for i in s.car_count():
			if s.car_speed(i) > 0.05 and s.car_in_crossing(i):
				cars_hold = false
		crowd_max = maxi(crowd_max, s.crowd_in_crossing())
		var wave := 0
		for i in range(TokyoLife.WALKER_COUNT, s.walker_count()):
			if s.walker_moving(i):
				wave += 1
		wave_max = maxi(wave_max, wave)
		for i in range(TokyoLife.WALKER_COUNT, s.walker_count()):
			var p: Vector3 = s.walker_position(i)
			if s.walker_moving(i) and absf(p.x - 46.0) < 1.5 and absf(p.z - 46.0) < 1.5:
				diagonal_seen = true
	_check("scramble: cars hold during All Walk (none moves in the crossing)", cars_hold)
	_check("scramble: a wave of 100+ people crossing at once", wave_max >= 100, str(wave_max))
	_check("scramble: 30+ of them inside the crossing field at once (diagonals, edges)", crowd_max >= 30, str(crowd_max))
	_check("scramble: people cross diagonally (through the center)", diagonal_seen)
	_check("scramble: the crossing is clear when the walk ends", s.crowd_in_crossing() == 0, str(s.crowd_in_crossing()))
	s.advance(1.0)
	_check("scramble: then north-south traffic gets green", s.is_green(0) and not s.is_walk_phase())
	s.advance(15.0)
	var moving_again := false
	for i in s.car_count():
		if s.car_speed(i) > 2.0:
			moving_again = true
	_check("scramble: traffic flows again", moving_again)

	# ---- cars stop for the player in their lane ----
	var cp := _make_life(mv, LEVEL_SEED)
	var player := Vector3(44.5, 0.95, 72.0) # northbound inner lane, south avenue
	var too_close := false
	var stopped_behind := false
	for k in 900:
		cp.advance(step, player)
		for i in cp.car_count():
			var q: Vector3 = cp.car_position(i)
			if absf(q.x - player.x) < 0.5 and absf(q.z - player.z) < 2.6:
				too_close = true
			if absf(q.x - player.x) < 0.5 and q.z > player.z and q.z < player.z + 6.0 and cp.car_speed(i) < 0.05:
				stopped_behind = true
	_check("cars: stop for the player standing in their lane", stopped_behind and not too_close)
	var cpt: Vector3 = cp.car_closest_point(0, cp.car_position(0) + Vector3(5, 0, 5))
	_check("cars: obstacle capsule along the car axis", cpt.distance_to(cp.car_position(0)) <= TokyoLife.CAR_AXIS_HALF + 0.001)

	if failures == 0:
		print("ALL %d TOKYO LIFE CHECKS PASSED" % checks)
	else:
		print("%d OF %d TOKYO LIFE CHECKS FAILED" % [failures, checks])
	quit(1 if failures > 0 else 0)


func _build_view(maze, seed: int) -> Node3D:
	var mv = load("res://scripts/maze_view.gd").new()
	root.add_child(mv)
	mv.build(maze, maze.start_cell, "tokyo", TokyoMaze.metro_cells(), TokyoMaze.metro_cells(), -1, "", seed)
	return mv


func _make_life(mv: Node3D, seed: int) -> Node3D:
	var life = TokyoLife.new()
	root.add_child(life)
	life.setup(mv, seed)
	return life


func _all_multimesh(node: Node) -> bool:
	for ch in node.get_children():
		if ch is GeometryInstance3D and not (ch is MultiMeshInstance3D):
			return false
	return true


func _shader_has(mmi: GeometryInstance3D, text: String) -> bool:
	var m: ShaderMaterial = mmi.material_override
	return m != null and m.shader.code.find(text) != -1


func _is_additive(g: GeometryInstance3D) -> bool:
	var m: Material = g.material_override
	if m == null and g is MeshInstance3D and g.mesh != null:
		m = g.mesh.surface_get_material(0)
	return m is ShaderMaterial and m.shader != null and m.shader.code.find("blend_add") != -1


func _collect(node: Node, geo: Array) -> void:
	for ch in node.get_children():
		if ch.is_queued_for_deletion():
			continue
		if ch is GeometryInstance3D and ch.visible:
			geo.append(ch)
		_collect(ch, geo)


func _count_nodes(n: Node) -> int:
	var k := 1
	for ch in n.get_children():
		k += _count_nodes(ch)
	return k


func _lum(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
