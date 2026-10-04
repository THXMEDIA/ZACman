// Amsterdam: the real corrugation at every cut edge of the base plate (quay
// walls, the model's outer edge). Geometry from amsterdam_scenery.gd
// (flute_mesh): liners, the two wave sheets of the double-wall board (B + C
// flute) and the dark back of the open cavities, 1.2 m deep. Light falls into
// the cavities and the sun throws real shadows in them. COLOR.r = how far the
// light reaches (1 at the cut plane, dark at the back); COLOR.g = 1 on the
// paper face in the cut plane. Beyond far_flat the pattern fades to its mean
// (moire protection).
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;

#include "res://shaders/amsterdam_common.gdshaderinc"

varying float vdist;
varying vec3 wp;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vdist = length(wp - CAMERA_POSITION_WORLD);
}

void fragment() {
	float far = 1.0 - smoothstep(far_flat * 0.6, far_flat * 1.2, vdist);
	vec3 c; vec2 nxy; float r;
	kraft_face(UV * vec2(1.0, 3.0), far, c, nxy, r);
	// light falls off quickly into the cavity (vertex colour is linear in depth)
	float lit = pow(COLOR.r, 1.8);
	vec3 cav = c * mix(0.14, 1.0, lit);
	cav = mix(cav, c * 1.12, COLOR.g);
	// far away: the mean of liner, flute and cavity (same as flute_mask's 0.62)
	vec3 mean = c * 0.62;
	ALBEDO = mix(mean, cav, far);
	ROUGHNESS = 0.93;
	AO = mix(1.0, mix(0.35, 1.0, lit), far);
	AO_LIGHT_AFFECT = 0.6;
}
