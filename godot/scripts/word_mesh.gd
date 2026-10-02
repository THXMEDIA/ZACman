extends RefCounted
## WordMesh — builds "letter block" meshes out of real extruded 3D text
## (Godot's TextMesh), for the word-built-world look: a taxi that IS the
## word TAXI, a wall that IS the word WALL, a ghost that IS the word GHOST.
## Ported in spirit from the Alex Gopher "The Child" / H5 music-video
## aesthetic the user referenced — every object is literally its own name,
## as a solid 3D letterform, not a texture or label. English words per the
## user's request, regardless of the rest of the UI being German.
##
## Static-only utility (no autoload, no instance state) — call
## WordMeshScript.build(...) directly on the preloaded script.

static func build(text: String, color: Color, options: Dictionary = {}) -> MeshInstance3D:
	var tm := TextMesh.new()
	tm.text = text
	tm.font_size = int(options.get("font_size", 48))
	tm.depth = float(options.get("depth", 0.3))
	tm.pixel_size = float(options.get("pixel_size", 0.01))
	tm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tm.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = float(options.get("emission_energy", 0.9))
	mat.roughness = float(options.get("roughness", 0.5))
	# Letters are thin extrusions seen from any angle in a maze corridor or
	# a city street — draw both faces so they don't vanish edge-on.
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	tm.material = mat

	var mi := MeshInstance3D.new()
	mi.mesh = tm
	if options.has("rotation_y"):
		mi.rotation.y = options.rotation_y
	return mi


## Convenience: how wide (local X, before any node scale) a word mesh built
## with the same font_size/pixel_size will be — lets callers center/space
## instances without first building them.
static func measure_width(text: String, options: Dictionary = {}) -> float:
	var tm := TextMesh.new()
	tm.text = text
	tm.font_size = int(options.get("font_size", 48))
	tm.pixel_size = float(options.get("pixel_size", 0.01))
	return tm.get_aabb().size.x


## Builds a Node3D holding one letter-block per character of `text`, stacked
## top-to-bottom — the same "totem" technique man_walking_dog.gd already
## uses for its "MAN" figure — so the whole word reads vertically up a
## face, hochkant, rather than lying sideways. Each letter is uniformly
## rescaled (width+height only, not depth — see below) so the stack's total
## height is exactly `target_height` regardless of the word's length: a
## short name ("MOMA") and a long one ("EMPIRESTATEBUILDING", spaces/
## apostrophes stripped) both span the same real building height. Depth
## (the extrusion, local Z) is deliberately left unscaled — scaling it along
## with height would turn a skyscraper's lettering into an absurdly deep
## block instead of a flat-ish relief panel on its face.
## Optional `max_width` / `max_depth` (> 0, in world units) cap each letter's
## X width and Z depth so a tall building's lettering stays inside the
## building's own footprint instead of bulging out over the street (a
## 64-unit skyscraper would otherwise get letters several units wide). The
## letter then gets narrower but keeps its full height — still readable as
## one letter per floor band.
static func build_vertical_stack(text: String, color: Color, target_height: float, options: Dictionary = {}) -> Node3D:
	var root := Node3D.new()
	var clean := text.replace(" ", "").replace("'", "")
	if clean.is_empty() or target_height <= 0.0:
		return root
	var letter_h: float = target_height / clean.length()
	var font_size := int(options.get("font_size", 40))
	var depth := float(options.get("depth", 0.3))
	var emission_energy := float(options.get("emission_energy", 0.9))
	var max_width := float(options.get("max_width", 0.0))
	var max_depth := float(options.get("max_depth", 0.0))
	for i in clean.length():
		var lw: MeshInstance3D = build(clean[i], color, {"font_size": font_size, "depth": depth, "emission_energy": emission_energy})
		var aabb: AABB = lw.mesh.get_aabb()
		var glyph_h: float = aabb.size.y
		if glyph_h > 0.0:
			var factor: float = letter_h / glyph_h
			var sx: float = factor
			if max_width > 0.0 and aabb.size.x * sx > max_width:
				sx = max_width / aabb.size.x
			var sz := 1.0
			if max_depth > 0.0 and aabb.size.z > max_depth:
				sz = max_depth / aabb.size.z
			lw.scale = Vector3(sx, factor, sz)
		lw.position = Vector3(0.0, target_height - letter_h * (i + 0.5), 0.0)
		root.add_child(lw)
	return root
