// Passers-by of the Tokyo line city (tokyo_figures.gd walker_mesh, ONE
// MultiMesh for the walkers and the scramble crowd, tokyo_life.gd). The
// gait is animated here, not on the CPU: legs swing around the hip, arms
// around the shoulder, body and umbrella bob a little.
// INSTANCE_CUSTOM: x = gait phase (0..1), y = stride frequency (Hz; 0 =
// standing), z = brightness, w = umbrella (1) or none (0).
// Brightness ~50 % of the building lines (readability rule 5).
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;

uniform vec3 walker_color : source_color = vec3(0.643, 0.604, 0.549);
uniform float energy = 1.0;
uniform float hip_y = 0.92;
uniform float shoulder_y = 1.43;
uniform float leg_swing = 0.42;
uniform float arm_swing = 0.32;

varying float v_bright;

vec3 swing(vec3 v, float pivot_y, float a) {
	float y = v.y - pivot_y;
	float c = cos(a);
	float s = sin(a);
	return vec3(v.x, pivot_y + y * c - v.z * s, y * s + v.z * c);
}

void vertex() {
	float phase = INSTANCE_CUSTOM.x;
	float freq = INSTANCE_CUSTOM.y;
	float umb = INSTANCE_CUSTOM.w;
	v_bright = INSTANCE_CUSTOM.z;
	float moving = step(0.01, freq);
	float g = sin((TIME * freq + phase) * 6.2831853) * moving;
	float part = UV.y;
	vec3 v = VERTEX;
	if (part > 0.5 && part < 1.5) {
		v = swing(v, hip_y, g * leg_swing);
	} else if (part > 1.5 && part < 2.5) {
		v = swing(v, hip_y, -g * leg_swing);
	} else if (part > 2.5 && part < 3.5) {
		v = swing(v, shoulder_y, -g * arm_swing);
	} else if (part > 3.5 && part < 4.5) {
		v = swing(v, shoulder_y, g * arm_swing);
		v *= 1.0 - umb;
	} else if (part > 4.5 && part < 5.5) {
		v *= umb;
	} else if (part > 5.5) {
		v *= umb;
	}
	// a slight bob per step (twice per stride)
	v.y += abs(g) * 0.022;
	VERTEX = v;
}

void fragment() {
	ALBEDO = walker_color * energy * UV.x * v_bright;
}
