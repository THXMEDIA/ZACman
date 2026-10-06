// Amsterdam: the little card people and bicycles of the model (meshes in
// amsterdam_figures.gd, ONE MultiMesh each, amsterdam_life.gd). Flat cut-outs
// of thin card: the faces show printed paper (colours from the palette
// texture, picked per instance), the cut edge shows kraft board. The gait is
// animated here, not on the CPU: legs and arms swing around hip and shoulder,
// a rider's feet turn on the pedals, the rim marker of each wheel goes round,
// the body bobs a little. Nothing here depends on TIME: the CPU hands in the
// gait phase (distance walked), so "Effekte reduzieren" simply stands still.
// INSTANCE_CUSTOM: x = gait phase (0..1, wrapped), y = amplitude (0 stands,
// 1 walks / rides), z = colour pick ((index + 0.5) / 8), w = 1 rider on the
// bicycle, 0 parked bicycle (the rider vanishes).
// Frequencies stay below 3 Hz (stride, wheel marker, pedals).
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D pal : source_color, filter_nearest, repeat_disable;
uniform vec3 kraft : source_color = vec3(0.663, 0.506, 0.341);
uniform bool bike = false;

varying flat float v_part;
varying flat vec4 v_inst;
varying float v_edge;
varying vec2 v_uv;

vec3 pick(float row, float idx) {
	return texture(pal, vec2((mod(idx, 8.0) + 0.5) / 8.0, (row + 0.5) / 4.0)).rgb;
}

void vertex() {
	vec4 cd = INSTANCE_CUSTOM;
	float ph = cd.x * 6.2831853;
	float amp = cd.y;
	float part = floor(COLOR.r * 16.0 + 0.5);
	float wt = COLOR.g;
	vec3 v = VERTEX;
	float s = sin(ph);
	float c = cos(ph);
	if (!bike) {
		// walking: legs and arms swing fore and aft (forward is -Z), a little
		// lift of the free foot, the body bobs twice per cycle and sways
		if (part > 0.5 && part < 1.5) {
			v.z -= wt * s * 0.24 * amp;
			v.y += wt * 0.05 * max(c, 0.0) * amp;
		} else if (part > 1.5 && part < 2.5) {
			v.z += wt * s * 0.24 * amp;
			v.y += wt * 0.05 * max(-c, 0.0) * amp;
		} else if (part > 2.5 && part < 3.5) {
			v.z += wt * s * 0.16 * amp;
		} else if (part > 3.5 && part < 4.5) {
			v.z -= wt * s * 0.16 * amp;
		}
		v.y += abs(s) * 0.025 * amp;
		v.x += v.y * s * 0.03 * amp;
	} else {
		float rider = cd.w;
		bool rider_part = part < 5.5;
		if (rider_part && rider < 0.5) {
			v = vec3(0.0); // parked: no rider (degenerate triangles)
		} else if (part > 0.5 && part < 1.5) {
			v.z += wt * 0.13 * c * amp;
			v.y += wt * 0.10 * s * amp;
		} else if (part > 1.5 && part < 2.5) {
			v.z -= wt * 0.13 * c * amp;
			v.y -= wt * 0.10 * s * amp;
		} else if (part > 8.5 && part < 10.5) {
			// rim marker: round the hub (rear z = +0.55, front z = -0.55),
			// the wheel turns twice per pedal turn
			float hz = part < 9.5 ? 0.55 : -0.55;
			float a = ph * 2.0;
			float dz = v.z - hz;
			float dy = v.y - 0.34;
			v.z = hz + dz * cos(a) - dy * sin(a);
			v.y = 0.34 + dz * sin(a) + dy * cos(a);
		}
		if (rider_part) {
			v.y += s * 0.012 * amp;
		}
		v.x += v.y * s * 0.015 * amp;
	}
	VERTEX = v;
	v_part = part;
	v_inst = cd;
	v_edge = COLOR.a;
	v_uv = UV;
}

void fragment() {
	vec3 col;
	float idx = floor(v_inst.z * 8.0);
	float part = v_part;
	if (v_edge > 0.5) {
		// cut edge of the card: kraft board, a darker core between two liners
		float t = abs(v_uv.y - 0.5) * 2.0;
		col = kraft * mix(0.72, 1.06, smoothstep(0.45, 0.9, t));
	} else if (part < 0.5) {
		col = pick(0.0, idx); // coat
	} else if (part < 2.5) {
		col = pick(0.0, idx * 3.0 + 1.0) * 0.55; // trousers
	} else if (part < 4.5) {
		col = pick(0.0, idx) * 0.88; // sleeves
	} else if (part < 5.5) {
		col = pick(1.0, idx * 7.0 + 3.0); // face
	} else if (part < 6.5) {
		col = kraft * 0.92; // base disc
	} else if (part < 7.5) {
		col = pick(2.0, idx * 5.0 + 2.0); // frame
	} else if (part < 8.5) {
		col = vec3(0.04); // tyres
	} else if (part < 10.5) {
		col = vec3(0.62, 0.58, 0.5); // rim marker
	} else {
		col = vec3(0.05); // saddle
	}
	ALBEDO = col;
	ROUGHNESS = 0.9;
	SPECULAR = 0.25;
}
