// Amsterdam: the things on the desk beyond the model edge (giant pencil,
// coffee mug, steel ruler, desk-lamp base) in one mesh with vertex colours.
// COLOR.a picks the surface: < 0.25 matte (wood, graphite, eraser), < 0.5
// lacquer (pencil, glossy), < 0.75 ceramic (mug, coffee), else metal (ruler,
// ferrule). Pencil yellow is used only here, beyond the way, never pellet size.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

void fragment() {
	ALBEDO = COLOR.rgb;
	float m = COLOR.a;
	if (m < 0.25) { ROUGHNESS = 0.85; }
	else if (m < 0.5) { ROUGHNESS = 0.28; CLEARCOAT = 1.0; CLEARCOAT_ROUGHNESS = 0.1; }
	else if (m < 0.75) { ROUGHNESS = 0.12; CLEARCOAT = 1.0; CLEARCOAT_ROUGHNESS = 0.05; }
	else {
		ROUGHNESS = 0.32;
		METALLIC = 0.85;
		// engraved scale of the ruler: UV.x in metres along it, UV.y across
		if (UV.y > 0.0) {
			float mm = abs(fract(UV.x * 10.0) - 0.5);
			float cm = abs(fract(UV.x) - 0.5);
			float tick = (1.0 - step(0.06, mm)) * step(UV.y, 0.25) + (1.0 - step(0.03, cm)) * step(UV.y, 0.45);
			ALBEDO = mix(ALBEDO, vec3(0.08), clamp(tick, 0.0, 1.0) * 0.9);
		}
	}
}
