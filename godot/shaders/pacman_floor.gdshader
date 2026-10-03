// pacman_floor.gdshader — Speedrun base look "Lagune" (spec 1.1). The look
// lives in pacman_floor_base.gdshaderinc, shared with kond_floor.gdshader.
shader_type spatial;
render_mode specular_schlick_ggx;

#include "res://shaders/pacman_floor_base.gdshaderinc"

void fragment() {
	vec3 a;
	vec3 e;
	pacman_floor(a, e);
	ALBEDO = a;
	ROUGHNESS = 0.85;
	EMISSION = e;
}
