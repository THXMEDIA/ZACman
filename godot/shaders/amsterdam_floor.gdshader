// Amsterdam: the top liner of the model's base plate (docs/design/amsterdam-explorer.md).
// The kraft photo scan with the washboard of the flutes underneath, pencil
// construction lines in front of the facades, the joint between two base
// plates taped over with packing tape, plank decks on the bridges (the Magere
// Brug painted white). Canal cells are discarded: there the lacquered water
// lies 0.85 m lower and the plate shows its corrugated cut edge (the collision
// edge). No animation.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

#include "res://shaders/amsterdam_common.gdshaderinc"

uniform float cell = 2.0;
// per cell: r = kind (0 street, 0.25 bridge, 0.5 white bridge, 0.75 house/block, 1 water),
// g = 1 for a bridge whose deck runs north-south
uniform sampler2D kind_tex : filter_nearest, repeat_disable;
uniform vec2 maze_size = vec2(49.0, 49.0);
uniform sampler2D tape_alb : source_color, filter_linear_mipmap, repeat_enable;
uniform vec3 white_paint : source_color = vec3(0.914, 0.894, 0.847);
uniform vec3 graphite : source_color = vec3(0.13, 0.13, 0.14);
uniform vec2 joint = vec2(49.0, 59.0); // world x of the N-S plate joint, world z of the E-W joint
uniform vec3 floor_albedo : source_color = vec3(0.663, 0.506, 0.341);

varying vec3 wp;
varying float vdist;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vdist = length(wp - CAMERA_POSITION_WORLD);
}

float kind_at(ivec2 c) {
	if (c.x < 0 || c.y < 0 || c.x >= int(maze_size.x) || c.y >= int(maze_size.y)) return 0.75;
	return texelFetch(kind_tex, c, 0).r;
}

bool is_house(float k) { return k > 0.62 && k < 0.88; }

void fragment() {
	vec2 p = wp.xz;
	ivec2 ci = ivec2(floor(p / cell + 0.5));
	float k = kind_at(ci);
	if (k > 0.88) discard; // canal: the water lies below
	float far = 1.0 - smoothstep(far_flat * 0.5, far_flat, vdist);
	vec3 c; vec2 nxy; float r;
	kraft_face(p, far, c, nxy, r);
	// the plate is a little lighter than the boards of the houses
	c *= 1.06;
	// washboard of the flutes inside the plate (running along z)
	float ribs = sin(p.x * 6.2831853 / pitch);
	c *= 1.0 - 0.025 * ribs * far;
	nxy.x += cos(p.x * 6.2831853 / pitch) * 0.12 * far;
	vec2 f = p / cell + 0.5 - vec2(ci); // 0..1 inside the cell
	float aa = max(fwidth(p.x), fwidth(p.y));

	if (k > 0.12 && k < 0.62) {
		// bridge deck: planks across the walking direction, joints dark
		bool white = k > 0.37;
		bool ns = texelFetch(kind_tex, ci, 0).g > 0.5; // g = 1: deck runs north-south
		float along = ns ? p.y : p.x;
		float pl = fract(along / 0.55);
		float seam = 1.0 - smoothstep(0.0, max(0.04, aa * 2.0 / 0.55), min(pl, 1.0 - pl));
		vec3 deck = white ? white_paint * (0.94 + 0.08 * vn(p * vec2(0.8, 3.0))) : c * 0.86;
		c = mix(deck, deck * 0.45, seam * 0.7 * far + seam * 0.2);
		r = white ? 0.55 : r;
	} else {
		// distance to the nearest house front in this cell (m), for the pencil
		// line and the contact shadow at the facade foot
		float dh = 99.0;
		if (is_house(kind_at(ci + ivec2(-1, 0)))) dh = min(dh, f.x * cell);
		if (is_house(kind_at(ci + ivec2(1, 0)))) dh = min(dh, (1.0 - f.x) * cell);
		if (is_house(kind_at(ci + ivec2(0, -1)))) dh = min(dh, f.y * cell);
		if (is_house(kind_at(ci + ivec2(0, 1)))) dh = min(dh, (1.0 - f.y) * cell);
		// pencil: building line 0.6 m in front of the facades, with gaps where it was erased
		float lw = 0.018 + aa * 0.7;
		float pen = 1.0 - smoothstep(lw * 0.5, lw, abs(dh - 0.6));
		float er = vn(p * 0.35);
		pen *= smoothstep(0.25, 0.4, er);
		// tick marks across it, every few metres (house widths)
		float along2 = (abs(f.x - 0.5) < abs(f.y - 0.5)) ? p.y : p.x;
		float tick = 1.0 - smoothstep(lw * 0.5, lw, abs(fract(along2 / 5.6) - 0.5) * 5.6);
		pen = max(pen, tick * (1.0 - smoothstep(0.35, 0.95, dh)) * step(0.45, dh) * smoothstep(0.25, 0.4, er));
		c = mix(c, graphite, pen * 0.75);
		r = mix(r, 0.45, pen);
		// contact shadow at the facade foot
		c *= mix(0.72, 1.0, smoothstep(0.0, 0.5, dh));
		// worn, lighter edge of the cut plate at the quay
		float dw = 99.0;
		if (kind_at(ci + ivec2(-1, 0)) > 0.88) dw = min(dw, f.x * cell);
		if (kind_at(ci + ivec2(1, 0)) > 0.88) dw = min(dw, (1.0 - f.x) * cell);
		if (kind_at(ci + ivec2(0, -1)) > 0.88) dw = min(dw, f.y * cell);
		if (kind_at(ci + ivec2(0, 1)) > 0.88) dw = min(dw, (1.0 - f.y) * cell);
		c = mix(c, c * 1.18 + 0.03, (1.0 - smoothstep(0.0, 0.06 + aa, dw)) * 0.8);
		// joint of two base plates, taped over on the streets
		float dj = min(abs(p.x - joint.x), abs(p.y - joint.y));
		bool jx = abs(p.x - joint.x) < abs(p.y - joint.y);
		float gap = 1.0 - smoothstep(0.012, 0.03 + aa, dj);
		c = mix(c, c * 0.25, gap);
		float tl = jx ? p.y : p.x;
		float tseg = fract(tl / 9.0);
		float tape = step(dj, 0.95) * step(abs(tseg - 0.5) * 9.0, 0.95);
		if (tape > 0.0) {
			vec3 tc = texture(tape_alb, vec2((jx ? (p.x - joint.x) : (p.y - joint.y)) / 1.9 + 0.5, tl / 4.0)).rgb;
			c = mix(c, c * 0.35 + tc * 0.75, 0.85);
			r = 0.3;
			SPECULAR = 0.7;
		}
	}
	NORMAL_MAP = vec3(nxy * 0.5 + 0.5, 1.0);
	ALBEDO = c;
	ROUGHNESS = r;
}
