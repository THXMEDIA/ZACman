extends RefCounted
## ConditionLooks — the rabbit-condition looks as data (spec
## docs/design/kaninchen-speedrun.md 1.2, values from the art-direction
## prototype tools/art/speedrun_proto/konditionen.patch, kond_looks.gd).
##
## A look is NOT a second wall set: MazeView registers each one with the Look
## API on the same wall MultiMesh and floor (kond_wall/kond_floor material,
## uniform `look` = shader id). Main blends the environment from the level's
## base environment to `env` with the transition value and switches the
## object style (black outline, fog exemption) at half the transition.
##
##   shader      kond_wall/kond_floor `look` uniform
##   outline     black inverted-hull outline on pellets, power pellets, ghosts
##               (objects keep their color and shape, the outline only
##               separates them from busy walls)
##   objects_ignore_fog  pellets, power pellets, ghosts and the rabbit stay
##               self-luminous through the fog (Stromausfall)
##   env         background / fog / ambient target (null fields = keep base)

const LOOKS := {
	"matrix": {"shader": 1, "outline": true, "objects_ignore_fog": false,
		"env": {"bg": Color(0, 0, 0), "fog": Color(0.0, 0.035, 0.012), "fog_density": 0.05,
			"ambient": Color(0.2, 0.6, 0.3), "ambient_energy": 0.5}},
	"kippbild": {"shader": 2, "outline": true, "objects_ignore_fog": false,
		"env": {"bg": Color("120610"), "fog": Color("1a0814"), "fog_density": 0.04,
			"ambient": Color(0.6, 0.4, 0.4), "ambient_energy": 0.5}},
	"taschenuhr": {"shader": 3, "outline": false, "objects_ignore_fog": false,
		"env": {"bg": Color("0d0905"), "fog": Color("0d0905"), "fog_density": 0.022,
			"ambient": Color(0.75, 0.55, 0.35), "ambient_energy": 0.95}},
	# Sight ~2 cells: exponential fog 0.45/m leaves ~16 % of a wall 4 m away.
	"stromausfall": {"shader": 4, "outline": false, "objects_ignore_fog": true,
		"env": {"bg": Color("020305"), "fog": Color("020305"), "fog_density": 0.45,
			"ambient": Color(0.3, 0.33, 0.38), "ambient_energy": 0.35}},
}

## Black outline material (inverted hull), shared by every outlined object.
static var _outline: StandardMaterial3D = null


static func outline_material() -> StandardMaterial3D:
	if _outline == null:
		_outline = StandardMaterial3D.new()
		_outline.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_outline.albedo_color = Color(0.0, 0.0, 0.0)
		_outline.cull_mode = BaseMaterial3D.CULL_FRONT
		_outline.grow = true
		_outline.grow_amount = 0.022
	return _outline


static func has_look(id: String) -> bool:
	return LOOKS.has(id)


static func get_look(id: String) -> Dictionary:
	return LOOKS.get(id, {})
