// Amsterdam: dried white glue squeezed out at house feet and tree bases -
// clear, slightly yellowish, glossy beads (transparent, one MultiMesh).
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, diffuse_burley, specular_schlick_ggx, cull_back;

void fragment() {
	float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	ALBEDO = vec3(0.95, 0.9, 0.74);
	ALPHA = mix(0.55, 0.22, ndv);
	ROUGHNESS = 0.04;
	SPECULAR = 0.9;
	CLEARCOAT = 1.0;
	CLEARCOAT_ROUGHNESS = 0.02;
}
