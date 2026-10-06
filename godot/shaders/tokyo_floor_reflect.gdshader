// Wet-floor reflection WITHOUT SSR (Compatibility renderer; tokyo_wet.gd
// turns it off when SSR is available, docs/design/tokyo-explorer.md M2):
// a thin additive layer just above the floor that samples the already
// rendered opaque image at the view direction mirrored about the horizon
// (the reflection of everything that is far enough away), streaked
// vertically like light on rain-soaked asphalt and sharp in the puddles
// (same baked mask as the floor). No second camera, no SubViewport: one
// screen copy and a few texture taps per floor pixel.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, fog_disabled, shadows_disabled;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform sampler2D puddle_tex : filter_linear, repeat_disable;
uniform float cell = 2.0;
uniform vec2 maze_size = vec2(47.0, 47.0);
uniform float puddle_threshold = 0.6;
uniform float gutter_amount = 0.32;
uniform vec2 road_x = vec2(41.0, 51.0);
uniform vec2 road_z = vec2(41.0, 51.0);
uniform float strength = 1.15;
uniform float asphalt_mul = 0.5; // half-wet asphalt reflects less than a puddle
uniform float streak = 0.09; // vertical smear (screen fraction)

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float h21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 p = wpos.xz;
	vec2 map_uv = (p + cell * 0.5) / (maze_size * cell);
	bool on_road = (p.x > road_x.x && p.x < road_x.y) || (p.y > road_z.x && p.y < road_z.y);
	float m = texture(puddle_tex, map_uv).r;
	float dx = min(abs(p.x - road_x.x), abs(p.x - road_x.y));
	float dz = min(abs(p.y - road_z.x), abs(p.y - road_z.y));
	float gutter = exp(-min(dx, dz) * 1.6) * (on_road ? 1.0 : 0.45);
	float puddle = smoothstep(puddle_threshold, puddle_threshold + 0.035, m + gutter * gutter_amount);

	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	vec3 I = normalize(wpos - cam);
	vec3 R = vec3(I.x, -I.y, I.z);
	// screen position of the mirrored direction (a point at infinity)
	vec4 cr = PROJECTION_MATRIX * (VIEW_MATRIX * vec4(R, 0.0));
	vec4 ci = PROJECTION_MATRIX * (VIEW_MATRIX * vec4(I, 0.0));
	vec2 uv_r = cr.xy / cr.w * 0.5 + 0.5;
	vec2 uv_i = ci.xy / ci.w * 0.5 + 0.5;
	vec2 uv = SCREEN_UV + (uv_r - uv_i);

	float cos_v = clamp(-I.y, 0.0, 1.0);
	float fres = 0.12 + 0.88 * pow(1.0 - cos_v, 3.0);

	// vertical streak: taps from a little below to well above the mirror
	// point (towards the horizon, where the reflected light comes from)
	vec3 sharp = texture(screen_tex, uv).rgb;
	vec3 blur = vec3(0.0);
	float jitter = h21(floor(FRAGCOORD.xy)) - 0.5;
	for (int i = 0; i < 10; i++) {
		float t = (float(i) + jitter) / 9.0;
		vec2 o = vec2(0.0, (t - 0.25) * streak);
		blur += texture(screen_tex, uv + o).rgb;
	}
	blur /= 10.0;
	vec3 c = mix(blur, sharp, puddle * 0.85);

	// fade where the mirrored ray leaves the image (top edge) or the floor
	// point lies above the horizon
	float edge = smoothstep(1.0, 0.86, uv.y) * smoothstep(0.0, 0.04, uv.y) * smoothstep(0.0, 0.03, uv.x) * smoothstep(1.0, 0.97, uv.x);
	float wet = mix(asphalt_mul * (on_road ? 1.0 : 0.7), 1.0, puddle);
	ALBEDO = c * fres * wet * edge * strength;
	ALPHA = 1.0;
}
