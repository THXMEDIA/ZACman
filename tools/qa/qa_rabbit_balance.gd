# Messung der Kaninchen-Wette (GD-Review 03.10.): Was kostet bzw. bringt das
# weiße Kaninchen gegenüber einem Lauf ohne Kaninchen? Reine Messung, ändert
# keine Spielwerte.
#
# Ein Bot fährt jedes Speedrun-Level des Pools einmal ohne Kaninchen und
# einmal je erzwungener Kondition (Matrix, Taschenuhr, Stromausfall und
# Fear & Loathing mit jeder Manipulation: A/D getauscht, Drift, Verzögerung)
# und gibt Δt gegenüber „ohne Kaninchen“ aus — für zwei Strategien:
#   gierig   das Kaninchen ist ein Ziel wie jede Kugel: der Bot nimmt immer
#            das nächste Ziel (BFS) und holt das Kaninchen, wenn es dran ist
#   zuerst   der Bot holt zuerst das Kaninchen, dann gierig die Kugeln
#
# Aufruf aus dem Repo-Wurzelverzeichnis (wie die anderen QA-Skripte):
#   cp tools/qa/qa_rabbit_balance.gd godot/qa_rabbit_balance.gd
#   OUT=/pfad/zu/ergebnis.md godot --headless --fixed-fps 60 --path godot \
#     --script res://qa_rabbit_balance.gd
#   rm godot/qa_rabbit_balance.gd
# Optional: LEVELS=klassik-1,offen (Teilmenge), STRATS=gierig (eine Strategie).
#
# Annahmen und Grenzen (bitte bei der Auswertung mitlesen):
# - Der Bot ist unverwundbar (Main.invuln_until). Gemessen werden Umweg und
#   Bewegungswirkung der Kondition. Taschenuhr und Stromausfall wirken im
#   Spiel nur über Geister und Sicht; hier zeigen sie deshalb nur den Umweg.
#   Als Gefahren-Näherung zählt der Bot „Kontakte“: wie oft ein nicht
#   verängstigter Geist in Trefferweite kam (im echten Spiel ein Leben).
# - Steuerung wie ein Spieler mit Maus + WASD: Blickdrehung höchstens
#   TURN_RAD_S, Bewegung als (seitwärts, vorwärts) relativ zum Blick, also
#   mit A/D-Anteilen in Kurven. A/D getauscht wirkt nur über diese Anteile.
# - Matrix: solange die Wände offen sind (Noclip, > 1 s Rest), nimmt der Bot
#   dasselbe nächste Ziel wie ohne Matrix (Abstand mit Wänden), läuft aber
#   auf dem kürzesten Weg durch die Wände dorthin (Abkürzung). Am Ende setzt
#   das Spiel ihn sicher in die nächste offene Zelle.
# - Feste Seeds (Main.seed_randomness) und feste Woche: jeder Lauf ist
#   reproduzierbar; „ohne“ und die Varianten unterscheiden sich nur durch das
#   Kaninchen. --fixed-fps 60 entkoppelt die Simulation von der Uhrzeit.
# - Läuft in einem eigenen Speicherordner (user://qa_balance_saves, wird am
#   Ende gelöscht); echte Spielstände bleiben unberührt.
extends SceneTree

const SavePaths := preload("res://scripts/save_paths.gd")
const LevelsScript := preload("res://scripts/levels.gd")
const QA_ROOT := "user://qa_balance_saves"
const SEED := 20261003
const TURN_RAD_S := 9.0
const WAYPOINT_R := 0.22
const TIMEOUT_S := 900.0
const VARIANTS := [
	{"id": "ohne", "cond": "", "manip": ""},
	# the rabbit is fetched but gives nothing (Main: unknown id = no condition):
	# separates the detour from the condition's own effect
	{"id": "neutral", "cond": "keine", "manip": ""},
	{"id": "matrix", "cond": "matrix", "manip": ""},
	{"id": "taschenuhr", "cond": "taschenuhr", "manip": ""},
	{"id": "stromausfall", "cond": "stromausfall", "manip": ""},
	{"id": "fl_swap", "cond": "fear_and_loathing", "manip": "swap"},
	{"id": "fl_drift", "cond": "fear_and_loathing", "manip": "drift"},
	{"id": "fl_delay", "cond": "fear_and_loathing", "manip": "delay"},
]
const LABELS := {"ohne": "ohne Kaninchen", "neutral": "Kaninchen ohne Wirkung (nur Umweg)", "matrix": "Matrix", "taschenuhr": "Taschenuhr", "stromausfall": "Stromausfall", "fl_swap": "F&L A/D getauscht", "fl_drift": "F&L Drift", "fl_delay": "F&L Verzögerung"}

