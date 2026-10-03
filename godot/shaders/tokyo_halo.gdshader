// Halos of the Tokyo line city (lamps, headlights, tail lights, subway) as
// ONE MultiMesh of camera-facing quads (tokyo_life.gd). Size = scale of the
// instance basis; INSTANCE_CUSTOM: rgb = color * energy, a = pulse in Hz
// (0 = steady; the subway pulses at 0.5 Hz, far below 3 Hz). Fades out
// right in front of the camera (no full-screen flash, red line E8e).
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

uniform float power = 2.4;
uniform float gain = 1.0;

varying vec3 v_col;

void vertex() {
	vec3 center = MODEL_MATRIX[3].xyz;
	float size = length(MODEL_MATRIX[0].xyz);
	float hz = INSTANCE_CUSTOM.a;
	float pulse = hz > 0.0 ? 0.8 + 0.2 * sin(TIME * 6.2831853 * hz) : 1.0;
	float dist = length(INV_VIEW_MATRIX[3].xyz - center);
	v_col = INSTANCE_CUSTOM.rgb * pulse * smoothstep(0.6, 3.5, dist);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * size, INV_VIEW_MATRIX[1] * size, INV_VIEW_MATRIX[2] * size, vec4(center, 1.0));
}

void fragment() {
	float d = length(UV - 0.5) * 2.0;
	float a = pow(max(1.0 - d, 0.0), power);
	ALBEDO = v_col * a * gain;
}
