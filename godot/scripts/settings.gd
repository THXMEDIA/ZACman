extends RefCounted
## Settings — the few player options that persist (today only "Effekte
## reduzieren", spec 1.2). There is no settings menu yet, so the switch sits
## on the start screen and in the pause menu (hud.gd); it is stored here, under
## SavePaths (tests redirect it), as a small versioned JSON file.
##
## "Effekte reduzieren" softens every condition look (denser Matrix walls, no
## blinking, slower flow, calmer transition) — the gameplay effect of the
## condition stays exactly the same.

const SavePathsScript := preload("res://scripts/save_paths.gd")
const SAVE_FILE := "kugelschlucker_settings.json"
const SAVE_VERSION := 1


static func save_path() -> String:
	return SavePathsScript.path(SAVE_FILE)


## {"reduce_fx": bool}; defaults for a missing or broken file.
static func load_settings() -> Dictionary:
	var out := {"reduce_fx": false}
	var p := save_path()
	if not FileAccess.file_exists(p):
		return out
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		return out
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) == TYPE_DICTIONARY and parsed.has("reduce_fx") and typeof(parsed.reduce_fx) == TYPE_BOOL:
		out.reduce_fx = parsed.reduce_fx
	return out


static func save_settings(values: Dictionary) -> void:
	var payload := {"version": SAVE_VERSION, "reduce_fx": bool(values.get("reduce_fx", false))}
	SavePathsScript.write_atomic(save_path(), JSON.stringify(payload))