var main: Node
var results := {} # "level|variant|strategy" -> {"t": float, "contacts": int, "ok": bool}


func _initialize() -> void:
	SavePaths.use_root(QA_ROOT)
	_run()


func _run() -> void:
	for i in 3:
		await process_frame
	root.get_node("Speedrun").reload()
	root.get_node("Leaderboard").reload()
	main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	for i in 5:
		await process_frame
	main.skip_start_intro = true
	main.rabbit_week_override = Vector2i(2026, 40)
	var levels: Array = LevelsScript.ids()
	var only := OS.get_environment("LEVELS")
	if only != "":
		levels = Array(only.split(","))
	var strats := ["gierig", "zuerst"]
	var only_s := OS.get_environment("STRATS")
	if only_s != "":
		strats = Array(only_s.split(","))
	var t0 := Time.get_ticks_msec()
	for lid in levels:
		for v in VARIANTS:
			for strat in strats:
				if v.id == "ohne" and strat != strats[0]:
					continue
				var r: Dictionary = await _one_run(lid, v, strat)
				results["%s|%s|%s" % [lid, v.id, strat]] = r
				print("RUN %-11s %-13s %-7s t=%7.2f s  Kontakte=%2d  Kaninchen bei %6.1f s (%s)  hängen=%d  %s  (%.0f s real)" % [lid, v.id, strat, r.t, r.contacts, r.rabbit_t, r.cond, r.stuck, "ok" if r.ok else "ABBRUCH", (Time.get_ticks_msec() - t0) / 1000.0])
	var report := _report(levels, strats)
	print(report)
	var out := OS.get_environment("OUT")
	if out != "":
		var f := FileAccess.open(out, FileAccess.WRITE)
		f.store_string(report)
		f.close()
	_cleanup()
	quit(0)


func _cleanup() -> void:
	var dir := DirAccess.open(QA_ROOT)
	if dir != null:
		for f in dir.get_files():
			dir.remove(f)
	DirAccess.remove_absolute(QA_ROOT)
	SavePaths.reset_root()


## One bot run of `lid` with variant `v`. Returns {t, contacts, ok}.
func _one_run(lid: String, v: Dictionary, strat: String) -> Dictionary:
	main.seed_randomness(SEED)
	main.forced_rabbit_condition = v.cond
	main.forced_fl_manipulation = v.manip
	main.begin_game(lid)
	await process_frame
	var take_rabbit: bool = v.cond != ""
	var path: Array = []
	var target := Vector2i(-1, -1)
	var contacts := 0
	var in_contact := {}
	var last_progress_pos: Vector3 = main.player.global_position
	var last_progress_t := 0.0
	var t := 0.0
	var finished := false
	var level_ref: String = main.level_id
	var rabbit_t := -1.0
	var cond_seen := ""
	var stuck := 0
	while t < TIMEOUT_S:
		main.invuln_until = 1e9
		var player = main.player
		var mv = main.maze_view
		# done?
		if mv.remaining_pickups() <= 0:
			finished = true
			break
		# rabbit taken (or not wanted)?
		var rabbit_open: bool = take_rabbit and mv.rabbit_alive
		# re-plan when the target is gone or the path is used up
		var noclip: bool = player.collision_mask == 0 and main.condition_remaining() > 1.0
		if path.is_empty() or not _target_alive(target) or (noclip != _planned_noclip):
			var plan := _plan(player.cell(), rabbit_open, strat, noclip)
			path = plan.path
			target = plan.target
			_planned_noclip = noclip
		_steer(path, 1.0 / 60.0)
		await process_frame
		t += 1.0 / 60.0
		if rabbit_t < 0.0 and main.active_condition != null:
			rabbit_t = main.real_now - main.level_start_real
			cond_seen = main.active_condition.id
			if "manipulation" in main.active_condition:
				cond_seen += "/" + main.active_condition.manipulation
		# ghost contacts (danger proxy)
		for i in main.enemies.size():
			var e = main.enemies[i]
			var d := Vector2(e.position.x - player.global_position.x, e.position.z - player.global_position.z).length()
			var danger: bool = d < main.ENEMY_HIT_RADIUS and e.mode == "chase" and main.now >= main.frightened_until
			if danger and not in_contact.get(i, false):
				contacts += 1
			in_contact[i] = danger
		# stuck guard
		if player.global_position.distance_to(last_progress_pos) > 0.5:
			last_progress_pos = player.global_position
			last_progress_t = t
		elif t - last_progress_t > 2.0:
			stuck += 1
			path = []
			last_progress_t = t
	var elapsed: float = main.real_now - main.level_start_real
	main.player.move_input = Vector2.ZERO
	main.forced_rabbit_condition = ""
	main.forced_fl_manipulation = ""
	main.go_to_main_menu()
	await process_frame
	return {"t": elapsed if finished else t, "contacts": contacts, "ok": finished and level_ref == lid, "rabbit_t": rabbit_t, "cond": cond_seen, "stuck": stuck}


