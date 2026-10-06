// Wire cars of the Tokyo line city (tokyo_figures.gd car_mesh, one
// MultiMesh, tokyo_life.gd): unshaded lines; UV.x = brightness, UV.y =
// part (0 body, 1 headlight, 2 tail light) — the colors are uniforms (no
// vertex colors: a MultiMesh without instance colors would zero them).
// INSTANCE_CUSTOM: x = visibility (0 hides the car), y = braking (tail
// lights brighter). The CPU only moves the instance transform.
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;

uniform vec3 body_color : source_color = vec3(0.95, 0.94, 0.91);
uniform vec3 head_color : source_color = vec3(1.0);
uniform vec3 tail_color : source_color = vec3(1.0, 0.165, 0.1);
uniform float body_energy = 0.9;
uniform float head_energy = 6.0;
uniform float tail_energy = 3.2;

varying float v_vis;
varying float v_brake;

void vertex() {
	v_vis = INSTANCE_CUSTOM.x;
	v_brake = INSTANCE_CUSTOM.y;
	if (v_vis <= 0.001) {
		VERTEX = vec3(0.0);
	}
}

void fragment() {
	float part = UV.y;
	vec3 c = body_color * body_energy;
	if (part > 1.5) {
		c = tail_color * tail_energy * (1.0 + 0.9 * v_brake);
	} else if (part > 0.5) {
		c = head_color * head_energy;
	}
	ALBEDO = c * UV.x * v_vis;
}
