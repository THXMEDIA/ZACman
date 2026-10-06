extends Node3D
## TokyoMetroStation — the subway exit (地下鉄) in the station facade of the
## Tokyo Explorer city: the only filled surface of the line city, in the
## exclusive subway green, with a canopy frame, the sign and a soft green
## light on the plaza. Same interface as metro_station.gd (Manhattan): Main
## places it on the metro cell (setup) and checks the player's distance to
## it; stepping in is the way into a speedrun.
##
## The facade is one cell north of the metro cell (tokyo_maze.gd METRO_CELL),
## so the portal sits at local z = -1 m. It pulses slowly (0.5 Hz, far below
## the 3 Hz flicker limit).

const Style := preload("res://scripts/tokyo_style.gd")
const NeonLinesScript := preload("res://scripts/neon_lines.gd")
const TokyoScenery := preload("res://scripts/tokyo_scenery.gd")

const PULSE_HZ := 0.5
const PORTAL_ENERGY := 1.5
const FACADE_Z := -0.94 # just in front of the station facade

var portal: MeshInstance3D
var portal_material: StandardMaterial3D
var frame_mesh: MeshInstance3D
var sign_label: Label3D
var light: OmniLight3D
var _t := 0.0


func setup(cell_world_pos: Vector3) -> void:
	# Main hands in the sign height of the Manhattan station; this one is
	# built from the floor up.
	position = Vector3(cell_world_pos.x, 0.0, cell_world_pos.z)

	portal = MeshInstance3D.new()
	portal.name = "Portal"
	var q := QuadMesh.new()
	q.size = Vector2(2.6, 2.1)
	portal.mesh = q
	portal_material = StandardMaterial3D.new()
	portal_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	portal_material.albedo_color = Style.METRO * PORTAL_ENERGY
	portal.material_override = portal_material
	portal.position = Vector3(0.0, 1.05, FACADE_Z)
	add_child(portal)

	var lines = NeonLinesScript.new()
	lines.define("metro", Style.METRO, 2.4)
	var z := FACADE_Z + 0.03
	var zc := z + 1.4
	lines.polyline([Vector3(-1.6, 0.0, z), Vector3(-1.6, 2.5, z), Vector3(1.6, 2.5, z), Vector3(1.6, 0.0, z)], "metro", 0.07)
	lines.polyline([Vector3(-1.9, 2.5, z), Vector3(-1.9, 2.5, zc), Vector3(1.9, 2.5, zc), Vector3(1.9, 2.5, z)], "metro", 0.06)
	for s in 4: # stair edges going down behind the portal
		var y := 0.85 - s * 0.24
		lines.line(Vector3(-1.2, y, z - 0.05 - s * 0.01), Vector3(1.2, y, z - 0.05 - s * 0.01), "metro", 0.03, 0.6)
	var built: Array = lines.build(self, 40.0, 1.0)
	frame_mesh = built[0]

	sign_label = Label3D.new()
	sign_label.name = "Schild_地下鉄"
	sign_label.text = "地下鉄 ↓"
	var font := TokyoScenery.load_sign_font()
	if font != null:
		sign_label.font = font
	sign_label.font_size = 96
	sign_label.outline_size = 0
	sign_label.pixel_size = 0.75 / 96.0
	sign_label.modulate = Color(Style.METRO.r * 2.0, Style.METRO.g * 2.0, Style.METRO.b * 2.0)
	sign_label.shaded = false
	sign_label.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	sign_label.position = Vector3(0.0, 3.05, z + 0.02)
	add_child(sign_label)

	light = OmniLight3D.new()
	light.light_color = Style.METRO
	light.omni_range = 6.0
	light.light_energy = 1.2
	light.position = Vector3(0.0, 1.6, 0.4)
	add_child(light)


func update(delta: float, _now: float) -> void:
	_t += delta
	var p := 0.85 + 0.15 * sin(_t * TAU * PULSE_HZ)
	portal_material.albedo_color = Style.METRO * (PORTAL_ENERGY * p)
	light.light_energy = 1.2 * p
