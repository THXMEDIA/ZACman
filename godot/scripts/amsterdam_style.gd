extends RefCounted
## AmsterdamStyle — the approved look "Pappmodell Amsterdam 1:100, Abend"
## (direction J / J v2, owner decision E21 04.10.2026, studio template
## studio/projekte/zapmaniac/art/explorer-stile-v1.md) as constants, plus the
## loader for the CC0 photo scans (docs/art/lizenzen.md).
##
## The city is an architecture model of corrugated cardboard at 1:100, seen
## from ant height: buildings have their real size, the material is scaled
## up a hundredfold (the board is 40 cm thick, the flutes of every cut edge
## are 70 cm apart). Golden hour: a low warm sun along the canals, a desk
## lamp, long shadows; beyond the model edge the cutting mat, a giant pencil,
## a coffee mug and the desk.
##
## Readability rules (docs/design/amsterdam-explorer.md):
##   - blue only for the pins (pellets), #00B894 only for the exit (tram + flag)
##   - the quay edge (cut edge of the base plate) and the facade foot are the
##     collision edges; trees stand only at the quay
##   - pencil yellow only beyond the model edge, never in pellet size
##   - no animation in the city; the exit pulses at 0.5 Hz (off with
##     "Effekte reduzieren"); no depth of field or grain in the game view

## Palette (art spec J).
const HAZE := Color("e9e3d8") # studio haze / fog
const KRAFT_LIT := Color("c9a47a") # kraft in the light
const KRAFT := Color("a98157")
const VOID := Color("5b412b") # flute cavities, shadows
const WATER := Color("1a120b") # lacquered water
const TABLE := Color("6e5139")
const PENCIL := Color("d9a21e") # only beyond the model edge
const MUG := Color("e8e2d6")
const WHITE_PAINT := Color("e9e4d8") # the white drawbridge, the crown
const MAT := Color("34393a") # cutting mat, slate grey (no green)
const PIN := Color("2e6bff") # exclusive: pellets (glass pin heads)
const PIN_CORE := Color("b4cdff")
const EXIT := Color("00b894") # exclusive: exit tram and flag
const FOG := Color("e9c79c") # warm evening haze
## Colour left in the blurred room behind the model (prototype "abend": 0.6).
const SKY_SATURATION := 0.35
## Brightest the blurred room may get (luminance before the background
## energy): the café's windows were a glaring patch that competed with the
## exit (QA K1); above SKY_KNEE the room is compressed softly up to SKY_MAX.
const SKY_KNEE := 0.45
const SKY_MAX := 0.7
const MINIMAP_WATER := Color("4b5559") # slate canals on the minimap (not blue)

## The little card people and bicycles (amsterdam_figures.gd, amsterdam_life.gd):
## printed paper in muted, warm colours - no blue (pins), no green (exit), no
## saturated yellow (pencil), none brighter than the cream of the white paint.
const FOLK_COATS := [Color("e2dac8"), Color("b4694a"), Color("a77a46"), Color("a5645d"),
	Color("5a4132"), Color("8b8174"), Color("c7bfb0"), Color("8e4a32")]
const FOLK_SKIN := [Color("e8c9a5"), Color("d1a47a"), Color("a8744f"), Color("7a5039")]
const FOLK_BIKES := [Color("2a2724"), Color("5e2a26"), Color("d8cfba"), Color("8e4a32"),
	Color("4d4a2c"), Color("4a3426"), Color("7b7771"), Color("a8664a")]

## Lights (golden hour, Kelvin as colour).
const SUN_COLOR := Color(1.0, 0.70, 0.42) # ~2900 K
const LAMP_COLOR := Color(1.0, 0.66, 0.36) # ~2700 K
const BOUNCE_COLOR := Color("d08a4a")
## Light travel direction of the sun: low (about 15 degrees) from the
## west-southwest, along the canals, so the south-facing dancing houses glow.
const SUN_DIR := Vector3(0.86, -0.27, -0.43)

## Model dimensions (m, ant height).
const T := 0.4 # board thickness (4 mm x 100)
const PITCH := 0.7 # flute pitch (7 mm x 100)
const WATER_Y := -0.85 # lacquered water surface below the street
const PLATE_Y := -1.0 # underside of the base plate = top of the cutting mat
const KD := 1.2 # depth of the open flute cavities at a cut edge
const TABLE_Y := -1.3 # top of the desk

## Photo scans (CC0, docs/art/lizenzen.md). Swap for the 2-4K originals by
## replacing the files under the same names (see the doc for the steps).
const TEX_DIR := "res://textures/amsterdam/"
const TEX_KRAFT_ALBEDO := TEX_DIR + "kraft_foto_albedo.jpg"
const TEX_KRAFT_NORMAL := TEX_DIR + "kraft_foto_normal.jpg"
const TEX_KRAFT_ROUGH := TEX_DIR + "kraft_foto_rough.jpg"
const TEX_TAPE_ALBEDO := TEX_DIR + "tape_foto_albedo.jpg"
const TEX_TAPE_NORMAL := TEX_DIR + "tape_foto_normal.jpg"
const TEX_WOOD_ALBEDO := TEX_DIR + "holz_albedo.jpg"
const TEX_WOOD_NORMAL := TEX_DIR + "holz_normal.jpg"
const TEX_WOOD_ROUGH := TEX_DIR + "holz_rough.jpg"
const TEX_HDRI := TEX_DIR + "hdri_warm.hdr"
const TEXTURES := [TEX_KRAFT_ALBEDO, TEX_KRAFT_NORMAL, TEX_KRAFT_ROUGH, TEX_TAPE_ALBEDO, TEX_TAPE_NORMAL,
	TEX_WOOD_ALBEDO, TEX_WOOD_NORMAL, TEX_WOOD_ROUGH, TEX_HDRI]
