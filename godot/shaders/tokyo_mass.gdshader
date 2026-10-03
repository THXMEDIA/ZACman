// Black, unlit building mass of the Tokyo line city: only the neon lines
// emit, the mass just hides what is behind it (fog still applies).
shader_type spatial;
render_mode unshaded;

uniform vec3 mass_color : source_color = vec3(0.012, 0.012, 0.016);

void fragment() {
	ALBEDO = mass_color;
}
