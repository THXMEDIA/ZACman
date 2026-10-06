extends RefCounted
## ArlesStyle — palette, brush materials and light constants of the Arles
## Explorer city, look "Sternennacht, echte Orte stilisiert", main look "tiefe
## Nacht" (direction B v2, owner decisions E19/E23; spec
## docs/design/arles-explorer.md, art studio/projekte/zapmaniac/art/
## explorer-stile-v1.md section B v2). Colours as in the art director's
## prototype (tools/art/explorer_proto/arles_v2 on the art branch).
##
## Exclusive colours (tests): vermilion only the pellets, mint green only the
## exit (green door, shutters, green star, its light). Halo rims and the
## mirrored lamps in the Rhône are gold, not orange (distance to the pellets
## for red-green colour vision).

# ---- exclusive ----
const PELLET := Color("ff4a1c") # vermilion: the pellets, nothing else
const PELLET_CORE := Color("ffb088")
const PELLET_RIM := Color("3a0e06") # dark contour (readable before yellow light)
const EXIT := Color("3af5c8") # mint green: door, shutters, star (colour vision: not #39FF6A)
const EXIT_DARK := Color("08291f")
const EXIT_CORE := Color("e0fff6")
const EXIT_RIM := Color("0e7a66")

# ---- night ----
const BG := Color("141d4a")
const AMBIENT := Color("2a3b7a")
const FOG := Color("1e2c66")
const MOON := Color("8fa8e0")
const SKY_BASE := Color("1b2a6b") # ultramarine
const SKY_MID := Color("2f55a8") # cobalt stroke
const SKY_LIGHT := Color("7fb2e5") # light stroke
const SKY_YELLOW := Color("f6c945") # chrome yellow zones
const LAMP_LIGHT := Color("ffc24a") # warm omni lights
const LAMP_POOL := Color(1.0, 0.76, 0.40) # painted light pools (linear factor)
const HALO_CORE := Color("fff3b0")
const HALO_YELLOW := Color("f9cc45")
const HALO_RIM := Color("d4a03a") # gold, not orange
const WINDOW := Color("f6c945")
const WINDOW_B := Color("f3b33a")
const WINDOW_C := Color("fff1b0")
const SHUTTER_A := Color("5e7fb0")
const SHUTTER_B := Color("3e5a8a")
const GLASS := Color("151a3c")
const DOOR := Color("3a2a20")
const ROOF_DARK := Color("2a2a55")
const PAVE := [Color("33456f"), Color("2b3b66"), Color("9c7a3e")] # cobalt grey, ochre accent
const GUTTER := Color("0e1130") # dark kerb line = collision edge
const KERB := Color("6a6e92")
const OUTSIDE := Color("1a1e40")
const WATER := [Color("0c1648"), Color("1e3478"), Color("5e86c8")]
const REFL_CORE := Color("ffdc73")
const REFL_RIM := Color("d4a03a") # gold

## Facade palettes (a, b, accent): night violet, ochre, blue grey, rose
## brown, slate, light ochre. Ochre stays rare (protanopia: vermilion vs
## ochre is the weakest pair; the dark plinth row is never ochre).
const FACADE_A := [Color("4b4a86"), Color("b88a3c"), Color("5a6fa8"), Color("8e6b5a"), Color("3f5f7a"), Color("c2a06a")]
const FACADE_B := [Color("3c3b72"), Color("9c7030"), Color("45598e"), Color("73554a"), Color("2f4a62"), Color("a3844e")]
## Minimap blocks: the pale lilac facade colour at 55 % brightness (HSV
## value), so the blocks do not outshine the pellets and the exit (UX N-D).
static func minimap_block() -> Color:
	var c: Color = FACADE_C[0]
	return Color.from_hsv(c.h, c.s, 0.55)


const FACADE_C := [
Color("8a86c4"), Color("e0b45a"), Color("9fb6e0"), Color("c79a7a"), Color("7fa8c0"), Color("e6c890")]
const FACADE_PICK := [0, 1, 2, 3, 4, 5, 0, 2, 3, 4] # per lot: ochre (1, 5) 2 in 10
const ROOF_A := [Color("7a3f3a"), Color("5a4e8e"), Color("8e5a3a"), Color("4a4a7a")]
const ROOF_B := [Color("6e4a3c"), Color("4a3e76"), Color("74482e"), Color("3a3a66")]
const LIT_RATIO := 0.38 # share of lit windows (tiefe Nacht)

# ---- brush (stroke) ----
const LOD_NEAR := 14.0 # m: impasto -> soft dabs between these distances
const LOD_FAR := 28.0
const SKY_DRIFT := 0.10 # phase per second (was 0.04: Abnahme 06.10. "schneller"); 0.1 Hz, far below the 3 Hz flicker limit
const SKY_BAKE_SIZE := Vector2i(2048, 1024)
const PULSE_HZ := 0.5

