extends RefCounted
## Settings — the few player options that persist. There is no settings menu
## yet, so the switches sit on the start screen (and "Effekte reduzieren" also
## in the pause menu, hud.gd); stored here, under SavePaths (tests redirect
## it), as a small versioned JSON file.
##
## "Effekte reduzieren" (spec 1.2) softens every condition look (denser Matrix
## walls, no blinking, slower flow, calmer transition) — the gameplay effect
## of the condition stays exactly the same.
## "Chaos-Modus" (spec 2.5): real randomness for the rabbit, own board.

const SavePathsScript := preload("res://scripts/save_paths.gd")
const SAVE_FILE := "zapmaniac_settings.json"
## 1: {"version", "reduce_fx"}; 2: plus "chaos". A missing field keeps its
## default, so a version-1 file loads unchanged.
const SAVE_VERSION := 2
const DEFAULTS := {"reduce_fx": false, "chaos": false}


static func save_path() -> String:
	return SavePathsScript.path(SAVE_FILE)


## {"reduce_fx": bool, "chaos": bool}; defaults for a missing or broken file
## or a field of the wrong type.
static func load_settings() -> Dictionary:
	var out := DEFAULTS.duplicate()
	var p := save_path()
	if not FileAccess.file_exists(p):
		return out
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		return out
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return out
	for k in DEFAULTS:
		if parsed.has(k) and typeof(parsed[k]) == TYPE_BOOL:
			out[k] = parsed[k]
	return out


## Writes every setting; fields missing in `values` get their default.
static func save_settings(values: Dictionary) -> void:
	var payload := {"version": SAVE_VERSION}
	for k in DEFAULTS:
		payload[k] = bool(values.get(k, DEFAULTS[k]))
	SavePathsScript.write_atomic(save_path(), JSON.stringify(payload))
