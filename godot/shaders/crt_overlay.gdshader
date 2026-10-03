// crt_overlay.gdshader — Speedrun base look (spec 1.1): calm arcade feel.
// Resolution independent: a fixed number of lines per image height
// (line_count = 270) instead of "every 3rd pixel row"; edges antialiased via
// fwidth so 720p and 4K show the same structure. Vignette in SCREEN_UV.
// No flicker, no screen curvature, no color fringes (comfort, readability).
shader_type canvas_item;
uniform float line_count = 270.0;   // lines per image height (resolution independent)
uniform float line_strength = 0.22;
uniform float vignette = 0.5;
void fragment() {
	float y = SCREEN_UV.y * line_count;
	float fw = max(fwidth(y), 1e-4);
	// dark third of every line, antialiased
	float p = fract(y);
	float dark = clamp((0.33 - p) / fw + 0.5, 0.0, 1.0);
	dark *= clamp(1.0 / (fw * 3.0), 0.0, 1.0);   // < 3 px per line: fade the structure out instead of moiré
	vec2 d = SCREEN_UV - vec2(0.5);
	float v = smoothstep(0.35, 0.85, length(d * vec2(1.0, 1.25))) * vignette;
	COLOR = vec4(0.0, 0.0, 0.0, clamp(dark * line_strength + v, 0.0, 0.85));
}
