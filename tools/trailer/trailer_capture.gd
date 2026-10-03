# Trailer-Aufnahme für ZAPmaniac (Pitch v2, intern, nicht zur Veröffentlichung).
#
# Nimmt die Spielszenen des Trailers als PNG-Folgen auf; Texttafeln, Timer,
# Bestenliste, Chat und Übergänge kommen erst im Schnitt dazu
# (tools/trailer/compose.py). Deterministisch: feste Seeds, feste Bildrate,
# Kamera und Bewegung sind skriptgesteuert, Geister bleiben im Haus.
#
# Aufruf aus dem Repo-Wurzelverzeichnis (Cloud: Software-Rendering):
#   cp tools/trailer/trailer_capture.gd godot/trailer_capture.gd
#   SHOT_DIR=/pfad/frames SEGS=s02,s03 xvfb-run -a -s "-screen 0 1920x1080x24" \
#     godot --rendering-driver opengl3 --path godot --resolution 1920x1080 \
#     --fixed-fps 30 --script res://trailer_capture.gd
#   rm godot/trailer_capture.gd
# Auf dem eigenen PC (Forward+, mit SSR/Glow) dieselbe Zeile ohne xvfb-run und
# ohne --rendering-driver.
#
# Jede Szene schreibt nach SHOT_DIR/<szene>/f00000.png …
extends SceneTree

const Conditions := preload("res://scripts/conditions.gd")
const FPS := 30.0
const CELL := 2.0

var main: Node
var out_dir := ""
var segs: Array = []
var mg  # MazeGen autoload


func _initialize() -> void:
	out_dir = OS.get_environment("SHOT_DIR")
	if out_dir == "":
		out_dir = "user://trailer"
	var s := OS.get_environment("SEGS")
	segs = s.split(",") if s != "" else ["s02", "s03", "s04", "s05", "s06", "s07", "s08", "s09", "s11", "s12", "s13", "s14"]
	seed(4242)
	# 16:9 for the trailer: the project is 16:10 with "keep" aspect, which
	# would letterbox to 1728×1080; "expand" fills the full 1920×1080 window.
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	mg = root.get_node("MazeGen")
	_run()


# ---------------------------------------------------------------- helpers

func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _save(seg: String, i: int) -> void:
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join(seg).path_join("f%05d.png" % i))


func _cell_pos(c: Vector2i) -> Vector3:
	return Vector3(c.y * CELL, main.player.EYE_H, c.x * CELL)


func _pose_v(p: Vector3, yaw: float, pitch: float = 0.0) -> void:
	main.player.global_position = p
	main.player.yaw = yaw
	main.player.pitch = pitch
	main.player.rotation.y = yaw
	main.player.camera.rotation.x = pitch


func _pose(x: float, z: float, yaw: float, pitch: float = 0.0, lift: float = 0.0) -> void:
	_pose_v(Vector3(x, main.player.EYE_H + lift, z), yaw, pitch)


func _yaw_dir(d: Vector3) -> float:
	return atan2(-d.x, -d.z)


func _calm() -> void:
	main.invuln_until = 1e9
	for e in main.enemies:
		e.release_at = 1e9


func _hud(on: bool) -> void:
	main.hud.visible = on


## Starts a speedrun level without the intro hold; HUD off for clean frames.
func _speedrun(level_id: String) -> void:
	main.go_to_main_menu()
	await _frames(3)
	main.rabbit_week_override = Vector2i(2026, 41)
	main.begin_game(level_id)
	_calm()
	await _frames(10)
	main.intro_until_real = main.real_now
	await _frames(3)
	main.start_hold = false
	main.player.movement_locked = true
	_calm()
	_hud(false)
	main.player.camera.fov = 92.0
	await _frames(10)