var _planned_noclip := false


func _target_alive(target: Vector2i) -> bool:
	if target.x < 0:
		return false
	var mv = main.maze_view
	if mv.rabbit_alive and target == mv.rabbit_cell:
		return true
	var i: int = mv.pellet_cells.find(target)
	if i >= 0 and mv.pellet_alive[i]:
		return true
	var j: int = mv.power_cells.find(target)
	return j >= 0 and mv.power_alive[j]


## The next target is always the nearest wanted one by the real (walled)
## distance — the same order as without Matrix. While noclipping, the path to
## it then goes straight through the walls (a shortcut), instead of letting
## "nearest through walls" scatter the route over neighbouring corridors.
## Returns {"path": [cells after from], "target"}.
func _plan(from: Vector2i, rabbit_open: bool, strat: String, noclip: bool) -> Dictionary:
	var walled := _bfs_plan(from, rabbit_open, strat, false, Vector2i(-1, -1))
	if not noclip or walled.target.x < 0:
		return walled
	return _bfs_plan(from, rabbit_open, strat, true, walled.target)


## BFS from `from` (walls respected, or ignored while noclipping) to the
## nearest wanted target, or to `only` if given.
func _bfs_plan(from: Vector2i, rabbit_open: bool, strat: String, noclip: bool, only: Vector2i) -> Dictionary:
	var maze = main.maze
	var mv = main.maze_view
	var targets := {}
	if only.x >= 0:
		targets[only] = true
	elif rabbit_open:
		targets[mv.rabbit_cell] = true
	if only.x < 0 and not (rabbit_open and strat == "zuerst"):
		for i in mv.pellet_cells.size():
			if mv.pellet_alive[i]:
				targets[mv.pellet_cells[i]] = true
		for i in mv.power_cells.size():
			if mv.power_alive[i]:
				targets[mv.power_cells[i]] = true
	var start := Vector2i(clampi(from.x, 0, maze.rows - 1), posmod(from.y, maze.cols))
	var parent := {start: start}
	var queue := [start]
	var qi := 0
	var found := Vector2i(-1, -1)
	while qi < queue.size():
		var cur: Vector2i = queue[qi]
		qi += 1
		if targets.has(cur) and cur != start:
			found = cur
			break
		for d in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
			var n := Vector2i(cur.x + d.x, posmod(cur.y + d.y, maze.cols))
			if n.x < 0 or n.x >= maze.rows or parent.has(n):
				continue
			if not noclip and maze.grid[n.x][n.y] != 0:
				continue
			parent[n] = cur
			queue.append(n)
	if found.x < 0:
		if targets.has(start):
			return {"path": [start], "target": start}
		return {"path": [], "target": Vector2i(-1, -1)}
	var path := []
	var c := found
	while c != start:
		path.push_front(c)
		c = parent[c]
	return {"path": path, "target": found}


