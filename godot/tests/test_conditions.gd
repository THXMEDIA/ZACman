extends SceneTree
## Headless test: res://scripts/conditions.gd and its condition scripts — the
## rabbit conditions (spec docs/design/kaninchen-speedrun.md 2.3/2.4).
## Pure-logic checks, no Main/scene (the scene side is in bot_test.gd). Run with
##   godot --headless --path . --script res://tests/test_conditions.gd
## Exits with code 0 on success, 1 on any failure.

var failures := 0
var checks := 0


func _check(name: String, cond: bool, detail := "") -> void:
	checks += 1
	if not cond:
		failures += 1
		print("FAIL ", name, (" -> " + detail) if detail != "" else "")


func _initialize() -> void:
	var Conditions = load("res://scripts/conditions.gd")
	var Fear = load("res://scripts/conditions/fear_and_loathing.gd")

	# --- registry: pool, flags, durations, weights ---
	_check("registry: the four conditions of the pool", Conditions.ids() == ["matrix", "taschenuhr", "fear_and_loathing", "stromausfall"], str(Conditions.ids()))
	_check("registry: good = matrix, taschenuhr", Conditions.ids_of_kind(true) == ["matrix", "taschenuhr"])
	_check("registry: bad = fear_and_loathing, stromausfall", Conditions.ids_of_kind(false) == ["fear_and_loathing", "stromausfall"])
	for id in Conditions.ids():
		var c = Conditions.get_condition(id)
		var e: Dictionary = Conditions.entry(id)
		_check("registry %s: instance with id, name, look and icon" % id, c != null and c.id == id and c.display_name != "" and c.look_id != "" and c.icon != "")
		_check("registry %s: is_good/duration/weight from the registry" % id, c.is_good == e.is_good and c.duration_s == e.duration_s and c.weight == e.weight and e.weight > 0.0)
		_check("registry %s: good 10 s, bad 8 s" % id, c.duration_s == (10.0 if c.is_good else 8.0))
	_check("registry: '' and unknown ids mean no condition", Conditions.get_condition("") == null and Conditions.get_condition("matrix_ghost") == null)
	_check("registry: matrix_ghost.gd is gone (renamed to matrix.gd)", not FileAccess.file_exists("res://scripts/conditions/matrix_ghost.gd") and FileAccess.file_exists("res://scripts/conditions/matrix.gd"))
	_check("registry: no start-screen selection API any more", not ("SELECTABLE_IDS" in Conditions) and not Conditions.has_method("other_condition_id"))

	# --- derived state ---
	_check("matrix wants noclip, nobody else", Conditions.get_condition("matrix").wants_noclip() and not Conditions.get_condition("taschenuhr").wants_noclip() and not Conditions.get_condition("fear_and_loathing").wants_noclip() and not Conditions.get_condition("stromausfall").wants_noclip())
	_check("taschenuhr halves the ghost speed", Conditions.get_condition("taschenuhr").ghost_speed_scale() == 0.5 and Conditions.get_condition("matrix").ghost_speed_scale() == 1.0)
	_check("stromausfall switches the minimap off, nobody else", not Conditions.get_condition("stromausfall").minimap_visible() and Conditions.get_condition("matrix").minimap_visible())

	# --- pick_condition: 60:40 good:bad, equal within; only the given RNG ---
	var rng := RandomNumberGenerator.new()
	rng.seed = 424242
	var counts := {}
	var n := 20000
	for i in n:
		var id: String = Conditions.pick_condition(rng, Conditions.P_GOOD_BASE)
		counts[id] = counts.get(id, 0) + 1
	var good: int = counts.get("matrix", 0) + counts.get("taschenuhr", 0)
	var share := float(good) / n
	# 4 standard deviations of a binomial(20000, 0.6): +-0.0139
	_check("pick: good share 60 % over many draws", absf(share - 0.6) < 0.014, "share=%f" % share)
	_check("pick: within good equally likely", absf(float(counts.get("matrix", 0)) / good - 0.5) < 0.02, str(counts))
	var bad := n - good
	_check("pick: within bad equally likely", absf(float(counts.get("fear_and_loathing", 0)) / bad - 0.5) < 0.025, str(counts))
	var r1 := RandomNumberGenerator.new()
	var r2 := RandomNumberGenerator.new()
	r1.seed = 99
	r2.seed = 99
	var same := true
	for i in 200:
		seed(i) # the global generator must not matter
		randf()
		if Conditions.pick_condition(r1) != Conditions.pick_condition(r2):
			same = false
	_check("pick: same seed -> same sequence, independent of the global randf()", same)
	_check("pick: p_good 1 -> always good, 0 -> always bad", Conditions.entry(Conditions.pick_condition(r1, 1.0)).is_good and not Conditions.entry(Conditions.pick_condition(r1, 0.0)).is_good)

	# --- Fear & Loathing manipulations (more in bot_test.gd) ---
	for kind in Fear.MANIPULATIONS:
		var f = Fear.new()
		f.set_manipulation(kind)
		var ok := true
		var too_fast := false
		for i in 120:
			var v: Vector2 = f.modify_input(Vector2.ZERO, 1.0 / 60.0)
			if v != Vector2.ZERO:
				ok = false
			var w: Vector2 = f.modify_input(Vector2(0.7071, 0.7071), 1.0 / 60.0)
			if w.length() > 1.0001:
				too_fast = true
		_check("F&L %s: never movement without input" % kind, ok)
		_check("F&L %s: never faster than full input" % kind, not too_fast)
		_check("F&L %s: symbol and subtitle for the title card" % kind, f.icon == "fl_" + kind and f.subtitle() != "")
	var f2 = Fear.new()
	_check("F&L: the old sine noise / unannounced inversion is gone", not ("NOISE_AMOUNT" in f2) and not ("_inverted" in f2))

	# --- base class is a no-op ---
	var base_condition = load("res://scripts/conditions/condition_base.gd").new()
	_check("condition_base: modify_input passes input through", base_condition.modify_input(Vector2(0.3, 0.7), 0.1) == Vector2(0.3, 0.7))
	_check("condition_base: neutral derived state", not base_condition.wants_noclip() and base_condition.ghost_speed_scale() == 1.0 and base_condition.minimap_visible() and base_condition.look_flip() == 0.0)

	print("")
	if failures == 0:
		print("ALL %d CONDITIONS CHECKS PASSED" % checks)
		quit(0)
	else:
		print("%d/%d CONDITIONS CHECKS FAILED" % [failures, checks])
		quit(1)
