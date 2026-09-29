extends RefCounted
## Conditions — the registry of selectable whole-run modifiers
## ("Konditionen"): Matrix Ghost (no wall collision, permanent word-built
## look), Fear & Loathing (noisy/periodically-inverted controls), and more
## to come over time — that's the point (see this project's "Explorer-
## Level-Erweiterung, Leaderboard & Konditionen" doc). Adding a new
## condition is one new script under scripts/conditions/ plus one line
## here; Main and PlayerController never need to change.

const MatrixGhostScript := preload("res://scripts/conditions/matrix_ghost.gd")
const FearAndLoathingScript := preload("res://scripts/conditions/fear_and_loathing.gd")

## Ordered so a future "pick a condition" UI can just iterate this.
const IDS := ["matrix_ghost", "fear_and_loathing"]


## Returns a fresh instance of the condition for `id`, or null for "" /
## an unknown id (meaning: no condition, the run plays unmodified).
static func get_condition(id: String):
	match id:
		"matrix_ghost":
			return MatrixGhostScript.new()
		"fear_and_loathing":
			return FearAndLoathingScript.new()
		_:
			return null


static func display_name_for(id: String) -> String:
	var c = get_condition(id)
	return c.display_name if c != null else "Normal"


## "" (no condition) plus every registered condition — the full set a
## post-run "pick a condition" choice can offer.
const SELECTABLE_IDS := ["", "matrix_ghost", "fear_and_loathing"]


## A different selectable condition id than `current_id` (see
## SELECTABLE_IDS) — always exists since there are 3 selectable values
## total (picked at random among the other two, so "andere Kondition"
## doesn't always offer the same alternative).
static func other_condition_id(current_id: String) -> String:
	var candidates := []
	for id in SELECTABLE_IDS:
		if id != current_id:
			candidates.append(id)
	return candidates[randi() % candidates.size()]