## Mouse + WASD like a player: turn toward the next waypoint at most
## TURN_RAD_S, move along the wanted direction expressed in the view frame
## (forward and A/D share), through PlayerController.move_input.
func _steer(path: Array, dt: float) -> void:
	var player = main.player
	if path.is_empty():
		player.move_input = Vector2.ZERO
		return
	var w: Vector2i = path[0]
	var width: float = main.maze.cols * main.CELL
	var dx: float = w.y * main.CELL - player.global_position.x
	if dx > width * 0.5:
		dx -= width
	elif dx < -width * 0.5:
		dx += width
	var dz: float = w.x * main.CELL - player.global_position.z
	var dist := Vector2(dx, dz).length()
	if dist < WAYPOINT_R:
		path.pop_front()
		if path.is_empty():
			player.move_input = Vector2.ZERO
			return
		_steer(path, 0.0)
		return
	var want_yaw := atan2(-dx, -dz)
	var diff := wrapf(want_yaw - player.yaw, -PI, PI)
	player.yaw += clampf(diff, -TURN_RAD_S * dt, TURN_RAD_S * dt)
	player.rotation.y = player.yaw
	var dir := Vector2(dx, dz) / dist
	var fwd := Vector2(-sin(player.yaw), -cos(player.yaw))
	var right := Vector2(cos(player.yaw), -sin(player.yaw))
	player.move_input = Vector2(dir.dot(right), dir.dot(fwd))


func _report(levels: Array, strats: Array) -> String:
	var lines := []
	lines.append("## Kaninchen-Wette: Messung per Bot (unverwundbar, feste Seeds)")
	lines.append("")
	lines.append("Zeiten in Sekunden, in Klammern die Geisterkontakte (Gefahren-Näherung). Δt > 0 = langsamer.")
	lines.append("Tabelle A: Δt gegenüber dem Lauf ohne Kaninchen (gierige Route) — das, was die Wette insgesamt kostet oder bringt.")
	lines.append("Tabelle B: Δt gegenüber „Kaninchen ohne Wirkung“ mit derselben Strategie — die Wirkung der Kondition allein, ohne Umweg und ohne Routen-Effekt.")
	lines.append("")
	for strat in strats:
		for table in ["A", "B"]:
			lines.append("### Strategie „%s“, Tabelle %s" % [strat, table])
			lines.append("")
			var head := "| Kondition |"
			var sep := "|---|"
			for lid in levels:
				head += " %s |" % LevelsScript.by_id(lid).get("name", lid)
				sep += "---:|"
			head += " Mittel |"
			sep += "---:|"
			lines.append(head)
			lines.append(sep)
			if table == "A":
				var base_row := "| ohne Kaninchen: t |"
				var base_sum := 0.0
				for lid in levels:
					var b0: Dictionary = results.get("%s|ohne|%s" % [lid, strats[0]], {})
					base_row += " %.1f (%d) |" % [b0.get("t", -1.0), b0.get("contacts", 0)]
					base_sum += float(b0.get("t", 0.0))
				base_row += " %.1f |" % (base_sum / levels.size())
				lines.append(base_row)
			for v in VARIANTS:
				if v.id == "ohne" or (table == "B" and v.id == "neutral"):
					continue
				var row := "| %s |" % LABELS[v.id]
				var sum := 0.0
				var n := 0
				for lid in levels:
					var base_key := "%s|ohne|%s" % [lid, strats[0]] if table == "A" else "%s|neutral|%s" % [lid, strat]
					var b: Dictionary = results.get(base_key, {})
					var r: Dictionary = results.get("%s|%s|%s" % [lid, v.id, strat], {})
					if r.is_empty() or b.is_empty():
						row += " – |"
						continue
					var dt: float = r.t - b.t
					row += " %+.1f (%d)%s |" % [dt, r.contacts, "" if r.ok else " !"]
					sum += dt
					n += 1
				row += " %+.1f |" % (sum / maxi(n, 1))
				lines.append(row)
			lines.append("")
	return "\n".join(lines)
