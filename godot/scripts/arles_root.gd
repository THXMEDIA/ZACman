extends Node3D
## Root node of the painted Arles night city (arles_scenery.gd builds it).
## Bakes the swirl sky once (technical condition): a SubViewport renders
## arles_sky_bake.gdshader (line integral convolution, seamless all around)
## into a 2048 x 1024 texture a single time; it is read back with mipmaps, the
## viewport is freed, and the finished texture is kept for the session (code
## W3): every later Arles start reads the cached texture and bakes nothing. At
## run time the sky shader only reads that texture (flow map, three samples).
## The read-back waits for RenderingServer.frame_post_draw as a one-shot
## connection (no await: freeing the city right after the build leaves no
## coroutine behind). Main forwards "Effekte reduzieren" here: the sky stands,
## the Rhône stops trembling, the brush gets calmer (the exit pulse stops in
## arles_exit.gd).

const Style := preload("res://scripts/arles_style.gd")

## The baked sky of this session (null until the first bake was read back).
static var baked_sky: ImageTexture = null

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
## been read back into a mipmapped ImageTexture, "cached" when this start took
## the texture of an earlier bake.
var sky_state := ""
var _reduce_fx := false
var _bake_tries := 0


func setup_sky(sky_mat: ShaderMaterial, bake_mat: ShaderMaterial) -> void:
	sky_material = sky_mat
	bake_material = bake_mat
	if baked_sky != null:
		sky_material.set_shader_parameter("baked", baked_sky)
		sky_state = "cached"
		return
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
		_wait_for_bake()


func _wait_for_bake() -> void:
	# headless (tests): nothing is drawn, keep the viewport texture
	if DisplayServer.get_name() == "headless":
		return
	RenderingServer.frame_post_draw.connect(_finish_bake, CONNECT_ONE_SHOT)


func _finish_bake() -> void:
	if not is_inside_tree() or not is_instance_valid(bake_viewport):
		return
	var img := bake_viewport.get_texture().get_image()
	if img == null or img.is_empty():
		# not drawn yet: wait for the next frame (a few at most)
		_bake_tries += 1
		if _bake_tries < 4:
			RenderingServer.frame_post_draw.connect(_finish_bake, CONNECT_ONE_SHOT)
		return
	store_bake(img)


## Keeps a finished bake (mipmapped) for the session and frees the viewport.
func store_bake(img: Image) -> void:
	img.generate_mipmaps()
	baked_sky = ImageTexture.create_from_image(img)
	sky_material.set_shader_parameter("baked", baked_sky)
	sky_state = "image"
	var save := OS.get_environment("ARLES_SKY_SAVE") # QA: keep the baked strokes as a picture
	if save != "":
		var small := img.duplicate()
		small.clear_mipmaps()
		small.resize(1024, 512)
		small.save_png(save)
	if is_instance_valid(bake_viewport):
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
