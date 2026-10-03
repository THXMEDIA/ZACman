// Road paint of the Tokyo crossing (zebras, scramble diagonals, center
// dashes): dull, unlit off-white on the wet asphalt, no glow. Wet paint is
// darker where the baked puddle mask (tokyo_wet.gd) puts water; the
// reflection layer without SSR lies above it, so puddles mirror over it.
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform vec3 paint_color : source_color = vec3(0.42, 0.40, 0.38);
uniform sampler2D puddle_tex : filter_linear, repeat_disable;
uniform vec2 map_size = vec2(94.0, 94.0); // world size of the mask (m)
uniform float cell = 2.0;
uniform float wet_dark = 0.5;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float m = texture(puddle_tex, (wpos.xz + cell * 0.5) / map_size).r;
	float puddle = smoothstep(0.6, 0.635, m);
	ALBEDO = paint_color * mix(0.78, wet_dark, puddle);
}