## World size of one tile of the kraft scan (m): the scan shows ~16 cm of a
## real box, i.e. 16 m at ant height. FOTO_DETAIL_M is a second, smaller
## sampling of the same scan for detail near the camera.
const FOTO_M := 16.0
const FOTO_DETAIL_M := 3.1
## Mean colour of the scan (for the colour pull), measured on the 1K file.
const FOTO_MEAN := Color(0.616, 0.510, 0.341)

static var _cache := {}
static var _sky: Sky = null


## Whether loading the raw scan file is allowed when the import is missing:
## only outside exported builds (code W4). An export carries the imported
## textures only; there the raw path would not exist anyway and only print
## errors.
static func raw_fallback_allowed() -> bool:
	return not OS.has_feature("template")


## A texture from the scan set: the imported resource when the project was
## imported (editor, export), otherwise - only outside exported builds - the
## raw file (fresh checkout, tests run before the first import), same idea as
## TokyoScenery.load_sign_font. A missing texture warns once (null is cached).
static func tex(path: String) -> Texture2D:
	if _cache.has(path):
		return _cache[path]
	var t: Texture2D = null
	if imported(path):
		t = load(path) as Texture2D
	if t == null and raw_fallback_allowed():
		var img := Image.load_from_file(ProjectSettings.globalize_path(path))
		if img != null and not img.is_empty():
			img.generate_mipmaps()
			t = ImageTexture.create_from_image(img)
	if t == null:
		push_warning("AmsterdamStyle: texture %s missing (not imported)" % path)
	_cache[path] = t
	return t


static func tex_image(path: String) -> Image:
	var img: Image = null
	if imported(path):
		var t = load(path)
		if t is Texture2D:
			img = t.get_image()
	if (img == null or img.is_empty()) and raw_fallback_allowed():
		img = Image.load_from_file(ProjectSettings.globalize_path(path))
	if img == null or img.is_empty():
		push_warning("AmsterdamStyle: image %s missing (not imported)" % path)
		return null
	if img.is_compressed():
		img.decompress()
	return img


## Whether the import of `path` exists (its .import file names the imported
## file(s); on a fresh checkout without .godot/ they are missing and loading
## would only print errors).
static func imported(path: String) -> bool:
	var f := FileAccess.open(path + ".import", FileAccess.READ)
	if f == null:
		return false
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line.begins_with("path") and line.contains("="):
			var target := line.get_slice("=", 1).strip_edges().trim_prefix("\"").trim_suffix("\"")
			if FileAccess.file_exists(target):
				return true
		if line.begins_with("[deps]"):
			break
	return false


## The evening sky of the room behind the model: the warm interior HDRI out of
## focus (the room is far behind a 1:100 model), as in the prototype: half
## size, highlights compressed, blurred, colours pulled to a warm grey (the
## room must not compete with the pin blue or the exit green: the café's
## daylight windows would be bluish). Built once. Resizing runs in RGBF
## (Image interpolates half floats only by nearest); Compatibility shows
## RGBE9995 panoramas wrong, so it ends as RGBH.
static func sky() -> Sky:
	if _sky != null:
		return _sky
	var img := tex_image(TEX_HDRI)
	var s := Sky.new()
	var pm := PanoramaSkyMaterial.new()
	if img != null and not img.is_empty():
		img.convert(Image.FORMAT_RGBF)
		var w := img.get_width()
		var h := img.get_height()
		# blur: average down to 1/16 (box steps), process, then smooth back up
		var cw := w
		while cw > maxi(32, w / 16):
			cw /= 2
			img.resize(cw, maxi(8, cw * h / w), Image.INTERPOLATE_BILINEAR)
		for y in img.get_height():
			for x in img.get_width():
				var c := img.get_pixel(x, y)
				var lum := (c.r + c.g + c.b) / 3.0
				var k := 1.0 / (1.0 + maxf(lum - 2.5, 0.0) / 2.5)
				c = Color(c.r * k, c.g * k, c.b * k)
				lum *= k
				# QA K1: no glaring patch in the room - a soft knee above
				# SKY_KNEE that never exceeds SKY_MAX
				if lum > SKY_KNEE:
					var span := SKY_MAX - SKY_KNEE
					var l2 := SKY_KNEE + span * (1.0 - exp(-(lum - SKY_KNEE) / span))
					c = Color(c.r * l2 / lum, c.g * l2 / lum, c.b * l2 / lum)
					lum = l2

				# desaturate to 35 % and tint warm (no blue left)
				var g := Color(lum * 1.08, lum * 0.98, lum * 0.82)
				c = g.lerp(c, SKY_SATURATION)
				c.b = minf(c.b, c.g * 0.92)
				img.set_pixel(x, y, c)
		while img.get_width() < w / 2:
			img.resize(img.get_width() * 2, img.get_height() * 2, Image.INTERPOLATE_BILINEAR)
		img.convert(Image.FORMAT_RGBH)
		pm.panorama = ImageTexture.create_from_image(img)
	s.sky_material = pm
	s.radiance_size = Sky.RADIANCE_SIZE_128
	_sky = s
	return s
