// pacman_wall.gdshader — Speedrun base look "Lagune" (spec 1.1). The look
// itself lives in pacman_wall_base.gdshaderinc, shared with kond_wall.gdshader
// so the rabbit-condition looks start and end on exactly this picture.
// MazeView swaps to kond_wall only while a condition runs (Look-API).
shader_type spatial;
render_mode cull_back, specular_disabled;

#include "res://shaders/pacman_wall_base.gdshaderinc"

void fragment() {
	vec3 a;
	vec3 e;
	pacman_wall(CAMERA_POSITION_WORLD, a, e);
	ALBEDO = a;
	ROUGHNESS = 0.9;
	EMISSION = e;
}