## Brush materials of every single object (landmarks, props, figures,
## trees, lamps, the far city): name -> [a, b, accent colour, params]. Params
## (all optional): len, wid (stroke size, m), angle (rad), accent (share of the
## accent colour), emit (self light), mode (0 plain, 1 concentric, 2 radial
## around "ctr" in map space x/z), bump, band (> 0: brick/stone bands of
## that height), band_col, back (two-sided, back faces in "back_col"), rough.
const MATS := {
	"post": ["1a2340", "121a30", "2a3660", {"len": 0.5, "wid": 0.05}],
	"glass": ["ffe9a0", "f6c945", "ffffff", {"accent": 0.3, "len": 0.2, "wid": 0.05, "emit": 2.2}],
	"glass_big": ["ffe9a0", "f6c945", "ffffff", {"accent": 0.3, "len": 0.2, "wid": 0.05, "emit": 2.4}],
	"stone": ["b9a27a", "94826a", "e2cfa0", {"len": 0.6, "wid": 0.09, "accent": 0.14, "emit": 0.10}],
	"stone_d": ["8c7e6a", "6e6458", "b8a688", {"len": 0.6, "wid": 0.09, "accent": 0.12, "emit": 0.10}],
	"plinth": ["7e7262", "665c50", "a4967c", {"len": 0.7, "wid": 0.1, "accent": 0.1, "emit": 0.06, "angle": 0.0}],
	"dark": ["1e1a34", "151228", "2e2850", {"len": 0.4, "wid": 0.07, "accent": 0.08}],
	"vault": ["2e2a4a", "3a3560", "6a5a8a", {"len": 0.5, "wid": 0.08, "accent": 0.1, "emit": 0.05}],
	"cavea": ["9c8a70", "7e6e5c", "c8b48e", {"mode": 1, "ctr": Vector2(68.0, 45.0), "len": 0.9, "wid": 0.35, "accent": 0.1, "back": 1.0, "back_col": "2a2644"}],
	"cafe_wall": ["f2c14e", "e8b03c", "ffe48a", {"accent": 0.25, "len": 0.6, "wid": 0.1, "emit": 0.55, "angle": 0.1}],
	"wood_door": ["5a3a22", "46301c", "7a5432", {"len": 0.3, "wid": 0.05}],
	"wood_door_v": ["5a3a22", "46301c", "7a5432", {"len": 0.3, "wid": 0.05, "angle": 1.5708}],
	"awning": ["f6c945", "efb83a", "fff1b0", {"accent": 0.2, "len": 1.4, "wid": 0.12, "emit": 0.35, "angle": 1.5708}],
	"table": ["e9d9a8", "d6c48f", "ffffff", {"len": 0.3, "wid": 0.05, "emit": 0.15}],
	"chair": ["6b4a2e", "55391f", "8b6a3a", {"len": 0.25, "wid": 0.05}],
	"coat_blue": ["7a86c0", "6a76b0", "a8b4e0", {"len": 0.3, "wid": 0.06, "angle": 1.5708, "emit": 0.12}],
	"coat_ochre": ["b08a62", "9a7450", "d8b488", {"len": 0.3, "wid": 0.06, "angle": 1.5708, "emit": 0.12}],
	"coat_lilac": ["9a8ac8", "8474b4", "c4b8e8", {"len": 0.3, "wid": 0.06, "angle": 1.5708, "emit": 0.12}],
	"skin": ["d9a066", "c8946a", "f0c080", {"len": 0.15, "wid": 0.05}],
	"bronze": ["3a3a52", "2a2a42", "8a7a5a", {"len": 0.25, "wid": 0.05, "angle": 1.5708}],
	"frieze": ["d2be94", "b4a07a", "f0e0b8", {"len": 0.25, "wid": 0.06, "accent": 0.2}],
	"roof_red": ["7a3f3a", "6e4a3c", "2a2a55", {"len": 0.5, "wid": 0.1}],
	"granite": ["9a8a92", "7a6a78", "c8b0b0", {"len": 0.5, "wid": 0.07, "angle": 1.5708}],
	"dome": ["4a4a7a", "3a3a66", "8a86c4", {"len": 0.4, "wid": 0.08}],
	"clock": ["ffe9a0", "f6d27a", "ffffff", {"emit": 1.2, "len": 0.2, "wid": 0.05}],
	"seats": ["a8967a", "8c7c64", "d0be98", {"len": 0.8, "wid": 0.3, "angle": 1.5708, "accent": 0.1}],
	"baths": ["b9a27a", "94826a", "e2cfa0", {"band": 0.55, "band_col": "7a4a3a", "len": 0.4, "wid": 0.08, "emit": 0.08}],
	"window_lit": ["f6c945", "e8b03c", "fff1b0", {"emit": 0.9, "len": 0.2, "wid": 0.05, "angle": 1.5708}],
	"iron": ["1a2140", "141a34", "3a4470", {"len": 0.6, "wid": 0.08}],
	"hull": ["3a2a2e", "2a1e22", "6a4a3a", {"len": 0.5, "wid": 0.08}],
	"quay": ["6e6a7e", "58556a", "9a93a8", {"len": 0.5, "wid": 0.12, "accent": 0.1}],
	"parapet": ["8a8296", "6e6880", "b8aeb8", {"len": 0.45, "wid": 0.1, "accent": 0.12}],
	"trunk": ["b8b090", "7a7a6a", "d8d0b0", {"len": 0.35, "wid": 0.07, "angle": 1.5708, "emit": 0.16}],
	"crown": ["34557a", "2a4868", "8aaac8", {"len": 0.45, "wid": 0.08, "accent": 0.2, "bump": 0.9, "mode": 2, "ctr": Vector2(27.0, 40.0), "emit": 0.14}],
	"cypress": ["102520", "1e3f30", "2e5a3e", {"accent": 0.1, "angle": 1.35, "len": 0.9, "wid": 0.12, "bump": 0.9, "rough": 0.7}],
	"cart_wood": ["8b6a4a", "6b4a2e", "ab8a5a", {"len": 0.5, "wid": 0.08}],
	"horse": ["6a5a50", "54463e", "8a7462", {"len": 0.4, "wid": 0.08}],
	"far": ["1e2650", "161c40", "2c3570", {"accent": 0.05, "len": 1.2}],
	"ground": ["232a52", "1a1e40", "3a4470", {"accent": 0.06, "len": 1.1, "wid": 0.2}],
	"house_yellow": ["e2b34c", "c99a3a", "f6d27a", {"accent": 0.18, "len": 0.6, "wid": 0.1, "angle": 0.05, "emit": 0.12}],
	"house_roof": ["8e4a3a", "74402e", "2a2a55", {"len": 0.5, "wid": 0.12}],
	"house_window": ["f6c945", "f3b33a", "fff1b0", {"emit": 1.3, "len": 0.22, "wid": 0.06, "angle": 1.5708, "accent": 0.3}],
	"house_door": ["3a2a20", "2a1e16", "5a4030", {"len": 0.3, "wid": 0.05, "angle": 1.5708}],
}
const MAX_MATS := 48


