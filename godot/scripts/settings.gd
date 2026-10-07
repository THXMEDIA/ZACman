extends RefCounted
## Settings — the few player options that persist. The comfort block
## ("Effekte reduzieren", field of view, mouse sensitivity; UX-K1) sits right
## under the title on the start screen and in the pause menu, the Chaos switch
## on the start screen (hud.gd); stored here, under SavePaths (tests redirect
## it), as a small versioned JSON file.
##
## "Effekte reduzieren" (spec 1.2) softens every condition look (Matrix rain
## slower and the walls a bit denser but still permeable, no blinking, the
## Kippbild does not tip the world — only a thin frame shows it, slower flow,
## calmer transition) — the gameplay effect of the condition stays the same.
## "Regen reduzieren" (Tokyo, docs/design/tokyo-explorer.md M2): fewer and
## dimmer rain drops; "Effekte reduzieren" dampens the rain as well.
## "Chaos-Modus" (spec 2.5): real randomness for the rabbit, own board.

const SavePathsScript := preload("res://scripts/save_paths.gd")
const SAVE_FILE := "zapmaniac_settings.json"
## 1: {"version", "reduce_fx"}; 2: plus "chaos"; 3: plus "fov" and
## "mouse_sens" (UX-K1 comfort block); 4: plus "reduce_rain" ("Regen
## reduzieren", Tokyo M2); 5: plus "map_mode" (ZAP-6: 0 Voll, 1 Lokal, 2 Aus).
## A missing field keeps its default, so older files load unchanged.
const SAVE_VERSION := 5
## Field of view (degrees) and mouse sensitivity (factor) — ranges of the
## sliders in the comfort block.
const FOV_MIN := 60.0
const FOV_MAX := 100.0
const FOV_DEFAULT := 72.0
const SENS_MIN := 0.3
const SENS_MAX := 3.0
## Map mode of the minimap: Voll = whole maze (default), Lokal = only a window
## of +-LOCAL_RADIUS cells around the player, Aus = no map (a compass strip
## replaces it in the last two).
const MAP_FULL := 0
const MAP_LOCAL := 1
const MAP_OFF := 2
const DEFAULTS := {"reduce_fx": false, "reduce_rain": false, "chaos": false, "fov": FOV_DEFAULT, "mouse_sens": 1.0, "map_mode": MAP_FULL}
const BOOL_FIELDS := ["reduce_fx", "reduce_rain", "chaos"]
const RANGES := {"fov": [FOV_MIN, FOV_MAX], "mouse_sens": [SENS_MIN, SENS_MAX], "map_mode": [0.0, 2.0]}
const INT_FIELDS := ["map_mode"]


static func save_path() -> String:
	return SavePathsScript.path(SAVE_FILE)


## {"reduce_fx": bool, "reduce_rain": bool, "chaos": bool, "fov": float, "mouse_sens": float};
## defaults for a missing file and for every broken or wrong-typed field. A
## file that could not be parsed or had a wrong-typed field is first kept as
## "<name>.corrupt-<unix time>" (W4), because the next save overwrites it.
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
		SavePathsScript.backup_corrupt(p)
		return out
	var broken := false
	for k in DEFAULTS:
		if not parsed.has(k):
			continue
		var v = parsed[k]
		if k in BOOL_FIELDS:
			if typeof(v) == TYPE_BOOL:
				out[k] = v
			else:
				broken = true
		else:
			if (typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT) and not is_nan(float(v)) and not is_inf(float(v)):
				out[k] = clampf(float(v), RANGES[k][0], RANGES[k][1])
				if k in INT_FIELDS:
					out[k] = int(roundf(out[k]))
			else:
				broken = true
	if broken:
		SavePathsScript.backup_corrupt(p)
	return out


## Writes every setting; fields missing in `values` get their default.
static func save_settings(values: Dictionary) -> void:
	var payload := {"version": SAVE_VERSION}
	for k in DEFAULTS:
		if k in BOOL_FIELDS:
			payload[k] = bool(values.get(k, DEFAULTS[k]))
		else:
			payload[k] = clampf(float(values.get(k, DEFAULTS[k])), RANGES[k][0], RANGES[k][1])
			if k in INT_FIELDS:
				payload[k] = int(roundf(payload[k]))
	SavePathsScript.write_atomic(save_path(), JSON.stringify(payload))
