// Light streaks of the traffic on the wet asphalt (tokyo_life.gd, ONE
// MultiMesh of floor quads): for every head and tail light the stretched
// reflection on the floor, placed where the mirror image of the light meets
// the floor as seen from the camera and stretched towards the viewer (like
// the long smears on a rainy street), plus the beam pool in front of each
// car. Broken up by the same baked puddle mask as the floor.
// Instance origin = the light (y = its height); INSTANCE_CUSTOM: rgb =
// color * energy, a > 0: reflection streak (a = width in m), a < 0: beam
// pool, length -a m along the instance's -Z (the car's forward).
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled, skip_vertex_transform;

uniform sampler2D puddle_tex : filter_linear, repeat_disable;
// cell map (R = wall, MazeView.maze_tex): a reflection whose light is hidden
// behind a building from the mirror point is not drawn
uniform sampler2D maze_tex : filter_nearest, repeat_disable;
uniform vec2 maze_cells = vec2(47.0, 47.0);
uniform vec2 map_size = vec2(94.0, 94.0); // world size of the mask (m)
uniform float cell = 2.0;
uniform float streak_len = 9.0;
uniform float gain = 1.0;

varying vec3 v_col;
varying vec2 v_uv;
varying vec3 v_wp;
varying float v_kind;

float wall_at(vec2 xz) {
	vec2 c = floor((xz + cell * 0.5) / cell);
	if (c.x < 0.0 || c.y < 0.0 || c.x >= maze_cells.x || c.y >= maze_cells.y) {
		return 1.0;
	}
	return textureLod(maze_tex, (c + 0.5) / maze_cells, 0.0).r;
}

void vertex() {
	vec3 L = MODEL_MATRIX[3].xyz;
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	float a = INSTANCE_CUSTOM.a;
	v_col = INSTANCE_CUSTOM.rgb;
	v_uv = UV;
	v_kind = a;
	vec3 wp;
	if (a > 0.0) {
		// mirror point of the light on the floor seen from the camera
		float h = max(L.y, 0.05);
		float k = cam.y / max(cam.y + h, 0.01);
		vec3 P0 = cam + (vec3(L.x, -h, L.z) - cam) * k;
		vec2 dir = P0.xz - cam.xz;
		float dl = length(dir);
		dir = dl > 0.001 ? dir / dl : vec2(0.0, -1.0);
		vec2 side = vec2(-dir.y, dir.x);
		// along: -1 towards the camera (long), +1 away (short)
		float along = VERTEX.z * 2.0; // plane mesh: z in -0.5..0.5
		// long smears at eye height, short ones seen from above
		float len = along < 0.0 ? min(streak_len, dl * 0.6) * clamp(1.4 / max(cam.y, 0.1), 0.2, 1.0) : 0.8;
		vec2 xz = P0.xz + dir * along * len + side * VERTEX.x * a;
		wp = vec3(xz.x, 0.02, xz.y);
		v_col *= smoothstep(0.5, 4.0, dl);
		// occlusion: walk from the mirror point to the light over the cell map
		float blocked = 0.0;
		for (int k = 1; k <= 6; k++) {
			blocked = max(blocked, wall_at(mix(P0.xz, L.xz, float(k) / 7.0)));
		}
		blocked = max(blocked, wall_at(P0.xz));
		v_col *= 1.0 - blocked;
	} else {
		// beam pool: unit plane scaled along the car's forward (-Z)
		vec3 fwd = -normalize(MODEL_MATRIX[2].xyz);
		vec3 rt = normalize(MODEL_MATRIX[0].xyz);
		float len = -a;
		vec3 c = vec3(L.x, 0.02, L.z) + fwd * (len * 0.5 + 0.4);
		wp = c + fwd * (-VERTEX.z) * len + rt * VERTEX.x * 2.6;
		wp.y = 0.02;
	}
	v_wp = wp;
	VERTEX = (VIEW_MATRIX * vec4(wp, 1.0)).xyz;
	NORMAL = (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
}

void fragment() {
	vec2 q = v_uv * 2.0 - 1.0;
	float f;
	if (v_kind > 0.0) {
		// peak at the mirror point (q.y = 0), long tail towards the camera
		float along = q.y < 0.0 ? pow(max(1.0 + q.y, 0.0), 0.8) : pow(max(1.0 - q.y, 0.0), 2.0);
		f = exp(-q.x * q.x * 5.0) * along;
	} else {
		// beam pool: soft ellipse, brightest near the car
		float r = q.x * q.x + q.y * q.y;
		f = max(1.0 - r, 0.0) * mix(1.0, 0.35, v_uv.y);
		f *= f;
	}
	vec2 muv = (v_wp.xz + cell * 0.5) / map_size;
	float m = texture(puddle_tex, muv).r;
	float puddle = smoothstep(0.6, 0.64, m);
	ALBEDO = v_col * f * mix(0.5, 1.0, puddle) * gain;
}
