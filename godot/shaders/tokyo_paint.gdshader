// Road paint of the Tokyo crossing (zebras, scramble diagonals, center
// dashes): dull, unlit off-white on the wet asphalt, no glow.
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform vec3 paint_color : source_color = vec3(0.42, 0.40, 0.38);

void fragment() {
	ALBEDO = paint_color;
}
