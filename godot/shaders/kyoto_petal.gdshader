// Falling cherry-blossom petals (Kyoto): one MultiMesh, all motion in the
// vertex shader (no CPU work per frame). Each instance sits at the top of a
// tree canopy; the petal sinks slowly to the page (fall_speed cycles/s,
// ~0.6 m/s), sways sideways and turns a little. It shrinks to nothing at
// both ends of its fall, so there is no popping and no flicker: every
// periodic change stays far below 3 Hz (tumble * fall_speed cycles/s).
// Switched off with "Effekte reduzieren" (the node is hidden).
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform vec3 petal : source_color = vec3(0.949, 0.839, 0.824);
uniform vec3 edge : source_color = vec3(0.784, 0.220, 0.294);
uniform float fall_speed = 0.1;   // fall cycles per second
uniform float tumble = 2.0;       // turns per fall
uniform float sway = 0.55;        // m
uniform float petal_size = 0.1;         // m
uniform float near_fade = 38.0;   // m: petals farther than this vanish


void vertex() {
	vec3 o = MODEL_MATRIX[3].xyz;
	float ph = INSTANCE_CUSTOM.r;
	float t = TIME * fall_speed * (0.8 + 0.4 * INSTANCE_CUSTOM.g) + ph;
	float f = fract(t);
	float top = max(o.y, 0.5);
	vec3 pos = o + vec3(sin(t * 6.2832 * 1.3 + ph * 20.0) * sway, -f * (top - 0.08), cos(t * 6.2832 * 1.1 + ph * 17.0) * sway);
	float dist = length(pos - CAMERA_POSITION_WORLD);
	float k = smoothstep(0.0, 0.1, f) * (1.0 - smoothstep(0.9, 1.0, f)) * (1.0 - smoothstep(near_fade - 8.0, near_fade, dist));
	float a = f * tumble * 6.2832 + ph * 30.0;
	vec2 v = VERTEX.xy * petal_size * k;
	v = vec2(v.x * cos(a) - v.y * sin(a), v.x * sin(a) + v.y * cos(a));
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], vec4(pos, 1.0));
	VERTEX = vec3(v, 0.0);
}

void fragment() {
	// a petal: a pointed oval with a thin vermilion rim
	vec2 q = (UV - 0.5) * vec2(1.0, 1.6);
	if (dot(q, q) > 0.25) {
		discard;
	}
	ALBEDO = mix(petal, edge, smoothstep(0.17, 0.25, dot(q, q)));
}
