extends Node3D
## Root node of the painted Arles night city (arles_scenery.gd builds it).
## Bakes the swirl sky once when the level starts (technical condition): a
## SubViewport renders arles_sky_bake.gdshader (line integral convolution,
## seamless all around) into a 2048 x 1024 texture a single time; it is read
## back with mipmaps and the viewport is freed. At run time the sky shader only
## reads that texture (flow map, three samples). Main forwards "Effekte
## reduzieren" here: the sky stands, the Rhône stops trembling, the brush gets
## calmer (the exit pulse stops in arles_exit.gd).

const Style := preload("res://scripts/arles_style.gd")

var city: Node3D = null
var house_box_count := 0
var object_parts: Array = []
var obstacle_boxes: Array = []
var halo_count := 0
var omni_count := 0
var brush_materials: Array = []
var water_material: ShaderMaterial = null
var halo_material: ShaderMaterial = null
var sky_material: ShaderMaterial = null
var bake_material: ShaderMaterial = null
var bake_viewport: SubViewport = null
## "viewport" while the bake texture is the live viewport, "image" once it has
## been read back into a mipmapped ImageTexture.
var sky_state := ""
var _reduce_fx := false


func setup_sky(sky_mat: ShaderMaterial, bake_mat: ShaderMaterial) -> void:
	sky_material = sky_mat
	bake_material = bake_mat
	bake_viewport = SubViewport.new()
	bake_viewport.name = "SkyBake"
	bake_viewport.size = Style.SKY_BAKE_SIZE
	bake_viewport.transparent_bg = false
	bake_viewport.disable_3d = true
	bake_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	var rect := ColorRect.new()
	rect.size = Vector2(Style.SKY_BAKE_SIZE)
	rect.material = bake_mat
	bake_viewport.add_child(rect)
	add_child(bake_viewport)
	sky_material.set_shader_parameter("baked", bake_viewport.get_texture())
	sky_state = "viewport"


func _ready() -> void:
	if bake_viewport != null and sky_material != null:
		_finish_bake()


func _finish_bake() -> void:
	# headless (tests): nothing is drawn, keep the viewport texture
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	if not is_instance_valid(bake_viewport):
		return
	var img := bake_viewport.get_texture().get_image()
	if img == null or img.is_empty():
		return
	img.generate_mipmaps()
	sky_material.set_shader_parameter("baked", ImageTexture.create_from_image(img))
	sky_state = "image"
	var save := OS.get_environment("ARLES_SKY_SAVE") # QA: keep the baked strokes as a picture
	if save != "":
		var small := img.duplicate()
		small.clear_mipmaps()
		small.resize(1024, 512)
		small.save_png(save)
	bake_viewport.queue_free()
	bake_viewport = null


func set_reduce_fx(on: bool) -> void:
	_reduce_fx = on
	if sky_material != null:
		sky_material.set_shader_parameter("moving", 0.0 if on else 1.0)
	if water_material != null:
		water_material.set_shader_parameter("shimmer", 0.0 if on else 1.0)
	for m in brush_materials:
		m.set_shader_parameter("calm", 1.0 if on else 0.0)
	# the floor belongs to MazeView (arles_floor.gdshader): calmer as well
	var mv = get_parent()
	if mv != null and "floor_mesh" in mv and mv.floor_mesh != null and mv.floor_mesh.material_override is ShaderMaterial:
		mv.floor_mesh.material_override.set_shader_parameter("calm", 1.0 if on else 0.0)


func fx_reduced() -> bool:
	return _reduce_fx


## What moves in the city: the sky drift and the trembling Rhône.
func animated_nodes() -> Array:
	if _reduce_fx:
		return []
	return [sky_material, water_material]