## A run built for the camera: keeps going straight while it can and, at
## every bend or junction, takes the way with the longest straight corridor
## ahead (unused corridors first). Never turns back; ends at a dead end.
## Skips the rabbit cell and the ghost house.
func _walk_path(from: Vector2i, length: int, first_dir := Vector2i.ZERO) -> Array:
	var path := [from]
	var used := {from: true}
	var cur := from
	var dir := first_dir
	while path.size() < length:
		var best := Vector2i(-99, -99)
		var best_run := -1000
		for n in mg.neighbors_of_no_wrap(main.maze, cur.x, cur.y):
			var d: Vector2i = n - cur
			if d == -dir or n == main.maze_view.rabbit_cell or main.in_ghost_house(_cell_pos(n)):
				continue
			var run := _straight_run(n, d, used)
			if used.has(n):
				run -= 20
			if d == dir:
				run += 2 # prefer not to turn
			if run > best_run:
				best_run = run
				best = n
		if best.x == -99:
			break
		dir = best - cur
		cur = best
		used[cur] = true
		path.append(cur)
	return path


## Tries every open cell and direction as a start and returns the first
## run that is at least `cells` long (else the longest one found).
func _long_run(cells: int, skip: int = 0) -> Array:
	var best: Array = []
	var found := 0
	for r in main.maze.rows:
		for c in main.maze.cols:
			var cell := Vector2i(r, c)
			if not mg.is_open(main.maze, r, c) or main.in_ghost_house(_cell_pos(cell)) or cell == main.maze_view.rabbit_cell:
				continue
			for n in mg.neighbors_of_no_wrap(main.maze, r, c):
				var p := _walk_path(cell, cells, n - cell)
				if p.size() >= cells:
					if found == skip:
						return p
					found += 1
				if p.size() > best.size():
					best = p
	return best


func _straight_run(c: Vector2i, d: Vector2i, used: Dictionary) -> int:
	var n := 0
	var k := c
	while mg.is_open(main.maze, k.x, k.y) and not used.has(k) and n < 30:
		n += 1
		k += d
	return n


## Rounds the corners of the cell polyline (Chaikin, two passes) so the
## camera runs through bends instead of facing the wall.
func _smooth(pts: Array) -> Array:
	var out := pts
	for pass_i in 2:
		var nxt := [out[0]]
		for k in range(out.size() - 1):
			var a: Vector3 = out[k]
			var b: Vector3 = out[k + 1]
			nxt.append(a.lerp(b, 0.25))
			nxt.append(a.lerp(b, 0.75))
		nxt.append(out[out.size() - 1])
		out = nxt
	return out


## Moves the camera along a cell path at `speed` units/s for `frames`
## frames, saving every frame; the view turns smoothly into the corners.
func _run_path(seg: String, path: Array, frames: int, speed: float, start_frame := 0, per_frame: Callable = Callable()) -> int:
	var pts: Array = []
	for c in path:
		pts.append(_cell_pos(c))
	pts = _smooth(pts)
	var dist := 0.0
	var yaw := _yaw_dir(pts[1] - pts[0])
	var i := start_frame
	for f in frames:
		var p := _point_at(pts, dist)
		var ahead := _point_at(pts, dist + 3.2)
		var want := yaw if ahead.distance_to(p) < 0.01 else _yaw_dir(ahead - p)
		yaw = lerp_angle(yaw, want, 0.16)
		_pose_v(p, yaw, 0.0)
		if per_frame.is_valid():
			per_frame.call(f)
		await process_frame
		_save(seg, i)
		i += 1
		dist += speed / FPS
	return i


func _point_at(pts: Array, d: float) -> Vector3:
	var left := d
	for k in range(pts.size() - 1):
		var a: Vector3 = pts[k]
		var b: Vector3 = pts[k + 1]
		var l := a.distance_to(b)
		if left <= l:
			return a.lerp(b, left / l)
		left -= l
	return pts[pts.size() - 1]