static func mat_names() -> Array:
	var names: Array = MATS.keys()
	names.sort()
	return names


static func mat_index(name: String) -> int:
	return mat_names().find(name)


static func lin(c: Color) -> Vector3:
	var k := c.srgb_to_linear()
	return Vector3(k.r, k.g, k.b)


## Every colour the world (not the pellets, not the exit) may show: palette
## constants and all brush materials. The tests check the exclusive colours
## against this list.
static func world_colors() -> Array:
	var out: Array = [BG, AMBIENT, FOG, MOON, SKY_BASE, SKY_MID, SKY_LIGHT, SKY_YELLOW, LAMP_LIGHT, HALO_CORE, HALO_YELLOW,
		HALO_RIM, WINDOW, WINDOW_B, WINDOW_C, SHUTTER_A, SHUTTER_B, GLASS, DOOR, ROOF_DARK, GUTTER, KERB, OUTSIDE, REFL_CORE, REFL_RIM]
	out.append_array(PAVE)
	out.append_array(WATER)
	out.append_array(FACADE_A)
	out.append_array(FACADE_B)
	out.append_array(FACADE_C)
	out.append_array(ROOF_A)
	out.append_array(ROOF_B)
	for k in MATS:
		var m: Array = MATS[k]
		for i in 3:
			out.append(Color(m[i]))
		var p: Dictionary = m[3]
		if p.has("band_col"):
			out.append(Color(p.band_col))
		if p.has("back_col"):
			out.append(Color(p.back_col))
	return out


## The brush material table as shader uniform arrays (linear colours).
static func apply_mat_table(sm: ShaderMaterial) -> void:
	var a := PackedVector3Array()
	var b := PackedVector3Array()
	var c := PackedVector3Array()
	var p := PackedVector4Array()
	var q := PackedVector4Array()
	var r := PackedVector4Array()
	var e := PackedVector3Array()
	for name in mat_names():
		var m: Array = MATS[name]
		var d: Dictionary = m[3]
		a.append(lin(Color(m[0])))
		b.append(lin(Color(m[1])))
		c.append(lin(Color(m[2])))
		p.append(Vector4(d.get("len", 0.7), d.get("wid", 0.09), d.get("angle", 0.0), d.get("accent", 0.12)))
		var ctr: Vector2 = d.get("ctr", Vector2.ZERO)
		q.append(Vector4(d.get("emit", 0.0), float(d.get("mode", 0)), d.get("bump", 0.7), d.get("band", 0.0)))
		r.append(Vector4(ctr.x, ctr.y, d.get("back", 0.0), d.get("rough", 0.55)))
		var extra := Color(d.get("band_col", d.get("back_col", "000000")))
		e.append(lin(extra))
	while a.size() < MAX_MATS:
		a.append(Vector3.ZERO)
		b.append(Vector3.ZERO)
		c.append(Vector3.ZERO)
		p.append(Vector4(0.7, 0.09, 0, 0))
		q.append(Vector4.ZERO)
		r.append(Vector4.ZERO)
		e.append(Vector3.ZERO)
	sm.set_shader_parameter("mat_a", a)
	sm.set_shader_parameter("mat_b", b)
	sm.set_shader_parameter("mat_c", c)
	sm.set_shader_parameter("mat_p", p)
	sm.set_shader_parameter("mat_q", q)
	sm.set_shader_parameter("mat_r", r)
	sm.set_shader_parameter("mat_e", e)
