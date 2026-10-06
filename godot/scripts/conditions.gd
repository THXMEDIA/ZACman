extends RefCounted
## Conditions — the registry of "Konditionen": time-limited effects that only
## the white rabbit triggers (spec docs/design/kaninchen-speedrun.md 2.3).
##
## Each entry: id, script, is_good, duration_s (good 10 s, Matrix 15 s, bad
## 8 s – E10, 04.10.2026: the bet barely paid off in the bot measurement),
## weight.
## Base ratio good:bad = 60:40 (P_GOOD_BASE); within good resp. bad the
## weights decide (all 1 today = equally likely). A new condition = one
## script under scripts/conditions/ plus one entry here.
##
## pick_condition(rng, p_good) is the one place that turns randomness into a
## condition. Main feeds it the "Kaninchen der Woche" generator and
## P_GOOD_BASE today; Etappe 3 plugs in a Chaos generator (real randomness)
## and the chat-weighted p_good (spec 2.6) through the same call.

const P_GOOD_BASE := 0.6
const GOOD_DURATION_S := 10.0
## E10 (b): the Matrix shortcut needs time to pay back the detour.
const MATRIX_DURATION_S := 15.0
const BAD_DURATION_S := 8.0

const REGISTRY := [
	{"id": "matrix", "script": "res://scripts/conditions/matrix.gd", "is_good": true, "duration_s": MATRIX_DURATION_S, "weight": 1.0},
	{"id": "taschenuhr", "script": "res://scripts/conditions/taschenuhr.gd", "is_good": true, "duration_s": GOOD_DURATION_S, "weight": 1.0},
	{"id": "fear_and_loathing", "script": "res://scripts/conditions/fear_and_loathing.gd", "is_good": false, "duration_s": BAD_DURATION_S, "weight": 1.0},
	{"id": "stromausfall", "script": "res://scripts/conditions/stromausfall.gd", "is_good": false, "duration_s": BAD_DURATION_S, "weight": 1.0},
]


static func ids() -> Array:
	var out := []
	for e in REGISTRY:
		out.append(e.id)
	return out


static func entry(id: String) -> Dictionary:
	for e in REGISTRY:
		if e.id == id:
			return e
	return {}


## Ids of the good (true) or bad (false) conditions, in registry order.
static func ids_of_kind(good: bool) -> Array:
	var out := []
	for e in REGISTRY:
		if e.is_good == good:
			out.append(e.id)
	return out


## A fresh instance for `id` with is_good/duration_s/weight from the
## registry, or null for "" / an unknown id.
static func get_condition(id: String):
	var e := entry(id)
	if e.is_empty():
		return null
	var c = load(e.script).new()
	c.is_good = e.is_good
	c.duration_s = e.duration_s
	c.weight = e.weight
	return c


static func display_name_for(id: String) -> String:
	var c = get_condition(id)
	return c.display_name if c != null else ""


## Draws one condition id: first good vs. bad with probability `p_good`
## (clamped to 0..1), then within that group by weight. Uses only `rng` —
## never the global randf()/randi() — so a seeded generator always gives the
## same result (Kaninchen der Woche, spec 2.5).
static func pick_condition(rng: RandomNumberGenerator, p_good: float = P_GOOD_BASE) -> String:
	var good := rng.randf() < clampf(p_good, 0.0, 1.0)
	var group := []
	var total := 0.0
	for e in REGISTRY:
		if e.is_good == good and e.weight > 0.0:
			group.append(e)
			total += e.weight
	if group.is_empty():
		return ""
	var roll := rng.randf() * total
	for e in group:
		roll -= e.weight
		if roll < 0.0:
			return e.id
	return group[group.size() - 1].id