## Camera move between two poses (x, z, yaw, pitch, lift), eased.
func _dolly(seg: String, a: Array, b: Array, frames: int, start_frame := 0, per_frame: Callable = Callable()) -> int:
	var i := start_frame
	for f in frames:
		var t: float = float(f) / maxf(1.0, frames - 1.0)
		t = t * t * (3.0 - 2.0 * t)
		_pose(lerpf(a[0], b[0], t), lerpf(a[1], b[1], t), lerp_angle(a[2], b[2], t), lerpf(a[3], b[3], t), lerpf(a[4], b[4], t))
		if per_frame.is_valid():
			per_frame.call(f)
		await process_frame
		_save(seg, i)
		i += 1
	return i


func _life_to(cycle: float) -> void:
	var life = main.get("tokyo_life")
	if life == null:
		return
	life.advance(fposmod(cycle - life.cycle_time, life.CYCLE))


func _mkdir(seg: String) -> void:
	DirAccess.make_dir_recursive_absolute(out_dir.path_join(seg))


# ---------------------------------------------------------------- scenes

func _run() -> void:
	await _frames(10)
	for seg in segs:
		_mkdir(seg)
		var t0 := Time.get_ticks_msec()
		await call("_" + seg)
		print("TRAILER_SEG ", seg, " fertig in ", (Time.get_ticks_msec() - t0) / 1000.0, " s")
	quit()


## Sprint im Basis-Look (7 s).
func _s02() -> void:
	await _speedrun("klassik-1")
	seed(11)
	var path := _long_run(22, 0)
	await _run_path("s02", path, 210, 5.2)


## Das Kaninchen: langsame Annäherung, Halt eine Zelle davor (4 s).
func _s03() -> void:
	await _speedrun("klassik-1")
	var r: Vector2i = main.maze_view.rabbit_cell
	var n: Vector2i = mg.neighbors_of(main.maze, r.x, r.y)[0]
	var d := n - r
	var a := _cell_pos(r + d * 4)
	var b := _cell_pos(r + d * 1) + Vector3(-d.y, 0, -d.x) * 0.25
	var yaw := _yaw_dir(_cell_pos(r) - a)
	for f in 120:
		var t: float = clampf(float(f) / 95.0, 0.0, 1.0)
		t = 1.0 - pow(1.0 - t, 2.2)
		_pose_v(a.lerp(b, t), yaw, -0.04 * t)
		await process_frame
		_save("s03", f)


## Titelkarte Matrix, HUD sichtbar, kurze Bewegung (3 s).
func _s04() -> void:
	await _speedrun("klassik-1")
	seed(4)
	var path := _long_run(8, 3)
	main.start_condition(Conditions.get_condition("matrix"))
	main.condition_until = main.now + 60.0
	_hud(true)
	await _run_path("s04", path, 90, 1.6)


## Matrix: ASCII, quer durch die Wände (5 s).
func _s05() -> void:
	await _speedrun("klassik-1")
	main.start_condition(Conditions.get_condition("matrix"))
	main.condition_until = main.now + 60.0
	_hud(false)
	await _frames(20)
	# straight line across the maze, through walls
	var rows: int = main.maze.rows
	var cols: int = main.maze.cols
	var z := 3.0 * CELL # a row away from the ghost house
	var a := Vector3(1.0 * CELL, main.player.EYE_H, z)
	var b := Vector3((cols - 2) * CELL, main.player.EYE_H, z)
	for f in 150:
		var t := float(f) / 149.0
		_pose_v(a.lerp(b, t), -PI / 2.0, 0.0)
		await process_frame
		_save("s05", f)


## Fear & Loathing: Kippbild, Kamera schwankt (4 s).
func _s06() -> void:
	await _speedrun("klassik-1")
	seed(21)
	var path := _long_run(12, 1)
	var fl = Conditions.get_condition("fear_and_loathing")
	main.start_condition(fl)
	fl.set_manipulation("swap")
	main.condition_until = main.now + 60.0
	_hud(false)
	await _frames(20)
	var wob := func(f: int) -> void:
		fl._acting = true
		main.player.camera.rotation.z = sin(f * 0.11) * 0.06
	await _run_path("s06", path, 120, 3.0, 0, wob)
	main.player.camera.rotation.z = 0.0


