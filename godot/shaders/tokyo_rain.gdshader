// Rain of the Tokyo line city (docs/design/tokyo-explorer.md M2): ONE
// MultiMesh of up to 8000 thin camera-facing streaks. Nothing moves on the
// CPU: every drop's place comes from its INSTANCE_ID, it falls and wraps
// in a box around the camera here in the vertex shader. Drops light up
// against the light (the 8 lights tokyo_life.gd picks: lamps, screens,
// headlights), fade out just before the camera and in the distance, and
// thin out where the pellets lie (pellet_map), so the golden trail stays
// readable. "Regen reduzieren" lowers visible_instance_count and gain.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled, skip_vertex_transform;

uniform vec3 box = vec3(34.0, 20.0, 34.0);
uniform float fall_speed = 9.5;
uniform float drop_len = 0.55;
uniform float drop_w = 0.011;
uniform vec2 wind = vec2(0.16, 0.05); // slant: horizontal drift per meter of fall
uniform vec3 rain_color : source_color = vec3(0.784, 0.753, 0.706);
uniform float base = 0.05;
uniform float lit = 0.55;
uniform float gain = 1.0;
uniform vec4 light_pos[8]; // xyz, w = falloff
uniform vec4 light_col[8]; // rgb * strength
uniform int light_n = 0;
uniform sampler2D pellet_map : filter_linear, repeat_disable;
uniform vec2 map_size = vec2(47.0, 47.0);
uniform float cell = 2.0;
uniform float pellet_thin = 0.75; // share of drops removed over a pellet trail

varying float v_bright;
varying vec3 v_col;

float h1(float n) {
	return fract(sin(n * 12.9898 + 78.233) * 43758.5453);
}

void vertex() {
	float id = float(INSTANCE_ID);
	vec3 r = vec3(h1(id * 1.37 + 0.1), h1(id * 2.71 + 3.3), h1(id * 0.73 + 7.9));
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	float speed = fall_speed * (0.85 + 0.3 * h1(id * 5.1 + 1.7));
	float fall = TIME * speed;
	float y_lo = max(cam.y - 4.0, 0.0);
	float y = y_lo + mod(r.y * box.y - fall, box.y);
	vec2 base_xz = r.xz * box.xz + wind * fall;
	vec2 xz = cam.xz + mod(base_xz - cam.xz + box.xz * 0.5, box.xz) - box.xz * 0.5;
	vec3 c = vec3(xz.x, y, xz.y);

	// thinner over the pellet trails
	vec2 muv = (xz + cell * 0.5) / (map_size * cell);
	float pel = textureLod(pellet_map, muv, 0.0).r;
	float keep = step(pellet_thin * pel, h1(id * 9.7 + 2.1));

	vec3 axis = normalize(vec3(wind.x, -1.0, wind.y));
	vec3 to_cam = cam - c;
	float dist = length(to_cam);
	vec3 side = normalize(cross(axis, to_cam / max(dist, 0.001)));
	float w = drop_w * max(1.0, dist * 0.045);
	vec3 wp = c + axis * (VERTEX.y * drop_len) + side * (VERTEX.x * 2.0 * w);
	wp = mix(c, wp, keep);

	vec3 view = -to_cam / max(dist, 0.001);
	vec3 acc = rain_color * base;
	for (int i = 0; i < 8; i++) {
		if (i >= light_n) {
			break;
		}
		vec3 Ld = light_pos[i].xyz - c;
		float d = length(Ld);
		float back = pow(max(dot(Ld / max(d, 0.001), view), 0.0), 4.0);
		acc += light_col[i].rgb * (0.12 + back * 2.6) / (1.0 + d * d * light_pos[i].w);
	}
	float near = smoothstep(0.7, 2.6, dist);
	float far = 1.0 - smoothstep(box.x * 0.32, box.x * 0.5, dist);
	v_bright = near * far * lit;
	v_col = acc;
	VERTEX = (VIEW_MATRIX * vec4(wp, 1.0)).xyz;
	NORMAL = (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
}

void fragment() {
	float taper = sin(UV.y * 3.14159);
	ALBEDO = v_col * v_bright * taper * gain;
}
