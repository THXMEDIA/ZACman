// Neon tube of the Tokyo line city (scripts/neon_lines.gd): unshaded, the
// only light sources of the city. One material per color; UV.x carries the
// per-vertex brightness factor (edges, floor bands, base line, background),
// so a whole color is one mesh and one draw call. Brightness falls off with
// height to top_mul (style rule: "Helligkeit nach oben auf ~30 %").
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform vec3 line_color : source_color = vec3(1.0);
uniform float energy = 2.0;
uniform float fade_h = 40.0;
uniform float top_mul = 0.3;

varying float world_y;

void vertex() {
	world_y = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
}

void fragment() {
	float f = mix(1.0, top_mul, smoothstep(0.0, fade_h, world_y));
	ALBEDO = line_color * energy * UV.x * f;
}