## Stromausfall, dann Taschenuhr (je 1,5 s).
func _s07() -> void:
	await _speedrun("klassik-1")
	seed(31)
	var path := _long_run(8, 2)
	main.start_condition(Conditions.get_condition("stromausfall"))
	main.condition_until = main.now + 60.0
	_hud(false)
	await _frames(15)
	var i: int = await _run_path("s07", path, 45, 4.5)
	main._end_condition(false)
	main.start_condition(Conditions.get_condition("taschenuhr"))
	main.condition_until = main.now + 60.0
	_hud(false)
	await _frames(15)
	seed(32)
	await _run_path("s07", _long_run(8, 5), 45, 4.5, i)


## Sprint für die Chat-Einblendung (5 s), anderes Level.
func _s08() -> void:
	await _speedrun("klassik-2")
	seed(41)
	await _run_path("s08", _long_run(16, 0), 150, 5.2)


## Zielgerade (2 s, danach Standbild im Schnitt).
func _s09() -> void:
	await _speedrun("klassik-1")
	seed(51)
	await _run_path("s09", _long_run(10, 4), 60, 5.6)


## Tokyo, Straße in Augenhöhe, Regen, Verkehr kommt entgegen (8 s).
func _s11() -> void:
	main.go_to_main_menu()
	await _frames(3)
	main.seed_randomness(4242)
	main.reduce_rain = false
	main.begin_explorer_game("tokyo")
	main.invuln_until = 1e9
	_hud(false)
	await _frames(20)
	_life_to(8.0)
	await _dolly("s11", [46.0, 69.0, 0.0, 0.05, 0.0], [46.0, 62.0, 0.03, 0.02, 0.0], 240)


## Tokyo-Totale, Ampel springt auf All Walk (10 s).
func _s12() -> void:
	main.go_to_main_menu()
	await _frames(3)
	main.seed_randomness(4242)
	main.reduce_rain = false
	main.begin_explorer_game("tokyo")
	main.invuln_until = 1e9
	_hud(false)
	await _frames(20)
	_life_to(57.0)
	await _dolly("s12", [50.5, 50.5, PI * 0.25 - 0.12, -0.30, 6.0], [52.6, 52.6, PI * 0.25 + 0.10, -0.40, 7.5], 300)


## Gasse (3 s), U-Bahn (2 s), Manhattan-Flash (1 s).
func _s13() -> void:
	main.go_to_main_menu()
	await _frames(3)
	main.seed_randomness(4242)
	main.reduce_rain = false
	main.begin_explorer_game("tokyo")
	main.invuln_until = 1e9
	_hud(false)
	await _frames(20)
	var i: int = await _dolly("s13", [18.0, 36.0, 0.0, 0.06, 0.0], [18.0, 32.5, 0.05, 0.08, 0.0], 90)
	i = await _dolly("s13", [48.0, 18.0, 0.18, 0.10, 0.0], [48.0, 16.5, 0.10, 0.10, 0.0], 60, i)
	main.go_to_main_menu()
	await _frames(3)
	main.seed_randomness(4242)
	main.begin_manhattan_game()
	main.invuln_until = 1e9
	await _frames(90)
	_hud(false)
	await _frames(5)
	# Manhattan from the start position (the letter towers read best there)
	for f in 30:
		await process_frame
		_save("s13", i + f)


## Neuer Lauf, Timer bei 0 (3,5 s).
func _s14() -> void:
	await _speedrun("klassik-2")
	seed(61)
	await _run_path("s14", _walk_path(main.start_cell, 14), 105, 5.4)
